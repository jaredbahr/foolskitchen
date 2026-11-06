"""Build the issue #125 aquarium pieces with Blender (or the `bpy` module).

blender --background --factory-startup --python tools/build_aquarium.py
(or: python tools/build_aquarium.py, with the `bpy` wheel installed)

Writes assets/made/aquarium/: aquarium_2.glb (2x1 tank on its stand),
aquarium_3.glb (3x1), four tiny fish (fish_neon/orange/yellow/guppy.glb) and
aquarium.metrics.json (triangles, bounds and the swim box each wrapper uses).

Tanks: chunky, slightly bevelled, flat-shaded boxes like the Furniture Kit
cabinets, coloured only with unchanged Furniture Kit material colours copied
from the kit files, plus the two named exceptions the issue approves:
  - AQUARIUM_GLASS: the transparent, slightly blue glass (the one new material);
  - AQUARIUM_GLOW: the soft blue-green glow of the lit water surface and the
    light's strip (a glowing part, ART_STYLE section 3): emissive and slightly
    see-through. It adds no light node.
Fish: under 100 triangles each, coloured only through the Food Kit's own
colormap.png (every face's UVs point at one palette swatch, like the kit's
food and the cat), referenced by relative path, never copied.

Metres; Blender Z-up with the front at +Y; the glTF export is Y-up facing -Z
with the origin at the base centre. Every size below is a world size at the
shared furniture scale (read from src/world/art_scale.gd) and is divided by it
once, so the wrapper's uniform ArtScale gives these exact world sizes.
Deterministic: no random draws, so a rebuild writes the same geometry.
"""
from pathlib import Path
import json
import math
import re
import struct
import sys

import bpy  # first: the bpy module provides bmesh and mathutils
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb, glb_metrics  # noqa: E402

SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)",
                        (ROOT / "src/world/art_scale.gd").read_text()).group(1))
OUTPUT = ROOT / "assets/made/aquarium"
KIT = ROOT / "assets/kenney/furniture"
FOOD_COLORMAP = ROOT / "assets/kenney/food/Textures/colormap.png"
COLORMAP_SIZE = 512

# Unchanged Furniture Kit colours, copied from these kit files by name.
KIT_SOURCES = {
    "woodDark": "kitchenCabinet.glb", "wood": "kitchenCabinet.glb", "metal": "kitchenCabinet.glb",
    "metalDark": "wall.glb", "metalMedium": "coatRack.glb", "plant": "plantSmall1.glb",
    "carpetWhite": "bathroomCabinetDrawer.glb",
}
# The approved new glass: the kit's glass made slightly blue and clearer, so
# the planted inside reads through it. Linear base colour and alpha.
AQUARIUM_GLASS = (0.55, 0.80, 1.0, 0.2)
# The approved emissive strip under the tank light: a soft blue-green.
AQUARIUM_GLOW = (0.04, 0.45, 0.5)
AQUARIUM_GLOW_STRENGTH = 1.0
AQUARIUM_GLOW_ALPHA = 0.28

# Food Kit colormap swatch pixels (x, y), picked for bright tetra/guppy colours.
SWATCH = {
    "blue": (16, 150),      # (103, 148, 217) neon stripe
    "red": (464, 270),      # (207, 83, 79) neon tail half
    "white": (464, 400),    # (255, 255, 255) belly
    "orange": (400, 270),   # (255, 126, 68) platy
    "amber": (432, 270),    # (255, 155, 68) fins
    "yellow": (336, 270),   # (255, 192, 68) lemon tetra
    "purple": (144, 150),   # (168, 120, 232) guppy body
    "pink": (16, 400),      # (236, 130, 207) guppy tail
    "dark": (208, 400),     # (56, 56, 61) eyes
}

STAND_HEIGHT = 0.30
TOP_THICK = 0.03
DEPTH = 0.44
TANK_HEIGHT = 0.27
BASE_THICK = 0.025
RIM = 0.018
PANE = 0.006
BED_FRONT = 0.03
BED_RISE = 0.04


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


