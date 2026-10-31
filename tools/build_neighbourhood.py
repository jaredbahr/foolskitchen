"""Build the eight issue-242 neighbourhood models from approved kit colours.

blender --background --factory-startup --python tools/build_neighbourhood.py -- \
  --manifest /absolute/outside-project/neighbourhood-assets.json

Coordinates below are desired rendered metres, Y-up/front -Z. Geometry is
converted to Blender Z-up and divided by the existing central furniture scale;
the made-model view applies that scale exactly once, without a Kenney PI turn.
No rendering, downloads, textures, animation, collisions or lights are created.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/made/neighbourhood"
MATERIAL_SOURCES = {
    "metalDark": ("wall.glb", "metalDark"),
    "carpetWhite": ("bathroomCabinetDrawer.glb", "carpetWhite"),
    "metal": ("lampRoundFloor.glb", "metal"),
    "wood": ("wall.glb", "wood"),
    "woodDark": ("bathroomCabinet.glb", "woodDark"),
    "glass": ("wallWindow.glb", "glass"),
    "carpetBlue": ("chairModernCushion.glb", "carpetBlue"),
    "lamp": ("lampRoundFloor.glb", "lamp"),
}
SOURCE_HASHES = {'wall.glb': '69273d5d623bddfce41d12d4e5eeb5621ea04f1edcbd8f35c00a60c2fd3258b7', 'bathroomCabinetDrawer.glb': 'f32d09c6dab20fe823d238310f75ce81f24e893a91c2078b12efd3f7fe6c6b10', 'lampRoundFloor.glb': '50fe1b5b588edf15bfa9cc880f71a02a4fda6036350b24733d0ef4de5cc5e908', 'bathroomCabinet.glb': '9db540227acaaedbbadc6a085f4a00460b73944e608afaad4770e53238a3b7f8', 'wallWindow.glb': '166a10fddb8a78d942bc2791186913f7015dfee8501d20efd7a7b8f196fc5c3e', 'chairModernCushion.glb': '245132697e633e907e2b48c86d56f6c8543604a3440a055d1c71c06ce11d2858'}
TARGETS = {
    "road_segment": ((1.10, .025, 2.40), 48, 2),
    "crossing_segment": ((1.10, .025, 2.40), 120, 2),
    "kerb_segment": ((1.10, .08, .10), 44, 1),
    "shopfront": ((2.20, 1.40, 1.70), 450, 4),
    "house_body": ((2.20, 1.40, 1.70), 450, 4),
    "gable_roof": ((2.32, .45, 1.82), 64, 1),
    "compact_car": ((.70, .66, 1.40), 600, 4),
    "street_lamp": ((.30, 1.65, .45), 280, 3),
}
SCALE = 1.0
MATERIALS: dict = {}
SOURCE_RECORDS: dict = {}


def read_glb(path: Path) -> tuple[dict, list]:
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from("<III", raw)
    if magic != 0x46546C67 or version != 2 or size != len(raw):
        raise ValueError(f"Invalid GLB: {path}")
    chunks = []
    offset = 12
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        chunks.append((kind, raw[offset + 8:offset + 8 + length]))
        offset += 8 + length
    return json.loads(chunks[0][1]), chunks


def load_materials() -> None:
    for name, (filename, source_name) in MATERIAL_SOURCES.items():
        path = ROOT / "assets/kenney/furniture" / filename
        if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_HASHES[filename]:
            raise ValueError(f"Approved kit source changed: {path}")
        doc, _ = read_glb(path)
        source = next(m for m in doc["materials"] if m["name"] == source_name)
        SOURCE_RECORDS[name] = {"path": str(path.relative_to(ROOT)),
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                "material": source}
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        material.use_backface_culling = not source.get("doubleSided", False)
        shader = material.node_tree.nodes.get("Principled BSDF")
        pbr = source["pbrMetallicRoughness"]
        shader.inputs["Base Color"].default_value = pbr["baseColorFactor"]
        shader.inputs["Metallic"].default_value = pbr.get("metallicFactor", 1.0)
        shader.inputs["Roughness"].default_value = pbr.get("roughnessFactor", 1.0)
        MATERIALS[name] = material


def coordinate(point: tuple) -> tuple:
    return (point[0] / SCALE, -point[2] / SCALE, point[1] / SCALE)


def finish(obj, material: str, bevel: float = 0.0) -> None:
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(MATERIALS[material])
    if bevel > 0.0:
        modifier = obj.modifiers.new("Single kit edge", "BEVEL")
        modifier.width = bevel / SCALE
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for face in obj.data.polygons:
        face.use_smooth = False


def box(name: str, size: tuple, center: tuple, material: str, bevel: float = 0.0) -> None:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=coordinate(center))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0] / SCALE, size[2] / SCALE, size[1] / SCALE)
    finish(obj, material, bevel)


def cylinder(name: str, radius: float, length: float, center: tuple,
             material: str, across_x: bool = False) -> None:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius / SCALE,
                                      depth=length / SCALE, location=coordinate(center))
    obj = bpy.context.object
    obj.name = name
    if across_x:
        obj.rotation_euler.y = math.pi / 2.0
    finish(obj, material)


def road(crossing: bool) -> None:
    box("Road", (1.10, .020, 2.40), (0, .010, 0), "metalDark")
    if crossing:
        for index, z in enumerate([-.95, -.57, -.19, .19, .57, .95]):
            box(f"Crossing{index}", (.80, .005, .22), (0, .0225, z), "carpetWhite")
    else:
        box("LaneMark", (.50, .005, .035), (0, .0225, 0), "carpetWhite")


def facade(house: bool) -> None:
    wall = "wood" if house else "carpetWhite"
    trim = "carpetWhite" if house else "wood"
    box("Walls", (2.20, 1.40, 1.68), (0, .70, 0), wall, .008)
    # Rear trim and front panels establish the complete symmetric 1.70 m depth.
    box("RearEave", (2.20, .020, .010), (0, 1.39, .845), trim)
    door_x = 0.0 if house else -.68
    box("DoorFrame", (.62, 1.16, .008), (door_x, .58, -.844), trim)
    box("Door", (.54, 1.11, .004), (door_x, .555, -.848), "metalDark")
    windows = [(-.72, .47), (.72, .47)] if house else [(.37, 1.14)]
    for index, (x, width) in enumerate(windows):
        height = .54 if house else .72
        box(f"WindowFrame{index}", (width + .08, height + .08, .008),
            (x, .83, -.844), trim)
        box(f"Pane{index}", (width, height, .004), (x, .83, -.848), "glass")
    if not house:
        box("Fascia", (1.90, .12, .010), (0, 1.32, -.845), trim)


def roof() -> None:
    vertices = [(-1.16, 0, -.91), (1.16, 0, -.91), (0, .45, -.91),
                (-1.16, 0, .91), (1.16, 0, .91), (0, .45, .91)]
    faces = [(0, 2, 1), (3, 4, 5), (0, 3, 5, 2), (2, 5, 4, 1), (0, 1, 4, 3)]
    mesh = bpy.data.meshes.new("Roof")
    mesh.from_pydata([coordinate(point) for point in vertices], [], faces)
    mesh.update()
    obj = bpy.data.objects.new("GableRoof", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(MATERIALS["woodDark"])


def car() -> None:
    box("Body", (.64, .24, 1.34), (0, .25, 0), "carpetBlue", .035)
    box("Cabin", (.54, .28, .70), (0, .50, .10), "carpetBlue", .025)
    box("Roof", (.56, .035, .76), (0, .6425, .10), "carpetWhite", .012)
    for side in [-1, 1]:
        for z in [-.42, .42]:
            cylinder("Wheel", .13, .12, (side * .29, .13, z), "metalDark", True)
        box("SideWindow", (.006, .17, .56), (side * .272, .51, .10), "glass")
        box("Bumper", (.54, .065, .06), (0, .20, side * .67), "carpetWhite")
        box("Headlamp", (.11, .045, .006), (side * .22, .29, -.697), "carpetWhite")
    box("FrontWindow", (.42, .17, .012), (0, .51, -.254), "glass")
    box("RearWindow", (.42, .17, .012), (0, .51, .454), "glass")


def lamp() -> None:
    box("Foot", (.18, .08, .20), (0, .04, .125), "metal", .008)
    cylinder("Post", .025, 1.47, (0, .735, .125), "metal")
    box("Arm", (.06, .06, .25), (0, 1.47, .025), "metalDark")
    box("HeadCap", (.30, .04, .30), (0, 1.63, -.075), "metalDark", .008)
    box("HeadBase", (.28, .04, .28), (0, 1.49, -.065), "metalDark", .006)
    box("UnlitPanel", (.22, .10, .24), (0, 1.565, -.075), "lamp")


def normalize_materials(path: Path) -> None:
    """Preserve source PBR/alpha records exactly, avoiding Blender conversion drift."""
    doc, chunks = read_glb(path)
    for material in doc.get("materials", []):
        name = material["name"]
        source = SOURCE_RECORDS[name]["material"]
        material.clear()
        material.update({key: value for key, value in source.items()
                         if key in {"name", "pbrMetallicRoughness", "alphaMode", "alphaCutoff", "doubleSided"}})
    for key in ["extensionsUsed", "extensionsRequired"]:
        if key in doc:
            doc[key] = [value for value in doc[key] if not value.startswith("KHR_materials_")]
            if not doc[key]:
                del doc[key]
    content = json.dumps(doc, separators=(",", ":")).encode()
    content += b" " * (-len(content) % 4)
    chunks[0] = (0x4E4F534A, content)
    body = b"".join(struct.pack("<II", len(data), kind) + data for kind, data in chunks)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def merge_surfaces() -> None:
    for name in MATERIALS:
        objects = [obj for obj in bpy.context.scene.objects
                   if obj.type == "MESH" and obj.data.materials[0].name == name]
        if not objects:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        merged = bpy.context.object
        merged.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="SELECT")


def audit(path: Path, target: tuple, max_triangles: int, max_materials: int) -> dict:
    doc, chunks = read_glb(path)
    binary = next(content for kind, content in chunks if kind == 0x004E4942)
    points = []
    triangles = 0
    transforms = []
    def walk(index: int, parent: Matrix) -> None:
        nonlocal triangles
        node = doc["nodes"][index]
        if "matrix" in node:
            values = node["matrix"]
            local = Matrix([values[row::4] for row in range(4)])
        else:
            q = node.get("rotation", [0, 0, 0, 1])
            local = Matrix.LocRotScale(Vector(node.get("translation", [0, 0, 0])),
                                       Quaternion((q[3], q[0], q[1], q[2])),
                                       Vector(node.get("scale", [1, 1, 1])))
        transform = parent @ local
        if "mesh" in node:
            transforms.append({"name": node.get("name"), "scale": list(transform.to_scale())})
            for primitive in doc["meshes"][node["mesh"]]["primitives"]:
                assert primitive.get("mode", 4) == 4
                accessor = doc["accessors"][primitive["attributes"]["POSITION"]]
                view = doc["bufferViews"][accessor["bufferView"]]
                offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
                for vertex in range(accessor["count"]):
                    point = Vector(struct.unpack_from("<fff", binary, offset + vertex * view.get("byteStride", 12)))
                    points.append(transform @ point)
                triangles += doc["accessors"][primitive["indices"]]["count"] // 3
        for child in node.get("children", []):
            walk(child, transform)
    for node in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        walk(node, Matrix.Identity(4))
    lower = [min(point[axis] for point in points) for axis in range(3)]
    upper = [max(point[axis] for point in points) for axis in range(3)]
    dimensions = [(upper[i] - lower[i]) * SCALE for i in range(3)]
    assert all(abs(dimensions[i] - target[i]) < .00002 for i in range(3)), (path.name, dimensions, target)
    assert abs(lower[1]) < .00002 and abs(lower[0] + upper[0]) < .00002 and abs(lower[2] + upper[2]) < .00002
    assert triangles <= max_triangles and len(doc["materials"]) <= max_materials
    assert all(all(abs(value - 1.0) < .00002 for value in item["scale"]) for item in transforms)
    assert not any(doc.get(key) for key in ["textures", "images", "animations", "cameras", "extensions"])
    for material in doc["materials"]:
        assert not material.get("emissiveFactor") and not material.get("extensions")
        assert material["pbrMetallicRoughness"] == SOURCE_RECORDS[material["name"]]["material"]["pbrMetallicRoughness"]
    return {"path": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "source_bounds_min": lower, "source_bounds_max": upper,
            "rendered_dimensions_m": dimensions, "triangles": triangles,
            "material_slots": len(doc["materials"]), "materials": doc["materials"],
            "mesh_transforms": transforms, "runtime_uniform_scale": SCALE,
            "no_textures_emission_lights_animations": True}


def main() -> None:
    global SCALE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    manifest = args.manifest.resolve()
    if manifest == ROOT or ROOT in manifest.parents:
        raise ValueError("Review audit manifest must remain outside the project")
    source = (ROOT / "src/world/art_scale.gd").read_text()
    SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([0-9.]+)", source)[1])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    load_materials()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    for name, (target, budget, slots) in TARGETS.items():
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        if name == "road_segment":
            road(False)
        elif name == "crossing_segment":
            road(True)
        elif name == "kerb_segment":
            box("Kerb", target, (0, .04, 0), "metal", .006)
        elif name == "shopfront":
            facade(False)
        elif name == "house_body":
            facade(True)
        elif name == "gable_roof":
            roof()
        elif name == "compact_car":
            car()
        elif name == "street_lamp":
            lamp()
        merge_surfaces()
        path = OUTPUT / (name + ".glb")
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True,
                                  use_selection=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
        normalize_materials(path)
        records.append(audit(path, target, budget, slots))
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({"issue": 242, "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                                   "scale_source": "ArtScale.FURNITURE_SCALE", "palette_sources": SOURCE_RECORDS,
                                   "composed_building_dimensions_m": [2.32, 1.85, 1.82], "assets": records}, indent=2) + "\n")
    print("NEIGHBOURHOOD_ASSETS_OK " + str(manifest))


if __name__ == "__main__":
    main()
