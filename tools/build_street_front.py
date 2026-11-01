"""Build the eight issue #240 street-front pieces with installed Blender.

blender --background --factory-startup --python tools/build_street_front.py
Optional external audit: append -- --manifest /absolute/outside/project/report.json
Metres, Blender Z-up/front +Y; GLB Y-up/front -Z. Target dimensions are
converted through the shared ArtScale; wrappers apply that uniform scale once.
Only unchanged Kenney material colours are copied. No textures or lights.
"""
from pathlib import Path
import argparse
import json
import math
import re
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb, glb_metrics

SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)",
                      (ROOT / "src/world/art_scale.gd").read_text()).group(1))
OUTPUT = ROOT / "assets/made/street_front"
MATERIAL_SOURCES = {
    "carpet": "benchCushion.glb", "carpetWhite": "bathroomCabinetDrawer.glb",
    "metalDark": "wall.glb", "wood": "pottedPlant.glb",
    "woodDark": "pottedPlant.glb", "plant": "pottedPlant.glb", "lamp": "lampWall.glb",
}


def material(name):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    doc, _ = read_glb(ROOT / "assets/kenney/furniture" / MATERIAL_SOURCES[name])
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


def mesh(name, vertices, faces, paint):
    data = bpy.data.meshes.new(name)
    data.from_pydata([tuple(v / SCALE for v in p) for p in vertices], [], faces)
    data.materials.append(material(paint))
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def box(name, dimensions, center, paint, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=tuple(v / SCALE for v in center))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = tuple(v / SCALE for v in dimensions)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material(paint))
    if bevel:
        modifier = obj.modifiers.new("Kit edge softness", "BEVEL")
        modifier.width = bevel / SCALE
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def segment(name, a, b, radius, paint, sides=4):
    start, end = Vector(a), Vector(b)
    axis = (end - start).normalized()
    normal = axis.cross(Vector((0, 0, 1))).normalized()
    if normal.length < .1:
        normal = Vector((1, 0, 0))
    other = axis.cross(normal).normalized()
    vertices = [tuple(p + radius * (math.cos(i * math.tau / sides) * normal +
                                    math.sin(i * math.tau / sides) * other))
                for p in (start, end) for i in range(sides)]
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, sides * 2))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides)
              for i in range(sides)]
    return mesh(name, vertices, faces, paint)


def awning(width):
    stripes = width * 2 + 5
    span = width * .5 - .05
    for index in range(stripes):
        x0 = -span / 2 + span * index / stripes
        x1 = -span / 2 + span * (index + 1) / stripes
        # Authored shallow profile: under .15 m total height leaves a full 1.10 m
        # door clearance while staying below the separate 1.27 m sign band.
        vertices = [(x, y, z) for x in (x0, x1)
                    for y, z in ((-.215, .1349), (.215, .045), (.215, .06), (-.215, .1499))]
        mesh(f"CanopyStripe{index}", vertices,
             [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
              (2, 3, 7, 6), (3, 0, 4, 7)], "carpet" if index % 2 == 0 else "carpetWhite")
        box(f"Valance{index}", (x1 - x0, .018, .045), ((x0 + x1) / 2, .206, .0225),
            "carpet" if index % 2 == 0 else "carpetWhite")
    box("RearRail", (span - .035, .025, .025), (0, -.20, .12), "metalDark", .003)
    for x in (-span / 2 + .05, span / 2 - .05):
        segment("SupportBracket", (x, -.195, .03), (x, .17, .055), .011, "metalDark")
        box("WallBracket", (.025, .025, .11), (x, -.20, .075), "metalDark")


