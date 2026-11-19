"""Draw the guest quirk badge icons (#661).

python3 tools/build_quirk_badges.py
Each badge is a 64 px cream disc with a dark brown rim and one bold pictogram,
the same two colours the mood dot's "!" uses, so a badge never reads as a mood
colour. The disc is baked in: the in-game view only shows the texture.
Files land in assets/made/icons/quirk_<hint>.png, one per GuestQuirk.icon hint.
A new quirk draws its pictogram here and points GuestQuirk.badge at the file.
No downloaded source, fonts or Godot process is used.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "made" / "icons"
SIZE = 64
SS = 8  # supersample factor
CREAM = (243, 230, 204, 255)
INK = (59, 42, 32, 255)
CLEAR = (0, 0, 0, 0)


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE * SS, SIZE * SS), CLEAR)
    draw = ImageDraw.Draw(image)
    s = SS
    draw.ellipse((1 * s, 1 * s, 63 * s, 63 * s), fill=INK)
    draw.ellipse((4.5 * s, 4.5 * s, 59.5 * s, 59.5 * s), fill=CREAM)
    return image, draw


def box(draw: ImageDraw.ImageDraw, x1: float, y1: float, x2: float, y2: float, r: float, fill) -> None:
    draw.rounded_rectangle((x1 * SS, y1 * SS, x2 * SS, y2 * SS), radius=r * SS, fill=fill)


def circle(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    draw.ellipse(((cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS), fill=fill)


def camera() -> Image.Image:
    image, draw = canvas()
    box(draw, 20, 14, 38, 24, 4, INK)       # viewfinder bump
    box(draw, 9, 20, 55, 49, 7, INK)       # body
    circle(draw, 32, 35, 12, CREAM)      # lens ring
    circle(draw, 32, 35, 7, INK)        # lens
    circle(draw, 47, 27, 2.6, CREAM)      # flash
    return image


def chat() -> Image.Image:
    image, draw = canvas()
    box(draw, 8, 12, 56, 44, 11, INK)       # bubble
    draw.polygon([(16 * SS, 40 * SS), (34 * SS, 40 * SS), (17 * SS, 55 * SS)], fill=INK)  # tail
    for cx in (21, 32, 43):
        circle(draw, cx, 28, 4.2, CREAM)    # speech dots
    return image


def watch() -> Image.Image:
    image, draw = canvas()
    circle(draw, 32, 32, 24, INK)           # clock rim
    circle(draw, 32, 32, 18.5, CREAM)       # face
    draw.line((32 * SS, 32 * SS, 32 * SS, 19 * SS), fill=INK, width=int(5.5 * SS))  # long hand
    draw.line((32 * SS, 32 * SS, 42 * SS, 38 * SS), fill=INK, width=int(5.5 * SS))  # short hand
    circle(draw, 32, 19.5, 2.7, INK)
    circle(draw, 42, 38, 2.7, INK)
    circle(draw, 32, 32, 4, INK)
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for hint, painter in (("camera", camera), ("chat", chat), ("watch", watch)):
        painter().resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"quirk_{hint}.png")
        print("wrote", OUT / f"quirk_{hint}.png")


if __name__ == "__main__":
    main()
