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

# 구름바다의 16초 루프. 높은 종소리 아래로 낮은 화음을 길게 깐다.
cloud_sea = [0.] * round(length * RATE)
for bar, chord in enumerate([
    (293.66, 369.99, 440.00, 554.37, 659.25),
    (246.94, 293.66, 369.99, 440.00, 554.37),
    (196.00, 246.94, 293.66, 369.99, 440.00),
    (220.00, 277.18, 329.63, 440.00, 493.88),
]):
    for step, note in enumerate((0, 2, 4, 3, 1, 2)):
        start = bar * 4 + step * .6
        mix(cloud_sea, tone(chord[note] * 2, .88, .075, 3.2), start)
    for note in (0, 2):
        mix(cloud_sea, tone(chord[note] / 2, 3.9, .045, .52, False), bar * 4)
for i in range(len(cloud_sea)):
    cloud_sea[i] *= min(1., i / (RATE * .06), (len(cloud_sea) - i - 1) / (RATE * .12))
write('bgm_w2.wav', cloud_sea)

# 거울 호수의 16초 루프. 원래 음 뒤에 한 옥타브 낮은 답을 둔다.
mirror_lake = [0.] * round(length * RATE)
for bar, chord in enumerate([
    (220.00, 261.63, 329.63, 392.00),
    (174.61, 220.00, 261.63, 329.63),
    (130.81, 164.81, 196.00, 293.66),
    (196.00, 246.94, 293.66, 349.23),
]):
    base = bar * 4
    mix(mirror_lake, tone(chord[0] / 2, 3.88, .055, .54, False), base)
    for step, note in enumerate((0, 2, 3, 1)):
        start = base + step * .91
        mix(mirror_lake, tone(chord[note] * 2, 1.02, .083, 3.0), start)
        mix(mirror_lake, tone(chord[note], .66, .042, 3.8), start + .34)
for i in range(len(mirror_lake)):
    mirror_lake[i] *= min(1., i / (RATE * .06), (len(mirror_lake) - i - 1) / (RATE * .12))
write('bgm_w3.wav', mirror_lake)

# 시계탑의 12초 루프. 태엽 소리를 번갈아 놓고 그 위에 작은 종을 울린다.
clocktower = [0.] * (12 * RATE)
for beat in range(24):
    tick = 1510 if beat % 2 == 0 else 1140
    mix(clocktower, tone(tick, .085, .105, 42), beat * .5)
    mix(clocktower, tone(tick * 1.51, .045, .045, 53), beat * .5)
for bar, chord in enumerate([
    (220.00, 261.63, 329.63, 392.00),
    (174.61, 220.00, 261.63, 349.23),
    (196.00, 246.94, 293.66, 329.63),
]):
    base = bar * 4
    mix(clocktower, tone(chord[0] / 2, 3.9, .068, .63, False), base)
    for offset, note in [(0, 0), (.75, 2), (1.5, 1), (2.5, 3), (3.25, 2)]:
        mix(clocktower, tone(chord[note], .72, .12, 3.1), base + offset)
for i in range(len(clocktower)):
    clocktower[i] *= min(1., (len(clocktower) - i - 1) / (RATE * .05))
write('bgm_w4.wav', clocktower)

# 얼음 동굴의 16초 루프. 낮은 울림 위로 맑은 종이 드문드문 번진다.
ice_cave = [0.] * round(length * RATE)
for bar, (bass, first_bell, answer) in enumerate([
    (146.83, 587.33, 880.00),
    (130.81, 523.25, 783.99),
    (116.54, 698.46, 587.33),
    (110.00, 440.00, 659.25),
]):
    start = bar * 4
    mix(ice_cave, tone(bass, 3.88, .06, .58, False), start)
    mix(ice_cave, tone(first_bell, 2.95, .15, 1.45), start)
    mix(ice_cave, tone(first_bell * 2.76, .69, .032, 5.5, False), start)
    mix(ice_cave, tone(answer, 2.08, .091, 1.68), start + 1.78)
for i in range(len(ice_cave)):
    ice_cave[i] *= min(1., i / (RATE * .045), (len(ice_cave) - i - 1) / (RATE * .10))
write('bgm_w5.wav', ice_cave)
