# Made assets

These assets are made for the named issues and follow `docs/ART_STYLE.md` §8. They do not modify the Kenney source kits.

## Icons (#118)
The two named icons fill gaps in the approved Kenney Game Icons pack. Their white, filled silhouettes use the pack's broad 18–20 px transparent margins and rounded corners; they add no outlines, gradients or fine details.

| Asset | Issue | Style reference |
|---|---|---|
| `icons/chefHat.svg` and `icons/chefHat.png` | #118 | Kenney Game Icons `home.png`, `star.png` and `gear.png`: a broad, rounded crown and a solid hat band, with the same white fill and transparent margins. |
| `icons/paintBrush.svg` and `icons/paintBrush.png` | #118 | Kenney Game Icons `wrench.png`, `home.png` and `gear.png`: a thick diagonal handle, broad brush head and rounded ends, with no outlines or gradients. |

The SVG files are the hand-authored editable sources; the 100 × 100 transparent PNG files are their Inkscape raster exports. To export either source again, run `inkscape assets/made/icons/<name>.svg --export-filename=assets/made/icons/<name>.png --export-width=100 --export-height=100`. The source comments record the four reference bounds and filled areas. The files use no art from another source and leave the Kenney kit unchanged.

## Diner booth (#147)
The white booth pairs the Kenney Furniture Kit `benchCushion` seat cushion and `loungeSofa` backrest proportions.
The Director-approved tall variant occupies two by two grid cells: two front seats and a blocking rear backrest row. Its seat height and supported guest offset stay unchanged; final posed-head clearance is checked against the exported geometry.

## Diner counter stool (#147)
The red stool is based on `stoolBar` proportions, with `lampWall` as the metal pedestal reference.

## Diner OPEN sign (#147)
The wall sign pairs the `lampWall` mounting shape with the Furniture Kit `wall` panel proportions. Its tube strokes use the approved dedicated neon red: linear albedo (0.70, 0.015, 0.02) and linear emission (0.35, 0.0075, 0.01). The housing and brackets retain their Furniture Kit colours; the sign adds no light component.

## Diner chalkboard (#147)
The blank board and wood frame use `wallWindow` and `paneling` as the nearest wall-frame references; game text is added in the scene.

## Diner wall art A (#147)
The framed sunrise uses the `wallWindow` frame and `paneling` proportions as references.

## Diner wall art B (#147)
The framed geometric peaks use the `wallWindow` frame and `paneling` proportions as references.

## Restroom hand dryer (#198 / #217)
`restroom/wall_hand_dryer.glb` is the Director-approved small rounded box with
a short downward nozzle and front sensor, not a towel dispenser or cabinet.
Its cream housing uses `bathroomCabinetDrawer`'s unchanged `carpetWhite` colour;
the darker nozzle/sensor use `wall`'s `metalDark`. Edge softness follows the
Furniture Kit bathroom cabinet and wall lamp. No textures or baked lighting.
Rebuild with `blender --background --factory-startup --python tools/build_hand_dryer.py`.
The source envelope is approximately 0.30 × 0.25 × 0.15 m; its wrapper uses
the shared uniform furniture scale and aligns its bottom with the mirror at
0.6 m above the floor, fitting the game's person scale.

## Neighbourhood (#242)

Each piece is rebuilt by `tools/build_neighbourhood.py`; dimensions and usage are in `neighbourhood/README.md`. The generator copies existing Furniture Kit PBR colours exactly and creates no textures, lights or emission.

| Asset | Named use and approved style reference |
|---|---|
| `neighbourhood/road_segment.glb` | Two-lane road slab based on `floorHalf` thickness, `wall` metalDark and cabinet carpetWhite lane marks. |
| `neighbourhood/crossing_segment.glb` | Replacement road segment with broad crossing marks in the same kit colours. |
| `neighbourhood/kerb_segment.glb` | Slightly bevelled kerb following `floorHalf` edges and `lampRoundFloor` metal. |
| `neighbourhood/shopfront.glb` | Simple shop front using `wall`, `wallWindow` and `doorwayFront` proportions and materials. |
| `neighbourhood/house_body.glb` | House box with alternate door/window arrangement in the same kit cream/wood/glass colours. |
| `neighbourhood/gable_roof.glb` | Chunky roof prism in `bathroomCabinet` woodDark, reusable on either building body. |
| `neighbourhood/compact_car.glb` | Authored bevelled body/cabin and twelve-sided wheels, using `chairModernCushion` carpetBlue and existing metalDark/glass/cream colours; no substituted furniture model. |
| `neighbourhood/street_lamp.glb` | Authored street post following the kit floor/wall lamp materials and soft box edges; unlit until the separate night feature. |

