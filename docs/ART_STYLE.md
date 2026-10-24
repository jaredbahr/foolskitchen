# Art style lock

**Status: locked (Jared, 2026-10-24, D19 and D20).** Consistency beats detail. Everything on screen must look like it came from one hand. If something you need is not covered here, stop and ask in the PR; never substitute an asset from another source or style.

## 1. Approved sources (all Kenney, CC0)
All of them are already in the repo; never download others.

| Use | Kit | Path |
|---|---|---|
| Furniture, kitchen equipment, lamps, decor, doors, walls | Kenney Furniture Kit 2.0 | `assets/kenney/furniture/` |
| Food, plates, bowls, pots, kitchen tools | Kenney Food Kit | `assets/kenney/food/` |
| People (staff, owner, guests) | Kenney Mini Characters | `assets/kenney/characters/` |
| UI icons | Kenney Game Icons (white, 100 px) | `assets/kenney/icons/` |

- Licences: the `License.txt` in each folder. Kenney is credited in `CREDITS.md`.
- Out: the UI Pack panels (their colours clash with our theme). UI panels, buttons and fonts stay in the existing warm theme (`main_theme.tres`). Icons are tinted with theme colours.

## 2. Scale and placement (view only; the sim grid never changes)
One grid cell is 0.5 units. Uniform scale only: never stretch or squash a model on one axis.

| Group | Scale | Result |
|---|---|---|
| Furniture Kit | **×1.1** | a kitchen module is about one cell deep (0.5); a chair seat is about 0.27 high |
| Mini Characters | **×1.1** (same as furniture) | a person is about 0.74 high; kit proportions are kept |
| Food Kit | **×0.22** (tuning range 0.18–0.26, set once in one constant) | a dinner plate is about 0.2 wide on a 0.92 table |
| Walls (our own, painted) | height **1.4** | about Kenney's wall (1.29) × 1.1 |

- **Origin:** Furniture Kit models have their origin at a back corner. Centre each one on its item footprint, on the floor (y = 0).
- **Facing:** an item's front faces the item's facing in the sim. Kenney models face the opposite way from us, so turn them 180° in the wrapper scene, never in the source file.
- **Filling a footprint:** if one model is smaller than the footprint, combine pieces **from the same kit** (for example stove + cabinet for a 2×1 stove). Never scale a piece up to fill the space.
- **Fit:** a model may not stick out of its footprint by more than 0.05.
- All the scale constants live in one script, `src/world/art_scale.gd`. No other file hard-codes a scale.

## 3. Colour and materials
- Keep each kit's own materials and its shared `colormap.png`. No per-model textures, no new materials on kit models, and no vertex-colour edits.
- **Paint (#94):** the swatch tints only the model's main body surface (for example a table top and legs, a chair frame). Pick the surface by its material name in the item's wrapper scene. Chrome, glass, food and faces are never painted.
- Placeholder colours and new UI colours come from the existing palette (`main_theme.tres`, the swatch list). No one-off hex values.

## 4. People
- Every person is a Mini Character. **Roles:**
  - **Cook:** `character-male-b` or `character-female-b`, plus a chef-hat piece. The hat is built from Furniture or Food Kit shapes in white, or from a simple primitive in the kit's flat style. Add nothing more than the hat.
  - **Server:** the kit model with a dark top (choose one and keep it).
  - **Owner:** one fixed model (D14).
  - **Guests:** the remaining models, chosen deterministically from the guest id.
- **Clips (kit names; the same for every model):**
  - `idle`, `walk`, `sit` (raise the body onto the chair seat), `holding-both` (carrying a plate or tray), `interact-right` (working a station), `pick-up`.
  - Don't use the combat, die or wheelchair clips. Wheelchairs and aids may be added later for guest variety, as a director decision.
- People face their walking direction. When people stand closer than 0.45 apart, the view nudges them apart (display only).

## 5. Food
- Recipes map to a Food Kit model:
  - **Burger:** `burger-cheese` (or `burger`)
  - **Tomato soup:** `bowl-soup`
  - **Grilled cheese and Tomato melt:** `sandwich`
- Every served dish sits on `plate` (or `plate-dinner`).
- A dirty plate is `plate` plus a small smear piece from the same kit, or `plate` alone tinted darker. No new models.

## 6. Lighting
- Lighting is engine-only and lives in one rig: a warm key light from the upper left, a soft cool fill, warm ambient light. Assets never bake light.
- Lamps use Furniture Kit lamps (`lampRoundFloor`, `lampSquareTable`, `lampWall`) and follow the #84 light cap.

## 7. UI
- **Icons:** `assets/kenney/icons/`, tinted with theme colours, at one size per context (top bar 28 px, panels 24 px).
- **Text:** stays on the current font and theme.
- **Missing icons:** there is no chef-hat or paint-brush icon in the pack. Use text labels for those until the director adds an approved icon. Never draw or import a substitute.

## 8. Review gate
Every visual PR includes before and after captures from `tools/screenshot.sh`, and the director checks the pixels against this file. If a PR breaks a rule here, it is sent back, however good it looks.
