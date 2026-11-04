#!/usr/bin/env python3
"""Builds the jukebox's three made music loops in assets/made/audio/ (#294).

Diner rock (a boogie bass, chopped guitar and a straight backbeat over a
12-bar blues in A), Cafe jazz (a walking bass, soft electric piano and brushes
over a ii-V-I turnaround in C) and Bar blues (a slow shuffle in E with a thin
organ and a few guitar licks). Every note, drum hit and pause is written out
below, and the only noise (drum hiss) comes from a fixed-seed generator, so the
output is the same on every run. Whatever rings past the last bar wraps round
to the first, so each loop repeats without a seam. They are mono, 22.05 kHz
and rolled off above 7 kHz for a warm, small-speaker sound, and are mixed to a
low peak: the game plays them quietly behind the room.

Run from the repository root (needs numpy and ffmpeg):
    python3 tools/make_jukebox_music.py
The .ogg files are committed, so the game never runs this script.
"""
from __future__ import annotations

import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path("assets/made/audio")
SWING = 0.62  # where the off-beat eighth falls inside its beat (0.5 is straight)


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


class Track:
    """A loop of whole bars; anything past the end wraps to the start."""

    def __init__(self, bpm: float, bars: int, seed: int) -> None:
        self.beat = 60.0 / bpm
        self.bars = bars
        self.size = int(round(bars * 4 * self.beat * RATE))
        self.buf = np.zeros(self.size)
        self.rng = np.random.default_rng(seed)

    def put(self, beat: float, sound: np.ndarray, gain: float = 1.0) -> None:
        start = int(round(beat * self.beat * RATE))
        idx = (start + np.arange(sound.size)) % self.size
        np.add.at(self.buf, idx, sound * gain)

    def swung(self, beat: float) -> float:
        """Beat position of an eighth: off-beats are pushed late by the swing."""
        whole = np.floor(beat)
        frac = beat - whole
        return whole + (SWING if abs(frac - 0.5) < 1e-9 else frac)

    def seconds(self, beats: float) -> float:
        return beats * self.beat


def envelope(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / RATE
    return np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / decay)


def tone(freq: float, seconds: float, partials, attack: float, decay: float) -> np.ndarray:
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    wave_ = sum(amp * np.sin(2.0 * np.pi * freq * mult * t) for mult, amp in partials)
    return wave_ * envelope(n, attack, decay)


def bass(freq: float, seconds: float) -> np.ndarray:
    return tone(freq, seconds, [(1, 1.0), (2, 0.45), (3, 0.18)], 0.008, seconds * 0.55)


def pluck(freq: float, seconds: float) -> np.ndarray:
    parts = [(1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.2), (6, 0.1)]
    return tone(freq, seconds, parts, 0.003, seconds * 0.35)


def epiano(freq: float, seconds: float) -> np.ndarray:
    body = tone(freq, seconds, [(1, 1.0), (2, 0.25)], 0.01, seconds * 0.9)
    tine = tone(freq, seconds, [(5, 0.18), (7, 0.07)], 0.002, 0.12)
    return body + tine


def organ(freq: float, seconds: float) -> np.ndarray:
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    wave_ = sum(a * np.sin(2.0 * np.pi * freq * m * t) for m, a in [(1, 1.0), (2, 0.7), (3, 0.35), (4, 0.2)])
    swell = np.minimum(1.0, t / 0.06) * np.minimum(1.0, (seconds - t) / 0.12)
    return wave_ * swell * (0.85 + 0.15 * np.sin(2.0 * np.pi * 5.5 * t))


def lead(freq: float, seconds: float) -> np.ndarray:
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    vib = 1.0 + 0.008 * np.sin(2.0 * np.pi * 5.0 * t) * np.minimum(1.0, t / 0.25)
    phase = 2.0 * np.pi * np.cumsum(freq * vib) / RATE
    wave_ = np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase)
    return wave_ * envelope(n, 0.01, seconds * 0.7)


def kick(track: Track) -> np.ndarray:
    n = int(0.22 * RATE)
    t = np.arange(n) / RATE
    freq = 45.0 + 80.0 * np.exp(-t / 0.035)
    return np.sin(2.0 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.09)


