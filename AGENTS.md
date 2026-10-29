# Fool's Kitchen: Rules for AI Workers

This file is read by every coding agent (Codex, harness workers, Claude). Read `docs/DESIGN.md` and `docs/TECH.md` before starting a task.

## Project
- A low-poly 3D restaurant tycoon game. Godot 4.7.2, typed GDScript, Compatibility renderer (it must stay web-exportable).
- Hobby project with a light process.

## Workflow
1. Work comes from an assigned GitHub issue. When choosing your next issue yourself, take open `worker-ready` issues in the order of `docs/ROADMAP.md` → "Up next: the Codex queue" (wave 1 first, top to bottom), skipping any whose **Depends on** / "Start after" hasn't merged. Issues without `worker-ready` are not yours yet. The issue is the brief: do what its **Do** says, stay out of **Don't**, and finish **Done when**.
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
9. **Saving happens in one place only:** the morning autosave in `src/world/main.gd` `_begin_morning()`. Never add a save after a player action (menu, build, owner, anything). New state joins the save by registering a section with `SaveSystem.register()` and is written at the next morning autosave. Don't change `src/core/save_system.gd` unless the issue asks for it.
10. **Keep CI cheap:** don't add loops, repeat runs, probes or extra jobs to `.github/workflows/`. A new feature may add at most one or two captures to the visual-review job. Put state checks in GDScript tests, not inline workflow scripts. Diagnostic loops go in `tools/` and are run by hand.
11. Player-facing text never shows raw enum or internal names (for example `OVERLAPS`, `dropped_too_often`). Map them to short plain sentences in one place.

## Files Godot generates
- Commit `*.uid` and `*.import` files next to their sources. Never commit `.godot/` or `.tools/`.

## Changelog (required)
- Every PR adds at least one line under `## Unreleased` in `CHANGELOG.md`, in the right group (Players / Content / Under the hood), ending with `(#<PR number>)`. Use plain words a player would understand for player-facing changes. CI fails without it. The `no-changelog` label is for changelog-only fixes and reverts.

## Before you mark a PR ready (the director has limited review time)
- Read every comment on the issue. A comment from the director (`jaredbahr` account, Claude-signed) overrides the issue body.
- Check **Depends on**. If a listed PR or issue hasn't merged, don't start. Pick another `worker-ready` issue.
- Merge the latest `main` into your branch (a merge commit, not a rebase) and run `bash tools/check.sh` again. A PR that only passed on an old base has broken `main` before.
- Self-review: in a fresh pass, re-read your whole diff against the issue's **Do**, **Don't** and **Done when**, and against code rules 1–11. Fix what you find.
- Put a short checklist in the PR body: each **Done when** item ticked, with evidence (the test name, probe table or screenshot), plus "Rules 9/10/11: held" or what you changed and why.
- Never commit review evidence: no screenshots, review PNGs, `.import` sidecars, evidence JSON or review notes (for example under `docs/reviews/`). Everything inside the project ships in builds. Attach images to the PR or let the visual-review job upload them.
- Mark the PR ready for review. Don't leave it as a draft.
  - Mark it ready as soon as `check.sh`, the balance probe, CI and your own captures are done. Director visual or taste acceptance, director decisions and Jared's playtests happen **after** it is ready, never before. "Draft retained for Director review" is wrong: the director reviews ready PRs only.
  - If you need a director decision, ask in a PR comment and still mark the PR ready with your best default. The director answers on the ready PR.
  - Finish your open PRs (answer director comments, merge `main`, mark ready) before you start a new issue.

## Before you finish
- Run `tools/check.sh` (created in Phase 0). It must pass.
- Add or update tests for any sim logic you touched.
- Setup: `bash tools/get_godot.sh` once (it downloads Godot into `.tools/`), then `bash tools/check.sh`.
- In the PR body: what changed, how you tested it, and any open questions.
- Visual changes: attach screenshots from `bash tools/screenshot.sh` (needs `xvfb` and Mesa; if your environment lacks them, say so).

## Art assets
- `.glb` only, 1 unit = 1 m, Y-up, origin at the base centre, facing -Z. See `docs/TECH.md` section 3.
- Use the Kenney kits in `assets/kenney/` (never edit them). New models or icons may be made **only** under `docs/ART_STYLE.md` §8 (Kenney style, in `assets/made/`), and only when the issue names the item.
- **Consistency is the top art rule (Jared, D19).** Everything on screen (people, furniture, kitchen equipment, food, decor, UI icons) must look like it came from one hand. Never mix in an asset, colour, font or icon from a new source or style without a director-approved issue saying so. If a needed item is missing from the approved source, stop and say so in the PR rather than substituting something that looks different. The approved style lock is `docs/ART_STYLE.md`: read it before any visual work.
