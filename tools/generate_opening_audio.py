"""인트로 전용 12초 원본 celesta/pad. 외부 음원/추가 패키지 불필요."""
from pathlib import Path
import math
import wave
from array import array

RATE = 22050
DURATION = 12
samples = [0.0] * (RATE * DURATION)
# D major의 부드러운 아르페지오와 끝의 별문 화음.
notes = [(0.3, 293.665), (1.5, 440), (2.8, 587.33), (4.1, 369.994),
         (5.2, 493.883), (6.4, 659.255), (7.8, 440), (8.6, 587.33),
         (9.3, 739.989), (9.8, 880), (10.1, 1174.66)]
for start, hz in notes:
    for n in range(min(int(2.8 * RATE), len(samples) - int(start * RATE))):
        t = n / RATE
        env = min(1, t / 0.02) * math.exp(-2.0 * t)
        samples[int(start * RATE) + n] += .15 * env * (
            math.sin(2 * math.pi * hz * t) + .2 * math.sin(2 * math.pi * hz * 2.002 * t))
for n in range(len(samples)):
    t = n / RATE
    fade = min(1, t / 1.5, (12 - t) / 1.8)
    pad = sum(math.sin(2 * math.pi * hz * t) for hz in [146.832, 220, 293.665]) * .022
    samples[n] = max(-1, min(1, (samples[n] + pad) * fade))
out = Path(__file__).resolve().parents[1] / 'assets/audio/opening.wav'
with wave.open(str(out), 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(array('h', (round(v * 32767) for v in samples)).tobytes())
print(out)
