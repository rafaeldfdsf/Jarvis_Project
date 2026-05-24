import requests

from config import LLM_TIMEOUT_SECONDS, MODEL, OLLAMA_URL
from logging_utils import get_logger, log_event


logger = get_logger(__name__)


class LLMUnavailableError(RuntimeError):
    """Erro levantado quando o Ollama nao esta acessivel."""


def call_llm(messages, *, model: str | None = None, ollama_url: str | None = None):
    selected_model = (model or MODEL).strip() or MODEL
    selected_ollama_url = (ollama_url or OLLAMA_URL).strip().rstrip("/") or OLLAMA_URL
    payload = {
        'model': selected_model,
        'messages': messages,
        'stream': False,
        'options': {
            'temperature': 0.7,
            'top_p': 0.9,
        },
    }

    try:
        response = requests.post(
            f'{selected_ollama_url}/api/chat',
            json=payload,
            timeout=LLM_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        log_event(
            logger,
            40,
            'llm_unavailable',
            ollama_url=selected_ollama_url,
            model=selected_model,
            error=str(exc),
        )
        raise LLMUnavailableError(
            f'Ollama indisponivel em {selected_ollama_url}. Inicia o servidor Ollama e confirma que o modelo "{selected_model}" esta carregado.'
        ) from exc

    try:
        data = response.json()
        reply = data['message']['content'].strip()
    except (ValueError, KeyError, TypeError) as exc:
        log_event(
            logger,
            40,
            'llm_invalid_response',
            ollama_url=selected_ollama_url,
            error=str(exc),
        )
        raise LLMUnavailableError('O Ollama respondeu num formato inesperado.') from exc

    log_event(
        logger,
        20,
        'llm_response',
        model=selected_model,
        message_count=len(messages),
        reply_length=len(reply),
    )

    return reply
