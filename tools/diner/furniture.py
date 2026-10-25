"""The two named diner seats, sized against the unchanged Furniture Kit."""
from __future__ import annotations

from common import Builder


def build_furniture(builder: Builder) -> None:
    # One model spans the existing two-cell bench footprint. Two padded halves
    # retain the benchCushion's 0.24 m seat plane and the sofa's chunky silhouette.
    builder.begin_asset("diner_booth", ["benchCushion", "loungeSofa"])
    builder.box("Wood foot plinth", (.86, .35, .04), (0, 0, .02), "wood", bevel=.005)
    builder.box("Padded bench base", (.90, .40, .16), (0, 0, .12), "cream", bevel=.01)
    builder.box("Tall back shell", (.90, .08, .46), (0, -.16, .42), "cream", bevel=.01)
    for x, side in [(-.2273, "Left"), (.2273, "Right")]:
        builder.box(side + " seat cushion", (.435, .29, .04), (x, .035, .22), "red", bevel=.009)
        builder.box(side + " back cushion", (.435, .055, .36), (x, -.104, .445), "red", bevel=.012)
    builder.export_asset("diner_booth")

    # stoolBar's exact top plane is 0.435 m and its greatest width 0.26544 m.
    # Its faceted round cushion is retained; the diner variant uses a single
    # post and low pedestal in the kit's existing metal colour, with no gloss.
    builder.begin_asset("diner_stool", ["stoolBar", "lampWall"])
    builder.cylinder("Low pedestal", .125, .025, (0, 0, .0125), "chrome", vertices=12, bevel=.005)
    builder.cylinder("Chrome post", .027, .32, (0, 0, .185), "chrome", vertices=12)
    builder.cylinder("Cushion support", .115, .025, (0, 0, .345), "chrome", vertices=12, bevel=.004)
    builder.cylinder("Round red cushion", .13272, .08, (0, 0, .395), "red", vertices=12, bevel=.01)
    # A small 12-sided foot ring is made as a mesh, not a high-poly torus.
    import math
    ring_vertices = []
    for z, radius in [(.13, .08), (.13, .092), (.145, .08), (.145, .092)]:
        ring_vertices.extend((radius * math.cos(i * math.tau / 12),
                              radius * math.sin(i * math.tau / 12), z) for i in range(12))
    ring_faces = []
    for i in range(12):
        j = (i + 1) % 12
        ring_faces.extend([(i, j, 12+j, 12+i), (24+i, 36+i, 36+j, 24+j),
                           (i, 24+i, 24+j, j), (12+i, 12+j, 36+j, 36+i)])
    builder.custommesh("Foot ring", ring_vertices, ring_faces, "chrome")
    builder.export_asset("diner_stool")
