"""Синтез звуковых эффектов игры (без внешних сэмплов).

Запуск из корня проекта:  python3 tool/gen_sfx.py
Результат: assets/sfx/*.wav (44.1 кГц, моно, 16 бит).
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def osc(freq, dur, partials=((1, 1.0),), decay=6.0, attack=0.003, vibrato=0.0):
    """Сумма гармоник с экспоненциальным затуханием. freq — число или функция от t."""
    t = t_axis(dur)
    f = freq(t) if callable(freq) else np.full_like(t, float(freq))
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = np.zeros_like(t)
    for k, a in partials:
        sig += a * np.sin(k * phase) * np.exp(-decay * (k ** 0.5 - 1) * t)
    env = np.minimum(t / attack, 1.0) * np.exp(-decay * t)
    return sig * env


def noise(dur, decay=20.0, attack=0.002):
    t = t_axis(dur)
    env = np.minimum(t / attack, 1.0) * np.exp(-decay * t)
    return rng.uniform(-1, 1, len(t)) * env


def lowpass(sig, cutoff):
    """Однополюсный ФНЧ; cutoff — число или массив (для свипа)."""
    out = np.zeros_like(sig)
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), sig.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = 0.0
    for i, x in enumerate(sig):
        y += a[i] * (x - y)
        out[i] = y
    return out


def highpass(sig, cutoff):
    return sig - lowpass(sig, cutoff)


def place_at(total, part, start):
    i = int(start * SR)
    end = min(len(total), i + len(part))
    total[i:end] += part[: end - i]
    return total


def mix(*parts):
    total = np.zeros(max(len(p) for p in parts))
    for p in parts:
        total[: len(p)] += p
    return total


def echo(sig, delays=((0.07, 0.28), (0.13, 0.16), (0.21, 0.08))):
    out = np.concatenate([sig, np.zeros(int(SR * 0.3))])
    for d, g in delays:
        place_at(out, sig * g, d)
    return out


def save(name, sig, peak=0.85):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * peak
    fade = min(len(sig), int(SR * 0.008))
    sig[-fade:] *= np.linspace(1, 0, fade)
    data = (sig * 32767).astype('<i2')
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


BELL = ((1, 1.0), (2, 0.42), (3, 0.18), (4.16, 0.1), (5.43, 0.05))
SOFT = ((1, 1.0), (2, 0.25), (3, 0.08))


def note(semi, base=523.25):
    return base * 2 ** (semi / 12)


def gen_pick():
    s = mix(osc(lambda t: 620 + 2600 * t, 0.07, SOFT, decay=45),
            0.3 * highpass(noise(0.02, 200), 2500))
    save('pick', s, 0.55)


def gen_place():
    body = osc(lambda t: 95 + 140 * np.exp(-t * 55), 0.16, ((1, 1), (2, 0.3)), decay=28, attack=0.001)
    wood = osc(720, 0.05, ((1, 1), (2.7, 0.4)), decay=70, attack=0.0005)
    click = lowpass(noise(0.03, 160, 0.0003), 3500)
    s = mix(body, 0.35 * wood, 0.5 * click)
    save('place', s, 0.8)


PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31]


def gen_clear(level):
    """Колокольчики-арпеджио: чем выше комбо, тем выше и ярче."""
    total = np.zeros(int(SR * 0.9))
    root = level - 1
    steps = [root, root + 2, root + 4]
    for i, st in enumerate(steps):
        n = osc(note(PENTA[st] - 5), 0.7, BELL, decay=5.5, attack=0.002)
        place_at(total, n * (0.8 + 0.1 * i), 0.055 * i)
    sparkle = highpass(noise(0.5, 9), 5000) * 0.12
    place_at(total, sparkle, 0.02)
    # плотный «хлопок» блоков
    pop = lowpass(noise(0.08, 60, 0.0005), 1800) * 0.5
    total = place_at(total, pop, 0)
    save(f'clear{level}', echo(total, ((0.09, 0.18), (0.18, 0.08))), 0.8)


def gen_great():
    total = np.zeros(int(SR * 1.3))
    sweep_cut = np.linspace(400, 6000, int(SR * 0.35))
    whoosh = lowpass(noise(0.35, 4, 0.12), sweep_cut) * 0.9
    place_at(total, whoosh, 0)
    for i, st in enumerate([0, 4, 7, 12, 16]):
        place_at(total, osc(note(st), 0.9, BELL, decay=3.5) * 0.55, 0.22 + 0.035 * i)
    place_at(total, highpass(noise(0.7, 5), 6000) * 0.1, 0.22)
    save('great', echo(total), 0.8)


def gen_bad():
    total = np.zeros(int(SR * 0.3))
    for i, f in enumerate([196, 164.8]):
        tone = osc(f, 0.13, ((1, 1), (3, 0.3), (5, 0.12)), decay=22)
        place_at(total, lowpass(tone, 1400), 0.1 * i)
    save('bad', total, 0.5)


def gen_over():
    total = np.zeros(int(SR * 1.6))
    for i, st in enumerate([7, 4, 0, -5]):
        tone = osc(note(st, 392), 0.55, SOFT, decay=4.5, vibrato=0.004)
        place_at(total, lowpass(tone, 2500) * (1 - 0.1 * i), 0.19 * i)
    save('over', echo(total), 0.7)


def gen_record():
    total = np.zeros(int(SR * 1.9))
    seq = [0, 4, 7, 12]
    for i, st in enumerate(seq):
        place_at(total, osc(note(st), 0.35, BELL, decay=7) * 0.8, 0.1 * i)
    for st in [0, 4, 7, 12, 16]:
        brass = osc(note(st, 523.25), 1.3, ((1, 1), (2, 0.5), (3, 0.3), (4, 0.15)), decay=2.2,
                    attack=0.03, vibrato=0.006)
        place_at(total, lowpass(brass, 3200) * 0.4, 0.42)
    place_at(total, highpass(noise(1.0, 3), 6500) * 0.12, 0.42)
    save('record', echo(total), 0.85)


def gen_levelup():
    total = np.zeros(int(SR * 1.3))
    for i, st in enumerate([0, 2, 4, 7, 9, 12, 14, 16, 19, 24]):
        place_at(total, osc(note(st), 0.4, BELL, decay=9) * 0.6, 0.045 * i)
    place_at(total, osc(note(24), 0.9, BELL, decay=3) * 0.5, 0.45)
    place_at(total, highpass(noise(0.8, 4), 6000) * 0.12, 0.3)
    save('levelup', echo(total), 0.8)


def gen_tap():
    s = mix(osc(1350, 0.05, SOFT, decay=80, attack=0.0008),
            0.25 * lowpass(noise(0.015, 300, 0.0003), 4000))
    save('tap', s, 0.45)


def gen_deal():
    cut = np.linspace(4500, 700, int(SR * 0.22))
    s = lowpass(noise(0.22, 9, 0.04), cut)
    save('deal', s, 0.35)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    gen_pick()
    gen_place()
    for lvl in range(1, 9):
        gen_clear(lvl)
    gen_great()
    gen_bad()
    gen_over()
    gen_record()
    gen_levelup()
    gen_tap()
    gen_deal()
    print('ok:', sorted(os.listdir(OUT)))
