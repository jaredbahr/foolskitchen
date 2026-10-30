"""Rebuild the three issue #241 icons in the approved Kenney Game Icons style.

python3 tools/build_weather_icons.py
White, solid rounded silhouettes on transparent 100x100 canvases. The same
primitive descriptions generate editable SVG and supersampled PNG exports.
References: approved Game Icons star.png, gear.png, home.png and audioOn.png.
No downloaded source, fonts, textures, image service or Godot process is used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE = 100
SUPERSAMPLE = 8
WHITE = (255, 255, 255)


def cloud(offset_y: float = 0) -> list[dict]:
    return [
        {"kind": "circle", "cx": 36, "cy": 51 + offset_y, "r": 18},
        {"kind": "circle", "cx": 54, "cy": 46 + offset_y, "r": 18},
        {"kind": "circle", "cx": 69, "cy": 54 + offset_y, "r": 13},
        {"kind": "roundrect", "x": 18, "y": 48 + offset_y, "w": 64, "h": 24, "r": 12},
    ]


def silhouettes() -> dict[str, list[dict]]:
    sunny = [{"kind": "circle", "cx": 50, "cy": 50, "r": 17}]
    for index in range(8):
        angle = index * math.tau / 8
        sunny.append({
            "kind": "capsule", "x1": round(50 + math.cos(angle) * 24, 6),
            "y1": round(50 + math.sin(angle) * 24, 6),
            "x2": round(50 + math.cos(angle) * 28, 6),
            "y2": round(50 + math.sin(angle) * 28, 6), "width": 8,
        })
    rain = cloud(-8)
    for x in (35, 52, 69):
        rain.append({"kind": "capsule", "x1": x, "y1": 72,
                     "x2": x - 5, "y2": 79, "width": 6})
    return {"weather_sunny": sunny, "weather_cloudy": cloud(), "weather_rain": rain}


def number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def svg(shapes: list[dict]) -> str:
    lines = ['<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">',
             '  <g fill="#ffffff">']
    for shape in shapes:
        kind = shape["kind"]
        if kind == "circle":
            lines.append('    <circle cx="%s" cy="%s" r="%s"/>' % tuple(number(shape[k]) for k in ("cx", "cy", "r")))
        elif kind == "roundrect":
            lines.append('    <rect x="%s" y="%s" width="%s" height="%s" rx="%s"/>' %
                         tuple(number(shape[k]) for k in ("x", "y", "w", "h", "r")))
        else:
            lines.append('    <path d="M%s %s L%s %s" fill="none" stroke="#ffffff" stroke-width="%s" stroke-linecap="round"/>' %
                         tuple(number(shape[k]) for k in ("x1", "y1", "x2", "y2", "width")))
    return "\n".join([*lines, "  </g>", "</svg>", ""])


def raster(shapes: list[dict]) -> Image.Image:
    mask = Image.new("L", (SIZE * SUPERSAMPLE, SIZE * SUPERSAMPLE))
    draw = ImageDraw.Draw(mask)
    def bounds(x0: float, y0: float, x1: float, y1: float) -> tuple:
        return tuple(v * SUPERSAMPLE for v in (x0, y0, x1, y1))
    for shape in shapes:
        kind = shape["kind"]
        if kind == "circle":
            x, y, radius = (shape[k] for k in ("cx", "cy", "r"))
            draw.ellipse(bounds(x - radius, y - radius, x + radius, y + radius), fill=255)
        elif kind == "roundrect":
            x, y, width, height, radius = (shape[k] for k in ("x", "y", "w", "h", "r"))
            draw.rounded_rectangle(bounds(x, y, x + width, y + height), radius=radius * SUPERSAMPLE, fill=255)
        else:
            x1, y1, x2, y2, width = (shape[k] for k in ("x1", "y1", "x2", "y2", "width"))
            radius = width / 2
            length = math.hypot(x2 - x1, y2 - y1)
            nx, ny = -(y2 - y1) / length * radius, (x2 - x1) / length * radius
            draw.polygon([(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in
                          [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny),
                           (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)]], fill=255)
            for x, y in [(x1, y1), (x2, y2)]:
                draw.ellipse(bounds(x - radius, y - radius, x + radius, y + radius), fill=255)
    result = Image.new("RGB", (SIZE, SIZE), WHITE).convert("RGBA")
    result.putalpha(mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "assets/made/icons")
    parser.add_argument("--manifest", type=Path, help="Optional audit JSON outside the shipping project")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    reports = []
    for ident, shapes in silhouettes().items():
        source = args.out / (ident + ".svg")
        source.write_text(svg(shapes))
        image = raster(shapes)
        target = args.out / (ident + ".png")
        image.save(target, compress_level=9, optimize=False)
        assert image.size == (100, 100)
        assert all(pixel[:3] == WHITE for pixel in image.get_flattened_data())
        alpha = image.getchannel("A")
        assert alpha.getextrema() == (0, 255)
        reports.append({"id": ident, "size": [100, 100], "alpha_bounds": alpha.getbbox(),
                        "solid_bounds": alpha.point(lambda value: 255 if value >= 128 else 0).getbbox(),
                        "svg_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "png_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                        "all_rgb_white": True, "transparent_background": True})
    if args.manifest:
        destination = args.manifest.resolve()
        if destination.is_relative_to(ROOT):
            raise ValueError("Review manifests must stay outside the shipping project")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
