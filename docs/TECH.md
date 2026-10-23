# Fool's Kitchen: Technical Plan

## 1. Engine
- **Godot 4.7.2 stable**, the latest stable when the project was created (verified 2026-10-23 against the [official download page](https://godotengine.org/download/linux/) and [official release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)). Do not upgrade mid-phase.
- **Language:** GDScript with static typing everywhere (`var x: int`, typed function signatures). No C#: it keeps one toolchain and avoids the .NET export setup.
- **Renderer:** Compatibility (OpenGL). Godot's web export only supports this renderer. It runs on older family laptops, and low-poly flat shading doesn't need Forward+ effects. It can be switched to Forward+ later for a Steam build, but lighting and shaders would need a retune.
- **Targets:** Windows desktop, plus a web build so family and friends can play from a link. Steam is optional, later.
- **CI and AI workers:** workers run in Linux containers. Download the official Godot Linux binary (the version pinned above) in the environment's setup script so `tools/check.sh` can run headless.

### Why Godot (decision record)
- Pathfinding, UI, animation, resources and export are built in. Three.js would mean building them ourselves.
- Scenes (`.tscn`) and resources (`.tres`) are text, so AI workers can read and change them.
- Free and MIT-licensed.
- **Re-evaluated 2026-10-23** against Unity, Three.js and Babylon.js for an AI-worker workflow. Unity needs licence activation and a heavy editor install for headless CI, and its scenes are hard to edit as text. Three.js and Babylon.js are the easiest for AI to write and test, but the tycoon systems would have to be built ourselves. Godot can be tested headless, its files are text, and it exports to the web.
- **Risk:** AI models sometimes write Godot 3 syntax. Mitigated by the Godot 3 to 4 table in `AGENTS.md` and by a checks script that fails on parse errors.

## 2. Architecture

### 2.1 Folder layout
```
project.godot
src/
  core/        # autoloads: GameState, Clock, Economy, SaveSystem, EventBus
  sim/         # pure simulation logic: customers, staff, tasks, kitchen
  build/       # build mode, grid, placement validation
  ui/          # HUD, menus, panels
  minigames/   # one folder per mini-game, each a self-contained scene
  world/       # restaurant scenes, the camera, agents' visual nodes
data/          # .tres resources: recipes, ingredients, items, themes, properties
assets/
  models/      # .glb only
  textures/
  audio/
tests/         # GUT unit tests
tools/         # check scripts
docs/
```

### 2.2 Key rules
1. **The sim is separate from the visuals.** `src/sim/` holds plain data and logic with no nodes. Visual nodes in `world/` read sim state and animate it. This makes the sim unit-testable and lets background properties run without visuals.
2. **Fixed simulation tick** (for example 10 ticks per game second), independent of frame rate. Speed controls change the number of ticks per frame.
3. **Data-driven content.** Recipes, items, themes and properties are custom `Resource` types in `data/`. Adding content means adding a `.tres` file, not code.
4. **Communication goes through `EventBus` signals.** No `get_node("../../..")` chains across systems.
5. **Deterministic randomness:** one seeded `RandomNumberGenerator` per system, held in `GameState`. This makes bugs reproducible.

### 2.3 AI (agents)
- **Task board:** stations and tables post tasks (`cook`, `serve`, `clean`, `seat`). Staff claim tasks by priority, distance and skill. This works like Sims autonomy and is simple to debug.
- **Movement:** `NavigationAgent3D` on a baked navmesh, rebaked when build mode commits a change.
- **Customers:** a simple state machine (`Arriving`, `Queued`, `Seated`, `Ordering`, `Waiting`, `Eating`, `Paying`, `Leaving`).

### 2.4 Save system
- JSON in `user://saves/`, with a `version` field and migration functions per version.
- Only sim state is saved, never nodes. The world is rebuilt from sim state on load.

### 2.5 Testing
- **GUT 9.7.1** (Godot Unit Test) for `src/sim/` and `src/core/`, vendored unchanged from the official [v9.7.1 tag](https://github.com/bitwes/Gut/tree/v9.7.1/addons/gut), commit `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`. Its [version table](https://github.com/bitwes/Gut/blob/v9.7.1/addons/gut/versions.json) supports Godot 4.7 through 4.7.999. The addon and bundled fonts retain their upstream licenses.
- `tools/check.sh` runs a headless import, loads all first-party scripts to catch parse/compile errors (even unused scripts), then runs the GUT tests. It rejects logged engine/script errors as well as nonzero exits. Logs are retained in ignored `.tools/check.*/` directories. Every worker's diff must pass it.

On a clean Linux clone (Bash, `curl`, `unzip`, and `sha256sum` required):

```sh
export GODOT="$(tools/get_godot.sh)"
tools/check.sh
```

`get_godot.sh` downloads the pinned standard Linux editor for x86_64 or ARM64 into `.tools/`, checks its SHA-256 against the official release asset digest, and prints its absolute path. The standard editor supports `--headless`; no separate headless build is needed. `check.sh` accepts a single executable path in `$GODOT` (including spaces), or falls back to `godot` on PATH, and verifies the pinned version.

For editor verification, open `project.godot` in Godot 4.7.2 and check the Output panel for errors and warnings. The main scene is an empty `Node3D`. The `Web` export preset uses `variant/thread_support=false`; export templates and an actual export are not required for the skeleton.

`GameState` owns `customers`, `staff`, `events`, and `minigames` RNG streams. `reset_rngs(seed)` starts each from a seed derived from the run seed and system name; `get_rng(name)` returns that existing stream. Reproduction is scoped to the pinned engine. Clock, economy, persistence, and EventBus behavior will be defined by later issues; persistence stubs explicitly return `ERR_UNAVAILABLE`.

## 3. Art pipeline
- **Style:** low-poly and flat-shaded, using a palette texture (one small gradient atlas shared by most models). This keeps the look consistent and draw calls low.
- **Tools:** Blender, and Tripo AI for drafts that are then cleaned up in Blender.
- **Format:** `.glb` (glTF binary), 1 unit = 1 metre, Y-up, origin at the base centre of the footprint, facing -Z.
- **Grid:** 0.5 m build grid. A person is about 1.75 m tall.
- **Poly budget (guide):** furniture 300 to 1,500 tris, characters 1,500 to 4,000 tris, small props under 300 tris.
- **AI-generated meshes** (Tripo and similar) need retopology or decimation, a pivot fix, a scale check and a swap to the palette material before they go into `assets/models/`.
- **Placeholders:** CSG or primitive shapes are fine until Phase 4. Systems first, art later.
