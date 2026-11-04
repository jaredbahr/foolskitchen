#!/usr/bin/env python3
"""Builds the made kitchen ambience loops in assets/made/audio/ (#117).

The Kenney audio packs have no kitchen ambience, so these four quiet loops are
made here from seeded noise. Each loop is shaped in the frequency domain over
its whole length, so it repeats without a seam. Short events (crackles,
bubbles) wrap around the loop end for the same reason.

Run from the repository root (needs numpy and ffmpeg):
    python3 tools/make_kitchen_audio.py
The output is deterministic for a given numpy version; the .ogg files are
committed, so the game never runs this script.
"""
from __future__ import annotations

import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path("assets/made/audio")


def shaped_noise(rng: np.random.Generator, seconds: float, shape) -> np.ndarray:
    """White noise with spectrum `shape(freqs)`; circular, so it loops cleanly."""
    n = int(RATE * seconds)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    out = np.fft.irfft(spectrum * shape(freqs), n)
    return out / (np.abs(out).max() + 1e-12)


def band(freqs: np.ndarray, low: float, high: float, slope: float = 2.0) -> np.ndarray:
    """A smooth band-pass gain between `low` and `high` Hz."""
    rise = 1.0 / (1.0 + (low / np.maximum(freqs, 1.0)) ** (2 * slope))
    fall = 1.0 / (1.0 + (freqs / high) ** (2 * slope))
    return rise * fall


def add_events(signal: np.ndarray, rng: np.random.Generator, count: int, make) -> None:
    """Adds `count` short events at seeded times, wrapping past the loop end."""
    n = signal.size
    for _ in range(count):
        event = make(rng)
        start = int(rng.integers(0, n))
        idx = (start + np.arange(event.size)) % n
        signal[idx] += event


def crackle(rng: np.random.Generator) -> np.ndarray:
    length = int(RATE * rng.uniform(0.002, 0.008))
    decay = np.exp(-np.linspace(0.0, 6.0, length))
    pop = rng.standard_normal(length) * decay * rng.uniform(0.3, 1.0)
    # A short moving average takes the harsh top off each pop.
    return np.convolve(pop, np.ones(5) / 5.0, mode="same")


def bubble(rng: np.random.Generator) -> np.ndarray:
    length = int(RATE * rng.uniform(0.03, 0.08))
    t = np.arange(length) / RATE
    pitch = rng.uniform(180.0, 420.0) * (1.0 + 0.8 * t / t[-1])  # bubbles rise in pitch
    phase = 2.0 * np.pi * np.cumsum(pitch) / RATE
    envelope = np.sin(np.pi * t / t[-1]) ** 2
    return np.sin(phase) * envelope * rng.uniform(0.2, 0.6)


def sizzle(rng: np.random.Generator) -> np.ndarray:
    """A pan of food on a stove: bright hiss with sparse fat crackles."""
    hiss = shaped_noise(rng, 4.0, lambda f: band(f, 1800.0, 6500.0)) * 0.35
    add_events(hiss, rng, 260, crackle)
    return hiss


def fryer(rng: np.random.Generator) -> np.ndarray:
    """A deep fryer: denser bubbling over a softer, lower hiss."""
    base = shaped_noise(rng, 4.0, lambda f: band(f, 700.0, 4000.0)) * 0.3
    add_events(base, rng, 520, crackle)
    add_events(base, rng, 70, bubble)
    return base


def coffee(rng: np.random.Generator) -> np.ndarray:
    """An espresso machine: steady steam hiss with a low gurgle."""
    steam = shaped_noise(rng, 4.0, lambda f: band(f, 3500.0, 11000.0)) * 0.3
    add_events(steam, rng, 40, bubble)
    return steam


def room_tone(rng: np.random.Generator) -> np.ndarray:
    """A busy room far away: low, soft rumble with a faint murmur band."""
    rumble = shaped_noise(rng, 8.0, lambda f: band(f, 60.0, 400.0, 1.5))
    murmur = shaped_noise(rng, 8.0, lambda f: band(f, 300.0, 1400.0, 2.0))
    # Slow swells in the murmur, built from whole cycles so the loop stays seamless.
    t = np.arange(rumble.size) / RATE
    swell = 0.6 + 0.4 * np.sin(2.0 * np.pi * t / 8.0) * np.sin(2.0 * np.pi * 3.0 * t / 8.0)
    return rumble * 0.6 + murmur * 0.35 * swell


LOOPS = {
    "stove_sizzle": (1171, sizzle, -14.0),
    "fryer_bubble": (2203, fryer, -14.0),
    "coffee_steam": (3307, coffee, -16.0),
    "room_tone": (4409, room_tone, -20.0),
}


def write_ogg(name: str, samples: np.ndarray, peak_db: float) -> None:
    scaled = samples / (np.abs(samples).max() + 1e-12) * (10.0 ** (peak_db / 20.0))
    pcm = (np.clip(scaled, -1.0, 1.0) * 32767.0).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis",
                        "-q:a", "4", "-map_metadata", "-1", "-fflags", "+bitexact",
                        str(OUT / f"{name}.ogg")], check=True)


def main() -> None:
    for name, (seed, build, peak_db) in LOOPS.items():
        write_ogg(name, build(np.random.default_rng(seed)), peak_db)
        print(f"wrote {OUT / name}.ogg")


if __name__ == "__main__":
    main()
