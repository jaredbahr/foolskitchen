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

## UI control icons (#498)
`ui/*.png` (switch on/off, slider handle, dropdown arrow, menu radio dots) are drawn by `tools/make_ui_controls.py` in the theme palette: rounded, outlined in the ink colour, no gradients. Re-run the script to regenerate.
