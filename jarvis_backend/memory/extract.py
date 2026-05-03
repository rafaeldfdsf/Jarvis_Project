"""
Extracao de factos a partir da fala do utilizador.

Responsabilidade:
- Detetar padroes simples (ex: nome, preferencias, lembretes)
- Guardar na memoria persistente

Nao e NLP avancado, e heuristica.
"""

from __future__ import annotations

import re

from memory.user_memory import save_fact, save_preference, save_reminder


def _normalize_fragment(value: str) -> str:
    clean_value = value.strip()
    clean_value = re.sub(r"\s+", " ", clean_value)
    clean_value = re.sub(r"[.!?,;:\-–—\s]+$", "", clean_value)
    return clean_value.strip()


def extract_user_facts(text, user_id: str | None = None):
    """
    Analisa texto e extrai factos simples do utilizador.
    """
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
            name = _normalize_fragment(match.group(1))
            name = re.sub(r"[^\w\s-]", "", name)
            name = " ".join(w.capitalize() for w in name.split())
            save_fact("name", name, user_id=user_id)
            return

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
            preference = f"Sempre que {condition}, quero que {action}."
            save_preference(preference, user_id=user_id)
            return

    reminder_patterns = [
        r"quero que te lembres que (.+)",
        r"lembra-te que (.+)",
        r"guarda que (.+)",
    ]

    for pattern in reminder_patterns:
        match = re.search(pattern, text_l, re.IGNORECASE)
        if match:
            reminder = _normalize_fragment(match.group(1))
            save_reminder(reminder, user_id=user_id)
            return
