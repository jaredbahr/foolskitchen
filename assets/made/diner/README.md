# Classic Diner working set — issue 123

These six GLBs were built locally with the installed Blender 4.5 from the
checked-in scripts in `tools/diner/`. They use the unchanged Kenney Furniture
Kit's material factors, rather than new textures. The referenced kit is CC0;
its existing licence and credit remain in `assets/kenney/furniture/` and
`CREDITS.md`. No kit source was modified.

Measured native dimensions are width × height × depth in metres, before the
existing shared furniture scale. The exported pivot is base-centred, +Y is up,
and the authored front is -Z. Detailed transformed indexed bounds, hashes,
material provenance and source hashes are in each `.metrics.json` and in
`diner_manifest.json`.

| Piece | Nearest unchanged kit references | Triangles | Native dimensions |
|---|---|---:|---|
| Booth | `benchCushion`, `loungeSofa` | 308 | 0.900 × 0.650 × 0.400 |
| Counter stool | `stoolBar`, `lampWall` | 432 | 0.26544 × 0.435 × 0.26544 |
| OPEN sign | `lampWall`, `wall` | 216 | 0.860 × 0.3775 × 0.131 |
| Chalkboard | `wallWindow`, `paneling` | 60 | 0.700 × 0.560 × 0.050 |
| Wall art A | `wallWindow`, `paneling` | 100 | 0.630 × 0.470 × 0.0645 |
| Wall art B | `wallWindow`, `paneling` | 76 | 0.630 × 0.470 × 0.0695 |

The bounded Blender export and genuine Godot import passed, followed by all
four focused diner geometry/seating/font tests. The booth and stool have item
definitions. Four wall wrappers are explicitly staged for review and are not
registered as floor decor: the current build system has no wall-mount contract.
The OPEN sign contains emissive geometry, no real light. Chalkboard text is
native `Label3D` using the existing theme's font or its normal fallback.

Still required: side-by-side kit comparisons, a furnished corner with actually
seated Mini Characters, full project checks, Director style approval, and
coordinated entries in the shared `assets/made/README.md` reserved by issue 118.
No appearance or full issue acceptance is claimed from successful import/tests.
