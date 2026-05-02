import os
import tempfile
from dataclasses import dataclass
from typing import Any
from time import perf_counter
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Request, UploadFile, WebSocket
from fastapi import FastAPI, status
from openai import OpenAI

from agent_gateway import agent_gateway
from auth_store import (
    AuthEmailCode,
    AuthUser,
    authenticate_user,
    consume_email_code,
    count_users,
    create_auth_session,
    create_email_code,
    create_user,
    get_user_by_id,
    get_user_by_email,
    init_auth_db,
    mark_user_email_verified,
    revoke_user_sessions,
    resolve_auth_session,
    revoke_auth_session,
    update_user_password,
)
from api.schemas import (
    AppSettingEntryResponse,
    AppSettingsUpdateRequest,
    AuthForgotPasswordRequest,
    AuthLoginRequest,
    AuthRegisterRequest,
    AuthResetPasswordRequest,
    AuthSessionResponse,
    AuthStatusResponse,
    AuthUserResponse,
    AuthVerifyEmailRequest,
    ChatRequest,
    ChatResponse,
    HomeAssistantDeviceAliasUpdateRequest,
    HomeAssistantDeviceResponse,
    HomeAssistantStatusResponse,
    MemoryEntryResponse,
    MemoryUpdateRequest,
    RegisteredDeviceResponse,
    RegisteredDeviceUpdateRequest,
    RoutinePayload,
    RoutineResponse,
    RoutineRunResponse,
    SessionResponse,
    VoiceTurnResponse,
)
from assistant.service import AssistantService
from audio.tts import synthesize_speech
from config import OPENAI_TIMEOUT_SECONDS, OPENAI_TRANSCRIPTION_MODEL, settings
from device_registry import get_device, init_device_registry, list_registered_devices, update_device
from email_service import is_email_enabled, send_password_reset_email, send_registration_email
from home_assistant.service import connection_status
from home_assistant.devices import (
    clear_devices,
    delete_device,
    init_devices_db,
    list_devices,
    sync_devices,
    update_device_alias,
)
from llm.ollama import LLMUnavailableError
from logging_utils import configure_logging, get_logger, log_event
from memory.user_memory import (
    clear_memory,
    delete_memory_entry,
    list_memory_entries,
    update_memory_entry,
)
from routines.service import (
    create_routine,
    delete_routine,
    init_routines_db,
    list_routines,
    run_routine,
    update_routine,
)
from settings_store import clear_settings, init_settings_db, list_settings, update_settings

configure_logging(settings.log_level)
logger = get_logger(__name__)
client = OpenAI(timeout=OPENAI_TIMEOUT_SECONDS)
assistant = AssistantService(enable_desktop_tools=False)
router = APIRouter()
init_auth_db()
init_routines_db()
init_devices_db()
init_settings_db()
init_device_registry()

app = FastAPI(
    title='Assistente Codex API',
    version='1.1.0',
    description='API HTTP para ligar o assistente a aplicacoes Windows, Android e iPhone.',
)


@dataclass(frozen=True)
class AuthContext:
    user: AuthUser | None
    access_token: str | None = None
    uses_legacy_api_token: bool = False

    @property
    def user_id(self) -> str | None:
        return self.user.id if self.user is not None else None


def _auth_error() -> HTTPException:
    return HTTPException(
        status_code=401,
        detail='Autenticacao obrigatoria.',
        headers={'WWW-Authenticate': 'Bearer'},
    )


def _parse_bearer_token(authorization: str | None) -> str:
    raw = (authorization or '').strip()
    if not raw.lower().startswith('bearer '):
        return ''
    return raw[7:].strip()


