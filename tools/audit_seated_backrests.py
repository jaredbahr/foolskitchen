#!/usr/bin/env python3
"""Verify an existing backrest manifest and draw its selections; never select faces.

Python 3.9+ standard library only. Example:
  python tools/audit_seated_backrests.py --out /tmp/fk-backrest-source-review
The output directory must not exist. This is source classification evidence,
not a Godot import, native measurement, clearance result or fit acceptance.
"""

import argparse
from collections import Counter
import hashlib
import html
import json
import math
from pathlib import Path
import struct
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def glb_faces(data):
    require(len(data) >= 20, "truncated GLB")
    magic, version, length = struct.unpack_from("<III", data)
    require(magic == 0x46546C67 and version == 2 and length == len(data), "invalid GLB2 header")
    chunks = []
    at = 12
    while at < len(data):
        require(at + 8 <= len(data), "truncated chunk header")
        size, kind = struct.unpack_from("<II", data, at)
        at += 8
        require(size % 4 == 0 and at + size <= len(data), "invalid GLB chunk length")
        chunks.append((kind, data[at:at + size]))
        at += size
    require(len(chunks) == 2 and chunks[0][0] == 0x4E4F534A and chunks[1][0] == 0x004E4942,
            "expected JSON then BIN chunks")
    document = json.loads(chunks[0][1].decode("utf-8"))
    binary = chunks[1][1]
    require(len(document.get("buffers", [])) == 1 and "uri" not in document["buffers"][0],
            "expected one embedded buffer")
    require(document["buffers"][0]["byteLength"] <= len(binary), "truncated embedded buffer")

    def accessor(number, components, formats):
        entry = document["accessors"][number]
        require("sparse" not in entry and not entry.get("normalized", False), "unsupported accessor")
        require(entry["type"] == components and entry["componentType"] in formats, "unexpected accessor type")
        view = document["bufferViews"][entry["bufferView"]]
        require(view.get("buffer", 0) == 0, "accessor references another buffer")
        code, width = formats[entry["componentType"]]
        stride = view.get("byteStride", width)
        require(stride >= width and entry["count"] > 0, "invalid accessor stride/count")
        offset = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
        end = offset + (entry["count"] - 1) * stride + width
        require(offset >= view.get("byteOffset", 0)
                and end <= view.get("byteOffset", 0) + view["byteLength"]
                and end <= len(binary), "accessor exceeds its buffer view")
        return [struct.unpack_from("<" + code, binary, offset + index * stride)
                for index in range(entry["count"])]

    faces = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            require(primitive.get("mode", 4) == 4 and "indices" in primitive, "expected indexed triangles")
            positions = accessor(primitive["attributes"]["POSITION"], "VEC3", {5126: ("fff", 12)})
            indices = accessor(primitive["indices"], "SCALAR",
                               {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)})
            require(len(indices) % 3 == 0, "incomplete source triangle")
            for start in range(0, len(indices), 3):
                face = []
                for (index,) in indices[start:start + 3]:
                    require(index < len(positions), "source index outside POSITION accessor")
                    face.extend(positions[index])
                require(all(math.isfinite(value) for value in face), "nonfinite source position")
                faces.append(face)
    require(faces, "source mesh has no faces")
    return faces


def decode_faces(entry):
    require(isinstance(entry.get("faces"), list) and entry["faces"], "empty manifest faces")
    faces = []
    for encoded in entry["faces"]:
        require(isinstance(encoded, str) and len(encoded) == 72
                and all(char in "0123456789abcdef" for char in encoded), "invalid float32 face encoding")
        face = list(struct.unpack("<9f", bytes.fromhex(encoded)))
        require(all(math.isfinite(value) for value in face), "nonfinite manifest face")
        faces.append(face)
    return faces


def triangle_key(face):
    # Winding/order are irrelevant to complete geometry inventory parity.
    return tuple(sorted(tuple(face[index:index + 3]) for index in (0, 3, 6)))


def verify(root, manifest):
    require(type(manifest.get("schema")) is int and manifest["schema"] == 2
            and isinstance(manifest.get("sources"), dict), "expected schema 2 sources")
    require(manifest["sources"], "empty source manifest")
    verified = []
    for reference, entry in manifest["sources"].items():
        # Kit sources, plus the lowered-backrest copies from tools/derive_seat_backrests.py.
        require((reference.startswith("res://assets/kenney/furniture/")
                 or reference.startswith("res://assets/props/seats/derived/")) and reference.endswith(".glb"),
                "unexpected source path: " + reference)
        relative = reference.removeprefix("res://")
        source = (root / relative).resolve()
        require(source.is_relative_to(root), "source escapes repository")
        data = source.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        require(digest == entry["sha256"], "SHA-256 differs: " + reference)
        faces = decode_faces(entry)
        actual = glb_faces(data)
        require(Counter(map(triangle_key, actual)) == Counter(map(triangle_key, faces)),
                "full source-face inventory differs: " + reference)
        require(actual == faces, "manifest face indices no longer follow source order: " + reference)
        selected = entry["backrest_faces"]
        require(isinstance(selected, list) and selected
                and all(type(index) is int and 0 <= index < len(faces) for index in selected)
                and len(set(selected)) == len(selected) and len(selected) < len(faces),
                "invalid, duplicated or whole-mesh backrest selection: " + reference)
        require(isinstance(entry.get("audit"), str) and entry["audit"].strip(), "missing audit: " + reference)
        verified.append((reference, entry))
    return verified