## Street-front decor (#240)

These eight pieces use the Furniture Kit's unchanged material colours and flat,
slightly bevelled shapes. Each width is authored as real geometry, with the
shared uniform furniture scale applied by its wrapper. No textures, baked light,
or light nodes are included. Prices and unlock levels live in `data/items/`.

| Asset under `street_front/` | Kit reference | Triangles | Materials |
|---|---|---:|---|
| `street_awning_2.glb` | `wallWindow` frame and `benchCushion` cloth | 308 | `carpet`, `carpetWhite`, `metalDark` |
| `street_awning_3.glb` | `wallWindow` frame and `benchCushion` cloth | 356 | `carpet`, `carpetWhite`, `metalDark` |
| `street_awning_4.glb` | `wallWindow` frame and `benchCushion` cloth | 404 | `carpet`, `carpetWhite`, `metalDark` |
| `flower_window_box.glb` | `pottedPlant` planter, foliage and chunky silhouette | 218 | `wood`, `woodDark`, `plant`, `carpetWhite`, `carpet`, `lamp` |
| `shop_name_sign.glb` | `wallWindow` frame and `bathroomCabinetDrawer` cream panel | 56 | `woodDark`, `carpetWhite` |
| `string_lights_2.glb` | `lampWall` warm bulbs, dark mounts and simple silhouette | 180 | `metalDark`, `lamp` |
| `string_lights_3.glb` | `lampWall` warm bulbs, dark mounts and simple silhouette | 216 | `metalDark`, `lamp` |
| `string_lights_4.glb` | `lampWall` warm bulbs, dark mounts and simple silhouette | 252 | `metalDark`, `lamp` |

At the shared scale, awnings are 0.95/1.45/1.95 m wide, 0.15 m high and 0.43 m
deep. Their bottoms clear the 1.10 m door opening and their tops sit at 1.25 m,
above the 0.74 m people and 0.02 m below the sign band.
Only the named `carpet` cloth surface accepts paint; white stripes and brackets
retain their kit materials. The flower box is 0.44 × 0.22 × 0.20 m and fits under
the actual window sill. Its flowers reuse the kit's cream, cloth red and lamp
yellow, with no new colour source.

The blank sign is 0.94 × 0.12 × 0.056 m, mounted from 1.27 m. The game adds the
live restaurant name using its existing font. String lights are approximately
0.968/1.468/1.968 m wide, 0.096 m high and 0.033 m deep; their `ItemDef.glow_color`
is the exact warm `lampWall` colour. Mount heights, sign text geometry and light
outset are centralized in `ArtScale`.

Rebuild all eight with
`blender --background --factory-startup --python tools/build_street_front.py`.
The optional `-- --manifest /outside/project/manifest.json` writes measured
bounds, triangle counts, material names and hashes outside the shipping project.

## Weather icons (#241)

`icons/weather_sunny.svg`, `icons/weather_cloudy.svg` and
`icons/weather_rain.svg` are the editable sources for the three matching
100 × 100 PNG exports. They use white solid rounded silhouettes on transparent
backgrounds, with the same approximately 64 px visual width and broad margins
as the approved Kenney Game Icons. The sunny disc and rounded rays reference
`gear.png` and `star.png`; the solid cloud and rounded rain strokes reference
`home.png`'s filled silhouette and `audioOn.png`'s rounded marks. No outside
art source, font, texture, gradient or outline is used. Runtime tint belongs to
the existing UI theme through `IconCatalogue`; SVGs are source files and the
catalogue aliases use only the PNG exports.

Rebuild with `python3 tools/build_weather_icons.py` (Pillow, already available
in the development environment). The generator shares one set of primitive
coordinates between SVG and supersampled PNG output. It never edits the
vendored kit or another made asset. Optional `--manifest /outside/project.json`
writes audit data outside the shipping project; review comparisons are never
stored with the assets.

