from __future__ import annotations

import os
import json

from openai import OpenAI

from config import LLM_TIMEOUT_SECONDS, OPENAI_CHAT_MODEL
from logging_utils import get_logger, log_event
from llm.ollama import LLMUnavailableError


logger = get_logger(__name__)


def _stringify_content(content: object) -> str:
    if isinstance(content, str):
        return content
    if content is None:
        return ""
    try:
        return json.dumps(content, ensure_ascii=False)
    except TypeError:
        return str(content)


def _prepare_messages(messages: list[dict]) -> list[dict[str, str]]:
    prepared: list[dict[str, str]] = []

    for message in messages:
        role = str(message.get("role") or "user").strip().lower()
        content = _stringify_content(message.get("content")).strip()

        if role in {"system", "user", "assistant"}:
            prepared.append({"role": role, "content": content})
            continue

        if role == "tool":
            prepared.append(
                {
                    "role": "user",
                    "content": (
                        "Resultado da ferramenta pedida anteriormente:\n"
                        f"{content}\n"
                        "Usa este resultado para responder ao pedido original do utilizador."
                    ),
                }
            )
            continue

        prepared.append({"role": "user", "content": content})

    return prepared


def _extract_completion_text(completion) -> str:
    try:
        message = completion.choices[0].message
    except Exception as exc:
        raise LLMUnavailableError("A OpenAI respondeu num formato inesperado.") from exc

    content = getattr(message, "content", "")
    if isinstance(content, str):
        return content.strip()

    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
                continue

            text = getattr(item, "text", None)
            if text:
                parts.append(str(text))

        return "\n".join(part.strip() for part in parts if part and part.strip())

    return str(content).strip()


def call_llm(messages, *, model: str | None = None, api_key: str | None = None):
    selected_model = (model or OPENAI_CHAT_MODEL).strip() or OPENAI_CHAT_MODEL
    selected_api_key = (api_key or "").strip() or os.getenv("OPENAI_API_KEY", "").strip()
    if not selected_api_key:
        raise LLMUnavailableError(
            "OpenAI sem chave API configurada. Define OPENAI_API_KEY no backend ou guarda a chave OpenAI nas configuracoes."
        )

    client = OpenAI(
        api_key=selected_api_key,
        timeout=LLM_TIMEOUT_SECONDS,
    )
    prepared_messages = _prepare_messages(messages)

    try:
        completion = client.chat.completions.create(
            model=selected_model,
            messages=prepared_messages,
            temperature=0.7,
            top_p=0.9,
        )
    except Exception as exc:
        log_event(
            logger,
            40,
            "openai_llm_failed",
            model=selected_model,
            message_count=len(prepared_messages),
            error=str(exc),
        )
        raise LLMUnavailableError(
            f"Nao consegui obter resposta da OpenAI com o modelo '{selected_model}'."
        ) from exc

    reply = _extract_completion_text(completion)
    if not reply:
        raise LLMUnavailableError("A OpenAI nao devolveu texto utilizavel.")

    log_event(
        logger,
        20,
        "openai_llm_response",
        model=selected_model,
        message_count=len(prepared_messages),
        reply_length=len(reply),
    )

    return reply