def projections(reference, entry):
    faces = decode_faces(entry)
    selected = set(entry["backrest_faces"])
    output = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1800 700" role="img"',
              ' aria-label="Source front side and top projections, selected backrests red and remaining faces gray">',
              '<rect width="1800" height="700" fill="white"/>',
              '<text x="16" y="28" font-size="20">' + html.escape(Path(reference).stem)
              + f': source polygons — {len(selected)}/{len(faces)} selected</text>']
    for pane, (title, axis_a, axis_b) in enumerate((('FRONT X/Y', 0, 1), ('SIDE Z/Y', 2, 1), ('TOP X/Z', 0, 2))):
        points = [face[index:index + 3] for face in faces for index in (0, 3, 6)]
        low_a, high_a = min(p[axis_a] for p in points), max(p[axis_a] for p in points)
        low_b, high_b = min(p[axis_b] for p in points), max(p[axis_b] for p in points)
        require(high_a > low_a and high_b > low_b, "degenerate source projection")
        scale = min(510 / (high_a - low_a), 510 / (high_b - low_b))
        left = 30 + pane * 600
        output.append(f'<text x="{left}" y="65" font-size="18">{title} (source metres)</text>')
        output.append(f'<text x="{left}" y="86" font-size="13">'
                      f'A [{low_a:.3f}, {high_a:.3f}] B [{low_b:.3f}, {high_b:.3f}]</text>')
        for selected_pass in (False, True):
            for index, face in enumerate(faces):
                if (index in selected) != selected_pass:
                    continue
                polygon = ' '.join(f'{left + 25 + (face[corner + axis_a] - low_a) * scale:.6f},'
                                   f'{620 - (face[corner + axis_b] - low_b) * scale:.6f}'
                                   for corner in (0, 3, 6))
                color = '#d62f25' if selected_pass else '#7d848b'
                output.append(f'<polygon points="{polygon}" fill="{color}" fill-opacity="0.30" '
                              f'stroke="{color}" stroke-width="0.8"><title>Manifest face {index}'
                              + (' — selected backrest' if selected_pass else ' — remaining source')
                              + '</title></polygon>')
    return '\n'.join(output + ['</svg>'])


def page(verified, manifest_digest):
    chunks = ['<!doctype html><html lang="en"><meta charset="utf-8">',
              '<meta name="viewport" content="width=device-width,initial-scale=1">',
              '<title>Seated backrest source audit</title>',
              '<style>body{font:16px system-ui,sans-serif;margin:24px;color:#20242a;max-width:1800px}'
              'table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccd0d5;padding:8px;text-align:left}'
              'code{overflow-wrap:anywhere;font-size:12px}svg{width:100%;height:auto;border:1px solid #ddd}'
              'section{margin-top:36px}p{line-height:1.5}</style>',
              '<h1>Seated backrest source audit</h1><p>Red: selected source backrest polygons. '
              'Gray: remaining source polygons. This verifies source inventory and classification only; '
              'it is not a native import, clearance measurement or seat-fit acceptance. '
              'Continuous rear-stile/shell triangles may extend below the seat.</p>',
              '<p>Manifest SHA-256: <code>' + manifest_digest + '</code></p>',
              '<table><thead><tr><th>Source</th><th>SHA-256</th><th>Selected / total</th><th>Audit</th></tr></thead><tbody>']
    for reference, entry in verified:
        chunks.append('<tr><td>' + html.escape(reference) + '</td><td><code>' + entry['sha256']
                      + '</code></td><td>' + f'{len(entry["backrest_faces"])} / {len(entry["faces"])}'
                      + '</td><td>' + html.escape(entry['audit']) + '</td></tr>')
    chunks.append('</tbody></table>')
    for reference, entry in verified:
        chunks.append('<section><h2>' + html.escape(Path(reference).stem) + '</h2>'
                      + projections(reference, entry) + '</section>')
    return '\n'.join(chunks + ['</html>'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--manifest', type=Path, default=Path('tools/seated_head_backrests.json'))
    parser.add_argument('--out', type=Path, required=True, help='fresh output directory; refuses overwrite')
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    manifest_path = arguments.manifest if arguments.manifest.is_absolute() else root / arguments.manifest
    require(not arguments.out.exists(), 'output path already exists; refusing overwrite')
    raw = manifest_path.read_bytes()
    verified = verify(root, json.loads(raw))
    rendered = page(verified, hashlib.sha256(raw).hexdigest())
    # Complete every source check before creating any output. Never write a manifest.
    arguments.out.mkdir(parents=True, exist_ok=False)
    target = arguments.out / 'index.html'
    target.write_text(rendered, encoding='utf-8')
    for reference, entry in verified:
        print(f'{reference}: SHA/inventory verified; {len(entry["backrest_faces"])}/{len(entry["faces"])} selected')
    print('SOURCE AUDIT VERIFIED: ' + str(target.resolve()))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, OverflowError, struct.error) as error:
        print('SOURCE AUDIT FAILED: ' + str(error), file=sys.stderr)
        sys.exit(2)