def glass_material():
    existing = bpy.data.materials.get("aquariumGlass")
    if existing:
        return existing
    result = bpy.data.materials.new("aquariumGlass")
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*AQUARIUM_GLASS[:3], 1.0)
    shader.inputs["Alpha"].default_value = AQUARIUM_GLASS[3]
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    result.diffuse_color = AQUARIUM_GLASS
    result.surface_render_method = "BLENDED"
    result.use_backface_culling = False
    return result


def glow_material():
    existing = bpy.data.materials.get("aquariumGlow")
    if existing:
        return existing
    result = bpy.data.materials.new("aquariumGlow")
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*AQUARIUM_GLOW, 1.0)
    shader.inputs["Emission Color"].default_value = (*AQUARIUM_GLOW, 1.0)
    shader.inputs["Emission Strength"].default_value = AQUARIUM_GLOW_STRENGTH
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Alpha"].default_value = AQUARIUM_GLOW_ALPHA
    result.diffuse_color = (*AQUARIUM_GLOW, AQUARIUM_GLOW_ALPHA)
    result.surface_render_method = "BLENDED"
    result.use_backface_culling = False
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


def material_for(token):
    if token == "glass":
        return glass_material()
    if token == "glow":
        return glow_material()
    return kit_material(token)


# ---------------------------------------------------------------- geometry

class Piece:
    """One exported mesh: parts are appended into a single bmesh, each face
    carrying its material slot (and a colormap UV for the fish)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def slot(self, token):
        if token not in self.slots:
            self.slots.append(token)
        return self.slots.index(token)

    def add(self, part, token, colour_of=None):
        """Merge a temporary bmesh. `colour_of(face)` picks a swatch per face."""
        index = self.slot(token)
        mapping = {}
        for vert in part.verts:
            mapping[vert] = self.bm.verts.new(vert.co)
        for face in part.faces:
            new = self.bm.faces.new([mapping[v] for v in face.verts])
            new.material_index = index
            new.smooth = False
            target = uv_of(colour_of(face)) if colour_of else (0.0, 0.0)
            for loop in new.loops:
                loop[self.uv].uv = target
        part.free()

    def finish(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for token in self.slots:
            mesh.materials.append(colormap_material() if token == "colormap" else material_for(token))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def uv_of(name):
    x, y = SWATCH[name]
    return ((x + 0.5) / COLORMAP_SIZE, 1.0 - (y + 0.5) / COLORMAP_SIZE)


def box_bm(size, center, bevel=0.0, taper=None):
    """A box of world size `size` centred at `center` (world metres, Z-up),
    optionally bevelled; `taper` (sx, sz) pinches the -Y end (a fish tail)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        co = Vector((vert.co.x * size[0], vert.co.y * size[1], vert.co.z * size[2]))
        if taper is not None and vert.co.y < 0:
            co.x *= taper[0]
            co.z *= taper[1]
        vert.co = co
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def poly_bm(vertices, faces):
    bm = bmesh.new()
    verts = [bm.verts.new(Vector(v)) for v in vertices]
    for face in faces:
        bm.faces.new([verts[i] for i in face])
    return bm


def scaled(bm):
    bmesh.ops.scale(bm, vec=Vector((1 / SCALE,) * 3), verts=bm.verts)
    return bm


def wobble(seed, amount):
    """A fixed pseudo-random offset in [-amount, amount] (no RNG state)."""
    value = math.sin(seed * 12.9898 + 78.233) * 43758.5453
    return (value - math.floor(value) - 0.5) * 2.0 * amount


# ---------------------------------------------------------------- the tank

def stand(piece, width, doors):
    piece.add(scaled(box_bm((width, DEPTH, STAND_HEIGHT), (0, 0, STAND_HEIGHT / 2), 0.008)), "woodDark")
    piece.add(scaled(box_bm((width + 0.012, DEPTH + 0.012, TOP_THICK),
                            (0, 0, STAND_HEIGHT + TOP_THICK / 2), 0.006)), "woodDark")
    gap = 0.014
    span = width - 0.05
    door_w = (span - gap * (doors - 1)) / doors
    door_h = STAND_HEIGHT - 0.06
    for i in range(doors):
        x = -span / 2 + door_w / 2 + i * (door_w + gap)
        piece.add(scaled(box_bm((door_w, 0.014, door_h), (x, DEPTH / 2 + 0.004, 0.035 + door_h / 2), 0.004)),
                  "wood")
        # Handles sit at the inner edges of each pair, like kitchenCabinet's.
        side = 1 if (i % 2 == 0) else -1
        if doors % 2 == 1 and i == doors - 1:
            side = -1
        hx = x + side * (door_w / 2 - 0.03)
        piece.add(scaled(box_bm((0.014, 0.012, 0.06), (hx, DEPTH / 2 + 0.016, 0.035 + door_h * 0.62), 0.003)),
                  "metal")


