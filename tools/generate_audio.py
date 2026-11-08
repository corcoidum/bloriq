"""BLORIQ용 원본 합성 음원 생성기. 외부 샘플은 사용하지 않는다."""
import math
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b''.join(int(max(-1, min(1, x)) * 32767).to_bytes(2, 'little', signed=True) for x in samples))


def tone(frequency, duration, volume=.3, decay=5, bell=True):
    result = []
    for i in range(round(RATE * duration)):
        t = i / RATE
        attack = min(1, t / .012)
        release = min(1, (duration - t) / .055)
        env = attack * release * math.exp(-decay * t)
        wave1 = math.sin(2 * math.pi * frequency * t)
        overtone = .22 * math.sin(2 * math.pi * frequency * 2.01 * t) if bell else 0
        result.append(volume * env * (wave1 + overtone))
    return result


def mix(destination, source, at):
    start = round(at * RATE)
    for i, value in enumerate(source):
        if start + i < len(destination):
            destination[start + i] += value


def cue(name, duration, notes):
    samples = [0.] * round(duration * RATE)
    for at, frequency, length, volume in notes:
        mix(samples, tone(frequency, length, volume), at)
    write(name, samples)


cue('move.wav', .20, [(0, 650, .17, .28), (.035, 980, .12, .08)])
cue('echo.wav', .34, [(0, 784, .28, .16), (.07, 1174.66, .20, .09)])
cue('blocked.wav', .23, [(0, 330, .20, .22), (.045, 261.63, .14, .10)])
cue('gate.wav', .45, [(0, 659.25, .30, .20), (.13, 987.77, .30, .18)])
cue('complete.wav', 1.30, [(0, 523.25, .30, .19), (.15, 659.25, .30, .20), (.30, 783.99, .35, .21), (.47, 1046.5, .65, .20)])

# 16초의 네 마디 아르페지오. 마지막 음의 잔향은 루프 경계에서 0으로 감쇠한다.
length = 16.0
music = [0.] * round(length * RATE)
chords = [
    [261.63, 329.63, 392.00, 523.25],
    [220.00, 261.63, 329.63, 440.00],
    [174.61, 220.00, 261.63, 349.23],
    [196.00, 246.94, 293.66, 392.00],
]
for bar, chord in enumerate(chords):
    for step in range(8):
        freq = chord[[0, 1, 2, 3, 2, 1, 2, 1][step]]
        mix(music, tone(freq, .48, .10, 3.5), bar * 4 + step * .5)
    mix(music, tone(chord[0] / 2, 3.85, .06, .6, False), bar * 4)
for i in range(len(music)):
    music[i] *= min(1., i / (RATE * .04), (len(music) - i) / (RATE * .08))
write('bgm.wav', music)