## Restaurant cat (#119)
`cat/cat.glb` is the shop cat: a light grey-orange tabby in the Mini Characters' flat, chunky style (slightly bevelled boxes, flat shading, big head, 672 triangles against an 800 budget). Its colours come only from the characters kit's `colormap.png` (every face's UVs point at one palette swatch, like the people); the GLB references that file by relative path and nothing is copied. Proportions follow the Mini Characters' big head and short limbs; at `ArtScale.CAT_SCALE` it stands about two thirds of a person's height. Ten rigid-skinned bones and three looping clips: `idle` (2 s), `walk` (1 s) and `nap` (3 s, curled up with the head tucked and the tail wrapped round). Origin at the feet, facing -Z. Measured numbers are in `cat/cat.metrics.json`.
Rebuild with `blender --background --factory-startup --python tools/build_cat.py` (Blender 4.2; it rewrites the GLB and the metrics file). Review capture: `tools/cat_review.tscn` (cat beside a Mini Character, walking and napping).

## Kitchen ambience loops (#117)
The Kenney audio packs have no kitchen ambience, so `audio/stove_sizzle.ogg`, `audio/fryer_bubble.ogg`, `audio/coffee_steam.ogg` and `audio/room_tone.ogg` are made from seeded, frequency-shaped noise with short crackles and bubbles. Each is shaped over its whole length, so it loops without a seam. No recorded or third-party audio is used. Rebuild with `python3 tools/make_kitchen_audio.py` (numpy and ffmpeg); the output is deterministic.

## Jukebox (#294)
`props/jukebox.tscn` is the Jukebox, composed in the scene rather than imported from a model file: a Furniture Kit `kitchenCabinetUpper` stretched into the floor-standing cabinet, topped by a made head of three flat-shaded primitives (a box, a 16-sided half-round arch and a window with a thin silver frame) and three dark grille bars, about 1 m tall at the shared furniture scale in a one-cell footprint. Every colour is a Furniture Kit material (`wood`, `metal`, `metalLight`, `metalDark`) copied exactly, with the kit's names so the three music-style looks recolour its `wood` like any other look; no textures, outlines or baked light. The kit's radio and speakers were tried first and read as a radio on a cabinet, not a jukebox, so the arch and window are made (this is the one made piece; no Blender file is involved).

## Jukebox music loops (#294)
`audio/jukebox_diner_rock.ogg` (19 s), `audio/jukebox_cafe_jazz.ogg` (20 s) and `audio/jukebox_bar_blues.ogg` (24 s) are short synthesised loops, one per music style: a boogie-bass 12-bar blues in A with chopped guitar and a backbeat; a ii-V-I turnaround in C with walking bass, soft electric piano and brushes; and a slow 12-bar shuffle in E with a thin organ and a few guitar licks. `tools/make_jukebox_music.py` writes every note and drum hit out by hand (bass, plucks, electric piano, organ and drums are sums of sine partials and a little fixed-seed noise), rolls the top off for a small-speaker sound and wraps whatever rings past the last bar to the first, so each repeats without a seam. Mono, 22.05 kHz, about 70-90 KB each; the game plays them quietly on the Effects bus. No recorded or third-party audio is used. Rebuild with `python3 tools/make_jukebox_music.py` (numpy and ffmpeg); the output is deterministic.

## Aquarium (#125)
Two planted fish tanks on their own cabinets and four tiny fish, all rebuilt by
`tools/build_aquarium.py` (Blender, or the `bpy` module: `python tools/build_aquarium.py`),
which also writes `aquarium/aquarium.metrics.json` (triangles, sizes and each
tank's swim box). Deterministic: no random draws. No textures, light nodes or baked light.

| Asset under `aquarium/` | Kit reference | Triangles | World size (w × h × d) |
|---|---|---:|---|
| `aquarium_2.glb` (Aquarium, 2×1) | `kitchenCabinet` / `sideTable` (cabinet, doors and handles), `plantSmall1-3` (leaf tiers) | 1214 | 0.97 × 0.63 × 0.47 |
| `aquarium_3.glb` (Large aquarium, 3×1) | the same kit, longer, three doors | 1468 | 1.47 × 0.63 × 0.47 |
| `fish_neon.glb`, `fish_orange.glb`, `fish_yellow.glb`, `fish_guppy.glb` | Food Kit colormap colours; simple made fish (`fish.glb` is 233 triangles and reads as food, not a live fish) | 80 each | about 0.10 long |

- **Cabinet:** a `woodDark` body and top with lighter `wood` doors and `metal`
  handles, the kit cabinet's proportions; `woodDark` is the paintable body.
- **Tank:** `metalDark` base, rim and slim corner posts; a `metalDark`
  background inside the back glass; a `metalDark` light bar on two feet.
- **Inside:** a faceted bed sloping up to the back (`metalDark`), two pale
  stones (`metal`), stem plants built from stacked four-sided leaf tiers like
  `plantSmall`, a sword plant and low carpet tufts (all kit `plant` green).
- **Approved new material (the issue's one):** `aquariumGlass`, a clear,
  slightly blue glass (linear 0.55, 0.80, 1.0, alpha 0.2).
- **Glowing part (ART_STYLE §3):** `aquariumGlow`, the soft blue-green of the
  lit water surface and the light's strip (linear 0.04, 0.45, 0.50; emissive).
  The wrapper draws the water unlit at 22% over what lies beneath, so it reads
  blue-green by day and glows at night without any light.
- **Fish:** a six-sided faceted lens body, a forked tail fan (bigger on the
  guppy), a dorsal fin and eyes; every face's UVs point at one Food Kit
  `colormap.png` swatch (neon blue, red and white; orange; yellow; purple with
  a pink tail). The GLBs reference that file by relative path; nothing is copied.
  Origin at the centre of the whole fish, facing -Z.

## Walk-up hatch, seaside treats and evening dress kit (#589)

Models only: nothing is buildable yet (D38; Codex wires them later). Rebuild
everything with `blender --background --factory-startup --python tools/build_walkup.py`
(Blender 4.2), which also writes `walkup/walkup.metrics.json` (triangles, world
sizes, materials and node names). Deterministic, no textures, lights or
emission. The furniture-scale pieces copy unchanged Furniture Kit material
colours by name and are authored at world size ÷ `ArtScale.FURNITURE_SCALE`; the
two dish pieces are coloured only through the Food Kit `colormap.png` (one
swatch per face, referenced by relative path, never copied) and are authored at
world size ÷ `ArtScale.FOOD_SCALE`. Origin at the base centre, facing -Z.
Review capture: `tools/walkup_models_review.tscn` (each piece beside its kit
reference, the hatch open and closed in a shell wall run, tables dressed for
the evening by day and night).

| Asset under `assets/made/` | Nearest kit pieces and approved style reference | Triangles | World size (w × h × d, m) |
|---|---|---:|---|
| `walkup/walkup_hatch_wood.glb` | `wallWindow` / `wallDoorway` frame proportions, `kitchenBar` top; plank awning in `wood`/`woodDark` | 1296 | 0.56 × 1.40 × 0.84 |
| `walkup/walkup_hatch_painted.glb` | the same, cream (`carpetWhite`) frame, plain `carpet` cloth awning | 1284 | 0.56 × 1.40 × 0.84 |
| `walkup/walkup_hatch_seaside.glb` | the same, `carpetBlue`/`carpetWhite` striped awning (as the #240 awnings) | 1388 | 0.56 × 1.40 × 0.84 |
| `walkup/soft_serve_machine.glb` | `kitchenCoffeeMachine` (sits on a `kitchenCabinet` like it), `kitchenBlender` | 836 | 0.36 × 0.34 × 0.32 |
| `walkup/shaved_ice_cart.glb` | `kitchenBar` counter height and `kitchenCabinet` panels; parasol in the awning stripes | 952 | 0.91 × 1.15 × 0.53 |
| `walkup/tablecloth_rect.glb` | `tableCloth` cloth; fits `table` (also `tableGlass`, `tableCross`) | 176 | 0.97 × 0.15 × 0.53 |
| `walkup/tablecloth_round.glb` | fits the six-sided `tableRound` | 44 | 0.85 × 0.15 × 0.99 |
| `walkup/candle_holder.glb` | `lampRoundTable` / `lampSquareTable` | 132 | 0.08 × 0.18 × 0.08 |
| `walkup/small_vase.glb` | `plantSmall1` (and the #240 flower box flowers) | 256 | 0.09 × 0.23 × 0.09 |
| `walkup/shaved_ice_topping.glb` | Food Kit `ice-cream-cup` (it sits in that cup) | 98 | 0.06 × 0.06 × 0.06 |
| `walkup/fries_cone.glb` | Food Kit `fries` and `ice-cream-cne` | 200 | 0.08 × 0.15 × 0.08 |

- **Walk-up hatch.** One shell wall cell (0.5 × 1.4 × 0.5 m) with a 0.40 m
  wide serving opening from the 0.50 m ledge to 1.02 m. Front (-Z) is the
  street. Named nodes: `WallBody` (the wall round the opening in the kit
  wall's `_defaultMat`, to take the shop's wall material or to hide where the
  shell draws its own), `LedgeSill`, `LedgeOuter` (the customer's ledge, on two
  brackets), `LedgeInner` (the staff ledge), `Frame`, `ShutterHousing`,
  `ShutterOpen` (rolled up: only the bottom bar shows) and `ShutterClosed`
  (slats down to the ledge), `Awning` (bottom 1.12 m, top 1.27 m, the #240
  canopy band) and `MenuBoard` (blank-lined board under the outer ledge). Show
  exactly one of `ShutterOpen` / `ShutterClosed`. The empties `InnerLedgeTop`
  and `OuterLedgeTop` mark the two ledge tops at 0.50 m, 0.305 m inside and
  0.31 m outside the cell centre.
- **Soft-serve machine.** A counter appliance for the top of a
  `kitchenCabinet`, like `coffee_machine.tscn` (0.495 m up). Its three pull
  handles carry vanilla, chocolate and strawberry knobs (`carpetWhite`,
  `woodDark`, `carpet`); the two warm lamps use the kit `lamp` colour only.
- **Shaved-ice cart.** Two cells (1.0 × 0.5 m): counter 0.47 m high, two
  wheels, a push handle, an ice shaver with a `glass` hopper, four syrups
  (`carpet`, `carpetBlue`, `lamp`, `plant`) and paper cups, under a
  blue-and-white parasol that stays inside the footprint.
- **Tablecloths.** Overlays for existing tables, not new tables: their origin is
  the table's own base centre (they keep the cloth at the table top, 0.36 m for
  `table`, 0.40 m for `tableRound`), so they take the table's position and
  turn. `tablecloth_rect` has a separate `Runner` node in the kit's cloth red.
- **Candle holder and small vase.** Small props for a table top; the candle's
  flame uses the kit `lamp` colour (a glowing part, ART_STYLE §3), behind a kit
  `glass` chimney; the vase is `carpetBlue` with three kit-coloured flowers.
- **Dishes** (Food Kit pieces wherever they exist, composed in
  `assets/props/`): the strawberry cone is the kit's own `ice-cream`;
  `ice_cream_cone_chocolate.tscn` and `ice_cream_cone_mint.tscn` seat the kit's
  scoops on its `ice-cream-cne`; `shaved_ice.tscn` puts the made topping in the
  kit `ice-cream-cup`; the paper cone of fries is `walkup/fries_cone.glb`. The
  sundae is #558's `ice_cream_sundae.tscn` (kit cup and chocolate scoop).

## UI control icons (#498)
`ui/*.png` (switch on/off, slider handle, dropdown arrow, menu radio dots) are drawn by `tools/make_ui_controls.py` in the theme palette: rounded, outlined in the ink colour, no gradients. Re-run the script to regenerate.

## Seaside beach (#588)

No kit has beach pieces, so these are made in the Kenney style, the same way as the
street's other code-built scenery (trees, hedges, street furniture, birds): chunky,
flat-shaded, vertex-coloured meshes built in `src/world/neighbourhood_shore.gd` from
boxes, six- and eight-sided posts and low-poly lumps. They are not files under
`assets/made/`: no textures, no imported models. Colours come from the street's
`ShoreSkin` in `data/streets/seaside.tres`, drawn from the shared swatches (Oat, Cream,
Birch, Sand, Milk, Coral, Tomato, Sunflower, Teal, Navy, Pewter) and the seaside
street's own blues; the sea's blues are the seaside accent colours D32 allows. People
on the beach are unchanged Mini Characters.

| Piece | Based on | Triangles |
|---|---|---:|
| Beach umbrella with its towel (open: eight striped panels and a valance on a pole; furled from dusk) | the street's awning stripes, `lampRoundFloor` pole, a flat `rugRectangle`-like slab | 66 open, 16 furled |
| Beach ball (six coloured wedges) | the street furniture's lumps, at toy size | 36 |
| Sandcastle with towers, flag, bucket and spade | stacked kit-style boxes and six-sided posts | about 280 |
| Lifeguard hut on stilts, ramp and flag | `wall` and `doorwayFront` proportions, street-front awning colours | 100 |
| Plank path with rope posts | the boardwalk's plank pitch, `lampRoundFloor` posts | 236 |
| Dunes and marram grass | the ground's lumps and the hedges' shapes, in sand | 12 a dune, 5 a tuft |
| Lighthouse on its rocks (lamp glows at night, beam sweeps) | eight-sided banded tower, kit lamp glow | 356 |
| Sailboat (hull, deck, mast, main and jib, mast lamp) | `compact_car`'s bevelled body proportions | about 40 |
| Gull (body, beak, two flapping wings) | the street's birds (#423) | about 45 |

The sea is one shader (`src/world/sea.gdshader`): flat bands of colour, a foam edge,
rolling crests and glints, driven by the street's display clock.

## Seaside promenade and beach-shop terrace (#596)

Code-built like the beach (#588) and the rest of the street: chunky, flat-shaded,
vertex-coloured meshes from boxes, discs, six- and eight-sided drums and low-poly
lumps, with no textures, imported models or lights. Not files under `assets/made/`.
Colours come from `data/streets/promenade.tres` (its `PromenadeSkin`, `StreetSet`
and the terrace's `ShopStyle`s), drawn from the shared swatches (Milk, Cream, Oat,
Birch, Mint, Blush, Peach, Powder blue, Lilac, Coral, Tomato, Teal, Sky, Navy,
Sunflower, Berry, Brass, Honey, Walnut, Dusty rose) and the seaside street's blues.
The painted names are `Label3D`s in the game's theme font. The arcade's bulbs and
screens join the street's lit-window glow; nothing adds a light.

| Piece | Built in | Based on |
|---|---|---|
| Promenade paving pattern: slab joints, centre band with its edging and an inlaid wave | `neighbourhood_promenade.gd` | the boardwalk's plank seams (#588), flat on the kit `floorHalf` paving |
| Double-lantern lamp post (bulbs, pools of light and halos as the street lamps) | `neighbourhood_promenade.gd` | `street_lamp.glb`'s height and glow (#423), the kit's soft box edges |
| Bicycle, pram, and a trotting dog on a lead | `neighbourhood_promenade.gd`, `neighbourhood_dressing.gd` | the street's birds and furniture lumps, at person scale |
| Seaside planter, ice-cream tricycle, cast-iron bollard | `neighbourhood_furniture.gd` | the street furniture (#423): bench, bin and bollard proportions, the awnings' stripes |
| Terrace shop (Surf Hire, Bucket & Spade): surfboards and wetsuits, a bucket stand, beach balls and a rubber ring | `neighbourhood_buildings.gd`, `neighbourhood_terrace.gd` | the neighbour shops (#422): same body, awning, sign board and window |
| Fish-and-chip kiosk: serving hatch, counter, tall fascia, chip cones and an A-board | `neighbourhood_terrace.gd` | the shop front's door, window and awning parts |
| Beach hut: boards, double doors, gable window, deck and a striped deckchair | `neighbourhood_terrace.gd` | the houses' front gable and the shop door (#422) |
| Arcade front: open front with glowing cabinets, bulb-ringed parapet sign, rocket ride | `neighbourhood_terrace.gd` | the false-front roof (#422), the shop's awning, the street lamp's glow |
| Closed and for sale: rolled-up awning, whitewashed window or roller shutter, agent's board on a post | `neighbourhood_terrace.gd` | the hatch shutter (#589), the shop sign board |
