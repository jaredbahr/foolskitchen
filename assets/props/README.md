# Kenney item views (FK-052)

These wrappers are centred on their unrotated footprints at floor y = 0.
The world caller positions and rotates the wrapper root for a placed item.
Each direct part contains an `Art` node, turned 180 degrees in the wrapper,
and an untouched imported Kenney model below it. `PropView.prepare()` applies
the shared uniform scale from `ArtScale` to `Art`, preserving the model's own
transforms, then centres the combined descendant bounds and puts its base on
the floor. `Board` uses the food scale and rests on `CabinetLeft`'s top.

`PropView.get_combined_aabb()` returns bounds in wrapper coordinates, including
all nested mesh transforms. `set_body_tint(color)` duplicates only the selected
existing body materials for this wrapper. `clear_body_tint()` restores their
previous overrides. Imported resources and non-body surfaces are not mutated.
`active_body_material()` reads an actual active named body surface; the shared
`ItemVisual.primary_body_material()` also handles the box fallback. Paint
evidence never assumes that the first imported surface is the body.
Food parts are always excluded, even if a future food material shares a body
material name.

| Item | Approved models | Named body surfaces | Surfaces kept as authored |
| --- | --- | --- | --- |
| Stove | `kitchenStove` + `kitchenCabinet` | `wood` | All metal, glass and dark wood trim |
| Fridge | `kitchenFridge` + `kitchenCabinet` | `metalLight`, `wood` | Metal handles/trim, glass and dark wood trim |
| Sink | `kitchenSink` | `wood` | Basin, taps, metal, dark wood and other kit surfaces |
| Prep counter | 2 x `kitchenCabinetDrawer` + Food Kit `cutting-board` | `wood` | Handles, dark wood trim and the entire cutting board |
| Pass counter | 2 x `kitchenBar` | `wood` | Metal and dark wood trim |
| Two-seat table | `table` | `wood` | No other material in this model |
| Chair | `chairCushion` | `wood` | `carpet` cushion |
| Potted plant | `pottedPlant` | `wood` | `woodDark` trim and `plant` foliage |
| Door | `doorwayFront` | `carpetWhite` frame | Door metal and glass |

Existing `ItemDef.paintable` values are unchanged: the stove, sink and door
remain unpaintable. Their mappings document the wrapper contract, rather than
enabling an additional gameplay command. The rectangular `table` is the current
source choice for the two-seat table: its long side fills the two-cell width
without enlarging it. The camera-readability choice still needs the director's
capture review.

Source paths and material names were checked against the vendored GLB metadata
on main `264c305f03fb58954e0f18cccc098a57f01358e8`. Main subsequently advanced to
`1598b1e3f06aef298ecbef1ca317f2dd063335ec`; the comparison contains no changes to
these item definitions, assets or wrapper inputs. Reading GLB metadata is not a
Godot import or an in-engine bounds measurement.

## World integration

- `ItemVisual` adapts a wrapper or the existing box fallback to a floor-centred
  root. Its `get_aabb()` supplies the displayed combined bounds, and its paint
  methods preserve kit details. Authored doors now render their wrapper; a
  placeholder door without a scene keeps its earlier invisible presentation.
- ShopView uses `ArtScale.WALL_HEIGHT`, keeps its cutaway and top-cap paths,
  routes body paint and paint previews through the adapter, and exposes
  `item_bounds(id)`, `item_at_ray(origin, direction)` and `set_selected_item(id)`.
  Ray results are an item ID, -1 for the floor fallback, or `OCCLUDED_ITEM` (-2)
  for a wall in front of the ray. Main now passes that result through its normal
  selection route: selected-owner commands first, drawn agents second, then
  the visible item. Only -1 permits the legacy floor furniture fallback.
- Item selection and unreachable warnings use `BoundsOutline` rails around
  the same model bounds. BuildPreview instantiates the real wrapper, tints a
  private copy of every surface for its ghost, and restores the original item's
  exact visibility on cancel, unbind and deletion. Marker cells remain driven
  by the unchanged checked footprint. Capture metadata reads actual descendant
  meshes and combined bounds. Agent and tray paths are unchanged in this lane.
- Main synchronizes the selected item with ShopView's outline. Its production
  session tests cover native screen picks, owner command precedence, drawn-agent
  priority, the floor fallback and a blocking wall without advancing the sim.
- The capture tool reads `primary_body_material()` for its two paint samples
  and accepts the ItemVisual ghost root. No capture option or workflow is added.

## Remaining integration and verification gates

- Review the combined view/Main/capture source before reconstructing the exact
  changed-file allowlist over official current main. The parent serialized the
  narrow Main/capture boundary separately from other feature branches.
- Run the normal Godot import, collect its actual generated script UIDs and
  run `bash tools/check.sh` on a branch reconstructed from real current main.
  The new prop tests are written but have not run; no script UID is fabricated.
- Verify the actual imported combined bounds, y = 0, part facing, material
  names and body-only paint. Check the doorway's clear opening against the
  style lock as well as the outer footprint. The source leaf bounds at the
  locked scale are about 0.47 wide and 1.08 high; those are not a measured clear
  opening and may require a director decision on the 0.5 by 1.1 minimum. Never
  stretch the model to conceal a fit discrepancy.
- Capture before and after default, cutaway and paint views, with people beside
  the furniture, for the director's pixel acceptance.
- Add a player-readable CHANGELOG entry with the actual PR number after world
  integration. Proposed wording: "Chairs, tables and kitchen equipment now use
  matching Kenney models, and painted furniture keeps its metal and glass details."

This checkout is a source preparation branch with local proxy ancestry. Never
push that ancestry. A source checkpoint is not a complete or review-ready #97 PR.
