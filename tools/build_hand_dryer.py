"""Rebuild the Director-approved #198 hand dryer with installed Blender.

blender --background --factory-startup --python tools/build_hand_dryer.py
Metres, Blender Z-up/front +Y; export Y-up/front -Z. Shared ArtScale is
applied only by PropView. No textures, downloads or services are used.
"""
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/diner"))
from common import read_glb


def kit_material(filename: str, name: str):
    doc, _ = read_glb(ROOT / "assets/kenney/furniture" / filename)
    source = next(m for m in doc["materials"] if m["name"] == name)
    pbr = source["pbrMetallicRoughness"]
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = pbr["baseColorFactor"]
    shader.inputs["Metallic"].default_value = pbr.get("metallicFactor", 1)
    shader.inputs["Roughness"].default_value = pbr.get("roughnessFactor", 1)
    return material


def box(name: str, size: tuple, center: tuple, material, bevel: float):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    modifier = obj.modifiers.new("Soft kit edges", "BEVEL")
    modifier.width = bevel
    modifier.segments = 1
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
cream = kit_material("bathroomCabinetDrawer.glb", "carpetWhite")
steel = kit_material("wall.glb", "metalDark")
# Total envelope .30 wide x .25 high x .15 deep, base-centred.
box("RoundedHousing", (.30, .15, .22), (0, 0, .14), cream, .018)
box("DownwardNozzle", (.13, .075, .045), (0, .023, .0225), steel, .006)
box("FrontSensor", (.024, .006, .018), (0, .076, .085), steel, .003)
output = ROOT / "assets/made/restroom/wall_hand_dryer.glb"
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False)
