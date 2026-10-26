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
| Booth | `benchCushion`, `loungeSofa` | 308 | 0.900 × 0.425 × 0.498 |
| Counter stool | `stoolBar`, `lampWall` | 432 | 0.26544 × 0.435 × 0.26544 |
| OPEN sign | `lampWall`, `wall` | 216 | 0.860 × 0.3775 × 0.131 |
| Chalkboard | `wallWindow`, `paneling` | 60 | 0.700 × 0.560 × 0.050 |
| Wall art A | `wallWindow`, `paneling` | 100 | 0.630 × 0.470 × 0.0645 |
| Wall art B | `wallWindow`, `paneling` | 76 | 0.630 × 0.470 × 0.0695 |

The revised white booth has a lower, thinner backrest and a 0.05 m authored
seated offset. Its cushions retain their original sitting height. The bounded
Blender export and genuine Godot import of this revision passed, followed by
six diner content tests and two emitted-material tests on source `f6f1a1f`.
These eight tests do not establish posed-head clearance or rendered seating
fit. The new surface-to-surface catalogue measurement, support tests, close
crop and final full check remain unrun while the user demo is open.

The booth and stool have item
definitions. Four wall wrappers are explicitly staged for review and are not
registered as floor decor: the current build system has no wall-mount contract.
The OPEN sign uses the source carpet-red colour with emission strength 0.35,
not a white colour blend or a real light. Chalkboard text is
native `Label3D` using the existing theme's font or its normal fallback.

Before the seating revision, on source/model head
`ecc21ac5546cd1f3970250c1a41317d9ca068503`, the unchanged
`bash tools/check.sh` passed using installed Git Bash and Windows Godot 4.7.2:
367 files parsed and 1,098 tests passed, with zero failures. The five asset
tests and four review-fixture tests are included in that full suite. Linux CI
and Web/browser validation are separate gates.

Two earlier 1600x900 Main-scene images were independently inspected: all six
made pieces beside unchanged kit references with a Mini Character for scale,
and a furnished corner whose six guests walked into real reserved booth/stool
seats and used native sitting poses. The complete OPEN word, menu text and
fixture disclosure are readable. These paused, unsaved review fixtures do not
prove natural service or player wall placement.

The Director accepted the original style and deferred the four wall ItemDefs
to issue 148. The revised lower-back booth still needs actual posed-surface
results and a reviewed 3x crop; the earlier images do not validate its new
silhouette. The shared `assets/made/README.md` includes the six diner entries
and preserves issue 118's pending icon entries for later integration. The
partial asset delivery in PR #147 does not complete issue 123.
