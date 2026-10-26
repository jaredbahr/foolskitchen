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
| Booth | `benchCushion`, `loungeSofa` | 308 | 0.900 × 0.650 × 0.642 |
| Counter stool | `stoolBar`, `lampWall` | 432 | 0.26544 × 0.435 × 0.26544 |
| OPEN sign | `lampWall`, `wall` | 216 | 0.860 × 0.3775 × 0.131 |
| Chalkboard | `wallWindow`, `paneling` | 60 | 0.700 × 0.560 × 0.050 |
| Wall art A | `wallWindow`, `paneling` | 100 | 0.630 × 0.470 × 0.0645 |
| Wall art B | `wallWindow`, `paneling` | 76 | 0.630 × 0.470 × 0.0695 |

The revised white booth has a lower, thinner backrest and a 0.05 m authored
seated offset. Its cushions retain their original sitting height. The bounded
Blender export and genuine Godot import of this revision passed, followed by
six diner content tests and two emitted-material tests on source `f6f1a1f`.
Those tests establish asset properties, separately from the posed-surface
checks below.

The booth and stool have item
definitions. Four wall wrappers are explicitly staged for review and are not
registered as floor decor: the current build system has no wall-mount contract.
The OPEN sign uses the source carpet-red colour with emission strength 0.35,
not a white colour blend or a real light. Chalkboard text is
native `Label3D` using the existing theme's font or its normal fallback.

On source/test head `3d3958b5e277aae0e85016ef57ee1744c1b888d3`, the unchanged
`bash tools/check.sh` passed using installed Git Bash and Windows Godot 4.7.2:
374 files parsed and 1,141 tests passed, with zero failures or shutdown errors.
Linux CI and Web/browser validation are separate gates, recorded in the PR.

The actual-surface catalogue run covered 1,632 unique cases, with complete
coverage, zero measurement/engine errors and zero unexpected failures. All
288 made-seat cases pass: the booth's minimum identified backrest gap is
0.021208 m, both hips project onto named cushions, and no head vertex is inside
a seat part. Nine unchanged kit definitions retain named, measured exceptions
under the Director's review rule. Their 1,152 raw failing rows comprise 1,008
physical-violation rows and 144 unclassified-only rows; they are not fixed by
this PR. See `tools/seated_head_probe.md` and the PR evidence for the distinction.

Two new 1600x900 Main-scene Windows/NVIDIA captures and an exact nearest-pixel
3x booth crop were generated on the same source/test head, with zero engine
errors. They show the six made pieces beside unchanged kit references and a
furnished corner with six actual reserved booth/stool seats. These paused,
unsaved review fixtures do not prove natural service or player wall placement.

The Director accepted the original style and deferred the four wall ItemDefs
to issue 148. The revised lower-back booth and final rendered sign colour
remain subject to Director visual review; source material colours alone do
not establish appearance. The shared `assets/made/README.md` includes the six diner entries
and preserves issue 118's pending icon entries for later integration. The
partial asset delivery in PR #147 does not complete issue 123.
