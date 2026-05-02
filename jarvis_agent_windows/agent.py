from __future__ import annotations

import base64
import io
import json
import os
import queue
import re
import subprocess
import threading
import time
import unicodedata
import urllib.parse
import webbrowser
from datetime import datetime, timezone
from typing import Any

import psutil
import pyautogui
import pygetwindow as gw
from fastapi import Body, FastAPI, Query

app = FastAPI()

KNOWN_APPS = {
    'calculadora': 'calc',
    'bloco de notas': 'notepad',
    'notepad': 'notepad',
    'explorador': 'explorer',
    'explorer': 'explorer',
    'cmd': 'cmd',
    'prompt de comandos': 'cmd',
    'powershell': 'powershell',
    'terminal': 'wt',
    'google chrome': 'chrome',
    'chrome': 'chrome',
    'microsoft edge': 'msedge',
    'edge': 'msedge',
    'firefox': 'firefox',
    'brave': 'brave',
    'spotify': 'spotify',
    'discord': 'discord',
    'steam': 'steam',
    'teams': 'ms-teams',
    'vscode': 'code',
    'visual studio code': 'code',
    'word': 'winword',
    'excel': 'excel',
}

KNOWN_WEBSITES = {
    'youtube': 'https://www.youtube.com',
    'google': 'https://www.google.com',
    'gmail': 'https://mail.google.com',
}

PROTECTED_WINDOW_TOKENS = ('jarvis', 'codex', 'flutter')

WAKE_WORD_ENGINE = 'windows_agent_local_fallback'
DEFAULT_WAKE_WORD_PHRASE = 'jarvis'
DEFAULT_WAKE_WORD_SENSITIVITY = 40
SAMPLE_RATE = 16000
BLOCKSIZE = 1600
MAX_BUFFER_CHUNKS = 8
MIN_AUDIO_SECONDS = 0.35

_WAKE_WORD_EVENTS: 'queue.Queue[dict[str, Any]]' = queue.Queue(maxsize=32)
_WAKE_WORD_LOCK = threading.Lock()
_WAKE_WORD_STOP = threading.Event()
_WAKE_WORD_THREAD: threading.Thread | None = None
_WAKE_WORD_RUNTIME: dict[str, Any] | None = None
_WAKE_WORD_RUNTIME_ERROR: str | None = None
_CURRENT_WAKE_WORD_PHRASE = DEFAULT_WAKE_WORD_PHRASE
_CURRENT_WAKE_WORD_SENSITIVITY = DEFAULT_WAKE_WORD_SENSITIVITY

AGENT_DEVICE_ID = (os.getenv('JARVIS_DEVICE_ID') or os.getenv('COMPUTERNAME') or 'pc-windows-01').strip()
AGENT_DEVICE_NAME = (os.getenv('JARVIS_DEVICE_NAME') or os.getenv('COMPUTERNAME') or AGENT_DEVICE_ID).strip()
AGENT_DEVICE_TYPE = (os.getenv('JARVIS_DEVICE_TYPE') or 'windows').strip()
AGENT_PLATFORM = (os.getenv('JARVIS_DEVICE_PLATFORM') or 'windows').strip()
AGENT_LOCATION = (os.getenv('JARVIS_DEVICE_LOCATION') or '').strip()
CORE_WS_URL = (os.getenv('JARVIS_CORE_WS_URL') or 'ws://127.0.0.1:8000/agents/ws').strip()
CORE_API_TOKEN = (os.getenv('JARVIS_API_TOKEN') or '').strip()
AUTO_CONNECT_CORE = (os.getenv('JARVIS_AGENT_AUTO_CONNECT') or 'true').strip().lower() not in {'0', 'false', 'no', 'off'}
AGENT_CAPABILITIES = [
    'desktop.control',
    'screen.capture',
    'wake_word.local',
]

_CORE_LOCK = threading.Lock()
_CORE_STOP = threading.Event()
_CORE_THREAD: threading.Thread | None = None
_CORE_CONNECTED = False
_CORE_LAST_ERROR = ''
_CORE_LAST_EVENT_AT = ''


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _publish_event(event_type: str, **payload: Any) -> None:
    event = {
        'type': event_type,
        'timestamp': _utc_now_iso(),
        **payload,
    }

    try:
        _WAKE_WORD_EVENTS.put_nowait(event)
    except queue.Full:
        try:
            _WAKE_WORD_EVENTS.get_nowait()
        except queue.Empty:
            pass

        try:
            _WAKE_WORD_EVENTS.put_nowait(event)
        except queue.Full:
            pass

    _set_core_last_event()


