from __future__ import annotations

from settings_store import load_settings_values

from llm.ollama import call_llm as call_ollama_llm
from llm.openai import call_llm as call_openai_llm


def resolve_llm_settings(user_id: str | None = None) -> dict[str, str]:
    values = load_settings_values(user_id=user_id)
    return {
        "provider": values.get("llm_provider", "ollama").strip().lower() or "ollama",
        "ollama_url": values.get("ollama_url", "").strip(),
        "ollama_model": values.get("ollama_model", "").strip(),
        "openai_model": values.get("openai_model", "").strip(),
        "openai_api_key": values.get("openai_api_key", "").strip(),
    }


def call_llm(messages, *, user_id: str | None = None):
    llm_settings = resolve_llm_settings(user_id=user_id)
    provider = llm_settings["provider"]

    if provider == "openai":
        return call_openai_llm(
            messages,
            model=llm_settings["openai_model"],
            api_key=llm_settings["openai_api_key"],
        )

    return call_ollama_llm(
        messages,
        model=llm_settings["ollama_model"],
        ollama_url=llm_settings["ollama_url"],
    )
