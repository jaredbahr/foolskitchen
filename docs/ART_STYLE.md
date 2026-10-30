# Art style lock

**Status: locked (Jared, 2026-10-24, D19 and D20).** Consistency beats detail. Everything on screen must look like it came from one hand. If something you need is not in the kits, it may be **made in the Kenney style** (§8), but never taken from another source or style.

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

**The building is scaled to the people (Jared).** The Mini Characters set the scale for everything built around them. A person is about 0.74 high and 0.37 wide.
- **Walls:** 1.4 high (about 1.9 people).
- **Door openings:** at least 1.1 high and 0.5 wide.
- **Aisles and walk paths:** at least one cell (0.5) wide, which fits one person comfortably.
- **Counters:** about 0.5 high, around the chest of a Mini Character, as in the kits.
- **Table tops:** about 0.36 high; a seated guest's arms rest on the table.
- **Chair seats:** about 0.27 high, matching the `sit` pose raised onto the seat.

**Seats with lowered backrests (Jared, 2026-10-28).** Mini Characters have big heads, and a seated guest's head sat inside the kit chairs' backrests. Guests are not leaned forward ("looks pretty rough"); instead every kit seat a guest sits in uses a derived copy with a lower backrest, in `assets/props/seats/derived/`. `tools/derive_seat_backrests.py` makes them from the unchanged kit files: it squashes only the heights above the seat top (to 52–58% of the kit's backrest height; the lounge chair's arms come down with its back), so the seat, legs, plan shape, materials and UVs stay the kit's and each seat still reads as the same piece. This is the one approved exception to "uniform scale only". A new seat must clear seated heads on its own (`tools/seated_head_probe.gd`, no exceptions); if a kit seat needs a lower back, add it to the tool's table rather than editing any file by hand.

Any new building piece (walls, windows, doors, the awning, counters) follows these numbers. Every visual PR shows at least one capture with people standing beside the furniture, so the fit can be checked.

