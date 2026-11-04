"""Rebuild the restaurant cat (#119) with installed Blender.

blender --background --factory-startup --python tools/build_cat.py
It also writes the measured numbers to assets/made/cat/cat.metrics.json
(`-- --metrics <path>` redirects them).

A light grey-orange tabby in the Kenney Mini Characters style: chunky, slightly
bevelled boxes, flat shading, and colour only from the characters kit's own
`colormap.png` (every face's UVs point at one palette swatch, exactly like the
people). One rigid-skinned mesh on a ten-bone rig with three looping clips:
`idle`, `walk` and `nap` (a curled-up loaf). Metres, Blender Z-up with the cat
facing +Y; the glTF export is Y-up facing -Z with the origin at the feet.
No lights, no extra textures, no downloads.
"""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
COLORMAP = ROOT / "assets/kenney/characters/Textures/colormap.png"
OUTPUT = ROOT / "assets/made/cat/cat.glb"
SIZE = 512

# Palette pixels (x, y) of the kit colormap, picked as the nearest swatch to
# the tabby colours named in the comments.
SWATCH = {
    "fur": (484, 390),      # light grey-orange coat, (241,189,151)
    "stripe": (416, 420),   # darker warm grey-brown stripes, (162,92,65)
    "cream": (34, 263),     # chest, muzzle, paws, (253,228,199)
    "nose": (352, 390),     # salmon nose and inner ears, (239,149,106)
    "eye": (28, 420),       # near-black eyes, (56,56,61)
    "iris": (97, 257),      # leaf green iris, (94,200,137)
}

FPS = 24


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablock in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions, bpy.data.images):
        for item in list(datablock):
            datablock.remove(item)


def colormap_material():
    image = bpy.data.images.load(str(COLORMAP))
    image.name = "colormap"
    material = bpy.data.materials.new("colormap")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def uv_of(name: str) -> tuple:
    x, y = SWATCH[name]
    return ((x + 0.5) / SIZE, 1.0 - (y + 0.5) / SIZE)


