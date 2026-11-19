"""Draw the city screen's illustrated paper map (#642).

python3 tools/build_city_map.py
A hand-drawn paper map open on the owner's desk (docs/CITY_MAP.md T1): flat
Kenney-style shapes, the UI's cream and dark-brown inks, a coffee ring and a few
doodles. Neighbourhood names, positions and roads are read from
data/city/city_map.tres, so the art follows the data: run this again after
moving a neighbourhood or a road.
Everything is deterministic: one fixed seed, no clock, no downloaded source and
no fonts (the lettering is a small stroke font drawn here and wobbled by the
seed, so it looks hand-lettered).

Files land in assets/made/city_map/:
  paper_map.png     the desk, the paper, patches, roads, names, doodles (3:2)
  pin_<state>.png   a shop pin: here, managed, closed, renovating, needs
  pin_for_sale.png, pin_locked.png   a lot's board
  roadworks.png     cones, a "Road closed" barrier and a digger (an area waiting on a tier)
  hoarding.png      a "Coming soon" fence with a painted preview (an area with no lot yet)
  van.png           the little red delivery van that rides the map road between shops (T5)
"""
from __future__ import annotations

import math
import random
import re
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "made" / "city_map"
DATA = ROOT / "data" / "city" / "city_map.tres"

SEED = 642
MAP_W, MAP_H = 1500, 1000   # final size, 3:2
SS = 2                      # supersample for the map
PIN = 160                   # final pin sprite size
PSS = 4

# The UI's own inks (main_theme.tres) plus a few flat map colours.
INK = (59, 42, 32)
CREAM = (243, 230, 204)
PAPER = (240, 226, 196)
PAPER_DARK = (222, 204, 168)
DESK = (150, 104, 70)
DESK_DARK = (122, 82, 54)
HARD_SHADOW = (50, 33, 37)
LAND = (206, 214, 150)
LAND_DARK = (182, 196, 126)
SEA = (118, 182, 196)
SEA_LIGHT = (176, 218, 222)
SAND = (238, 212, 150)
ROAD = (252, 246, 228)
RED = (196, 72, 56)
ORANGE = (200, 116, 58)
YELLOW = (240, 196, 72)
GREEN_DARK = (84, 128, 84)
WOOD = (150, 104, 70)
PATCH = {
    "old_town": (236, 196, 148),
    "millbrook": (176, 208, 126),
    "seafront": (244, 220, 160),
    "skyline": (178, 194, 212),
    "pinewood": (128, 172, 112),
}
DEFAULT_PATCH = (214, 200, 170)


def shadow(alpha: int = 90) -> tuple:
    return HARD_SHADOW + (alpha,)


# ---------------------------------------------------------------- stroke font
def arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int = 14) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


# Capitals on a 4 x 6 grid (y down). Each glyph is a list of strokes.
P_BOWL = [(0, 6), (0, 0), (2.4, 0), (3.7, 0.8), (3.7, 2.4), (2.4, 3.2), (0, 3.2)]
GLYPHS: dict[str, list[list[tuple[float, float]]]] = {
    "A": [[(0, 6), (2, 0), (4, 6)], [(0.9, 4), (3.1, 4)]],
    "B": [[(0, 0), (0, 6), (2.6, 6), (3.8, 5.2), (3.8, 3.9), (2.6, 3), (0, 3)],
          [(0, 0), (2.4, 0), (3.6, 0.7), (3.6, 2.2), (2.4, 3), (0, 3)]],
    "C": [arc(2.2, 3, 2.2, 3, 40, 320)],
    "D": [[(0, 0), (0, 6), (1.8, 6), (3.6, 5), (4, 3), (3.6, 1), (1.8, 0), (0, 0)]],
    "E": [[(4, 0), (0, 0), (0, 6), (4, 6)], [(0, 3), (3, 3)]],
    "F": [[(4, 0), (0, 0), (0, 6)], [(0, 3), (3, 3)]],
    "G": [arc(2.1, 3, 2.1, 3, 35, 360) + [(2.3, 3.1)]],
    "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
    "I": [[(0.6, 0), (3.4, 0)], [(2, 0), (2, 6)], [(0.6, 6), (3.4, 6)]],
    "J": [[(4, 0), (4, 4.2)] + arc(2.3, 4.2, 1.7, 1.8, 0, 160, 8)],
    "K": [[(0, 0), (0, 6)], [(4, 0), (0, 3.6)], [(1.4, 2.6), (4, 6)]],
    "L": [[(0, 0), (0, 6), (4, 6)]],
    "M": [[(0, 6), (0, 0), (2, 3.8), (4, 0), (4, 6)]],
    "N": [[(0, 6), (0, 0), (4, 6), (4, 0)]],
    "O": [arc(2, 3, 2, 3, 0, 360, 20)],
    "P": [P_BOWL],
    "Q": [arc(2, 3, 2, 3, 0, 360, 20), [(2.5, 4.4), (4, 6.5)]],
    "R": [P_BOWL, [(1.8, 3.2), (4, 6)]],
    "S": [[(3.8, 0.9), (2.6, 0), (1.2, 0), (0.2, 0.9), (0.2, 2.2), (1.2, 3), (2.8, 3), (3.8, 3.8),
           (3.8, 5.1), (2.8, 6), (1.4, 6), (0.2, 5.1)]],
    "T": [[(0, 0), (4, 0)], [(2, 0), (2, 6)]],
    "U": [[(0, 0), (0, 4)] + arc(2, 4, 2, 2, 180, 0, 10) + [(4, 0)]],
    "V": [[(0, 0), (2, 6), (4, 0)]],
    "W": [[(0, 0), (1, 6), (2, 2.4), (3, 6), (4, 0)]],
    "X": [[(0, 0), (4, 6)], [(4, 0), (0, 6)]],
    "Y": [[(0, 0), (2, 3), (4, 0)], [(2, 3), (2, 6)]],
    "Z": [[(0, 0), (4, 0), (0, 6), (4, 6)]],
}
ADVANCE = {"I": 3.6, "W": 5.0, "M": 4.8, " ": 3.0}
GAP = 1.4