def get_auth_context(authorization: str | None = Header(default=None)) -> AuthContext:
    token = _parse_bearer_token(authorization)

    if settings.api_auth_enabled and token == settings.api_token:
        return AuthContext(user=None, access_token=token, uses_legacy_api_token=True)

    if token:
        resolved = resolve_auth_session(token)
        if resolved is not None:
            _, user = resolved
            return AuthContext(user=user, access_token=token, uses_legacy_api_token=False)

    if count_users() == 0 and not settings.api_auth_enabled:
        raise HTTPException(
            status_code=401,
            detail='Ainda nao existe nenhuma conta. Regista-te primeiro.',
            headers={'WWW-Authenticate': 'Bearer'},
        )

    raise _auth_error()


def require_agent_token(websocket: WebSocket) -> None:
    if not settings.api_auth_enabled:
        return

    token = (websocket.query_params.get('token') or '').strip()
    if token != settings.api_token:
        raise HTTPException(
            status_code=status.HTTP_1008_POLICY_VIOLATION,
            detail='Token do agente invalido.',
        )


@app.middleware('http')
async def request_logging_middleware(request: Request, call_next):
    request_id = request.headers.get('x-request-id') or str(uuid4())
    started = perf_counter()

    try:
        response = await call_next(request)
    except Exception as exc:
        duration_ms = round((perf_counter() - started) * 1000, 2)
        log_event(
            logger,
            40,
            'http_request_failed',
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            duration_ms=duration_ms,
            error=str(exc),
        )
        raise

    duration_ms = round((perf_counter() - started) * 1000, 2)
    response.headers['X-Request-ID'] = request_id
    log_event(
        logger,
        20 if response.status_code < 400 else 30,
        'http_request',
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=duration_ms,
        client=(request.client.host if request.client else None),
    )
    return response


@app.get('/health')
def healthcheck():
    return {
        'status': 'ok',
        'auth_enabled': settings.api_auth_enabled,
        'user_count': count_users(),
        'email_enabled': is_email_enabled(),
    }


def _user_response_payload(user: AuthUser) -> dict[str, Any]:
    return {
        'id': user.id,
        'email': user.email,
        'display_name': user.display_name,
        'created_at': user.created_at,
        'email_verified_at': user.email_verified_at,
        'email_verified': user.email_verified,
    }


def _session_response_payload(user: AuthUser, access_token: str) -> dict[str, Any]:
    return {
        'access_token': access_token,
        'token_type': 'bearer',
        'user': _user_response_payload(user),
    }


def _email_delivery_response(*, email: str, message: str, email_sent: bool, verification_required: bool) -> dict[str, Any]:
    return {
        'ok': True,
        'message': message,
        'email': email,
        'email_sent': email_sent,
        'verification_required': verification_required,
    }


def _send_registration_code(user: AuthUser) -> AuthEmailCode:
    email_code = create_email_code(user_id=user.id, email=user.email, purpose='verify_email')
    send_registration_email(
        to_email=user.email,
        display_name=user.display_name,
        code=email_code.code,
    )
    return email_code


def _send_password_reset_code(user: AuthUser) -> AuthEmailCode:
    email_code = create_email_code(user_id=user.id, email=user.email, purpose='reset_password')
    send_password_reset_email(
        to_email=user.email,
        display_name=user.display_name,
        code=email_code.code,
    )
    return email_code


@app.post('/auth/register', response_model=AuthStatusResponse)
def register_auth_user(payload: AuthRegisterRequest):
    try:
        user = create_user(
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
        )
        try:
            _send_registration_code(user)
            return _email_delivery_response(
                email=user.email,
                message='Conta criada. Enviamos um codigo de verificacao para o teu email.',
                email_sent=True,
                verification_required=True,
            )
        except Exception as exc:
            return _email_delivery_response(
                email=user.email,
                message=f'Conta criada, mas o email nao foi enviado: {exc}',
                email_sent=False,
                verification_required=True,
            )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post('/auth/login', response_model=AuthSessionResponse)
