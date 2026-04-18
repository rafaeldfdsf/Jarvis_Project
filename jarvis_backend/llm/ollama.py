import requests

from config import LLM_TIMEOUT_SECONDS, MODEL, OLLAMA_URL
from logging_utils import get_logger, log_event


logger = get_logger(__name__)


class LLMUnavailableError(RuntimeError):
    """Erro levantado quando o Ollama nao esta acessivel."""


def call_llm(messages):
    payload = {
        'model': MODEL,
        'messages': messages,
        'stream': False,
        'options': {
            'temperature': 0.7,
            'top_p': 0.9,
        },
    }

    try:
        response = requests.post(
            f'{OLLAMA_URL}/api/chat',
            json=payload,
            timeout=LLM_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        log_event(
            logger,
            40,
            'llm_unavailable',
            ollama_url=OLLAMA_URL,
            model=MODEL,
            error=str(exc),
        )
        raise LLMUnavailableError(
            f'Ollama indisponivel em {OLLAMA_URL}. Inicia o servidor Ollama e confirma que o modelo "{MODEL}" esta carregado.'
        ) from exc

    try:
        data = response.json()
        reply = data['message']['content'].strip()
    except (ValueError, KeyError, TypeError) as exc:
        log_event(
            logger,
            40,
            'llm_invalid_response',
            ollama_url=OLLAMA_URL,
            error=str(exc),
        )
        raise LLMUnavailableError('O Ollama respondeu num formato inesperado.') from exc

    log_event(
        logger,
        20,
        'llm_response',
        model=MODEL,
        message_count=len(messages),
        reply_length=len(reply),
    )

    return reply
