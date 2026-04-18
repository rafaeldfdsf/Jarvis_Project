"""
Text-to-Speech (fala do assistente).

Responsabilidade:
- Converter texto em audio MP3 em base64
- Usar o mesmo provider OpenAI ja usado na transcricao
"""

import base64

from openai import OpenAI

from config import (
    OPENAI_TIMEOUT_SECONDS,
    OPENAI_TTS_INSTRUCTIONS,
    OPENAI_TTS_MODEL,
    OPENAI_TTS_VOICE,
)
from logging_utils import get_logger, log_event

client = OpenAI(timeout=OPENAI_TIMEOUT_SECONDS)
logger = get_logger(__name__)


def synthesize_speech(text: str) -> str:
    clean_text = (text or '').strip()
    if not clean_text:
        raise ValueError('Texto vazio para TTS.')

    response = client.audio.speech.create(
        model=OPENAI_TTS_MODEL,
        voice=OPENAI_TTS_VOICE,
        input=clean_text,
        instructions=OPENAI_TTS_INSTRUCTIONS,
        response_format='mp3',
    )

    audio_base64 = base64.b64encode(response.read()).decode('utf-8')
    log_event(
        logger,
        20,
        'tts_synthesized',
        input_length=len(clean_text),
        model=OPENAI_TTS_MODEL,
        voice=OPENAI_TTS_VOICE,
        audio_base64_length=len(audio_base64),
    )
    return audio_base64
