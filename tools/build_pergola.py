"""Build the issue #380 rain cover for terrace seats: a pergola in two variants.

blender --background --factory-startup --python tools/build_pergola.py
(or any Python with the `bpy` module: python tools/build_pergola.py)

Writes assets/made/pergola/ and pergola.metrics.json (triangles, sizes, materials
and named nodes). Art only: the buildable rain-cover item (D-decision 2 in #380)
is a later issue that wraps these files.

- `pergola_timber.glb`: a timber pergola: four posts on metal shoes, two beams,
  five rafters and a cream canvas sheet stretched over them, with a short drop
  at front and back.
- `pergola_awning.glb`: a striped awning on four slim metal poles: a pitched
  blue-and-white canopy (the #240 / #589 awning stripes) with scalloped
  valances along both long sides.

Both cover a 2 x 2 m patch (4 x 4 grid cells), the eaves at 1.55 m and higher, so
a seated or standing person (0.74 m) and a table fit under with room to spare.
Unchanged Furniture Kit material colours copied by name from the kit files; no
textures, lights or emission. Every size below is a world size divided once by
ArtScale.FURNITURE_SCALE, so the wrapper's uniform scale gives it back.

Metres; Blender Z-up with the front at +Y; the glTF export is Y-up facing -Z. The
origin is the base centre. Deterministic: no random draws.
"""
from pathlib import Path
import json
import math
import re
import sys

import bpy  # first: the bpy module provides bmesh and mathutils
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb, glb_metrics  # noqa: E402

ART_SCALE = (ROOT / "src/world/art_scale.gd").read_text()
FURNITURE_SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)", ART_SCALE).group(1))
OUTPUT = ROOT / "assets/made/pergola"
KIT = ROOT / "assets/kenney/furniture"

# Unchanged Furniture Kit colours, copied from these kit files by name.
KIT_SOURCES = {
    "wood": "kitchenCabinet.glb", "woodDark": "kitchenCabinet.glb", "metal": "kitchenCabinet.glb",
    "metalDark": "wall.glb", "carpetWhite": "bathroomCabinetDrawer.glb", "carpetBlue": "chairModernCushion.glb",
}

HALF = 1.0          # half the covered patch (2 x 2 m)
POST_IN = 0.06      # posts stand this far in from the patch's corners
EAVES = 1.55        # underside of the beams / the canopy's low edge


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
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for token in self.slots:
            mesh.materials.append(kit_material(token))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


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


def poly(vertices, faces):
    bm = bmesh.new()
    verts = [bm.verts.new(Vector(v)) for v in vertices]
    for face in faces:
        bm.faces.new([verts[i] for i in face])
    return bm


def cylinder(center, r_bottom, r_top, z0, z1, sides=8, caps=True):
    """A vertical (truncated) cone or cylinder around `center` (x, y)."""
    cx, cy = center
    ring = [(math.cos(i * math.tau / sides), math.sin(i * math.tau / sides)) for i in range(sides)]
    vertices = [(cx + r_bottom * c, cy + r_bottom * s, z0) for c, s in ring]
    vertices += [(cx + r_top * c, cy + r_top * s, z1) for c, s in ring]
    faces = [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    if caps:
        faces += [tuple(range(sides - 1, -1, -1)), tuple(range(sides, 2 * sides))]
    return poly(vertices, faces)


def sheet(points, thickness):
    """A thin slab under a strip of quads: `points` is a list of (left, right) pairs
    of 3D points running along the strip; the slab hangs `thickness` below them."""
    vertices = []
    for left, right in points:
        vertices += [left, right, (left[0], left[1], left[2] - thickness), (right[0], right[1], right[2] - thickness)]
    faces = []
    for i in range(len(points) - 1):
        a, b = 4 * i, 4 * (i + 1)
        faces += [(a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3), (a, b, b + 2, a + 2), (a + 1, a + 3, b + 3, b + 1)]
    n = len(points) - 1
    faces += [(0, 2, 3, 1), (4 * n, 4 * n + 1, 4 * n + 3, 4 * n + 2)]
    return poly(vertices, faces)


def corners():
    c = HALF - POST_IN
    return [(-c, -c), (c, -c), (c, c), (-c, c)]


# ---------------------------------------------------------------- the timber pergola

def timber_pergola():
    frame = Piece("PergolaFrame")
    canvas = Piece("PergolaCanvas")
    post = 0.045
    for x, y in corners():
        frame.add(box((x - .06, y - .06, 0.0), (x + .06, y + .06, 0.06), bevel=.008), "metalDark")
        frame.add(box((x - post, y - post, 0.0), (x + post, y + post, EAVES + 0.14), bevel=.01), "woodDark")
        # Knee braces from each post out along the beams (x).
        for side in (-1.0, 1.0):
            if (x > 0) == (side > 0):
                continue
            a = Vector((x, y, EAVES - 0.26))
            b = Vector((x + side * 0.26, y, EAVES))
            frame.add(_rod(a, b, .022), "woodDark")
    # Two beams along x over the posts, sticking out a little past them.
    for y in (-(HALF - POST_IN), HALF - POST_IN):
        frame.add(box((-HALF - 0.08, y - .04, EAVES), (HALF + 0.08, y + .04, EAVES + 0.14), bevel=.01), "wood")
    # Five rafters across them (along y), proud of the beams each end.
    for index in range(5):
        x = -HALF + 0.12 + index * (2 * HALF - 0.24) / 4
        frame.add(box((x - .03, -HALF - 0.1, EAVES + 0.14), (x + .03, HALF + 0.1, EAVES + 0.24), bevel=.008), "wood")
    # The canvas: stretched taut over the rafters (its underside just clear of them),
    # with a short drop at the front and back edges.
    top = EAVES + 0.26
    rows = [((-HALF - 0.04, -HALF - 0.12, top), (-HALF - 0.04, HALF + 0.12, top)),
            ((HALF + 0.04, -HALF - 0.12, top), (HALF + 0.04, HALF + 0.12, top))]
    canvas.add(sheet(rows, 0.016), "carpetWhite")
    for y in (-HALF - 0.12, HALF + 0.12):
        canvas.add(box((-HALF - 0.04, y - .008, top - 0.14), (HALF + 0.04, y + .008, top - 0.016)), "carpetWhite")
    frame.finish()
    canvas.finish()
    return {"cover": [2 * HALF, 2 * HALF], "eaves": EAVES, "top": round(top + 0.012, 3)}


def _rod(a, b, radius, sides=4):
    axis = (b - a).normalized()
    normal = axis.cross(Vector((0, 1, 0)))
    if normal.length < .1:
        normal = Vector((1, 0, 0))
    normal.normalize()
    other = axis.cross(normal).normalized()
    vertices = [tuple(p + radius * (math.cos(i * math.tau / sides + math.pi / 4) * normal +
                                    math.sin(i * math.tau / sides + math.pi / 4) * other))
                for p in (a, b) for i in range(sides)]
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, sides * 2))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    return poly(vertices, faces)