def tank(piece, width):
    """The glass box with its dark rims, background, water and light."""
    y0 = STAND_HEIGHT + TOP_THICK
    tw, td, th = width - 0.04, DEPTH - 0.05, TANK_HEIGHT
    piece.add(scaled(box_bm((tw, td, BASE_THICK), (0, 0, y0 + BASE_THICK / 2), 0.004)), "metalDark")
    top = y0 + th
    # Top rim: four bars.
    piece.add(scaled(box_bm((tw, RIM, 0.02), (0, td / 2 - RIM / 2, top - 0.01), 0.003)), "metalDark")
    piece.add(scaled(box_bm((tw, RIM, 0.02), (0, -td / 2 + RIM / 2, top - 0.01), 0.003)), "metalDark")
    for sx in (-1, 1):
        piece.add(scaled(box_bm((RIM, td - 2 * RIM, 0.02), (sx * (tw / 2 - RIM / 2), 0, top - 0.01), 0.003)),
                  "metalDark")
        for sy in (-1, 1):
            # Slim corner posts tie the rims together, as a framed tank.
            piece.add(scaled(box_bm((0.012, 0.012, th - BASE_THICK - 0.02),
                                    (sx * (tw / 2 - 0.006), sy * (td / 2 - 0.006),
                                     y0 + BASE_THICK + (th - BASE_THICK - 0.02) / 2))), "metalDark")
    pane_low, pane_high = y0 + BASE_THICK, top - 0.02
    ph = pane_high - pane_low
    pz = pane_low + ph / 2
    piece.add(scaled(box_bm((tw - 0.012, PANE, ph), (0, td / 2 - PANE / 2, pz))), "glass")
    piece.add(scaled(box_bm((tw - 0.012, PANE, ph), (0, -td / 2 + PANE / 2, pz))), "glass")
    for sx in (-1, 1):
        piece.add(scaled(box_bm((PANE, td - 0.012, ph), (sx * (tw / 2 - PANE / 2), 0, pz))), "glass")
    # A dark blue-green background inside the back glass, as aquarists use.
    piece.add(scaled(box_bm((tw - 0.02, 0.004, ph), (0, -td / 2 + PANE + 0.003, pz))), "metalDark")
    # The lit water surface a little below the rim: the soft blue-green glow
    # under the tank light (emissive and see-through, no light node).
    water = top - 0.03
    inner_w, inner_d = tw / 2 - PANE, td / 2 - PANE
    piece.add(scaled(poly_bm([(-inner_w, -inner_d, water), (inner_w, -inner_d, water),
                              (inner_w, inner_d, water), (-inner_w, inner_d, water)], [(0, 1, 2, 3)])), "glow")
    # The light: a slim dark bar across the back of the top on two feet, with
    # a glowing strip along its front edge.
    bar_w = tw - 0.08
    bar_y = -td / 2 + 0.06
    piece.add(scaled(box_bm((bar_w, 0.04, 0.014), (0, bar_y, top + 0.026), 0.003)), "metalDark")
    piece.add(scaled(box_bm((bar_w - 0.04, 0.006, 0.006), (0, bar_y + 0.021, top + 0.024))), "glow")
    for sx in (-1, 1):
        piece.add(scaled(box_bm((0.01, 0.02, 0.022), (sx * (bar_w / 2 - 0.012), bar_y, top + 0.009))), "metalDark")
    return {"floor": y0 + BASE_THICK, "water": water, "inner_w": inner_w, "inner_d": inner_d}