def login_auth_user(payload: AuthLoginRequest):
    user = authenticate_user(payload.email, payload.password)
    if user is None:
        raise HTTPException(status_code=401, detail='Email ou palavra-passe invalidos.')
    if not user.email_verified:
        raise HTTPException(
            status_code=403,
            detail='Precisas de confirmar o email antes de entrar.',
        )
    session = create_auth_session(user.id)
    return _session_response_payload(user, session.token)


@app.post('/auth/verify-email', response_model=AuthSessionResponse)
def verify_email(payload: AuthVerifyEmailRequest):
    user = consume_email_code(
        email=payload.email,
        purpose='verify_email',
        code=payload.code,
    )
    if user is None:
        raise HTTPException(status_code=400, detail='Codigo de verificacao invalido ou expirado.')

    verified_user = mark_user_email_verified(user.id)
    if verified_user is None:
        raise HTTPException(status_code=404, detail='Conta nao encontrada.')

    session = create_auth_session(verified_user.id)
    return _session_response_payload(verified_user, session.token)


@app.post('/auth/resend-verification', response_model=AuthStatusResponse)
def resend_verification_email(payload: AuthForgotPasswordRequest):
    user = get_user_by_email(payload.email)
    if user is None:
        return _email_delivery_response(
            email=payload.email,
            message='Se existir uma conta com esse email, enviamos um novo codigo de verificacao.',
            email_sent=False,
            verification_required=True,
        )
    if user.email_verified:
        return _email_delivery_response(
            email=user.email,
            message='Esse email ja esta confirmado.',
            email_sent=False,
            verification_required=False,
        )

    try:
        _send_registration_code(user)
        return _email_delivery_response(
            email=user.email,
            message='Enviamos um novo codigo de verificacao para o teu email.',
            email_sent=True,
            verification_required=True,
        )
    except Exception as exc:
        return _email_delivery_response(
            email=user.email,
            message=f'Nao consegui enviar o email de verificacao: {exc}',
            email_sent=False,
            verification_required=True,
        )


@app.post('/auth/forgot-password', response_model=AuthStatusResponse)
def forgot_password(payload: AuthForgotPasswordRequest):
    user = get_user_by_email(payload.email)
    if user is None:
        return _email_delivery_response(
            email=payload.email,
            message='Se existir uma conta com esse email, enviamos um codigo para recuperar a palavra-passe.',
            email_sent=False,
            verification_required=False,
        )

    try:
        _send_password_reset_code(user)
        return _email_delivery_response(
            email=user.email,
            message='Enviamos um codigo para recuperares a palavra-passe.',
            email_sent=True,
            verification_required=False,
        )
    except Exception as exc:
        return _email_delivery_response(
            email=user.email,
            message=f'Nao consegui enviar o email de recuperacao: {exc}',
            email_sent=False,
            verification_required=False,
        )


@app.post('/auth/reset-password', response_model=AuthStatusResponse)
def reset_password(payload: AuthResetPasswordRequest):
    user = consume_email_code(
        email=payload.email,
        purpose='reset_password',
        code=payload.code,
    )
    if user is None:
        raise HTTPException(status_code=400, detail='Codigo de recuperacao invalido ou expirado.')

    updated_user = update_user_password(user.id, payload.new_password)
    if updated_user is None:
        raise HTTPException(status_code=404, detail='Conta nao encontrada.')
    revoke_user_sessions(updated_user.id)

    return _email_delivery_response(
        email=updated_user.email,
        message='A tua palavra-passe foi atualizada. Ja podes entrar com a nova palavra-passe.',
        email_sent=False,
        verification_required=False,
    )


@app.get('/auth/me', response_model=AuthUserResponse)
def auth_me(auth: AuthContext = Depends(get_auth_context)):
    if auth.user is None:
        raise _auth_error()
    user = get_user_by_id(auth.user.id)
    if user is None:
        raise _auth_error()
    return _user_response_payload(user)


