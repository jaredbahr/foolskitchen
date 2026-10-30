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
