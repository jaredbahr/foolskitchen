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
- **Grid API (FK-012, `src/sim/grid/`):**
  - `GridMath`: `CELL_SIZE` 0.5 m. `rotate_cell(cell, footprint, quarter_turns)` turns clockwise seen from above, mapping one turn `(x, y) → (d-1-y, x)`. `rotated_footprint`, `cell_to_world`/`world_to_cell`, `path_cost`. Cell x → world +X, cell y → world +Z, and an unrotated item faces −Y (world −Z).
  - `SimGrid`:
    - `from_ascii(rows)`: `.` floor, `#` wall, `E` street entry, space for outside.
    - `place(footprint, origin, turns, solid, work_cells, seat_cells, def) -> PlacedItem` (or null), with `can_place` returning `PlaceResult`.
    - `remove(id)`, `item(id)`, `item_at(cell)`, `items()` (in placement order), `entries()`, `is_walkable(cell)`.
    - `find_path(a, b) -> Array[Vector2i]` includes both ends, is empty when there's no path, and lets an agent walk out of a cell that just became blocked. `find_path_to_any(a, goals)`.
    - `cells_changed(cells)` fires on every walkability change.
  - `PlacedItem`: absolute `cells`, `work_cells` and `seat_cells`. One-agent reservations: `reserve`, `release`, `release_all`, `reserved_by`, `free_work_cell`, `free_seat_cell`.
  - `find_path` from a blocked start (furniture placed on an agent) starts at that cell and continues from `nearest_walkable`, so agents are never trapped. `free_work_cell(item)`/`free_seat_cell(item)` skip reserved and unwalkable cells. `item_removed(item)` fires when an item is removed, and a removed item can't be reserved.
  - Agents don't block each other.
  - **World view:** Godot's positive `rotation.y` turns counter-clockwise seen from above, so a placed item uses `rotation.y = -quarter_turns * PI / 2`, with its mesh anchored at the rotated footprint's minimum corner.
