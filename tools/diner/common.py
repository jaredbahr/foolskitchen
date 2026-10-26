"""Issue #123: Kenney colours plus the named, approved glowing-part exception.

Author in metres, Blender Z-up/front +Y. glTF exports Y-up/front -Z.
No art scale belongs here: wrappers use the project's single ArtScale value.
The reader is standard-library-only; importing this file never starts Blender.
"""
from __future__ import annotations

import hashlib
import importlib
import json
import math
from pathlib import Path
import re
import struct
from typing import Any, Sequence


ASSET_IDS = frozenset({"diner_booth", "diner_stool", "diner_open_sign",
                       "diner_chalkboard", "diner_wall_art_a", "diner_wall_art_b"})
MATERIAL_SOURCES = {
    "wood": ("benchCushion.glb", "wood"),
    "red": ("benchCushion.glb", "carpet"),
    "chrome": ("lampWall.glb", "metal"),
    "dark": ("wall.glb", "metalDark"),
    "cream": ("bathroomCabinetDrawer.glb", "carpetWhite"),
}
NEON_RED_ALBEDO = (0.70, 0.015, 0.02)
NEON_RED_EMISSION = (0.35, 0.0075, 0.01)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    if len(data) < 20 or struct.unpack_from("<4sII", data) != (b"glTF", 2, len(data)):
        raise ValueError(f"Not a complete GLB 2 file: {path}")
    doc: dict[str, Any] | None = None
    binary = b""
    offset = 12
    while offset < len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + size]
        if len(chunk) != size:
            raise ValueError(f"Truncated GLB chunk: {path}")
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    if doc is None:
        raise ValueError(f"Missing GLB JSON: {path}")
    return doc, binary


