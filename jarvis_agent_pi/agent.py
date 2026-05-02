from __future__ import annotations

import json
import os
import threading
import time
import urllib.parse
from datetime import datetime, timezone
from typing import Any

from fastapi import Body, FastAPI

app = FastAPI()

DEFAULT_WAKE_WORD_PHRASE = 'jarvis'

AGENT_DEVICE_ID = (os.getenv('JARVIS_DEVICE_ID') or os.getenv('HOSTNAME') or 'pi-agent-01').strip()
AGENT_DEVICE_NAME = (os.getenv('JARVIS_DEVICE_NAME') or AGENT_DEVICE_ID).strip()
AGENT_DEVICE_TYPE = (os.getenv('JARVIS_DEVICE_TYPE') or 'raspberry-pi').strip()
AGENT_PLATFORM = (os.getenv('JARVIS_DEVICE_PLATFORM') or 'linux').strip()
AGENT_LOCATION = (os.getenv('JARVIS_DEVICE_LOCATION') or '').strip()
CORE_WS_URL = (os.getenv('JARVIS_CORE_WS_URL') or 'ws://127.0.0.1:8000/agents/ws').strip()
CORE_API_TOKEN = (os.getenv('JARVIS_API_TOKEN') or '').strip()
AUTO_CONNECT_CORE = (os.getenv('JARVIS_AGENT_AUTO_CONNECT') or 'true').strip().lower() not in {'0', 'false', 'no', 'off'}
AGENT_CAPABILITIES = [
    'audio.capture',
    'audio.playback',
    'wake_word.local',
]

_CORE_LOCK = threading.Lock()
_CORE_STOP = threading.Event()
_CORE_THREAD: threading.Thread | None = None
_CORE_CONNECTED = False
_CORE_LAST_ERROR = ''
_CORE_LAST_EVENT_AT = ''
_WAKE_WORD_RUNNING = False
_WAKE_WORD_PHRASE = DEFAULT_WAKE_WORD_PHRASE


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _set_core_connection_state(connected: bool, *, error: str = '') -> None:
    global _CORE_CONNECTED, _CORE_LAST_ERROR, _CORE_LAST_EVENT_AT
    with _CORE_LOCK:
        _CORE_CONNECTED = connected
        _CORE_LAST_ERROR = error.strip()
        if connected:
            _CORE_LAST_EVENT_AT = _utc_now_iso()


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
        'agent_version': '1.0.0',
        'capabilities': list(AGENT_CAPABILITIES),
        'metadata': {
            'wake_word_engine': 'pi-agent-placeholder',
        },
    }


def _load_websocket_connect():
    from websockets.sync.client import connect
    return connect


def _run_core_command(message: dict[str, Any]) -> dict[str, Any] | None:
    message_type = (message.get('type') or '').strip()

    if message_type == 'core.command.start_wake_word':
        global _WAKE_WORD_RUNNING
        _WAKE_WORD_RUNNING = True
        return {
            'type': 'agent.status',
            'device_id': AGENT_DEVICE_ID,
            'wake_word_running': _WAKE_WORD_RUNNING,
            'last_error': '',
        }

    if message_type == 'core.command.stop_wake_word':
        _WAKE_WORD_RUNNING = False
        return {
            'type': 'agent.status',
            'device_id': AGENT_DEVICE_ID,
            'wake_word_running': _WAKE_WORD_RUNNING,
            'last_error': '',
        }

    return None


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
                    raise RuntimeError('Handshake invalido com o core.')

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
                                    'wake_word_running': _WAKE_WORD_RUNNING,
                                    'last_error': '',
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
            name='jarvis-pi-core-client',
            daemon=True,
        )
        _CORE_THREAD.start()


def _stop_core_connection_thread() -> None:
    _CORE_STOP.set()
    thread = _CORE_THREAD
    if thread is not None and thread.is_alive():
        thread.join(timeout=2.0)


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
        'wake_word_running': _WAKE_WORD_RUNNING,
        'wake_word_phrase': _WAKE_WORD_PHRASE,
    }


@app.post('/wake-word/start')
def start_wake_word(data: dict[str, Any] | None = Body(default=None)) -> dict[str, Any]:
    global _WAKE_WORD_RUNNING, _WAKE_WORD_PHRASE
    _WAKE_WORD_RUNNING = True
    requested_phrase = str((data or {}).get('keyword') or '').strip()
    if requested_phrase:
        _WAKE_WORD_PHRASE = requested_phrase

    return {
        'ok': True,
        'running': True,
        'keyword': _WAKE_WORD_PHRASE,
    }


@app.post('/wake-word/stop')
def stop_wake_word() -> dict[str, Any]:
    global _WAKE_WORD_RUNNING
    _WAKE_WORD_RUNNING = False
    return {
        'ok': True,
        'running': False,
    }


@app.on_event('startup')
def _startup() -> None:
    _ensure_core_connection_thread()


@app.on_event('shutdown')
def _shutdown() -> None:
    _stop_core_connection_thread()