@app.post('/auth/logout')
def auth_logout(auth: AuthContext = Depends(get_auth_context)):
    if auth.access_token and not auth.uses_legacy_api_token:
        revoke_auth_session(auth.access_token)
    return {'ok': True}


async def _dispatch_client_action_to_agent(
    response: dict[str, Any],
) -> dict[str, Any]:
    client_action = response.get('client_action')
    if not isinstance(client_action, dict):
        return response

    action_type = (client_action.get('type') or '').strip()
    action_name = ''
    arguments: dict[str, Any] = {}

    if action_type == 'pc_action':
        action_name = (client_action.get('action') or '').strip()
        raw_arguments = client_action.get('arguments')
        if isinstance(raw_arguments, dict):
            arguments = raw_arguments
    elif action_type == 'open_app':
        action_name = 'open_app'
        app_name = (client_action.get('app_name') or '').strip()
        if app_name:
            arguments['app_name'] = app_name
    elif action_type == 'open_url':
        action_name = 'open_url'
        url = (client_action.get('url') or '').strip()
        if url:
            arguments['url'] = url

    if not action_name:
        return response

    target_device_id = None
    raw_target = client_action.get('target_device_id')
    if isinstance(raw_target, str) and raw_target.strip():
        target_device_id = raw_target.strip()

    dispatch_result = await agent_gateway.dispatch_action(
        action_name,
        arguments=arguments,
        target_device_id=target_device_id,
    )
    if not dispatch_result.get('ok'):
        return response

    response['client_action'] = None
    response['tool_result'] = {
        'tool_name': action_name,
        'ok': True,
        'data': dispatch_result,
    }
    return response


@app.post('/sessions', response_model=SessionResponse)
def create_session(auth: AuthContext = Depends(get_auth_context)):
    return assistant.create_session(user_id=auth.user_id)


@app.delete('/sessions/{session_id}')
def delete_session(session_id: str, auth: AuthContext = Depends(get_auth_context)):
    deleted = assistant.delete_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail='Sessao nao encontrada.')
    return {'deleted': True}


@app.post('/chat', response_model=ChatResponse)
async def chat(payload: ChatRequest, auth: AuthContext = Depends(get_auth_context)):
    try:
        response = assistant.chat(payload.session_id, payload.message)
        return await _dispatch_client_action_to_agent(response)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get('/memory', response_model=list[MemoryEntryResponse])
def get_memory_entries(auth: AuthContext = Depends(get_auth_context)):
    return list_memory_entries(user_id=auth.user_id)


@app.put('/memory/{memory_key}', response_model=MemoryEntryResponse)
def put_memory_entry(memory_key: str, payload: MemoryUpdateRequest, auth: AuthContext = Depends(get_auth_context)):
    try:
        return update_memory_entry(memory_key, payload.value, user_id=auth.user_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f'Memoria nao encontrada: {memory_key}') from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.delete('/memory/{memory_key}')
def remove_memory_entry(memory_key: str, auth: AuthContext = Depends(get_auth_context)):
    deleted = delete_memory_entry(memory_key, user_id=auth.user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Memoria nao encontrada: {memory_key}')
    return {'deleted': True}


@app.delete('/memory')
def remove_all_memory(auth: AuthContext = Depends(get_auth_context)):
    deleted_count = clear_memory(user_id=auth.user_id)
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/settings',
    response_model=list[AppSettingEntryResponse],
)
def get_app_settings(auth: AuthContext = Depends(get_auth_context)):
    return list_settings(user_id=auth.user_id)


@app.put(
    '/settings',
    response_model=list[AppSettingEntryResponse],
)
def put_app_settings(payload: AppSettingsUpdateRequest, auth: AuthContext = Depends(get_auth_context)):
    return update_settings(payload.model_dump(), user_id=auth.user_id)


