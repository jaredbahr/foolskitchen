"""Build the issue #589 walk-up hatch, seaside treats and evening dress kit.

blender --background --factory-startup --python tools/build_walkup.py
Optional external audit: append -- --manifest /absolute/outside/project/report.json

Writes assets/made/walkup/ and walkup.metrics.json (triangles, sizes, materials
and the hatch's named nodes and ledge anchors).

- Furniture-scale pieces (the hatch, the two machines, the evening kit) copy
  unchanged Furniture Kit material colours by name from the kit files. No
  textures, lights or emission. Every size below is a world size divided once
  by ArtScale.FURNITURE_SCALE, so the wrapper's uniform scale gives it back.
- Dish pieces (the shaved-ice topping and the paper cone of fries) are coloured
  only through the Food Kit's own colormap.png (every face's UVs point at one
  swatch, like the kit's food), referenced by relative path, never copied.
  Their sizes are divided by ArtScale.FOOD_SCALE.

Metres; Blender Z-up with the front at +Y; the glTF export is Y-up facing -Z.
The origin is the base centre, except the two tablecloths, whose origin is the
table's own base centre (they drop onto the table with the table's transform).
Deterministic: no random draws, so a rebuild writes the same geometry.
"""
from pathlib import Path
import argparse
import json
import math
import re
import struct
import sys

import bpy  # first: the bpy module provides bmesh and mathutils
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb, glb_metrics  # noqa: E402

ART_SCALE = (ROOT / "src/world/art_scale.gd").read_text()
FURNITURE_SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)", ART_SCALE).group(1))
FOOD_SCALE = float(re.search(r"const FOOD_SCALE: float = ([\d.]+)", ART_SCALE).group(1))
OUTPUT = ROOT / "assets/made/walkup"
KIT = ROOT / "assets/kenney/furniture"
FOOD_COLORMAP = ROOT / "assets/kenney/food/Textures/colormap.png"
COLORMAP_SIZE = 512

# Unchanged Furniture Kit colours, copied from these kit files by name.
KIT_SOURCES = {
    "wood": "kitchenCabinet.glb", "woodDark": "kitchenCabinet.glb", "metal": "kitchenCabinet.glb",
    "metalDark": "wall.glb", "metalMedium": "coatRack.glb", "metalLight": "bathroomCabinetDrawer.glb",
    "carpet": "benchCushion.glb", "carpetWhite": "bathroomCabinetDrawer.glb",
    "carpetBlue": "chairModernCushion.glb", "plant": "plantSmall1.glb", "lamp": "lampWall.glb",
    "glass": "bathroomMirror.glb", "_defaultMat": "wall.glb",
}

# Food Kit colormap swatch pixels (x, y): the centre of each kit column.
SWATCH = {
    "white": (464, 400),     # (255, 255, 255) paper
    "ice": (80, 150),        # (208, 232, 255) shaved ice
    "red": (464, 270),       # (207, 83, 79) strawberry syrup, paper band
    "blue": (16, 150),       # (103, 148, 217) blue syrup
    "yellow": (336, 270),    # (255, 192, 68) fries
    "golden": (352, 330),    # (255, 176, 70) fry tips
    "pink": (16, 400),       # (236, 130, 207)
}

# Active scale for the asset being built (furniture or food), and a uniform
# size factor some small props are authored at (so they read at game zoom).
_unit = FURNITURE_SCALE
_size = 1.0


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


def colormap_material():
    existing = bpy.data.materials.get("colormap")
    if existing:
        return existing
    image = bpy.data.images.load(str(FOOD_COLORMAP))
    image.name = "colormap"
    result = bpy.data.materials.new("colormap")
    result.use_nodes = True
    nodes = result.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    result.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return result


def uv_of(name):
    x, y = SWATCH[name]
    return ((x + 0.5) / COLORMAP_SIZE, 1.0 - (y + 0.5) / COLORMAP_SIZE)


# ---------------------------------------------------------------- geometry
# Every helper takes world metres; Piece.finish divides by the active unit.

