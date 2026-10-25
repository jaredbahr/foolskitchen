# Seated head clearance review

Run these only when the coordinator admits runtime work. Import the project
normally first. No result is recorded by this source change.

## Original geometry baseline

Before changing geometry or seated offsets, run against PR147's original
geometry and presentation with the measurement tool added:

```sh
godot --headless --path . --script tools/seated_head_probe.gd -- --out=original-seat-clearance.json
```

Exit 1 is expected if the review's original clipping reproduces. Keep the JSON:
the booth's measured failing rows demonstrate that the regression catches it.
This is a diagnostic command; do not run the full suite until the actual fixes
are integrated. The probe does not modify imported assets, definitions or saves.

## Native bake parity and final regression

```sh
godot --rendering-method gl_compatibility --path . --script tools/seated_head_probe.gd -- --native-bake --out=final-seat-clearance-native.json
godot --headless --path . --script tools/run_tests.gd -- --filter=seated_head_clearance
```

The native bake command requires a real rendered Compatibility session (a dummy
headless renderer cannot supply its skin buffers). Every sample must have an
empty `error`, `native_bake_max_error <= 0.00001`, no intersecting seat triangles,
no enclosed head, and `clearance >= 0.02` within 0.000001 numerical tolerance.
Every successful measurement has a finite `clearance` and the exact
`clearance_metric` label from `SeatedHeadGeometry.CLEARANCE_METRIC`.
`facing_dot` must exceed 0.9999. Preserve the original
and final report and compare palms' world height and horizontal table distance
alongside the furnished capture before accepting a forward offset.

All visible catalogue definitions with authored seat cells are included, including
built-in table chairs, every authored seat cell, four placement rotations, all
eight eligible guest rigs, and sit times 0%, 37% and 91% of the imported clip.
Rig-local posed vertices are cached by look and time; the placement, facing,
seat height and model transforms come from actual `ShopView`/`PersonView` nodes.
The test contains coverage assertions, so missing imports or empty samples fail.
Rendered parity compares the 24 distinct mesh-local model/time poses once each,
awaiting `RenderingServer.frame_post_draw` only for those 24 first encounters.
Every placement still receives a clearance measurement. The report records
`native_bake_upload_waits`, per-pose `native_bake_poses` results, and each sample's
`native_bake_pose_key`, `native_bake_reused`, error and provenance. A failed pose
comparison fails every sample that uses it; a non-finite parity error is encoded
as JSON null with its failure message retained. No runtime parity is implied by
the presence of this source or by cached mathematical pose calculations.

`SeatedHeadGeometry.measure_person_head(person)` returns `error`, `world_bounds`
and `person_bounds` (`AABB`), `head_vertices` and `provenance`. The world bounds
are formed after transforming every real posed vertex and can be projected
through the actual capture camera for the derivative crop. `measure(person,
furnishing_node)` additionally reports clearance and seat intrusion. Neither API
moves a person or changes a pose. The bounds include the native head's hair and
are conservative: a seat triangle entering even an empty corner of the measured
head bounds fails. Clearance is the minimum Euclidean separation between every
actual seat triangle and the conservative posed-head bounds. Nearby backrest
top and side edges count even when they lie outside the head's X/Y span. The
distance enumerates vertex/face and edge/edge features; only a true box-distance
lower bound prunes expensive feature work. Six-plane clipping detects triangle
intersection, and solid-angle winding detects closed-seat enclosure. Neither
check is skipped by distance pruning. The catalogue's 1,632 placement samples
and 24 rendered parity comparisons remain unchanged; runtime cost is unmeasured.

The headless helper performs weighted skinning from the current native Skeleton3D
global poses, imported Skin bind transforms and head mesh vertex weights. This
matches the mathematical order in Godot's implementation, but runtime parity
is only established by the rendered command above. References:
[MeshInstance3D bake documentation](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html#class-meshinstance3d-method-bake-mesh-from-current-skeleton-pose),
[native bake source](https://github.com/godotengine/godot/blob/master/scene/3d/mesh_instance_3d.cpp),
[Skeleton3D skin binding source](https://github.com/godotengine/godot/blob/master/scene/3d/skeleton_3d.cpp).
