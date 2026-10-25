"""Procedural, low-poly wall props for the classic diner set.

The models use the existing Kenney material tokens exposed by common.py. OPEN is
made from square-profile emissive geometry; the sign contains no light object or
baked lettering texture. Chalkboard lettering is intentionally left to the game.
"""

from __future__ import annotations

from typing import Sequence

from common import Builder


# Each custom box is a closed six-quad prism: 12 triangles after triangulation.
_BOX_FACES: tuple[tuple[int, int, int, int], ...] = (
    (0, 3, 2, 1),  # bottom
    (4, 5, 6, 7),  # top
    (0, 1, 5, 4),  # back
    (1, 2, 6, 5),  # right
    (2, 3, 7, 6),  # front
    (3, 0, 4, 7),  # left
)


def _box_mesh(
    builder: Builder,
    name: str,
    dimensions: tuple[float, float, float],
    location: tuple[float, float, float],
    material_token: str,
) -> None:
    """Add one axis-aligned closed box through the builder's custom-mesh API."""
    half_x, half_y, half_z = (component / 2.0 for component in dimensions)
    center_x, center_y, center_z = location
    vertices = [
        (center_x - half_x, center_y - half_y, center_z - half_z),
        (center_x + half_x, center_y - half_y, center_z - half_z),
        (center_x + half_x, center_y + half_y, center_z - half_z),
        (center_x - half_x, center_y + half_y, center_z - half_z),
        (center_x - half_x, center_y - half_y, center_z + half_z),
        (center_x + half_x, center_y - half_y, center_z + half_z),
        (center_x + half_x, center_y + half_y, center_z + half_z),
        (center_x - half_x, center_y + half_y, center_z + half_z),
    ]
    builder.custommesh(name, vertices, list(_BOX_FACES), material_token)


def _stroke_mesh(
    builder: Builder,
    name: str,
    start: tuple[float, float],
    end: tuple[float, float],
    width: float,
    depth: float,
    y: float,
    material_token: str,
) -> None:
    """Add one square-profile OPEN stroke in the front-facing X/Z plane."""
    dx = end[0] - start[0]
    dz = end[1] - start[1]
    length = (dx * dx + dz * dz) ** 0.5
    normal_x = -dz / length * width / 2.0
    normal_z = dx / length * width / 2.0
    y_back = y - depth / 2.0
    y_front = y + depth / 2.0
    vertices = [
        (start[0] - normal_x, y_back, start[1] - normal_z),
        (end[0] - normal_x, y_back, end[1] - normal_z),
        (end[0] + normal_x, y_back, end[1] + normal_z),
        (start[0] + normal_x, y_back, start[1] + normal_z),
        (start[0] - normal_x, y_front, start[1] - normal_z),
        (end[0] - normal_x, y_front, end[1] - normal_z),
        (end[0] + normal_x, y_front, end[1] + normal_z),
        (start[0] + normal_x, y_front, start[1] + normal_z),
    ]
    builder.custommesh(name, vertices, list(_BOX_FACES), material_token)


def _frame(
    builder: Builder,
    prefix: str,
    center_z: float,
    inner_width: float,
    inner_height: float,
    rail: float,
    depth: float,
) -> None:
    """Build a four-piece wood frame around a flat image or chalk panel."""
    outer_width = inner_width + 2.0 * rail
    outer_height = inner_height + 2.0 * rail
    y = depth / 2.0
    _box_mesh(
        builder,
        f"{prefix}_frame_top",
        (outer_width, depth, rail),
        (0.0, y, center_z + inner_height / 2.0 + rail / 2.0),
        "wood",
    )
    _box_mesh(
        builder,
        f"{prefix}_frame_bottom",
        (outer_width, depth, rail),
        (0.0, y, center_z - inner_height / 2.0 - rail / 2.0),
        "wood",
    )
    _box_mesh(
        builder,
        f"{prefix}_frame_left",
        (rail, depth, inner_height),
        (-inner_width / 2.0 - rail / 2.0, y, center_z),
        "wood",
    )
    _box_mesh(
        builder,
        f"{prefix}_frame_right",
        (rail, depth, inner_height),
        (inner_width / 2.0 + rail / 2.0, y, center_z),
        "wood",
    )


def _triangle_panel(
    builder: Builder,
    name: str,
    points: Sequence[tuple[float, float]],
    y: float,
    depth: float,
    material_token: str,
) -> None:
    """Add a filled triangular prism defined by three X/Z points."""
    front_y = y + depth / 2.0
    back_y = y - depth / 2.0
    vertices = [
        (x, back_y, z) for x, z in points
    ] + [
        (x, front_y, z) for x, z in points
    ]
    faces = [
        (0, 2, 1),
        (3, 4, 5),
        (0, 1, 4, 3),
        (1, 2, 5, 4),
        (2, 0, 3, 5),
    ]
    builder.custommesh(name, vertices, faces, material_token)


