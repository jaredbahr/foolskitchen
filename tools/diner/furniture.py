"""The two named diner seats, sized against the unchanged Furniture Kit."""
from __future__ import annotations

from common import Builder


def build_furniture(builder: Builder) -> None:
    # Director 6408764842: front-row seats and a blocking rear backrest row.
    # Keep the benchCushion's 0.24 m seat plane and the old tall silhouette.
    builder.begin_asset("diner_booth", ["benchCushion", "loungeSofa"])
    builder.box("Wood foot plinth", (.86, .60, .04), (0, -.121, .02), "wood", bevel=.005)
    builder.box("Padded bench base", (.90, .642, .16), (0, -.121, .12), "cream", bevel=.01)
    # Export centres source depth [-.442, .20] by -.121. The wrapper puts that
    # assembly at z=-.1708 world metres, aligning the unchanged seat front with
    # the two front-row cells. At shared scale the padded back's front is
    # .3278 m behind their centres: >.02 beyond the actual posed rear hair.
    # The deepened base/cushions connect to the back; no floating tall panel.
    # This authored contract is checked independently in test_diner_content.
    builder.box("Tall back shell", (.90, .06, .46), (0, -.412, .42), "cream", bevel=.01)
    for x, side in [(-.2273, "Left"), (.2273, "Right")]:
        builder.box(side + " seat cushion", (.435, .527, .04), (x, -.0835, .22), "red", bevel=.009)
        builder.box(side + " back cushion", (.435, .035, .36), (x, -.3645, .445), "red", bevel=.01)
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
