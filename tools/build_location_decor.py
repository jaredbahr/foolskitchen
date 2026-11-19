"""Build the location starter decor (#596, "Location interiors"): ten small pieces.

python tools/build_location_decor.py   (any Python with the `bpy` module)
or: blender --background --factory-startup --python tools/build_location_decor.py

Writes assets/made/location_decor/ and location_decor.metrics.json (triangles,
sizes, materials). Each place's starter building hangs or stands some of them:

- Seaside cliff (nautical): `lifebuoy`, `fishing_net` (a net with floats and a
  coil of rope on a pole), `bunting` (pennants on a sagging string).
- Old Mill (farmhouse): `flour_sacks` (three burlap sacks, blue band, flour at the neck),
  `barrel`, `wheat_sheaf` (a tied sheaf on a peg).
- Skyline rooftop (sleek): `skyline_print` (a framed city print).
- Beachfront boardwalk (beachy): `surfboard` (on two wall pegs), `beach_sign`
  (two painted arrow planks), `shell_jars` (two glass jars of shells for a counter).

Unchanged Furniture Kit material colours copied by name from the kit files; no
textures, lights or emission. Every size below is a world size divided once by
ArtScale.FURNITURE_SCALE, so the wrapper's uniform scale gives it back.
Metres; Blender Z-up with the front at +Y (the glTF export is Y-up facing -Z),
the back of a wall piece at y = 0. Deterministic: no random draws.
"""
from pathlib import Path
import json
import math
import re
import sys

import bpy  # first: the bpy module provides bmesh and mathutils
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb, glb_metrics  # noqa: E402

ART_SCALE = (ROOT / "src/world/art_scale.gd").read_text()
FURNITURE_SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)", ART_SCALE).group(1))
OUTPUT = ROOT / "assets/made/location_decor"
KIT = ROOT / "assets/kenney/furniture"

# Unchanged Furniture Kit colours, copied from these kit files by name.
KIT_SOURCES = {
    "wood": "kitchenCabinet.glb", "woodDark": "kitchenCabinet.glb", "metal": "kitchenCabinet.glb",
    "metalDark": "wall.glb", "metalMedium": "chairDesk.glb", "carpetWhite": "bathroomCabinetDrawer.glb",
    "carpetBlue": "chairModernCushion.glb", "carpet": "bedBunk.glb", "lamp": "ceilingFan.glb",
    "glass": "bathroomMirror.glb",
}


# ---------------------------------------------------------------- materials

def kit_material(name):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    doc, _ = read_glb(KIT / KIT_SOURCES[name])
    source = next(m for m in doc["materials"] if m["name"] == name)
    pbr = source["pbrMetallicRoughness"]
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = pbr["baseColorFactor"]
    shader.inputs["Metallic"].default_value = pbr.get("metallicFactor", 1)
    shader.inputs["Roughness"].default_value = pbr.get("roughnessFactor", 1)
    if pbr["baseColorFactor"][3] < 1.0:
        shader.inputs["Alpha"].default_value = pbr["baseColorFactor"][3]
        result.surface_render_method = "BLENDED"
    result.diffuse_color = pbr["baseColorFactor"]
    return result


# ---------------------------------------------------------------- geometry
# Every helper takes world metres; Piece.finish divides by the furniture scale.