## 3. Colour and materials
- Keep each kit's own materials and its shared `colormap.png`. No per-model textures, no new materials on kit models, and no vertex-colour edits.
- **Paint (#94):** the swatch tints only the model's main body surface (for example a table top and legs, a chair frame). Pick the surface by its material name in the item's wrapper scene. Chrome, glass, food and faces are never painted.
- **Floors (D25):** floor types are drawn by the floor shader (`floor_finish.gdshader`) as flat patterns in palette swatch colours, with no textures; the light comes from the scene, and the only extra marks are seams, grout and a thin darker line where two floor types meet. Catalogue cards draw the same patterns on the CPU (`FloorThumbnail`).
- **Wall finishes (D26):** wall finishes are drawn by the wall finish shader (`wall_finish.gdshader`) on a thin facing just off each finished wall face, as flat patterns in palette swatch colours with no textures, lit like the plain walls; the only extra marks are boards, grout and mortar lines. Catalogue cards draw the same patterns on the CPU (`WallThumbnail`). Wall decor uses the made diner wall pieces (`assets/made/diner/`) through their wrapper scenes; the neon sign keeps its approved emissive red and adds no light.
- Placeholder colours and new UI colours come from the existing palette (`main_theme.tres`, the swatch list). No one-off hex values.
- **Exception, glowing parts (Jared, 2026-10-26):** neon tubes, sign letters and lamp glow may use a dedicated emissive colour when no kit colour reads correctly (the kit's only red is a salmon). Define each one once as a named constant in the asset's build script, never inline. Non-glowing surfaces still use kit colours.

## 4. People
- Every person is a Mini Character. **Roles:**
  - **Cook:** `character-male-b` or `character-female-b`, plus a chef-hat piece. The hat is built from Furniture or Food Kit shapes in white, or from a simple primitive in the kit's flat style. Add nothing more than the hat.
  - **Server:** the kit model with a dark top (choose one and keep it).
  - **Owner (FK-111):** the player's choice of the 12 unmodified Mini Characters;
    older shops and tools retain `character-male-a`. The existing owner-selection
    ring keeps an inspected owner recognisable. No new character art or uniform.
  - **Guests:** the remaining models, chosen deterministically from the guest id.
  - **Delivery driver (FK-099):** `character-female-b`, the one model no other role uses (cooks use `character-male-b`), in a delivery uniform no other role wears: a parcel-brown (`#9a6a3e`) cap with an amber (`#d98e2b`) peak, built from primitives in the kit's flat style like the chef hat, and her clothes repainted brown with amber sleeves. The repaint is a private copy of the kit colormap made when she loads; the vendored texture is never edited. Delivery crates are the Furniture Kit's `cardboardBoxClosed` at 0.65 of the furniture scale, one at a time in anyone's hands (its top under the chin), stacked at most as high as a standing person's chin. The **Freezer** is the kit's `kitchenFridgeLarge` with its metal tinted cool (slate blue mixed in, `PropView.rest_tint`) so it never reads as the tall fridge.
- **Clips (kit names; the same for every model):**
  - `idle`, `walk`, `sit` (raise the body onto the chair seat), `holding-both` (carrying a plate or tray), `interact-right` (working a station), `pick-up`.
  - `carry-walk` is not a new clip: the game builds it from the kit's `walk` with the arms of `holding-both`, so someone carrying walks instead of gliding.
  - Don't use the combat, die or wheelchair clips. Wheelchairs and aids may be added later for guest variety, as a director decision.
- People face their walking direction. When people stand closer than 0.45 apart, the view nudges them apart (display only).

## 5. Food
- Recipes map to a Food Kit model:
  - **Burger:** `burger-cheese` (or `burger`)
  - **Tomato soup:** `bowl-soup`
  - **Grilled cheese and Tomato melt:** `sandwich`
  - **Croissant:** `croissant`. Drinks, when shown: **Coffee** `cup-coffee`, **Tea** `cup-tea`, **Soft drink** `soda-glass`, **Beer** `glass`, **Wine** `glass-wine` (FK-083)
  - **Fries:** `fries`; **Savoury pie:** `pie` (FK-081).
- Every served dish sits on `plate` (or `plate-dinner`).
- A dirty plate is `plate` plus a small smear piece from the same kit, or `plate` alone tinted darker. No new models.

## 6. Lighting
- Lighting is engine-only and lives in one rig: a warm key light from the upper left, a soft cool fill, warm ambient light. Assets never bake light.
- Lamps use Furniture Kit lamps (`lampRoundFloor`, `lampSquareTable`, `lampWall`) and follow the #84 light cap.

## 7. UI
- **Icons:** `assets/kenney/icons/`, tinted with theme colours, at one size per context (top bar 28 px, panels 24 px).
- **Text:** stays on the current font and theme.
- **Missing icons:** there is no chef-hat or paint-brush icon in the pack. Make them in the Game Icons style (§8), or use text until one exists.

## 8. Making new items in the Kenney style
New stoves, cooking gear, decor, building pieces or icons may be made when the kits lack them (Jared). **Designing the space is a core part of the fun** (walls, layouts, tables and chairs, restaurant styles and vibes), so making assets for variety is encouraged. **The player decides the look (D22)**: prefer several variants of a piece (other kit material colours, wood vs. painted, plain vs. trimmed) over one "right" version, so every theme can be built more than one way. Reviews check Kenney-style consistency, not taste. A made item must be indistinguishable in style from the kits:
- **3D:** built in Blender (headless, scripted is fine) from the same kind of shapes as the kit:
  - chunky, slightly bevelled boxes and cylinders, flat-shaded, low poly (under about 1,500 tris for furniture, 300 for small props);
  - coloured only through the kit's own `colormap.png` UVs or the kit's existing material colours. No new textures.
  - Same proportions and edge softness as the nearest kit piece. Put it next to that piece in a capture to prove it.
- **Icons:** the Game Icons style: white, solid, rounded silhouette, 100 px, same stroke weight.
- **Location:** made assets live in `assets/made/` (never inside `assets/kenney/`), and each is listed in `assets/made/README.md` with what it is and what it was based on.
- **Approval:** each made item needs an issue that names it. The director checks it side by side with the kit before it merges.

## 9. Review gate
Every visual PR includes before and after captures from `tools/screenshot.sh`, and the director checks the pixels against this file. If a PR breaks a rule here, it is sent back, however good it looks.