# ---------------------------------------------------------------- the striped awning

def striped_awning():
    frame = Piece("AwningFrame")
    canopy = Piece("AwningCanopy")
    ridge = EAVES + 0.42
    for x, y in corners():
        frame.add(cylinder((x, y), .07, .06, 0.0, 0.05, sides=8), "metalDark")
        frame.add(cylinder((x, y), .022, .022, 0.0, EAVES, sides=6, caps=False), "metal")
        frame.add(cylinder((x, y), .03, .03, EAVES - 0.02, EAVES + 0.02, sides=6), "metalDark")
    # Side rails under the eaves and the ridge pole.
    for y in (-(HALF - POST_IN), HALF - POST_IN):
        frame.add(box((-HALF + POST_IN, y - .015, EAVES - .03), (HALF - POST_IN, y + .015, EAVES)), "metal")
    frame.add(box((-HALF - 0.06, -.02, ridge - .02), (HALF + 0.06, .02, ridge + .02)), "metal")
    for x in (-(HALF - POST_IN), HALF - POST_IN):
        frame.add(_rod(Vector((x, -(HALF - POST_IN), EAVES)), Vector((x, 0.0, ridge)), .014), "metal")
        frame.add(_rod(Vector((x, HALF - POST_IN, EAVES)), Vector((x, 0.0, ridge)), .014), "metal")
    # The pitched canopy: eight stripes across each slope, blue and white.
    stripes = 8
    eave_out = HALF + 0.1
    low = EAVES - 0.04
    for slope in (-1.0, 1.0):
        for index in range(stripes):
            x0 = -HALF - 0.08 + index * (2 * HALF + 0.16) / stripes
            x1 = -HALF - 0.08 + (index + 1) * (2 * HALF + 0.16) / stripes
            rows = [((x0, slope * eave_out, low), (x1, slope * eave_out, low)), ((x0, 0.0, ridge + 0.03), (x1, 0.0, ridge + 0.03))]
            if slope < 0:
                rows = [((p[1][0], p[1][1], p[1][2]), (p[0][0], p[0][1], p[0][2])) for p in rows]
            colour = "carpetBlue" if index % 2 == 0 else "carpetWhite"
            canopy.add(sheet(rows, 0.012), colour)
            # The valance: a scalloped tab under each stripe along the eaves.
            y = slope * eave_out
            mid = (x0 + x1) / 2
            outline = [(x0, low), (x0, low - 0.1), (mid, low - 0.15), (x1, low - 0.1), (x1, low)]
            n = len(outline)
            vertices = [(x, y - .006, z) for x, z in outline] + [(x, y + .006, z) for x, z in outline]
            faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
            faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
            canopy.add(poly(vertices, faces), colour)
    # The gable ends: a triangle of white cloth at each end.
    for x in (-HALF - 0.08, HALF + 0.08):
        vertices = [(x, -eave_out, low), (x, eave_out, low), (x, 0.0, ridge + 0.03)]
        vertices += [(x + (0.006 if x > 0 else -0.006), vy, vz) for _, vy, vz in vertices]
        canopy.add(poly(vertices, [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]), "carpetWhite")
    frame.finish()
    canopy.finish()
    return {"cover": [2 * HALF, 2 * HALF], "eaves": low - 0.15, "top": round(ridge + 0.03, 3)}


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
    ("pergola_timber", timber_pergola, 1500, ["table.glb", "kitchenCabinet.glb (wood)", "benchCushion.glb"]),
    ("pergola_awning", striped_awning, 1500, ["chairModernCushion.glb (carpetBlue)", "lampRoundFloor.glb"]),
]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"issue": 380, "furniture_scale": FURNITURE_SCALE, "assets": {}}
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
            "nodes": sorted(n["name"] for n in doc["nodes"]), "nearest_kit": nearest, **extra}
    (OUTPUT / "pergola.metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: (v["triangles"], v["world_dimensions"]) for k, v in report["assets"].items()}, indent=1))


main()