def _is_wake_word_running() -> bool:
    return _WAKE_WORD_THREAD is not None and _WAKE_WORD_THREAD.is_alive()


def _set_core_last_event() -> None:
    global _CORE_LAST_EVENT_AT
    _CORE_LAST_EVENT_AT = _utc_now_iso()


def _set_core_connection_state(connected: bool, *, error: str = '') -> None:
    global _CORE_CONNECTED, _CORE_LAST_ERROR
    with _CORE_LOCK:
        _CORE_CONNECTED = connected
        _CORE_LAST_ERROR = error.strip()
        if connected:
            _set_core_last_event()


def _is_core_connected() -> bool:
    with _CORE_LOCK:
        return _CORE_CONNECTED


def _core_ws_url() -> str:
    if not CORE_API_TOKEN:
        return CORE_WS_URL

    separator = '&' if '?' in CORE_WS_URL else '?'
    return f'{CORE_WS_URL}{separator}token={urllib.parse.quote_plus(CORE_API_TOKEN)}'


def _agent_hello_payload() -> dict[str, Any]:
    return {
        'type': 'agent.hello',
        'device_id': AGENT_DEVICE_ID,
        'device_name': AGENT_DEVICE_NAME,
        'device_type': AGENT_DEVICE_TYPE,
        'platform': AGENT_PLATFORM,
        'location': AGENT_LOCATION,
        'agent_version': '2.0.0',
        'capabilities': list(AGENT_CAPABILITIES),
        'metadata': {
            'wake_word_engine': WAKE_WORD_ENGINE,
        },
    }


def _run_core_command(message: dict[str, Any]) -> dict[str, Any] | None:
    message_type = (message.get('type') or '').strip()

    if message_type == 'core.command.run_action':
        request_id = (message.get('request_id') or '').strip()
        action_payload = message.get('action')
        if not isinstance(action_payload, dict):
            return {
                'type': 'agent.result.action_completed',
                'request_id': request_id,
                'device_id': AGENT_DEVICE_ID,
                'ok': False,
                'error': 'Payload de acao invalido.',
            }

        action_name = (action_payload.get('name') or '').strip()
        arguments = action_payload.get('arguments')
        if not isinstance(arguments, dict):
            arguments = {}

        result = _run_action({
            'action': action_name,
            **arguments,
        })
        return {
            'type': 'agent.result.action_completed',
            'request_id': request_id,
            'device_id': AGENT_DEVICE_ID,
            'ok': result.get('ok') is True,
            'result': result,
            'error': result.get('error'),
        }

    if message_type == 'core.command.start_wake_word':
        keyword = (message.get('keyword') or '').strip()
        result = start_wake_word({'keyword': keyword} if keyword else None)
        return {
            'type': 'agent.status',
            'device_id': AGENT_DEVICE_ID,
            'wake_word_running': result.get('running') is True,
            'last_error': result.get('error') or '',
        }

    if message_type == 'core.command.stop_wake_word':
        stop_wake_word()
        return {
            'type': 'agent.status',
            'device_id': AGENT_DEVICE_ID,
            'wake_word_running': False,
            'last_error': '',
        }

    return None


def _load_websocket_connect():
    from websockets.sync.client import connect
    return connect


