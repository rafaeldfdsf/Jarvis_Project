import os
import tempfile
from typing import Any
from time import perf_counter
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Request, UploadFile, WebSocket
from fastapi import FastAPI, status
from openai import OpenAI

from agent_gateway import agent_gateway
from api.schemas import (
    AppSettingEntryResponse,
    AppSettingsUpdateRequest,
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
init_routines_db()
init_devices_db()
init_settings_db()
init_device_registry()

app = FastAPI(
    title='Assistente Codex API',
    version='1.1.0',
    description='API HTTP para ligar o assistente a aplicacoes Windows, Android e iPhone.',
)


def require_api_token(authorization: str | None = Header(default=None)) -> None:
    if not settings.api_auth_enabled:
        return

    expected = f'Bearer {settings.api_token}'
    if authorization != expected:
        raise HTTPException(
            status_code=401,
            detail='Token Bearer em falta ou invalido.',
            headers={'WWW-Authenticate': 'Bearer'},
        )


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
    }


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


@app.post('/sessions', response_model=SessionResponse, dependencies=[Depends(require_api_token)])
def create_session():
    return assistant.create_session()


@app.delete('/sessions/{session_id}', dependencies=[Depends(require_api_token)])
def delete_session(session_id: str):
    deleted = assistant.delete_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail='Sessao nao encontrada.')
    return {'deleted': True}


@app.post('/chat', response_model=ChatResponse, dependencies=[Depends(require_api_token)])
async def chat(payload: ChatRequest):
    try:
        response = assistant.chat(payload.session_id, payload.message)
        return await _dispatch_client_action_to_agent(response)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get('/memory', response_model=list[MemoryEntryResponse], dependencies=[Depends(require_api_token)])
def get_memory_entries():
    return list_memory_entries()


@app.put('/memory/{memory_key}', response_model=MemoryEntryResponse, dependencies=[Depends(require_api_token)])
def put_memory_entry(memory_key: str, payload: MemoryUpdateRequest):
    try:
        return update_memory_entry(memory_key, payload.value)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f'Memoria nao encontrada: {memory_key}') from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.delete('/memory/{memory_key}', dependencies=[Depends(require_api_token)])
def remove_memory_entry(memory_key: str):
    deleted = delete_memory_entry(memory_key)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Memoria nao encontrada: {memory_key}')
    return {'deleted': True}


@app.delete('/memory', dependencies=[Depends(require_api_token)])
def remove_all_memory():
    deleted_count = clear_memory()
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/settings',
    response_model=list[AppSettingEntryResponse],
    dependencies=[Depends(require_api_token)],
)
def get_app_settings():
    return list_settings()


@app.put(
    '/settings',
    response_model=list[AppSettingEntryResponse],
    dependencies=[Depends(require_api_token)],
)
def put_app_settings(payload: AppSettingsUpdateRequest):
    return update_settings(payload.model_dump())


@app.delete('/settings', dependencies=[Depends(require_api_token)])
def remove_app_settings():
    deleted_count = clear_settings()
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/devices',
    response_model=list[RegisteredDeviceResponse],
    dependencies=[Depends(require_api_token)],
)
def get_registered_devices():
    return list_registered_devices()


@app.get(
    '/devices/{device_id}',
    response_model=RegisteredDeviceResponse,
    dependencies=[Depends(require_api_token)],
)
def get_registered_device(device_id: str):
    device = get_device(device_id)
    if device is None:
        raise HTTPException(status_code=404, detail=f'Dispositivo nao encontrado: {device_id}')
    return device


@app.put(
    '/devices/{device_id}',
    response_model=RegisteredDeviceResponse,
    dependencies=[Depends(require_api_token)],
)
def put_registered_device(device_id: str, payload: RegisteredDeviceUpdateRequest):
    try:
        updates = payload.model_dump(exclude_none=True)
        return update_device(device_id, updates)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get(
    '/home-assistant/status',
    response_model=HomeAssistantStatusResponse,
    dependencies=[Depends(require_api_token)],
)
def get_home_assistant_status():
    return connection_status()