def _accessor(doc: dict[str, Any], binary: bytes, index: int) -> list[tuple[Any, ...]]:
    item = doc["accessors"][index]
    if "sparse" in item:
        raise ValueError("Sparse accessors are outside this static asset pipeline")
    view = doc["bufferViews"][item["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError("External buffers are outside this GLB pipeline")
    code = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[item["componentType"]]
    count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[item["type"]]
    fmt = "<" + code * count
    stride = view.get("byteStride", struct.calcsize(fmt))
    offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    return [struct.unpack_from(fmt, binary, offset + n * stride) for n in range(item["count"])]


def _identity() -> list[list[float]]:
    return [[float(i == j) for j in range(4)] for i in range(4)]


def _multiply(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _node_matrix(node: dict[str, Any]) -> list[list[float]]:
    if "matrix" in node:
        return [[node["matrix"][j * 4 + i] for j in range(4)] for i in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    return [
        [(1 - 2*y*y - 2*z*z)*sx, (2*x*y - 2*z*w)*sy, (2*x*z + 2*y*w)*sz, tx],
        [(2*x*y + 2*z*w)*sx, (1 - 2*x*x - 2*z*z)*sy, (2*y*z - 2*x*w)*sz, ty],
        [(2*x*z - 2*y*w)*sx, (2*y*z + 2*x*w)*sy, (1 - 2*x*x - 2*y*y)*sz, tz],
        [0, 0, 0, 1],
    ]


def glb_metrics(path: Path) -> dict[str, Any]:
    """Measure indexed vertices after node transforms, not shared accessor bounds."""
    doc, binary = read_glb(path)
    points: list[tuple[float, ...]] = []
    tris = 0
    def visit(index: int, parent: list[list[float]]) -> None:
        nonlocal tris
        node = doc["nodes"][index]
        matrix = _multiply(parent, _node_matrix(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                if prim.get("mode", 4) != 4:
                    raise ValueError(f"Non-triangle primitive in {path}")
                vertices = _accessor(doc, binary, prim["attributes"]["POSITION"])
                indices = [v[0] for v in _accessor(doc, binary, prim["indices"])] if "indices" in prim else list(range(len(vertices)))
                if len(indices) % 3:
                    raise ValueError("Incomplete triangles")
                tris += len(indices) // 3
                for index_ in indices:
                    v = (*vertices[index_], 1)
                    points.append(tuple(sum(matrix[i][k] * v[k] for k in range(4)) for i in range(3)))
        for child in node.get("children", []):
            visit(child, matrix)
    for root in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        visit(root, _identity())
    if not points or not all(math.isfinite(x) for p in points for x in p):
        raise ValueError(f"Missing or nonfinite geometry: {path}")
    low = [min(p[k] for p in points) for k in range(3)]
    high = [max(p[k] for p in points) for k in range(3)]
    return {"triangles": tris, "aabb_min": low, "aabb_max": high,
            "dimensions": [high[k] - low[k] for k in range(3)],
            "sha256": sha256(path)}


class Builder:
    def __init__(self, repo_root: str | Path):
        self.repo = Path(repo_root).resolve(strict=True)
        self.kit = self.repo / "assets/kenney/furniture"
        self.output = self.repo / "assets/made/diner"
        if not (self.repo / "project.godot").is_file():
            raise ValueError("Expected the Fool's Kitchen repository root")
        self.bpy = importlib.import_module("bpy")
        self.objects: list[Any] = []
        self.materials: dict[str, Any] = {}
        self.material_provenance: dict[str, Any] = {}
        self.reports: list[dict[str, Any]] = []
        self.asset_id = ""
        self.references: list[Path] = []
        self.root: Any = None

    def _reference(self, value: str) -> Path:
        name = Path(value).name
        if name != value or not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.glb)?", name):
            raise ValueError("References must be Furniture Kit basenames")
        return (self.kit / (name if name.endswith(".glb") else name + ".glb")).resolve(strict=True)

    def _output(self, filename: str) -> Path:
        target = (self.output / filename).resolve()
        target.relative_to(self.repo.resolve())
        if target.parent != self.output.resolve() or self.output.resolve() != self.repo / "assets/made/diner":
            raise ValueError("Output escaped assets/made/diner")
        self.output.mkdir(parents=True, exist_ok=True)
        return target

    def begin_asset(self, asset_id: str, nearest_reference: str | Sequence[str]) -> None:
        if asset_id not in ASSET_IDS:
            raise ValueError(f"Unapproved asset id: {asset_id}")
        for obj in self.objects:
            mesh = obj.data if obj.type == "MESH" else None
            self.bpy.data.objects.remove(obj, do_unlink=True)
            if mesh is not None and mesh.users == 0:
                self.bpy.data.meshes.remove(mesh)
        self.objects = []
        self.asset_id = asset_id
        refs = [nearest_reference] if isinstance(nearest_reference, str) else list(nearest_reference)
        self.references = [self._reference(r) for r in refs]
        if not self.references:
            raise ValueError("Every made piece needs a nearest kit reference")
        self.root = self.bpy.data.objects.new(asset_id, None)
        self.bpy.context.scene.collection.objects.link(self.root)
        self.objects.append(self.root)

    def material(self, token: str) -> Any:
        if token in self.materials:
            return self.materials[token]
        emissive = token.startswith("emissive_")
        base = token.removeprefix("emissive_") if emissive else token
        source_name, material_name = MATERIAL_SOURCES[base]
        path = self._reference(source_name)
        doc, _ = read_glb(path)
        original = next(m for m in doc["materials"] if m["name"] == material_name)
        pbr = original["pbrMetallicRoughness"]
        colour = (*NEON_RED_ALBEDO, 1.0) if emissive else tuple(pbr["baseColorFactor"])
        if emissive and base != "red":
            raise ValueError("The approved neon emission contract applies only to emissive red")
        emission: dict[str, Any] | None = None
        material = self.bpy.data.materials.new(material_name + ("_emissive" if emissive else ""))
        material.use_nodes = True
        material.diffuse_color = colour
        material.use_backface_culling = not original.get("doubleSided", False)
        node = material.node_tree.nodes.get("Principled BSDF")
        node.inputs["Base Color"].default_value = colour
        node.inputs["Metallic"].default_value = pbr.get("metallicFactor", 1)
        node.inputs["Roughness"].default_value = pbr.get("roughnessFactor", 1)
        if emissive:
            # Keep a deeper albedo under the dedicated linear neon emission so
            # the square tube faces retain their two-tone shading.
            emission_colour = (*NEON_RED_EMISSION, 1.0)
            node.inputs["Emission Color"].default_value = emission_colour
            node.inputs["Emission Strength"].default_value = 1.0
            emission = {
                "color": list(NEON_RED_EMISSION),
                "strength": 1.0,
            }
        self.materials[token] = material
        self.material_provenance[token] = {
            "source": path.relative_to(self.repo).as_posix(), "source_sha256": sha256(path),
            "material": material_name, "source_pbr": pbr,
            "material_albedo": list(colour), "emissive": emissive,
            "emission": emission,
        }
        return material

    def _finish(self, obj: Any, name: str, token: str, bevel: float) -> Any:
        if not self.asset_id:
            raise ValueError("Call begin_asset before constructing geometry")
        obj.name = name
        obj.parent = self.root
        obj.data.materials.clear()
        obj.data.materials.append(self.material(token))
        self.bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        self.bpy.context.view_layer.objects.active = obj
        self.bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel:
            if bevel < 0 or not math.isfinite(bevel):
                raise ValueError("Invalid bevel")
            modifier = obj.modifiers.new("Kit edge softness", "BEVEL")
            modifier.width = bevel
            modifier.segments = 1
            modifier.affect = "EDGES"
            self.bpy.ops.object.modifier_apply(modifier=modifier.name)
        for face in obj.data.polygons:
            face.use_smooth = False
        self.objects.append(obj)
        return obj

    def box(self, name: str, dimensions: Sequence[float], location: Sequence[float],
            material_token: str = "cream", bevel: float = 0.0) -> Any:
        if len(dimensions) != 3 or any(d <= 0 or not math.isfinite(d) for d in dimensions):
            raise ValueError("Box dimensions must be positive metres")
        self.bpy.ops.mesh.primitive_cube_add(size=1, location=location)
        obj = self.bpy.context.object
        obj.dimensions = dimensions
        return self._finish(obj, name, material_token, bevel)

    def cylinder(self, name: str, radius: float, depth: float,
                 location: Sequence[float] = (0, 0, 0), material_token: str = "chrome",
                 vertices: int = 12, rotation: Sequence[float] = (0, 0, 0),
                 bevel: float = 0.0) -> Any:
        if radius <= 0 or depth <= 0 or not math.isfinite(radius + depth) or not 3 <= vertices <= 24:
            raise ValueError("Cylinder must have finite positive dimensions and 3-24 sides")
        self.bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                                location=location, rotation=rotation, end_fill_type="NGON")
        return self._finish(self.bpy.context.object, name, material_token, bevel)

    def custommesh(self, name: str, vertices: Sequence[Sequence[float]],
                   faces: Sequence[Sequence[int]], material_token: str) -> Any:
        if not vertices or not faces or any(len(v) != 3 or not all(math.isfinite(n) for n in v) for v in vertices):
            raise ValueError("Custom mesh requires finite three-dimensional vertices")
        if any(len(f) < 3 or any(i < 0 or i >= len(vertices) for i in f) for f in faces):
            raise ValueError("Invalid mesh face")
        mesh = self.bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = self.bpy.data.objects.new(name, mesh)
        self.bpy.context.scene.collection.objects.link(obj)
        self.bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        return self._finish(obj, name, material_token, 0)

    def export_asset(self, asset_id: str, wall: bool = False) -> dict[str, Any]:
        if asset_id != self.asset_id or len(self.objects) < 2:
            raise ValueError("Only the active nonempty asset may be exported")
        from mathutils import Vector
        meshes = [o for o in self.objects if o.type == "MESH"]
        self.bpy.context.view_layer.update()
        points = [o.matrix_world @ Vector(v) for o in meshes for v in o.bound_box]
        shift = Vector(((min(p.x for p in points) + max(p.x for p in points)) / 2,
                        (min(p.y for p in points) + max(p.y for p in points)) / 2,
                        min(p.z for p in points)))
        for obj in meshes:
            obj.location -= shift
        self.bpy.context.view_layer.update()
        self.bpy.ops.object.select_all(action="DESELECT")
        for obj in self.objects:
            obj.select_set(True)
        self.bpy.context.view_layer.objects.active = self.root
        path = self._output(asset_id + ".glb")
        self.bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                      export_yup=True, export_animations=False, export_cameras=False,
                                      export_lights=False, export_extras=False, export_materials="EXPORT")
        measured = glb_metrics(path)
        limit = 300 if wall else 1500
        if measured["triangles"] >= limit:
            raise ValueError(f"{asset_id} exceeds strict triangle budget {limit}: {measured['triangles']}")
        low, high = measured["aabb_min"], measured["aabb_max"]
        if abs(low[1]) > 1e-5 or abs(low[0] + high[0]) > 1e-5 or abs(low[2] + high[2]) > 1e-5:
            raise ValueError(f"{asset_id} has an incorrect exported base-centre origin")
        sources = {p.relative_to(self.repo).as_posix(): sha256(p) for p in sorted((self.repo / "tools/diner").glob("*.py"))}
        used = {token: info for token, info in self.material_provenance.items()
                if self.materials[token] in [mat for obj in meshes for mat in obj.data.materials]}
        report = {"asset": asset_id, "format": "glTF 2 GLB", "metres_per_unit": 1,
                  "up": "+Y", "front": "-Z", "origin": "base centre", "budget_exclusive": limit,
                  **measured, "references": [{"path": p.relative_to(self.repo).as_posix(), **glb_metrics(p)} for p in self.references],
                  "materials": used, "source_sha256": sources}
        self._output(asset_id + ".metrics.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        self.reports.append(report)
        print(json.dumps({"asset": asset_id, **measured}), flush=True)
        return report

    def write_manifest(self) -> None:
        self._output("diner_manifest.json").write_text(json.dumps({"issue": 123, "assets": self.reports}, indent=2) + "\n", encoding="utf-8")
