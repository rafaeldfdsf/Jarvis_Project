import sounddevice as sd
import numpy as np
from scipy.io.wavfile import write

fs = 16000
print("🎤 Fala durante 3 segundos...")
audio = sd.rec(int(3 * fs), samplerate=fs, channels=1)
sd.wait()

write("teste.wav", fs, audio)
print("✅ Gravado em teste.wav")