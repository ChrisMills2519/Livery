"""Synthesise the judge's bell for the showground.

    python3 tools/build_arena_bell.py

Writes assets/sounds/ui/arena_bell.wav: a short struck bell with inharmonic
partials and a soft strike transient.  The file is generated rather than
sampled so it carries no licensing questions and can be rebuilt exactly.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 1.6
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sounds", "ui", "arena_bell.wav")

# (frequency, amplitude, decay rate)
PARTIALS = (
    (932.0, 0.50, 3.2),
    (1398.0, 0.28, 4.4),
    (1864.0, 0.18, 6.0),
    (2796.0, 0.10, 9.0),
    (466.0, 0.22, 2.4),
)


def build():
    rng = random.Random(7)
    frames = []
    total = int(RATE * DURATION)
    for i in range(total):
        t = i / RATE
        value = 0.0
        for freq, amp, decay in PARTIALS:
            value += amp * math.sin(2.0 * math.pi * freq * t) * math.exp(-decay * t)
        # Strike noise, very short, gives the bell its "clack" at the start.
        if t < 0.03:
            value += rng.uniform(-1.0, 1.0) * 0.22 * (1.0 - t / 0.03)
        value *= 1.0 - math.exp(-t * 260.0)
        value = max(-1.0, min(1.0, value * 0.72))
        frames.append(int(value * 32767.0))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(RATE)
        fh.writeframes(b"".join(struct.pack("<h", f) for f in frames))
    print("wrote %s (%d frames)" % (OUT, len(frames)))


if __name__ == "__main__":
    build()