def _core_client_loop(stop_event: threading.Event) -> None:
    connect = _load_websocket_connect()
    url = _core_ws_url()

    while not stop_event.is_set():
        try:
            with connect(url, open_timeout=5, close_timeout=1, ping_interval=20) as websocket:
                websocket.send(json.dumps(_agent_hello_payload()))
                ack_raw = websocket.recv(timeout=10)
                if isinstance(ack_raw, bytes):
                    ack_raw = ack_raw.decode('utf-8', errors='replace')
                ack = json.loads(ack_raw)
                if ack.get('type') != 'core.hello_ack':
                    raise RuntimeError('Resposta invalida do core durante handshake.')

                _set_core_connection_state(True, error='')

                while not stop_event.is_set():
                    try:
                        raw_message = websocket.recv(timeout=1)
                    except TimeoutError:
                        websocket.send(
                            json.dumps(
                                {
                                    'type': 'agent.status',
                                    'device_id': AGENT_DEVICE_ID,
                                    'wake_word_running': _is_wake_word_running(),
                                    'last_error': _WAKE_WORD_RUNTIME_ERROR or '',
                                }
                            )
                        )
                        continue

                    if isinstance(raw_message, bytes):
                        raw_message = raw_message.decode('utf-8', errors='replace')

                    payload = json.loads(raw_message)
                    response = _run_core_command(payload)
                    if response is not None:
                        websocket.send(json.dumps(response))
                        _set_core_last_event()
        except Exception as exc:
            _set_core_connection_state(False, error=str(exc))
            time.sleep(2.0)


def _ensure_core_connection_thread() -> None:
    if not AUTO_CONNECT_CORE:
        return

    with _CORE_LOCK:
        global _CORE_THREAD
        if _CORE_THREAD is not None and _CORE_THREAD.is_alive():
            return

        _CORE_STOP.clear()
        _CORE_THREAD = threading.Thread(
            target=_core_client_loop,
            args=(_CORE_STOP,),
            name='jarvis-core-client',
            daemon=True,
        )
        _CORE_THREAD.start()


def _stop_core_connection_thread() -> None:
    _CORE_STOP.set()
    thread = _CORE_THREAD
    if thread is not None and thread.is_alive():
        thread.join(timeout=2.0)


def _fold_text(value: str) -> str:
    normalized = unicodedata.normalize('NFD', value)
    return ''.join(char for char in normalized if unicodedata.category(char) != 'Mn')


def _normalize_transcript(value: str) -> str:
    normalized = _fold_text(value.lower())
    normalized = re.sub(r'[^a-z0-9\s]', ' ', normalized)
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized.strip()


def _sanitize_wake_word_phrase(value: str | None) -> str:
    normalized = _normalize_transcript(value or '')
    return normalized or DEFAULT_WAKE_WORD_PHRASE


def _sanitize_wake_word_sensitivity(value: Any) -> int:
    try:
        sensitivity = int(value)
    except (TypeError, ValueError):
        sensitivity = DEFAULT_WAKE_WORD_SENSITIVITY
    return max(0, min(100, sensitivity))


def _normalize_lookup(value: str) -> str:
    normalized = _fold_text((value or '').lower())
    normalized = re.sub(r'[^a-z0-9]+', ' ', normalized)
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized.strip()


def _is_protected_window_title(title: str) -> bool:
    normalized = _normalize_lookup(title)
    return any(token in normalized for token in PROTECTED_WINDOW_TOKENS)


def _launch_app_target(target: str) -> None:
    last_error = None
    attempts = (
        (target, True),
        (['cmd', '/c', 'start', '', target], False),
    )

    for command, use_shell in attempts:
        try:
            subprocess.Popen(command, shell=use_shell)
            return
        except Exception as exc:
            last_error = exc

    if last_error is not None:
        raise last_error


def _find_windows(window_title: str) -> list[Any]:
    normalized_target = _normalize_lookup(window_title)
    if not normalized_target:
        return []

    matches = []
    for window in gw.getAllWindows():
        title = (window.title or '').strip()
        if not title:
            continue
        if normalized_target in _normalize_lookup(title):
            matches.append(window)
    return matches


def _active_window_title() -> str | None:
    window = gw.getActiveWindow()
    title = (window.title or '').strip() if window else ''
    return title or None


def _capture_screen_payload() -> dict[str, Any]:
    screenshot = pyautogui.screenshot()
    buffer = io.BytesIO()
    screenshot.save(buffer, format='PNG')
    return {
        'ok': True,
        'format': 'png',
        'image_base64': base64.b64encode(buffer.getvalue()).decode('ascii'),
        'active_window_title': _active_window_title(),
    }


def _close_window(window_title: str | None = None) -> dict[str, Any]:
    if window_title:
        windows = _find_windows(window_title)
    else:
        active_window = gw.getActiveWindow()
        windows = [active_window] if active_window else []

    for window in windows:
        title = (window.title or '').strip()
        if title and _is_protected_window_title(title):
            continue

        try:
            window.close()
            return {'ok': True, 'window_title': title or window_title}
        except Exception:
            continue

    if window_title:
        return {'ok': False, 'error': f'Janela nao encontrada: {window_title}'}

    return {'ok': False, 'error': 'Sem janela ativa'}


