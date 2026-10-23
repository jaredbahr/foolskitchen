# Brief FK-001: Godot project skeleton and checks

- **Phase:** 0
- **Depends on:** none
- **Branch:** `brief/fk-001-skeleton`

## Goal
An empty but correctly structured Godot 4 project that opens cleanly and has a working headless check script.

## Context
Read `AGENTS.md`, and `docs/TECH.md` sections 1, 2.1 and 2.5.

## Do
- Create `project.godot` (Forward+, name "Fool's Kitchen") using the installed Godot 4 stable version. Write the exact version into `docs/TECH.md` section 1 and `AGENTS.md`.
- Create the folder layout from TECH.md 2.1. Add `.gitkeep` to folders that are empty.
- Add autoload stubs with typed, empty APIs and a doc comment each: `EventBus`, `GameState` (holds named seeded RNGs), `Clock`, `Economy`, `SaveSystem`.
- Install GUT under `addons/gut/`, pinned to a version that supports this Godot version. Add one sample test in `tests/`.
- Add `tools/check.sh`: a headless import (`godot --headless --import`), a check for script errors, then a headless GUT run. It exits non-zero on any failure.
- Add a Godot-appropriate `.gitignore` (`.godot/`, `*.import` caches as appropriate, exports).
- Add a `.gitattributes` setting `* text=auto eol=lf`.

## Don't
- No gameplay, scenes beyond an empty `Main.tscn`, art, or camera work. Those come in FK-002.

## Done when
- [ ] `tools/check.sh` passes on a clean clone.
- [ ] The project opens in the editor with no errors or warnings in the output.
- [ ] The Godot and GUT versions are recorded.

## Report back
Files changed, the versions chosen, and how you tested.
