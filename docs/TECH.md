# Fool's Kitchen: Technical Plan

## 1. Engine
- **Godot 4.7.2 stable** (pinned 2026-10-23). It's recorded here, in `AGENTS.md` and in `tools/godot_version.txt`. Don't upgrade mid-phase. Upgrades are their own issue.
- **Language:** GDScript with static typing everywhere (`var x: int`, typed function signatures). No C#: it keeps one toolchain and avoids the .NET export setup.
- **Renderer:** Compatibility (OpenGL). Godot's web export only supports this renderer. It runs on older family laptops, and low-poly flat shading doesn't need Forward+ effects. It can be switched to Forward+ later for a Steam build, but lighting and shaders would need a retune.
- **Targets:** Windows desktop, plus a web build so family and friends can play from a link. Steam is optional, later.
- **CI and AI workers:** workers run in Linux containers. `tools/get_godot.sh` downloads the pinned official Linux binary from godotengine.org into `.tools/`. Put it in the environment's setup script.

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
tests/         # unit tests (test_*.gd), run by tools/run_tests.gd
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
- **The sim owns movement.** Pathfinding runs in `src/sim/` on the 0.5 m build grid using `AStarGrid2D` (a `RefCounted`, so no nodes are involved). Agents have a grid position and a path. Visual nodes in `world/` only interpolate between grid points and play animations.
  - Why not `NavigationAgent3D`: it lives in the scene tree. That would break headless tests, determinism and background simulation of other sites (TECH 2.2 rule 1).
  - Diagonal moves are allowed, but corners can't be cut. Furniture marks cells solid, and stations expose "work cells" where a worker stands.
- **Task board:** stations, tables and orders post tasks (`take_order`, `cook`, `deliver`, `bus_table`, `clean`, `seat`). Each idle agent scores the open tasks: role priority x skill / distance, and claims the best one. Claims are exclusive.
- **Self-healing (fixes TasteMaker's stuck-AI complaint):**
  - Every task has a timeout. When it expires, the agent drops it, the task goes back on the board, and the drop is logged.
  - **No progress for N ticks** (the agent hasn't moved and its task step hasn't advanced) triggers a re-path. A second failure drops the task.
  - A path that is blocked after a build edit makes every affected agent re-plan in the same tick.
  - An **invariant test** runs several seeded sim days headless and asserts: every customer leaves, no task stays claimed past its timeout, and no agent is stuck for more than N ticks.
- **Customers:** a state machine (`Arriving`, `Queued`, `Seated`, `Ordering`, `Waiting`, `Eating`, `Paying`, `Leaving`, `Left`). Every state has a maximum duration and an exit path.
- **Debug overlay (F3):** paths, claimed tasks, agent states and the task board, from Phase 1 onward.

### 2.4 Save system
- JSON in `user://saves/`, with a `version` field and migration functions per version.
- Only sim state is saved, never nodes. The world is rebuilt from sim state on load.

### 2.5 Testing
- **In-repo runner, not GUT** (decision D9). `tools/run_tests.gd` finds `tests/**/test_*.gd`, runs every `test_*` method, and exits non-zero on failure. Tests extend `tests/test_case.gd`, which provides `assert_eq`, `assert_true`, `assert_false`, `assert_almost_eq` and `assert_null`. No downloads and nothing to version-match. The sim is pure logic, so it doesn't need mocks.
- A test also fails if it raises an engine or script error (a null call, `push_error`), even when its asserts pass. So code paths exercised by tests report problems through return values, not `push_error`.
- `tools/check.sh` runs a headless import, then loads every script and resource (`tools/parse_all.gd`, which also catches scenes pointing at missing files), then the tests. Untyped declarations are errors (`untyped_declaration=2`). Every diff must pass it.
- **Sim tests run without the scene tree** wherever possible (`RefCounted` classes, which can be built directly in tests).

## 3. Art pipeline
**Mood: warm and cosy, and consistency comes first (D13).** Every asset must look like it came from the same hand. When in doubt, match the existing assets rather than adding detail.
- **One palette:** a single shared palette texture (`assets/textures/palette.png`, locked in Phase 4) used by every model. No one-off colours or materials.
- **One lighting setup:** a warm key light from the upper left, a soft cool fill, and warm interior lamps. Assets never bake their own lighting.
- **One level of detail:** flat-shaded, bevel-free, chunky proportions. Small props don't get more polygons per metre than furniture.
- **Placeholders follow the palette too,** so early builds already look consistent.
- **Style:** low-poly and flat-shaded, using a palette texture (one small gradient atlas shared by most models). This keeps the look consistent and draw calls low.
- **Tools:** Blender, and Tripo AI for drafts that are then cleaned up in Blender.
- **Format:** `.glb` (glTF binary), 1 unit = 1 metre, Y-up, origin at the base centre of the footprint, facing -Z.
- **Grid:** 0.5 m build grid. A person is about 1.75 m tall.
- **Poly budget (guide):** furniture 300 to 1,500 tris, characters 1,500 to 4,000 tris, small props under 300 tris.
- **AI-generated meshes** (Tripo and similar) need retopology or decimation, a pivot fix, a scale check and a swap to the palette material before they go into `assets/models/`.
- **Placeholders:** CSG or primitive shapes are fine until Phase 4. Systems first, art later.
