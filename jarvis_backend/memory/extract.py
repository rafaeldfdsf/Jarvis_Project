"""
Extração de factos a partir da fala do utilizador.

Responsabilidade:
- Detetar padrões simples (ex: nome, preferências, lembretes)
- Guardar na memória persistente

Não é NLP avançado, é heurística.
"""

import re
from memory.user_memory import save_fact, save_preference, save_reminder

def extract_user_facts(text):
    """
    Analisa texto e extrai factos simples do utilizador.
    """
    text_l = text.lower()

    # Detetar nome
    patterns = [
        r"chamo-me\s+(.+)",
        r"o meu nome é\s+(.+)",
        r"meu nome é\s+(.+)",
        r"eu sou o\s+(.+)",
        r"eu sou a\s+(.+)",
        r"eu sou da\s+(.+)",
        r"eu sou das\s+(.+)",
    ]

    for pattern in patterns:
        match = re.search(pattern, text_l)
        if match:
            name = match.group(1)

            name = re.sub(r"[^\w\sÀ-ÿ]", "", name)
            name = " ".join(w.capitalize() for w in name.split())

            save_fact("name", name)
            print(f"Nome guardado: {name}")
            return

    # Detetar preferências (ex: "Sempre que eu te perguntar o tempo quero que me digas o tempo nas Caldas da Rainha")
    preference_patterns = [
        r"sempre que (.+?) quero que (.+)",
        r"sempre que (.+?) quero (.+)",
        r"quando (.+?) quero que (.+)",
        r"quando (.+?) quero (.+)",
    ]

    for pattern in preference_patterns:
        match = re.search(pattern, text_l, re.IGNORECASE)
        if match:
            condition = match.group(1).strip()
            action = match.group(2).strip()
            preference = f"Sempre que {condition}, quero que {action}."
            save_preference(preference)
            print(f"Preferência guardada: {preference}")
            return

    # Detetar lembretes (ex: "Quero que te lembres que o aniversario do Manel é no dia 5 de março")
    reminder_patterns = [
        r"quero que te lembres que (.+)",
        r"lembra-te que (.+)",
        r"guarda que (.+)",
    ]

    for pattern in reminder_patterns:
        match = re.search(pattern, text_l, re.IGNORECASE)
        if match:
            reminder = match.group(1).strip()
            save_reminder(reminder)
            print(f"Lembrete guardado: {reminder}")
            return