def _build_open_sign(builder: Builder) -> None:
    """Build a geometric OPEN neon sign with square tube-like strokes."""
    builder.begin_asset(
        "diner_open_sign",
        ["lampWall.glb", "wall.glb"],
    )
    # Compact dark housing and two simple wall brackets. The housing is 12 tris;
    # brackets are 24 tris total.
    _box_mesh(builder, "open_sign_housing", (0.86, 0.055, 0.34), (0.0, 0.0, 0.22), "dark")
    _box_mesh(builder, "open_sign_bracket_left", (0.09, 0.08, 0.045), (-0.32, -0.045, 0.035), "chrome")
    _box_mesh(builder, "open_sign_bracket_right", (0.09, 0.08, 0.045), (0.32, -0.045, 0.035), "chrome")

    # Fifteen closed rectangular strokes form four readable block letters.
    # 15 × 12 triangles + 12 housing + 24 brackets = 216 source triangles.
    width = 0.145
    height = 0.19
    stroke = 0.026
    z_bottom = 0.125
    z_top = z_bottom + height
    mid_z = (z_bottom + z_top) / 2.0
    centers = (-0.2925, -0.0975, 0.0975, 0.2925)
    letters: tuple[tuple[str, tuple[tuple[tuple[float, float], tuple[float, float]], ...]], ...] = (
        (
            "O",
            (
                ((centers[0] - width / 2.0, z_bottom), (centers[0] + width / 2.0, z_bottom)),
                ((centers[0] - width / 2.0, z_top), (centers[0] + width / 2.0, z_top)),
                ((centers[0] - width / 2.0, z_bottom), (centers[0] - width / 2.0, z_top)),
                ((centers[0] + width / 2.0, z_bottom), (centers[0] + width / 2.0, z_top)),
            ),
        ),
        (
            "P",
            (
                ((centers[1] - width / 2.0, z_bottom), (centers[1] - width / 2.0, z_top)),
                ((centers[1] - width / 2.0, z_top), (centers[1] + width / 2.0, z_top)),
                ((centers[1] - width / 2.0, mid_z), (centers[1] + width / 2.0, mid_z)),
                ((centers[1] + width / 2.0, mid_z), (centers[1] + width / 2.0, z_top)),
            ),
        ),
        (
            "E",
            (
                ((centers[2] - width / 2.0, z_bottom), (centers[2] - width / 2.0, z_top)),
                ((centers[2] - width / 2.0, z_top), (centers[2] + width / 2.0, z_top)),
                ((centers[2] - width / 2.0, mid_z), (centers[2] + width / 2.0, mid_z)),
                ((centers[2] - width / 2.0, z_bottom), (centers[2] + width / 2.0, z_bottom)),
            ),
        ),
        (
            "N",
            (
                ((centers[3] - width / 2.0, z_bottom), (centers[3] - width / 2.0, z_top)),
                ((centers[3] + width / 2.0, z_bottom), (centers[3] + width / 2.0, z_top)),
                ((centers[3] - width / 2.0, z_bottom), (centers[3] + width / 2.0, z_top)),
            ),
        ),
    )
    for letter, strokes in letters:
        for stroke_index, (start, end) in enumerate(strokes):
            _stroke_mesh(
                builder,
                f"open_sign_{letter.lower()}_stroke_{stroke_index}",
                start,
                end,
                stroke,
                0.024,
                0.034,
                "emissive_red",
            )
    builder.export_asset("diner_open_sign", wall=True)


def _build_chalkboard(builder: Builder) -> None:
    """Build an empty chalkboard; UI text is composed by the game theme font."""
    builder.begin_asset(
        "diner_chalkboard",
        ["wallWindow.glb", "paneling.glb"],
    )
    center_z = 0.28
    inner_width = 0.59
    inner_height = 0.45
    _box_mesh(
        builder,
        "chalkboard_surface",
        (inner_width, 0.025, inner_height),
        (0.0, 0.0125, center_z),
        "dark",
    )
    _frame(builder, "chalkboard", center_z, inner_width, inner_height, 0.055, 0.05)
    builder.export_asset("diner_chalkboard", wall=True)


def _build_wall_art_a(builder: Builder) -> None:
    """Build a framed, simple sunrise composition from palette geometry."""
    builder.begin_asset(
        "diner_wall_art_a",
        ["wallWindow.glb", "paneling.glb"],
    )
    center_z = 0.27
    inner_width = 0.52
    inner_height = 0.36
    _box_mesh(
        builder,
        "wall_art_a_canvas",
        (inner_width, 0.025, inner_height),
        (0.0, 0.0125, center_z),
        "cream",
    )
    _frame(builder, "wall_art_a", center_z, inner_width, inner_height, 0.055, 0.05)
    builder.cylinder(
        "wall_art_a_sun",
        radius=0.075,
        depth=0.035,
        location=(0.0, 0.047, center_z + 0.035),
        material_token="red",
        vertices=8,
        rotation=(90.0, 0.0, 0.0),
    )
    _box_mesh(
        builder,
        "wall_art_a_horizon",
        (0.37, 0.025, 0.025),
        (0.0, 0.052, center_z - 0.055),
        "chrome",
    )
    builder.export_asset("diner_wall_art_a", wall=True)


def _build_wall_art_b(builder: Builder) -> None:
    """Build a framed abstract composition using two chunky flat triangles."""
    builder.begin_asset(
        "diner_wall_art_b",
        ["wallWindow.glb", "paneling.glb"],
    )
    center_z = 0.27
    inner_width = 0.52
    inner_height = 0.36
    _box_mesh(
        builder,
        "wall_art_b_canvas",
        (inner_width, 0.025, inner_height),
        (0.0, 0.0125, center_z),
        "cream",
    )
    _frame(builder, "wall_art_b", center_z, inner_width, inner_height, 0.055, 0.05)
    _triangle_panel(
        builder,
        "wall_art_b_red_peak",
        ((-0.18, 0.13), (0.015, 0.42), (0.13, 0.13)),
        0.047,
        0.025,
        "red",
    )
    _triangle_panel(
        builder,
        "wall_art_b_dark_peak",
        ((-0.015, 0.13), (0.16, 0.35), (0.25, 0.13)),
        0.057,
        0.025,
        "dark",
    )
    builder.export_asset("diner_wall_art_b", wall=True)


def build_wall_pieces(builder: Builder) -> None:
    """Export the four bounded wall assets required by diner build content."""
    _build_open_sign(builder)
    _build_chalkboard(builder)
    _build_wall_art_a(builder)
    _build_wall_art_b(builder)
