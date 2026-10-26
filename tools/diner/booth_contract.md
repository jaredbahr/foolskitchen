# Tall diner booth

Director decision: [PR147 comment 6408764842](https://github.com/jaredbahr/foolskitchen/pull/147#issuecomment-6408764842).
The tall booth occupies two cells across and two deep. Its front row is the two
seat cells `(0, 0)` and `(1, 0)`. The rear row `(0, 1)`, `(1, 1)` blocks movement,
has no seat or work cells, and costs floor space in exchange for the tall back.
The price is 105, up from 90. The compact low back is a separate future variant.

`ItemDef.blocking_cells` supplies those explicit occupied cells while `solid`
remains false. Empty blocking lists retain the existing boolean-solid behavior.
The grid rotates and snapshots the list on placement and relocation, refreshes
old cells on moves/removal, and reconstructs it from content when loading a shop.
No new saved field or save action is needed. Blocking lists must contain unique
footprint-local cells, disjoint from seats/work cells; floor decor cannot use them.

## Authored geometry

`furniture.py` uses Blender Z-up, front +Y. Export converts to Y-up/front -Z and
centres source depth `[-0.442, 0.20]` by `-0.121`. The GLB remains base-centred.
The wrapper's `Seat` part then sits at world `z=-0.1708`, aligning the seat front
with the front row of the larger footprint. `PropView` still applies only the
shared uniform furniture scale of 1.1. The character position, native animation,
seat height and supported forward adjustment are unchanged.

| Part | Authored dimensions | Authored centre |
|---|---|---|
| White back shell | 0.90 × 0.06 × 0.46 | (0, -0.412, 0.42) |
| Red back cushions | 0.435 × 0.035 × 0.36 | (±0.2273, -0.3645, 0.445) |
| Red seat cushions | 0.435 × 0.527 × 0.04 | (±0.2273, -0.0835, 0.22) |
| White base | 0.90 × 0.642 × 0.16 | (0, -0.121, 0.12) |
| Wood plinth | 0.86 × 0.60 × 0.04 | (0, -0.121, 0.02) |

The base and seat cushions extend to the back, supporting the tall shell and
avoiding a detached panel. The original shell top returns to 0.715 world metres;
the seat top remains 0.264. White uses the unchanged kit `carpetWhite` material.
The model has the same seven parts and bevel topology.

Literal expected item-local world bounds are X `[-0.495, 0.495]`, Y `[0, 0.715]`,
Z `[-0.5239, 0.1823]`, within the new footprint plus 0.05 per side. The front row's
seat centres are X `±0.25`, Z `-0.25`. The padded back starts at item Z `0.0778`,
or 0.3278 behind those centres. Its white shell starts at item Z `0.1163`.
The seat cushions span item Z `[-0.5019, 0.0778]`; their bevel-flat top still
contains both actual hip rays. The 0.05 forward offset places the hip pivots at
item Z `-0.268375`, with at least 0.1373919 m margin inside the flat cushion top.

## Verification contract

`test_diner_content.gd` asserts literal imported part positions and wrapper
placement independently of production seat-height/placement getters. It also
checks front/rear cells and the four rotated front-row centres. The focused pure
grid/editor tests cover blocking, dining links, paths, mutation-free edit checks,
move/rotate/sell, invalid definitions and restored agents under blocking cells.

Source-only indexed weighted Mini sit-triangle calculations give a conservative
minimum head/back gap of 0.026434892 m for `character-female-e`, including the
actual pivot, shared scales, seat lift and 0.05 adjustment. The calculation uses
unbevelled boxes containing the intended seat geometry and finds no crossing.
This is a construction bound, **not an exported-geometry or runtime pass**.

After bounded Blender regeneration and import, the existing actual-surface
catalogue acceptance must still measure all 1,632 cases, including all 288 made
seat cases, without new exceptions or changed offset/clearance limits. Retain
the native 24-pose vertex-parity check and the two real review frames plus their
3× seated crop. Move the reversed review-fixture booth origin from `(2, 5)` to
`(2, 4)` so its front seats stay in row 5 facing the table in row 6; its new rear
row occupies row 4. The first booth remains at `(2, 7)`, facing forward.