def flower_box():
    box("Planter", (.44, .20, .11), (0, 0, .055), "wood", .008)
    box("Soil", (.40, .16, .015), (0, 0, .111), "woodDark")
    for y in (-.092, .092):
        box("Rim", (.44, .016, .022), (0, y, .112), "woodDark")
    for x in (-.212, .212):
        box("RimEnd", (.016, .168, .022), (x, 0, .112), "woodDark")
    for index, x in enumerate((-.145, 0, .145)):
        segment("Stem", (x, 0, .115), (x, 0, .19), .006, "plant")
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=.035 / SCALE,
                                            location=(x / SCALE, 0, .185 / SCALE))
        bpy.context.object.name = "Flower"
        bpy.context.object.data.materials.append(material(("carpetWhite", "carpet", "lamp")[index]))
        mesh("Leaves", [(x - .055, 0, .14), (x, -.025, .12), (x + .055, 0, .14),
                        (x, .025, .12), (x, 0, .16)],
             [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)], "plant")


def sign():
    box("SignFrame", (.94, .055, .12), (0, 0, .06), "woodDark", .005)
    box("BlankNameFace", (.885, .003, .085), (0, .027, .06), "carpetWhite")


def lights(width):
    span = width * .5 - .05
    bulbs = width + 2
    points = [(span * (i / (bulbs + 1) - .5), 0,
               .09 - .04 * math.sin(math.pi * i / (bulbs + 1))) for i in range(bulbs + 2)]
    for index in range(len(points) - 1):
        segment("Cord", points[index], points[index + 1], .004, "metalDark")
    for x, y, z in points[1:-1]:
        box("Socket", (.014, .014, .012), (x, y, z - .008), "metalDark")
        ring = [(x + .014 * math.cos(i * math.tau / 6),
                 y + .014 * math.sin(i * math.tau / 6), z - .028) for i in range(6)]
        mesh("Bulb", [(x, y, z - .014), *ring, (x, y, z - .047)],
             [(0, 1 + i, 1 + (i + 1) % 6) for i in range(6)] +
             [(7, 1 + (i + 1) % 6, 1 + i) for i in range(6)], "lamp")
    for x in (-span / 2, span / 2):
        box("Mount", (.018, .028, .018), (x, -.007, .09), "metalDark")


def build():
    args = argparse.ArgumentParser()
    args.add_argument("--manifest", type=Path)
    args.add_argument("--only-awnings", action="store_true",
                      help="Rebuild only awnings; audit the other five existing GLBs without writing them")
    options = args.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    OUTPUT.mkdir(parents=True, exist_ok=True)
    reports = []
    builders = [(f"street_awning_{w}", lambda w=w: awning(w)) for w in (2, 3, 4)]
    builders += [("flower_window_box", flower_box), ("shop_name_sign", sign)]
    builders += [(f"string_lights_{w}", lambda w=w: lights(w)) for w in (2, 3, 4)]
    for asset_id, builder in builders:
        path = OUTPUT / (asset_id + ".glb")
        if not options.only_awnings or asset_id.startswith("street_awning_"):
            bpy.ops.object.select_all(action="SELECT")
            bpy.ops.object.delete(use_global=False)
            builder()
            # True base-centred origins, with no nonuniform object scales.
            meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
            points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
            low = Vector(tuple(min(p[k] for p in points) for k in range(3)))
            high = Vector(tuple(max(p[k] for p in points) for k in range(3)))
            offset = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
            for obj in meshes:
                obj.location -= offset
                for polygon in obj.data.polygons:
                    polygon.use_smooth = False
            bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True,
                                     export_animations=False, export_cameras=False, export_lights=False)
        report = {"id": asset_id, **glb_metrics(path)}
        doc, _ = read_glb(path)
        report["materials"] = [m["name"] for m in doc["materials"]]
        report["world_dimensions"] = [v * SCALE for v in report["dimensions"]]
        assert report["triangles"] < (1500 if "awning" in asset_id else 300), report
        assert not doc.get("images") and not doc.get("animations")
        reports.append(report)
    if options.manifest:
        target = options.manifest.resolve()
        if target.is_relative_to(ROOT):
            raise ValueError("Review manifests must remain outside the shipping project")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps({"uniform_scale": SCALE, "assets": reports}, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    build()
