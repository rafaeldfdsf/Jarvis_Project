import queue
from time import time, sleep
import sounddevice as sd
import numpy as np
from faster_whisper import WhisperModel
from silero_vad import load_silero_vad, get_speech_timestamps
from audio.signals import beep
from config import SAMPLE_RATE
from rapidfuzz import fuzz

# carregar VAD
vad_model = load_silero_vad()

# whisper local (modelo pequeno e rápido)
model = WhisperModel("tiny", device="cpu", compute_type="int8")

def wait_for_wake_word():

    print("🎤 A ouvir palavra de ativação...")

    q = queue.Queue()

    # buffer para acumular áudio
    audio_buffer = []

    def callback(indata, frames, time_info, status):
        q.put(indata.copy())

    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="float32",
        blocksize=1600,   # ~100ms
        callback=callback
    ):

        while True:

            chunk = q.get().flatten()

            audio_buffer.append(chunk)

            # manter apenas últimos ~2 segundos
            if len(audio_buffer) > 8:
                audio_buffer.pop(0)

            audio = np.concatenate(audio_buffer)

            # evitar áudio muito curto
            if len(audio) < SAMPLE_RATE * 0.5:
                continue

            # verificar se há fala
            speech = get_speech_timestamps(
                audio,
                vad_model,
                sampling_rate=SAMPLE_RATE
            )

            if not speech:
                continue

            # transcrever
            segments, _ = model.transcribe(
                audio,
                language="pt",
                vad_filter=False
            )

            for segment in segments:

                text = segment.text.lower().strip()

                print("detected:", text)

                score = fuzz.partial_ratio(text, "jarvis")

                if score > 70:
                    print("🔔 Jarvis detectado")
                    beep()
                    sd.sleep(500)
                    audio_buffer.clear()
                    sleep(1.5)
                    return