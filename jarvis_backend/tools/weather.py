import random
import requests

from config import WEATHER_TIMEOUT_SECONDS

CITY_COORDS = {
    "lisboa": (38.72, -9.13),
    "porto": (41.15, -8.61),
    "braga": (41.55, -8.42),
    "coimbra": (40.21, -8.43),
    "faro": (37.02, -7.93),
    "caldas da rainha": (39.40, -9.14),
}


def get_weather(city: str = "Lisboa", day_offset: int = 1) -> str:
    """
    Obtém previsão do tempo.

    day_offset:
    0 = hoje
    1 = amanhã
    2 = depois de amanhã
    3+ = dias seguintes
    """

    city_key = city.lower().strip()
    lat, lon = CITY_COORDS.get(city_key, CITY_COORDS["lisboa"])

    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lon}"
        "&daily=temperature_2m_max,temperature_2m_min"
        "&timezone=Europe/Lisbon"
    )

    r = requests.get(url, timeout=WEATHER_TIMEOUT_SECONDS)
    r.raise_for_status()
    data = r.json()

    # Limitar day_offset ao intervalo disponível
    max_days = len(data.get("daily", {}).get("temperature_2m_max", [])) - 1
    if max_days < 0:
        raise ValueError("Dados de temperatura não disponíveis no serviço de previsão")

    if day_offset < 0:
        day_offset = 0
    elif day_offset > max_days:
        day_offset = max_days

    temp_max = data["daily"]["temperature_2m_max"][day_offset]
    temp_min = data["daily"]["temperature_2m_min"][day_offset]

    day_names = ["hoje", "amanhã", "depois de amanhã"]
    day_label = day_names[day_offset] if day_offset < len(day_names) else f"daqui a {day_offset} dias"

    day_label_title = day_label.capitalize()

    templates = [
        "{day_label_title} em {city}, espera-se uma temperatura entre {temp_min}°C e {temp_max}°C.",
        "Para {city}, {day_label} a previsão indica entre {temp_min}°C e {temp_max}°C.",
        "{day_label_title} em {city} deve ficar de {temp_min}°C a {temp_max}°C, com clima confortável.",
        "A previsão para {city} ({day_label}) é de {temp_min}°C a {temp_max}°C.",
        "Parece que {city} terá {temp_min}°C a {temp_max}°C {day_label}.",
    ]

    template = random.choice(templates)

    return template.format(
        day_label=day_label,
        day_label_title=day_label_title,
        city=city.title(),
        temp_min=temp_min,
        temp_max=temp_max,
    )
