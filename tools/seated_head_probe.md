# Seated head clearance review

Director clarification: [PR147 comment 6404820766](https://github.com/jaredbahr/foolskitchen/pull/147#issuecomment-6404820766).
Use the actual indexed, skinned Mini head in `sit` at shared scale 1.1. Its
nearest identified backrest surface must be at least 0.02 m away. No head vertex
may lie inside any seat part. A non-backrest arm/cushion does not inherit the
0.02 m gap rule. Offsets stay at most 0.05 m and retain cushion support.

## Commands and unchanged bounds

Use the normal repository runtime workflow and current cooperative gaming
policy. No extra CI job or workflow loop.

```sh
godot --headless --path . --script tools/seated_head_probe.gd -- --out=seat-clearance.json
godot --rendering-method gl_compatibility --path . --script tools/seated_head_probe.gd -- --native-bake --out=seat-clearance-native.json
godot --headless --path . --script tools/run_tests.gd -- --filter=seated_head_clearance
```

The catalogue covers 14 definitions, 21 authored seat cells, four rotations,
eight guest looks and three imported sit times: 2,016 rows (1,632 before
`table_4` added one definition and four seat cells). Rendered parity compares
all 24 distinct model/time poses, with 24 first-pose upload waits. The native comparison uses every native vertex; collision/crop geometry uses each
surface's actual indices, with a nonindexed fallback. An unused position cannot
inflate the collision geometry or crop bounds.

`failures` counts unexpected failures and errors; nonzero exits 1. `raw_failures`
also includes the reported kit failures. Every row retains its original `passes`
value and actual measurements. `accepted` is the separate catalogue policy.
Exceptions cannot waive errors, missing head/seat triangles, native bake parity,
facing, the 0.05 offset limit, or an unknown/new/made item ID.

## Measurement contract

`SeatedHeadGeometry.measure(person, furnishing_prop)` returns:

- `error`: nonempty means unusable measurement; never waived.
- `backrest_clearance`: finite metres for `named_parts`; null for `backless` or
  unclassified geometry. Null is never an invented passing gap.
- `backrest_status`: `named_parts`, `backless`, `unclassified_kit` or `unclassified`.
- `backrest_parts`: mesh node paths; `nearest_backrest_part`: the actual witness.
- `clearance_metric`: `indexed posed-head mesh to identified backrest surfaces`.
- `head_vertices_inside_count`: unique referenced head positions inside solids;
  `max_head_vertex_penetration`: greatest such vertex's nearest-boundary depth.
- `head_seat_surface_crossings`: number of seat parts with an actual proper
  crossing witness (a lower bound, not the total number of triangle pairs).
- `intrusion_parts`: path strings; `intrusion_details`: each part's inside count,
  maximum vertex depth and crossing-witness flag.
- `measurement_complete`, `passes`, head/seat triangle counts, and provenance.
- `hips_supported`: true/false for the made booth/stool, null for unannotated kit
  support. `hip_bone_positions`, `hip_support_points` are two person-local XYZ
  arrays; `hip_support_parts` names the actual cushions hit by downward rays from
  the real current `leg-left` and `leg-right` bone pivots. Both must hit for a
  made seat to pass. The base or plinth cannot masquerade as a cushion.

The booth's exact named backrest meshes are `Left back cushion`, `Right back
cushion`, `Tall back shell`. Its support meshes are `Left seat cushion` and
`Right seat cushion`; the stool uses `Round red cushion`. The three explicitly
backless wrapper IDs are `bar_stool`, `square_bar_stool`, `diner_stool`.
Unclassified joined kit meshes receive no fabricated whole-prop backrest gap.
In particular, table_2 does not measure the table or opposite chair as the
current guest's backrest. All its parts still participate in intrusion checks.

Joined kit backrests have explicit source-polygon selections in
`seated_head_backrests.json` (schema 2). Each source pins its GLB SHA-256 and
complete indexed source-face inventory, with a nonempty proper backrest subset.
Face strings encode nine little-endian IEEE-754 float32 coordinates; this avoids
Godot JSON decimal precision loss without introducing a geometry tolerance.
The manual `audit_seated_backrests.py` verifies every source bit, original face
order, hash and selection, and draws front/side/top SVGs for independent review.

Native matching applies the pinned engine's exact `TriangleMesh::create`
`snappedf(0.0001)` conversion to the source inventory, then compares complete
triangle multisets bit for bit (order/winding independent, multiplicity retained).
See [Godot ed1daf0bf, triangle_mesh.cpp:127](https://github.com/godotengine/godot/blob/ed1daf0bf/core/math/triangle_mesh.cpp#L127).
This reproduces `Mesh.get_faces()`, already used by the seat oracle; it does not
change the clearance epsilon, 0.02 m gap, source assets or collision geometry.
Every returned selected triangle is taken from the actual native mesh.
Unknown sources stay unclassified; missing, changed or invalid inventories fail
closed. The source audit additionally detects manifest/source discrepancies
smaller than the engine's face-grid conversion.

Every original complete joined mesh remains in vertex-inside and crossing tests.
Only backrest distance uses the audited polygon subset. Multi-chair wrappers
validate all expected sources and choose the nearest native chair origin in the
guest's floor plane, retaining exact ties; opposite chairs remain collision parts.
Cache identity includes both complete and selected geometry. Provenance reports
selected/full triangle counts and a source/selection digest. Continuous source
faces remain whole, including conservative rear-stile/shell extensions.
Classification is not a seat-fit fix and never grants an exception.

`measure_person_head(person)` retains `world_bounds`, `person_bounds` (AABB),
`head_vertices`, `error` and `provenance` for camera framing. Those bounds are
formed from referenced posed vertices and are not the collision acceptance
shape. Neither API changes a pose, placement, asset, definition or save.

Triangle bounds and whole-part bounds only prune impossible comparisons. Exact
head/backrest distance enumerates triangle vertex/face and edge/edge features;
proper surface crossings and per-part solid-angle vertex containment remain
separate. The comparison cache hashes and then compares the entire normalized
person-local geometry payload. An item ID, nominal pose or rounded AABB alone
cannot reuse a passing result. The complete native catalogue and renderer-parity results are recorded in the PR;
physical kit exceptions remain separately reported.

## Cushioned chair correction

Director review rejected the earlier 33-degree pose: it cleared the backrest
but pushed heads into real tables. Jared chose a small 10–15 degree lean and
accepted the remaining chair backrest overlap (comment6460103763). `chair`
therefore remains an explicit measured exception; this does not complete #155.

The private sit clip rotates only the native torso joint. Root/hip/leg transforms,
character proportions, shared scale, source assets, simulation cells and random
streams stay unchanged. Pose/parity cache keys include the actual lean. Native
parity must still meet the unchanged 1e-5 bound for every measured pose.

`seated_table_clearance.gd` uses production ShopView seating at real cross,
glass, cloth and round tables, with a guest opposite. It measures every table
mesh for head vertices inside and surface crossings, and reports exact posed
head-surface separation across the table. Backrest overlap is a separate
finding and cannot excuse a table intrusion. Tables and both guests stay
visible in native review images. Generated images and JSON remain outside
the shipped repository; the visual-review artifact carries the images.

```sh
godot --headless --path . --script tools/seated_table_review.gd -- --sweep --out=/fresh/table-sweep
godot --rendering-method gl_compatibility --path . --script tools/seated_table_review.gd -- --capture-only --out=/fresh/table-review
```

## Explicit unchanged-kit findings

The Director permitted item-ID exceptions for kit seats that still fail mesh
measurements. The first nine were observed with actual head/seat surface crossings
in the bounded read-only source audit (at least one of the eight native looks);
`table_4` was measured at runtime for PR #152:

| Item ID | Actual physical finding at the unchanged original pose |
|---|---|
| bench | Indexed head triangles cross a bench mesh |
| chair | Crosses chairCushion; Jared accepts the measured remainder with a small lean, subject to real-table safety |
| cushioned_bench | Two looks cross benchCushion; six other looks had a 0.003575 surface gap, which alone is not proof of a backrest-rule violation |
| lounge_chair | Indexed head triangles cross loungeChair |
| modern_chair | Indexed head triangles cross chairModernCushion |
| modern_frame_chair | Indexed head triangles cross chairModernFrameCushion |
| rounded_chair | Indexed head triangles cross chairRounded |
| table_2 | Indexed head triangles cross the guest's own ChairLeft chairCushion in the audited first seat |
| table_4 | All 384 of its rows show a single crossing with the guest's own chairCushion and 0 head vertices inside: the same class as table_2 |
| wooden_chair | Indexed head triangles cross chair |

This table records physical crossing evidence, not invented penetration depths.
The runtime report records measured inside-vertex counts/depths and crossing
witnesses for every row and aggregates them under `known_kit_failures`. Every
allowlisted ID must have at least one actual physical violation in that report;
unknown backrest classification alone cannot justify an exception. A stale
exception fails. The new booth and stool have no exception.

## Preserved history: withdrawn whole-head-box criterion

Original baseline source `60686df56c731b80b05e439f4e4482fbbcb9662a` produced
1,632 rows, no errors and 1,344 whole-box failures. Rendered native skin parity on
`1eab9f37755510e0185b728ff2cef021fdaff41e` passed 24 poses with maximum vertex
error 0.0. These validate the source skinning order, not the withdrawn collision
criterion. Keep those original receipts and JSON for comparison. They do not
establish acceptance of this new surface oracle.

`measure_triangles(AABB, triangles)` and its older focused mathematical tests are
retained only as withdrawn diagnostics, explicitly labelled by
`WITHDRAWN_AABB_METRIC`/`withdrawn_criterion`. Catalogue/capture acceptance never
uses them. Empty corners of the whole-head box do not count as head geometry.

References: [native bake documentation](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html#class-meshinstance3d-method-bake-mesh-from-current-skeleton-pose),
[Godot native bake source](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/mesh_instance_3d.cpp),
[skin binding source](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/skeleton_3d.cpp).

## Supported-offset exception eligibility

Each allowlisted kit ID also gets one explicit `character-female-e`, turn-zero,
first-seat, sit-time-zero eligibility trial at 0.05 m. These records (one per ID) live in
`known_kit_offset_trials`; they do not add catalogue rows, change definitions,
move scene nodes, advance animation, or add native bake waits. Actual pose
triangles are translated by the difference from the authored offset. Both real
hip rays must retain the baseline native seat-surface height; a floor/plinth hit
at a different height does not establish support. A physical violation must
remain at that supported trial before an item exception can apply.

The bounded read-only source audit at 0.05 found actual head/seat crossing pairs
for all nine representative looks: bench 75, chair 71, cushioned_bench 41, lounge
54, modern 53, framed modern 65, rounded 52, table_2 own chair 71, wooden 63.
These counts are historical source-audit evidence, not new native runtime
penetration depths. The runtime report must independently record supported
trial results and actual inside-vertex depths/crossing witnesses. The new oracle,
its focused tests and runtime performance must be verified on the submitted
head; historical source counts alone are not acceptance.