def _close_app(app_name: str) -> dict[str, Any]:
    clean_name = (app_name or '').strip()
    if not clean_name:
        return {'ok': False, 'error': 'Nome da app vazio'}

    normalized_name = _normalize_lookup(clean_name)
    candidates = {normalized_name}
    mapped_target = KNOWN_APPS.get(normalized_name)
    if mapped_target:
        candidates.add(_normalize_lookup(mapped_target))

    closed_titles = []
    for window in _find_windows(clean_name):
        title = (window.title or '').strip()
        if title and _is_protected_window_title(title):
            continue
        try:
            window.close()
            if title:
                closed_titles.append(title)
        except Exception:
            continue

    current_pid = os.getpid()
    terminated_processes = []
    for process in psutil.process_iter(['pid', 'name', 'exe']):
        if process.info.get('pid') == current_pid:
            continue

        process_name = process.info.get('name') or ''
        executable = process.info.get('exe') or ''
        normalized_fields = (_normalize_lookup(process_name), _normalize_lookup(executable))

        if not any(
            candidate and any(candidate in field for field in normalized_fields)
            for candidate in candidates
        ):
            continue

        if any(token in normalized_fields[0] for token in PROTECTED_WINDOW_TOKENS):
            continue

        try:
            process.terminate()
            terminated_processes.append(process_name or str(process.info.get('pid')))
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    if closed_titles or terminated_processes:
        return {
            'ok': True,
            'app': clean_name,
            'closed_windows': closed_titles[:5],
            'terminated_processes': terminated_processes[:10],
        }

    return {'ok': False, 'error': f'App nao encontrada: {clean_name}'}


def _search_youtube(query: str) -> dict[str, Any]:
    clean_query = (query or '').strip()
    if not clean_query:
        return {'ok': False, 'error': 'Pesquisa vazia para o YouTube'}

    url = f'https://www.youtube.com/results?search_query={urllib.parse.quote_plus(clean_query)}'
    webbrowser.open(url)
    return {'ok': True, 'url': url, 'query': clean_query}


def _phonetic_form(value: str) -> str:
    if not value:
        return value

    folded = (
        value.replace('ch', 'j')
        .replace('sh', 'x')
        .replace('ph', 'f')
    )
    folded = re.sub(r'(.)\1+', r'\1', folded)

    if len(folded) <= 1:
        return folded

    head = folded[0]
    tail = re.sub(r'[aeiou]', '', folded[1:])
    return f'{head}{tail}'


def _levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)

    if not b:
        return len(a)

    previous = list(range(len(b) + 1))
    current = [0] * (len(b) + 1)

    for i, char_a in enumerate(a, start=1):
        current[0] = i

        for j, char_b in enumerate(b, start=1):
            cost = 0 if char_a == char_b else 1
            current[j] = min(
                current[j - 1] + 1,
                previous[j] + 1,
                previous[j - 1] + cost,
            )

        previous, current = current, previous

    return previous[len(b)]


def _score_threshold_for_sensitivity(sensitivity: int) -> int:
    return max(60, min(88, 88 - round(sensitivity * 0.28)))


def _allowed_text_distance(sensitivity: int) -> int:
    if sensitivity >= 80:
        return 2
    if sensitivity >= 45:
        return 1
    return 0


def _allowed_phonetic_distance(sensitivity: int) -> int:
    if sensitivity >= 70:
        return 1
    return 0


def _matches_wake_word_candidate(value: str, wake_word_phrase: str, sensitivity: int) -> bool:
    candidate = value.replace(' ', '')
    wake_word = wake_word_phrase.replace(' ', '')

    if not candidate:
        return False

    phonetic_candidate = _phonetic_form(candidate)
    phonetic_wake_word = _phonetic_form(wake_word)

    if candidate == wake_word or phonetic_candidate == phonetic_wake_word:
        return True

    if sensitivity >= 60 and (candidate in wake_word or wake_word in candidate):
        return len(candidate) >= 4

    if _levenshtein(candidate, wake_word) <= _allowed_text_distance(sensitivity):
        return True

    return _levenshtein(phonetic_candidate, phonetic_wake_word) <= _allowed_phonetic_distance(sensitivity)