def part(name, bone, size, center, colour, bevel=0.012, rotate=(0.0, 0.0, 0.0), taper=None):
    """One bevelled box. `rotate` is Euler XYZ in degrees about its own centre.
    `taper` = (top scale x, top scale y) pinches the +Z face like a cone/prism."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        vert.co = Vector((vert.co.x * size[0], vert.co.y * size[1], vert.co.z * size[2]))
        if taper is not None and vert.co.z > 0:
            vert.co.x *= taper[0]
            vert.co.y *= taper[1]
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    rotation = Euler([math.radians(a) for a in rotate], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ rotation, verts=bm.verts)
    uv_layer = bm.loops.layers.uv.new("UVMap")
    target = uv_of(colour)
    for face in bm.faces:
        face.smooth = False
        for loop in face.loops:
            loop[uv_layer].uv = target
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    return obj


def pyramid(name, bone, base, height, center, colour, rotate=(0.0, 0.0, 0.0)):
    """A four-sided ear: square base on -Z, apex up, slightly blunted."""
    return part(name, bone, (base, base * 0.55, height), center, colour, bevel=0.0,
                rotate=rotate, taper=(0.18, 0.25))


def limb(name, bone, start, lean, t0, t1, width, colour, bevel=0.0):
    """A box along a straight line from `start` (y, z), leaning back from
    vertical by `lean` degrees, covering distance t0..t1 along it."""
    a = math.radians(lean)
    direction = Vector((0.0, -math.sin(a), math.cos(a)))
    middle = Vector(start) + direction * ((t0 + t1) / 2)
    return part(name, bone, (width, width, t1 - t0), middle, colour, bevel, rotate=(lean, 0.0, 0.0))


TAIL_A = Vector((0.0, -0.105, 0.125))
TAIL_B = Vector((0.0, -0.168, 0.182))


def build_mesh(material):
    parts = []
    add = parts.append
    # ---- body (the `body` bone: hips at z 0.115) ---------------------------
    add(part("Body", "body", (0.140, 0.215, 0.116), (0, 0.0, 0.115), "fur", 0.030))
    add(part("Chest", "body", (0.090, 0.030, 0.080), (0, 0.108, 0.098), "cream", 0.0))
    for index, y in enumerate((-0.060, -0.010, 0.040)):
        add(part("Stripe%d" % index, "body", (0.144, 0.020, 0.120), (0, y, 0.116), "stripe", 0.0))
    # ---- head (`head` bone, neck joint at y 0.09 z 0.17) --------------------
    add(part("Head", "head", (0.170, 0.130, 0.130), (0, 0.145, 0.205), "fur", 0.030))
    add(part("Muzzle", "head", (0.086, 0.030, 0.052), (0, 0.2085, 0.172), "cream", 0.0))
    add(part("Nose", "head", (0.028, 0.014, 0.018), (0, 0.2285, 0.190), "nose", 0.0))
    for side in (-1, 1):
        add(part("Eye%d" % side, "head", (0.032, 0.012, 0.040), (side * 0.046, 0.2075, 0.222), "eye", 0.0))
        add(part("Iris%d" % side, "head", (0.022, 0.008, 0.026), (side * 0.046, 0.2125, 0.2235), "iris", 0.0))
        add(pyramid("Ear%d" % side, "head", 0.072, 0.074, (side * 0.056, 0.140, 0.300), "fur",
                    rotate=(-6.0, side * 10.0, side * -8.0)))
        add(pyramid("EarIn%d" % side, "head", 0.038, 0.044, (side * 0.056, 0.162, 0.292), "nose",
                    rotate=(-6.0, side * 10.0, side * -8.0)))
    for index, x in enumerate((-0.034, 0.0, 0.034)):
        add(part("Brow%d" % index, "head", (0.016, 0.014, 0.046), (x, 0.2105, 0.2625 + 0.0), "stripe", 0.0))
    # ---- legs (own bones, joints at the hip/shoulder z 0.10) ----------------
    for name, bone, x, y in (("FrontLeft", "leg_fl", 0.042, 0.075), ("FrontRight", "leg_fr", -0.042, 0.075),
                             ("BackLeft", "leg_bl", 0.042, -0.075), ("BackRight", "leg_br", -0.042, -0.075)):
        add(part(name, bone, (0.048, 0.050, 0.092), (x, y, 0.054), "fur", 0.012))
        add(part(name + "Paw", bone, (0.050, 0.058, 0.030), (x, y + 0.004, 0.015), "cream", 0.0))
    # ---- tail: two segments curving up from the rump ------------------------
    add(limb("TailA", "tail_a", TAIL_A, 48.0, 0.0, 0.085, 0.040, "fur", 0.010))
    add(limb("TailRingA", "tail_a", TAIL_A, 48.0, 0.040, 0.058, 0.043, "stripe"))
    add(limb("TailB", "tail_b", TAIL_B, 14.0, 0.0, 0.085, 0.040, "fur", 0.010))
    add(limb("TailRingB", "tail_b", TAIL_B, 14.0, 0.030, 0.048, 0.043, "stripe"))
    add(limb("TailTip", "tail_b", TAIL_B, 14.0, 0.085, 0.120, 0.040, "stripe", 0.008))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mesh_obj = bpy.context.object
    mesh_obj.name = "cat-mesh"
    mesh_obj.data.name = "cat-mesh"
    mesh_obj.data.materials.append(material)
    return mesh_obj


# Bone joints (head positions), Blender coordinates. All bones stand vertical
# with roll 0 so their local axes line up with the world axes:
#   local X = world X (pitch), local Y = world Z (yaw), local Z = -world Y (roll)
BONES = (
    ("root", None, (0.0, 0.0, 0.0)),
    ("body", "root", (0.0, 0.0, 0.118)),
    ("head", "body", (0.0, 0.090, 0.170)),
    ("tail_a", "body", (0.0, -0.105, 0.125)),
    ("tail_b", "tail_a", (0.0, -0.168, 0.182)),
    ("leg_fl", "body", (0.042, 0.075, 0.100)),
    ("leg_fr", "body", (-0.042, 0.075, 0.100)),
    ("leg_bl", "body", (0.042, -0.075, 0.100)),
    ("leg_br", "body", (-0.042, -0.075, 0.100)),
)


def build_armature():
    data = bpy.data.armatures.new("cat-rig")
    rig = bpy.data.objects.new("cat-rig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, parent, head in BONES:
        bone = data.edit_bones.new(name)
        bone.head = Vector(head)
        bone.tail = Vector((head[0], head[1], head[2] + 0.04))
        bone.roll = 0.0
        if parent is not None:
            bone.parent = made[parent]
        made[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def skin(mesh_obj, rig):
    mesh_obj.parent = rig
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig


def pose(rig, bone, rot=(0.0, 0.0, 0.0), loc=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    """rot in degrees about WORLD x (pitch), z (yaw), y (roll); loc in world axes."""
    pb = rig.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    # local Y is world Z; local Z is world -Y
    pb.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(-rot[2]))
    pb.location = (loc[0], loc[2], -loc[1])
    pb.scale = (scale[0], scale[2], scale[1])


def key(rig, frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("scale", frame=frame)


def reset(rig):
    for name, _p, _h in BONES:
        pose(rig, name)


def make_action(rig, name, length, writer):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    reset(rig)
    frames = [0, length // 4, length // 2, 3 * length // 4, length]
    for frame in frames:
        reset(rig)
        writer(rig, frame / length)
        key(rig, frame)
    for fcurve in action.fcurves:
        for point in fcurve.keyframe_points:
            point.interpolation = "BEZIER"
    return action


def idle(rig, t):
    """A slow breath, a tail sway and a small ear-twitch of the head, looping."""
    s = math.sin(t * math.tau)
    c = math.cos(t * math.tau)
    pose(rig, "body", scale=(1.0, 1.0, 1.0 + 0.022 * s), rot=(0.0, 0.0, 0.0))
    pose(rig, "head", rot=(-2.0 * s, 6.0 * c, 0.0), loc=(0, 0, 0.002 * s))
    pose(rig, "tail_a", rot=(0.0, 12.0 * s, 0.0))
    pose(rig, "tail_b", rot=(0.0, 20.0 * math.sin(t * math.tau - 0.9), 0.0))
    for leg in ("leg_fl", "leg_fr", "leg_bl", "leg_br"):
        pose(rig, leg)


def walk(rig, t):
    """A trotting walk: diagonal legs swing together, the body bobs twice a cycle."""
    swing = math.sin(t * math.tau)
    swing2 = math.sin(t * math.tau + math.pi)
    lift = lambda v: max(0.0, math.cos(v))
    pose(rig, "body", rot=(2.0 * math.sin(t * 2 * math.tau), 0.0, 3.0 * swing), loc=(0, 0, 0.006 * abs(math.sin(t * math.tau)) - 0.003))
    pose(rig, "head", rot=(-3.0 * math.sin(t * 2 * math.tau + 0.4), -3.0 * swing, 0.0))
    pose(rig, "tail_a", rot=(-8.0, 9.0 * swing, 0.0))
    pose(rig, "tail_b", rot=(-6.0, 14.0 * math.sin(t * math.tau - 0.8), 0.0))
    amp = 34.0
    pose(rig, "leg_fl", rot=(amp * swing, 0, 0), loc=(0, 0, 0.012 * lift(t * math.tau + math.pi / 2)))
    pose(rig, "leg_br", rot=(amp * swing, 0, 0), loc=(0, 0, 0.012 * lift(t * math.tau + math.pi / 2)))
    pose(rig, "leg_fr", rot=(amp * swing2, 0, 0), loc=(0, 0, 0.012 * lift(t * math.tau - math.pi / 2)))
    pose(rig, "leg_bl", rot=(amp * swing2, 0, 0), loc=(0, 0, 0.012 * lift(t * math.tau - math.pi / 2)))


def nap(rig, t):
    """Curled up: body sunk to the floor, paws tucked, head down, tail wrapped round."""
    s = math.sin(t * math.tau)
    pose(rig, "body", loc=(0, 0, -0.060), scale=(1.10, 1.0, 0.94 + 0.020 * s))
    pose(rig, "head", rot=(-22.0, 34.0, 0.0), loc=(0.018, 0.012, -0.034 + 0.002 * s))
    pose(rig, "tail_a", rot=(28.0, 78.0, 0.0), loc=(0.0, 0.0, -0.040))
    pose(rig, "tail_b", rot=(8.0, 58.0, 0.0))
    for leg in ("leg_fl", "leg_fr", "leg_bl", "leg_br"):
        pose(rig, leg, scale=(1.0, 1.0, 0.18))


def build_animations(rig):
    for name, length, writer in (("idle", 48, idle), ("walk", 24, walk), ("nap", 72, nap)):
        make_action(rig, name, length, writer)
    reset(rig)
    rig.animation_data.action = None
    # Rest pose is the standing pose; scene fps matches the clip lengths.
    bpy.context.scene.render.fps = FPS


def link_kit_colormap(path: Path) -> None:
    """Point the material at the characters kit's own colormap file by relative
    path, exactly as the kit's models do, instead of embedding a copy."""
    data = path.read_bytes()
    _magic, _version, _length = struct.unpack_from("<4sII", data)
    offset = 12
    json_size, _kind = struct.unpack_from("<II", data, offset)
    document = json.loads(data[offset + 8:offset + 8 + json_size])
    rest = data[offset + 8 + json_size:]
    relative = Path("../../kenney/characters/Textures/colormap.png")
    document["images"] = [{"uri": relative.as_posix(), "name": "colormap"}]
    document["samplers"] = [{"magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497}]
    document["textures"] = [{"sampler": 0, "source": 0, "name": "colormap"}]
    for material in document["materials"]:
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
        material["pbrMetallicRoughness"].pop("baseColorFactor", None)
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def triangles(mesh_obj) -> int:
    mesh = mesh_obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def bounds(mesh_obj):
    corners = [mesh_obj.matrix_world @ Vector(c) for c in mesh_obj.bound_box]
    low = [min(c[i] for c in corners) for i in range(3)]
    high = [max(c[i] for c in corners) for i in range(3)]
    # Blender (x, y, z) -> glTF (x, z, -y)
    return ([low[0], low[2], -high[1]], [high[0], high[2], -low[1]])


def main() -> None:
    clear_scene()
    material = colormap_material()
    mesh_obj = build_mesh(material)
    rig = build_armature()
    skin(mesh_obj, rig)
    build_animations(rig)
    tris = triangles(mesh_obj)
    low, high = bounds(mesh_obj)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT), export_format="GLB", export_yup=True, export_animations=True,
        export_animation_mode="ACTIONS", export_skins=True, export_cameras=False, export_lights=False,
        export_apply=False, export_image_format="NONE", export_force_sampling=True)
    link_kit_colormap(OUTPUT)
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    metrics = {
        "asset": "cat", "format": "glTF 2 GLB", "metres_per_unit": 1, "up": "+Y", "front": "-Z",
        "origin": "feet centre", "budget_exclusive": 800, "triangles": tris,
        "aabb_min": [round(v, 4) for v in low], "aabb_max": [round(v, 4) for v in high],
        "dimensions": [round(h - l, 4) for l, h in zip(low, high)],
        "animations": {"idle": 48 / FPS, "walk": 24 / FPS, "nap": 72 / FPS},
        "texture": "assets/kenney/characters/Textures/colormap.png (referenced by path, unmodified)",
        "sha256": digest,
    }
    print("CAT", json.dumps(metrics))
    target = ROOT / "assets/made/cat/cat.metrics.json"
    if "--metrics" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--metrics") + 1])
    target.write_text(json.dumps(metrics, indent=2) + "\n")


main()
