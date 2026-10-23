# Fool's Kitchen: Technical Plan

## 1. Engine
- **Godot 4.x**, latest stable when the project is created. Record the exact version here and in `AGENTS.md` and do not upgrade mid-phase. Version: TBD (Phase 0).
- **Language:** GDScript with static typing everywhere (`var x: int`, typed function signatures). No C#: it keeps one toolchain and avoids the .NET export setup.
- **Renderer:** Forward+ for desktop. Recheck at Phase 0 if a web build is wanted.
- **Targets:** Windows desktop first. Web and Steam are later, optional.

### Why Godot (decision record)
- Pathfinding, UI, animation, resources and export are built in. Three.js would mean building them ourselves.
- Scenes (`.tscn`) and resources (`.tres`) are text, so AI workers can read and change them.
- Free and MIT-licensed.
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
- **GUT** (Godot Unit Test) for `src/sim/` and `src/core/`.
- `tools/check.sh` runs a headless import and parse, then the GUT tests. Every worker's diff must pass it.

## 3. Art pipeline
- **Style:** low-poly and flat-shaded, using a palette texture (one small gradient atlas shared by most models). This keeps the look consistent and draw calls low.
- **Tools:** Blender, and Tripo AI for drafts that are then cleaned up in Blender.
- **Format:** `.glb` (glTF binary), 1 unit = 1 metre, Y-up, origin at the base centre of the footprint, facing -Z.
- **Grid:** 0.5 m build grid. A person is about 1.75 m tall.
- **Poly budget (guide):** furniture 300 to 1,500 tris, characters 1,500 to 4,000 tris, small props under 300 tris.
- **AI-generated meshes** (Tripo and similar) need retopology or decimation, a pivot fix, a scale check and a swap to the palette material before they go into `assets/models/`.
- **Placeholders:** CSG or primitive shapes are fine until Phase 4. Systems first, art later.
