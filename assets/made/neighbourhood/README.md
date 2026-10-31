# Neighbourhood pieces (#242)

Original Blender-made pieces for the issue-named street, buildings, car and lamps, following `docs/ART_STYLE.md` §8. No City/Suburban kit, downloaded asset, new texture, animation or baked lighting is used. All colours/PBR values are copied exactly from the existing Kenney Furniture Kit; the generator verifies each approved source file's hash before export.

Rebuild with installed Blender, passing an audit path **outside this project**:

```bash
blender --background --factory-startup --python tools/build_neighbourhood.py -- --manifest /tmp/neighbourhood-assets.json
```

The GLBs use metres, Y-up, base-centred origins and front -Z. Their source geometry is authored for the existing `ArtScale.FURNITURE_SCALE`, which the made-model view applies once uniformly. Do not add the original Kenney wrapper's PI rotation or stretch a model. The road runs along X with two lanes across Z; crossing pieces replace ordinary road pieces. Body and roof are separate reusable modules. Both street lamps reuse one unlit asset; its yellow panel is the existing kit lamp colour, with no emission or light node.

| Model | Rendered envelope X × Y × Z (m) | Nearest approved reference |
|---|---|---|
| road_segment.glb | 1.10 × 0.025 × 2.40 | floorHalf slab, wall metalDark, cabinet carpetWhite lane mark |
| crossing_segment.glb | 1.10 × 0.025 × 2.40 | Same slab and broad kit-white crossing marks |
| kerb_segment.glb | 1.10 × 0.08 × 0.10 | floorHalf-like edge, lampRoundFloor metal |
| shopfront.glb | 2.20 × 1.40 × 1.70 | wall/wallWindow/doorwayFront proportions, kit cream and wood |
| house_body.glb | 2.20 × 1.40 × 1.70 | Same wall/door/window scale, alternate kit-wood facade |
| gable_roof.glb | 2.32 × 0.45 × 1.82 | Simple chunky prism in bathroomCabinet woodDark |
| compact_car.glb | 0.70 × 0.66 × 1.40 | Slightly bevelled kit-style boxes and twelve-sided wheels, chairModernCushion carpetBlue, wall metalDark/window glass/cabinet cream |
| street_lamp.glb | 0.30 × 1.65 × 0.45 | lampRoundFloor/lampWall materials and edge softness on an authored post |

A roof placed at the body's 1.40 m top gives a complete 2.32 × 1.85 × 1.82 m building. Placement and moving-car clearance must use full composed/transformed bounds. The generator writes bounds, triangles, material records, source hashes and mesh transforms only to the requested outside audit file; review evidence does not ship in this directory. Pavement and pedestrians reuse the existing `floorHalf.glb` and Mini Character/PersonView assets without editing them.
