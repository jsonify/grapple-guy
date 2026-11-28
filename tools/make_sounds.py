#!/usr/bin/env python3
"""Generates Grapple Guy's sound effects as small mono WAV files (issue #20).

Pure standard library, deterministic (seeded noise). Re-run to tweak:
    python3 tools/make_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Sounds")
rng = random.Random(7)


def env(t, attack, decay):
    """Fast attack, exponential decay."""
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def write(name, samples, gain=0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * gain)) * 32767)) for s in samples)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def render(duration, fn):
    return [fn(i / RATE) for i in range(int(duration * RATE))]


def noise():
    return rng.uniform(-1, 1)


class LowPass:
    def __init__(self, cutoff):
        self.a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        self.y = 0.0

    def __call__(self, x, cutoff=None):
        if cutoff is not None:
            self.a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        self.y += self.a * (x - self.y)
        return self.y


# Rope shot: a quick rising "zip".
def shoot():
    phase = 0.0
    lp = LowPass(3000)
    out = []
    for i in range(int(0.14 * RATE)):
        t = i / RATE
        f = 600 + 2600 * (t / 0.14)
        phase += 2 * math.pi * f / RATE
        s = 0.5 * math.sin(phase) + 0.5 * lp(noise(), 1500 + 6000 * t / 0.14)
        out.append(s * env(t, 0.005, 0.05))
    return out


# Attach: a woody thunk.
def attach():
    def f(t):
        pitch = 140 * math.exp(-t * 12)
        return (math.sin(2 * math.pi * (90 + pitch) * t) * env(t, 0.002, 0.07)
                + 0.3 * noise() * env(t, 0.001, 0.01))
    return render(0.22, f)


# Clank: rope hits a wall (inharmonic metal).
def clank():
    partials = [(520, 1.0), (1370, 0.6), (2210, 0.4), (3170, 0.25)]
    def f(t):
        s = sum(a * math.sin(2 * math.pi * fr * t) for fr, a in partials)
        return s * env(t, 0.001, 0.06) + 0.4 * noise() * env(t, 0.001, 0.008)
    return render(0.3, f)


# Boost: a rising whoosh-chirp.
def boost():
    phase = 0.0
    lp = LowPass(800)
    out = []
    for i in range(int(0.35 * RATE)):
        t = i / RATE
        f = 300 + 900 * (t / 0.35) ** 2
        phase += 2 * math.pi * f / RATE
        swell = math.sin(math.pi * min(1, t / 0.35))
        s = 0.35 * math.sin(phase) + 0.8 * lp(noise(), 600 + 5000 * t / 0.35)
        out.append(s * swell)
    return out


# Gem: a bright two-note chime.
def gem():
    def note(t, freq, start):
        if t < start:
            return 0
        u = t - start
        return (math.sin(2 * math.pi * freq * u) + 0.3 * math.sin(2 * math.pi * freq * 2 * u)) * env(u, 0.003, 0.12)
    return render(0.4, lambda t: note(t, 1318.5, 0) + note(t, 1975.5, 0.07))


# Checkpoint: two rising notes.
def checkpoint():
    def note(t, freq, start):
        if t < start:
            return 0
        u = t - start
        return math.sin(2 * math.pi * freq * u) * env(u, 0.005, 0.15)
    return render(0.5, lambda t: note(t, 659.3, 0) + note(t, 987.8, 0.1))


# Crash: a thud plus a noisy crunch.
def crash():
    lp = LowPass(1200)
    out = []
    for i in range(int(0.5 * RATE)):
        t = i / RATE
        thud = math.sin(2 * math.pi * (55 + 80 * math.exp(-t * 20)) * t) * env(t, 0.002, 0.12)
        crunch = lp(noise(), 400 + 2500 * math.exp(-t * 8)) * env(t, 0.001, 0.09)
        out.append(thud + 1.2 * crunch)
    return out


# Finish: a short major arpeggio.
def finish():
    notes = [523.3, 659.3, 784.0, 1046.5]
    def f(t):
        s = 0
        for k, freq in enumerate(notes):
            start = k * 0.09
            if t >= start:
                u = t - start
                s += (math.sin(2 * math.pi * freq * u) + 0.25 * math.sin(2 * math.pi * freq * 3 * u)) * env(u, 0.005, 0.25 if k == 3 else 0.12)
        return s
    return render(0.9, f)


# Splash: a watery burst with bubbly blips (water hazard).
def splash():
    lp = LowPass(900)
    blips = [(0.05, 520), (0.11, 760), (0.17, 430), (0.24, 640)]
    out = []
    for i in range(int(0.6 * RATE)):
        t = i / RATE
        s = lp(noise(), 300 + 2500 * math.exp(-t * 6)) * env(t, 0.004, 0.18)
        for start, freq in blips:
            if t >= start:
                u = t - start
                s += 0.35 * math.sin(2 * math.pi * freq * (1 + 2 * u) * u) * env(u, 0.002, 0.04)
        out.append(s)
    return out


# Countdown: a short, clean beep for 3, 2, 1.
def countdown():
    def f(t):
        return (math.sin(2 * math.pi * 784.0 * t) + 0.2 * math.sin(2 * math.pi * 1568.0 * t)) * env(t, 0.004, 0.09)
    return render(0.25, f)


# Go: the same beep an octave up, longer and brighter.
def go():
    def f(t):
        s = math.sin(2 * math.pi * 1568.0 * t) + 0.35 * math.sin(2 * math.pi * 2352.0 * t)
        return s * env(t, 0.004, 0.28) * (1 + 0.15 * math.sin(2 * math.pi * 7 * t))
    return render(0.7, f)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("shoot", shoot(), 0.5)
    write("attach", attach(), 0.7)
    write("clank", clank(), 0.5)
    write("boost", boost(), 0.6)
    write("gem", gem(), 0.5)
    write("checkpoint", checkpoint(), 0.5)
    write("crash", crash(), 0.8)
    write("finish", finish(), 0.6)
    write("splash", splash(), 0.7)
    write("countdown", countdown(), 0.45)
    write("go", go(), 0.5)
    print("wrote", sorted(os.listdir(OUT)))