def substrate(piece, width, inside):
    """A faceted sloping bed: low at the front glass, banked up at the back."""
    floor = inside["floor"]
    hw, hd = inside["inner_w"] - 0.002, inside["inner_d"] - 0.002
    nx = max(6, round(width / 0.09))
    ny = 4
    verts, faces = [], []
    for j in range(ny + 1):
        y = -hd + 2 * hd * j / ny
        back = 1.0 - j / ny  # 1 at the back (-Y), 0 at the front
        for i in range(nx + 1):
            x = -hw + 2 * hw * i / nx
            edge = i in (0, nx) or j in (0, ny)
            z = floor + BED_FRONT + BED_RISE * back + (0.0 if edge else wobble(i * 31 + j * 7, 0.008))
            verts.append((x, y, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    count = len(verts)
    # Skirts down to the tank floor so the bed reads solid through the glass.
    ring = [j * (nx + 1) for j in range(ny + 1)][::-1] + list(range(nx + 1)) \
        + [j * (nx + 1) + nx for j in range(ny + 1)] + [ny * (nx + 1) + i for i in range(nx + 1)][::-1]
    seen = []
    for index in ring:
        if not seen or seen[-1] != index:
            seen.append(index)
    for a, b in zip(seen, seen[1:] + seen[:1]):
        if a == b:
            continue
        x0, y0, _ = verts[a]
        x1, y1, _ = verts[b]
        verts += [(x0, y0, floor), (x1, y1, floor)]
        faces.append((b, a, count, count + 1))
        count += 2
    bm = poly_bm(verts, faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    piece.add(scaled(bm), "metalDark")


def rock(piece, center, size, seed, token="metalMedium"):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5)
    for k, vert in enumerate(bm.verts):
        jitter = 1.0 + wobble(seed * 13 + k, 0.18)
        vert.co = Vector((vert.co.x * size[0] * jitter, vert.co.y * size[1] * jitter,
                          max(vert.co.z, -0.2) * size[2] * jitter))
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    piece.add(scaled(bm), token)


def cone(center, radius, height, turn, lean=(0.0, 0.0)):
    """A four-sided pointed cone, plantSmall's leaf tier: a square base turned
    `turn` radians, its tip shifted by `lean` (dx, dy). Open underneath."""
    verts = [(center[0] + radius * math.cos(turn + k * math.pi / 2),
              center[1] + radius * math.sin(turn + k * math.pi / 2), center[2]) for k in range(4)]
    verts.append((center[0] + lean[0], center[1] + lean[1], center[2] + height))
    return poly_bm(verts, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)])


def stem_plant(piece, base, height, tiers, width, seed):
    """A stem plant as stacked leaf tiers, like plantSmall's tiered leaves:
    each tier a turned four-sided cone, narrowing to the top."""
    for t in range(tiers):
        f = t / max(1, tiers - 1)
        z = base[2] + height * (0.12 + 0.72 * t / tiers)
        radius = width * (1.0 - 0.45 * f)
        turn = 0.6 * t + wobble(seed + t, 0.3)
        sway = (wobble(seed * 5 + t, 0.006), wobble(seed * 7 + t, 0.004))
        piece.add(scaled(cone((base[0] + sway[0], base[1] + sway[1], z), radius,
                              height * 0.34, turn, sway)), "plant")
    # The stem itself: a thin three-sided post up the middle (open ends).
    r = 0.004
    ring = [(base[0] + r * math.cos(k * math.tau / 3), base[1] + r * math.sin(k * math.tau / 3)) for k in range(3)]
    verts = [(x, y, base[2]) for x, y in ring] + [(x, y, base[2] + height * 0.8) for x, y in ring]
    piece.add(scaled(poly_bm(verts, [(k, (k + 1) % 3, 3 + (k + 1) % 3, 3 + k) for k in range(3)])), "plant")


def sword_plant(piece, base, height, leaves, seed):
    """A rosette of long pointed leaves fanning out from one crown."""
    for k in range(leaves):
        angle = k / leaves * math.tau + wobble(seed + k, 0.3)
        h = height * (0.7 + 0.3 * ((k * 3) % leaves) / max(1, leaves - 1))
        out = h * 0.45
        lean = (math.cos(angle) * out, math.sin(angle) * out * 0.7)
        piece.add(scaled(cone((base[0] + math.cos(angle) * 0.01, base[1] + math.sin(angle) * 0.008, base[2]),
                              0.013, h, angle + math.pi / 4, lean)), "plant")


