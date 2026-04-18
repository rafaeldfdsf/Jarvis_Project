"""
Sinais sonoros curtos.

Responsabilidade:
- Sons de feedback (ex: beep quando começa a ouvir)

Não contém TTS nem lógica de voz.
"""

import numpy as np
import simpleaudio as sa
from config import SAMPLE_RATE

def beep():
    """
    Emite um beep curto para indicar que a escuta começou.

    Útil para feedback imediato ao utilizador.
    """
    freq = 880      # frequência do tom (Hz)
    duration = 0.08 # duração em segundos
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), False)
    tone = np.sin(freq * t * 2 * np.pi)
    audio = np.int16(tone / np.max(np.abs(tone)) * 32767)
    sa.play_buffer(audio, 1, 2, SAMPLE_RATE)