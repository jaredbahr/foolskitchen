# Fool's Kitchen: Rules for AI Workers

This file is read by every coding agent (Codex, harness workers, Claude). Read `docs/DESIGN.md` and `docs/TECH.md` before starting a task.

## Project
- A low-poly 3D restaurant tycoon game. Godot 4.7.2, typed GDScript, Compatibility renderer (it must stay web-exportable).
- Hobby project with a light process.

## Workflow
1. Work comes from an assigned GitHub issue. The issue is the brief: do what its **Do** says, stay out of **Don't**, and finish **Done when**.
2. Branch from `main` as `issue-<number>-<slug>`.
3. Open a PR into `main` with `Closes #<number>` in the body.
4. One task per PR. If you find extra work, note it in the PR body instead of doing it.

## Godot 4 only (never Godot 3 syntax)
| Wrong (Godot 3) | Right (Godot 4) |
|---|---|
| `export var x` | `@export var x: int` |
| `onready var n = $N` | `@onready var n: Node = $N` |
| `yield(obj, "sig")` | `await obj.sig` |
| `connect("sig", self, "_f")` | `sig.connect(_f)` |
| `KinematicBody`, `Spatial` | `CharacterBody3D`, `Node3D` |
| `move_and_slide(vel)` | set `velocity`, then call `move_and_slide()` |
| `tool` | `@tool` |
| `instance()` | `instantiate()` |
| `PoolStringArray` | `PackedStringArray` |
| `rand_range()` | `randf_range()` on a seeded `RandomNumberGenerator` |

## Code rules
1. Static typing everywhere: variables, parameters, return types.
2. `src/sim/` has no Node or scene dependencies. It contains `RefCounted` or `Resource` classes only, and is unit tested (`tests/test_*.gd`, see `docs/TECH.md` 2.5). Pathfinding is `AStarGrid2D` in the sim, not `NavigationAgent3D`.
3. Content lives in `data/*.tres`. Don't hard-code recipes, prices or items.
4. Cross-system communication goes through `EventBus` signals.
5. No global `randf()`/`randi()`. Use the system's seeded RNG from `GameState`.
6. No runtime network calls, and no AI or API calls in the game.
7. Connect signals to **methods**, not lambdas that use `self`, when the signal's owner is (directly or indirectly) owned by `self`. Such a lambda keeps both objects alive (a reference cycle), and the leak warning at exit fails `check.sh`.
8. Nothing that breaks the web export: no threads that need special headers, no C#, no GDExtension unless an issue says so.

## Files Godot generates
- Commit `*.uid` and `*.import` files next to their sources. Never commit `.godot/` or `.tools/`.

## Changelog (required)
- Every PR adds at least one line under `## Unreleased` in `CHANGELOG.md`, in the right group (Players / Content / Under the hood), ending with `(#<PR number>)`. Use plain words a player would understand for player-facing changes. CI fails without it. The `no-changelog` label is for changelog-only fixes and reverts.

## Before you finish
- Run `tools/check.sh` (created in Phase 0). It must pass.
- Add or update tests for any sim logic you touched.
- Setup: `bash tools/get_godot.sh` once (it downloads Godot into `.tools/`), then `bash tools/check.sh`.
- In the PR body: what changed, how you tested it, and any open questions.
- Visual changes: attach screenshots from `bash tools/screenshot.sh` (needs `xvfb` and Mesa; if your environment lacks them, say so).

## Art assets
- `.glb` only, 1 unit = 1 m, Y-up, origin at the base centre, facing -Z. See `docs/TECH.md` section 3.
- AI workers do not generate or edit 3D models. They may build placeholder shapes in scenes.