class Piece:
    """One exported, named mesh: parts merge into one bmesh, each face keeping its
    material slot."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []

    def add(self, part, token):
        if token not in self.slots:
            self.slots.append(token)
        index = self.slots.index(token)
        mapping = {vert: self.bm.verts.new(vert.co) for vert in part.verts}
        for face in part.faces:
            new = self.bm.faces.new([mapping[v] for v in face.verts])
            new.material_index = index
            new.smooth = False
        part.free()
        return self

    def finish(self):
        bmesh.ops.scale(self.bm, vec=Vector((1.0 / FURNITURE_SCALE,) * 3), verts=self.bm.verts)
        # Every part is a closed solid (or a ring of open tubes that meet), so the
        # outward winding can be recomputed in one pass; Godot culls back faces.
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for token in self.slots:
            mesh.materials.append(kit_material(token))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def poly(vertices, faces):
    bm = bmesh.new()
    verts = [bm.verts.new(Vector(v)) for v in vertices]
    for face in faces:
        bm.faces.new([verts[i] for i in face])
    return bm


def box(lo, hi, bevel=0.0):
    """An axis-aligned box from corner `lo` to corner `hi`, optionally bevelled."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = [hi[k] - lo[k] for k in range(3)]
    for vert in bm.verts:
        vert.co = Vector(((vert.co.x + .5) * size[0] + lo[0], (vert.co.y + .5) * size[1] + lo[1],
                          (vert.co.z + .5) * size[2] + lo[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * .45), segments=1, affect="EDGES")
    return bm


def transformed(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


def cylinder(center, r_bottom, r_top, z0, z1, sides=8, caps=True, phase=0.0):
    """A vertical (truncated) cone or cylinder around `center` (x, y)."""
    cx, cy = center
    ring = [(math.cos(phase + i * math.tau / sides), math.sin(phase + i * math.tau / sides)) for i in range(sides)]
    vertices = [(cx + r_bottom * c, cy + r_bottom * s, z0) for c, s in ring]
    vertices += [(cx + r_top * c, cy + r_top * s, z1) for c, s in ring]
    faces = [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    if caps:
        faces += [tuple(range(sides - 1, -1, -1)), tuple(range(sides, 2 * sides))]
    return poly(vertices, faces)


def lathe(profile, sides=12, center=(0.0, 0.0), phase=0.0, cap_bottom=True, cap_top=True):
    """A turned shape: `profile` is a list of (radius, z) from bottom to top."""
    cx, cy = center
    ring = [(math.cos(phase + i * math.tau / sides), math.sin(phase + i * math.tau / sides)) for i in range(sides)]
    vertices = [(cx + r * c, cy + r * s, z) for r, z in profile for c, s in ring]
    faces = []
    for row in range(len(profile) - 1):
        a, b = row * sides, (row + 1) * sides
        faces += [(a + i, a + (i + 1) % sides, b + (i + 1) % sides, b + i) for i in range(sides)]
    if cap_bottom:
        faces.append(tuple(range(sides - 1, -1, -1)))
    if cap_top:
        top = (len(profile) - 1) * sides
        faces.append(tuple(range(top, top + sides)))
    return poly(vertices, faces)


def rod(a, b, radius, sides=4):
    """A thin prism between points `a` and `b`."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    normal = axis.cross(Vector((0, 1, 0)))
    if normal.length < .1:
        normal = axis.cross(Vector((1, 0, 0)))
    normal.normalize()
    other = axis.cross(normal).normalized()
    vertices = [tuple(p + radius * (math.cos(i * math.tau / sides + math.pi / 4) * normal +
                                    math.sin(i * math.tau / sides + math.pi / 4) * other))
                for p in (a, b) for i in range(sides)]
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, sides * 2))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    return poly(vertices, faces)


def slab(outline, y0, y1):
    """A flat prism: `outline` is a counter-clockwise polygon of (x, z) points
    seen from the front (+Y), extruded from y0 (back) to y1 (front)."""
    n = len(outline)
    vertices = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in outline]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    bm = poly(vertices, faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.normal_update()
    # Keep the caps facing out whatever the outline's winding.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def torus_arc(center, major, minor, u0, u1, steps, minor_sides=6):
    """Part of a ring standing in the x-z plane (facing +Y), from angle u0 to u1."""
    cx, cy, cz = center
    vertices = []
    for k in range(steps + 1):
        u = u0 + (u1 - u0) * k / steps
        for j in range(minor_sides):
            v = j * math.tau / minor_sides
            r = major + minor * math.cos(v)
            vertices.append((cx + r * math.cos(u), cy + minor * math.sin(v), cz + r * math.sin(u)))
    faces = []
    for k in range(steps):
        a, b = k * minor_sides, (k + 1) * minor_sides
        faces += [(a + j, b + j, b + (j + 1) % minor_sides, a + (j + 1) % minor_sides) for j in range(minor_sides)]
    return poly(vertices, faces)


def disc(center, radius, y0, y1, sides=8, phase=0.0):
    """A coin standing in the x-z plane, facing +Y."""
    cx, cz = center
    outline = [(cx + radius * math.cos(phase + i * math.tau / sides), cz + radius * math.sin(phase + i * math.tau / sides))
               for i in range(sides)]
    return slab(outline, y0, y1)


# ---------------------------------------------------------------- seaside cliff

def lifebuoy():
    ring = Piece("Lifebuoy")
    major, minor = 0.13, 0.045
    centre = (0.0, minor, 0.0)
    for quarter in range(4):
        u0 = math.pi / 4 + quarter * math.pi / 2
        ring.add(torus_arc(centre, major, minor, u0, u0 + math.pi / 2, 4), "carpet" if quarter % 2 == 0 else "carpetWhite")
    # Two thin rope wraps over the white quarters.
    for u in (0.0, math.pi):
        x = major * math.cos(u)
        ring.add(box((x - .008, -0.002, -minor - .004), (x + .008, 2 * minor + .004, minor + .004)), "wood")
    # The peg it hangs on, through the hole at the top.
    ring.add(box((-.02, 0.0, major - minor - .03), (.02, 2 * minor + .03, major - minor - .002), bevel=.006), "woodDark")
    ring.finish()
    return {"ring": [2 * (major + minor), 2 * minor]}


def fishing_net():
    net = Piece("FishingNet")
    width, drop = 0.86, 0.42
    top = drop + 0.06
    net.add(rod((-width / 2 - .04, .03, top), (width / 2 + .04, .03, top), .022, sides=6), "woodDark")
    for x in (-width / 2 + .02, width / 2 - .02):
        net.add(box((x - .02, 0.0, top - .03), (x + .02, .03, top + .03)), "metalDark")

    def sag(x, row):
        # Each horizontal strand hangs in two shallow swags between three tie points.
        depth = 0.04 + 0.03 * row
        phase = abs(math.sin(math.pi * (x + width / 2) / (width / 2)))
        return top - .03 - row * (drop / 4) - depth * phase

    columns = 9
    xs = [-width / 2 + i * width / (columns - 1) for i in range(columns)]
    for x in xs:
        bottom = sag(x, 4)
        net.add(rod((x, .05, top - .02), (x, .05, bottom), .006), "woodDark")
    for row in range(1, 5):
        pts = [(x, .052, sag(x, row)) for x in xs]
        for a, b in zip(pts, pts[1:]):
            net.add(rod(a, b, .006), "woodDark")
    # Cork floats along the bottom edge.
    for i, x in enumerate(xs[1:-1:2]):
        z = sag(x, 4)
        net.add(transformed(cylinder((0, 0), .03, .03, -.022, .022, sides=8), Matrix.Translation((x, .055, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")),
                "carpet" if i % 2 == 0 else "carpetWhite")
    # A coil of rope looped over the right end of the pole.
    net.add(torus_arc((width / 2 - .1, .07, top - .1), .085, .026, 0.0, math.tau, 12, minor_sides=4), "wood")
    net.finish()
    return {"width": width, "drop": round(top - sag(0.0, 4), 3)}


def bunting():
    flags = Piece("Bunting")
    width, sag_depth, top = 1.42, 0.07, 0.17
    def z(x):
        return top - sag_depth * (1.0 - (2.0 * x / width) ** 2)
    xs = [-width / 2 + i * width / 8 for i in range(9)]
    for a, b in zip(xs, xs[1:]):
        flags.add(rod((a, .02, z(a)), (b, .02, z(b)), .006), "metalDark")
    for x in (xs[0], xs[-1]):
        flags.add(box((x - .015, 0.0, z(x) - .015), (x + .015, .03, z(x) + .015)), "metalDark")
    colours = ["carpet", "carpetWhite", "carpetBlue"]
    pennants = 9
    for i in range(pennants):
        x = -width / 2 + (i + 0.5) * width / pennants
        half = 0.055
        outline = [(x - half, z(x - half)), (x, z(x) - 0.13), (x + half, z(x + half))]
        flags.add(slab(outline, .015, .025), colours[i % 3])
    flags.finish()
    return {"width": width}


# ---------------------------------------------------------------- old mill

def _sack(height, width, depth, band=True):
    """A standing calico sack, its base centred on the origin."""
    parts = []
    body = box((-width / 2, -depth / 2, 0.0), (width / 2, depth / 2, height), bevel=.045)
    # Round the shoulders in a little.
    for vert in body.verts:
        if vert.co.z > height * 0.75:
            vert.co.x *= 0.9
            vert.co.y *= 0.9
    parts.append((body, "wood"))
    if band:
        parts.append((box((-width / 2 * 1.01, -depth / 2 * 1.01, height * .32), (width / 2 * 1.01, depth / 2 * 1.01, height * .44)), "carpetBlue"))
    parts.append((cylinder((0, 0), width * .26, width * .15, height - .01, height + .02, sides=6), "wood"))
    parts.append((cylinder((0, 0), width * .17, width * .17, height + .006, height + .018, sides=6), "woodDark"))
    parts.append((cylinder((0, 0), width * .15, width * .22, height + .02, height + .042, sides=6, phase=.4), "carpetWhite"))
    return parts


def flour_sacks():
    sacks = Piece("FlourSacks")
    for x in (-0.105, 0.105):
        for part, token in _sack(0.27, 0.19, 0.17):
            sacks.add(transformed(part, Matrix.Translation((x, -0.03, 0.0))), token)
    # A third sack lying across the front, its neck to the right.
    for part, token in _sack(0.3, 0.17, 0.14):
        lying = Matrix.Translation((-0.16, 0.13, 0.085)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
        sacks.add(transformed(part, lying), token)
    sacks.finish()
    return {}


def barrel():
    cask = Piece("Barrel")
    profile = [(0.14, 0.0), (0.165, 0.1), (0.175, 0.2), (0.165, 0.3), (0.14, 0.4)]
    cask.add(lathe(profile, sides=12), "wood")
    cask.add(cylinder((0, 0), .122, .122, .4, .406, sides=12), "woodDark")
    for z0, z1, r in ((0.045, 0.075, 0.156), (0.325, 0.355, 0.156)):
        cask.add(cylinder((0, 0), r, r, z0, z1, sides=12, caps=False), "metalDark")
    # A few dark stave seams down the front half.
    for i in range(6):
        a = math.pi * (0.1 + i / 6.0) + math.pi / 12
        x, y = math.cos(a), math.sin(a)
        cask.add(rod((0.142 * x, 0.142 * y, 0.01), (0.176 * x, 0.176 * y, 0.2), .004), "woodDark")
        cask.add(rod((0.176 * x, 0.176 * y, 0.2), (0.142 * x, 0.142 * y, 0.39), .004), "woodDark")
    cask.finish()
    return {}


def wheat_sheaf():
    sheaf = Piece("WheatSheaf")
    tie = 0.24
    stalks = 9
    for i in range(stalks):
        f = (i - (stalks - 1) / 2) / ((stalks - 1) / 2)
        y = .02 + .015 * (i % 3)
        foot = (0.09 * f, y, 0.0)
        waist = (0.012 * f, y, tie)
        head = (0.14 * f, y, tie + 0.24 - 0.03 * abs(f))
        sheaf.add(rod(foot, waist, .006), "wood")
        sheaf.add(rod(waist, head, .006), "wood")
        # The ear: a slim diamond along the stalk's line.
        d = Vector(head) - Vector(waist)
        d.normalize()
        c = Vector(head) + d * 0.045
        side = Vector((d.z, 0, -d.x)) * 0.018
        tip = c + d * 0.05
        base = c - d * 0.04
        front, back = Vector((0, .014, 0)), Vector((0, -.006, 0))
        vertices = [tuple(base), tuple(c + side + front), tuple(tip), tuple(c - side + front), tuple(c + side + back), tuple(c - side + back)]
        sheaf.add(poly(vertices, [(0, 1, 2), (0, 2, 3), (0, 4, 1), (0, 3, 5), (2, 1, 4), (2, 5, 3), (0, 5, 4), (2, 4, 5)]), "lamp")
    sheaf.add(cylinder((0, 0), .028, .028, tie - .025, tie + .015, sides=8), "carpet")
    sheaf.add(transformed(cylinder((0, 0), .03, .03, tie - .025, tie + .015, sides=8), Matrix.Translation((0, .035, 0))), "carpet")
    # Ribbon tails.
    sheaf.add(slab([(-.01, tie - .02), (-.06, tie - .1), (-.035, tie - .1), (0.0, tie - .03)], .062, .07), "carpet")
    sheaf.add(slab([(.01, tie - .02), (0.0, tie - .03), (.035, tie - .1), (.06, tie - .1)], .062, .07), "carpet")
    sheaf.add(box((-.018, 0.0, tie + .2), (.018, .03, tie + .23), bevel=.005), "woodDark")
    sheaf.finish()
    return {}


# ---------------------------------------------------------------- skyline rooftop

def skyline_print():
    art = Piece("SkylinePrint")
    w, h, frame, depth = 0.7, 0.46, 0.035, 0.04
    art.add(box((-w / 2, 0.0, 0.0), (w / 2, depth, frame), bevel=.006), "metalDark")
    art.add(box((-w / 2, 0.0, h - frame), (w / 2, depth, h), bevel=.006), "metalDark")
    art.add(box((-w / 2, 0.0, frame), (-w / 2 + frame, depth, h - frame), bevel=.006), "metalDark")
    art.add(box((w / 2 - frame, 0.0, frame), (w / 2, depth, h - frame), bevel=.006), "metalDark")
    art.add(box((-w / 2 + frame, 0.005, frame), (w / 2 - frame, depth - .015, h - frame)), "carpetWhite")
    inner = (-w / 2 + frame + .025, w / 2 - frame - .025)
    art.add(box((inner[0], .005, frame + .025), (inner[1], depth - .012, h - frame - .025)), "carpetBlue")
    art.add(transformed(disc((0.17, h - 0.135), 0.035, 0.0, .004, sides=10), Matrix.Translation((0, depth - .012, 0))), "lamp")
    # Towers along the bottom, back row light, front row dark.
    base = frame + .025
    span = inner[1] - inner[0]
    back = [(0.02, 0.12, 0.16), (0.2, 0.32, 0.22), (0.56, 0.7, 0.19), (0.8, 0.95, 0.13)]
    front = [(0.0, 0.1, 0.09), (0.1, 0.22, 0.17), (0.3, 0.4, 0.27), (0.42, 0.55, 0.12), (0.62, 0.74, 0.21), (0.86, 1.0, 0.1)]
    for row, token, y in ((back, "metal", depth - .011), (front, "metalDark", depth - .008)):
        for a, b, tall in row:
            x0, x1 = inner[0] + a * span, inner[0] + b * span
            art.add(box((x0, depth - .013, base), (x1, y, base + tall)), token)
    # A few lit windows on the tall front tower and a spire.
    x0, x1 = inner[0] + 0.3 * span, inner[0] + 0.4 * span
    for k in range(4):
        z = base + 0.04 + k * 0.05
        art.add(box((x0 + .012, depth - .008, z), (x0 + .03, depth - .005, z + .022)), "lamp")
        art.add(box((x1 - .03, depth - .008, z), (x1 - .012, depth - .005, z + .022)), "lamp")
    mid = (x0 + x1) / 2
    art.add(box((mid - .004, depth - .011, base + .27), (mid + .004, depth - .008, base + .33)), "metalDark")
    art.finish()
    return {"size": [w, h]}


# ---------------------------------------------------------------- beachfront boardwalk

def surfboard():
    board = Piece("Surfboard")
    length, half_width, thick = 0.86, 0.13, 0.035

    def half(t):
        # Widest a little behind the middle, a soft pin tail (t = 0) and a pointed nose (t = 1).
        return half_width * math.sin(math.pi * t ** 0.85) ** 0.55

    steps = 16
    ts = [k / steps for k in range(1, steps)]
    outline = [(-length / 2, 0.0)] + [(-length / 2 + t * length, -half(t)) for t in ts] + [(length / 2, 0.0)]
    outline += [(-length / 2 + t * length, half(t)) for t in reversed(ts)]
    board.add(slab(outline, 0.025, 0.025 + thick), "carpetBlue")
    # The stringer and a red band near the nose, painted on the deck.
    deck = 0.025 + thick
    board.add(box((-length / 2 + .03, deck - .002, -.006), (length / 2 - .05, deck + .003, .006)), "carpetWhite")
    t_band = 0.78
    w_band = half(t_band + 0.03)
    x_band = -length / 2 + t_band * length
    board.add(box((x_band, deck - .002, -w_band + .006), (x_band + .03, deck + .004, w_band - .006)), "carpet")
    for x in (-0.24, 0.24):
        board.add(box((x - .025, 0.0, -half_width - .03), (x + .025, .065, -half_width + .005), bevel=.006), "woodDark")
    # It stands on its tail, nose up: lying flat, a board on a wall reads as a thin
    # stroke from the game's camera. The two wall cleats end up at its side.
    bmesh.ops.rotate(board.bm, verts=board.bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "Y"))
    board.finish()
    return {"length": length}


def beach_sign():
    sign = Piece("BeachSign")
    def arrow(x0, x1, z0, z1, right):
        mid = (z0 + z1) / 2
        if right:
            return [(x0, z0), (x1 - .07, z0), (x1, mid), (x1 - .07, z1), (x0, z1)]
        return [(x0 + .07, z0), (x1, z0), (x1, z1), (x0 + .07, z1), (x0, mid)]

    def inset(points, by):
        cx = sum(p[0] for p in points) / len(points)
        cz = sum(p[1] for p in points) / len(points)
        return [(cx + (x - cx) * (1 - by / 0.35), cz + (z - cz) * (1 - by / 0.08)) for x, z in points]

    planks = [(-0.36, 0.34, 0.2, 0.34, True, "carpetBlue"), (-0.32, 0.36, 0.02, 0.16, False, "lamp")]
    for x0, x1, z0, z1, right, paint in planks:
        board = arrow(x0, x1, z0, z1, right)
        sign.add(slab(board, 0.0, 0.03), "wood")
        sign.add(slab(inset(board, 0.018), 0.03, 0.036), paint)
        for nx in (x0 + 0.06, x1 - 0.12) if right else (x0 + 0.12, x1 - 0.06):
            sign.add(box((nx - .008, .036, (z0 + z1) / 2 - .008), (nx + .008, .04, (z0 + z1) / 2 + .008)), "metalDark")
    # A white wave on the blue plank, a red sun on the yellow one.
    wave = []
    for k in range(9):
        x = -0.2 + k * 0.05
        wave.append((x, 0.255 + (0.02 if k % 2 else 0.0)))
    for a, b in zip(wave, wave[1:]):
        sign.add(rod((a[0], .039, a[1]), (b[0], .039, b[1]), .009), "carpetWhite")
    sign.add(disc((0.02, 0.09), 0.042, 0.035, 0.041, sides=10), "carpet")
    for k in range(8):
        a = k * math.tau / 8
        sign.add(rod((0.02 + 0.055 * math.cos(a), .039, 0.09 + 0.055 * math.sin(a)),
                     (0.02 + 0.07 * math.cos(a), .039, 0.09 + 0.07 * math.sin(a)), .006), "carpet")
    # Big enough to read at the game's camera distance (two faces wide).
    bmesh.ops.scale(sign.bm, vec=Vector((1.25, 1.25, 1.25)), verts=sign.bm.verts)
    sign.finish()
    return {}


def shell_jars():
    jars = Piece("ShellJars")
    for cx, tall, r in ((-0.045, 0.12, 0.042), (0.05, 0.085, 0.038)):
        jars.add(cylinder((cx, 0), r, r, 0.0, tall, sides=10, caps=False), "glass")
        jars.add(cylinder((cx, 0), r * .98, r * .98, 0.0, 0.004, sides=10), "glass")
        jars.add(cylinder((cx, 0), r * 1.04, r * 1.04, tall, tall + 0.018, sides=10), "wood")
        jars.add(cylinder((cx, 0), r * .7, r * .7, tall + 0.018, tall + 0.026, sides=10), "woodDark")
        # Shells piled inside: little cones and scallops in kit colours.
        fill = tall * 0.55
        for k, token in enumerate(("carpetWhite", "carpet", "wood", "carpetWhite", "carpet")):
            a = k * 2.1
            sx, sy = cx + r * .45 * math.cos(a), r * .45 * math.sin(a)
            z = 0.006 + (k // 3) * fill * 0.45
            jars.add(cylinder((sx, sy), r * .32, 0.004, z, z + fill * 0.5, sides=5, phase=a), token)
    jars.finish()
    return {}


# ---------------------------------------------------------------- export

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for datablock in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(datablock):
            datablock.remove(item)


def export(path: Path) -> None:
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True,
                              export_animations=False, export_cameras=False, export_lights=False,
                              export_extras=False)


# (asset id, builder, triangle budget, nearest kit pieces)
ASSETS = [
    ("lifebuoy", lifebuoy, 800, ["lampWall.glb (wall mount)", "pillow.glb (carpet, carpetWhite)"]),
    ("fishing_net", fishing_net, 800, ["coatRack.glb (woodDark pegs)", "lampWall.glb"]),
    ("bunting", bunting, 800, ["#240 string_lights (metalDark string)", "benchCushion.glb (carpet)"]),
    ("flour_sacks", flour_sacks, 800, ["pillow.glb", "cardboardBoxClosed.glb"]),
    ("barrel", barrel, 800, ["trashcan.glb", "kitchenCabinet.glb (wood)"]),
    ("wheat_sheaf", wheat_sheaf, 800, ["plantSmall3.glb", "coatRack.glb"]),
    ("skyline_print", skyline_print, 800, ["#147 diner wall art (wallWindow frame)", "televisionModern.glb"]),
    ("surfboard", surfboard, 800, ["chairModernCushion.glb (carpetBlue)", "coatRack.glb"]),
    ("beach_sign", beach_sign, 800, ["#240 shop_name_sign", "paneling.glb"]),
    ("shell_jars", shell_jars, 800, ["bathroomMirror.glb (glass)", "Food Kit cup"]),
]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"issue": 596, "furniture_scale": FURNITURE_SCALE, "assets": {}}
    only = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
    for asset_id, builder, budget, nearest in ASSETS:
        clear_scene()
        extra = builder()
        path = OUTPUT / (asset_id + ".glb")
        export(path)
        measured = glb_metrics(path)
        doc, _ = read_glb(path)
        assert measured["triangles"] < budget, (asset_id, measured["triangles"])
        assert not doc.get("images"), asset_id + " uses kit material colours only"
        report["assets"][asset_id] = {
            "triangles": measured["triangles"], "budget": budget,
            "world_dimensions": [round(v * FURNITURE_SCALE, 4) for v in measured["dimensions"]],
            "materials": sorted(m["name"] for m in doc["materials"]),
            "nearest_kit": nearest, **{k: v for k, v in extra.items()}}
    (OUTPUT / "location_decor.metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: (v["triangles"], v["world_dimensions"]) for k, v in report["assets"].items()}, indent=1))


main()