def carpet_tuft(piece, base, spread, count, seed):
    """Low foreground carpet: small squat cones in a loose patch."""
    for k in range(count):
        angle = k * 2.4 + seed
        r = spread * math.sqrt((k + 0.5) / count)
        at = (base[0] + math.cos(angle) * r, base[1] + math.sin(angle) * r * 0.6, base[2] - 0.003)
        piece.add(scaled(cone(at, 0.018 + wobble(seed + k, 0.004), 0.028 + wobble(seed * 2 + k, 0.008),
                              angle)), "plant")


def bed_height(inside, y):
    """Bed surface height at depth y (matches substrate's slope, unjittered)."""
    hd = inside["inner_d"] - 0.002
    back = 1.0 - (y + hd) / (2 * hd)
    return inside["floor"] + BED_FRONT + BED_RISE * back


def build_tank(asset_id, cells):
    width = cells * 0.5 - 0.04
    piece = Piece(asset_id)
    stand(piece, width, cells)
    inside = tank(piece, width)
    substrate(piece, width, inside)
    hw = inside["inner_w"]
    # Layout in thirds, as aquascapers plant: a tall stem group back left, a
    # pale stone left of centre with a companion, a sword plant and stems back
    # right, carpet tufts along the front.
    d = inside["inner_d"]
    back = -d * 0.6

    def ground(x, y):
        return (x, y, bed_height(inside, y) - 0.004)

    rock(piece, ground(-hw * 0.22, -0.01), (0.13, 0.095, 0.10), 1, "metal")
    rock(piece, ground(-hw * 0.02, 0.06), (0.06, 0.05, 0.045), 2, "metal")
    # Tall stems in the back left corner, stepping down toward the middle.
    for k, (fx, fy, h) in enumerate(((-0.9, -0.75, 0.19), (-0.8, -0.45, 0.2), (-0.68, -0.8, 0.18),
                                     (-0.86, -0.1, 0.14), (-0.56, -0.5, 0.16), (-0.44, -0.82, 0.14),
                                     (-0.68, -0.2, 0.12))):
        stem_plant(piece, ground(hw * fx, d * fy), h, 4, 0.032, 10 + k * 7)
    # A low group behind the stone.
    for k, (fx, fy, h) in enumerate(((-0.2, -0.8, 0.1), (-0.06, -0.72, 0.085))):
        stem_plant(piece, ground(hw * fx, d * fy), h, 3, 0.028, 30 + k * 7)
    # A sword plant and stems back right.
    sword_plant(piece, ground(hw * 0.5, back), 0.15, 7, 3)
    for k, (fx, fy, h) in enumerate(((0.86, -0.72, 0.18), (0.76, -0.3, 0.13), (0.88, 0.05, 0.1))):
        stem_plant(piece, ground(hw * fx, d * fy), h, 4, 0.03, 40 + k * 7)
    # Carpet along the front glass.
    carpet_tuft(piece, ground(hw * 0.3, d * 0.5), 0.06, 7, 1)
    carpet_tuft(piece, ground(-hw * 0.55, d * 0.5), 0.05, 6, 2)
    carpet_tuft(piece, ground(hw * 0.72, d * 0.45), 0.04, 4, 4)
    if cells >= 3:
        for k, (fx, fy, h) in enumerate(((0.14, -0.78, 0.19), (0.24, -0.42, 0.15), (0.04, -0.6, 0.12))):
            stem_plant(piece, ground(hw * fx, d * fy), h, 4, 0.03, 60 + k * 7)
        rock(piece, ground(hw * 0.4, 0.04), (0.08, 0.06, 0.055), 3, "metal")
        carpet_tuft(piece, ground(-hw * 0.05, d * 0.55), 0.05, 5, 3)
    obj = piece.finish()
    # Swim box and inner glass box in the model's own glTF frame (Y-up, front
    # -Z, source units before ArtScale): clear of the glass, above the bed's
    # highest point and below the water. The wrapper maps them through its Art
    # transform, so they follow the shared scale and centring exactly.
    swim = gltf_box((-hw + 0.012, -inside["inner_d"] + 0.012, inside["floor"] + 0.075),
                    (hw - 0.012, inside["inner_d"] - 0.012, inside["water"] - 0.02))
    glass = gltf_box((-hw, -inside["inner_d"], inside["floor"]), (hw, inside["inner_d"], inside["water"]))
    return obj, {"swim_box_model": swim, "glass_inner_model": glass}