def _contains_wake_word(text: str, wake_word_phrase: str, sensitivity: int) -> bool:
    if not text:
        return False

    words = [word for word in text.split() if word]
    candidates = {text, text.replace(' ', '')}
    candidates.update(words)

    for index in range(len(words) - 1):
        candidates.add(f'{words[index]}{words[index + 1]}')

    return any(
        _matches_wake_word_candidate(candidate, wake_word_phrase, sensitivity)
        for candidate in candidates
    )


def _load_wake_word_runtime() -> dict[str, Any]:
    global _WAKE_WORD_RUNTIME, _WAKE_WORD_RUNTIME_ERROR

    if _WAKE_WORD_RUNTIME is not None:
        return _WAKE_WORD_RUNTIME

    try:
        import numpy as np
        import sounddevice as sd
        from faster_whisper import WhisperModel
        from rapidfuzz import fuzz
        from silero_vad import get_speech_timestamps, load_silero_vad
    except Exception as exc:  # pragma: no cover - optional runtime dependencies
        _WAKE_WORD_RUNTIME_ERROR = str(exc)
        raise RuntimeError(
            'Dependencias de wake word em falta no jarvis_agent_windows.'
        ) from exc

    model = WhisperModel('tiny', device='cpu', compute_type='int8')
    vad_model = load_silero_vad()

    _WAKE_WORD_RUNTIME = {
        'np': np,
        'sd': sd,
        'model': model,
        'vad_model': vad_model,
        'get_speech_timestamps': get_speech_timestamps,
        'fuzz': fuzz,
    }
    _WAKE_WORD_RUNTIME_ERROR = None
    return _WAKE_WORD_RUNTIME


def _wait_for_wake_word(stop_event: threading.Event) -> dict[str, Any] | None:
    runtime = _load_wake_word_runtime()
    wake_word_phrase = _CURRENT_WAKE_WORD_PHRASE
    wake_word_sensitivity = _CURRENT_WAKE_WORD_SENSITIVITY

    np = runtime['np']
    sd = runtime['sd']
    model = runtime['model']
    vad_model = runtime['vad_model']
    get_speech_timestamps = runtime['get_speech_timestamps']
    fuzz = runtime['fuzz']

    audio_queue: 'queue.Queue[Any]' = queue.Queue()
    audio_buffer: list[Any] = []
    last_heard = ''

    def callback(indata, frames, time_info, status):
        if status:
            _publish_event('wake_word_warning', message=str(status))

        try:
            audio_queue.put_nowait(indata.copy())
        except queue.Full:
            pass

    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype='float32',
        blocksize=BLOCKSIZE,
        callback=callback,
    ):
        while not stop_event.is_set():
            try:
                chunk = audio_queue.get(timeout=0.2).flatten()
            except queue.Empty:
                continue

            audio_buffer.append(chunk)
            if len(audio_buffer) > MAX_BUFFER_CHUNKS:
                audio_buffer.pop(0)

            audio = np.concatenate(audio_buffer)
            if len(audio) < SAMPLE_RATE * MIN_AUDIO_SECONDS:
                continue

            speech = get_speech_timestamps(
                audio,
                vad_model,
                sampling_rate=SAMPLE_RATE,
            )
            if not speech:
                continue

            segments, _ = model.transcribe(
                audio,
                language='pt',
                vad_filter=False,
                beam_size=1,
                best_of=1,
                condition_on_previous_text=False,
                without_timestamps=True,
            )

            for segment in segments:
                raw_text = (segment.text or '').lower().strip()
                normalized = _normalize_transcript(raw_text)
                if not normalized:
                    continue

                score = int(
                    fuzz.partial_ratio(
                        normalized.replace(' ', ''),
                        wake_word_phrase.replace(' ', ''),
                    )
                )
                if normalized != last_heard:
                    last_heard = normalized
                    _publish_event(
                        'wake_word_heard',
                        transcript=normalized,
                        raw_transcript=raw_text,
                        score=score,
                    )

                if (
                    _contains_wake_word(normalized, wake_word_phrase, wake_word_sensitivity)
                    or score >= _score_threshold_for_sensitivity(wake_word_sensitivity)
                ):
                    return {
                        'keyword': wake_word_phrase,
                        'sensitivity': wake_word_sensitivity,
                        'transcript': normalized,
                        'raw_transcript': raw_text,
                        'score': score,
                    }

    return None


