"""
Extracao de memoria a partir da fala do utilizador.

Responsabilidade:
- Interpretar frases do utilizador que devam ficar na memoria
- Priorizar extracao via LLM em JSON estruturado
- Manter heuristicas simples como fallback seguro
"""

from __future__ import annotations

import json
import re

from llm.service import call_llm
from memory.user_memory import load_facts, save_fact, save_preference, save_reminder


MEMORY_EXTRACTION_SYSTEM_PROMPT = """
Analisa uma unica mensagem do utilizador e decide se ha informacao que deve ser guardada como memoria.

Tipos de memoria aceites:
- name: nome atual do utilizador
- preferences: preferencias duradouras sobre como responder ou agir
- reminders: coisas que o utilizador quer que fiquem lembradas

Regras:
- So guardas memoria quando a frase contem informacao pessoal, uma preferencia persistente, uma correcao a memoria existente, ou um lembrete explicito.
- Ignora pedidos operacionais passageiros, perguntas, small talk, comandos de abrir/fechar apps, meteorologia pontual, e pedidos para listar ou limpar memoria.
- Se o utilizador corrigir um facto anterior, devolve apenas o valor mais recente.
- Para preferencias, escreve frases curtas, claras e auto-contidas em portugues de Portugal.
- Para lembretes, devolve o conteudo essencial do lembrete sem texto extra.
- Responde APENAS em JSON valido, sem markdown.

Formato exato:
{
  "should_store": true,
  "name": "Rui",
  "preferences": ["Prefiro respostas curtas e diretas."],
  "reminders": ["tenho consulta na sexta"]
}

Se nao houver nada para guardar:
{
  "should_store": false,
  "name": "",
  "preferences": [],
  "reminders": []
}
""".strip()


def _normalize_fragment(value: str) -> str:
    clean_value = value.strip()
    clean_value = re.sub(r"\s+", " ", clean_value)
    clean_value = re.sub(r"[.!?,;:\-\u2013\u2014\s]+$", "", clean_value)
    return clean_value.strip()


def _normalize_name(value: str) -> str:
    clean_value = _normalize_fragment(value)
    clean_value = re.sub(r"[^\w\s-]", "", clean_value)
    return " ".join(word.capitalize() for word in clean_value.split())


def _normalize_preference(value: str) -> str:
    clean_value = _normalize_fragment(value)
    if not clean_value:
        return ""
    clean_value = clean_value[0].upper() + clean_value[1:]
    if not clean_value.endswith("."):
        clean_value += "."
    return clean_value


def _normalize_reminder(value: str) -> str:
    return _normalize_fragment(value)


def _is_placeholder_name(value: str) -> bool:
    normalized = _normalize_fragment(value).lower()
    return normalized in {
        "",
        "desconhecido",
        "desconhecida",
        "nao fornecido",
        "nao fornecida",
        "nao indicado",
        "nao indicada",
        "sem nome",
        "unknown",
        "none",
        "n a",
        "n/a",
    }


def _looks_like_memory_candidate(text: str) -> bool:
    normalized = (text or "").strip().lower()
    if not normalized:
        return False

    obvious_non_memory_patterns = (
        "que horas",
        "qual e a data",
        "que dia",
        "mostra memoria",
        "lista memoria",
        "limpa a memoria",
        "abre ",
        "fecha ",
        "toca ",
        "pesquisa ",
        "como esta o tempo",
    )
    if any(pattern in normalized for pattern in obvious_non_memory_patterns):
        return False

    memory_query_patterns = (
        "lembras-te do meu nome",
        "qual e o meu nome",
        "o que e que te pedi para te lembrares",
        "do que te lembras",
        "que tipo de respostas prefiro",
        "que lembretes tens meus",
    )
    if normalized.endswith("?") or any(pattern in normalized for pattern in memory_query_patterns):
        return False

    command_prefixes = (
        "abre ",
        "abrir ",
        "fecha ",
        "fechar ",
        "toca ",
        "tocar ",
        "poe ",
        "por ",
        "pesquisa ",
        "procura ",
        "liga ",
        "desliga ",
        "aumenta ",
        "baixa ",
        "mostra ",
        "lista ",
        "ver ",
        "mete ",
        "muda ",
        "define ",
        "diz-me ",
    )
    if normalized.startswith(command_prefixes):
        return False

    if normalized in {"ola", "olá", "bom dia", "boa tarde", "boa noite", "obrigado", "obrigada"}:
        return False

    return len(normalized.split()) >= 3


def _build_memory_context(user_id: str | None = None) -> str:
    facts = load_facts(user_id=user_id)
    lines: list[str] = []

    if facts.get("name"):
        lines.append(f"Nome atual: {facts['name']}")

    preferences = facts.get("preferences") or []
    if preferences:
        lines.append("Preferencias atuais:")
        lines.extend(f"- {preference}" for preference in preferences)

    reminders = facts.get("reminders") or []
    if reminders:
        lines.append("Lembretes atuais:")
        lines.extend(f"- {reminder}" for reminder in reminders)

    if not lines:
        return "Sem memoria guardada."

    return "\n".join(lines)