def gltf_box(low, high):
    """A Blender Z-up world-metre box as a glTF (x, z, -y) box in source units."""
    a = (low[0] / SCALE, low[2] / SCALE, -high[1] / SCALE)
    b = (high[0] / SCALE, high[2] / SCALE, -low[1] / SCALE)
    return {"position": [round(v, 5) for v in a], "size": [round(b[k] - a[k], 5) for k in range(3)]}


# ---------------------------------------------------------------- the fish

FISH = {
    # name: (body, tail, fins, pattern)
    "fish_neon": ("blue", "red", "white", "neon"),
    "fish_orange": ("orange", "amber", "amber", "plain"),
    "fish_yellow": ("yellow", "amber", "amber", "plain"),
    "fish_guppy": ("purple", "pink", "pink", "guppy"),
}
FISH_LENGTH = 0.06   # body only; the tail adds a little more
FISH_WIDTH = 0.03
FISH_HEIGHT = 0.04
# The whole fish a little larger than life, so it still reads as a fish at
# play zoom.
FISH_SCALE = 1.15


def build_fish(asset_id):
    body_c, tail_c, fin_c, pattern = FISH[asset_id]
    piece = Piece(asset_id)
    L, W, H = FISH_LENGTH, FISH_WIDTH, FISH_HEIGHT

    def body_colour(face):
        c = face.calc_center_median()
        if pattern == "neon":
            if c.z < -H * 0.1:
                return "red" if c.y < 0 else "white"
            return "blue"
        if pattern == "guppy" and c.y < -L * 0.2:
            return tail_c
        if c.z < -H * 0.3:
            return "white" if pattern != "plain" else body_c
        return body_c

    # Body: a faceted lens, six-sided in section (point up and down, flat
    # sides), widest a little ahead of the middle, pinched at the nose and
    # at the tail root. Open-ended rings are closed with small caps.
    stations = ((L / 2, 0.28), (L / 4, 0.86), (0.0, 1.0), (-L / 4, 0.62), (-L / 2, 0.26))
    angles = [math.radians(a) for a in (90, 30, -30, -90, -150, 150)]
    verts, faces = [], []
    for y, size in stations:
        for a in angles:
            verts.append((math.cos(a) * W / 2 * size, y, math.sin(a) * H / 2 * size - (H * 0.04 if y > L / 3 else 0)))
    for k in range(len(stations) - 1):
        for i in range(6):
            j = (i + 1) % 6
            faces.append((k * 6 + i, k * 6 + j, (k + 1) * 6 + j, (k + 1) * 6 + i))
    faces.append(tuple(range(6)))
    faces.append(tuple(range(len(verts) - 1, len(verts) - 7, -1)))
    body = poly_bm(verts, faces)
    bmesh.ops.recalc_face_normals(body, faces=body.faces)
    piece.add(scaled(body), "colormap", body_colour)
    # Tail: a thin forked fan behind the body (a guppy's is a big fan).
    t0 = -L / 2 + 0.003
    fan = 1.45 if pattern == "guppy" else 1.0
    tail = poly_bm([(0, t0, 0.0), (0, t0 - 0.03 * fan, H * 0.6 * fan), (0, t0 - 0.02 * fan, 0.0),
                    (0, t0 - 0.03 * fan, -H * 0.6 * fan)], [(0, 1, 2), (0, 2, 3)])
    bmesh.ops.solidify(tail, geom=list(tail.faces), thickness=0.004)
    piece.add(scaled(tail), "colormap", lambda face: tail_c)
    # Dorsal fin.
    fin = poly_bm([(0, L * 0.12, H / 2 - 0.003), (0, -L * 0.2, H / 2 + 0.012), (0, -L * 0.24, H / 2 - 0.008)],
                  [(0, 1, 2)])
    bmesh.ops.solidify(fin, geom=list(fin.faces), thickness=0.003)
    piece.add(scaled(fin), "colormap", lambda face: fin_c)
    # Eyes: small dark squares just proud of each side, near the nose.
    for sx in (-1, 1):
        # On the flat side face, just proud of it, between the nose rings.
        cy, cz = L * 0.3, H * 0.06
        ring = 0.86 + (0.28 - 0.86) * (cy - L / 4) / (L / 4)
        x = sx * (math.cos(math.radians(30)) * W / 2 * ring + 0.0008)
        e = 0.005
        quad = [(x, cy - e, cz - e), (x, cy + e, cz - e), (x, cy + e, cz + e), (x, cy - e, cz + e)]
        if sx < 0:
            quad = quad[::-1]
        piece.add(scaled(poly_bm(quad, [(0, 1, 2, 3)])), "colormap", lambda face: "dark")
    bmesh.ops.scale(piece.bm, vec=Vector((FISH_SCALE,) * 3), verts=piece.bm.verts)
    # Origin at the centre of the whole fish (tail and fin included), so it
    # turns about its middle and its half sizes bound it from the origin.
    low = Vector(tuple(min(v.co[k] for v in piece.bm.verts) for k in range(3)))
    high = Vector(tuple(max(v.co[k] for v in piece.bm.verts) for k in range(3)))
    bmesh.ops.translate(piece.bm, vec=-(low + high) / 2, verts=piece.bm.verts)
    obj = piece.finish()
    return obj