- **Task board:** stations, tables and orders post tasks (`take_order`, `cook`, `deliver`, `bus_table`, `clean`, `seat`). Each idle agent scores the open tasks: role priority x skill / distance, and claims the best one. Claims are exclusive.
- **Self-healing (fixes TasteMaker's stuck-AI complaint):**
  - Every task has a timeout. When it expires, the agent drops it, the task goes back on the board, and the drop is logged.
  - **No progress for N ticks** (the agent hasn't moved and its task step hasn't advanced) triggers a re-path. A second failure drops the task.
  - A path that is blocked after a build edit makes every affected agent re-plan in the same tick.
  - An **invariant test** runs several seeded sim days headless and asserts: every customer leaves, no task stays claimed past its timeout, and no agent is stuck for more than N ticks.
- **Agent API (FK-013, `src/sim/agents/`, `src/sim/sim_world.gd`):**
  - `SimWorld(grid, clock)`:
    - `advance()` runs the clock, then every agent in id order. `now` is the world tick.
    - `add_agent()`, `agent(id)`, and `log_event()` / `event_log` for the overlay.
    - It sets `needs_repath` on agents whose path crosses `cells_changed`, and cancels tasks aimed at a removed item.
  - `TaskBoard`:
    - `post(task, now)`, `claim`, `drop(task, reason)` (reopens; fails after `MAX_DROPS` = 3), `complete`, `cancel`, `open_tasks()`/`claimed_tasks()` (in id order).
    - Signals: `task_posted`, `task_completed`, `task_failed(task, reason)`, `task_dropped`. Posters listen to `task_completed` and `task_failed`.
  - `SimTask(kind, role, label)`: `priority` 0–3, `timeout_ticks` (default 600), `payload` for the poster's data, and `steps`.
  - `TaskStep`:
    - `go_to_item(item_id, label, seat)` reserves a free work cell (or seat) and walks there.
    - `go_to_cell(cell, label)`.
    - `work(ticks, label, on_done)`. `on_done(agent) -> bool`; false cancels the task with `step_failed`.
  - `SimAgent` (movement base, which customers will extend): `cell`, `path`, `path_index`, `move_progress` (0–1 toward `next_cell()`, which the world view lerps), `set_destination`, `step_move`, `why()`.
  - `StaffAgent(role, skill)`:
    - `skills` and `priorities` per role. Claim score = (priority+1) × role priority × skill ÷ (1 + distance).
    - Work speed is 0.6 + 0.1 × skill.
    - Before waiting for a station, it releases the one it held, so two workers can't deadlock.
  - **The board heals itself too** (`SimWorld._heal_board`, every tick): a claimed task whose claimant is gone, or that is more than one tick past its timeout, is dropped. An open task aimed at an item that no longer exists fails with `target_gone`. `remove_agent()` makes the agent give back its task and cells.
  - **A dropped task restarts at step 0** when it's claimed again, so `on_done` callbacks must be safe to run twice (check or record progress in `task.payload`).
  - **Proven by** `tests/sim/test_agent_soak.gd`: 8,000 ticks of deliberate chaos.
    - **The chaos:** random blockers dropped on and around 5 staff, a station boxed in, stations removed and re-placed, workers leaving mid-task, and tasks whose timeout is shorter than their work.
    - **Checked every tick:** no task is held past its timeout; every claimed task's holder is alive and working on it; no reservation is held by an idle or missing agent; nobody is stuck.
    - **At the end:** the board drains to zero, and every healing path (timeout, agent removed, target gone, unreachable) must have fired at least once.
    - **Mutation check:** with both the agent-level and board-level timeouts switched off, the test fails.
    - Run it again after any change to agents.
- **Shops as data (FK-025, `src/sim/shop/`):**
  - A `ShopLayout` (`data/layouts/*.tres`) holds ASCII terrain rows, `placements` (`ShopPlacement`: item id, origin, quarter turns) and `staff_spawns` (role → cell).
  - `ShopBuilder.build(layout, content, errors) -> SimWorld`, and `ShopBuilder.items_with_def(world, id)`.
  - `SimGrid.place_def(item_def, origin, turns)` places an item from its definition.
  - The Tier 1 hole-in-the-wall is `data/layouts/tier1_hole_in_the_wall.tres`:
    - kitchen at the top (fridge, prep counter and stove facing down, with a kitchen door at x=7);
    - the pass at (5,4), worked from both sides;
    - three two-seat tables in the dining room;
    - street entry at (6,11) and (7,11).
- **Customers and orders (FK-014, `src/sim/restaurant/`):**
  - `RestaurantSim.create(layout, content, seed, errors)` owns `world`, `orders`, the tier-one `menu`, and a seeded `spawner`. It adds a cook and server from the layout spawns.
  - `start_day()` resets `served_today`, `lost_today`, `leave_reasons_today` and the arrival countdown; open the world's clock separately. `advance()` runs one world tick, then arrivals and departure cleanup; empty last orders closes the clock.
  - Signals: `customer_arrived(customer)`, `customer_paid(customer, order, amount)`, `customer_left(customer, reason)`. Payment is emitted once at the captured recipe price; there is no economy dependency.
  - `CustomerAgent` extends `SimAgent`: `state`, `table_item_id`, `seat_cell`, `order`, `leave_reason`, `paid`, and `why()`. Seats are reserved in placement order and released on leaving or removal. A server takes each order through ordinary `TaskStep`s.
  - `queue_patience` (300 ticks), `food_patience` (1200 ticks, including order-taking) and `eat_ticks` (300 ticks) are configurable. Missing food cancels work and tickets. An unreachable exit is logged and forcibly removed after 100 ticks.
  - `OrderBook.place(order, now)`, `get_order(id)`, `set_state(order, state)`, `orders_in_state(state)`; placed/ready/delivered/cancelled signals. Delivered and cancelled tickets are terminal. Tickets retain their recipe, price, guest, table, seat and placement tick for reports.
  - `CustomerSpawner` draws uniform `min_gap`..`max_gap` (150..400 ticks) only during OPEN; street choice and each guest's private seed come from its injected RNG.
  - `SimGrid.walkable_neighbours(cell)` returns cardinal then diagonal neighbours in fixed order, without corner cutting. The server uses the nearest neighbour of the reserved seat.
  - `tests/sim/test_customers.gd` includes a three-day seeded fake-kitchen soak with random delays and missing deliveries; it prints arrivals, payments and losses by reason.
- **Debug overlay (F3):** paths, claimed tasks, agent states and the task board, from Phase 1 onward.

### 2.4 Save system
- JSON in `user://saves/`, with a `version` field and migration functions per version.
- Only sim state is saved, never nodes. The world is rebuilt from sim state on load.
- `SaveSystem.register(key, capture, restore)` replaces a unique section provider; capture returns a dictionary and restore returns success.
- `save_game(slot)` / `load_game(slot)` return errors. Writes use `.tmp`, move the previous final to `.bak`, then publish to an absent final; loads prefer a valid final or recover a valid backup. This is a recoverable transaction, not a filesystem-atomic Windows overwrite or power-loss durability guarantee (Godot 4.7.2's Windows rename removes an existing destination before moving).
- Missing sections are skipped; `MIGRATIONS` maps each old version to one upgrade step. Clock and GameState register state in `_ready`.
- RNG seed/state and the master seed use decimal strings to preserve 64-bit integers through JSON parsing.

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
