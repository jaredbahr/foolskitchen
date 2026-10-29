# Made assets

These assets are made for the named issues and follow `docs/ART_STYLE.md` §8. They do not modify the Kenney source kits.

## #118 pending integration
These icon entries are carried forward from issue #118; they are not part of PR #147.

| Asset | Issue | Style reference |
|---|---|---|
| `icons/chefHat.svg` and `icons/chefHat.png` | #118 | Kenney Game Icons `home.png`, `star.png` and `menuList.png`: one white, rounded silhouette with broad transparent margins. |
| `icons/paintBrush.svg` and `icons/paintBrush.png` | #118 | Kenney Game Icons `wrench.png`, `home.png` and `menuList.png`: a thick diagonal tool silhouette with rounded ends and no outlines or gradients. |

The SVG files are the editable sources; the 100 × 100 PNG files are their raster exports.

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