@app.post(
    '/home-assistant/devices/sync',
    response_model=list[HomeAssistantDeviceResponse],
    dependencies=[Depends(require_api_token)],
)
def sync_home_assistant_devices():
    status_snapshot = connection_status()
    if not status_snapshot.get('enabled', True):
        raise HTTPException(status_code=409, detail=status_snapshot['message'])
    if not status_snapshot.get('configured', False):
        raise HTTPException(status_code=400, detail=status_snapshot['message'])
    if not status_snapshot.get('connected', False):
        raise HTTPException(status_code=502, detail=status_snapshot['message'])
    return sync_devices()


@app.get(
    '/home-assistant/devices',
    response_model=list[HomeAssistantDeviceResponse],
    dependencies=[Depends(require_api_token)],
)
def get_home_assistant_devices():
    return list_devices()


@app.put(
    '/home-assistant/devices/{entity_id}/alias',
    response_model=HomeAssistantDeviceResponse,
    dependencies=[Depends(require_api_token)],
)
def put_home_assistant_device_alias(
    entity_id: str,
    payload: HomeAssistantDeviceAliasUpdateRequest,
):
    try:
        return update_device_alias(entity_id, payload.alias)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.delete(
    '/home-assistant/devices/{entity_id}',
    dependencies=[Depends(require_api_token)],
)
def remove_home_assistant_device(entity_id: str):
    deleted = delete_device(entity_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Dispositivo nao encontrado: {entity_id}')
    return {'deleted': True}


@app.delete(
    '/home-assistant/devices',
    dependencies=[Depends(require_api_token)],
)
def remove_all_home_assistant_devices():
    deleted_count = clear_devices()
    return {'deleted': True, 'count': deleted_count}


@app.get(
    '/routines',
    response_model=list[RoutineResponse],
    dependencies=[Depends(require_api_token)],
)
def get_routines():
    return list_routines()


@app.post(
    '/routines',
    response_model=RoutineResponse,
    dependencies=[Depends(require_api_token)],
)
def post_routine(payload: RoutinePayload):
    try:
        return create_routine(
            name=payload.name,
            description=payload.description,
            trigger_text=payload.trigger_text,
            actions=[action.model_dump(exclude_none=True) for action in payload.actions],
            enabled=payload.enabled,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.put(
    '/routines/{routine_id}',
    response_model=RoutineResponse,
    dependencies=[Depends(require_api_token)],
)
def put_routine(routine_id: str, payload: RoutinePayload):
    try:
        return update_routine(
            routine_id,
            name=payload.name,
            description=payload.description,
            trigger_text=payload.trigger_text,
            actions=[action.model_dump(exclude_none=True) for action in payload.actions],
            enabled=payload.enabled,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.delete('/routines/{routine_id}', dependencies=[Depends(require_api_token)])
def remove_routine(routine_id: str):
    deleted = delete_routine(routine_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f'Rotina nao encontrada: {routine_id}')
    return {'deleted': True}


@app.post(
    '/routines/{routine_id}/run',
    response_model=RoutineRunResponse,
    dependencies=[Depends(require_api_token)],
)
def run_routine_endpoint(routine_id: str):
    try:
        return run_routine(routine_id)
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


@app.post('/transcribe', dependencies=[Depends(require_api_token)])
async def transcribe(file: UploadFile = File(...)):
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


@app.post('/voice/turn', response_model=VoiceTurnResponse, dependencies=[Depends(require_api_token)])
async def voice_turn(
    session_id: str = Form(...),
    file: UploadFile = File(...),
    platform: str | None = Form(None),
    locale: str | None = Form(None),
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
async def tts_endpoint(data: dict):
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


app.include_router(router, dependencies=[Depends(require_api_token)])


@app.websocket('/agents/ws')
async def agents_websocket(websocket: WebSocket):
    if settings.api_auth_enabled:
        token = (websocket.query_params.get('token') or '').strip()
        if token != settings.api_token:
            await websocket.close(code=1008, reason='Token do agente invalido.')
            return

    await agent_gateway.handle_connection(websocket)