def text_width(text: str, cap: float) -> float:
    unit = cap / 6.0
    return (sum(ADVANCE.get(ch, 4.0) for ch in text) + GAP * (len(text) - 1)) * unit


# ------------------------------------------------------------------- the data
def read_data() -> tuple[dict, list[dict]]:
    text = DATA.read_text()
    areas: dict[str, dict] = {}
    for block in re.findall(r'\[sub_resource type="Resource" id="[^"]+"\]\n(script = ExtResource\("2_area"\)\n.*?)\n\n', text, re.S):
        area_id = re.search(r'^id = &"([^"]+)"', block, re.M).group(1)
        name = re.search(r'^display_name = "([^"]+)"', block, re.M).group(1)
        x, y = re.search(r"map_position = Vector2\(([\d.]+), ([\d.]+)\)", block).groups()
        areas[area_id] = {"name": name, "pos": (float(x), float(y))}
    roads: list[dict] = []
    for block in re.findall(r'\[sub_resource type="Resource" id="[^"]+"\]\n(script = ExtResource\("3_road"\)\n.*?)\n\n', text, re.S):
        a = re.search(r'^from = &"([^"]+)"', block, re.M).group(1)
        b = re.search(r'^to = &"([^"]+)"', block, re.M).group(1)
        raw = re.search(r"bends = PackedVector2Array\(([^)]*)\)", block)
        nums = [float(n) for n in re.findall(r"[\d.]+", raw.group(1))] if raw else []
        roads.append({"from": a, "to": b, "bends": list(zip(nums[0::2], nums[1::2]))})
    return areas, roads


def smooth(points: list[tuple[float, float]], per: int = 16) -> list[tuple[float, float]]:
    """A Catmull-Rom curve through the points (the van's road)."""
    if len(points) < 3:
        return points
    pts = [points[0]] + points + [points[-1]]
    out: list[tuple[float, float]] = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(per):
            t = s / per
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                                    + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t ** 3) for k in (0, 1)))
    out.append(points[-1])
    return out


def shade(color, amount: float):
    return tuple(max(0, min(255, round(c * amount))) for c in color[:3])


def blob(cx: float, cy: float, rx: float, ry: float, rng: random.Random, wob: float = 0.1, n: int = 72):
    p = [rng.uniform(0, 6.28) for _ in range(3)]
    pts = []
    for i in range(n):
        a = 6.2832 * i / n
        r = 1 + wob * math.sin(2 * a + p[0]) + wob * 0.7 * math.sin(3 * a + p[1]) + wob * 0.4 * math.sin(5 * a + p[2])
        pts.append((cx + rx * r * math.cos(a), cy + ry * r * math.sin(a)))
    return pts


class Canvas:
    """A supersampled drawing surface; every call takes final-pixel units."""

    def __init__(self, w: int, h: int, scale: int, bg=(0, 0, 0, 0)):
        self.w, self.h, self.s = w, h, scale
        self.image = Image.new("RGBA", (w * scale, h * scale), bg)
        self.d = ImageDraw.Draw(self.image, "RGBA")

    def _sc(self, pts):
        return [(x * self.s, y * self.s) for x, y in pts]

    def poly(self, pts, fill, outline=None, width: float = 0):
        self.d.polygon(self._sc(pts), fill=fill)
        if outline is not None and width > 0:
            closed = list(pts) + [pts[0], pts[1]]
            self.d.line(self._sc(closed), fill=outline, width=round(width * self.s), joint="curve")

    def rect(self, x1, y1, x2, y2, fill, outline=None, width: float = 0, r: float = 0):
        box = (x1 * self.s, y1 * self.s, x2 * self.s, y2 * self.s)
        ow = round(width * self.s) if outline else 0
        if r > 0:
            self.d.rounded_rectangle(box, radius=r * self.s, fill=fill, outline=outline, width=ow)
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=ow)

    def ellipse(self, cx, cy, rx, ry, fill, outline=None, width: float = 0):
        self.d.ellipse(((cx - rx) * self.s, (cy - ry) * self.s, (cx + rx) * self.s, (cy + ry) * self.s),
                       fill=fill, outline=outline, width=round(width * self.s) if outline else 0)

    def line(self, pts, fill, width: float, caps: bool = True):
        self.d.line(self._sc(pts), fill=fill, width=max(1, round(width * self.s)), joint="curve")
        if caps:
            r = width * self.s / 2
            for x, y in (pts[0], pts[-1]):
                self.d.ellipse((x * self.s - r, y * self.s - r, x * self.s + r, y * self.s + r), fill=fill)

    def letters(self, text: str, cx: float, cy: float, cap: float, fill, rng: random.Random,
                weight: float = 0.17, wobble: float = 0.1) -> None:
        """Hand-lettered capitals centred on (cx, cy); `cap` is the cap height."""
        unit = cap / 6.0
        x = cx - text_width(text, cap) / 2.0
        width = max(2, cap * weight)
        for ch in text:
            adv = ADVANCE.get(ch, 4.0)
            if ch in GLYPHS:
                tilt = math.radians(rng.uniform(-3.5, 3.5))
                gx, gy = x + adv * unit / 2.0, cy + rng.uniform(-0.24, 0.24) * unit
                for stroke in GLYPHS[ch]:
                    pts = []
                    for px, py in stroke:
                        ox = (px + rng.uniform(-wobble, wobble) - 2.0) * unit
                        oy = (py + rng.uniform(-wobble, wobble) - 3.0) * unit
                        pts.append((gx + ox * math.cos(tilt) - oy * math.sin(tilt),
                                    gy + ox * math.sin(tilt) + oy * math.cos(tilt)))
                    self.line(pts, fill, width)
            x += (adv + GAP) * unit

    def finish(self) -> Image.Image:
        return self.image.resize((self.w, self.h), Image.LANCZOS)


