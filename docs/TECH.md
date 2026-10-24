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
  build/       # pure interaction controller; placement checks live in sim/shop
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
    - `go_to_work_cell(item_id, index, label)` is an exact rotated work-cell selector (used for the two pass sides). It retains GO_TO_ITEM reservation, busy wait, removal, repath and timeout handling. `work_cell_index = -1` preserves legacy first-free-cell selection.
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
  - `start_day()` resets `served_today`, `lost_today`, `leave_reasons_today` and the arrival countdown, clears departure tracking, prunes finished orders, runs the overnight tidy (`Kitchen.tidy_overnight()`) and puts every staff member back at its layout spawn with no task; open the world's clock separately. `advance()` runs one world tick, then arrivals and departure cleanup; empty last orders closes the clock. At the CLOSED deadline all remaining guests are removed and recorded that day as `closing`.
  - Final closing counters are ready when `advance()` returns; raw clock phase signals can precede its cleanup sweep.
  - Signals: `customer_arrived(customer)`, `customer_paid(customer, order, amount)`, `customer_left(customer, reason)`. Payment is emitted once at the captured recipe price; there is no economy dependency.
  - `CustomerAgent` extends `SimAgent`: `state`, `table_item_id`, `seat_cell`, `order`, `leave_reason`, `paid`, and `why()`. Reachable seats are reserved in placement order and released on leaving or removal. Failed seat paths or a 200-tick seat walk release the reservation and retry within the bounded queue budget. A server takes each order through ordinary `TaskStep`s.
  - `queue_patience` (300 ticks), `food_patience` (1200 ticks, including order-taking) and `eat_ticks` (300 ticks) are configurable. Missing food cancels work and tickets. An unreachable exit is logged and forcibly removed after 100 ticks.
  - `CustomerAgent.mood() -> float` reads remaining queue patience in QUEUED and food patience in ORDERING/WAITING_FOOD, clamped to 0..1 (nonpositive waiting budgets give 0). Every other state, including walking, gives 1. `mood_band() -> int` uses named thresholds 0.6/0.35/0.15 for happy/waiting/impatient/about-to-leave; waiting `why()` text adds that band without changing the sim.
  - `ShopView.mood_nodes` holds native billboard dots and ASCII `!`/`!!` above waiting guests. State/band caches avoid repeated presentation updates; state exits, guest removal and world rebinding remove the icons. No textures or imported models are used.
  - Real `--open --fast=8` mood captures record unmodified guest patience/mood/bands, actual visible indicator ids/bands/marks/colours and camera positions, plus actual RNG seeds/state. Post-draw JSON includes the saved PNG's SHA-256. The visual review job samples frames 120/180/240/300 sequentially and reports observed bands without claiming that several bands appeared until the PNGs are reviewed; no waiting fixture is applied.
  - `OrderBook.place(order, now)`, `get_order(id)`, `set_state(order, state)`, `orders_in_state(state)`; placed/ready/delivered/cancelled signals. Delivered and cancelled tickets are terminal; `prune_finished()` discards them next morning. Tickets retain their recipe, price, guest, table, seat and placement tick for reports.
  - `CustomerSpawner` draws uniform `min_gap`..`max_gap` (150..400 ticks) only during OPEN; street choice and each guest's private seed come from its injected RNG.
  - `SimGrid.walkable_neighbours(cell)` returns cardinal then diagonal neighbours in fixed order, without corner cutting. The server uses the nearest neighbour of the reserved seat.
  - `tests/sim/test_customers.gd` includes a three-day seeded fake-kitchen soak with random delays and missing deliveries; it prints arrivals, payments and losses by reason.