def _extract_first_json_object(raw_text: str) -> dict | None:
    text = (raw_text or "").strip()
    if not text:
        return None

    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            return None
        try:
            payload = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return None

    if isinstance(payload, dict):
        return payload
    return None


def _extract_with_regex(text: str) -> dict[str, object]:
    text_l = text.lower()

    patterns = [
        r"chamo-me\s+(.+)",
        r"o meu nome e\s+(.+)",
        r"meu nome e\s+(.+)",
        r"eu sou o\s+(.+)",
        r"eu sou a\s+(.+)",
        r"eu sou da\s+(.+)",
        r"eu sou das\s+(.+)",
    ]

    for pattern in patterns:
        match = re.search(pattern, text_l)
        if match:
            return {
                "should_store": True,
                "name": _normalize_name(match.group(1)),
                "preferences": [],
                "reminders": [],
            }

    preference_patterns = [
        r"sempre que (.+?) quero que (.+)",
        r"sempre que (.+?) quero (.+)",
        r"quando (.+?) quero que (.+)",
        r"quando (.+?) quero (.+)",
    ]

    for pattern in preference_patterns:
        match = re.search(pattern, text_l, re.IGNORECASE)
        if match:
            condition = _normalize_fragment(match.group(1))
            action = _normalize_fragment(match.group(2))
            return {
                "should_store": True,
                "name": "",
                "preferences": [
                    _normalize_preference(f"Sempre que {condition}, quero que {action}")
                ],
                "reminders": [],
            }

    reminder_patterns = [
        r"quero que te lembres que (.+)",
        r"lembra-te que (.+)",
        r"guarda que (.+)",
    ]

    for pattern in reminder_patterns:
        match = re.search(pattern, text_l, re.IGNORECASE)
        if match:
            return {
                "should_store": True,
                "name": "",
                "preferences": [],
                "reminders": [_normalize_reminder(match.group(1))],
            }

    return {
        "should_store": False,
        "name": "",
        "preferences": [],
        "reminders": [],
    }


def _extract_with_llm(text: str, user_id: str | None = None) -> dict[str, object]:
    if not _looks_like_memory_candidate(text):
        return {
            "should_store": False,
            "name": "",
            "preferences": [],
            "reminders": [],
        }

    memory_context = _build_memory_context(user_id=user_id)
    raw_response = call_llm(
        [
            {"role": "system", "content": MEMORY_EXTRACTION_SYSTEM_PROMPT},
            {"role": "system", "content": f"Memoria atual do utilizador:\n{memory_context}"},
            {"role": "user", "content": f"Mensagem do utilizador:\n{text.strip()}"},
        ],
        user_id=user_id,
    )
    payload = _extract_first_json_object(raw_response)
    if payload is None:
        return {
            "should_store": False,
            "name": "",
            "preferences": [],
            "reminders": [],
        }

    name = _normalize_name(str(payload.get("name") or ""))
    if _is_placeholder_name(name):
        name = ""
    preferences = [
        normalized
        for normalized in (
            _normalize_preference(str(item or ""))
            for item in (payload.get("preferences") or [])
            if isinstance(item, str)
        )
        if normalized
    ]
    reminders = [
        normalized
        for normalized in (
            _normalize_reminder(str(item or ""))
            for item in (payload.get("reminders") or [])
            if isinstance(item, str)
        )
        if normalized
    ]

    should_store = bool(payload.get("should_store")) and bool(name or preferences or reminders)
    return {
        "should_store": should_store,
        "name": name,
        "preferences": preferences,
        "reminders": reminders,
    }


def _persist_memory(payload: dict[str, object], user_id: str | None = None) -> bool:
    updated = False

    name = str(payload.get("name") or "").strip()
    if name:
        save_fact("name", name, user_id=user_id)
        updated = True

    seen_preferences: set[str] = set()
    for preference in payload.get("preferences") or []:
        clean_preference = str(preference or "").strip()
        if not clean_preference or clean_preference in seen_preferences:
            continue
        save_preference(clean_preference, user_id=user_id)
        seen_preferences.add(clean_preference)
        updated = True

    seen_reminders: set[str] = set()
    for reminder in payload.get("reminders") or []:
        clean_reminder = str(reminder or "").strip()
        if not clean_reminder or clean_reminder in seen_reminders:
            continue
        save_reminder(clean_reminder, user_id=user_id)
        seen_reminders.add(clean_reminder)
        updated = True

    return updated


def extract_user_facts(text, user_id: str | None = None) -> bool:
    """
    Analisa texto e extrai memoria do utilizador.
    Usa heuristicas rapidas primeiro e recorre ao LLM para frases livres.
    """
    regex_payload = _extract_with_regex(text)
    if _persist_memory(regex_payload, user_id=user_id):
        return True

    try:
        llm_payload = _extract_with_llm(text, user_id=user_id)
        return _persist_memory(llm_payload, user_id=user_id)
    except Exception:
        return False
