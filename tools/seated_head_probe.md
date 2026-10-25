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
JSON `clearance: null` means no seat/backrest geometry intersects the head's X/Y
span behind its midpoint. `facing_dot` must exceed 0.9999. Preserve the original
and final report and compare palms' world height and horizontal table distance
alongside the furnished capture before accepting a forward offset.

All visible catalogue definitions with authored seat cells are included, including
built-in table chairs, every authored seat cell, four placement rotations, all
eight eligible guest rigs, and sit times 0%, 37% and 91% of the imported clip.
Rig-local posed vertices are cached by look and time; the placement, facing,
seat height and model transforms come from actual `ShopView`/`PersonView` nodes.
The test contains coverage assertions, so missing imports or empty samples fail.

`SeatedHeadGeometry.measure_person_head(person)` returns `error`, `world_bounds`
and `person_bounds` (`AABB`), `head_vertices` and `provenance`. The world bounds
are formed after transforming every real posed vertex and can be projected
through the actual capture camera for the derivative crop. `measure(person,
furnishing_node)` additionally reports clearance and seat intrusion. Neither API
moves a person or changes a pose. The bounds include the native head's hair and
are conservative: a seat triangle entering even an empty corner of the measured
head bounds fails. Backrest clearance is the rear-axis gap to actual seat
triangles clipped to that head span, not an asset-name guess or a whole-model
AABB. Closed-seat enclosure is checked by solid-angle winding.

The headless helper performs weighted skinning from the current native Skeleton3D
global poses, imported Skin bind transforms and head mesh vertex weights. This
matches the mathematical order in Godot's implementation, but runtime parity
is only established by the rendered command above. References:
[MeshInstance3D bake documentation](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html#class-meshinstance3d-method-bake-mesh-from-current-skeleton-pose),
[native bake source](https://github.com/godotengine/godot/blob/master/scene/3d/mesh_instance_3d.cpp),
[Skeleton3D skin binding source](https://github.com/godotengine/godot/blob/master/scene/3d/skeleton_3d.cpp).