def _wake_word_loop() -> None:
    try:
        while not _WAKE_WORD_STOP.is_set():
            detected = _wait_for_wake_word(_WAKE_WORD_STOP)
            if _WAKE_WORD_STOP.is_set():
                return

            if detected is not None:
                _publish_event('wake_word_detected', **detected)
                return
    except Exception as exc:  # pragma: no cover - runtime/environment dependent
        _publish_event('wake_word_error', message=str(exc))
    finally:
        with _WAKE_WORD_LOCK:
            global _WAKE_WORD_THREAD
            _WAKE_WORD_THREAD = None


def _run_action(data: dict[str, Any]) -> dict[str, Any]:
    action = (data.get('action') or '').strip()

    if action == 'volume_up':
        pyautogui.press('volumeup')
        return {'ok': True}

    if action == 'volume_down':
        pyautogui.press('volumedown')
        return {'ok': True}

    if action == 'close_window':
        return _close_window((data.get('window_title') or '').strip() or None)

    if action == 'close_tab':
        pyautogui.hotkey('ctrl', 'w')
        return {'ok': True}

    if action == 'close_app':
        return _close_app((data.get('app_name') or data.get('target') or '').strip())

    if action == 'screenshot':
        path = 'screenshot.png'
        pyautogui.screenshot(path)
        return {'ok': True, 'path': path}

    if action == 'list_processes':
        processes = [p.name() for p in psutil.process_iter()]
        return {'ok': True, 'processes': processes[:20]}

    if action == 'open_url':
        url = (data.get('url') or '').strip()
        if not url:
            return {'ok': False, 'error': 'URL vazia'}

        if not url.startswith('http'):
            url = 'https://' + url

        webbrowser.open(url)
        return {'ok': True, 'url': url}

    if action == 'open_app':
        app_name = (data.get('app_name') or '').strip()
        if not app_name:
            return {'ok': False, 'error': 'Nome da app vazio'}

        normalized_name = _normalize_lookup(app_name)
        if normalized_name in KNOWN_WEBSITES:
            url = KNOWN_WEBSITES[normalized_name]
            webbrowser.open(url)
            return {'ok': True, 'url': url}

        target = KNOWN_APPS.get(normalized_name, app_name)
        try:
            _launch_app_target(target)
        except Exception as exc:
            return {'ok': False, 'error': f'Nao consegui abrir {app_name}: {exc}'}

        return {'ok': True, 'app': app_name}

    if action == 'type_text':
        text = data.get('text') or ''
        if not text:
            return {'ok': False, 'error': 'Texto vazio'}
        pyautogui.write(text, interval=0.02)
        return {'ok': True, 'text': text}

    if action == 'press_keys':
        keys = (data.get('keys') or '').strip()
        parts = [key.strip().lower() for key in keys.split('+') if key.strip()]
        if not parts:
            return {'ok': False, 'error': 'Atalho vazio'}
        if len(parts) == 1:
            pyautogui.press(parts[0])
        else:
            pyautogui.hotkey(*parts)
        return {'ok': True, 'keys': keys}

    if action == 'youtube_search':
        return _search_youtube(data.get('query') or '')

    if action == 'activate_window':
        window_title = (data.get('window_title') or data.get('target') or '').strip()
        if not window_title:
            return {'ok': False, 'error': 'Titulo da janela vazio'}
        for window in _find_windows(window_title):
            title = (window.title or '').strip()
            try:
                if getattr(window, 'isMinimized', False):
                    window.restore()
                window.activate()
                return {'ok': True, 'window_title': title or window_title}
            except Exception:
                continue
        return {'ok': False, 'error': f'Janela nao encontrada: {window_title}'}

    if action == 'minimize_window':
        window_title = (data.get('window_title') or data.get('target') or '').strip()
        windows = _find_windows(window_title) if window_title else [gw.getActiveWindow()]
        for window in windows:
            if not window:
                continue
            title = (window.title or '').strip()
            try:
                window.minimize()
                return {'ok': True, 'window_title': title or window_title}
            except Exception:
                continue
        return {'ok': False, 'error': 'Sem janela para minimizar'}

    return {'ok': False, 'error': 'Acao desconhecida'}