# ---------------------------------------------------------------- export

def link_food_colormap(path: Path) -> None:
    """Point the fish material at the Food Kit's own colormap by relative path,
    exactly as the kit's models do, instead of embedding a copy."""
    data = path.read_bytes()
    offset = 12
    json_size, _kind = struct.unpack_from("<II", data, offset)
    document = json.loads(data[offset + 8:offset + 8 + json_size])
    rest = data[offset + 8 + json_size:]
    document["images"] = [{"uri": "../../kenney/food/Textures/colormap.png", "name": "colormap"}]
    document["samplers"] = [{"magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497}]
    document["textures"] = [{"sampler": 0, "source": 0, "name": "colormap"}]
    for material in document["materials"]:
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
        material["pbrMetallicRoughness"].pop("baseColorFactor", None)
        material["doubleSided"] = True
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


def export(obj, path, colormap=False):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False, export_cameras=False, export_lights=False,
                              export_extras=False, export_image_format="NONE" if colormap else "AUTO")
    if colormap:
        link_food_colormap(path)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"issue": 125, "uniform_scale": SCALE, "assets": {}}
    for asset_id, cells in (("aquarium_2", 2), ("aquarium_3", 3)):
        clear_scene()
        obj, extra = build_tank(asset_id, cells)
        path = OUTPUT / (asset_id + ".glb")
        export(obj, path)
        measured = glb_metrics(path)
        doc, _ = read_glb(path)
        assert measured["triangles"] < 1500, measured
        assert not doc.get("images"), "tanks use material colours only"
        report["assets"][asset_id] = {"triangles": measured["triangles"],
                                      "dimensions": [round(v, 4) for v in measured["dimensions"]],
                                      "world_dimensions": [round(v * SCALE, 4) for v in measured["dimensions"]],
                                      "materials": [m["name"] for m in doc["materials"]], **extra}
    for asset_id in FISH:
        clear_scene()
        obj = build_fish(asset_id)
        path = OUTPUT / (asset_id + ".glb")
        export(obj, path, colormap=True)
        measured = glb_metrics(path)
        assert measured["triangles"] < 100, measured
        report["assets"][asset_id] = {"triangles": measured["triangles"],
                                      "dimensions": [round(v, 4) for v in measured["dimensions"]],
                                      "world_dimensions": [round(v * SCALE, 4) for v in measured["dimensions"]],
                                      # AquariumSwim.HALF_LENGTH / HALF_HEIGHT bound these.
                                      "world_half_length": round(measured["dimensions"][2] * SCALE / 2, 4),
                                      "world_half_height": round(measured["dimensions"][1] * SCALE / 2, 4)}
    (OUTPUT / "aquarium.metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


main()