def hat(track: Track, length: float = 0.05) -> np.ndarray:
    n = int(length * RATE)
    noise = track.rng.standard_normal(n)
    noise = np.diff(noise, prepend=0.0)  # tilts the hiss towards the highs
    return noise * np.exp(-np.arange(n) / RATE / (length * 0.3))


def snare(track: Track, soft: bool = False) -> np.ndarray:
    n = int(0.16 * RATE)
    t = np.arange(n) / RATE
    noise = track.rng.standard_normal(n) * np.exp(-t / 0.045)
    body = np.sin(2.0 * np.pi * 190.0 * t) * np.exp(-t / 0.05)
    return (noise * 0.6 + body * 0.5) * (0.5 if soft else 1.0)


def brush(track: Track) -> np.ndarray:
    n = int(0.14 * RATE)
    t = np.arange(n) / RATE
    noise = track.rng.standard_normal(n)
    return noise * np.minimum(1.0, t / 0.03) * np.exp(-t / 0.07)


def ride(track: Track) -> np.ndarray:
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    ring = sum(np.sin(2.0 * np.pi * f * t) for f in (3100.0, 4370.0, 5230.0)) * 0.12
    tick = track.rng.standard_normal(n) * np.exp(-t / 0.01) * 0.5
    return (ring + tick) * np.exp(-t / 0.12)


def finish(track: Track, name: str, peak_db: float = -4.0, rolloff_hz: float = 7000.0) -> None:
    spectrum = np.fft.rfft(track.buf)
    freqs = np.fft.rfftfreq(track.size, 1.0 / RATE)
    spectrum *= 1.0 / (1.0 + (freqs / rolloff_hz) ** 4)
    spectrum[0] = 0.0
    out = np.fft.irfft(spectrum, track.size)
    out = np.tanh(out / (np.abs(out).max() + 1e-12) * 1.4) / np.tanh(1.4)  # gentle glue, no clipping
    out *= 10.0 ** (peak_db / 20.0) / (np.abs(out).max() + 1e-12)
    pcm = (np.clip(out, -1.0, 1.0) * 32767.0).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis",
                        "-q:a", "2", "-map_metadata", "-1", "-fflags", "+bitexact",
                        str(OUT / f"{name}.ogg")], check=True)
    print(f"wrote {OUT / name}.ogg  {track.size / RATE:.1f} s")


def diner_rock() -> Track:
    track = Track(bpm=150.0, bars=12, seed=2941)
    roots = {"A": 45, "D": 50, "E": 52}
    bars = "AAAADDAAEDAE"
    boogie = [0, 4, 7, 9, 10, 9, 7, 4]
    for bar, chord in enumerate(bars):
        root = roots[chord]
        base = bar * 4.0
        for step, interval in enumerate(boogie):
            beat = track.swung(base + step * 0.5)
            track.put(beat, bass(hz(root + interval), track.seconds(0.45)), 0.9)
        for beat in (1.0, 3.0):  # chopped guitar on the 2 and 4
            for interval in (12, 16, 19, 22):
                track.put(base + beat, pluck(hz(root + interval), 0.16), 0.11)
        track.put(base + 0.0, kick(track), 0.8)
        track.put(base + 2.0, kick(track), 0.7)
        track.put(base + 1.0, snare(track), 0.5)
        track.put(base + 3.0, snare(track), 0.5)
        for step in range(8):
            track.put(track.swung(base + step * 0.5), hat(track), 0.12 if step % 2 else 0.2)
    return track