class Piece:
    """One exported, named mesh: parts merge into one bmesh, each face keeping
    its material slot (and, for colormap faces, one swatch UV)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def add(self, part, token, swatch=None):
        if token not in self.slots:
            self.slots.append(token)
        index = self.slots.index(token)
        mapping = {vert: self.bm.verts.new(vert.co) for vert in part.verts}
        for face in part.faces:
            new = self.bm.faces.new([mapping[v] for v in face.verts])
            new.material_index = index
            new.smooth = False
            target = uv_of(swatch(face) if callable(swatch) else swatch) if swatch else (0.0, 0.0)
            for loop in new.loops:
                loop[self.uv].uv = target
        part.free()
        return self

    def finish(self):
        bmesh.ops.scale(self.bm, vec=Vector((_size / _unit,) * 3), verts=self.bm.verts)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for token in self.slots:
            mesh.materials.append(colormap_material() if token == "colormap" else kit_material(token))
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
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * .45),
                        segments=1, affect="EDGES")
    return bm


def poly(vertices, faces):
    bm = bmesh.new()
    verts = [bm.verts.new(Vector(v)) for v in vertices]
    for face in faces:
        bm.faces.new([verts[i] for i in face])
    return bm


def prism(points, z0, z1):
    """A vertical prism from a counter-clockwise outline (x, y)."""
    n = len(points)
    vertices = [(x, y, z0) for x, y in points] + [(x, y, z1) for x, y in points]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return poly(vertices, faces)


def cylinder(center, r_bottom, r_top, z0, z1, sides=8, caps=True, rotate=0.0):
    """A vertical (truncated) cone or cylinder around `center` (x, y)."""
    cx, cy = center
    ring = [(math.cos(rotate + i * math.tau / sides), math.sin(rotate + i * math.tau / sides)) for i in range(sides)]
    vertices = [(cx + r_bottom * c, cy + r_bottom * s, z0) for c, s in ring]
    vertices += [(cx + r_top * c, cy + r_top * s, z1) for c, s in ring]
    faces = [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    if caps:
        faces += [tuple(range(sides - 1, -1, -1)), tuple(range(sides, 2 * sides))]
    return poly(vertices, faces)


def rod(a, b, radius, sides=4):
    """A thin prism from point `a` to point `b`."""
    start, end = Vector(a), Vector(b)
    axis = (end - start).normalized()
    normal = axis.cross(Vector((0, 0, 1)))
    if normal.length < .1:
        normal = Vector((1, 0, 0))
    normal.normalize()
    other = axis.cross(normal).normalized()
    vertices = [tuple(p + radius * (math.cos(i * math.tau / sides + math.pi / 4) * normal +
                                    math.sin(i * math.tau / sides + math.pi / 4) * other))
                for p in (start, end) for i in range(sides)]
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, sides * 2))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    return poly(vertices, faces)


def wheel(center, radius, width, sides=10):
    """A wheel turning about the Y axis (its faces look along Y)."""
    cx, cy, cz = center
    ring = [(math.cos(i * math.tau / sides), math.sin(i * math.tau / sides)) for i in range(sides)]
    vertices = [(cx + radius * c, cy - width / 2, cz + radius * s) for c, s in ring]
    vertices += [(cx + radius * c, cy + width / 2, cz + radius * s) for c, s in ring]
    faces = [tuple(range(sides)), tuple(range(2 * sides - 1, sides - 1, -1))]
    faces += [(i + sides, (i + 1) % sides + sides, (i + 1) % sides, i) for i in range(sides)]
    return poly(vertices, faces)


def sloped_panel(x0, x1, y0, z0, y1, z1, thickness):
    """A flat panel from the wall line (y0, z0) out to (y1, z1), `thickness` thick."""
    vertices = [(x, y, z) for x in (x0, x1)
                for y, z in ((y0, z0), (y1, z1), (y1, z1 + thickness), (y0, z0 + thickness))]
    return poly(vertices, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                           (2, 3, 7, 6), (3, 0, 4, 7)])


def valance(x0, x1, y, top, side_drop, mid_drop, thickness=.012):
    """A flat valance tab hanging from `top` at the awning's front edge, with a
    pointed (scalloped) lower edge."""
    outline = [(x0, top), (x0, top - side_drop), ((x0 + x1) / 2, top - mid_drop), (x1, top - side_drop), (x1, top)]
    n = len(outline)
    vertices = [(x, y - thickness, z) for x, z in outline] + [(x, y, z) for x, z in outline]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    return poly(vertices, faces)


def anchor(name, location):
    """A named empty: exported as a plain glTF node at `location` (world metres)."""
    obj = bpy.data.objects.new(name, None)
    obj.location = tuple(v / _unit for v in location)
    bpy.context.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- walk-up hatch
# One shell wall cell (0.5 x 0.5 m, 1.4 m high) with a serving opening. +Y is
# the street (the customer side, the model's front); -Y is the room.

CELL = 0.5
HALF = CELL / 2
LEDGE_TOP = 0.50          # about counter height (ART_STYLE: counters ~0.5)
OPENING_TOP = 1.02
OPENING_HALF = 0.20       # 0.40 m wide: a person (0.37) fits the opening
OUTER_LEDGE = 0.12        # how far the ledges reach past each wall face
INNER_LEDGE = 0.11
HOUSING = (1.025, 1.10)   # the shutter's roll box, below the 1.10 canopy band
AWNING_TOP = 1.27
AWNING_FRONT = 1.12
AWNING_REACH = 0.23
AWNING_HALF = 0.28

HATCH_VARIANTS = {
    # frame, ledge, shutter slats, housing, menu header, awning style
    "wood": {"frame": "woodDark", "ledge": "wood", "slat": "metal", "housing": "woodDark",
             "header": "wood", "awning": "planks"},
    "painted": {"frame": "carpetWhite", "ledge": "woodDark", "slat": "metalMedium", "housing": "carpetWhite",
                "header": "carpet", "awning": "cloth"},
    "seaside": {"frame": "carpetWhite", "ledge": "wood", "slat": "metal", "housing": "carpetBlue",
                "header": "carpetBlue", "awning": "stripes"},
}


def hatch(style):
    v = HATCH_VARIANTS[style]
    y_out, y_in = HALF, -HALF
    # The wall around the opening, in the kit wall's plain surface; the game's
    # wall material replaces it (or hides it where it draws its own shell).
    body = Piece("WallBody")
    body.add(box((-HALF, y_in, 0), (HALF, y_out, LEDGE_TOP - .03)), "_defaultMat")
    for x0, x1 in ((-HALF, -OPENING_HALF), (OPENING_HALF, HALF)):
        body.add(box((x0, y_in, LEDGE_TOP - .03), (x1, y_out, OPENING_TOP)), "_defaultMat")
    body.add(box((-HALF, y_in, OPENING_TOP), (HALF, y_out, 1.4)), "_defaultMat")
    body.finish()

    # The serving ledge: one board through the opening, out past both faces.
    sill = Piece("LedgeSill")
    sill.add(box((-OPENING_HALF, y_in, LEDGE_TOP - .03), (OPENING_HALF, y_out, LEDGE_TOP), .004), v["ledge"])
    sill.finish()
    outer = Piece("LedgeOuter")
    outer.add(box((-HALF + .015, y_out - .01, LEDGE_TOP - .032), (HALF - .015, y_out + OUTER_LEDGE, LEDGE_TOP), .006),
              v["ledge"])
    for x in (-HALF + .05, HALF - .05):
        outer.add(rod((x, y_out + .004, LEDGE_TOP - .15), (x, y_out + OUTER_LEDGE - .02, LEDGE_TOP - .035), .011),
                  "metalDark")
    outer.finish()
    inner = Piece("LedgeInner")
    inner.add(box((-HALF + .015, y_in - INNER_LEDGE, LEDGE_TOP - .032), (HALF - .015, y_in + .01, LEDGE_TOP), .006),
              v["ledge"])
    inner.finish()

    # Frame round the opening on both faces, and the shutter's side guides.
    frame = Piece("Frame")
    for y0, y1 in ((y_out - .005, y_out + .022), (y_in - .022, y_in + .005)):
        for x0, x1 in ((-HALF + .005, -OPENING_HALF + .005), (OPENING_HALF - .005, HALF - .005)):
            frame.add(box((x0, y0, LEDGE_TOP), (x1, y1, OPENING_TOP + .02), .004), v["frame"])
        frame.add(box((-HALF + .005, y0, OPENING_TOP - .005), (HALF - .005, y1, OPENING_TOP + .03), .004),
                  v["frame"])
    # The reveal: the opening's sides and head lined in the frame colour, so
    # the open hatch reads as a framed hole through the wall.
    for x0, x1 in ((-OPENING_HALF, -OPENING_HALF + .012), (OPENING_HALF - .012, OPENING_HALF)):
        frame.add(box((x0, y_in, LEDGE_TOP), (x1, y_out, OPENING_TOP)), v["frame"])
    frame.add(box((-OPENING_HALF, y_in, OPENING_TOP - .012), (OPENING_HALF, y_out, OPENING_TOP)), v["frame"])
    for x in (-OPENING_HALF + .008, OPENING_HALF - .008):
        frame.add(box((x - .008, y_out + .02, LEDGE_TOP), (x + .008, y_out + .034, HOUSING[0])), "metalDark")
    frame.finish()

    housing = Piece("ShutterHousing")
    housing.add(box((-HALF + .01, y_out + .005, HOUSING[0]), (HALF - .01, y_out + .075, HOUSING[1]), .012),
                v["housing"])
    housing.finish()

    # Closed: the slats come down to the ledge, a handle on the bottom bar.
    closed = Piece("ShutterClosed")
    slats = 7
    top, bottom = HOUSING[0], LEDGE_TOP + .022
    step = (top - bottom) / slats
    closed.add(box((-OPENING_HALF + .004, y_out + .016, bottom), (OPENING_HALF - .004, y_out + .022, top)), "metalDark")
    for i in range(slats):
        z0 = bottom + i * step
        closed.add(box((-OPENING_HALF + .004, y_out + .022, z0 + .006), (OPENING_HALF - .004, y_out + .034, z0 + step),
                       .002), v["slat"])
    closed.add(box((-OPENING_HALF + .004, y_out + .02, LEDGE_TOP), (OPENING_HALF - .004, y_out + .038, bottom + .003),
                   .003), "metalDark")
    closed.add(box((-.04, y_out + .038, LEDGE_TOP + .006), (.04, y_out + .05, LEDGE_TOP + .016)), "metalDark")
    closed.finish()

    # Open: the slats are rolled into the housing; only the bottom bar shows.
    opened = Piece("ShutterOpen")
    opened.add(box((-OPENING_HALF + .004, y_out + .02, HOUSING[0] - .022), (OPENING_HALF - .004, y_out + .038,
                                                                          HOUSING[0] + .002), .003), "metalDark")
    opened.add(box((-.04, y_out + .038, HOUSING[0] - .02), (.04, y_out + .05, HOUSING[0] - .01)), "metalDark")
    opened.finish()

    awning = Piece("Awning")
    reach = y_out + AWNING_REACH
    if v["awning"] == "planks":
        boards = 5
        width = 2 * AWNING_HALF / boards
        for i in range(boards):
            x0 = -AWNING_HALF + i * width
            awning.add(sloped_panel(x0 + .003, x0 + width - .003, y_out, AWNING_TOP - .02, reach, AWNING_FRONT, .022),
                       "woodDark" if i % 2 else "wood")
        awning.add(box((-AWNING_HALF, reach - .025, AWNING_FRONT - .025), (AWNING_HALF, reach + .004, AWNING_FRONT + .01),
                       .004), "woodDark")
    else:
        stripes = 7 if v["awning"] == "stripes" else 1
        width = 2 * AWNING_HALF / stripes
        for i in range(stripes):
            x0 = -AWNING_HALF + i * width
            cloth = "carpet" if v["awning"] == "cloth" else ("carpetBlue" if i % 2 == 0 else "carpetWhite")
            awning.add(sloped_panel(x0, x0 + width, y_out, AWNING_TOP - .016, reach, AWNING_FRONT, .016), cloth)
            # The valance: a short drop at the front edge, one scallop per stripe.
            scallops = 5 if v["awning"] == "cloth" else 1
            for k in range(scallops):
                a = x0 + k * width / scallops
                awning.add(valance(a, a + width / scallops, reach, AWNING_FRONT + .016, .035, .06), cloth)
    for x in (-AWNING_HALF + .04, AWNING_HALF - .04):
        awning.add(rod((x, y_out + .005, HOUSING[1] + .005), (x, reach - .03, AWNING_FRONT + .005), .008), "metalDark")
    awning.finish()

    # The menu board under the outer ledge: a dark board in a frame, a
    # coloured header and four cream lines with price dots.
    menu = Piece("MenuBoard")
    face = y_out + .018
    menu.add(box((-.165, y_out - .004, .14), (.165, face, .40), .005), "woodDark" if style == "wood" else v["frame"])
    menu.add(box((-.145, face - .004, .16), (.145, face + .003, .38)), "metalDark")
    menu.add(box((-.12, face + .002, .345), (.12, face + .007, .368)), v["header"])
    for i, z in enumerate((.30, .265, .23, .195)):
        menu.add(box((-.115, face + .002, z), (.035 - .02 * (i % 2), face + .006, z + .011)), "carpetWhite")
        menu.add(box((.075, face + .002, z), (.115, face + .006, z + .011)), "carpetWhite")
    menu.finish()

    anchor("OuterLedgeTop", (0, y_out + OUTER_LEDGE / 2, LEDGE_TOP))
    anchor("InnerLedgeTop", (0, y_in - INNER_LEDGE / 2, LEDGE_TOP))
    return {"anchors": {"OuterLedgeTop": [0, LEDGE_TOP, -(y_out + OUTER_LEDGE / 2)],
                        "InnerLedgeTop": [0, LEDGE_TOP, -(y_in - INNER_LEDGE / 2)]},
            "opening": {"half_width": OPENING_HALF, "bottom": LEDGE_TOP, "top": OPENING_TOP}}


# ---------------------------------------------------------------- soft-serve machine
# A counter appliance for the top of a kitchen cabinet, like the kit coffee machine.

def soft_serve():
    m = Piece("SoftServeMachine")
    w, d = .15, .12
    m.add(box((-w, -d, 0), (w, d, .27), .012), "metal")
    m.add(box((-w + .01, -d + .01, .27), (w - .01, d - .01, .285), .004), "metalMedium")
    # Two hoppers with lids on top.
    for x in (-.07, .07):
        m.add(box((x - .06, -.085, .285), (x + .06, .075, .325), .01), "metalLight")
        m.add(cylinder((x, -.005), .016, .016, .325, .338, 6), "metalDark")
    # The dispensing bay: a dark recess with a drip tray and grille.
    m.add(box((-.12, d - .002, .03), (.12, d + .006, .15), .004), "metalDark")
    m.add(box((-.12, d - .02, .03), (.12, d + .045, .045), .004), "metalMedium")
    for x in (-.08, 0, .08):
        m.add(box((x - .03, d + .006, .045), (x + .03, d + .04, .049)), "metal")
    # Spout head with three star nozzles and three pull handles.
    m.add(box((-.13, d - .01, .15), (.13, d + .05, .205), .008), "metalLight")
    knobs = ("carpetWhite", "woodDark", "carpet")   # vanilla, chocolate, strawberry
    for x, knob in zip((-.075, 0, .075), knobs):
        m.add(cylinder((x, d + .025), .016, .012, .118, .15, 6), "metal")
        m.add(cylinder((x, d + .025), .006, .006, .108, .118, 6), "metalDark")
        m.add(rod((x, d + .035, .2), (x, d + .065, .255), .007), "metalDark")
        m.add(box((x - .016, d + .05, .25), (x + .016, d + .082, .272), .005), knob)
    # A small control panel with two warm lamps.
    m.add(box((-.06, d - .002, .215), (.06, d + .004, .255), .003), "metalDark")
    for x in (-.03, .03):
        m.add(box((x - .008, d + .003, .228), (x + .008, d + .007, .242)), "lamp")
    # A cone tube on the right side, a cone showing at its open top.
    m.add(cylinder((w + .03, .02), .028, .028, .06, .29, 8), "metalLight")
    m.add(cylinder((w + .03, .02), .022, .022, .29, .295, 8), "metalDark")
    m.add(cylinder((w + .03, .02), .004, .024, .245, .33, 8), "wood")
    m.add(box((w - .002, .0, .16), (w + .006, .04, .2)), "metalDark")
    m.finish()
    return {}


# ---------------------------------------------------------------- shaved-ice cart
# A two-cell (1.0 x 0.5 m) push cart: the counter is ~0.47 high, under a
# small striped canopy, with the ice shaver, syrups and paper cups on top.

def shaved_ice_cart():
    cart = Piece("ShavedIceCart")
    hx, hy, top = .37, .17, .45
    cart.add(box((-hx, -hy, .09), (hx, hy, top), .012), "carpetWhite")
    cart.add(box((-hx - .004, -hy - .004, .25), (hx + .004, hy + .004, .31), .006), "carpetBlue")
    cart.add(box((-hx - .02, -hy - .02, top), (hx + .02, hy + .02, top + .025), .006), "wood")
    # Two wheels at one end, two short legs at the other.
    for y in (-hy - .025, hy + .025):
        cart.add(wheel((-.22, y, .1), .1, .03, 10), "metalDark")
        cart.add(wheel((-.22, y + (.016 if y > 0 else -.016), .1), .03, .006, 6), "metal")
    for y in (-hy + .04, hy - .04):
        cart.add(box((.26, y - .02, 0), (.30, y + .02, .1), .006), "metalDark")
    # The push handle.
    cart.add(rod((hx, -.12, .38), (hx + .08, -.12, .45), .012), "metalDark")
    cart.add(rod((hx, .12, .38), (hx + .08, .12, .45), .012), "metalDark")
    cart.add(rod((hx + .08, -.14, .45), (hx + .08, .14, .45), .016), "woodDark")
    # The ice shaver: a metal box, a clear hopper with an ice block, a crank.
    sx, base = -.17, top + .025
    cart.add(box((sx - .085, -.075, base), (sx + .085, .075, base + .11), .01), "metal")
    cart.add(box((sx - .05, .06, base + .015), (sx + .05, .085, base + .07), .004), "metalDark")
    cart.add(box((sx - .07, -.06, base + .11), (sx + .07, .06, base + .21), .006), "glass")
    cart.add(box((sx - .042, -.035, base + .12), (sx + .042, .035, base + .19), .01), "metalLight")
    cart.add(box((sx - .075, -.065, base + .21), (sx + .075, .065, base + .23), .006), "metal")
    cart.add(rod((sx, 0, base + .23), (sx, 0, base + .27), .01), "metalDark")
    cart.add(rod((sx, 0, base + .27), (sx + .08, 0, base + .27), .008), "metalDark")
    cart.add(rod((sx + .08, 0, base + .27), (sx + .08, 0, base + .3), .01), "carpet")
    # Four syrup bottles with white pump tops.
    for i, syrup in enumerate(("carpet", "carpetBlue", "lamp", "plant")):
        x = .04 + i * .058
        cart.add(cylinder((x, .06), .022, .022, base, base + .1, 6), syrup)
        cart.add(cylinder((x, .06), .014, .008, base + .1, base + .125, 6), "carpetWhite")
        cart.add(rod((x, .06, base + .12), (x, .085, base + .12), .004), "carpetWhite")
    # A stack of paper cups.
    cart.add(cylinder((.27, -.07), .024, .032, base, base + .05, 8), "carpetWhite")
    cart.add(cylinder((.27, -.07), .026, .034, base + .05, base + .085, 8), "carpetWhite")
    # A beach parasol on a pole at the back corner: eight blue-and-white
    # panels, tilted a little towards the front, clear of the counter.
    px, py, pole_top = .3, -hy + .02, 1.08
    cart.add(rod((px, py, top + .02), (px, py, pole_top), .012), "metal")
    centre = Vector((px - .05, 0, pole_top + .03))
    tilt = Vector((-.05, .08, 0)).normalized() * .07
    panels, radius = 8, .265
    rim = []
    for i in range(panels):
        a = i * math.tau / panels
        point = centre + Vector((radius * math.cos(a), radius * math.sin(a), -.11))
        point.z += tilt.dot(Vector((math.cos(a), math.sin(a), 0))) * -1.2
        rim.append(point)
    for i in range(panels):
        cloth = "carpetBlue" if i % 2 == 0 else "carpetWhite"
        a, b = rim[i], rim[(i + 1) % panels]
        cart.add(poly([tuple(centre), tuple(a), tuple(b), tuple(centre), tuple(b), tuple(a)],
                      [(0, 1, 2), (3, 4, 5)]), cloth)
        # A short scalloped drop at each panel's edge.
        mid = (a + b) / 2
        cart.add(poly([tuple(a), tuple(b), tuple(mid + Vector((0, 0, -.035))),
                       tuple(a), tuple(mid + Vector((0, 0, -.035))), tuple(b)], [(0, 1, 2), (3, 4, 5)]), cloth)
    cart.add(cylinder((centre.x, centre.y), .012, .004, centre.z, centre.z + .035, 6), "metal")
    cart.finish()
    return {}


# ---------------------------------------------------------------- evening dress kit

# The kit table tops these cloths drop onto, measured from the kit files.
TABLE_TOP = {"rect": None, "round": None}


def _kit_top(name):
    """Top height and half extents (world metres) of a kit table, from its own
    bounds (PropView stands it on the floor, centred on its footprint)."""
    size = glb_metrics(KIT / name)["dimensions"]
    return {"top": size[1] * FURNITURE_SCALE, "half_x": size[0] / 2 * FURNITURE_SCALE,
            "half_z": size[2] / 2 * FURNITURE_SCALE}


def tablecloth_rect():
    """For the kit `table` (and `tableGlass`, `tableCross`: the same top)."""
    t = _kit_top("table.glb")
    cloth = Piece("Tablecloth")
    hx, hy, top, drop, t_ = t["half_x"] + .012, t["half_z"] + .012, t["top"] + .004, .15, .008
    cloth.add(box((-hx, -hy, top - t_), (hx, hy, top), .003), "carpetWhite")
    # Four skirts hanging straight down from the edges, a little proud at the hem.
    for x0, y0, x1, y1 in ((-hx, hy - .006, hx, hy + .004), (-hx, -hy - .004, hx, -hy + .006),
                           (hx - .006, -hy, hx + .004, hy), (-hx - .004, -hy, -hx + .006, hy)):
        cloth.add(box((x0, y0, top - drop), (x1, y1, top - t_ + .002)), "carpetWhite")
    for x0, y0, x1, y1 in ((-hx - .002, hy - .004, hx + .002, hy + .008), (-hx - .002, -hy - .008, hx + .002, -hy + .004),
                           (hx - .004, -hy - .002, hx + .008, hy + .002), (-hx - .008, -hy - .002, -hx + .004, hy + .002)):
        cloth.add(box((x0, y0, top - drop), (x1, y1, top - drop + .018)), "carpetWhite")
    cloth.finish()
    # A slim runner down the length, in the kit's cloth red (its own node, so
    # it can be hidden or painted on its own).
    runner = Piece("Runner")
    runner.add(box((-hx - .006, -.055, top), (hx + .006, .055, top + .003)), "carpet")
    runner.add(box((hx - .002, -.055, top - .09), (hx + .008, .055, top)), "carpet")
    runner.add(box((-hx - .008, -.055, top - .09), (-hx + .002, .055, top)), "carpet")
    runner.finish()
    return {"table": "table.glb", "table_top": round(t["top"], 4), "drop": drop}


def tablecloth_round():
    """For the kit's six-sided `tableRound`: corners front and back (+-Y)."""
    t = _kit_top("tableRound.glb")
    radius = t["half_z"] + .018
    top, drop, sides = t["top"] + .004, .15, 6
    cloth = Piece("Tablecloth")
    cloth.add(cylinder((0, 0), radius, radius, top - .008, top, sides, rotate=math.pi / 2), "carpetWhite")
    # The skirt hangs from the six edges and flares a little at each corner
    # and between them, in soft folds (twelve points round the hem).
    ring_top, ring_low = [], []
    for i in range(sides * 2):
        a = math.pi / 2 + i * math.pi / sides
        corner = i % 2 == 0
        r_top = radius if corner else radius * math.cos(math.pi / sides)
        ring_top.append((r_top * math.cos(a), r_top * math.sin(a)))
        r_low = r_top + (.035 if corner else .016)
        ring_low.append((r_low * math.cos(a), r_low * math.sin(a)))
    n = len(ring_top)
    vertices = [(x, y, top - .006) for x, y in ring_top] + [(x, y, top - drop) for x, y in ring_low]
    faces = [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    cloth.add(poly(vertices, faces), "carpetWhite")
    cloth.finish()
    return {"table": "tableRound.glb", "table_top": round(t["top"], 4), "drop": drop}


def candle_holder():
    global _size
    _size = 1.3
    c = Piece("CandleHolder")
    c.add(cylinder((0, 0), .032, .028, 0, .008, 8), "metalDark")
    c.add(cylinder((0, 0), .008, .008, .008, .045, 6), "metalDark")
    c.add(cylinder((0, 0), .024, .02, .045, .055, 8), "metalDark")
    # A glass chimney round the candle.
    c.add(cylinder((0, 0), .026, .03, .055, .135, 8, caps=False), "glass")
    c.add(cylinder((0, 0), .012, .012, .055, .1, 6), "carpetWhite")
    c.add(rod((0, 0, .1), (0, 0, .106), .0018), "metalDark")
    flame = [(0, 0, .104)] + [(.007 * math.cos(i * math.tau / 4), .007 * math.sin(i * math.tau / 4), .112)
                             for i in range(4)] + [(0, 0, .13)]
    c.add(poly(flame, [(0, 2, 1), (0, 3, 2), (0, 4, 3), (0, 1, 4), (1, 2, 5), (2, 3, 5), (3, 4, 5), (4, 1, 5)]),
          "lamp")
    c.finish()
    return {}


def small_vase():
    global _size
    _size = 1.3
    v = Piece("SmallVase")
    v.add(cylinder((0, 0), .022, .032, 0, .04, 8, rotate=math.pi / 8), "carpetBlue")
    v.add(cylinder((0, 0), .032, .016, .04, .075, 8, rotate=math.pi / 8), "carpetBlue")
    v.add(cylinder((0, 0), .016, .02, .075, .09, 8, rotate=math.pi / 8), "carpetBlue")
    stems = ((-.02, .005, .15, "carpet"), (.018, -.008, .14, "carpetWhite"), (.002, .018, .165, "lamp"))
    for x, y, height, petal in stems:
        v.add(rod((0, 0, .08), (x, y, height), .003), "plant")
        v.add(box((x - .012, y - .012, height - .01), (x + .012, y + .012, height + .012), .005), petal)
    for x, y in ((.02, .012), (-.014, -.016)):
        leaf = [(0, 0, .088), (x * 1.6, y * 1.6, .11), (x * 2.2 - y * .3, y * 2.2 + x * .3, .1)]
        v.add(poly(leaf + leaf[::-1], [(0, 1, 2), (3, 4, 5)]), "plant")
    v.finish()
    return {}


# ---------------------------------------------------------------- dishes (food scale)

def shaved_ice_topping():
    """Shaved ice heaped in the Food Kit's ice-cream cup, two syrups on top.
    Sized for `ice-cream-cup.glb` (its rim, at the food scale)."""
    p = Piece("ShavedIce")
    cup = glb_metrics(ROOT / "assets/kenney/food/ice-cream-cup.glb")
    rim_y = cup["aabb_max"][1] * FOOD_SCALE
    radius = (cup["dimensions"][0] / 2) * FOOD_SCALE * .9
    sides = 10
    rings = [(radius * 1.06, 0.0), (radius * 1.04, .012), (radius * .86, .026), (radius * .55, .04), (radius * .2, .05)]
    verts = []
    for r, z in rings:
        verts += [(r * math.cos(i * math.tau / sides), r * math.sin(i * math.tau / sides), rim_y - .006 + z)
                  for i in range(sides)]
    verts.append((0, 0, rim_y - .006 + .056))
    peak = len(verts) - 1
    faces = [tuple(range(sides - 1, -1, -1))]
    colours = []
    for k in range(len(rings) - 1):
        for i in range(sides):
            a, b = k * sides + i, k * sides + (i + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces += [((len(rings) - 1) * sides + i, (len(rings) - 1) * sides + (i + 1) % sides, peak) for i in range(sides)]

    def colour(face):
        z = max(v.co.z for v in face.verts) - (rim_y - .006)
        if z < .018:
            return "white"
        angle = math.atan2(sum(v.co.y for v in face.verts), sum(v.co.x for v in face.verts))
        return "red" if math.cos(angle - .6) > 0 else "blue"
    p.add(poly(verts, faces), "colormap", colour)
    obj = p.finish()
    return obj, {"sits_on": "ice-cream-cup.glb", "rim_height": round(rim_y, 4)}


def fries_cone():
    """A paper cone of fries, standing on its small flat tip."""
    p = Piece("FriesCone")
    sides = 8
    p.add(cylinder((0, 0), .012, .042, 0, .095, sides, rotate=math.pi / sides), "colormap",
          lambda face: "red" if min(v.co.z for v in face.verts) > .05 else "white")
    p.add(cylinder((0, 0), .04, .04, .09, .094, sides, caps=True, rotate=math.pi / sides), "colormap", "golden")
    sticks = ((-.018, -.01, .135, .2), (.0, -.022, .145, -.15), (.022, -.006, .13, .1), (-.008, .018, .14, -.25),
              (.016, .018, .128, .3), (.004, .0, .152, .05), (-.026, .008, .124, -.1), (-.012, -.024, .128, .25),
              (.026, .01, .122, -.2), (.012, -.016, .138, .0), (-.022, -.004, .146, .15), (.0, .026, .126, .1))
    for x, y, height, lean in sticks:
        stick = box((x - .006, y - .006, .07), (x + .006, y + .006, height))
        for vert in stick.verts:
            if vert.co.z > .1:
                vert.co.x += lean * (vert.co.z - .1)
        p.add(stick, "colormap", lambda face: "golden" if min(v.co.z for v in face.verts) > height - .001 else "yellow")
    p.finish()
    return {}


# ---------------------------------------------------------------- export

def link_food_colormap(path: Path) -> None:
    """Point the material at the Food Kit's own colormap by relative path."""
    data = path.read_bytes()
    json_size, _kind = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20:20 + json_size])
    rest = data[20 + json_size:]
    document["images"] = [{"uri": "../../kenney/food/Textures/colormap.png", "name": "colormap"}]
    document["samplers"] = [{"magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497}]
    document["textures"] = [{"sampler": 0, "source": 0, "name": "colormap"}]
    for material in document["materials"]:
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
        material["pbrMetallicRoughness"].pop("baseColorFactor", None)
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for datablock in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(datablock):
            datablock.remove(item)


def export(path: Path, colormap: bool) -> None:
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True,
                              export_animations=False, export_cameras=False, export_lights=False,
                              export_extras=False, export_image_format="NONE" if colormap else "AUTO")
    if colormap:
        link_food_colormap(path)


# (asset id, builder, unit, triangle budget, nearest kit pieces)
ASSETS = [
    *[(f"walkup_hatch_{style}", lambda s=style: hatch(s), "furniture", 1500,
       ["wallWindow.glb", "wallDoorway.glb", "kitchenBar.glb"]) for style in HATCH_VARIANTS],
    ("soft_serve_machine", soft_serve, "furniture", 1500, ["kitchenCoffeeMachine.glb", "kitchenBlender.glb"]),
    ("shaved_ice_cart", shaved_ice_cart, "furniture", 1500, ["kitchenBar.glb", "kitchenCabinet.glb"]),
    ("tablecloth_rect", tablecloth_rect, "furniture", 300, ["tableCloth.glb", "table.glb"]),
    ("tablecloth_round", tablecloth_round, "furniture", 300, ["tableRound.glb"]),
    ("candle_holder", candle_holder, "furniture", 300, ["lampRoundTable.glb", "lampSquareTable.glb"]),
    ("small_vase", small_vase, "furniture", 300, ["plantSmall1.glb"]),
    ("shaved_ice_topping", shaved_ice_topping, "food", 300, ["ice-cream-cup.glb"]),
    ("fries_cone", fries_cone, "food", 300, ["fries.glb", "ice-cream-cne.glb"]),
]


def main():
    global _unit, _size
    args = argparse.ArgumentParser()
    args.add_argument("--manifest", type=Path)
    options = args.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"issue": 589, "furniture_scale": FURNITURE_SCALE, "food_scale": FOOD_SCALE, "assets": {}}
    for asset_id, builder, unit, budget, nearest in ASSETS:
        clear_scene()
        _unit = FURNITURE_SCALE if unit == "furniture" else FOOD_SCALE
        _size = 1.0
        extra = builder()
        if isinstance(extra, tuple):
            extra = extra[1]
        path = OUTPUT / (asset_id + ".glb")
        export(path, unit == "food")
        measured = glb_metrics(path)
        doc, _ = read_glb(path)
        assert measured["triangles"] < budget, (asset_id, measured["triangles"])
        assert not doc.get("animations")
        if unit == "furniture":
            assert not doc.get("images"), asset_id + " uses kit material colours only"
        nodes = sorted(n["name"] for n in doc["nodes"])
        report["assets"][asset_id] = {
            "triangles": measured["triangles"], "budget": budget, "scale": unit,
            "world_dimensions": [round(v * _unit, 4) for v in measured["dimensions"]],
            "materials": sorted(m["name"] for m in doc["materials"]), "nodes": nodes,
            "nearest_kit": nearest, **extra}
    (OUTPUT / "walkup.metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    if options.manifest:
        target = options.manifest.resolve()
        if target.is_relative_to(ROOT):
            raise ValueError("Review manifests must remain outside the shipping project")
        target.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: (v["triangles"], v["world_dimensions"]) for k, v in report["assets"].items()}, indent=1))


main()
