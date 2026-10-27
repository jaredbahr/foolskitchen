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
| Two-seat table | `table` + 2 x `chairCushion` | `wood` on table and chair frames | `carpet` chair cushions |
| Chair | `chairCushion` | `wood` | `carpet` cushion |
| Potted plant | `pottedPlant` | `wood` | `woodDark` trim and `plant` foliage |
| Door | `doorwayFront` | `carpetWhite` frame | Door metal and glass |
| Bar section (FK-083) | `kitchenBar`, flush to the guest (-Z) edge | `wood` | Metal and dark wood |
| Bar end, left/right | `kitchenBar` + `kitchenBarEnd` (0.035 over the inner edge, onto the neighbour's identical bar) | `wood` | Metal and dark wood |
| Bar corner | 2 x `kitchenBar` at right angles (guest sides -Z and +X), overlapping in the corner | `wood` | Metal and dark wood |
| Coffee machine | `kitchenCabinet` + `kitchenCoffeeMachine` on top | `wood` | The whole machine |
| Drinks fridge | `kitchenFridgeSmall` | none (unpaintable) | All |
| Drinks shelf | `bookcaseOpenLow` + Food Kit `wine-red`, `wine-white`, `soda-bottle` | `wood` | Every bottle |
| Storage shelf (FK-087) | `bookcaseOpen` + Food Kit `barrel`, `loaf`, `carton`, `bag`, `can` on its shelves and 2 x Furniture Kit `cardboardBoxClosed` on top; parts tagged `metadata/stock_slot` 0-10 show in proportion to how full dry storage is | `wood` | Every crate, box and food piece |

Existing `ItemDef.paintable` values are unchanged: the stove, sink and door
remain unpaintable. Their mappings document the wrapper contract, rather than
enabling an additional gameplay command. The rectangular `table` is the current
source choice for the two-seat table: its long side fills the two-cell width
without enlarging it. The director accepted that table and the existing door
dimensions in [PR #131's review](https://github.com/jaredbahr/foolskitchen/pull/131#issuecomment-6389082368).

The two-seat table includes a `chairCushion` at each authored `seat_cells` entry,
(-1, 1) and (2, 1). Their direct parts declare `metadata/seat_cell`, sit at those
cell centres, and turn toward the table centre. Each `Art` child still gets the
shared furniture scale and the kit's 180-degree facing correction. The table
body stays inside its footprint; each chair fits its own declared seat cell
with the same 0.05 tolerance. Combined bounds include both chairs for picking,
selection and build ghosts. This changes no simulation footprint or seat data.

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

## Validation status and remaining chair gates

The director merged current main into PR #131 and committed seven actual Godot
script UIDs. At `cdcf048fbd563a6a4ac456bc716c69a21fc33829`, the normal cloud check
parsed 224 scripts and passed 736 tests with no failures. Default, open-shop and
paint captures were reviewed: the kitchen, shared furniture scale, body paint,
rectangular table and existing door proportions were accepted. The accepted
door leaf remains about 0.47 by 1.08, within the director's stated tolerance.
Those results precede the two built-in chairs added here.

The chair change has source review and focused assertions for declared seat
centres, all four placement rotations, shared scale, floor alignment, per-seat
fit, combined bounds and body-only paint/preview restoration. These new chair
checks have not run. The remaining gates are the normal cloud import and
`bash tools/check.sh` on the updated PR, followed by the existing open-shop
capture and the director's review of the actual chairs. No local engine, test
or render result is claimed for this change.

This checkout is a source preparation branch with local proxy ancestry. Never
push that ancestry; publish only the reviewed changed-file overlay on official
PR history, preserving the director's main merge and generated UIDs.