- **Kitchen line (FK-015, `src/sim/restaurant/kitchen.gd`):**
  - `RestaurantSim.create(..., stock = null, with_kitchen = true)` creates the real `Kitchen` by default; omitted stock means an empty `Stock`, never free supplies. `sim.stock` is shared with the kitchen; replacing that public property immediately propagates the new inventory to the live kitchen. Customer-only regression fixtures explicitly pass `null, false` and install their fake kitchen when needed.
  - Cook tasks fetch ingredients at the fridge, perform the recipe's station steps, and plate at pass `work_cells[0]` (kitchen side). `ingredients_taken` in task payload prevents double consumption after a dropped/restarted task; a shortage cancels the ticket and guest visit with `out_of_stock`.
  - There is no task-claimed signal. `Kitchen.advance()` examines only its tracked active cook tasks after the world tick, publishing COOKING on the claim tick before `RestaurantSim.advance()` returns. READY is emitted on cook completion.
  - Priority-3 delivery tasks reserve pass `work_cells[1]` (dining side), explicitly release it on pickup, walk to a reachable seat neighbour, then serve. They do not hold the pass while walking to the guest.
  - `Order.quality` is `clamp(base_quality * (0.7 + 0.1 * cook_skill) + station_bonuses, 0, 1)` with skill clamped 1..5 (factor 0.8..1.2). Each distinct recipe station contributes its bonus once. `Order.cancellation_reason` is set by the optional reason argument to `OrderBook.set_state` and is preserved by guest departure.
  - `Kitchen.mark_table_dirty(id)` runs before an occupied seat is released (also on forced/external removal); failed seat walks do not dirty a table. Customers skip `is_table_dirty(id)` tables. A real priority-1 server task reserves a free table seat and works 40 units before removing the dirty hold. Terminal bus failures keep the flag and log a reason;   - CLOSED immediately removes guests, terminalizes their tickets and cancels their cook/deliver tasks. Real bussing may continue while the evening report is open. Each morning `start_day()` runs the overnight tidy (decision on #45): staff clean up after hours, so every dirty table is cleared, any leftover kitchen task is cancelled (`overnight_tidy`) and staff start at their posts. This is a deliberate rule, not a hidden failure: unfinished work never spills into the next day.ions and `Kitchen.is_clean()`. `start_day()` never clears dirty tables to conceal unfinished work.
  - The current playable `Clock` driver stops at CLOSED and does not yet drive this cleanup interval; future restaurant/world integration must do so. `RestaurantSim.advance()` remains exactly one world tick per call, with no internal drain loop.
- **Plate cycle (FK-038):** `Kitchen.plates` is a pure `PlateLedger` with
  `clean`, `dirty`, `in_use` and durable `total` (Tier 1 starts with 12).
  Plating takes one clean plate per order. READY, carrying, seated and returned
  table plates remain in use; completed bussing collects only returned orders.
  Cancellation and table removal recover plates once, including terminal orders.
  Clean + dirty + in use always equals total; returned plates are a subset of use.
  Priority-0 server `wash` tasks work 15 units per plate, at most four per task.
  Only washing opts into `SimTask.defer_to_higher_priority`: an idle actor
  defers its claim while eligible OPEN higher-priority work of the same task
  role remains. Existing actor scores decide eligibility and all other ties;
  claimed washing is not preempted. Ordinary drop/timeout recovery is unchanged.
  Per-step replay guards survive drops. Reachable sinks are chosen in stable
  placement order. A transient terminal wash failure retries after 30 world
  ticks; only a shop with no reachable sink waits for a layout change.
  At the pass, `WAIT_UNTIL` gives "Waiting for a clean plate" without changing
  the existing claimed-task timeout or stuck recovery. Ready waits start the
  following plating WORK in the same tick. Overnight cleanup washes all stock.
  The ASCII HUD counter shows clean/total, with dirty/in-use in its tooltip.
  Main stages the validated `plates` save section (total only), installs it after
  a successful morning load, and saves at the existing morning boundary.
  Totals save as integers; loading accepts 1 through 999 and earlier canonical
  decimal-string totals. This validation range does not change the live ledger.
  Older saved layouts keep their furniture and default plate stock. Without
  any sink, plate limits are off and the HUD says "Plates: buy a sink".
  A present but unreachable sink still enables plate limits and cook waits.
  Buying a sink enables counting at the next plating decision; already
  bypassed meals remain uncounted across replay/completion/cancellation.
  Existing held tokens still recover normally if the last sink is externally
  removed; no live ledger reset occurs. The last present sink cannot be sold.
- **Trays (FK-041):** `RestaurantSim.carry_capacity` is 1, 2 or 4 for the
  entire shop. The server's claimed delivery gathers up to that many READY
  orders at pass pickup, taking only unclaimed delivery tasks. It chooses
  reachable tables in nearest-next path order with order-ID ties. Each meal
  becomes DELIVERED at its own stop; the guest's existing eating and payment
  path runs once. A cancelled meal recovers its own held plate and the other
  stops remain on the trip. A failed trip cancels only its still-READY meals.
  A dropped prepared batch remains one delivery task covering its READY meals;
  another pickup cannot absorb its primary and orphan the other stops. Trays
  affect delivery only: bussing still clears every returned plate at one table
  in one task, independent of carry capacity.
  Main offers two MORNING-only, ordered purchases at the prices in
  `tier1_economy.tres` ($60/$150 initially) under `Ledger.UPGRADES`.
  The shop save section adds `tray_level` (0/1/2); old sections default to 0.
  Purchases wait for the next existing morning autosave. The Staff panel shows
  the prices, ownership and current capacity, while the placeholder view shows
  a tray during delivery of more than one plate.
- **Debug overlay (F3):** paths, claimed tasks, agent states and the task board, from Phase 1 onward.
- **Owner assignment (FK-020):** the restaurant factory creates one `OwnerAgent`
  at the authored owner spawn, with cook/server skill 3 and default `rest`.
  `owner_agent()` returns that live agent and `assign_owner(mode) -> bool`
  accepts `kitchen` (3/0 cook/server priorities), `floor` (0/3), `help` (1/1)
  or `rest` (0/0). The role stays `owner`; owner/any priorities are always zero.
  A newly disabled task is dropped on the next owner tick through the ordinary
  task board and StaffAgent cleanup, including reservations and drop limits.
  Rest walks home through real path/movement steps; unreachable or stalled
  routes have three bounded attempts and wait honestly for a grid change.
  Morning staff resets retain the mode. The owner is excluded from wages.
- `OwnerAssignment.resolve(world_position, grid)` reads footprints and rotated
  external work cells. Fridge, prep counter, stove and pass side 0 choose kitchen;
  tables and pass side 1 choose floor. Footprint pass clicks choose the nearest
  side with deterministic ties. It changes no grid, reservation or agent state.

### 2.3b Game session (FK-024, `src/world/main.gd`)
- `main.tscn` is the game session for one shop. It builds a `RestaurantSim` from the layout and content, and points `sim.stock` at `Economy.stock`.
- `Clock.attach_world(world, sim.advance)` makes every tick run the restaurant (guests, staff, and the kitchen once it lands).
- **Day loop:**
  - **MORNING:** `sim.start_day()`, the fridge is topped up to `EconomyTuning.morning_stock` (bought through `Economy.buy_ingredient`), then autosave.
  - **CLOSED:** wages per staff role and rent are charged through the ledger, then the evening report shows a `DayReport` built from `Ledger.day_totals` and the sim's counters.
  - **"Next day"** (in the report or the HUD) calls `Clock.sim.next_day()`, which returns to MORNING.
- Money numbers live in `data/balance/*.tres` (`EconomyTuning`).
- `customer_paid` records a SALE and counts the dish.
- **Saves:** the slot is "autosave" (F10 deletes it and restarts). Autoloads register save providers through `register_save_provider()`, which `main.start()` also calls, because the test runner never delivers `_ready()`.
- `run_ticks(n)` fast-forwards for tests and tools.
- With the owner selected, Main resolves assignment targets before ordinary
  agent/item picking and retains owner selection. K/F/H/R and the inspector's
  Kitchen/Floor/Help/Rest buttons use the same guarded `assign_owner_mode`
  command. Other selections retain normal inspection. The inspector preserves
  native button press attempts across frame/tick refreshes and emits primitive
  requests; it never assigns sim work itself.
- A small `owner` save section stores only the mode through Main's capture and
  restore methods, with `OwnerModeSettings` validating the plain mode data.
  Like the shop and menu providers, these callbacks belong to the active Main.
  Startup applies the validated mode only after a complete
  successful MORNING load; missing old-save data defaults to rest, and failed
  loads reset it with the existing fresh-game/skip-one-autosave behavior.
  Assignment commands in every phase wait for the next normal MORNING autosave;
  quitting before that checkpoint loses those assignment changes. No service
  snapshot or additional stock purchase is introduced by a service hotkey.
- Capture option `--select=owner --assign-owner=kitchen --open` selects the live
  factory owner and uses the same command. At each requested image it permits
  at most 900 extra normal sim ticks to observe actual claimed cooking work.
  Post-draw metadata reports the real selected owner/mode/task/claimant/step,
  world tick and warmup count; it fails when these cannot be established.
  It installs no task, guest, stock or altered staff fixture. The existing
  sequential visual-review job includes an owner kitchen image for review.

### 2.3c Furniture edits (FK-031)
- `ShopEditor(sim, content, books)` is pure `RefCounted` logic. `ShopEditBooks`
  receives typed method Callables for `can_spend_without_loan` and `add_cash`;
  checks never change live placements, reservations, books or grid signals.
- `can_edit()` permits MORNING and CLOSED only. `check_move`/`move`,
  `check_buy`/`buy`, and `check_sell`/`sell` expose the checked operation.
  `EditCheck` has `ok`, `why`, and sorted `unreachable` item IDs (0 means the
  proposed new purchase). Path warnings describe the resulting shop and never
  block a geometrically valid edit. They use rotated seats/work cells; both
  kitchen/dining pass sides must be reachable from a street entry.
- Moves/rotations are free and preserve the `PlacedItem`, ID and order through
  `SimGrid.relocate_def`. An item with a held work/seat cell refuses relocation:
  "in use; try next morning". Successful changes emit one complete old/new cell
  union, without a temporary removal. An identical pose is a no-op.
- Buying charges the content price once under `Ledger.UPGRADES`, without loans.
  Selling returns half the price rounded down; -1 means refusal and zero is a
  successful zero refund. `last_check`/`check_sell` explain refusal. Doors and
  the last functional fridge, prep counter, stove or pass cannot be sold.
  Normal grid removal releases reservations and cancels work targeting a sale.
- `to_dict()` returns version 1 and stable `items` records containing `def_id`,
  `[x, y]` origin and quarter turns. Static `from_dict(data, template, content,
  errors)` validates an isolated layout or returns null; it never replaces a
  live world. Terrain/staff spawns come from the template, with required station
  and template-door safeguards. Missing old-save `shop` sections use the layout.
- The session exposes `shop_editor` and plain `shop_move`, `shop_buy`,
  `shop_sell` wrappers. Edits change the grid/books without saving. The next
  normal morning autosave persists the latest items, including CLOSED edits.
- One `shop` provider stores the editor snapshot. Its restore callback decodes
  an isolated layout and holds it until `load_game` succeeds and the saved
  phase is MORNING; only then does startup rebuild the restaurant and rebind
  its presentation, stock, clock and customer RNG. Provider failure follows
  the existing fresh-game path; SaveSystem is unchanged.
- `RestaurantSim.create(..., allow_blocked_spawns=false)` forwards the opt-in to
  ShopBuilder only for a validated edited layout. Solid furniture covering a
  FLOOR spawn is allowed; wall/outside spawns remain errors. Staff retain the
  existing blocked-start escape behavior.
- Loaded mornings retain the normal day setup: one customer-gap draw from the
  restored RNG, stock top-up, ledger prune and autosave. Missing old-save `shop`
  sections use the authored layout. Non-MORNING saves remain unsupported.

### 2.3d Menu and prices (FK-030)
- `MenuSettings(cookable_recipes)` owns per-shop enabled dishes and prices. The
  session injects Tier 1 recipes whose station types are present, with a usable
  fridge/pass definition. Temporary stock shortages and path warnings do not
  silently remove a chosen dish. At least one dish remains enabled.
- `RestaurantSim.prices: Dictionary[StringName, int]` stores overrides;
  `price_of(recipe)` falls back to the immutable `RecipeDef.standard_price`.
  Orders capture that price once, so later settings never reprice a ticket.
- At order time an above-standard price has refusal probability
  `clamp((price / standard - 1) * price_sensitivity, 0, max_price_walkout)`.
  The `EconomyTuning` defaults are 1.5 and 0.9. The guest uses its private RNG
  only when the chance is positive: standard/cheaper menus preserve the existing
  random stream. Refusal creates no ticket and gives `too_expensive` as a readable
  departure reason. Balance values are bounded safely; a zero standard avoids
  division and cannot be marked up through MenuSettings.
- The HUD Menu button and MenuPanel requests are MORNING-only. Main's
  `menu_set_enabled`, `menu_set_price` apply accepted model changes to the sim,
  then refresh the request-only panel without saving. Whole-dollar prices clamp
  to ceil(50%) through 200% of standard. Shared recipe resources never change.
- The `menu` save section contains enabled IDs and every cookable ID's
  price as a decimal string. The strict model decoder validates all choices
  in a pure provider against the staged shop layout. Installation waits for
  normal `load_game` success; missing old-save menu sections use defaults.
  Provider rejection retains SaveSystem's FAILED/fresh-game behavior, with no
  semantic backup fallback or all-provider rollback. Only the next startup
  autosave is skipped after a failed load, as before.
- Restored menu choices are installed before normal MORNING day setup, stock
  top-up, ledger prune and autosave. Future reorder settings must also restore
  before that purchasing boundary. Menu edits change no books, clock or RNG;
  the next morning's autosave captures the latest choices, just like furniture
  edits. Changing the menu never writes the current morning's save or bypasses
  the skipped startup autosave after a failed load.
- `tools/balance_probe.gd --price=1.25` now changes only sim price overrides.
  `tools/screenshot.sh --menu --speed=0 --frames=12` requests the production
  morning panel, verifies its actual visible state and captures after drawing;
  no workflow or renderer setting is changed by the option.

### 2.3e Build controls (FK-032)
- `src/build/build_mode.gd` is a typed `RefCounted` interaction controller.
  It reads `ShopEditor` checks and commits only through Main's shop wrappers.
- Main owns one input route. B or the HUD toggle enters only in MORNING/CLOSED;
  active build input takes precedence over ordinary selection and service keys.
- Pick-up preserves the clicked tile's offset from the item's origin. Hover and
  each click use the actual Camera3D floor ray, including during camera smoothing.
- R cycles world quarter turns. Click commits a valid preview; Delete sells only
  a held MOVE item. Esc cancels a preview, then exits. Hints show available actions.
- Previews/cancellation never change the grid or books. Placement failures use
  short sentences from `ShopEditor.placement_reason`; path warnings do not block.
- Valid checks supply unreachable IDs (0 for a proposed buy); committed warnings
  use actual IDs and survive invalid proposals, cancellation and exit until fixed.
- Build forces the rendered grid while retaining the G preference; phase changes,
  exit and presentation rebinding cancel previews and restore that preference.
- Build closes Menu and inspection; opening Menu exits build. GUI controls consume
  their clicks. Content-sized hints/catalogue use bounded scrolling when needed.
- CLOSED edits hide the report; exit rebuilds it without recharging or day setup.
- Sale results/books are authoritative; shared HUD feedback retains its same-frame
  coalescing and zero suppression. Only the existing morning boundary autosaves.

### 2.3f Staff roster and hiring (FK-037)
- `StaffMember` records a stable ID, name, cook/server role, skill, daily wage
  and trait. `data/staff/traits.tres` authors the starter people, candidate names
  and four trait effects. `EconomyTuning.staff_wage_curve` scales the existing
  default role wages by skill; the starting skill-3 Steady team still costs $55.
- `StaffRoster` owns copied members/candidates, role minimums and the six-person
  cap (the owner is separate). `draw_candidates(day, rng)` draws three only when
  the day changes. Its versioned decoder validates the complete roster and pool
  before installation; the saved candidate day retains depleted morning pools
  without another draw. Only `GameState.rng(&"hiring")` supplies session draws.
- `RestaurantSim.create` appends optional roster and catalogue arguments after
  the existing seven arguments. Omitted choices preserve cook/server/owner
  order and defaults. MORNING `set_staff_roster` keeps retained agents and the
  exact owner, adds hires at their role's spawn and removes departures through
  normal task/reservation cleanup. Several people may share a spawn.
- Quick changes walking by its data multiplier once. Its opt-in movement carries
  baseline-tick credit across cells: the existing neutral cadence is four ticks
  per straight edge and six per diagonal at speed 0.25. Scaling that quantized
  time (rather than only Quick's geometric distance) preserves every neutral
  tick and avoids an unintended 18% diagonal arrival advantage. Residual credit
  converts using the next edge's own cost; final arrival, blocking and path
  resets never bank extra movement. The neutral movement body is unchanged.
  Careful adds the actual
  completing cook's quality bonus before the normal clamp. Cheerful extends a
  guest's food-patience budget when that server takes an accepted order, inside
  the existing replay guard. Steady and the owner retain neutral values. Work
  speed, queue patience, elapsed waiting and guest RNG draws are unchanged.
- Each new candidate pool samples names without replacement from the authored
  list, skipping team names case-insensitively. Same-day saved pools, including
  legacy duplicate names, remain intact and draw no new random values.
- The HUD Staff button and request-only `StaffPanel` use MORNING commands
  `staff_hire`/`staff_let_go`. They spend no cash, draw no RNG and never save.
  Closing charges each live employee's own wage, excluding the owner.
- Main stages a `staff` provider alongside shop/menu/owner; installation waits
  for the complete successful MORNING load, even without a shop section. Old
  saves get the starter team. Candidates are prepared before the one normal
  morning autosave; hiring changes wait until the next morning to persist.
- Manual balance comparison: run `tools/balance_probe.gd` with `--seed=1`,
  `--seed=7`, `--seed=42`, first normally and then with `--extra-cook=4`. This
  explicit scenario adds a Steady cook and their wage, without altering tasks
  or supplies. It is not called by CI. `--staff --speed=0 --frames=12` captures
  the genuine Staff panel and native row/model metadata after drawing; the
  existing visual job adds one image. Runtime/balance evidence is separate
  from source review.

### 2.3a Guest reviews and reputation (FK-048)
- `ReputationBook` holds the newest 30 scores. A new shop starts with five
  virtual three-star reviews, so its displayed average is 3.0; those starters
  leave the window in first-in-first-out order as real reviews arrive. Only
  sampled, non-closing departures enter the window. The public daily rows carry
  stars and a friendly quote, never an internal cause name.
- `ReviewVisit` snapshots a guest's served state, queue and food waits as
  fractions of their patience, their paid price divided by the standard menu
  price, and a dirt fraction. Until FK-044 cleanliness lands, the dirt input is
  zero. An unserved guest gives one star; closing departures give no review.
  For a served guest, the score is `clamp(round(5 - penalty), 1, 5)`, where the
  penalty is the sum of each input clamped to 0..1 times its authored weight.
  `data/balance/reviews.tres` starts with queue 1.0, food 1.3, overprice 0.8,
  and dirt 0.6. The largest weighted penalty chooses the complaint group;
  otherwise the visit uses a positive quote. `data/reviews/quotes.tres` holds
  the grouped lines.
- A separate saved `GameState.rng(&"reviews")` stream draws the 50% chance and
  quote. Neither reviews nor quotes consume customer, kitchen or hiring draws.
  The 0.8x-at-one-star to 1.2x-at-five-stars arrival curve is linear in the
  authored resource. Main samples it once before `sim.start_day()` schedules
  the first guest, scaling the base min/max arrival gaps inversely. Reviews
  earned during service update the HUD but do not change that day's gaps.
- Main stages the versioned `reviews` save section and installs it only after a
  successful full morning load. Missing sections in older saves start at the
  five virtual reviews. A rejected section follows the existing failed-load
  recovery path. The only write remains the normal morning autosave; the
  evening report's review cards and before/after averages are transient. The
  `--report` screenshot uses Main's test-only seed override (seed 1) before
  starting a real, unsaved game, then verifies the closed report's native
  review rows after drawing; ordinary games still choose a wall-clock seed.

### 2.3g Paint and colour slots (FK-042)
- `data/swatches/*.tres` contains twelve named `SwatchDef` resources. `ContentDB`
  validates nonempty unique IDs and names; UI only exposes this curated list.
- `ItemDef.paintable` and its one `body` slot control furniture painting. A
  `PlacedItem.swatch_id` is cosmetic; moving preserves it, removing drops it,
  and buying starts with an empty ID and the authored placeholder colour.
- `ShopEditor` owns whole-room wall and floor IDs plus per-item paint commands.
  Paint is free and phase-independent. Version-1 `shop` snapshots add optional
  swatch IDs; missing, unknown or malformed IDs restore the authored defaults.
  The existing morning autosave writes the section; no action saves immediately.
- Main routes Paint clicks separately from furniture edits, so an open shop can
  be recoloured without moving, buying or selling. The build catalogue's round
  chips show player names in tooltips. Hover previews only change presentation.
  `ShopView` shares one material per swatch across items and walls, and updates
  the existing floor shader's colour parameter. Paint never changes terrain,
  paths, agent decisions, prices, books or random streams.

### 2.4 Save system
- JSON in `user://saves/`, with a `version` field and migration functions per version.
- Only sim state is saved, never nodes. The world is rebuilt from sim state on load.
- `SaveSystem.register(key, capture, restore)` replaces a unique section provider; capture returns a dictionary and restore returns success.
- `save_game(slot)` / `load_game(slot)` return errors. Writes use `.tmp`, move the previous final to `.bak`, then publish to an absent final; loads prefer a valid final or recover a valid backup. This is a recoverable transaction, not a filesystem-atomic Windows overwrite or power-loss durability guarantee (Godot 4.7.2's Windows rename removes an existing destination before moving).
- Missing sections are skipped; `MIGRATIONS` maps each old version to one upgrade step. Clock and GameState register state in `_ready`.
- Autosaves remain morning-only. If startup cannot load an existing slot, it
  starts fresh and skips only the next autosave; later morning saves resume.
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