# ------------------------------------------------------------- map decorations
def tree(c: Canvas, x: float, y: float, size: float, color=GREEN_DARK, pine: bool = False) -> None:
    c.ellipse(x, y + size * 0.15, size * 0.55, size * 0.22, shadow())
    c.rect(x - size * 0.08, y - size * 0.1, x + size * 0.08, y + size * 0.18, (120, 80, 56), INK, 2)
    if pine:
        for k in range(3):
            yy = y - size * (0.1 + 0.34 * k)
            w = size * (0.5 - 0.1 * k)
            c.poly([(x - w, yy), (x + w, yy), (x, yy - size * 0.55)], shade(color, 1.0 + 0.08 * k), INK, 2)
    else:
        c.ellipse(x, y - size * 0.45, size * 0.46, size * 0.42, color, INK, 2)
        c.ellipse(x - size * 0.14, y - size * 0.55, size * 0.16, size * 0.13, shade(color, 1.25))


def house(c: Canvas, x: float, y: float, w: float, h: float, wall, roof) -> None:
    c.ellipse(x, y + 2, w * 0.62, h * 0.2, shadow())
    c.rect(x - w / 2, y - h, x + w / 2, y, wall, INK, 2)
    c.poly([(x - w * 0.6, y - h), (x + w * 0.6, y - h), (x, y - h * 1.55)], roof, INK, 2)
    c.rect(x - w * 0.12, y - h * 0.5, x + w * 0.12, y, (120, 80, 56), INK, 1.5)
    c.rect(x - w * 0.4, y - h * 0.8, x - w * 0.2, y - h * 0.58, (250, 226, 150), INK, 1.5)