@app.delete('/settings')
def remove_app_settings(auth: AuthContext = Depends(get_auth_context)):
    deleted_count = clear_settings(user_id=auth.user_id)
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/devices',
    response_model=list[RegisteredDeviceResponse],
)
def get_registered_devices(auth: AuthContext = Depends(get_auth_context)):
    return list_registered_devices(user_id=auth.user_id)


@app.get(
    '/devices/{device_id}',
    response_model=RegisteredDeviceResponse,
)
def get_registered_device(device_id: str, auth: AuthContext = Depends(get_auth_context)):
    device = get_device(device_id, user_id=auth.user_id)
    if device is None:
        raise HTTPException(status_code=404, detail=f'Dispositivo nao encontrado: {device_id}')
    return device


@app.put(
    '/devices/{device_id}',
    response_model=RegisteredDeviceResponse,
)
def put_registered_device(device_id: str, payload: RegisteredDeviceUpdateRequest, auth: AuthContext = Depends(get_auth_context)):
    try:
        updates = payload.model_dump(exclude_none=True)
        return update_device(device_id, updates, user_id=auth.user_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get(
    '/home-assistant/status',
    response_model=HomeAssistantStatusResponse,
)
def get_home_assistant_status(auth: AuthContext = Depends(get_auth_context)):
    return connection_status(user_id=auth.user_id)


@app.post(
    '/home-assistant/devices/sync',
    response_model=list[HomeAssistantDeviceResponse],
)
def sync_home_assistant_devices(auth: AuthContext = Depends(get_auth_context)):
    status_snapshot = connection_status(user_id=auth.user_id)
    if not status_snapshot.get('enabled', True):
        raise HTTPException(status_code=409, detail=status_snapshot['message'])
    if not status_snapshot.get('configured', False):
        raise HTTPException(status_code=400, detail=status_snapshot['message'])
    if not status_snapshot.get('connected', False):
        raise HTTPException(status_code=502, detail=status_snapshot['message'])
    return sync_devices(user_id=auth.user_id)


@app.get(
    '/home-assistant/devices',
    response_model=list[HomeAssistantDeviceResponse],
)
def get_home_assistant_devices(auth: AuthContext = Depends(get_auth_context)):
    return list_devices(user_id=auth.user_id)


@app.put(
    '/home-assistant/devices/{entity_id}/alias',
    response_model=HomeAssistantDeviceResponse,
)
def put_home_assistant_device_alias(
    entity_id: str,
    payload: HomeAssistantDeviceAliasUpdateRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    try:
        return update_device_alias(entity_id, payload.alias, user_id=auth.user_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.delete(
    '/home-assistant/devices/{entity_id}',
)
def remove_home_assistant_device(entity_id: str, auth: AuthContext = Depends(get_auth_context)):
    deleted = delete_device(entity_id, user_id=auth.user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Dispositivo nao encontrado: {entity_id}')
    return {'deleted': True}


@app.delete(
    '/home-assistant/devices',
)
def remove_all_home_assistant_devices(auth: AuthContext = Depends(get_auth_context)):
    deleted_count = clear_devices(user_id=auth.user_id)
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/routines',
    response_model=list[RoutineResponse],
)
def get_routines(auth: AuthContext = Depends(get_auth_context)):
    return list_routines(user_id=auth.user_id)


@app.post(
    '/routines',
    response_model=RoutineResponse,
)
def post_routine(payload: RoutinePayload, auth: AuthContext = Depends(get_auth_context)):
    try:
        return create_routine(
            name=payload.name,
            description=payload.description,
            trigger_text=payload.trigger_text,
            actions=[action.model_dump(exclude_none=True) for action in payload.actions],
            enabled=payload.enabled,
            user_id=auth.user_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.put(
    '/routines/{routine_id}',
    response_model=RoutineResponse,
)
def put_routine(routine_id: str, payload: RoutinePayload, auth: AuthContext = Depends(get_auth_context)):
    try:
        return update_routine(
            routine_id,
            name=payload.name,
            description=payload.description,
            trigger_text=payload.trigger_text,
            actions=[action.model_dump(exclude_none=True) for action in payload.actions],
            enabled=payload.enabled,
            user_id=auth.user_id,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.delete('/routines/{routine_id}')
def remove_routine(routine_id: str, auth: AuthContext = Depends(get_auth_context)):
    deleted = delete_routine(routine_id, user_id=auth.user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Rotina nao encontrada: {routine_id}')
    return {'deleted': True}


@app.post(
    '/routines/{routine_id}/run',
    response_model=RoutineRunResponse,
)
def run_routine_endpoint(routine_id: str, auth: AuthContext = Depends(get_auth_context)):
    try:
        return run_routine(routine_id, user_id=auth.user_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _transcribe_file(audio_path: str) -> str:
    with open(audio_path, 'rb') as audio_file:
        transcript = client.audio.transcriptions.create(
            model=OPENAI_TRANSCRIPTION_MODEL,
            file=audio_file,
            language='pt',
            temperature=0,
            prompt='Transcreve apenas fala real em portugues de Portugal. Se nao houver fala, devolve vazio.',
        )

    if hasattr(transcript, 'text'):
        text = transcript.text.strip()
    else:
        text = str(transcript).strip()

    log_event(logger, 20, 'transcription_completed', transcript_length=len(text))
    return text


def _delete_temp_file(path: str | None):
    if path and os.path.exists(path):
        os.remove(path)


@app.post('/transcribe')
async def transcribe(file: UploadFile = File(...), auth: AuthContext = Depends(get_auth_context)):
    tmp_path = None

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name

        return _transcribe_file(tmp_path)
    except Exception as exc:
        log_event(logger, 40, 'transcribe_failed', error=str(exc))
        raise HTTPException(status_code=503, detail=f'Falha ao transcrever audio: {exc}') from exc
    finally:
        _delete_temp_file(tmp_path)


@app.post('/voice/turn', response_model=VoiceTurnResponse)
async def voice_turn(
    session_id: str = Form(...),
    file: UploadFile = File(...),
    platform: str | None = Form(None),
    locale: str | None = Form(None),
    auth: AuthContext = Depends(get_auth_context),
):
    tmp_path = None

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name

        transcript = _transcribe_file(tmp_path)

        if not transcript:
            return {
                'session_id': session_id,
                'transcript': '',
                'reply': 'Nao percebi o que disseste.',
                'tool_result': None,
                'desktop_tools_enabled': assistant.enable_desktop_tools,
                'client_action': None,
                'platform': platform,
                'locale': locale,
            }

        response = assistant.chat(session_id, transcript)
        response = await _dispatch_client_action_to_agent(response)
        response['transcript'] = transcript
        response['platform'] = platform
        response['locale'] = locale
        return response
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        log_event(logger, 40, 'voice_turn_failed', session_id=session_id, error=str(exc))
        raise HTTPException(status_code=503, detail=f'Falha ao processar turno de voz: {exc}') from exc
    finally:
        _delete_temp_file(tmp_path)


@router.post('/tts')
async def tts_endpoint(data: dict, auth: AuthContext = Depends(get_auth_context)):
    text = (data.get('text') or '').strip()
    if not text:
        raise HTTPException(status_code=400, detail='Texto vazio para TTS.')

    try:
        audio = synthesize_speech(text)
        return {'audio': audio}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        log_event(logger, 40, 'tts_failed', error=str(exc))
        raise HTTPException(status_code=503, detail=f'Falha ao sintetizar audio: {exc}') from exc


app.include_router(router)


@app.websocket('/agents/ws')
async def agents_websocket(websocket: WebSocket):
    if settings.api_auth_enabled:
        token = (websocket.query_params.get('token') or '').strip()
        if token != settings.api_token:
            await websocket.close(code=1008, reason='Token do agente invalido.')
            return

    await agent_gateway.handle_connection(websocket)
