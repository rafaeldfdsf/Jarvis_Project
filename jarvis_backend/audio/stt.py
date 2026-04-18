import os
import queue
import tempfile

import numpy as np
import sounddevice as sd
import soundfile as sf
import webrtcvad

from openai import OpenAI
from audio.signals import beep
from config import OPENAI_TIMEOUT_SECONDS, OPENAI_TRANSCRIPTION_MODEL, SAMPLE_RATE
from logging_utils import get_logger, log_event


# cliente OpenAI
client = OpenAI(timeout=OPENAI_TIMEOUT_SECONDS)
logger = get_logger(__name__)

# VAD (detector de fala)
vad = webrtcvad.Vad(2)


def calibrate_noise():
    """
    Mantido apenas para compatibilidade com main.py.
    """
    return 1


# -----------------------------
# Transcrição com Whisper
# -----------------------------
def transcribe(audio):

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:

        path = f.name
        sf.write(path, audio, SAMPLE_RATE)

    try:

        with open(path, "rb") as file:

            result = client.audio.transcriptions.create(
                model=OPENAI_TRANSCRIPTION_MODEL,
                file=file,
                language="pt"
            )

        return result.text.strip()

    except Exception as exc:
        log_event(logger, 40, "stt_failed", error=str(exc))
        return None

    finally:

        if os.path.exists(path):
            os.remove(path)


# -----------------------------
# Ouvir comando com VAD
# -----------------------------
def listen(_voice_threshold=None):

    print("🎤 Fala...")

    q = queue.Queue()

    def callback(indata, frames, time_info, status):

        if status:
            print(status)

        q.put(indata.copy())

    frame_duration_ms = 30
    frame_size = int(SAMPLE_RATE * frame_duration_ms / 1000)

    max_silence_frames = 20
    pre_buffer_max = 10

    pre_buffer = []
    recorded_frames = []

    speech_started = False
    silence_count = 0

    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="int16",
        blocksize=frame_size,
        callback=callback
    ):

        while True:

            chunk = q.get()

            if not speech_started:

                pre_buffer.append(chunk)

                if len(pre_buffer) > pre_buffer_max:
                    pre_buffer.pop(0)

            is_speech = vad.is_speech(chunk.tobytes(), SAMPLE_RATE)

            if not speech_started:

                if is_speech:

                    speech_started = True

                    recorded_frames.extend(pre_buffer)
                    recorded_frames.append(chunk)

                    pre_buffer.clear()

            else:

                recorded_frames.append(chunk)

                if is_speech:
                    silence_count = 0
                else:
                    silence_count += 1

                    if silence_count >= max_silence_frames:
                        break

    if not recorded_frames:
        return None

    audio = np.concatenate(recorded_frames, axis=0)
    audio_float = audio.astype(np.float32) / 32768.0

    text = transcribe(audio_float)

    if not text:
        return None

    log_event(logger, 20, "stt_transcribed", transcript_length=len(text))
    print(f"Tu: {text}")

    return text