def tower(c: Canvas, x: float, y: float, w: float, h: float, color) -> None:
    c.rect(x + 4, y - h + 4, x + w + 4, y, shadow(80))
    c.rect(x, y - h, x + w, y, color, INK, 2)
    for r in range(int(h // 16)):
        for col in range(max(1, int(w // 14))):
            c.rect(x + 5 + col * 13, y - h + 8 + r * 16, x + 11 + col * 13, y - h + 14 + r * 16,
                   (236, 244, 252) if (r + col) % 3 else (250, 226, 150))


def mill(c: Canvas, x: float, y: float, s: float) -> None:
    c.ellipse(x, y + 3, s * 0.7, s * 0.16, shadow())
    c.poly([(x - s * 0.4, y), (x + s * 0.4, y), (x + s * 0.28, y - s * 0.9), (x - s * 0.28, y - s * 0.9)],
           (240, 226, 196), INK, 2)
    c.poly([(x - s * 0.36, y - s * 0.9), (x + s * 0.36, y - s * 0.9), (x, y - s * 1.3)], (176, 84, 64), INK, 2)
    c.rect(x - s * 0.08, y - s * 0.3, x + s * 0.08, y, (120, 80, 56), INK, 1.5)
    hub = (x, y - s * 0.62)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        end = (hub[0] + math.cos(a) * s * 0.7, hub[1] + math.sin(a) * s * 0.7)
        c.line([hub, end], INK, 3)
        mx, my = hub[0] + (end[0] - hub[0]) * 0.65, hub[1] + (end[1] - hub[1]) * 0.65
        c.rect(mx - 4, my - 4, mx + 4, my + 4, (250, 244, 228), INK, 1)
    c.ellipse(hub[0], hub[1], 4, 4, INK)


def umbrella(c: Canvas, x: float, y: float, color) -> None:
    c.ellipse(x, y + 2, 14, 4, shadow(80))
    c.line([(x, y), (x, y - 20)], INK, 2.5)
    c.poly(arc(x, y - 20, 17, 11, 180, 360, 10), color, INK, 2)


def wave(c: Canvas, x: float, y: float, w: float) -> None:
    c.line([(x + i, y + math.sin(i / w * 9.4) * 3) for i in range(0, int(w) + 1, 4)], SEA_LIGHT, 3)


def draw_desk(c: Canvas, rng: random.Random) -> None:
    c.rect(0, 0, MAP_W, MAP_H, DESK)
    y = 0
    while y < MAP_H:
        h = rng.randint(70, 130)
        c.rect(0, y, MAP_W, y + 3, DESK_DARK)
        for _ in range(7):
            gx, gy = rng.uniform(0, MAP_W), y + rng.uniform(8, h - 8)
            c.line([(gx, gy), (gx + rng.uniform(60, 220), gy + rng.uniform(-2, 2))],
                   shade(DESK, rng.choice([0.93, 1.07])), 2)
        y += h


def coast_y(u: float) -> float:
    """The shoreline's y at x fraction u across the frame (a bay in the south-west)."""
    base = 905 + 14 * math.sin(u * 9)
    return base - max(0.0, 0.2 - u) / 0.2 * 330


def build_map(areas: dict, roads: list[dict]) -> Image.Image:
    rng = random.Random(SEED)
    c = Canvas(MAP_W, MAP_H, SS)
    draw_desk(c, rng)
    # The paper, with a hard drop shadow (light from the upper left).
    c.rect(36, 36, MAP_W - 16, MAP_H - 12, shadow(110), r=14)
    c.rect(26, 24, MAP_W - 26, MAP_H - 24, PAPER, INK, 4, r=14)
    fx1, fy1, fx2, fy2 = 62, 56, MAP_W - 62, MAP_H - 56
    c.rect(fx1, fy1, fx2, fy2, LAND, INK, 4, r=10)
    for _ in range(190):
        tx, ty = rng.uniform(fx1 + 14, fx2 - 14), rng.uniform(fy1 + 14, fy2 - 14)
        c.line([(tx - 5, ty), (tx, ty - 7), (tx + 5, ty)], LAND_DARK, 2.5)
    # The sea along the bottom and into the south-west bay, clipped to the frame.
    coast = [(fx1 + (fx2 - fx1) * t / 100, coast_y(t / 100)) for t in range(0, 101, 3)]
    sea_mask = Image.new("L", c.image.size, 0)
    ImageDraw.Draw(sea_mask).polygon([(x * SS, y * SS) for x, y in coast + [(fx2, fy2), (fx1, fy2)]], fill=255)
    frame_mask = Image.new("L", c.image.size, 0)
    ImageDraw.Draw(frame_mask).rounded_rectangle((fx1 * SS, fy1 * SS, fx2 * SS, fy2 * SS), radius=10 * SS, fill=255)
    c.image.paste(Image.new("RGBA", c.image.size, SEA + (255,)), (0, 0), ImageChops.multiply(sea_mask, frame_mask))
    c.d = ImageDraw.Draw(c.image, "RGBA")
    c.line(coast, SAND, 14, caps=False)
    c.line(coast, INK, 3, caps=False)
    c.rect(fx1, fy1, fx2, fy2, None, INK, 4, r=10)
    for _ in range(9):
        wave(c, rng.uniform(fx1 + 200, fx2 - 150), rng.uniform(chosen_wave_y(), 936), 80)
    wave(c, 90, 700, 50)
    wave(c, 110, 800, 60)
    # Neighbourhood patches, kept inside the frame.
    patches = Canvas(MAP_W, MAP_H, SS)
    for aid, area in areas.items():
        ax, ay = area["pos"][0] * MAP_W, area["pos"][1] * MAP_H
        color = PATCH.get(aid, DEFAULT_PATCH)
        cy = min(max(ay + 85, fy1 + 150), fy2 - 140)
        pts = blob(ax, cy, 205, 150, rng)
        patches.poly([(x + 6, y + 8) for x, y in pts], shadow(70))
        patches.poly(pts, color, shade(color, 0.55), 5)
        inner = blob(ax, cy, 186, 134, random.Random(SEED + len(aid)), 0.1)
        patches.line(inner + [inner[0]], shade(color, 0.86), 2)
    patches.image.putalpha(ImageChops.multiply(patches.image.getchannel("A"), frame_mask))
    c.image.alpha_composite(patches.image)
    c.d = ImageDraw.Draw(c.image, "RGBA")
    # Roads, under the names.
    for road in roads:
        a, b = areas[road["from"]]["pos"], areas[road["to"]]["pos"]
        pts = [(a[0] * MAP_W, a[1] * MAP_H)] + [(x * MAP_W, y * MAP_H) for x, y in road["bends"]] \
            + [(b[0] * MAP_W, b[1] * MAP_H)]
        curve = smooth(pts)
        c.line(curve, INK, 30)
        c.line(curve, ROAD, 22)
        acc = 0.0
        for i in range(len(curve) - 1):
            acc += math.dist(curve[i], curve[i + 1])
            if int(acc // 14) % 2 == 0:
                c.line([curve[i], curve[i + 1]], (216, 178, 120), 3, caps=False)
    deco = Canvas(MAP_W, MAP_H, SS)
    decor(deco, areas, rng)
    deco.image.putalpha(ImageChops.multiply(deco.image.getchannel("A"), frame_mask))
    c.image.alpha_composite(deco.image)
    c.d = ImageDraw.Draw(c.image, "RGBA")
    # Name banners with hand lettering.
    for area in areas.values():
        ax, ay = area["pos"][0] * MAP_W, area["pos"][1] * MAP_H
        text = area["name"].upper()
        cap = 44
        half = text_width(text, cap) / 2 + 26
        c.rect(ax - half + 5, ay - 40 + 6, ax + half + 5, ay + 40 + 6, shadow(110), r=10)
        c.rect(ax - half, ay - 40, ax + half, ay + 40, CREAM, INK, 4, r=10)
        c.letters(text, ax, ay, cap, INK, rng, 0.15)
    compass(c, 1380, 780)
    doodles(c)
    coffee_ring(c)
    creases(c)
    return c.finish()


def chosen_wave_y() -> float:
    return 922.0


def decor(c: Canvas, areas: dict, rng: random.Random) -> None:
    """Small flat scenery round each name, clear of the name banner and the pin band below it."""
    def at(aid, dx, dy):
        a = areas[aid]
        return a["pos"][0] * MAP_W + dx, a["pos"][1] * MAP_H + dy

    if "old_town" in areas:
        for dx, dy, w, h, wall, roof in [(-150, -62, 44, 34, (250, 238, 214), RED), (-92, -66, 40, 32, (232, 200, 150), (84, 112, 148)),
                                         (96, -62, 46, 36, (250, 238, 214), ORANGE), (150, -50, 38, 30, (232, 200, 150), RED),
                                         (-170, 62, 40, 30, (250, 238, 214), (84, 112, 148)), (200, 90, 42, 32, (232, 200, 150), ORANGE)]:
            house(c, *at("old_town", dx, dy), w, h, wall, roof)
        tree(c, *at("old_town", 30, -66), 40)
    if "millbrook" in areas:
        mill(c, *at("millbrook", -120, -62), 66)
        for dx, dy in [(40, -64), (110, -76), (190, -30), (-175, 48)]:
            tree(c, *at("millbrook", dx, dy), 40)
        x, y = at("millbrook", 0, 150)
        stream = [(x - 190, y - 10), (x - 90, y + 14), (x, y - 4), (x + 110, y + 20), (x + 200, y)]
        c.line(stream, SEA, 12)
        c.line(stream, SEA_LIGHT, 4)
    if "seafront" in areas:
        for dx, dy, col in [(-175, -20, RED), (190, -10, (84, 150, 190)), (-130, -88, YELLOW), (120, -92, RED)]:
            umbrella(c, *at("seafront", dx, dy), col)
    if "skyline" in areas:
        for dx, dy, w, h, col in [(-130, -48, 44, 120, (150, 170, 196)), (-80, -48, 52, 160, (168, 186, 208)),
                                  (-20, -48, 38, 100, (140, 160, 188)), (28, -48, 50, 140, (150, 170, 196)),
                                  (88, -48, 40, 96, (168, 186, 208)), (150, 36, 46, 120, (150, 170, 196))]:
            tower(c, *at("skyline", dx, dy), w, h, col)
    if "pinewood" in areas:
        for dx, dy in [(-200, 10), (-160, 60), (190, 0), (225, 50), (-150, -48), (170, -50), (-215, 100), (250, 110), (80, -56), (-70, -58)]:
            tree(c, *at("pinewood", dx, dy), 52, (72, 118, 84), pine=True)


def compass(c: Canvas, x: float, y: float) -> None:
    c.ellipse(x, y, 60, 60, CREAM, INK, 4)
    for ang, big in [(0, True), (90, False), (180, False), (270, False)]:
        a = math.radians(ang - 90)
        length = 50 if big else 40
        tip = (x + math.cos(a) * length, y + math.sin(a) * length)
        left = (x + math.cos(a + 1.57) * 9, y + math.sin(a + 1.57) * 9)
        right = (x + math.cos(a - 1.57) * 9, y + math.sin(a - 1.57) * 9)
        c.poly([tip, left, right], RED if big else INK, INK, 2)
    c.ellipse(x, y, 6, 6, CREAM, INK, 2)
    c.letters("N", x, y - 80, 26, INK, random.Random(SEED + 9), 0.2)


def doodles(c: Canvas) -> None:
    pencil = (92, 80, 76, 230)
    # A Golden Ladle sketched in the margin.
    x, y = 760, 830
    c.line([(x - 6, y - 4), (x + 40, y - 96)], pencil, 7)
    c.line([(x - 6, y - 4), (x + 40, y - 96)], (240, 196, 72), 3)
    c.poly(arc(x - 14, y - 6, 24, 24, 0, 180, 12), (240, 196, 72, 240), pencil, 3)
    c.line([(x + 6, y - 6), (x - 34, y - 6)], pencil, 3)
    # A dotted route along the shore, a fish and a little sun.
    pts = [(640, 925), (700, 915), (780, 930), (860, 918), (930, 928)]
    for i in range(len(pts) - 1):
        for t in range(0, 10, 2):
            u0, u1 = t / 10, (t + 1) / 10
            p = (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * u0, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * u0)
            q = (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * u1, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * u1)
            c.line([p, q], pencil, 3)
    fx, fy = 150, 780
    c.poly(arc(fx, fy, 22, 11, 0, 360, 14), (252, 238, 206, 230), pencil, 3)
    c.poly([(fx + 20, fy), (fx + 36, fy - 10), (fx + 36, fy + 10)], (252, 238, 206, 230), pencil, 3)
    c.ellipse(fx - 10, fy - 3, 2, 2, pencil)
    sx, sy = 112, 112
    c.ellipse(sx, sy, 20, 20, (252, 222, 120, 230), pencil, 3)
    for k in range(10):
        a = math.radians(k * 36)
        c.line([(sx + 26 * math.cos(a), sy + 26 * math.sin(a)), (sx + 38 * math.cos(a), sy + 38 * math.sin(a))], pencil, 3)
    c.ellipse(sx - 7, sy - 4, 2, 2, pencil)
    c.ellipse(sx + 7, sy - 4, 2, 2, pencil)
    c.line(arc(sx, sy + 2, 9, 7, 20, 160, 8), pencil, 2.5)
    # A star.
    star = []
    for k in range(10):
        r = 20 if k % 2 == 0 else 8
        a = math.radians(-90 + k * 36)
        star.append((1390 + r * math.cos(a), 470 + r * math.sin(a)))
    c.poly(star, (240, 196, 72, 235), pencil, 3)
    # A pencil on the desk edge.
    c.poly([(1060, 968), (1250, 956), (1252, 974), (1062, 984)], YELLOW, INK, 3)
    c.poly([(1060, 968), (1030, 976), (1062, 984)], (240, 214, 168), INK, 3)
    c.poly([(1030, 976), (1018, 977), (1030, 972)], INK)


def coffee_ring(c: Canvas) -> None:
    ring = (120, 80, 48, 120)
    cx, cy = 1250, 880
    pts = []
    for i in range(0, 361, 6):
        a = math.radians(i)
        pts.append((cx + (58 + 2.5 * math.sin(a * 3) + (3 if i < 40 else 0)) * math.cos(a),
                    cy + (58 + 2.5 * math.sin(a * 3) + (3 if i < 40 else 0)) * math.sin(a)))
    c.line(pts, ring, 7, caps=False)
    c.line([(cx + 49 * math.cos(math.radians(i)), cy + 49 * math.sin(math.radians(i))) for i in range(30, 300, 8)],
           (120, 80, 48, 60), 3)
    c.ellipse(cx + 70, cy + 44, 5, 5, ring)
    c.ellipse(cx + 82, cy + 58, 3, 3, ring)


def creases(c: Canvas) -> None:
    c.line([(MAP_W / 2, 30), (MAP_W / 2, MAP_H - 30)], (150, 128, 90, 22), 3, caps=False)
    c.line([(MAP_W / 2 + 3, 30), (MAP_W / 2 + 3, MAP_H - 30)], (255, 250, 232, 34), 2, caps=False)


# ------------------------------------------------------------------------ pins
def pin_canvas() -> Canvas:
    return Canvas(PIN, PIN, PSS)


def ground_shadow(c: Canvas, cx: float, y: float, rx: float) -> None:
    c.ellipse(cx, y, rx, rx * 0.22, shadow(120))


def shop_body(c: Canvas, state: str) -> None:
    """A small shopfront, standing on the pin's lower middle."""
    x1, x2, base, top = 32, 128, 140, 62
    ground_shadow(c, 80, base + 2, 54)
    wall, awn_a, awn_b = (250, 238, 214), RED, (250, 244, 228)
    if state == "closed":
        wall, awn_a, awn_b = (214, 204, 186), (150, 140, 130), (190, 182, 170)
    c.rect(x1, top, x2, base, wall, INK, 4)
    c.rect(x1 - 4, top - 14, x2 + 4, top + 4, shade(wall, 0.9), INK, 4)
    sw = (x2 - x1 + 8) / 6
    for i in range(6):
        xa = x1 - 4 + i * sw
        c.poly([(xa, top + 2), (xa + sw, top + 2), (xa + sw - 1, top + 30), (xa + 1, top + 30)],
               awn_a if i % 2 == 0 else awn_b, INK, 3)
    window = (252, 222, 130) if state in ("managed", "here") else ((190, 196, 200) if state == "closed" else (176, 206, 220))
    c.rect(x1 + 10, top + 40, x1 + 40, base - 12, window, INK, 3)
    c.rect(x2 - 36, top + 36, x2 - 8, base, (120, 110, 100) if state == "closed" else (140, 96, 64), INK, 3)
    c.ellipse(x2 - 14, base - 22, 2.5, 2.5, (190, 190, 190) if state == "closed" else YELLOW)


def badge_here(c: Canvas) -> None:
    c.line([(100, 48), (100, 8)], INK, 5)
    c.poly([(100, 8), (138, 20), (100, 34)], RED, INK, 3)
    c.ellipse(100, 8, 4, 4, YELLOW, INK, 2)


def badge_open_sign(c: Canvas) -> None:
    c.rect(54, 108, 86, 126, (84, 150, 130), INK, 3, r=3)
    c.line([(60, 117), (80, 117)], CREAM, 3)


def badge_closed(c: Canvas) -> None:
    c.rect(34, 98, 126, 140, (176, 182, 188), INK, 4)
    for yy in range(106, 138, 7):
        c.line([(36, yy), (124, yy)], (130, 138, 148), 2.5, caps=False)
    c.rect(34, 98, 126, 106, (150, 158, 168), INK, 3)
    web = (110, 100, 96)
    for ang in (0, 25, 50, 75, 90):
        a = math.radians(ang)
        c.line([(36, 66), (36 + 40 * math.cos(a), 66 + 40 * math.sin(a))], web, 1.8, caps=False)
    for r in (14, 26, 38):
        c.line([(36 + r * math.cos(math.radians(k)), 66 + r * math.sin(math.radians(k))) for k in range(0, 91, 15)],
               web, 1.8, caps=False)


def badge_renovating(c: Canvas) -> None:
    for x in (30, 76, 126):
        c.line([(x, 142), (x, 36)], (176, 130, 84), 6)
    for y in (58, 94, 128):
        c.rect(24, y, 132, y + 9, (214, 168, 108), INK, 3)
    c.line([(30, 128), (76, 94)], (176, 130, 84), 5)
    c.line([(76, 128), (126, 94)], (176, 130, 84), 5)
    c.poly(arc(112, 40, 20, 18, 180, 360, 10), YELLOW, INK, 3)
    c.rect(88, 38, 138, 46, (224, 168, 40), INK, 3, r=3)


def badge_needs(c: Canvas) -> None:
    c.poly([(100, 54), (122, 54), (116, 74)], RED, INK, 3)
    c.rect(78, 8, 146, 62, RED, INK, 4, r=14)
    c.poly([(102, 56), (120, 56), (116, 66)], RED)
    c.line([(112, 20), (112, 40)], CREAM, 7)
    c.ellipse(112, 51, 4.5, 4.5, CREAM)


def pin_shop(state: str) -> Image.Image:
    c = pin_canvas()
    shop_body(c, "closed" if state == "renovating" else state)
    {"here": badge_here, "managed": badge_open_sign, "closed": badge_closed,
     "renovating": badge_renovating, "needs": badge_needs}[state](c)
    return c.finish()


def pin_for_sale() -> Image.Image:
    c = pin_canvas()
    ground_shadow(c, 80, 146, 40)
    c.rect(36, 44, 44, 148, WOOD, INK, 3)
    c.rect(116, 44, 124, 148, WOOD, INK, 3)
    c.rect(18, 24, 142, 44, RED, INK, 4, r=3)
    c.rect(24, 44, 136, 112, CREAM, INK, 4, r=3)
    r = random.Random(SEED + 31)
    c.letters("FOR", 80, 66, 20, INK, r, 0.18)
    c.letters("SALE", 80, 94, 20, RED, r, 0.18)
    return c.finish()


def pin_locked() -> Image.Image:
    c = pin_canvas()
    ground_shadow(c, 80, 146, 44)
    c.rect(30, 52, 130, 146, (170, 130, 92), INK, 4, r=4)
    for yy in (82, 114):
        c.line([(32, yy), (128, yy)], (120, 86, 58), 2.5, caps=False)
    c.line([(30, 98), (130, 98)], INK, 9)
    c.line([(30, 98), (130, 98)], (170, 176, 188), 5)
    shackle = arc(80, 80, 16, 24, 180, 360, 12)
    c.line(shackle, INK, 11)
    c.line(shackle, (190, 196, 206), 5)
    c.rect(56, 82, 104, 128, YELLOW, INK, 4, r=6)
    c.ellipse(80, 100, 6, 6, INK)
    c.rect(77, 102, 83, 118, INK)
    return c.finish()


def cone(c: Canvas, x: float, y: float, s: float) -> None:
    ground_shadow(c, x, y + 1, s * 0.62)
    c.rect(x - s * 0.55, y - s * 0.12, x + s * 0.55, y + s * 0.06, (60, 50, 44), INK, 2)
    c.poly([(x - s * 0.4, y - s * 0.12), (x + s * 0.4, y - s * 0.12), (x + s * 0.1, y - s * 1.0), (x - s * 0.1, y - s * 1.0)],
           (232, 108, 44), INK, 3)
    c.poly([(x - s * 0.27, y - s * 0.46), (x + s * 0.27, y - s * 0.46), (x + s * 0.2, y - s * 0.64), (x - s * 0.2, y - s * 0.64)], CREAM)


def roadworks_art() -> Image.Image:
    c = Canvas(320, 220, PSS)
    ground_shadow(c, 160, 205, 150)
    # The digger: tracks, body, cab, arm and bucket.
    c.rect(150, 176, 278, 204, (70, 66, 64), INK, 4, r=14)
    for k in range(5):
        c.ellipse(166 + k * 24, 190, 6, 6, (120, 116, 110), INK, 2)
    c.rect(160, 134, 270, 178, YELLOW, INK, 4, r=6)
    c.rect(214, 92, 266, 136, YELLOW, INK, 4, r=6)
    c.rect(222, 100, 258, 126, (170, 214, 232), INK, 3, r=3)
    arm = [(176, 150), (126, 92), (84, 128)]
    c.line(arm, INK, 17)
    c.line(arm, (224, 168, 40), 10)
    c.poly([(62, 118), (98, 120), (94, 156), (64, 150)], (130, 126, 122), INK, 4)
    c.poly(arc(46, 206, 46, 36, 180, 360, 12), (150, 112, 76), INK, 4)
    # The barrier and the "Road closed" sign on its post.
    for x in (104, 216):
        c.rect(x - 4, 150, x + 4, 206, (176, 176, 180), INK, 3)
    c.rect(66, 140, 250, 176, CREAM)
    for k in range(7):
        x0 = 70 + k * 26
        c.poly([(x0, 176), (x0 + 13, 176), (x0 + 24, 140), (x0 + 11, 140)], RED)
    c.rect(66, 140, 250, 176, None, INK, 4)
    c.rect(18, 112, 26, 206, (176, 176, 180), INK, 3)
    c.rect(4, 44, 108, 112, CREAM, INK, 4, r=6)
    rng = random.Random(SEED + 77)
    c.letters("ROAD", 56, 66, 17, RED, rng, 0.2)
    c.letters("CLOSED", 56, 92, 17, RED, rng, 0.2)
    cone(c, 114, 212, 40)
    cone(c, 240, 214, 36)
    return c.finish()


def hoarding_art() -> Image.Image:
    c = Canvas(300, 220, PSS)
    ground_shadow(c, 150, 210, 138)
    for x in (30, 150, 270):
        c.rect(x - 7, 120, x + 7, 212, WOOD, INK, 3)
    board = (92, 130, 160)
    c.rect(10, 40, 290, 190, board, INK, 5, r=4)
    for k in range(1, 6):
        c.line([(10 + k * 46.7, 42), (10 + k * 46.7, 188)], shade(board, 0.8), 2.5, caps=False)
    # The painted preview: a little street of new shops under a sun.
    c.rect(24, 52, 276, 130, (170, 214, 236), INK, 3)
    c.ellipse(244, 76, 15, 15, (252, 222, 120), INK, 2)
    for i, (col, hh) in enumerate([(RED, 46), ((250, 238, 214), 58), (ORANGE, 40), ((84, 150, 130), 52)]):
        x = 36 + i * 54
        c.rect(x, 128 - hh, x + 44, 128, col, INK, 2)
        c.rect(x + 6, 128 - hh + 8, x + 18, 128 - hh + 20, (252, 236, 170), INK, 1.5)
        c.rect(x + 26, 106, x + 38, 128, (140, 96, 64), INK, 1.5)
    c.rect(24, 124, 276, 130, (110, 168, 100), INK, 2)
    c.rect(36, 144, 264, 182, CREAM, INK, 3, r=4)
    c.letters("COMING SOON", 150, 163, 22, INK, random.Random(SEED + 88), 0.17)
    for k in range(10):
        x0 = 12 + k * 28
        c.poly([(x0, 40), (x0 + 14, 40), (x0 + 22, 28), (x0 + 8, 28)], YELLOW, INK, 1.5)
    return c.finish()


def van_art() -> Image.Image:
    """The owner's delivery van, side on and facing right (the ride drives it
    along the map road, so it is drawn small and chunky, like the pins)."""
    c = Canvas(120, 80, PSS)
    ground_shadow(c, 60, 70, 52)
    # The cargo box, then the cab and its bonnet, all one red.
    c.rect(8, 14, 76, 62, RED, INK, 4, r=6)
    c.rect(12, 18, 72, 26, shade(RED, 1.18))
    c.poly([(76, 26), (96, 26), (112, 44), (114, 62), (76, 62)], RED, INK, 4)
    c.poly([(82, 31), (95, 31), (106, 44), (82, 44)], (170, 214, 232), INK, 3)
    # A cream stripe round the box with the spoon the shop sells under.
    c.rect(8, 40, 76, 50, CREAM, INK, 3)
    c.ellipse(50, 45, 5, 3.4, INK)
    c.line([(54, 45), (68, 45)], INK, 2.4)
    # Bumpers, lights and the door line.
    c.rect(106, 54, 116, 62, (176, 176, 180), INK, 3)
    c.rect(2, 54, 10, 62, (176, 176, 180), INK, 3)
    c.ellipse(110, 49, 3, 3, YELLOW, INK, 1.5)
    c.line([(88, 46), (88, 60)], shade(RED, 0.7), 2.5, caps=False)
    # Wheels over the arches.
    for x in (30, 92):
        c.ellipse(x, 62, 13, 13, (60, 50, 44), INK, 4)
        c.ellipse(x, 62, 5, 5, (190, 190, 190), INK, 2)
    return c.finish()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    areas, roads = read_data()
    build_map(areas, roads).convert("RGB").save(OUT / "paper_map.png", optimize=True)
    for state in ("here", "managed", "closed", "renovating", "needs"):
        pin_shop(state).save(OUT / f"pin_{state}.png", optimize=True)
    pin_for_sale().save(OUT / "pin_for_sale.png", optimize=True)
    pin_locked().save(OUT / "pin_locked.png", optimize=True)
    roadworks_art().save(OUT / "roadworks.png", optimize=True)
    hoarding_art().save(OUT / "hoarding.png", optimize=True)
    van_art().save(OUT / "van.png", optimize=True)
    print("city map art written to", OUT)


if __name__ == "__main__":
    main()