@app.get('/health')
def health() -> dict[str, Any]:
    return {
        'ok': True,
        'device_id': AGENT_DEVICE_ID,
        'device_name': AGENT_DEVICE_NAME,
        'device_type': AGENT_DEVICE_TYPE,
        'core_connected': _is_core_connected(),
        'core_last_error': _CORE_LAST_ERROR,
        'core_last_event_at': _CORE_LAST_EVENT_AT,
        'capabilities': list(AGENT_CAPABILITIES),
        'wake_word_running': _is_wake_word_running(),
        'wake_word_engine': WAKE_WORD_ENGINE,
        'wake_word_error': _WAKE_WORD_RUNTIME_ERROR,
        'wake_word_phrase': _CURRENT_WAKE_WORD_PHRASE,
        'wake_word_sensitivity': _CURRENT_WAKE_WORD_SENSITIVITY,
        'wake_word_threshold': _score_threshold_for_sensitivity(_CURRENT_WAKE_WORD_SENSITIVITY),
    }


@app.post('/wake-word/start')
def start_wake_word(data: dict[str, Any] | None = Body(default=None)) -> dict[str, Any]:
    requested_phrase = _sanitize_wake_word_phrase(
        (data or {}).get('keyword') or (data or {}).get('wake_word_phrase')
    )
    requested_sensitivity = _sanitize_wake_word_sensitivity(
        (data or {}).get('sensitivity')
    )

    with _WAKE_WORD_LOCK:
        global _CURRENT_WAKE_WORD_PHRASE, _CURRENT_WAKE_WORD_SENSITIVITY
        _CURRENT_WAKE_WORD_PHRASE = requested_phrase
        _CURRENT_WAKE_WORD_SENSITIVITY = requested_sensitivity

        if _is_wake_word_running():
            return {
                'ok': True,
                'running': True,
                'engine': WAKE_WORD_ENGINE,
                'keyword': _CURRENT_WAKE_WORD_PHRASE,
                'sensitivity': _CURRENT_WAKE_WORD_SENSITIVITY,
            }

        try:
            _load_wake_word_runtime()
        except Exception as exc:
            return {
                'ok': False,
                'running': False,
                'error': str(exc),
            }

        _WAKE_WORD_STOP.clear()

        global _WAKE_WORD_THREAD
        _WAKE_WORD_THREAD = threading.Thread(
            target=_wake_word_loop,
            name='jarvis-wake-word',
            daemon=True,
        )
        _WAKE_WORD_THREAD.start()

        return {
            'ok': True,
            'running': True,
            'engine': WAKE_WORD_ENGINE,
            'keyword': _CURRENT_WAKE_WORD_PHRASE,
            'sensitivity': _CURRENT_WAKE_WORD_SENSITIVITY,
        }


@app.post('/wake-word/stop')
def stop_wake_word() -> dict[str, Any]:
    _WAKE_WORD_STOP.set()

    thread = _WAKE_WORD_THREAD
    if thread is not None and thread.is_alive():
        thread.join(timeout=1.0)

    return {'ok': True, 'running': False}


@app.get('/wake-word/events/next')
def next_wake_word_event(
    timeout_ms: int = Query(default=3000, ge=0, le=30000),
) -> dict[str, Any]:
    timeout_seconds = timeout_ms / 1000

    try:
        event = _WAKE_WORD_EVENTS.get(timeout=timeout_seconds)
    except queue.Empty:
        return {'ok': True, 'event': None}

    return {'ok': True, 'event': event}


@app.get('/screen/capture')
def capture_screen() -> dict[str, Any]:
    try:
        return _capture_screen_payload()
    except Exception as exc:
        return {'ok': False, 'error': str(exc)}


@app.post('/action')
def run_action(data: dict[str, Any]) -> dict[str, Any]:
    try:
        return _run_action(data)
    except Exception as exc:
        return {'ok': False, 'error': str(exc)}


@app.on_event('startup')
def _startup() -> None:
    _ensure_core_connection_thread()


@app.on_event('shutdown')
def _shutdown() -> None:
    _stop_core_connection_thread()
    _WAKE_WORD_STOP.set()