def cafe_jazz() -> Track:
    track = Track(bpm=96.0, bars=8, seed=5303)
    # (bar, beat in bar, beats long, root, third, chord tones for the piano, melody)
    chords = [
        (0, 0, 4, 38, 3, [53, 57, 60, 64], [74, 72, 69, 72]),
        (1, 0, 4, 43, 4, [53, 59, 62, 65], [71, 74, 71, 67]),
        (2, 0, 4, 36, 4, [52, 55, 59, 62], [72, 76, 74, 72]),
        (3, 0, 4, 45, 3, [55, 60, 64, 67], [76, 72, 69, 72]),
        (4, 0, 4, 38, 3, [53, 57, 60, 64], [74, 77, 74, 72]),
        (5, 0, 4, 43, 4, [53, 59, 62, 65], [71, 67, 71, 74]),
        (6, 0, 2, 36, 4, [52, 55, 59, 62], [72, 76]),
        (6, 2, 2, 45, 4, [55, 57, 61, 64], [73, 69]),
        (7, 0, 2, 38, 3, [53, 57, 60, 64], [74, 69]),
        (7, 2, 2, 43, 4, [53, 59, 62, 65], [71, 67]),
    ]
    for index, (bar, start, length, root, third, tones, melody) in enumerate(chords):
        base = bar * 4.0 + start
        next_root = chords[(index + 1) % len(chords)][3]
        approach = next_root - 1 if next_root >= root else next_root + 1
        walk = [root, root + third, root + 7, approach] if length == 4 else [root, approach]
        for step, midi in enumerate(walk):
            track.put(base + step, bass(hz(midi), track.seconds(0.95)), 0.8)
        for beat in (0.0, 1.5):  # comping: on the 1 and the "and" of 2
            if beat < length:
                for midi in tones:
                    track.put(base + track.swung(beat), epiano(hz(midi), track.seconds(1.6)), 0.09)
        for step, midi in enumerate(melody):  # a soft line, spread evenly over the chord
            beat = base + step * (length / len(melody))
            track.put(beat, epiano(hz(midi), track.seconds(1.4)), 0.075)
    for bar in range(8):
        base = bar * 4.0
        for beat in (1.0, 3.0):
            track.put(base + beat, brush(track), 0.14)
        for beat in (0.0, 1.0, 1.5, 2.0, 3.0, 3.5):
            track.put(track.swung(base + beat), ride(track), 0.07)
    return track


def bar_blues() -> Track:
    track = Track(bpm=120.0, bars=12, seed=7127)
    roots = {"E": 40, "A": 45, "B": 47}
    bars = "EEEEAAEEBAEB"
    phrases = {  # bar -> [(beat, midi, beats long)]  E minor pentatonic over E7, A7 and B7
        0: [(0.0, 76, 1.0), (1.5, 79, 0.5), (2.0, 76, 1.5)],
        1: [(0.0, 74, 1.0), (1.0, 71, 2.0)],
        4: [(0.0, 76, 1.0), (1.0, 81, 0.5), (1.5, 79, 0.5), (2.0, 76, 1.0)],
        5: [(0.0, 76, 2.0), (2.5, 74, 1.5)],
        8: [(0.0, 78, 1.0), (1.0, 76, 1.0), (2.0, 74, 2.0)],
        9: [(0.0, 76, 1.0), (1.0, 72, 1.0), (2.0, 71, 2.0)],
        11: [(0.0, 71, 1.0), (1.0, 74, 1.0), (2.0, 76, 2.0)],
    }
    for bar, chord in enumerate(bars):
        root = roots[chord]
        base = bar * 4.0
        for step, interval in enumerate([0, 0, 7, 10]):
            track.put(base + step, bass(hz(root + interval), track.seconds(0.9)), 0.85)
        for interval in (12, 16, 19, 22):  # a thin organ chord held through the bar
            track.put(base, organ(hz(root + interval), track.seconds(3.9)), 0.05)
        track.put(base + 0.0, kick(track), 0.6)
        track.put(base + 2.0, kick(track), 0.5)
        for beat in (1.0, 3.0):
            track.put(base + beat, snare(track, soft=True), 0.4)
        for step in range(4):
            track.put(base + step, hat(track), 0.14)
            track.put(track.swung(base + step + 0.5), hat(track), 0.08)
        for beat, midi, length in phrases.get(bar, []):
            track.put(base + beat, lead(hz(midi), track.seconds(length)), 0.09)
    return track


def main() -> None:
    finish(diner_rock(), "jukebox_diner_rock")
    finish(cafe_jazz(), "jukebox_cafe_jazz")
    finish(bar_blues(), "jukebox_bar_blues")


if __name__ == "__main__":
    main()
