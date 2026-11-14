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

**Local player preferences (FK-109):** `SettingsPreferences` owns
`user://settings.cfg` through `ConfigFile`. Audio volumes, UI scale, opening
speed, fullscreen and edge panning are device preferences, not simulation
state. Discrete choices save immediately. Volume sliders preview audio live
and save on release, after 0.5 seconds without another step, or when Settings
closes. This is the issue's narrow exception to `AGENTS.md` rule 9; game state
still uses only the existing morning `SaveSystem` autosave. Missing or invalid
preference files restore the whole default set without touching a game save.
Build's grid choice (`build_grid`, D25 follow-up) is optional in the file, so
an older file without it still loads (grid on).
The test and parse runners disable the default preference file before autoload
reads; settings tests use explicit private `user://` fixtures on every platform.
The HUD gear opens Settings during any day phase and pauses the clock. Closing
restores the previous speed, including pause. Escape closes Settings, dismisses
an active edit/panel/selection first, or opens Settings when none is active.

**Panel scrolling (#497):** every panel (Menu, Staff, Stock, Goals, Property,
the evening report, Settings, the Build catalogue) attaches `PanelScroll`
(`src/ui/panel_scroll.gd`) with its card, its one main scroll area and any
extra area (Menu's dish detail). A wheel notch is always `WHEEL_STEP` (110 px);
a wheel anywhere over the card scrolls the area under it, else the main one;
the helper takes the wheel from each control's `gui_input` before the control
sees it, so sliders and choices never change while scrolling. PgUp/PgDn/
Home/End scroll the open panel unless a text field has focus. Menu, Staff and
Stock keep their card-wide ScrollContainer only as a fallback for very short
windows (150% UI on 1280x720 with HUD notices); it takes the wheel only while
it really overflows. Every panel but the Build catalogue (closed by leaving
Build) has Close at the top right of its header;
the report's Close (and Esc) only hide it; the top bar then shows a Report
button (`HUD.report_requested` -> `Main.show_closed_report`), and the top bar's
Next day goes through `HUD.next_day_requested` -> `Main._on_next_day_pressed`
so the day's history row records the final books. Dropdown popups keep their
own wheel, and page keys are ignored while a dialog or a later panel covers
the card's centre (`PanelScroll.is_covered`).

**Build version and What's new (#433):** `tools/export.sh` stamps every export
before it runs Godot: `build_info/version.txt` (the tag from
`GITHUB_REF_NAME` on a `vX.Y.Z` build, or `FK_VERSION`; any other build such as
a `workflow_dispatch` run is `dev-<short sha>`) and `build_info/release_notes.txt`
(the output of `tools/release_notes.sh <version>`, so a tag build fails if its
CHANGELOG section is missing, and a non-tag build bundles `Unreleased`). Both
are git-ignored, picked up by the presets' `include_filter="build_info/*"` and
removed when the script ends. `BuildInfo` (`src/core/build_info.gd`) reads them
from `res://`: no file means a run from the editor, which reports `dev` and
falls back to the `Unreleased` section of `CHANGELOG.md` for the notes.
`ReleaseNotes` parses the section into groups and puts `### What to test`
first. `WhatsNewPanel` renders it; the title screen opens it once when
`BuildInfo.should_show_whats_new` says the version is a release (`vX.Y.Z`)
that differs from `Preferences.last_seen_version`, then records it. That value
is the optional `last_seen_version` key in `user://settings.cfg`, never the
game save. Dev builds never open the panel by themselves. The title screen and
Settings both have a What's new button, and "All release notes" calls
`OS.shell_open` on the GitHub releases page. Nothing is fetched at runtime.
`bash tools/screenshot.sh --whats-new` captures the panel with a sample release.

1. **The sim is separate from the visuals.** `src/sim/` holds plain data and logic with no nodes. Visual nodes in `world/` read sim state and animate it. This makes the sim unit-testable and lets background properties run without visuals.
2. **Fixed simulation tick** (for example 10 ticks per game second), independent of frame rate. Speed controls change the number of ticks per frame.
3. **Data-driven content.** Recipes, items, themes and properties are custom `Resource` types in `data/`. Adding content means adding a `.tres` file, not code.
4. **Communication goes through `EventBus` signals.** No `get_node("../../..")` chains across systems.
5. **Deterministic randomness:** one seeded `RandomNumberGenerator` per system, held in `GameState`. This makes bugs reproducible.

### 2.3 AI (agents)
- **The sim owns movement.** Pathfinding runs in `src/sim/` on the 0.5 m build grid using `AStarGrid2D` (a `RefCounted`, so no nodes are involved). Agents have a grid position and a path. Visual nodes in `world/` only interpolate between grid points and play animations.
  - Why not `NavigationAgent3D`: it lives in the scene tree. That would break headless tests, determinism and background simulation of other sites (TECH 2.2 rule 1).
  - **Smooth motion (view only, `src/world/motion_smoother.gd`).** Each production frame carries the sim's timed cell-centre movement trace for the latest tick. `MotionSmoother` samples its actual piecewise route at `Clock.tick_fraction()`, including every crossed centre and any terminal hold; several ticks between rendered frames never create a chord through furniture. Walking reaches the actual seat before the seated pose and its authored offset begin. Missing, invalid or explicitly discontinuous traces snap rather than invent a connecting route. Morning resets, a new world and newly admitted actors are explicit transitions, not ordinary service movement. Hand-authored frame fixtures retain their no-trace interpolation contract. Pausing holds the fraction; direct tools/fast-forwards and worlds not driven by the Clock render at alpha 1. Existing facing, crate and carrying presentation stays in the view. Seat/reach/separation offsets are checked against furniture, internal wall edges and every person's final position; rejecting one offset rechecks the group, so a later fallback cannot invalidate an earlier accepted offset. The view never changes simulation movement.
  - **Deterministic traffic (`MovementCoordinator`).** `SimWorld` owns value-only current-cell, next-cell, swept-cell and edge claims. Every neutral, Quick and courier edge must claim its destination and diagonal clearance before travel. Crossed cells remain held until the next tick so a later actor cannot cut through the earlier actor's drawn interval. Actors advance in ID order. Both people in a physically valid cardinal head-on pair keep their reciprocal routes until stable-priority yielding; staggered repath deadlines cannot send both into repeated opposing detours. Physical meals and prepared drinks in hand have priority over other staff, staff over guests, with lower-ID ties; a claimed task or stale tray metadata alone is not carried food. Kitchen confirms a drink's real READY ticket, task ownership and carrying stage through a weak world query; replayed preparation, served and cancelled drinks grant no carry priority. Courier crates use ordinary staff priority.
  - **Cost.** Movement checks stay cheap on busy days: `SimGrid.seat_items_at` keeps a seat index rebuilt only when the grid version changes; `find_path_avoiding` is a binary-heap A* that keeps the old open-list choice and ties exactly; a yield search flood-fills the actor's reachable area once and skips pockets it cannot reach instead of running a failed route for each.
  - **Door lane (#305).** `MovementCoordinator.door_lane()` derives the front-door lane from `grid.entries()`: the entries, the floor cells beside them and the cells just inside those (cached per grid version, no side assumed). A guest still ARRIVING or QUEUED standing in it has traffic priority 0, below every other guest, so a leaver or seat-walker wins the head-on and the stander yields. A QUEUED guest without a bench picks one sticky waiting spot (`CustomerAgent._stand_clear_of_door`, radius `WAIT_SPOT_RADIUS` = 4): the nearest reachable free dining-floor cell that is not lane, not a seat, not any item work cell and not another queued guest's spot. It is re-picked only when it stops being valid, and cleared on requeue (single and party). With no spot (a crowd that has filled them) the guest stays where it is, still at priority 0. Narrow doors (#322): an edited shop can leave a one-cell way in behind the door, with the cells beside it the only waiting spots, so queued guests stand on the only way out and arrivals pack the door cells. While someone on the way out has been stuck for `escape_after_ticks` in the door lane or one step from it (`MovementCoordinator.door_outflow_stalled`), a queued guest still on the street with no bench seat or table yet stays there instead of stepping in (the "let them out first" admission hold only covers a leaver inside the lane, which a lane full of waiting guests never lets happen). A step into the door already begun still finishes: frozen mid-edge, the guest held the door cell the leaver needed (#453). And a cell on the static way out of anyone leaving who has been stuck that long (`on_stalled_exit_way`, the escape route, cached per tick) is not a valid waiting spot (`CustomerAgent._wait_cell_free`): a guest waiting there moves off it, and one the backstop cleared off it does not walk back. Both only act during a stall: the default balance probe is identical, and busier set-ups (bar, coffee shop) shift by a few served guests either way. Counterflow at the door (#459): the stall rules above came too late for a leaver behind a crowd at a one-cell way in (180 to 360 ticks, mostly once waiting guests ran out of patience). Let them out first at a narrow way in (Jared's call: arrivals may take a few seconds longer to come in, but the door never jams): `MovementCoordinator.narrow_way_in()` (cached per grid version) is true when some floor cell of the door lane, if blocked, leaves the entries reaching no floor beyond the lane. While anyone is leaving such a shop (`door_counterflow`, a guest or the inspector anywhere inside), `register_agent` keeps arrivals pending on the street and a queued guest on the street does not step in (`hold_at_door`, used by `CustomerAgent._queue_inside` together with `door_outflow_stalled`). Each hold lasts at most `door_hold_max_ticks`, but the two are timed separately, so an arrival held pending and then queued on the street can wait up to twice that (the street part spends queue patience). A wide door is never held this way, so the default balance probe is identical. A crowd already standing in a doorway when someone starts to leave is passed with three rules; unlike the hold, these apply at any door, wide or narrow. In `_before`, someone leaving goes before a guest still ARRIVING or QUEUED anywhere, ahead of right of way: a stuck arrival's escape had won the head-on, and the leaver stepped back. A boxed-in waiting guest never asks a leaver for a cooperative vacancy in `_wait` (the gap only let the crowd press further in). And a leaver whose step, or the step after it, is in the door lane and whose step cells are held only by waiting guests asks for a squeeze past them (`_counterflow_blockers`): after half of `yield_after_ticks` blocked ticks when every blocker is boxed in (no pocket reachable), otherwise after `yield_after_ticks`, so in an ordinary doorway the waiting guest still steps aside first. The squeeze starts at the next `begin_tick` (`_squeeze_counterflow`, lowest ID first, re-checked) so that both partners advance together, like a backstop squeeze. A leaver gets through a crowd of 6 to 14 in 30 to 130 ticks (walking from the back tables included); squeezing every blocker after half the limit changed the default probe, the boxed-in condition keeps it identical. The café timing golden in `tests/sim/test_order_counter.gd` (a small shop whose door fills with queued guests) was re-recorded: each guest served there leaves as early as before or up to 19 ticks earlier.
  - **Waiting and admission.** `data/balance/movement.tres` authors repath/yield delays and search radii. A blocked actor waits, then tries an actor-aware route and deterministic yielding to a reachable pocket. If a distant crowd prevents a complete avoidance route, it can reconnect around a local blocker to a later vertex of its existing route, retaining the real destination and validating the remaining geometry and seat permissions. Physical step claims still stop it at any distant person. Diagonal clearance checks also identify a person holding either corner when the destination itself is free. An outbound sidestep stays protected while fresh or physically moving; after the authored number of denied attempts it can select another pocket or use the existing cooperative recovery without losing its original goal. If the preferred person has no escape, the waiting person can step aside and briefly hold that pocket for physical progress, bounded by the same authored timeout. Impossible enclosures remain blocked instead of teleporting. A pending birth stays outside active `world.agents`, receives no movement/task/patience ticks, and is retried in ID order. Pending customer visits still participate in party, closing and departure accounting. An idle worker, or a worker waiting for a busy station without holding a lease, can clear another worker’s claimed station to a legal pocket without returning to block that station again; active work, carried food and owner commands keep their existing priority. A genuinely idle employee parks outside the moving worker’s remaining route and retires the completed job’s destination only after reaching that pocket. If the escape is behind the incoming person, the existing cooperative retreat opens a real vacancy before the idle blocker moves through it. Staff morning resets choose distinct legal positions. No traffic decision fetches or draws RNG.
  - **Cancellation and seats.** Cancelling or changing a route mid-edge finishes the current reserved edge before task work or the new goal can advance; it never erases travelled trace segments or reports an intermediate vertex as final arrival. A returning sidestep can re-path or yield again, while productive work stays paused until the actual original goal. Explicit cancellation or a new public destination clears obsolete detour and return intent at a physical vertex; internal and same-goal replanning retains it. An unbooked queued guest can keep waiting on a safe dining-floor pocket after the cooperative hold. Queue searches, patience and seat-walk deadlines continue once per tick during movement recovery, without another physical step or meal work. Shared party queue movement skips reserved stops, including a stop created while choosing a waiting bench. During a detour or reserved stop, existing staff withdrawal, timeout and stuck-task cleanup still runs without claiming new work or advancing productive steps. An idle worker waits to claim a new task while a direct-grid fault covers their actual origin; restoring the floor resumes ordinary claiming without spending a viable task’s retry budget. A direct-grid chaos edit that buries a person or closes a partial edge holds the actual position and claims until the geometry is safe; it does not enable a jump through furniture. Active-service position resets are refused. A physical seat may be projected by both its table and furnishing, but needs a real own reservation and no foreign holder. Empty and foreign seats are not aisles. Guest, bench and staff clearing reservations remain held until the person actually vacates their current/partial-next seat, or is removed/reset. An idle worker steps safely off a cleared seat before releasing it. Rugs and flat floor decor remain walkable.
  - **Liveness backstop (#306).** The local rules above can still lock a crowd: a doorway full of leaving guests and arriving parties, or people who only shuffle (yield, return, yield again) without ever getting closer. `MovementCoordinator._watch_liveness` runs at the end of `begin_tick` during service. Progress means getting closer (octile) to the real goal (a sidestep's return goal; for a leaving guest, any entry), and nothing else resets the count: being swapped back a cell in someone else's squeeze does not. A leaving guest (or the leaving health inspector, treated the same way) is followed even between tries (it drops its path whenever a step is blocked, so it can look arrived), and its escape takes its static route to the nearer street cell (for the inspector, never the door it gave up on); without this a doorway full of leaving guests and an arriving party could shuffle for good without anyone standing still. Someone with a route who has not got closer for `escape_after_ticks` is escaped, one acting escape per tick in a total order (longest stall, then lowest ID), retried every `escape_retry_ticks`; someone mid-edge is skipped and checked again next tick, so a shuffling person never starves the next one in the order. An escape that can change nothing passes the turn on, but at most `MAX_ESCAPE_TRIES_PER_TICK` are searched per tick. When everyone in a leaving person's first step is another leaver ahead in the same line (not a head-on), the escape and its wait are handed to that leaver, up to `MAX_LINE_HAND_ON` times and never twice through the same person, so it reaches the head of the line instead of shuffling the people in it; Each escape route is searched once per liveness pass (`_route_memo`). An escape that starts a squeeze is retried after `SQUEEZE_RETRY_TICKS` instead of `escape_retry_ticks`, so a one-cell corridor with people going both ways drains one swap after another (a corner swap too: in a doorway the way out turns, and on an ordinary retry a leaving line in an edited shop stalled past 600 ticks), and the same two people never swap again within `SQUEEZE_PAIR_COOLDOWN_TICKS`. A hand-off that reaches a head of the line who is mid-step is looked at again next tick but counts as one of that tick's searched tries. When nobody stands in the shortest static route's first step the escape still grants right of way (so a free step contested by a passer-by is won), but holds no way, moves nobody and passes the turn on; it also replaces a stale detour with that route. The exception (#453): the first person further along that route, if they are standing still (settled, arrived, not sidestepping or leaving; a busy worker only past `squeeze_after_ticks`), who would only turn the stalled person back again, is cleared to a pocket off the route in that same escape (`_standing_on_route`, counted as `ahead`); if that first person is moving, leaving or a courier, nobody is cleared. Without it a cook whose short way to its booked coffee machine was blocked by a server waiting for that machine detoured round the counter at each repath, and each retry, landing while it was on the detour, sent it back: the 40-tick loop never lined up with the blocker being in the first step (530 ticks in the coffee-shop soak). A worker waiting for a busy station without a lease that the backstop clears keeps its new spot, as an idle one does, instead of returning to stand in the way. The escape gives them right of way (they win `_before` until the retry, except against food in hand, and nobody else may step into the cells of the step they are waiting for, diagonal corners included, even while one is still occupied; whoever already stands in those cells may still move to clear them, and someone kept out cannot veto that move in ordinary arbitration; only one person holds its way at a time, so two held ways never lock each other, and a newer escape takes it over only once the holder's right of way has lapsed or the newcomer has waited at least as long as the holder has by now) and their static route, and asks whoever holds the first step or its diagonal corners to clear: to the nearest reachable free floor cell off that route (`_pocket_path`: one breadth-first search over the steps they could take now, no radius cap, preferring cells outside the door lane and station work cells and taking one of those only when nothing else is free); or, when boxed, by first clearing each stationary person between them and the nearest free cell (`_push_through`); or by clearing the boxed blocker's neighbours for a later retry. Someone busy where they stand (`_busy_worker`, #458: a worker carrying food, working, waiting in a `WAIT_UNTIL` step or standing on their leased work cell before the work starts; the owner resting on their home spot; the inspector looking something over) is not cleared, pushed through (`_push_through`) or moved as the person ahead before `squeeze_after_ticks`, the same gate as a squeeze, and never moved as a boxed blocker's neighbour: clearing them only sent them straight back to their spot, to be cleared again at the next retry. When everyone in the way is busy like that, the escape squeezes past at once if a squeeze is allowed, as when nobody can go anywhere. An owner helping out counts as staff (idle, they are cleared and keep the new spot). The backstop does not protect a guest at their table the same way: protecting one on the diagonal corner of a doorway step held a leaving line past the 600-tick limit in an edited coffee shop. Someone just standing about (an idle worker, a waiting guest) keeps the new spot; anyone with somewhere to be returns through the ordinary `_resume` path. From `squeeze_after_ticks` (or at once when nobody in the way can go anywhere, such as a leaving guest meeting an arrival in the doorway with only the street behind it) a worker squeezes past a physically stationary guest or the inspector, and a leaving guest or inspector past any stationary non-courier who is not also on the way out (two leavers swapping gets neither closer), unless it is a real head-on (that leaver's own way out runs through the stuck person's cell): both partners swap over one shared cardinal edge in lockstep at the slower ordinary step time, each claiming the other's cell (declared in `snapshot().squeezes`; the movement invariants exempt only the swap edge itself and a seat handed to the partner, and still check the route after the swap; the partner whose turn did not finish the swap holds for the rest of that tick), and `SimAgent.movement_position` bows them to opposite sides (`squeeze_side`) so the view draws them passing. An idle worker who still cannot go anywhere just stays put. From `give_up_after_ticks` a guest who is not already leaving gives up (never the inspector, who has its own visit cap) (`CustomerAgent.give_up_blocked`, reason `no_way_through`, “Couldn't get through” in the evening report) and walks out normally. Every move is a real claimed step; nobody is teleported or removed by the backstop. All four limits live in `data/balance/movement.tres`; `escape_counts` records how often each branch ran (diagnostics only). A stop whose edge never started (an idle busser stepping off a cleaned seat) is dropped after `yield_after_ticks` blocked ticks instead of waiting forever, and that step-off now requires the whole edge, corners included, to be open. Let them out first: while the door is jammed (someone on the way out has been stuck in the door lane for `escape_after_ticks`), `register_agent` keeps a guest arriving from the street pending (outside, holding no cell), for at most `door_hold_max_ticks` and only until the jammed leaver reaches `give_up_after_ticks` (waiting arrivals do not tick, so the hold must end on its own); every lasting doorway crowd in the soak was arrivals stepping into a door full of leavers. A brisk exit never holds anyone up (holding on every leaver cost about 1% of served guests in the balance probe). A guest walking to or from the restroom yields like anyone else; in ordinary yielding (`_yield`, not the backstop) only a guest at their table or inside a stall is protected. `tools/liveness_soak.sh` runs real games (balance-probe set-ups, optional seeded morning edits, optional `--inspector true` for a health inspector visit every open day) and dumps every person plus an ASCII map whenever anyone who wants to move gets no closer to their real goal (the watchdog's own measure, so a yield-return shuffle counts) or stays frozen past a limit; `tests/world/test_movement_liveness_soak.gd` keeps the seeds that used to lock up and also caps `no_way_through` give-ups per case, so sending guests home cannot pass for a fix.
  - **Player placement.** The final `ShopEditor` preview shared by buying, moving, blueprint batches and exact history refuses new solid or seat obstructions on active current/next/swept/corner claims with “Someone is in the way.” Refusal changes no geometry, cash or history stack. This is distinct from direct-grid fault injection used by recovery tests.
  - Diagonal moves are allowed, but corners can't be cut. Furniture marks cells solid, and stations expose "work cells" where a worker stands.
  - **Station approaches.** When an unindexed work step begins, the worker chooses the shortest legal route to an unreserved authored work cell, keeping authored order for ties. A free current cell needs no walk. Explicit work-cell indices and seat steps retain their authored targets; unavailable leases wait, while available but unreachable cells use ordinary task recovery. The selected goal stays fixed for later repaths.
- **Grid API (FK-012, `src/sim/grid/`):**
  - `GridMath`: `CELL_SIZE` 0.5 m. `rotate_cell(cell, footprint, quarter_turns)` turns clockwise seen from above, mapping one turn `(x, y) → (d-1-y, x)`. `rotated_footprint`, `cell_to_world`/`world_to_cell`, `path_cost`. Cell x → world +X, cell y → world +Z, and an unrotated item faces −Y (world −Z).
  - `SimGrid`:
    - `from_ascii(rows)`: `.` floor, `#` wall, `E` street entry, space for outside.
    - `place(footprint, origin, turns, solid, work_cells, seat_cells, def) -> PlacedItem` (or null), with `can_place` returning `PlaceResult`.
    - `remove(id)`, `item(id)`, `item_at(cell)`, `items()` (in placement order), `entries()`, `is_walkable(cell)`.
    - `find_path(a, b) -> Array[Vector2i]` includes both ends and is empty when there is no static route; `find_path_to_any(a, goals)`. Active actors use `MovementCoordinator.route` and `find_path_avoiding`, which apply occupancy, seat permissions and guest room rules without changing shared path layers.
    - `cells_changed(cells)` fires on every walkability change.
  - `PlacedItem`: absolute `cells`, `work_cells` and `seat_cells`. One-agent reservations: `reserve`, `release`, `release_all`, `reserved_by`, `free_work_cell`, `free_seat_cell`.
  - The static `find_path` helper retains its historical blocked-start output through `nearest_walkable`; actors may not execute its non-adjacent escape jump through solid cells. `free_work_cell(item)`/`free_seat_cell(item)` skip reserved and unwalkable cells. `item_removed(item)` fires when an item is removed, and a removed item cannot be reserved.
  - **World view:** Godot's positive `rotation.y` turns counter-clockwise seen from above, so a placed item uses `rotation.y = -quarter_turns * PI / 2`, with its mesh anchored at the rotated footprint's minimum corner.
- **Task board:** stations, tables and orders post tasks (`take_order`, `cook`, `deliver`, `bus_table`, `clean`, `seat`). Each idle agent scores the open tasks: role priority x skill / distance, and claims the best one. Claims are exclusive.
- **Guest urgency (#307):** inside the job tier and deferral rules above, a claim score is multiplied by `1 + weight x urgency`. Urgency (`GuestUrgency`, `CustomerAgent.urgency()`) is the used fraction (0..1) of the patience that applies to that guest: table patience while queued, food patience while ordering or waiting. `take_order`, `cook`, `pour` and `deliver` use `guest_weight` and read the guest(s) behind the task (a batched delivery uses the most impatient of its orders; cook tickets share the fridge, so urgency decides between them and equal urgency keeps posting order); `bus_table` uses the smaller `table_weight` and the most impatient queued guest. Weights live in `data/balance/guest_urgency.tres` (`GuestUrgencyTuning`). Urgency rises every tick, so a far guest ages up and is not starved. Pure reads, no RNG. Seating needs no rule of its own: queued guests try tables in arrival (id) order, which is longest-waiting first (`test_longest_waiting_guest_gets_a_freed_table`). The guest inspector shows "<name> is coming to take my order" / "is bringing my food" from `GuestUrgency.staff_line`.
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
    - `go_to_cell(cell, label)` retains its exact point by default. Ordinary take-order steps also carry candidate service cells and their seat origin: the actual claimant chooses the shortest legal approach when GO starts, retaining the posted point for scoring. Current neighbour, seat, room and edge rules still apply; later repaths keep the selected destination. Serve-across counters keep their exact point.
    - `go_to_work_cell(item_id, index, label)` is an exact rotated work-cell selector (used for the two pass sides). It retains GO_TO_ITEM reservation, busy wait, removal, repath and timeout handling. `work_cell_index = -1` lets ordinary non-seat steps choose the closest legal reachable free authored work cell when GO starts, with stable authored ties; seat steps retain their existing selection.
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
  - `ItemDef.PlacementLayer` defaults to NORMAL; the three rugs use FLOOR_DECOR.
    Each cell permits one item per layer. Floor decor must be non-solid DECOR
    without work or seat cells. It owns no walkability or guest reservation.
    Definition-aware `can_place_def` and commits enforce the same restrictions.
  - `item_at(cell)` returns normal furniture first, then floor decor;
    `item_on_layer` selects one explicitly, and `items_at` returns a detached
    normal-first list. `PlacedItem` retains its layer so moving or removing a
    rug changes only floor coverage, never the furniture object above it.
    The world view discovers both layers after cell changes and retains each
    existing native visual. Owner station dispatch uses NORMAL coverage so a
    rug cannot intercept an external station work cell.
    In idle build mode, Alt-click selects the floor layer explicitly, including
    a rug fully covered by furniture. A floor-layer miss consumes that build
    click; plain picking and an active buy/move ghost keep their existing rules.
  - The existing version-1 shop rows already store definition, pose and paint.
    Layer comes from the definition; both placement orders restore through
    `place_def` without a new field, migration, provider or save point. The
    snapshot item-count ceiling accounts for both layers. Morning/closed edit
    gates and warning-only path policy remain unchanged; this adds no service
    decor exception from the separate lamp issue.
  - `catalogue_visible` defaults true. Small plants keep their IDs, scenes and
    saved placements but opt out of catalogue cards and thumbnail requests;
    hidden items are also excluded from new level-up announcements. The larger
    Potted plant stays available. The old `chair` ID is retained
    with the clearer display name Cushioned chair. A 30-frame thumbnail
    timeout fails only that scene, preserving later queued previews and the
    failed-item guard against blind retries; global renderer/stage failures
    keep their existing separate handling.
  - New games start in the deeper Tier 1 hole-in-the-wall, `data/layouts/tier1_deeper.tres` (#389):
    - kitchen at the top (fridge, prep counter and stove facing down), with seat-free Kitchen/Dining crossings at x=3, x=4 and x=5;
    - the pass at (6,4), worked from (6,3) in the kitchen and (6,5) in the dining room;
    - ten dining rows (5–14): three two-seat tables at (3,8), (7,8) and (11,8), each turned one quarter, with two-cell aisles above (rows 5–6), below (rows 11–12) and between them; rows 13–14 leave room for two more tables at the corners;
    - street entries at (7,16) and (8,16), through the two-cell opening in the front wall at row 15.
  - `tier1_hole_in_the_wall.tres` is the earlier 7-row dining room (16×14, entries at row 13), kept for saves named `tier1_roomier`; `tier1_original.tres` is the first 14×12 shell.
- **Customers and orders (FK-014, `src/sim/restaurant/`):**
  - `RestaurantSim.create(layout, content, seed, errors)` owns `world`, `orders`, the tier-one `menu`, and a seeded `spawner`. It adds a cook and server from the layout spawns.
  - `start_day()` resets `served_today`, `lost_today`, `leave_reasons_today` and the arrival countdown, clears departure tracking, prunes finished orders, runs the overnight tidy (`Kitchen.tidy_overnight()`) and puts every staff member back at its layout spawn with no task; open the world's clock separately. `advance()` runs one world tick, then arrivals and departure cleanup; empty last orders closes the clock. At the CLOSED deadline all remaining guests are removed and recorded that day as `closing`.
  - Final closing counters are ready when `advance()` returns; raw clock phase signals can precede its cleanup sweep.
  - Signals: `customer_arrived(customer)`, `customer_paid(customer, order, amount)`, `customer_left(customer, reason)`. Payment is emitted once at the captured recipe price; there is no economy dependency.
  - `CustomerAgent` extends `SimAgent`: `state`, `table_item_id`, `seat_cell`, `order`, `leave_reason`, `paid`, and `why()`. Reachable seats are reserved in placement order; leaving retains the physical seat lease until the actor vacates it, while removal releases it immediately. Failed seat paths or a 200-tick seat walk release the reservation and retry within the bounded queue budget. A server takes each order through ordinary `TaskStep`s.
  - `queue_patience` (300 ticks), `food_patience` (1200 ticks, including order-taking) and `eat_ticks` (270 ticks, #291) are configurable. Missing food cancels work and tickets. An unreachable exit is logged and forcibly removed after 100 ticks.
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
  A cook waiting at the pass for a clean plate raises an open (unclaimed) wash
  task to priority 3 without deferral (`Kitchen._expedite_wash`, #291), because a
  wash that only runs when the server is otherwise idle leaves the cook, the
  slowest stage of service, stalled. Plating itself takes `Kitchen.PLATING_TICKS` (5).
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
- **Cleanliness (FK-040):** `CleanlinessState` owns one spot per walkable FLOOR
  cell, capped at 12 by `data/balance/cleanliness.tres`; spots never block paths.
  The separate saved `GameState.rng(&"cleanliness")` stream samples a 15% chance
  at a service arrival's street-entry neighbour and a 25% chance at a paid
  eater's departed seat. Ineligible cells and off-service arrivals draw nothing.
  `CleanTaskController` posts one priority-0 `clean_spot` walk-and-mop task per
  eligible spot. Mopping takes 30 work units before skill scaling; terminal
  failures wait for a layout change before reposting. A hired Cleaner owns this
  role; without one, servers and the Floor-mode owner take it only after their
  eligible delivery and bussing work, regardless of distance.
  Before adding their own door spot, each arriving guest retains the current
  dirt fraction and samples both queue and food patience once using
  `1.0 - 0.3 * spots / 12`; later dirt changes do not rescale that visit or
  replace the retained review input.
  The report captures the day's worst Spotless/A bit messy/Grubby band, F3
  shows the current spot count, and ShopView draws shaded, matte floor
  decals with a roughly 0.2-unit radius, using the approved swatch palette.
  The active floor paint and finish's main swatch chooses cream on dark floors
  and dark brown on light floors; a thin ink outline keeps every kind readable.
  `start_day()` tidies all spots and mop tasks before the existing morning
  autosave. Spots themselves are never saved; only the named RNG stream is
  restored by GameState. The optional Cleaner joins the existing roster,
  candidate and next-morning staff-save paths, with a skill-scaled Tier 1
  base wage of $20 versus a server's $25; cook/server minimums still hold.
- **Everyday messes (FK-077):** `data/balance/messes.tres` authors every chance,
  cap and threshold. `RestaurantSim.configure_messes` installs a transient
  `MishapState` sharing the existing cleanliness RNG; no new stream or save
  section is created. While genuinely carrying food, a server rolls once per
  newly entered cell (0.04% normally; Clumsy ×3; extra crowding near the pass
  adds 0.02% per person above the authored threshold, capped at 0.3%). Standing
  still and a zero base chance draw nothing. Drinks are excluded. Pickup
  must finish before any spill rolls, including a reclaimed trip's
  walk back to the pass after the owner changes duties.
  The first carried READY meal spills; other tray meals continue on the same route.
  The original ticket returns to PLACED and follows real ingredient fetching,
  cooking and plating again, retaining the guest's original wait budget and
  price. It never charges a second meal or creates a second guest order.
  A spill enters `CleanlinessState` independently of random dirt's cap;
  one cleaning task clears a cell's dirt, spill and broken fragments together.
  Five percent of spills break one actual owned plate. `PlateLedger.spill_order`
  makes an intact held plate dirty, or removes a broken one from owned stock;
  legacy no-sink service can break a clean/dirty owned plate without an order
  token. Clean + dirty + in use remains equal to the live total, even at zero.
  Main records the authored $2 replacement immediately under **Breakages**.
  Already-paid replacements arrive during overnight tidy, before the existing
  morning autosave, restoring the existing `plates.total` section with no new
  fields or recovery UI. No morning is written with a transient zero total.
  Each completed recipe station step adds one grease use, once per real task
  step even across replay. At 24 uses that station works at 90% of its
  normal work rate (walking, fetching and plating keep their rates).
  `CleanTaskController` posts a priority-0 **Degrease** walk/work task at the
  actual station, with normal reservations; completion clears its grease.
  Cleaning job priorities apply: a dedicated cleaner owns it; without one,
  servers use low-priority Cleaning, then the owner on Floor duty. Off remains
  Off. Terminal failed maintenance waits for a layout change before retrying.
  Uncleaned spills can produce three **Sticky floor** review quotes. The live
  evening report adds a plain **Mishaps** line with spills, broken plates and
  stations degreased; this display text is deliberately absent from historical
  report saves. Overnight withdraws all mess/maintenance tasks and clears floor
  messes, grease and daily counters. The approved Food Kit `plate-broken` model
  marks a broken spill and disappears with its cleaning task.
  Tests: `tests/sim/test_mishaps.gd`, `tests/world/test_mess_view.gd`.
  Manual visual fixture: `tools/messes_review.tscn` (dark/light, one frame each).
- **Debug overlay (F3):** paths, claimed tasks, agent states and the task board, from Phase 1 onward.

- **Hygiene overview (FK-097):** the Build/Buy room readout has a session-local
  Hygiene toggle. `HygieneOverview` reads existing dirty-table holds, floor spots
  and restroom upkeep; it counts used toilets separately from their tidy spots.
  Today's cleanliness is the same worst-so-far label used by the evening report,
  not a new gameplay score. `BuildPreview` tints a detached, deduplicated set of
  problem cells using the existing Clay swatch. The native mesh updates only
  when those cells change and disappears outside Build; no sim, RNG or save
  state changes. The catalogue's shared readout wraps within its bounded panel.
  `bash tools/screenshot.sh --scene=res://tools/hygiene_review.tscn --speed=0
  --frames=12,60 --quarter=2` shows an explicitly staged, unsaved slightly messy
  shop before and after enabling Hygiene (seed 1, one dirty table, two floor
  spots and one toilet needing a tidy).
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
- **Entry screen (FK-058):** `src/ui/title_screen.tscn` is the project startup
  scene. Continue opens `main.tscn` and uses its existing morning-load path;
  New game confirms replacement when an autosave exists, then shares F10's
  `Main.start_fresh_run` reset route. The live, slowly orbiting title backdrop
  uses Main's `display_only` mode: local fixed-seed view initialization only,
  with no session start, save providers, autosave or run RNG draws. Title
  disables Clock processing/input until it leaves. Settings uses the existing
  shared panel and theme; Quit is hidden on web.
- **Quit to title** is available in Menu and also in Settings during service.
  Outside MORNING it pauses for the progress-loss confirmation; Cancel resumes
  the prior speed. Returning never saves. Continue therefore restores the last
  normal morning checkpoint. `main.tscn` stays directly bootable: existing
  screenshot, balance-probe and soak entry points still choose it explicitly,
  so they skip the title without a new flag. `tools/title_review.gd` captures
  the real title in a no-save fixture and verifies unchanged run state.
- `main.tscn` is the game session for one shop. It builds a `RestaurantSim` from the layout and content, and points `sim.stock` at `Economy.stock`.
- `Clock.attach_world(world, sim.advance)` makes every tick run the restaurant (guests, staff, and the kitchen once it lands).
- **Day loop:**
  - **MORNING:** `sim.start_day()`, expired batches are removed (`Stock.expire`), the morning delivery brings the auto-order (the standing order) and any evening orders (see 2.3i and 2.3j), then autosave.
  - **CLOSED:** wages per staff role and rent are charged through the ledger, automatic loans settle, then the evening report shows a `DayReport` built from `Ledger.day_totals` and the sim's counters.
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
- The `owner` save section stores mode, experience and presentation appearance
  through Main's capture and restore methods. `OwnerModeSettings`,
  `OwnerProgress` and `OwnerAppearance` validate each part before installation.
  Like the shop and menu providers, these callbacks belong to the active Main.
  Startup applies the validated mode only after a complete
  successful MORNING load; missing old-save data defaults to rest, and failed
  loads reset it with the existing fresh-game/skip-one-autosave behavior.
  Assignment commands in every phase wait for the next normal MORNING autosave;
  quitting before that checkpoint loses those assignment changes. No service
  snapshot or additional stock purchase is introduced by a service hotkey.
- **Owner appearance (FK-111):** the new-run picker offers all 12 approved
  Mini Characters and an optional name. A fresh interactive run finishes this
  choice before the existing initial `_begin_morning()` checkpoint; Confirm
  never adds a separate save call. The Staff panel can reopen the picker in
  MORNING for a free presentation-only change, saved next morning. Old saves
  without appearance data keep `character-male-a` and "You". ShopView and the
  owner's inspector portrait use the same session-owned choice; simulation
  names, tasks, money and paths are untouched. Random draws only on the explicit
  button, from the separate `owner_appearance` stream. Main with `use_saves=false`,
  headless drivers and `skip_owner_picker` retain the old direct boot and look.
  The row of live previews owns a private World3D with the shared lighting rig.
  `OWNER_REVIEW_STAGE=picker|shop bash tools/screenshot.sh
  --scene=res://tools/owner_character_review.tscn --speed=0 --frames=60`
  captures the picker or a chosen owner with saves disabled and seed 1.
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
- `to_dict()` returns version 2 (FK-070 added `walls`) and stable `items` records containing `def_id`,
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

### Seafood content (FK-076)
- Five level-gated food recipes form a data-defined seafood branch: Fries →
  Fish & chips (level 2) → Salmon maki (4), and Tomato soup → Mussels in
  broth (3) → Shrimp skewer (4) → Seafood stew (5). The first uses prep and
  fryer, maki uses prep, mussels/skewer use the stove, and stew uses prep
  then stove. Sections and `seafood` theme tags live in recipe resources.
- Fish fillet and shrimp use freezer storage, mussels and lemon use the
  fridge, and rice uses dry storage. All five have station-only reorder
  targets, so the existing menu-use projection buys them only while a
  selected dish needs them. Starting menus, default orders and save formats
  are unchanged; levels make foods selectable without enabling them.
- Deck planks is a level-4 floor resource using the existing `PLANKS`
  pattern, Slate Blue boards and Cream seams, priced at $3 a tile. It adds
  no shader branch, texture or pattern number and carries the `seafood` tag.
- **Model support.** The approved Food Kit contains `fish` and `fries`,
  `mussel-open`, `bowl-broth`, `maki-salmon`, `skewer` and `pot-stew`.
  Maki has a direct match. Fish & chips and mussels in broth have matching
  components but no composed whole-dish model; there is no shrimp-specific
  skewer or seafood-specific stew model. Current recipes have no per-dish
  render binding (food-on-plates is FK-054/#99), so this data-only change
  creates no renderer, speculative scene metadata, substituted art or new
  model. Those fitting kit parts remain available to the food presentation
  work; whole-dish gaps are disclosed rather than claiming new visuals.
- `tools/seafood_review.tscn` is an explicit unsaved capture fixture with
  seed 126, $2,000 extra funds and owner level 5. Run it through
  `tools/screenshot.sh --scene=res://tools/seafood_review.tscn --speed=0
  --frames=30` with `SEAFOOD_REVIEW_STAGE=floor` or `menu`. It uses normal
  purchase/menu/floor commands and shows the furnished Deck planks room or
  selected seafood stew details. No service, stock grant or save is faked.

### 2.3d Menu and prices (FK-030)
- **Today's special (#330):** `DailySpecial` holds one enabled recipe for the
  current day. Main accepts morning requests without saving or drawing RNG;
  its optional registered section joins the existing morning checkpoint.
  Re-entering the same morning retains the selection; the next morning clears
  it. Restore validates against the staged menu and day before installation;
  saves without the section have no special. Discount and pull live in the
  existing menu tuning resource. Tickets capture the discounted player price,
  rounded to whole dollars. The primary order keeps its ordinary private
  choice first, then draws the special pull only when that recipe is available;
  booking, regular-favourite and critic preferences still run afterward.
  Menu, board and service HUD show the accepted choice. The detached report
  keeps its name and paid sales count after tomorrow's selection is cleared.
- **Live menu boards (FK-086 remainder):** each placed `menu_board` keeps a
  section choice in `WallDecor.Hung.menu_section` (`-1`: first nonempty section).
  The inspector changes it through `ShopEditor.set_menu_board_section`; its
  optional fifth wall-item save field joins the existing morning shop autosave.
  Legacy four-field rows keep automatic selection. Rehang, removal and undo keep
  each board's choice. `MenuBoardText` draws the restaurant name, section and up
  to four enabled dishes with the shared theme font, bounded to the existing
  chalkboard face; accepted menu/name changes refresh placed boards.
  `MenuThemeText` gives the Menu panel's read-out using the existing known-tag
  votes and labels. A dish can count toward several themes, so percentages can
  total over 100%; this display adds no variety/focus bonus or simulation change.
- **Menu identity (FK-086a):** `MenuSettings` owns a trimmed 1–24 character
  restaurant name. The morning request updates the HUD and view-only entrance
  sign; `DayReport` snapshots it for the report and its review heading. Reviews'
  stars, quote selection and RNG are unchanged. Terrain/world rebuilds retain the
  sign name; text uses the existing UI font and follows its supporting wall's
  cutaway visibility. No item, collision or Vibe input is added by the sign.
- Recipes author a `RecipeDef.Section` (Starters, Mains, Sides, Drinks, Desserts).
  The panel groups its rows by section; simulation recipe order remains lexical.
  `data/balance/menu.tres` gives six menu slots initially, one more every two
  owner levels, capped at twelve. Enabling or restoring too many dishes fails
  atomically, while raising the level never changes the player's chosen dishes.
- The menu snapshot is now `{version: 1, name, enabled, prices}`. The strict
  decoder also accepts the old two-key `{enabled, prices}` shape with the default
  name. All name/menu changes remain memory-only until the normal next-morning
  autosave. The #161(b) tree links recipes through `RecipeDef.unlock_from`. The
  existing owner-level gate is the unlock cost: learning is automatic by level,
  and content validation rejects unknown/cyclic links and later-level parents.
  It adds no points, selected-dish state or unlock flags to the save.
- The request-only Menu tree displays every definition, including missing
  equipment, while `MenuSettings` still owns the cookable catalogue, prices,
  toggles and size limit. Selecting a tree node shows one dish's details.
  Requirements reuse #183's reachable-station scan and #156's actual stock,
  aggregating repeated ingredient units. Missing equipment does not become
  a purchasable dish, and a short stock is a red preparation warning rather
  than a new menu rule (opening's normal top-up still supplies the menu).
- Quality stars project the last service's delivered `Order.quality` samples;
  a transient Main cache survives the next morning's ticket pruning. It is
  not saved: a fresh load or an unsampled dish explicitly shows recipe base
  quality instead. The separate review line is labelled shop-wide, because
  current reviews do not retain dish IDs. No review scoring or quote/RNG logic
  is changed; the paired default probe remains an acceptance gate. Menu boards
  and menu bonuses remain later slices.
- `MenuSettings(cookable_recipes)` owns per-shop enabled dishes and prices. The
  session injects Tier 1 recipes whose station types are present, with a usable
  fridge/pass definition. Temporary stock shortages and path warnings do not
  silently remove a chosen dish. At least one dish remains enabled.
- `RestaurantSim.prices: Dictionary[StringName, int]` stores overrides;
  `price_of(recipe)` falls back to the immutable `RecipeDef.standard_price`.
  Orders capture that price once, so later settings never reprice a ticket.
- At order time an above-standard price has refusal probability
  `clamp(max(price / standard - 1, 0) / budget * price_sensitivity, 0, max_price_walkout)`.
  Every type accepts standard or cheaper prices. Regular's budget multiplier
  is 1.0, preserving its existing formula.
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
- **Menu access (FK-100).** `MenuAccess` shares the live station scan with
  isolated furniture, wall and Expand previews. Enabled dishes that would lose
  their last reachable station are named on the existing amber advice line,
  alongside the restock budget. A new edit that would leave no unlocked dish
  cookable is refused; `Exact` undo/redo keeps its accepted-layout exemption.
  Existing structural cut-off guards still apply, with the dish advice retained
  on their refused previews. Rooms, finishes and wall decor do not run this
  topology check. Opening names dishes that left the menu during the morning;
  restoring access removes them from the note. This memory is day-local and
  never saved. A previously broken layout explains its empty catalogue and
  disables the HUD's Open shop button until access is repaired.
- Valid checks supply unreachable IDs (0 for a proposed buy); committed warnings
  use actual IDs and survive invalid proposals, cancellation and exit until fixed.
- Build shows its own grid choice (`CameraRig.build_grid_visible`, on by
  default) while retaining the G preference used elsewhere; phase changes, exit
  and presentation rebinding cancel previews and restore that preference. In
  Build, G or the Build bar's Grid button (`BuildCatalogue.grid_requested`)
  flips Build's grid and remembers it per viewer in `Preferences.build_grid`
  (never in the shop save); Paint hides the button and keeps the G choice.
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
- `StaffActivity` observes existing claims at the start of each OPEN tick,
  including the final tick before last orders. Travel and station waits count
  as busy; task selection, movement and random streams are unchanged. Employee
  rows pool busy person-ticks over open person-ticks by their primary role.
  The owner has a separate row covering assigned open hours only.
- Closing copies these counts into optional `DayReport.staff_activity` display
  data. The next morning resets live counters while `StaffPanel` retains a
  detached last-service summary in memory. No save provider or save point is
  added; historical reports without observations remain unknown, not 0% busy.
- `data/balance/staff_advice.tres` authors the high/low busy thresholds and
  minimum waiting/table losses. Advice checks cooks, servers, then spare team
  capacity in that order, using unrounded ratios; `StaffAdviceText` owns the
  shared wording and display rounding. Waiting losses are a staffing heuristic,
  not proof of which task delayed a guest. The ordinary balance probe output
  stays unchanged; opt-in daily report snapshots add the activity field.
- Quick changes walking by its data multiplier once. Its opt-in movement carries
  baseline-tick credit across cells: the existing neutral cadence is four ticks
  per straight edge and six per diagonal at speed 0.25. Scaling that quantized
  time (rather than only Quick's geometric distance) preserves uncontested neutral
  cadence and avoids an unintended 18% diagonal arrival advantage. Residual credit
  converts using the next edge's own cost; arrival and blocking never bank extra
  movement. Mid-edge cancellation now finishes its reserved physical edge before
  stopping or taking the deferred goal; traffic waiting applies to both speeds.
  Careful adds the actual
  completing cook's quality bonus before the normal clamp. Cheerful extends a
  guest's food-patience budget when that server takes an accepted order, inside
  the existing replay guard. Steady and the owner retain neutral values. Work
  speed, queue patience, elapsed waiting and guest RNG draws are unchanged.
- Each new candidate pool samples names without replacement from the authored
  list, skipping team names case-insensitively. Same-day saved pools, including
  legacy duplicate names, remain intact and draw no new random values.
- The HUD Staff button and request-only `StaffPanel` remain reachable in every
  day phase for job priorities. Hiring, letting staff go, raises and tray
  upgrades still use their existing MORNING-only commands. These requests
  draw no RNG and never save; ordinary tray purchases retain their ledger cost.
  Closing charges each live employee's own wage, excluding the owner.
  Trait descriptions use authored role overrides: only cooks see Careful's
  meal-quality bonus and only servers see Cheerful's food-patience bonus.
  Other roles see neutral wording without an implied gameplay bonus.
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

#### Staff job priorities (FK-044)
- `StaffJobPriorities.TASK_JOBS` is the single selection mapping: cook to
  Cooking; take-order and delivery to Serving; table clearing to Bussing;
  plate washing to Washing; floor mopping to Cleaning; putting a delivery
  away (FK-099) to Cleaning, with one role exception in `ROLE_TASK_JOBS`: a
  server does it as Serving (`job_for_task(kind, role)`). High, Normal, Low and
  Off choose work rather than changing its duration, skill or pay. A role's
  main job cannot be Off; work outside its existing capabilities stays Off.
- Defaults keep a cook's Cooking and a cleaner's Cleaning High. Servers keep
  Serving, Bussing and Washing Normal, with Cleaning Low. The existing rule
  still makes server mopping unavailable while a dedicated cleaner is on the
  team. The panel explains that conditional availability without discarding
  the server's saved fallback choice. The owner's task policy is unchanged.
- Idle employees select the highest available job level, then use the old
  score and task-ID order within that level. Existing urgency deferral applies
  within the selected level. Off work is never claimed. Unknown synthetic
  task kinds preserve the legacy neutral level for existing test/agent APIs.
- Each staff-section member and candidate row adds a complete `priorities`
  dictionary. Missing legacy rows receive role defaults. Malformed, unknown
  or forbidden values reject the whole roster before installation. Roster and
  member copy APIs detach choices; `StaffRoster.copy()` also retains staged
  service XP, which is deliberately absent from the morning save format.
- Main's any-phase `staff_set_job_priority` stages that runtime copy, applies
  validated choices to the same existing live employee, and installs the
  staged roster only on success. It never reinstalls staff, interrupts work,
  resets paths/reservations/skills, settles XP, draws RNG or performs an action
  save. The existing next-morning staff provider persists the choices.
- The shared-theme grid keeps native cells stable across refreshes and emits
  typed requests only. Cells show words and colours; main jobs skip Off, and
  unsupported jobs show a noninteractive faded dash on a flat cell (the
  panel fill, a faint muted outline, Button text at reduced alpha), unlike
  Low's muted fill. A supported job chosen Off retains its distinct
  inverted style. The main-job lock is explained below the grid, which now
  follows the member cards. XP rows preserve shared HBox spacing and include
  a trailing inset before the scrollbar. Other staffing actions keep
  their morning gates even when this panel is open during service. Opening
  Staff at closing hides the evening report; closing Staff rebuilds that
  report without settling the day's books again. The report's full-window
  root lets clicks outside its card reach the HUD; its card controls still
  consume their own input.
- Tests cover selection tiers, real in-flight work, strict legacy/JSON roster
  restore, detached pending XP and next-morning persistence. The golden test
  compares actual five-day Main sessions for seeds 1, 7 and 42 with the frozen
  pre-feature picker, retaining reports, books, stock, roster, named RNG and
  full task-event traces. Those assertions are runtime evidence only after
  the existing `tools/check.sh` suite actually passes; source review is not a
  substitute. The unchanged `--staff --speed=0 --frames=12` capture provides
  morning grid pixels, not service interaction or occupied-seat evidence.
  Read-only native evidence records the actual disabled style/font state and
  the lock note's text, flags and bounds. Validation rejects stale Off labels
  on unavailable jobs, mismatched role/palette/override state, missing notes,
  viewport clipping and fabricated minimum-size origins; it never edits the
  roster or moves the scene to make a capture pass.

### 2.3a Guest reviews and reputation (FK-048)
- `ReputationBook` holds the newest 30 scores. A new shop starts with five
  virtual three-star reviews, so its displayed average is 3.0; those starters
  leave the window in first-in-first-out order as real reviews arrive. Only
  sampled, non-closing departures enter the window. The public daily rows carry
  stars and a friendly quote, never an internal cause name.
- `ReviewVisit` snapshots a guest's served state, queue and food waits as
  fractions of their patience, their paid price divided by the standard menu
  price, and the dirt fraction retained on the customer before their own
  arrival spot. Departure passes that retained fraction to `review_visit`, so
  mopping or later dirt cannot change the floor that guest saw. Legacy visits
  without cleanliness retain zero dirt. An unserved guest gives one star;
  closing departures give no review. The optional raw ambience bonus is also
  retained on arrival, so a later redesign cannot change that guest's term.
  For a served guest, the score is `round(clamp(5 - penalty + vibe_bonus + quality_bonus, 1, 5))`, where the
  penalty is the sum of each input clamped to 0..1 times its authored weight.
  `data/balance/reviews.tres` starts with queue 1.0, food 1.3, overprice 0.8,
  and dirt 0.6. Final ratings of four or five, or visits without a substantial
  complaint, use the existing positive-quote policy. Otherwise the largest
  weighted penalty chooses the complaint group with the same stable ties.
  `data/reviews/quotes.tres` holds
  the grouped lines.
- A separate saved `GameState.rng(&"reviews")` stream draws the 50% chance and
  quote, with the type's review-chance multiplier applied before the draw.
  Neither reviews nor quotes consume customer, kitchen or hiring draws.
  Demand growth (FK-120 below) replaces Main's former reputation-only gap
  division. Reviews earned during service update the HUD; reputation joins
  demand at the next morning's latch.
- Main stages the versioned `reviews` save section and installs it only after a
  successful full morning load. Missing sections in older saves start at the
  five virtual reviews. A rejected section follows the existing failed-load
  recovery path. The only write remains the normal morning autosave; the
  evening report's review cards and before/after averages are transient. The
  `--report` screenshot uses Main's test-only seed override (seed 1) before
  starting a real, unsaved game, then verifies the closed report's native
  review rows after drawing; ordinary games still choose a wall-clock seed.

### 2.3b Owner experience and unlocks (FK-049)
- `OwnerProgress` earns the authored `data/balance/progression.tres` rates at
  `RestaurantSim.service_closed`, after wages and rent enter the day ledger:
  two XP per happy departure, one per complete $10 of positive daily profit,
  and three per sampled five-star review. Its `last_awarded_day` guard prevents
  a second award for the same closing day. Level N starts at
  `ceil(level_base * N^level_exponent)` total XP (level one starts at zero);
  both values are authored in the tuning resource. The initial base 24 and
  exponent 2.0 set levels two, three and six at 96, 216 and 864 total XP.
  The 25-day seed-1/7/42 pacing probe remains pending.
- `RecipeDef` and `ItemDef` author `unlock_level`, defaulting to one. Tomato
  soup, grilled cheese and burger stay available initially; Tomato melt and
  new potted-plant purchases unlock at level two. `MenuSettings` rejects a
  locked recipe even on a direct call, while `ShopEditor` rejects a locked
  purchase before it reaches the books. Existing placed plants remain movable
  and sellable. The menu and catalogue still show locked entries in muted
  text with the level needed; unlocking never silently adds a dish to today's
  selected menu.
- Main stores progress inside its existing `owner` save section alongside
  the mode. Mode-only older saves start at level one with zero XP. A present
  progress snapshot is validated before installation; a malformed section
  takes the usual failed-load path. The sole write remains the next normal
  morning autosave. The evening XP breakdown, level-up notice and unlocked
  names are transient report data. `tools/balance_probe.sh` reports final XP,
  final level and the first days reaching levels two, three and six; it is a
  manual tool, not an added CI job.

### 2.3g Paint and colour slots (FK-042, #431)
- `data/swatches/*.tres` contains forty named `SwatchDef` resources (the original
  twelve keep their ids, names, colours and tags). Each has a `family` (neutral,
  pastel, bright, deep, wood, metal: `SwatchDef.FAMILIES`) and a `family_order`;
  `ContentDB.palette()` is that order (the Paint grid, the Floors and Wall finish
  colour rows), while `swatches()` stays sorted by id (the floor shader palette,
  now 48 entries). `ContentDB` validates nonempty unique IDs, names and known
  families; UI only exposes this curated list.
- **Paint slots (#431).** `ItemDef.paint_slots` lists up to three
  `PaintSlotDef` sub-resources (id, player name, imported surface names, default
  `PaintFinish` material). The first is the main slot; empty `surfaces` there
  means the wrapper scene's `body_material_names`. An item without authored slots
  has one derived "Body" slot (`ItemDef.slots()`), so unchanged content paints as
  before. `PlacedItem.swatch_id` stays the main slot's colour, so the vibe and
  every older reader are untouched; `PlacedItem.paint` (`PaintLook`) holds a
  material per slot (absent: the slot's default) and the other slots' colours
  (absent: the kit colour). `ShopEditor.paint_slot`, `set_item_look`,
  `look_fits` and `items_alike_in_room` (Shift: same definition, same connected
  room) are free at any phase; `ShopEditHistory.paint_slot` / `apply_look`
  record one `ITEM_LOOK` step for any number of items while editing is
  allowed. Buys, sales, look changes and blueprints copy the whole look.
- **Materials.** `PaintFinish` ids: `painted`, `wood`, `fabric`, `metal`.
  `PaintMaterials` (view) configures a duplicate of the kit surface material:
  Paint is the legacy flat `albedo_color`; Wood, Fabric and Metal add a light
  64-pixel pattern drawn from integer hashes (deterministic, shared texture)
  in object-space triplanar mapping, plus their roughness (Metal: low metallic
  and high specular, since the Compatibility renderer has no reflections).
  `albedo_color` is always the swatch colour. `PropView.set_slot_paint` layers
  kit material, rest tint, look recipe, then each painted slot, and restores
  only the surfaces it touched (an aquarium's cloudy glass stays its own).
  `ShopView.flat_body_only` sends unpainted items and a flat body coat down
  the unchanged `set_body_tint` path, so older shops render exactly as before.
- **Save.** Version-9 `shop` item rows gain `"paint": [[slot, material, swatch],
  ...]` (sorted, main colour still in `swatch_id`); no version bump. A row
  without `"paint"` is from before slots: `PaintLook.legacy` pins a painted main
  slot to `painted`, so its flat coat does not become the new wood default.
  Unknown slots, materials, colours and malformed rows are skipped. Blueprint
  rows (library and `FK1:` codes) carry the same optional `"paint"` key, written
  whenever the piece is painted, with the same legacy rule. Older builds can
  read such saves and libraries (they ignore the key), but their strict code
  decoder refuses an `FK1:` code whose rows carry `"paint"` (six keys, one
  more nesting level), so a painted blueprint's code only pastes into this
  build or newer. Saves and codes both cap paint rows at `PaintLook.MAX_ROWS`
  (8): a save truncates, a code is refused.
- `PaintMaterials.shared` keeps one painted copy per (kit source material,
  colour, material) for every item, capped at 1024 and cleared when the shop
  view leaves the tree; `ShopView._apply_paint` redraws only previewed items
  and items whose look changed, and drops a hover whose item is gone.
- **UI.** Paint shows a Part row (the hovered item's slot names with their
  colours, plus Original, which resets a part, wall or floor), a Material row
  (Auto + the four, with pattern chips) and the palette as an 8-wide grid, one
  family a row. A part an item lacks paints its main slot. Hovering previews the
  brush on that part (`ShopView.preview_slot_paint`); Shift previews and paints
  every piece of that kind in the room. Alt-click, or the Copy look button
  (some Linux window managers take Alt-click), copies a piece's look; clicks
  then paste it (part by part onto other kinds, `PaintLook.mapped`). `--paint-slots` (screenshot.sh) captures
  the panel and a painted room up close.
- `ItemDef.paintable` and its main slot control furniture painting. A
  `PlacedItem.swatch_id` is cosmetic; moving preserves it, removing drops it,
  and buying starts with an empty ID and the authored placeholder colour.
- `ShopEditor` owns whole-room wall and floor IDs plus per-item paint commands.
  Paint is free and phase-independent. Since D25 a floor click in Paint
  recolours the connected floor of one look within its room (Shift: the room) instead of the
  whole floor; the whole-floor ID is the default colour (see Floor types). Version-1 `shop` snapshots add optional
  swatch IDs; missing, unknown or malformed IDs restore the authored defaults.
  The existing morning autosave writes the section; no action saves immediately.
- Main routes Paint clicks separately from furniture edits, so an open shop can
  be recoloured without moving, buying or selling. The build catalogue's round
  chips show player names in tooltips. Hover previews only change presentation.
  `ShopView` shares one material per swatch across items and walls, and updates
  the existing floor shader's colour parameter. Paint never changes terrain,
  paths, agent decisions, prices, books or random streams.

### 2.3h Staff growth and morning raises (FK-051)
- Main connects the live board's `task_completed` signal once and passes each
  finished task to `StaffTaskCredit`. It credits the stable claimant only when
  that claimant is an employee;
  failed, dropped and cancelled tasks and the owner earn no staff XP. The task
  kind maps to cooking, service or cleaning through `data/balance/staff_growth.tres`.
  The same resource sets XP per completed task and the next-level thresholds.
- `StaffGrowth` stages XP during service. At closing, Main charges that day's
  existing wages before `StaffRoster.close_growth_day()` applies staged XP,
  levels each skill up to 5 and queues one raise for each level gained. Morning
  setup flushes any newly completed cleanup XP before serializing or replacing
  the roster; repeating either flush with no new work changes nothing. Direct
  sim drivers can finish cleanup after `service_closed`; the current Clock and
  Main tick drivers still stop at CLOSED. No new cleanup ticking is introduced.
  All earned skills reach live agents next morning, including a server's
  fallback cleaning skill, with the existing work-speed formula unchanged.
- At the next morning Main settles due quits, installs the resulting roster and
  skills, then draws candidates and performs the normal morning autosave. A
  raise offer is read-only until the player accepts or refuses it. Acceptance
  applies `EconomyTuning.staff_wage(role, new_level)` from that day, never below
  the current wage. If pay is already covered, the skill update has one Got it
  acknowledgement; it cannot be refused or lower mood. Refusing an actual pay
  increase lowers mood by one. Mood starts at 3. The last cook or server is
  clamped at mood 1 immediately inside the refusal command, with no due quit;
  other staff reaching 0 schedule a quit for the following morning. The last
  Cleaner remains optional.
  Neither decision adds a save point.
- The versioned growth state is nested in each employee's `staff` record:
  per-skill levels and XP, mood, wage, queued raises and any due quit day. Old
  six-field staff records restore with zero XP and mood 3. The roster decoder
  validates the full snapshot before installation. The Staff panel shows the
  current role's XP and mood, with morning-only raise requests and readable
  departure notices; it does not mutate the roster or save by itself. Morning
  staff notices, including quit messages, are transient and are not saved.
  Reloading after a quit loses its message; that behavior is accepted.
- Provisional pacing data uses 3 XP per cook task, 1 per service task and 8
  per completed floor spot, with thresholds 175/225/275/325. The prior review
  measured starters reaching skill 5 by day 4 for service and day 7 for cooking,
  failing the 4–6-working-day-per-level target. Raising cook XP from 2 to 3
  brings the observed service/cooking XP ratio of about 1.6 toward 1.07, while
  thresholds increase by 2.5 times. Cleaning's weight assumes roughly 0.4 dirt
  opportunities per meal when arrival and paid-meal counts match; differing
  arrival/served ratios, duplicate spots, the spot cap
  and overnight cancellation can change actual completions. These are initial
  tuning hypotheses, not measured corrected pacing or wage profitability.
- The manual 4–6-working-day level-up check uses fixed seeds 1, 7 and 42 with
  the real Main session and no saves. Run
  `bash tools/balance_probe.sh --days=6 --seeds=1,7,42 --setup=default --staff-growth=true`.
  The optional per-member/day trace prints completed-task counts, earned XP,
  skill and residual XP after close, pending requests, mood and wage. Its
  default policy leaves raise requests pending. Compare each starter's first skill-3-to-4 day
  against the target; the aggregate throughput table alone cannot establish
  that timing. The actual run and 4–6-day pacing result remain pending. This
  trace is manual, not a CI job.
- For wage creep, run the feature head manually with
  `bash tools/balance_probe.sh --days=25 --seeds=1,7,42 --setup=default --staff-growth=true --auto-accept-raises=true`.
  This opt-in policy accepts every morning request, including no-pay
  acknowledgements, through Main's real `staff_accept_raise` command before
  opening service. It reports each seed's skill-up days and final wages beside
  the ordinary cumulative wage/profit table. Day-25 closing requests wait for
  the next morning, outside that 25-day window. Compare against an isolated,
  exact main run with the same days/seeds/setup and no feature-only flags;
  paste both outputs with their exact SHAs. Repeat with `--setup=extra_cleaner`
  to check the cleaning hypothesis with a dedicated cleaner. The required
  25-day comparison is UNRUN; accepting every raise must not leave profit below
  main's before this pacing is accepted. No workflow or CI probe loop is added.

### Automatic bank loans (FK-050)
- `LoanAccount` settles once per closing day after wages and rent. Existing
  principal pays daily interest, then positive pre-financing profit repays its
  authored share (whole dollars, at least $1 when a positive share is due),
  capped by both principal and nonnegative cash available after interest.
  Repayment never causes a new advance. An interest shortfall still gets an
  automatic advance rounded up to the borrowing step; new advances start
  interest at the following close. `data/balance/loans.tres` keeps the 5% default
  within the Director's 4–6% range, a 50% repayment share, and $50 step/limit.
- Bank loan is ledger income; loan interest and repayment are costs. All cash
  movements appear separately in the evening report. Its headline and colour
  use `DayReport.operating_profit()`, excluding all three financing categories.
  The existing `profit()` API still returns the full financial cash movement,
  as do `total_income()` and `total_costs()` for their respective sides; this
  preserves ledger-parity callers and historical report decoding. Since #255,
  the headline also substitutes recorded sold-food cost for stock purchases;
  unrecorded historical basis is labelled plainly instead of estimated.
  The five-day invariant independently checks the headline's operating result
  and retains the full financial result's parity with the ledger. Main captures
  operating profit before financing for owner XP, so advances earn no XP and repayments/interest
  do not reduce the operating-profit award. The existing close guard and the
  account's saved `last_settled_day` prevent duplicate settlements.
- An open loan refuses furniture over the authored limit and every tray
  upgrade with "Pay off your bank loan first". `ShopEditBooks` accepts an optional
  read-only refusal callback; old cash-only callers keep their existing text.
  The Staff panel accepts an optional loan-lock hint without changing phase,
  ownership or purchase-order hints. Cheap furniture, ingredients and wages
  keep their existing policies; ordinary purchases never create a loan.
- Economy's existing save section adds `loan` with decimal-string principal and
  last settled day plus boolean `has_borrowed`. Missing old loan sections start
  debt-free. Older loan snapshots without the flag infer prior borrowing from
  positive principal; an already paid-off old snapshot has no recoverable loan
  history and can show the introduction again on its next advance. This state
  persists only at the normal morning autosave; no financial action saves.
- Main sends primitive loan state to the HUD. A text chip uses the existing warm
  theme and joins the native financial group, releasing all width when hidden.
  Its tooltip explains the repayment share and daily interest, using one decimal
  for fractional percentages such as 4.5% and keeping whole rates such as 5%.
  A transient DayReport flag shows the friendly introduction on the first advance, remains
  stable across repeated report builds for that close, and resets next morning.
  The durable borrowing flag prevents later loans from repeating it.
- Loan model, actual Main close/save/load, editor refusal, native HUD bounds,
  report fixtures and the five-day ledger invariant run through the existing
  `tools/check.sh` suite. The pure ten-day forced-loss fixture checks solvency
  and accounting; playable balance and rendered loan-state UI are separate
  review requirements. Int64 charge, shortfall and principal limits reject an
  unrepresentable settlement before any account or ledger mutation.

### Joined dining tables (FK-246)

`DiningSeats` derives components of ordinary TABLE items sharing an entire
unblocked facing edge in one room. Both rectangles must have the same facing
edge span; corners and partial edges do not join. Serve-across counters never
join, and chairs/booths contribute seats without connecting components. The
leader is chosen by geometry (row, column, definition, rotation), independently
of placement order. Only outside seats contribute to a joined component.

`SimGrid` caches detached group/member/seat lookups before geometry or room
notifications. `PlacedItem.seat_cells`, seat links, guest and order table IDs
remain physical. Group reservations validate the whole request before holding
each seat on its physical owner. Editor previews report group capacity and
refuse moving/selling any occupied joined group's member, changing occupied
membership, or orphaning a held seat; cosmetic edits remain available. An
occupied standalone table retains its established sale/undo-removal cancellation
and refund behavior. Relocating it or joining another table onto it is refused. Forced low-level removal
continues to support lifecycle recovery. Groups are derived after load and never
stored; the snapshot version and morning-only save policy are unchanged.

Explicit parties support at most six people. Shipped type ranges and arrival
random draws remain unchanged. Standalone parties of at most four retain the
existing matching order; joined groups and larger parties use deterministic
augmenting-path matching. Bookings share spare seats and capture transient
physical `booked_table_ids`. Before seating, stale topology releases all holds
and paths together. After seating, each person's delivery/payment outcome stays
independent. A real meal departure dirties every original surviving member,
while plate tokens and bus tasks stay on physical tables. New seating waits for
all current members to be clean; existing bus-completion timing is unchanged.

Build previews, hover and Inspect use the same cached component and display
`Seats N (joined table)`. The manual `joined_tables` probe moves two starter
tables and buys two normal chairs for $20, without changing menu/staff/tuning.

### Furniture catalogue and dining seats (FK-071)
- Twenty-five additional item resources use unchanged approved Furniture Kit
  scenes: nine seats, four tables, a counter assembled from bar pieces and
  eleven decor items. Prices, levels 1–6, categories and theme tags remain in
  data. Wood body slots share existing paint; rugs, glass and upholstered parts
  retain their original materials. Benches assemble two unscaled kit seats,
  and the counter uses two bar pieces and an end. Central ArtScale is unchanged.
- `DiningSeats.derive()` stages links from furnishing seat cells to physical
  tables. Authored built-in table seats have priority; every seat of a new
  furnishing must be walkable, unique and face an adjacent table/counter
  footprint. A two-seat bench contributes both links or neither. Item capacity
  continues to describe work/storage capacity, not a dining-seat limit.
- Grid placement, movement, removal and terrain changes install the projection
  before notifications. Retained reservations stay attached to the physical
  table, while lost links release their bookings. Guests order from the table
  rather than treating a chair as a food surface; delivery and dirty-table
  cleanup keep the same physical table ID. Generic non-ItemDef grid fixtures
  retain their existing seat behavior.
- `EditCheck.validate_dining()` rejects new or moved seats without a surface,
  and prevents edits from orphaning previously valid seating. Existing loose
  chairs in older saves can remain while unrelated items are edited. Blocked
  built-in seats and unreachable stations retain warning-only path checks.
  These checks do not enable service-time decor edits; #84's blocking policy
  remains a separate decision. The merged loan purchase-refusal path is kept.
- The catalogue filters its existing native cards into Seating, Tables, Kitchen
  and Decor, preserving purchase requests, unlock checks and button identity.
  `ItemThumbnailCache` queues unique wrapper scenes into one private 96×96
  viewport with a private instance of `lighting_rig.tscn`. Its detached environment
  retains the authored lighting and tone mapping with a transparent clear
  background; it does not alter Main's sky. It copies the real
  frame after drawing, releases the rendered prop and reuses the cached
  texture. A per-item 30-frame limit bounds draw waits; headless tests exercise
  queue and cleanup contracts without claiming rendered thumbnails.
- New seat wrappers expose measured sitting surfaces to PropView. ShopView
  combines that height with central scale and the placed seat's rotation;
  built-in table chairs retain their existing path. Measured planes are source
  geometry evidence, not acceptance of every seated animation or cushion fit.
  Real-Kitchen fixtures exercise bench and bar-stool orders through cooking,
  delivery, payment, bussing and washing with conserved plates and the existing
  4,000-tick test bound. Runtime and visual results belong in the PR evidence.
- `ItemDef.seated_forward_offset` is a view-only displacement in world metres,
  finite and between 0 and 0.05, defaulting to zero. Presentation applies it
  along the authored seat facing before standing-person separation; simulation
  cells, reservations, random streams and save data do not move with it.
  `ItemDef.seated_lean_degrees` separately authors a forward torso pose, finite
  and between 0 and 35 degrees; zero preserves the imported sit pose. The
  presenter's physical furnishing supplies it only after verified seat arrival.
  PersonView keys a private duplicate of the sit clip at the native torso joint,
  leaving root translation, sibling leg joints, shared models and scale alone.
  Changing it re-seeks the same animation time, including while paused. Other
  clips retain their source keys. Head-skinning and native-bake parity caches
  include the applied lean as well as model and animation time. This mechanism
  does not establish a seat's physical fit: authored tuning still requires the
  full surface run, supported hips and actual rendered review.
  No shipped seat uses a lean (Jared, 2026-10-28: leaning "looks pretty
  rough"); the kit seats instead use lowered-backrest meshes derived by
  `tools/derive_seat_backrests.py` (see `docs/ART_STYLE.md` §2). Real-table review additionally seats guests opposite each other at
  cross, glass, cloth and round tables: no head may enter or cross any table
  mesh, and the exact head-to-head separation is reported for visual review.
  A backrest exception never excuses table intrusion. Review images and JSON
  remain external to shipped resources.
  The seated-head probe uses indexed, skinned Mini head surfaces at the shared
  scale: no head vertex may be inside any seat part, and an identified backrest
  must clear the head surface by at least 0.02 m. No seat vertex may be inside
  the closed head surface either (the reverse check catches a thin backrest
  corner wholly inside the head). Made seats also require both
  hips to project onto their named cushion surfaces. Whole-head boxes are for
  framing only. The policy for explicitly named kit failures (after a supported
  trial offset of at most 0.05 m) remains, but its list is empty: every
  catalogue seat must pass. See
  `tools/seated_head_probe.md` for the bounded catalogue and native-pose checks.
- No save section is added. Existing item IDs, positions, turns and swatches
  use the shop snapshot; dining links are derived again from the restored
  layout. The sole persistence boundary stays the normal morning autosave.

### Walls, doorways and windows (FK-070)
- **Edge data.** `SimGrid` stores segments on cell edges, never cells. An edge
  key is `Vector3i(x, y, axis)`: `EDGE_WEST` (0) is the grid line on the west
  side of cell (x, y), `EDGE_NORTH` (1) the line on its north side. Helpers:
  `edge_between(a, b)`, `edge_cells`, `edge_vertices`, `edge_from_vertices`,
  `edges_at_vertex`, `cell_edges`. `set_segment(edge, Segment)` (NONE removes)
  emits `cells_changed` with both cells; `set_segments(changes)` applies a
  batch with one signal and one dining refresh (a dragged run rebuilds
  observers once); `segment_edges()` is sorted; `step_open(a, b)` answers one
  step. Agents also check `step_open` when stepping, a wall edit beside the
  cell an agent is leaving triggers a re-plan, and a buried agent's escape
  never jumps a wall next to it.
  `Segment`: WALL and WINDOW block a step across the edge, DOORWAY does not;
  any segment blocks a diagonal step past its end (no corner cutting past a
  post). Keys are grid-line positions, so they do not care whether a line is
  inside the room or on the outer shell.
- **Pathing.** `EdgeAStar` is an `AStarGrid2D` subclass whose `_compute_cost`
  prices a blocked step at 1e9; `SimGrid` rejects any path that still crosses
  one. It is used only while a path-relevant segment exists (FLOOR/ENTRY on
  both sides), so a shop without interior walls keeps the plain engine search
  and its exact paths (the balance probe is unchanged). `walkable_neighbours`,
  reachability and dining links respect edges. Furniture may not straddle a
  segment or have a wall/window between it and its own work cell
  (`PlaceResult.WALL_IN_WAY`, "A wall is in the way"). Tables may stand flush
  against a wall: a built-in seat across it is dropped (`DiningSeats.WALLED_OFF`),
  as against the shell. A chair across a wall from its table does not link,
  and a wall between a linked chair and its table is refused.
- **Rules (`WallRules`, one place for every refusal sentence).** Interior
  edges (FLOOR both sides) take wall, doorway or window. An outer face (FLOOR,
  then a shell WALL cell with the street, outside or grid border beyond) takes
  a window only, and each side keeps at least one solid face. The street door
  (floor cells beside ENTRY, and door items) is never touched. Both are
  derived from terrain on every check, not stored.
- **Edits.** `ShopEditor.check_segments(changes)` / `apply_segments(changes)`
  take edge -> Segment and are MORNING/CLOSED only. A change refuses when it
  cuts through furniture, blocks a work spot, unlinks a chair, or cuts off the
  door, the sink, a kitchen station, a seat, or a staff post (and, in the
  morning, a staff member where they stand) from the street. Cut-off is
  checked twice: walls only (furniture ignored), so furniture blocking a
  doorway today can never hide a permanent seal; then with furniture, where
  only newly cut-off things refuse (furniture-made blocks stay warnings). Each
  changed edge sells the old segment at the furniture rate (half) and buys the
  new one, both under `Ledger.UPGRADES`. Prices live in `data/walls/*.tres`
  (`WallKindDef`: Wall $10, Doorway $15, Window $20 per edge). `run_changes`
  skips edges that already hold a segment; `next_segment` is the click cycle
  (wall -> doorway -> window -> wall; outer face solid <-> window).
- **Save.** The `shop` snapshot is version 2 with `walls: [{edge: [x, y, axis],
  kind}]`; version 1 loads with no walls. `from_dict` validates every saved
  edge with `WallRules` after the items, then `ShopLayout.wall_segments` (edge
  -> kind id) is rebuilt by `ShopBuilder`.
- **Build mode.** The catalogue's Walls tab picks the kind; `BuildMode.State.WALLS`
  turns a drag along grid lines into a run (longer axis wins) with a green/red
  ghost per edge and the cost in the build hint; a click without a run applies
  the click cycle; Delete removes the hovered segment; Esc ends a drag, then the
  tool, then build mode. Commits go through Main's `shop_walls` wrapper.
- **View.** `WallSegmentView` (under `ShopView`) rebuilds from the grid on
  `cells_changed`, wall mode or camera quarter. Interior segments are painted
  slabs (room wall paint, 1.4 high, 0.06 thick) running vertex to vertex, so a
  doorway is the full 0.5 edge wide under a 1.15 head; slab ends reach half a
  thickness past a vertex where segments meet at an angle. Windows frame the
  native Kenney `wallWindow` pane. An outer window cuts the shell cell: its box
  drops to the sill, jambs and head surround the pane, which sits at the room
  face; `RoomDressing` keeps its street pane/lamp slots but skips that cell.
  Down lowers every interior segment. Cutaway (#205) lowers only those whose
  middle stands more than half a cell in front of the camera focus
  (`ShopView.lowered_interior_edges`, `cutaway_lowers`): walls behind it stay
  up with their finishes and decor. The set is recomputed on a quarter turn or
  when the focus enters a new cell, never per frame, and one set drives the
  segments, finishes, decor visibility and picking. A lowered doorway keeps a
  post stub at each end and a floor threshold, and a lowered window shows a
  Slate blue glass strip instead of the dark cap, so cycling reads there too.
- **Back doors (FK-099, #187).** The Doorway tool can put a back door on an
  outer face at the back or side (`WallRules.back_door_side`: not the street
  side, inferred from the entry cells), using the saved doorway segment kind
  and price. It opens that shell cell for staff and deliveries without
  changing terrain or customer entry cells: `SimGrid.is_back_door(cell)`. The
  cell is never guest-walkable: solid on the guest layer, refused by
  `is_guest_walkable`, `guest_step_ok` and `find_guest_path`, and any back
  door turns the guest layer on (`has_guest_limits()`), staff rooms or not, so
  `RoomRules.guest_reachable` agrees, and no seat may stand in it
  (`DiningSeats`). A door whose cell has only its own floor cell as a walkable
  neighbour does not count as an interior segment, so such a shop keeps the
  engine's plain paths (`_solve`); removing a door that is an item's work spot
  is refused as a blocked work spot. Removing the door restores the wall;
  floor edits derive its role again (bought floor behind it makes it an
  interior doorway, selling the floor makes it a back door again).
  `WallRules.delivery_cell(grid, target)` returns a reachable inside receiving
  cell, with stable segment-order choice and a street-entry fallback, or
  `NO_CELL` when neither route reaches the target;
  `WallRules.delivery_route(grid, target, lot)` adds where the delivery
  person stands (`door`: the shell cell, or the street entry), the receiving
  cell (`drop`: for the street, the floor cell inside the street door), `out`
  and the `approach` cells, far to near: for a back door
  (`back_door_approach`) along the **back alley** and up the door's path;
  none at the street, where the delivery person appears at the entry as
  guests do. **Back alley (Jared):** `WallRules.back_alley(grid, door, side,
  lot)` puts a paved service lane on the first row or column outside the
  shop's lot (`ShopFootprint.lot`, which Main hands to `DeliveryDock.lot` and
  `ShopView.set_lot`; empty: the building) behind the door's wall, parallel
  to it, two cells wide, paved `WallSegmentView.PATH_REACH` (24) cells past
  the lot at each end, and walked by the delivery person on to
  `ALLEY_REACH` (56) cells past it (#204: so she fades in and out off screen
  even zoomed out to 26); a side wall's alley stops at the shop's front line, where it
  meets the street (`street_side`), and deliveries come from its back end
  (a back wall's from the west). The door's path runs straight out across
  the open lot to it; with a wing of the shop in the way there is no path
  and deliveries use the street door. The alley lies outside the lot, so it
  never crosses the shop, bought floor or the street. She walks its outer
  lane (clear of the wall and an open leaf), turns up the path to the door
  and leaves the same way.
  **One back door per shop (D25).** `WallRules.back_door_problem(before,
  after)` refuses an edit that adds a back door to a shop that has one
  (`ONE_BACK_DOOR`, "The shop already has a back door: remove it first to
  move it"), or one more than a cell wide (two doorways side by side on one
  face: `BACK_DOOR_WIDTH`, "A back door is one cell wide"), in `check_segments` and in `check_floor` (selling floor can turn
  an interior doorway back into a back door). Only adding is refused: an
  older save with several loads and keeps them all, every other edit still
  works, removing one is fine, and deliveries use the first in segment order.
  Undo and redo (`Exact`) restore accepted layouts as they were.
  **The view** hides the shell box and draws the Kenney `doorway` frame with
  its own `door` leaf (posts only when lowered) and a floor tile in the floor
  material, plus the path outside: the street's pavement (Kenney `floorHalf`,
  palette tint) cut to one stone per cell, flush, out to the back alley (2.3j).
  The leaf swings out, onto the path where nothing is ever placed, like a
  service door (`WallSegmentView.set_door_open`, up to `DOOR_OPEN_DEGREES` =
  178, right round and flat against the outside wall, the turn's sign read
  from the leaf's own transforms; the door is turned round to hinge on the
  side with open ground beside the path), sliding `DOOR_OPEN_SLIDE` (0.08 m)
  onto its hinge-side jamb as it opens and, past square, out to the wall's
  outer face (`DOOR_FLAT_OUT`, 0.315 m from the wall's centre line, so its
  handle clears the wall). Open, it lies along the wall beside the doorway,
  clear of the path and of anyone on it (the Mini Characters' heads are about
  as wide as the door, so only the jamb line is near them), while someone going
  through is within 1.75 m (fully open within 0.5 m, smoothstep between:
  about a second of walking at 1x): the delivery person always, staff only
  when their path leads through the door, guests never
  (`ShopView._sync_back_doors`, a pure function of where people are drawn;
  no sim effect). Delivery people, crates and carrying: 2.3j.
- **Openings need a wall (#212).** `WallRules.has_continuing_wall` requires
  a WINDOW or DOORWAY to have a neighbouring WALL terrain cell or an interior
  WALL segment continuing along its line. Full-cell dividers and shell cells
  cut by an opening count as wall terrain, preserving existing wall runs.
  New unsupported openings are refused;
  removing their last wall support takes existing frames down with their
  half-price refund. Perpendicular thin wall segments and neighbouring
  interior openings alone are not support.
  Loading older saves stages every wall first, then drops only unsupported
  opening rows with a plain load note; the shop and its cash remain intact.
  Floor expansion uses the same rule (see the next section).
- Captures: `tools/screenshot.sh --walls=place` (a dragged run with ghost and
  cost) and `--walls=room` (a built room; add `--quarter=0` for Cutaway).
  For the expansion regression, run `OPENINGS_REVIEW_STAGE=before` or `after`
  with `bash tools/screenshot.sh --scene=res://tools/openings_review.tscn
  --speed=0 --frames=30 --quarter=2`. This unsaved fixture uses the production morning
  commands with $2,000 extra cash and wall decor unlocked, showing the
  supported window, back door and decor before expansion, then their removal
  and refund after opening that wall.

### Floor expansion (FK-080)
- **Lot (data).** `ShopLayout.lot_west`, `lot_east`, `lot_north` say how many
  cells the outer walls may move out past the starting shell; the street
  (south) side never moves, so the door, sidewalk and street dressing stay
  put. `floor_cell_price` is the price per new floor cell ($15). Tier 1: 2 west,
  2 east, 4 north (about 4 cells wider, 4 deeper). `ShopFootprint` reads it:
  `building` is the starting shell rect, `lot` that rect grown by the margins;
  new floor may go strictly inside the lot (its edge is kept for the wall) and
  outside `building`.
- **Footprint.** Only the bought floor cells are stored
  (`ShopLayout.floor_cells`, `ShopEditor.bought_floor()`). `ShopFootprint.
  terrain_for(bought)` derives every cell: authored floor and interior walls
  never change; bought cells are FLOOR; an authored shell cell with floor on two
  opposite sides opens into FLOOR (repeated, so the inner corner of an L opens).
  Only floor counts: authored interior walls never open, and a shell cell that
  carries one on (the kitchen divider's ends (0, 4) and (13, 4)) stays a wall;
  the player can add a doorway;
  a lot cell touching the floor (8 directions) becomes the new shell WALL; other
  lot cells are OUTSIDE, except a notch that walls cut off from the world
  beyond, which fills in as WALL (never bought, never refused). Cells outside
  the lot never change. `problem()` refuses
  cells outside the lot, floor that does not join the authored floor through
  floor (or, when removing, would split it) and enclosed gaps.
- **No auto walls (Jared).** The old outer wall opens up: no WALL segments are
  placed on the old outline. Players add interior walls with the Walls tool.
- **No shifting.** `SimGrid` has an `origin` and `bounds`; `grow_to(rect)`
  extends the grid (new cells OUTSIDE, AStar regions updated, solidity rebuilt)
  so lot cells north or west have negative coordinates. Cells, items, edge
  keys, staff posts and saves keep their coordinates. `SimGrid.NO_CELL` is
  far outside any lot. Iterate cells with `grid.cells()`, never `0..size`. The
  grid grows on the first purchase (or load) only, so a shop that never
  expands keeps its exact grid and the balance probe is unchanged.
- **Edits.** `ShopEditor.check_floor(cells, adding)` / `apply_floor` are
  MORNING/CLOSED only. Adding takes the unbuilt lot cells of the rectangle
  (starting building, bought cells and the lot's wall ring are skipped; a cell
  beyond the lot refuses), and every new floor cell must then be walkable from
  the street through the walls as built (a window still supported by remaining
  wall can seal a pocket: "New floor must join the shop"). Removing may not cut off
  bought floor that is reachable now. Removing takes only bought cells: furniture on any cell that would
  stop being floor refuses ("Clear the furniture off that floor first"), then a
  lost seat, work spot or door uses the wall cut-off sentences, then the usual
  walls/dining/cut-off checks run on a preview (people standing there count).
  Wall segments that would no longer fit (for example an outer window now
  facing the wing's new wall), and window/doorway frames with no continuing
  wall along their line, are taken down and refunded at the furniture rate.
  This includes a back door whose supporting shell opens; selling the floor
  later does not buy the refunded door back. The Expand summary names removed
  openings and wall decor with their refund. Undo restores their exact
  segments, finishes, hung decor and cash. Floor costs `floor_cell_price` per cell, refunds half, under
  `Ledger.UPGRADES`; every cell that stops being floor (bought cells and
  shell cells that close again) also refunds `floor(price / 2)` of its floor
  type (D25, `EditCheck.floor_finish_refund`, part of `refund`). The terrain change is one `set_terrains` batch (one
  `cells_changed`), applied before any segment is taken down so a refusal
  changes nothing; dirt spots on cells that stop being floor are cleared.
- **Save.** The `shop` snapshot is version 3 with `floor: [[x, y], ...]`
  (sorted). Versions 1 and 2 load as the starting shell. `from_dict` validates
  the floor with the template's lot before items and walls, which may stand on
  it; `ShopBuilder` applies `layout.floor_cells` before placing items.
- **Build mode.** Build's Floor tab (FK-085) has a Floor card (`BuildCatalogue.
  floor_tool_requested`; the tab is hidden without a lot). `BuildMode.State.FLOOR`: drag
  a rectangle to add floor, Shift-drag to remove bought floor, Esc ends a drag
  then the tool. The hint shows the tile count and cost or refund, or the
  refusal. `BuildPreview` draws flat green (add), gold (remove) or red tiles,
  and in every Build mode state a pale cream fill on the unbuilt cells where
  floor may go, with a cream line around that area (`ShopFootprint.
  floor_area()`, the lot inside its wall ring). A check costs about 15 ms, so
  BuildMode memoises floor checks per rectangle until the next refresh,
  topology change or commit. Commits go through Main's `shop_floor` wrapper,
  which then calls `_frame_shop()`: the camera centres on all non-outside cells
  and zooms out to fit (`CameraRig.frame_area`, a glide). The starting shell
  keeps its old framing exactly (zoom 12 for 14 x 12 cells).
- **View.** `ShopView` and `RoomDressing` rebuild from terrain, so new walls,
  floor paint, cutaway and the street frontage follow automatically.
- Tests: `tests/sim/test_floor_expansion.gd`; the five-day soak
  `tests/world/test_expanded_shop_invariants.gd` reruns the multi-day
  invariants in an L-shaped shop expanded on day 1 (with a reload).
  Probe: `--setup expanded_tables` (wings both sides, two extra table_2s, built
  free). Captures: `tools/screenshot.sh --expand=drag --speed=0 --frames=90`
  and `--expand=shop --open --fast=10 --speed=1 --frames=150 [--quarter=0]`.

### Build and Buy modes and the edit history (FK-085)
- **Two sides, one panel.** `BuildCatalogue` has Build/Buy tabs (`mode`),
  category tabs, tool buttons (Hand, Eyedropper, Sell) and Undo/Redo, and the
  room readout (the `VibeMeter` plus a theme label, path
  `Panel/Margin/Rows/Scroll/Content/Categories/Readout/VibeMeter`). Build has
  Walls, Floor (only with a lot) and Paint; Paint asks Main for the existing
  paint mode (`paint_requested`), and Esc in paint opened from Build returns to
  Build. Buy tabs are rooms: `ItemDef.catalogue_room` (data, one of
  `ItemDef.CATALOGUE_ROOMS`; empty or unknown means Decor, content validation
  names unknown ones). A room tab shows only once it holds an item, so Lighting
  and Restroom appear when such items exist. Sub-tabs are groups derived from
  the item's function (`CatalogueText.group_for`: seating, tables, equipment,
  accents, rugs) and show when a room has two or more. Theme filters come from
  `VibeTuning.theme_order`/`theme_labels` (any chosen theme matches); the sort
  cycles name, cheapest, priciest (ties keep name order) and only reorders the
  existing tile buttons. Tiles show the picture and the price (or the unlock
  level); `CatalogueText` holds every sentence the catalogue shows about an
  item (hover card lines, "Seats 2", "Cooks hot dishes", charm only for decor,
  which is all the vibe counts). The hover card sits beside the panel, never
  over it.
- **Tools.** `BuildMode.tool` (`Tool.HAND`, `EYEDROPPER`, `SELL`) decides what
  a click on placed furniture does while IDLE; `hover_item()` tracks the item
  under the pointer and `hover_summary()` gives the refund or eyedropper text
  for the HUD strip, while `BuildPreview` tints its tiles. The eyedropper
  starts a buy of the same definition, turn and colour (`buy_swatch_id`,
  applied as a free repaint in the same history entry); items outside the
  catalogue (the door) are refused with a sentence. Del sells the held item,
  or with the Sell tool the hovered one. `,`/`.` rotate (R still works);
  right-click is `BuildMode.cancel_ghost()` (drops a ghost or drag, never the
  mode); Esc is `cancel()`: ghost or drag, then the tool, then the mode.
- **Command history.** `ShopEditHistory` (src/sim/shop, pure) wraps every
  shop edit: Main's `shop_buy`, `shop_move`, `shop_sell`, `shop_walls`,
  `shop_floor` and `paint_cell` call it instead of `ShopEditor`. Each entry
  records how to invert itself with the same editor calls, so undo and redo
  pass the normal edit checks (path, dining, cut-off, cash, phase): buy <->
  sell, move <-> move back, wall changes <-> the old segments, floor add <->
  remove (putting back any segments the edit took down via
  `check_floor(..., restore)`), paint <-> the old colour. Items get new grid
  ids when they come back, so entries share an `ItemRef` that is updated.
  Money is exact: the entry stores the signed cash the edit moved
  (`ShopEditor.last_cash_change`) and the inverse passes
  `ShopEditor.Exact(-cash, "undo")` (redo: `Exact(cash, "redo")`), which
  replaces list prices and the half-price sell rate with that amount in one
  `Ledger.UPGRADES` line carrying the note (`ShopEditBooks.add_cash(...,
  note)`, `Economy.add_cash(..., note)`). So undoing a buy refunds 100% and a
  day's upgrades net to zero. An undo or redo restores a layout the shop
  already accepted, so with `Exact` the checks that only forbid losing
  something are skipped: seat, work-spot, door and floor reachability, seat
  links and the unlock level (the restored layout may already have had an
  unusable seat, and refusing would block the whole stack). Placement
  geometry, minimum equipment, items in use, people who would be shut in,
  furniture on removed floor, cash and closed-only still apply; moves pass
  `Exact` too (no money). A refused undo/redo leaves both stacks
  as they were and sets `last_refusal`; Main shows "Can't undo: ..." in the
  key strip. A new edit clears redo; paint during service is not recorded.
  Main clears the history on every phase change (opening, and the next
  morning), so it never crosses opening or the morning save; it is never
  saved. Keys: Ctrl+Z, Ctrl+Y or Ctrl+Shift+Z (Cmd on macOS), in Build and
  Paint.
- Tests: `tests/sim/test_shop_edit_history.gd` (every edit kind, exact ledger
  round trips, refused undo kept), `tests/ui/test_build_buy_catalogue.gd`
  (rooms for every item, filters, sort, hover card text, Build side),
  `tests/world/test_build_buy_session.gd` (keys, buttons, eyedropper, sell
  tool, history clearing on open). Captures: the catalogue review
  (`--catalogue-review=rustic|modern`) shows Buy mode.

### Furniture blueprints (FK-045)
- `Blueprint` is a Resource containing a player name and `ShopPlacement`
  entries: content id, anchor-relative offset, quarter turns and body swatch.
  Furniture variant ids travel with their body swatches, so copies retain
  their selected looks.
  Only floor furniture and rugs participate, never doors, wall decor or
  structure. Box selection includes whole footprints on both placement layers.
  Rotation turns the group's bounding rectangle and each item's already-rotated
  footprint together; non-square pieces retain the same relative geometry.
- `ShopEditor.check_stamp` stages every entry on one preview, then checks each
  chair's dining links and the final `RoomRules`, existing buy path warnings,
  unlocks and total affordability. Chairs may precede their tables in the
  saved list. A refused proposal changes no live items, ids, cash or history.
  `SimGrid.place_group` preflights and publishes the complete group through one
  grid notification; observers never see a partially placed group. Normal
  stamping writes one upgrade ledger line per item. `ShopEditHistory.STAMP`
  records one step with shared item references and a private blueprint copy;
  undo removes the whole group with an exact refund and redo restores it.
  Group removal validates reservations, remaining required equipment and
  combined storage capacity before changing anything. Both directions are
  closed-only and retain refused history steps.
- Buy's Blueprints tab has selection, naming, total price, rename and delete.
  The group ghost uses the existing item palette, rejection sentences, rotation
  keys (R, comma, period) and amber restock line. Blueprint names consume text
  input without triggering build shortcuts. Cancel/phase changes discard only
  the active selection/ghost, not the player's library.
- `BlueprintLibrary` is registered as a separate `blueprints` save section in
  Main, not inside the version-7 `shop` snapshot. The existing morning autosave
  is the only write boundary; creating, renaming, deleting and stamping do not
  save immediately. Restore stages the library until the whole morning load
  succeeds. Old saves without it get an empty library; unknown item ids are
  skipped with a world log line (empty resulting blueprints are omitted).
  Unknown swatches use the item's default; malformed section data is rejected
  transactionally with the existing failed-load protection. Library state does
  not reset when a shop editor is rebound. Names are single-line, at most 80
  characters; bounded input supports 256 blueprints of 512 entries each.
- Tests: `tests/sim/test_blueprints.gd`, `tests/build/test_blueprint_mode.gd`,
  `tests/ui/test_blueprint_catalogue.gd`, `tests/world/test_blueprint_session.gd`,
  `tests/world/test_blueprint_build_session.gd`, `tests/tools/test_blueprint_review.gd`.
  Manual native captures: `bash tools/screenshot.sh
  --blueprints=selection|ghost|stamped --speed=0 --frames=30 --out=<review-dir>`
  (choose one profile per run). No additional CI jobs or repeated probes.
- **Clipboard codes (#332):** Copy code shares the exact blueprint row as
  `FK1:` plus base64 of compact JSON; Paste code imports a private library
  copy, using the first free ` (2)`, ` (3)` name suffix within the 80-character
  limit. The separate pure `BlueprintCode` decoder accepts at most 40 pieces
  whose complete rotated footprints fit a nonnegative 20×20 box. It strictly
  checks transport, UTF-8, JSON, types, content ids and looks before import;
  malformed input returns null and one plain reason without logging engine
  errors. This does not change the larger, lenient version-1 saved library.
  Clipboard actions are available only in the existing closed Build flow;
  an empty/unavailable Paste reports "Nothing to paste". Successful imports
  join the next normal morning autosave. The existing blueprint ghost capture
  also records the actual Copy/Paste buttons; no new job or capture loop.

### Rooms and restrooms (FK-101)
- **Rooms on the grid.** `SimGrid.Room` is DINING (the default, never
  stored), KITCHEN, RESTROOM or STORAGE. Only FLOOR cells take a room
  (`set_rooms(cell -> Room)`, one `cells_changed`); a cell that stops being
  floor drops its room, so bought floor starts as Dining. `terrain_copy()`
  copies rooms, so every edit preview has them. Kitchen and Storage are
  staff-only (`SimGrid.room_staff_only`, `is_staff_only`).
- **Guest path layer.** `SimAgent.plan_path()` is the route an agent walks;
  `CustomerAgent` overrides it with `SimGrid.find_guest_path()`. That tries
  the plain path first and keeps it when no cell after the start is
  staff-only and no diagonal step passes a staff cell (`guest_step_ok`: no
  cutting a kitchen corner), so a shop whose guests never went near the
  kitchen keeps its exact paths (the balance probe is unchanged). Otherwise it
  searches `_guest_astar`, a third `EdgeAStar` sharing the edge maps, where
  staff-only cells are solid as well. A staff-only goal has no guest path. A
  guest buried by furniture escapes to a guest cell first; only a guest
  standing in a staff cell, or one with no guest way out, walks out on the
  plain path. `guest_neighbours` uses the same step rule, so the edit checks'
  flood fill (`RoomRules.guest_reachable`) agrees with what guests walk. Guests also use
  `is_guest_reachable`, `find_guest_path_to_any` (the exit) and
  `guest_neighbours` (the door queue); `PartySeating` and
  `DiningSeats.usable_cells` count only seats guests can reach. Staff, the
  owner, deliveries and cleaning path everywhere as before.
- **Rules (`RoomRules`, one place for every sentence).** Violations are keyed
  by item (live id; 0 for a proposed buy) and cell, and an edit is refused
  only when it adds one, so an older save's problem never blocks unrelated
  edits: a table seat in a Kitchen, Storage or Restroom room ("Guests don't
  sit in the kitchen" / "... storage room" / "Guests don't eat in the
  restroom"); a seat, a toilet's use spot or the street door that
  staff can reach but guests can't ("Guests can't reach this without walking
  through the kitchen"); and, once the shop has a Kitchen cell, a pass whose
  staff side (`work_cells[0]`) is not Kitchen or whose guest side is not
  guest-reachable ("The pass needs the kitchen on one side and guests on the
  other"). `ShopEditor` runs it for buys and moves (after the dining check),
  wall and floor edits (after the cut-off check) and room painting. Stations
  may stand in any room. Undo/redo (`Exact`) skips it (#178 accepted layout).
  The live side is cached on the grid against `SimGrid.version` (bumped on
  every terrain, item, segment or room change), so a hover only recomputes the
  proposal (a buy check went from about 4.6 to 3.1 ms).
- **The back-wall rule (Jared).** When a floor edit opens a starting-shell
  cell that touches a Kitchen cell (the wall row behind the kitchen, the east
  end of the divider), that cell becomes Kitchen, not Dining
  (`RoomRules.opened_kitchen`, applied in `check_floor`'s preview and in
  `apply_floor`). Guests reach a back room only by a route round the kitchen;
  the player may repaint the cell. Opened cells were walls before, so this
  can't cut off an existing seat, but the usual checks run on the preview.
- **Painting.** `ShopEditor.room_changes(cells, kind)`, `check_rooms` and
  `apply_rooms` (MORNING/CLOSED, free, no ledger line); `ShopEditHistory`
  records `Kind.ROOMS` with the rooms before and after, and a floor removal
  keeps the rooms it wiped to paint back on undo. Build's Rooms tab
  (`BuildCatalogue.rooms_tool_requested`, shown once Main binds a shop) has a
  card per room; `BuildMode.State.ROOMS` drags a rectangle (`rooms_press`,
  `rooms_pointer`, `rooms_release`, `rooms_summary`) through Main's
  `shop_rooms` wrapper. While the tool is on, `BuildPreview` tints every floor
  cell by room from the paint palette (Butter dining, Slate blue kitchen,
  Sage restroom, Clay storage) with a small billboard label per connected
  room area, and draws the drag in the room's colour (red when refused).
  Nothing shows outside the tool.
- **Starter and saves.** `ShopLayout.room_rows` authors rooms like `rows`
  ('K', 'R', 'S'); the Tier 1 kitchen (x 1..12, y 1..3) and its divider
  openings (5..7, 4) are Kitchen. The `shop` snapshot is version 4 with
  `rooms: [[x, y, id], ...]` (non-Dining cells, row-major); `from_dict`
  refuses unknown ids, Dining rows, duplicates and non-floor cells. Versions
  1-3 infer the template's rooms on the floor (with the back-wall rule for
  bought floor), unless that would break a room rule (a seat in or behind the
  kitchen, say); then nothing is inferred, every cell stays Dining, and the
  HUD shows "Mark your kitchen in Build → Rooms." that morning
  (`ShopLayout.rooms_unmarked`; cleared on entering Build or opening).
  `ShopLayout.room_cells`/`rooms_explicit` carry loaded rooms to `ShopBuilder`.
- **Restroom pieces.** `ItemDef.Category.RESTROOM` (appended; vibe theme
  weight 0): `toilet` (station_type `toilet`, Kenney `toilet`) and
  `bathroom_sink` ("Wash basin", Kenney `bathroomSink`), both
  `catalogue_room = restroom`, so Buy's Restroom tab appears. FK-103 adds `restroom_mirror` using the kit's
  `bathroomMirror` and `wall_hand_dryer` using the approved made hand dryer:
  both WALL / INSIDE_FACE, RESTROOM, charm 1. `WallDecor.room_hint`
  suggests marking a Restroom when hung elsewhere; it never refuses placement.
  Their bottom edges align at 0.6 m for the game's person scale; lowering the
  dryer's mount leaves its approved model dimensions and shared scale unchanged.
  Hung RESTROOM accents contribute charm with the usual diminishing returns;
  floor fixtures still do not. `STALL_PARTITION` is appended to the segment
  enum and uses the same access checks as a wall (including toilet and basin
  use spots). Its fixed cream-laminate panel is 1.4 m high and 0.035 m thin,
  drawn on the edge; it takes no floor cell and has no finish/decor face.
  The catalogue and live view share `StallPartitionView` geometry; existing
  cutaway input lowers it without changing saved state.
- **Restrooms.** `RoomRules.restroom_toilets()`: toilets in a Restroom room
  whose use spot is in the Restroom too and reachable by guests. `RestaurantSim` caches them and the dining
  seat count per layout change (`has_restroom`, `seat_count`,
  `restrooms_expected` at `data/balance/restroom.tres` `seat_threshold` 12,
  `restrooms_matter`). After the ticket is placed a guest draws one
  `randf()` from their own stream against `CustomerType.restroom_chance`
  (`default_need_chance` for an untyped guest), but
  only when restrooms matter, so default play draws nothing new. The trip
  (`CustomerAgent.Restroom`: NEEDED, WALKING, INSIDE, RETURNING, DONE) runs
  inside WAITING_FOOD: the seat stays booked, a delivered meal waits and food
  patience pauses while away. The toilet's use cell is reserved for one guest;
  inside lasts `use_ticks` (200, about 20 s) and the view hides the guest
  (`AgentPresentationController.Frame.hidden`). A busy toilet is waited for
  at the seat with patience running; a meal arriving first ends the wait.
  Missing out (none, or the meal came first) costs `missed_patience_share` of
  food patience and adds `missed_review_penalty` (review cause `no_restroom`,
  or `restroom_busy` when the shop had one, mentioned whenever it is the
  biggest complaint) only at or above the threshold. Every OPEN arrival in a
  shop with a restroom gets `restroom_review_bonus`. Walks are bounded by
  `SEAT_WALK_LIMIT`; a guest who can't get back to their seat leaves
  (`no_table`) rather than eat away from the table.
- **Cleaning.** Each use calls `CleanlinessState.add_use_spot()` on the use
  cell (no draw) when cleanliness exists. Restroom spots are a separate set:
  never in the dirt fraction, arrival patience, the dirty-floor review, the
  day's worst band or the floor spot cap, and never drawn (D8: no mess).
  `CleanTaskController` posts "Tidy the restroom" for them (tagged by origin,
  not by the room under the cell).
- **Vibe.** `VibeInputs.capture()` drops DECOR items that are not in a guest
  room: none of their non-staff cells is, or is next to without a wall, a cell
  of `RoomRules.guest_floor` (floor joined to the door by orthogonal steps
  through no wall and no staff room; furniture ignored, so crowded decor still
  counts). Grids without a street entry (tests) count everything. Stations
  still vote as before.
- Tests: `tests/sim/test_rooms.gd`, `tests/sim/test_restrooms.gd`. Captures:
  `tools/screenshot.sh --rooms=tool --speed=0 --frames=30`, `--rooms=refused
  --speed=0 --frames=30`, `--rooms=restroom --open --fast=10 --speed=1
  --frames=200` (the back room reached round the kitchen, with a restroom;
  the clock pauses on a guest walking there).

### Floor types and patterns (D25)
- **Data.** `FloorStyleDef` (`src/sim/content/floor_style_def.gd`,
  `data/floors/*.tres`): id, display name, catalogue order, price per tile,
  `pattern` (`FloorStyleDef.Pattern`, the shader's number: never renumber),
  `default_swatch`/`default_accent` (SwatchDef ids; an empty main colour is
  the shop's original brown, an empty accent a darker shade of the main
  colour), empty `theme_tags`, `unlock_level` and `unlock_tier` (only tier 1
  exists, so a higher tier stays locked: "Unlocks with a bigger restaurant").
  `ContentDB.floor_style(s)` and `validate_floor_styles`: unique ids, names,
  prices of 0 or more, known patterns and colours, and exactly one free
  `planks` (pattern 0, level 1, the shop's own colour). This PR ships Wide
  planks (free), Narrow planks ($1) and Herringbone ($3) as the starter set,
  Small tiles ($2, level 2) and Checker tiles ($2, level 3). Herringbone
  starts honey with walnut seams (the oak parquet look, Jared). Hex tiles
  (butter/cream, 0.125 m across) and Terracotta pavers (terracotta/clay,
  0.25 m squares in half-offset rows) each cost $3 and unlock at level 4.
  Their pattern values are appended as 5 and 6. Terrazzo ($4, level 5),
  Polished concrete ($1, level 3) and Carpet ($2, level 4) append 7, 8 and 9.
  Terrazzo uses cream/slate-blue hashed chips on a 0.125 m lattice;
  concrete uses slate-blue/charcoal metre slabs with faint mottling; carpet
  uses dusty-rose/walnut with a faint 0.025 m weave and no joints. The
  existing slate-blue swatch is the lighter blue-grey concrete main: the
  initially specified charcoal read near-black in the native normal/close
  review. Charcoal remains the joint colour; no new palette colour is added.
  The integer lattice hash is shared exactly by the shader and thumbnail;
  chip edges use smooth pixel coverage, and the fine lattice fades with
  `fwidth` as its cells approach a few pixels.
  Looks only: no
  sim effect.
- **Looks per cell.** `FloorFinishes` (`src/sim/shop/floor_finishes.gd`),
  owned by `ShopEditor.floors`, never by `SimGrid`: cell -> `Finish`
  {style, swatch, accent}, storing only cells that differ from the default
  (`planks` in `ShopEditor.floor_swatch_id`), with one `changed(cells)` per
  edit. A v4 shop therefore has no stored cells and looks exactly as before;
  new floor is the default; `apply_floor` drops the looks of cells that stop
  being floor. `room_cells` floods FLOOR cells of the same `SimGrid.Room` and
  stops at any wall segment (doorways and windows too); `area_cells` floods
  the connected same look within that same room, so it is never larger than
  `room_cells` (Jared: a paint click stops at
  room edges, so it never runs through the open pass into the kitchen). The legacy whole-floor `paint_floor` still sets
  the default colour (`set_default_swatch`).
- **Edits.** `ShopEditor.lay_changes(cells, style, swatch, accent)` and
  `recolour_changes(cells, swatch)` build proposals on floor cells only;
  `check_flooring`/`apply_flooring` price them: a change of floor type costs
  the new type's price per tile and refunds `floor(old price / 2)` per tile,
  only MORNING/CLOSED (`FLOORS_CLOSED`) and only when unlocked; a recolour
  (same type) is free at any time. Undo/redo pass `Exact` (exact money, no
  unlock check). `ShopEditHistory.Kind.FLOORING` keeps the looks before and
  after ("lay Checker tiles" / "recolour the floor"); like paint, a recolour
  during service is not recorded. A FLOOR removal refunds half the type's
  price of each cell it takes (Jared, as walls do), keeps their looks
  (`finishes_before`) and lays them again free on undo (the entry's exact
  cash takes the refund back); redo takes them up again. The Expand line
  says so: "Remove 10 floor tiles  (refund $75, $5 of it for the flooring)".
- **Tools.** Build > Floors (`BuildCatalogue.FLOORS`; the lot tool's tab is
  now labelled Expand, id `floor` unchanged) shows one card per floor type
  (price per tile, or "Level N" disabled with its reason) with a CPU-drawn
  picture (`FloorThumbnail`, the shader's layout in flat colours, no
  textures), then a Colour row (Original + the swatches) and an Accent row
  (Auto + the swatches, hidden for wide planks). A card or chip emits
  `floors_tool_requested(style, swatch, accent)`; Main's `begin_floors_tool`
  starts or updates `BuildMode.State.FLOORS`: a drag lays the rectangle
  (`floors_press`/`floors_pointer`/`floors_release`), Shift-click lays the
  clicked room, Alt-click (`floors_pick`) copies a floor's look into the tool
  and the tab, Esc cancels, and the hint line says "Lay 24 tiles of Narrow
  planks: $24 (refund $12)", "Recolour 24 tiles (free)" or the refusal.
  Commits go through Main's `shop_flooring`. Paint mode no longer paints the
  whole floor: a floor click recolours the connected same look inside its
  room (it stops at room edges, open passes included) and Shift the whole
  room (`Main._floor_paint_changes`), at any phase, with the same
  ShopView preview on hover. The level-up banner lists newly unlocked floors
  ("Small tiles floor").
- **Rendering.** One floor mesh and one `ShaderMaterial` with
  `src/world/floor_finish.gdshader` (it replaces `build_grid.gdshader` and
  keeps its uniforms). `ShopView` writes a per-cell RGBA8 data texture
  (`finish_image`, origin `grid.origin`, rebuilt on terrain changes, so it
  follows a grown grid, and on `FloorFinishes.changed`): R pattern, G main
  colour index (0 = `floor_color`, the shop's own colour; 1 the authored
  brown; 2.. the swatches in `content.swatches()` order, sent as the
  `palette` uniform array), B accent index (0 = automatic), A a threshold
  mask (1 west, 2 north, 4 east, 8 south: that neighbour is another floor
  type). The street entry and a back door's threshold tile (which shares the
  floor material) copy the floor inside them. The shader reads it with
  `texelFetch` (GLES3/Compatibility) and lays patterns in world space so they
  line up across cells; pattern 0 is the old plank code verbatim, so a default
  shop is an all-zero map and renders pixel-identical to before. Fine detail
  fades with `fwidth`; a thin darker line marks a change of floor type.
  `preview_floor_finishes`/`clear_floor_preview` draw a proposal through a
  preview copy of the map (the Floors drag, with a green outline from
  `BuildPreview`, and the paint hover). Adding a floor look = a `Pattern`
  value, a branch in the shader (and `FloorThumbnail`), and a data file.
- **Save and vibe.** The `shop` snapshot is version 5 with `floor_style_id`
  (the default type; only `planks` is accepted, any other value loads as
  the planks so an edited save cannot make every cell a priced, refundable
  type) and `floors: [[x, y, style, swatch, accent], ...]`
  (stored cells, row-major); no new SaveSystem section. Versions 1-4 load as
  all default. Decoding forgives (looks only): an unknown type or a cell
  that is no longer floor falls back to the default, an unknown colour to the
  type's own, a malformed row is skipped. `ShopEditor.floor_vibe_swatch()`
  gives the vibe the main colour of most guest-room floor cells (ties go to
  the first colour id), which is exactly the old whole-floor paint in a shop
  with one colour.
- **Review.** `tools/screenshot.sh --floors-review --speed=0 --frames=12,30`
  (`tools/floors_review.gd`): small tiles in the kitchen with a back door,
  narrow planks, herringbone, checker, hex tiles and terracotta in the dining room with thresholds
  and the street door, staff standing on them; then Build > Floors holding a
  herringbone drag.

### Wall finishes and wall decor (D26)
- **Faces.** `WallFaces` (`src/sim/shop/wall_faces.gd`, pure, static): a face
  is one 0.5 m side of a wall seen from the floor cell in front of it, keyed
  `Vector3i(x, y, dir)` (the floor cell, and the direction into the wall:
  0 north, 1 east, 2 south, 3 west). Faces are derived from the grid on every
  query, never stored: the room side of a solid shell `WALL` cell, both
  sides of an interior `WALL` segment, and solid street-facing outside shell
  faces. An outside key uses the outside/entry cell and direction into the
  shell; no existing inside/window coordinates change meaning.
  `WallFaces.all(grid)` and room fill retain inside-only enumeration; the
  explicit `include_exterior` argument includes outside faces. Windows, doorways (the back door too),
  the street door and a shell cell cut by a window or back door (on any side;
  its box is cut or hidden) have none. `problem(grid, face)` gives the
  sentence (rule 11). `flood` follows a face along its wall and round inside
  corners (an opening ends the run); `span(anchor, width)` is a wide item's
  faces to the right of its anchor seen from the room. A **window slot** uses
  the same key for an outside window (the floor cell inside and the direction
  into a WINDOW segment whose `WallRules.outer_side` is that direction):
  `window_problem` ("This sign hangs in a window", "... on an outside wall"),
  `windows(grid)`. A slot is never a face, so both share one decor map.
- **Finishes.** `WallStyleDef` (`src/sim/content/wall_style_def.gd`,
  `data/wall_finishes/*.tres`), as `FloorStyleDef`: id, name, order, price per
  face, `pattern` (`WallStyleDef.Pattern`, never renumber: 0 plain paint),
  `default_swatch`/`default_accent` (empty main: the shop's wall colour; empty
  accent: automatic, the shop's wall colour above painted panelling, else a
  darker shade), empty `theme_tags`, `unlock_level`/`unlock_tier`.
  `ContentDB.wall_style(s)` and `validate_wall_styles` (exactly one free
  `paint`, pattern 0, level 1). This PR: Plain paint (free), Painted panelling
  ($2, sage, a 0.46 m wainscot under the shop colour), Striped wallpaper ($2),
  Subway tiles ($3, level 2), Brick ($4, level 3). `WallFinishes`
  (`src/sim/shop/wall_finishes.gd`, owned by `ShopEditor.walls`) mirrors
  `FloorFinishes` and shares its `Finish` value: face -> look, only faces that
  differ from the default (plain paint in `ShopEditor.wall_swatch_id`) are
  stored, so a v5 shop has none and looks exactly as before; `paint_wall`
  still sets the default colour (`set_default_swatch`, which folds faces
  already in that colour into the default; the history's PAINT entry keeps
  the stored wall faces, or floor cells for floor paint, and puts them back
  on undo, so an unwind is exact).
- **Finish edits.** `ShopEditor.wall_lay_changes`/`wall_recolour_changes`
  build proposals on faces only; `check_wall_finishes`/`apply_wall_finishes`
  price them like floors: a new finish costs its price per face and refunds
  `floor(old price / 2)`, MORNING/CLOSED only (`WALL_FINISH_CLOSED`) and only
  when unlocked; a recolour is free at any time. `ShopEditHistory.Kind.WALL_FINISH`
  ("put up Brick" / "recolour the walls"); a service-time recolour is not
  recorded. Build > **Wall finish** (`BuildCatalogue.WALL_FINISH`, between
  Walls and Floors): one card per finish with a CPU picture (`WallThumbnail`),
  a Colour row (Original + swatches) and an Accent row (Auto + swatches,
  hidden for plain paint); a card or chip emits `wall_finish_tool_requested`,
  Main's `begin_wall_finish_tool` runs `BuildMode.State.WALL_FINISH`: click a
  face, drag (every face of the floor rectangle between the two ends that
  turns the way either end does: one wall, or round a corner), Shift-click the
  room (`wall_room_faces`), Alt-click copies a look (`wall_finish_pick`).
  Commits go through Main's `shop_wall_finishes`. **Paint** on a wall face hit
  before any furniture recolours the connected run of that look inside its
  room (`wall_area_faces`), Shift the room; Paint on the outside of the shell
  still calls the legacy whole-shop `paint_wall`, even when an outside face
  has a stored finish override. Existing inside/window decor ignores Paint;
  a paintable exterior awning uses free `paint_hung`, with closed-phase history.
- **Wall decor.** A wall item is an `ItemDef` on `PlacementLayer.WALL`
  (DECOR or RESTROOM, not solid, no work/seat/blocking cells, footprint
  `(width 1..4, 1)`); `SimGrid` refuses that layer (`INVALID_LAYER`), so it
  can never stand on the floor. `ItemDef.wall_mount` (`WallMount`, never
  renumber) says where: `INSIDE_FACE` (prints, boards: the default) or
  `WINDOW` (one outside window wide, footprint (1, 1)), or appended
  `EXTERIOR=2` on the fixed street front. The OPEN sign retains WINDOW and
  its original price/unlock, adding `allow_exterior`; its instance records
  the actual mount, so moving between window and outside is unambiguous. `WallDecor` (`src/sim/shop/wall_decor.gd`,
  owned by `ShopEditor.decor`, never by `SimGrid`) maps anchor face -> item
  (`def_id`, width, actual mount, swatch) and face -> anchor: one item per
  face/band, never in anyone's way. `problem` refuses a span that is not one straight run of solid faces
  (`WallFaces` sentences: window, doorway, street door, "Not enough wall here",
  "A wall is in the way", "This would span two different walls": a shell
  face and an interior slab's face are on different planes) or covers another
  item ("Something already hangs here"); a window item instead needs an outside window slot, one per window
  (`Hung.window`). `ShopEditor.check_hang`/`hang` (price, unlock, cash; one ledger line
  like furniture), `check_rehang`/`rehang` (free), `check_take_down`/`take_down`
  (half price), all MORNING/CLOSED (`DECOR_CLOSED`); `Exact` for undo/redo.
  History kinds HANG, TAKE_DOWN, REHANG. This PR's items are the made diner
  wall pieces (#147) through their wrappers: Sunrise print ($30), Chalk menu
  board ($25), Mountain print ($35, level 2), Neon OPEN sign ($80, level 4,
  in a window).
  They show in Buy > Decor under a **Wall decor** sub-tab
  (`CatalogueText.group_for`), and a tile starts `BuildMode.State.HANG`: the
  hovered face (`ShopView.wall_face_at_ray`, with the nearest face of the
  floor cell as a fallback for low walls) and the pointer's side pick the
  anchor (`WallFaces.anchor_for`); a window item takes the window under the
  pointer (`ShopView.window_at_ray`: the shell cell's box, else a window of the
  floor cell pointed at) and otherwise the wall face (refused with the window
  sentence); a buy keeps the item in hand. While idle the
  Hand picks a hung item up (Del sells it), the Eyedropper hangs another and
  Sell (or Del) sells the pointed one (`ShopView.wall_item_at_ray`: an item
  only counts when no furniture or wall (`wall_distance`: shell boxes and
  segment meshes, not window glass) is nearer along the ray, so nothing is
  picked or sold through a wall). A shell box hit on a side counts only for
  that side's face (`_shell_face`): its street side has none (paint there
  repaints the building); a hit on a lowered box's top takes the nearest face.
  Rotating does nothing: an item always faces out from its wall. A restroom
  mirror or dryer (#198) is another WALL-layer `ItemDef` with
  `catalogue_room = restroom`.
- **Walls that go.** A wall or floor edit that takes a face away (a wall
  removed or turned into a doorway or window, a shell cell bought as floor or
  cut by a window, floor sold) takes its finish and every item covering it
  down, and an edit that takes a window slot away (the window closed or turned
  into a doorway, its shell cell bought as floor) takes its sign down: `check_segments`/`check_floor` note them (`EditCheck.lost_finishes`,
  `lost_decor`) and add their refund (half the finish's price per face, the
  item's sale refund) to the edit's refund; the apply drops them. The history
  entry keeps them (`lost_walls`, `lost_decor`) and puts them back free on
  undo (the entry's exact cash already moved the money); redo takes them again.
- **Rendering.** `WallFinishView` (under `ShopView`, rebuilt on terrain,
  wall heights, finish and decor changes) draws each finished face as a thin
  quad 3 mm off the wall (interior faces off the slab's face), as high as the
  wall is drawn (full, or the stub in Cutaway and Down), with world-metre UVs
  so patterns line up from face to face; an interior face stops at a joining
  slab on its side and wraps a corner on the far side. One `ShaderMaterial`
  of `src/world/wall_finish.gdshader` per look (pattern, main and resolved
  accent colours, roughness 0.9 like the plain walls); a proposal (the tool's
  drag, the paint hover) draws with a thin green outline. Default faces draw
  nothing, so a shop without finishes renders pixel-identical to before. Hung
  items are their `ItemVisual` wrappers standing on the span's floor cells
  with their back (+Z) on the face; they hide while any wall they cover is
  drawn lowered (they would float over the stub). The HANG ghost is a tinted
  copy (`BuildPreview` colours) shown on any face, the held item hidden while
  moved. A window item is its wrapper scaled down to fit 90% x 80% of the
  window opening (`WallSegmentView.window_opening`), centred in it, front
  (-Z) to the street, just inside the shell's outer face: the steep camera
  sees no deeper into a window from outside, and from the room it shows its
  back through the glass; it hides while its shell cell is drawn lowered,
  like wall decor. Catalogue thumbnails turn wall wrappers (`WallMount` node) to face
  the camera. **Glow** (Jared): an item with `ItemDef.glow_color` (alpha > 0;
  the neon OPEN sign's red) gets one `OmniLight3D` child "Glow" on its
  visual, 0.2 m out from the face at the item's middle: range 1.2 m, energy
  0.45, attenuation 1.6, no shadows, no specular. That is a soft pool on its
  wall, a nearby corner and the floor below, not the room (a future
  face-mounted glowing item should get the window treatment below, since a
  shadowless 1.2 m light reaches past an interior wall). A window item's
  light (the window-mounted OPEN sign) stands in the window plane,
  halfway through the opening at the sign's height, with range 0.34 m: it
  lights the window's own jambs, and no room beside the window (at least
  0.375 m away, past an interior wall on the window cell's side line). Its
  pools are two flat additive, unshaded glow squares ("PoolInside",
  "PoolOutside"), each exactly the one cell in front of the window (the floor
  inside, the ground outside the shell), fading from the wall, so the glow
  never bleeds into another room. The item's own
  meshes move to render layer 20 (`GLOW_SELF_LAYER`), which the light's cull
  mask skips, so the sign isn't washed out by its own glow. It hides with the
  item (lowered walls, held for a move); ghosts get none. The shop has no
  day/night, so the glow is constant. Compatibility draws each light as one
  more pass over the meshes in its range, up to 8 lights per mesh (the
  floor is one mesh), so many glowing items in one shop would start to drop
  lights on the floor; a shop without one renders exactly as before.
- **Street-front supports.** Pure `ExteriorSupport` derives the fixed front
  from street entries and `WallRules.street_side`; back/side walls refuse.
  It distinguishes solid finishable surfaces from door/window supports,
  including the unchanged decorative frontage panes. Outside item keys keep
  the outside cell and encode `z=dir+4*band`: BODY0, CANOPY1, HEADER2, SILL3,
  LIGHTS4. `span`/`anchor_for` preserve the full key. A canopy spans a door
  or window, a sign header spans the street door, and a sill supports a
  flower box under a window. Independent bands coexist; same-band overlaps
  refuse. Solid finish quads never cover a cut window or doorway. Support
  loss refunds/deletes dependent items and history restores their mount and
  swatch exactly. New data supplies awning widths2–4, a flower box, one shop
  sign and light runs2–4. The new `shows_restaurant_name` sign follows the
  existing MenuSettings -> Main -> ShopView name path on rename/rebuild/load;
  the free RoomDressing board remains unchanged. No second saved name.
- **Save and vibe.** The current `shop` snapshot remains version 7 (furniture
  looks); wall fields introduced in version 6 keep `wall_style_id`
  (always `paint`: any other value is ignored, like floors), `wall_finishes:
  [[x, y, dir, style, swatch, accent], ...]` and `wall_items: [[x, y, dir,
  def_id], ...]` (sorted; a window item's row is its window slot, so the row
  format is unchanged). Only exterior instances append their actual mount
  and selected swatch: `[x,y,z,def_id,2,swatch_id]`; old inside/window rows
  remain four fields on load and output. Optional rows validate band, mount,
  support and uniqueness before staging. There is no new SaveSystem section
  or action save; all state joins the existing morning checkpoint. Versions 1-5 load as
  plain paint with nothing hung. Decoding forgives: a face that is no longer a
  face, an unknown finish or item, a non-wall item, an overlap or a malformed
  row is skipped; an unknown colour falls back to the finish's own. The vibe
  reads `ShopEditor.wall_vibe_swatch()` (the main colour of most guest-room
  wall faces: exactly the old wall paint by default) and
  `decor_vibe_items()` (hung items on guest-room faces) through
  `VibeInputs.capture(..., wall_items)`: decor charm and themes like rugs
  (no floor space). Actual exterior placements are explicitly excluded even
  when guest cells are empty; outside finishes do not vote in inside wall
  colour. Their existing saved shop facts also feed the derived curb appeal
  below; geometry, paths and indoor vibe remain unchanged.
- **Review.** `tools/screenshot.sh --walls-review --speed=0 --frames=12,30`
  (`tools/walls_review.gd`, `[--quarter=N]` for frame 12): finishes on shell
  and interior walls and four hung items (the OPEN sign in a street-front
  window right of the door: hidden in frame 12's quarter-0 Cutaway, which
  lowers the front; seen from the street in frame 30 and from inside with
  `--quarter=2`) in Cutaway, then Walls Up with
  Build > Wall finish holding a striped wallpaper drag; a hand-run frame after
  40 holds a chalk menu board from Buy > Decor > Wall decor, and one after 60
  shows Walls Down (finished stubs, hung items hidden).

### Furniture variant data and materials (FK-079)
- `ItemDef.variants` lists `ItemVariant` resources. The first is the legacy
  default. A missing/unknown id resolves to that default; content without
  variants retains its original price and tags. Each look holds a player
  name, price delta, theme tags and imported-material-name to kit-colour-name
  recipe. Returned theme tags are detached copies.
- `KitMaterialColours` reads colours from unchanged Furniture Kit donors once.
  `PropVariantMaterials` validates every named surface and donor before any
  change, duplicates only affected active materials and changes their colour,
  retaining alpha and other material properties. Switching or clearing a
  recipe restores exact original overrides. It never modifies imported meshes,
  materials, textures or scales. The caller restores it before model disposal.
- First authored resources are the booth's white, walnut and red shells and
  the stool's chrome/red, chrome/dark-teal and dark-frame/white looks. The
  colour names are descriptive: the donor colours remain exactly the kit's
  `carpet`, `carpetWhite`, `woodDark` and `metalDark`; there is no invented
  black, red or teal RGB value.
- `ShopPlacement` and `PlacedItem` carry `variant_id` (empty for the legacy
  default); the grid sets it before its placement signal. Shop snapshots are
  version 7; missing, malformed and removed look ids fall back to the default.
  The morning autosave remains the only save boundary. Purchases and sale
  refunds use the look's price; undo/redo restores the id with exact ledger
  deltas, and `VibeInputs` reads its detached theme tags.
- Buy tiles choose a named kit-colour dot without purchasing. `CatalogueText`
  supplies that look's price/name/themes; thumbnail cache keys include both
  wrapper and look resources and retain them for identity safety. The buy
  command, eyedropper, live model and ghost carry the selected look.
- `PropView` owns the material recipe below body paint: painting preserves
  frame/other surfaces, and clearing paint reveals the selected look again.
  Imported resources remain immutable and disposal restores overrides first.
- Paint offers named looks for the first set at any phase and clears the
  ordinary body swatch so the selected recipe is visible. Closed-phase undo
  restores both old look and swatch; painting during service adds no history.
  Equal-price look changes are free. The Director-approved policy refuses
  cross-price repaint: choose a differently priced look at purchase time,
  when its authored price delta is charged. No repaint charge or refund is needed.
- Vibe keeps repeat decay, variety and item-specific weights grouped by base
  furniture definition, while counting theme votes by explicit look identity.
  Different looks can coexist; inconsistent copies of the same look are still
  rejected. Default looks retain the previous balance.
- Director visual review follows the ready PR. For the first set, the kit's
  dark blue-green is not literal black. The Director accepted the existing kit
  palette and honest dark-frame/dark-teal names; no replacement colours are needed.

### Restaurant vibe core (FK-072)
- `VibeModel.evaluate()` reads detached layout, paint and enabled-menu inputs.
  It never changes the inputs, draws randomness, reads nodes or saves a result.
  Definition and recipe IDs are aggregated in lexical String order, rather
  than the pointer ordering of interned StringNames.
- `data/balance/vibe.tres` authors diminishing repeat charm, variety, component
  caps, theme and menu weights, crowding and the maximum effects. Only DECOR
  earns charm and variety; a data-authored lamp-ID list partitions lamp charm
  without guessing IDs. The lamp list is empty until lamp content is available.
- Known themes are Cosy, Modern, Rustic, Diner and Seafood. Tagged items, paint
  and today's enabled recipes contribute weighted votes; menu weight is lower
  than decor weight, and a menu alone cannot establish a layout theme. The
  authored theme order resolves active ties. Themes are never auto-built.
  Theme points ramp with excess charm after the starter allowance, reaching
  their full value at the data-authored `theme_full_charm` (currently 4).
  Matching starter furniture does not give one extra plant the full bonus.
- Crowding counts the union of normal-layer occupied interior FLOOR cells.
  Floor rugs still contribute charm and tags but do not double-count furniture
  coverage. Score and component results remain finite and bounded; invalid
  inputs or authoring return a neutral result and a readable reason.
- Provisional tuning gives the starter plant's two charm and one decor kind a
  free allowance. The actual starter's effects should therefore remain zero;
  this is not a measured five-day profit result. The current authored caps give
  a maximum 1.15 patience multiplier and a 0.4 raw review term. Both consumers
  read those limits from `vibe.tres`, rather than imposing a second adjustable
  ceiling. Tuning must remain finite and nonnegative; the theme ramp threshold
  must be positive. Review scores are bounded to their physical 1–5 range
  before integer rounding, including for a large finite authored bonus.
  Consumer tests use detached tuning resources, never mutate the shared asset.
  Customer-type strength is a
  hook until FK-061 is integrated.
- `VibeInputs.capture()` copies the live grid, current paint tags and enabled
  recipes. Main recomputes after final startup/load installation and accepted
  layout, paint or menu-selection changes, never on simulation ticks or frame
  updates. It disconnects the old grid observer before a world replacement.
  Paint colours and IDs are unchanged; optional swatch theme tags are authored
  in the existing curated resources.
- `RestaurantSim.set_vibe()` keeps a detached bounded snapshot. A real OPEN
  arrival applies its patience multiplier once after cleanliness, then keeps
  its raw review bonus and theme label even if the player redecorates later.
  Neutral budgets remain exact and the existing later Cheerful-server bonus
  is preserved. `CustomerAgent.review_visit()` carries the retained term into
  the existing review path, before integer rounding/clamping; unserved and
  closing policies and the existing review/quote random stream remain intact.
  A bonus that crosses into a positive rating uses the existing positive quote
  policy, rather than retaining an old complaint from its lower raw rating.
- A native read-only meter in the Build catalogue shows score and component
  tooltip. The HUD adds the active theme to its existing reputation tooltip.
  The evening report uses a transient count of paid guests' captured positive
  arrival themes for the softer wording “Guests noticed the … vibe”, rather
  than implying that every paid guest liked the visit. A factual current-score
  fallback is shown only when that score rounds above zero. A captured arrival
  theme can still be reported after a later edit makes the room neutral.
  This avoids attributing a late repaint to earlier guests. Counts reset each
  morning and never join the saved report. Score, snapshots and presentation
  add no save section, action save, random draw or customer-type selection.

**Customer types (FK-061):** `data/customers/types.tres` authors neutral Regulars,
Students (budget 0.8 / patience 1.3, level 1), Foodies (1.4 / 0.9, level 3), and
Families (1.1 / 1.4, level 4). Main installs the detached catalogue
after owner progression and reviews restore, and refreshes its level each morning.
The spawner chooses in authored order from unlocked, positive weights interpolated
by reputation, using the named customers stream. One eligible type consumes no
selection draw; an unconfigured simulation retains the old Regular arrival path.

A guest captures its authored name, budget and review preferences, and scales
patience once before cleanliness and Vibe; the server bonus still applies later
once. Walkouts and the overprice review penalty scale only the positive excess
`max(charged / standard - 1, 0) / budget`; standard prices are fair for every
type, and discounted-price quote rules stay unchanged. Reviews add
`(clamp(Order.quality, 0, 1) - 0.5) * quality_weight`: half-quality is neutral,
better food helps and worse food hurts. Invalid quality measurements add no
term, and Regular's zero quality weight is unchanged. Types also multiply review
probability before clamping it to 0-1. Closing/unserved policies and the separate
review RNG remain unchanged. Native Mini model pairs distinguish special types
deterministically; Regular keeps its existing guest-id mapping. The inspection
panel shows the authored type name. No customer-type save section or action save
is added. Regular compatibility fixtures retain the pre-type methods from main
`34f8fde` for seeds 1, 7 and 42; they do not substitute for the required ten-day
before/after balance probe.

**Group seating (FK-066):** the same catalogue authors Family parties of 2-4
and Regular, Student and Foodie parties of 1-2. Each type's
`party_unlock_level` (data) sets the owner level from which it may arrive as
a group: 5 for Regular, Student and Foodie, 1 for Family (whose own unlock is
level 4). Below it the type is a single guest that draws exactly what main's
single guest draws: no size draw and one private seed. Frozen single-guest
integration comparisons share the current traffic and world implementation.
Fixed-size ranges consume no size draw either. An unlocked type draws one
ranged party size, then clamps it to the largest currently usable dining group
reachable from the chosen street entry, but never below one. Capacity counts
clear, unique, reachable seats, including linked furnishings; temporary
bookings and dirt do not shrink the layout's capacity. Single guests always
arrive; with no usable table a clamped party becomes one guest who waits and
leaves as "no table", so the loss is counted. The customers stream still
draws a private seed for every originally drawn member, discarding the extra
streams after the clamp, so the next arrival's draws do not shift. The next
arrival gap is one gap draw multiplied by the number of guests who arrived,
so groups keep guests per hour unchanged. The level-up report shows the
type's short `party_tip` once, in the evening report of the day the owner reaches the unlock level; groups arrive from the next day.
It installs and links
every member before publishing any arrival; singleton installation retains
the old draw and signal order. `Party` stores member IDs rather than strong
agent references. `PartySeating` searches one derived table group with enough reachable
free seats, matches all members before reserving, and rolls back every hold
and path on failure. Arrival IDs give waiting parties first choice: later
guests and parties leave clear seats at any table that could seat an earlier
waiting party after current reservations clear. Smaller tables or tables the
earlier party cannot reach may backfill. The decision reads current geometry
each time and adds no saved reservations or random draws.
No member orders until everyone reaches their own seat.
The shared table/walk budget is bounded by the least patient member. A table
timeout ends every waiting visit once. On a food timeout only members still
waiting for food leave; eating, paying and already-delivered members keep
their seats and finish individually, even before their next state tick.
Previously paid members also retain their successful outcome. Orders, payments and reviews
remain per person; no review formula or patience tuning changes.
Build checks report partial table capacity with plain text such as "Only 3 of
4 seats usable". Preview and committed outlines use the same detached warning
data; Main forwards that text to the HUD, with invalid-action reasons taking
precedence. Warnings permit placement and clear when the layout is repaired.
The four-seat table combines unchanged Kenney tables and chairs inside a 2x3
footprint at the existing furniture scale. Each chair faces the same table
centre as its seated guest. The clearance probe classifies its joined
chairCushion meshes like the existing cushioned kit seats; classification
does not grant an exception or establish a measured fit. The inspector adds "Party of N".
All party state is transient, with no save section or action save. Singleton
regressions freeze only the old integration boundaries from exact main
`1f9804e` and compare complete tick/RNG snapshots for seeds 1, 7 and 42 under
the same current traffic implementation; these
written regressions are not a substitute for the required balance comparisons:
`bash tools/balance_probe.sh --days=5 --seeds=1,2,3,4,5 --setup=default` and
`bash tools/balance_probe.sh --days=10 --seeds=1,7,42 --setup=default` on exact
main and feature heads. The Director's acceptance bar is a five-day mean profit
at most $15 below main and no-table losses at most 1.5 times main's. These are
manual checks using the existing probe; no CI loop or job is added.

**Career goals (FK-062):** `data/milestones/starter.tres` owns the twelve starter
goals. The pure `MilestoneTracker` observes closed-day served/lost counts,
reputation, operating profit, owner level and staff count. It records lifetime
served guests and the consecutive no-loss streak, and returns each goal once.
`MilestoneSettlement` prepares detached tracker/owner copies and validates the
whole cash/XP reward batch before Main installs it. Reward XP does not recursively
complete another goal in the same batch. Completion IDs use lexical String
ordering; well-formed historical IDs remain completed even after content removal.

Main captures operating profit after closing costs, awards ordinary owner XP,
then applies career rewards before loan settlement. `Milestone bonus` is a
separate ledger income category. Its cash can prevent an unnecessary advance;
the loan repayment share and ordinary profit XP still use pre-bonus operating
profit. The evening report lists reached goals near the top and includes their
XP in its breakdown. Opening the read-only Goals panel from Menu never pays a
reward or changes clock/RNG state; it shows the next three unlocked goals and
known completed goals with progress in their original condition units.

The registered `milestones` save section is staged during decoding and installed
only after the complete morning restore succeeds. Its last evaluated day must
precede the saved morning. Missing legacy sections start a fresh career tracker;
malformed data rejects the load without partially installing career state. Career
state uses the existing next-morning autosave only, including rewards earned at
the preceding close. New Game resets it. No action or evening save is added.

**Weekly challenges (FK-135, #345):** Ten data definitions reuse the close-day
`MilestoneDay` observation. A draw on mornings 1, 8, 15 and so on uses the named
weekly stream, excludes the previous objective, and freezes its level-scaled
target and selected menu dish. Paid sales keep counting for that frozen dish
after menu removal. A one-time closing cash reward has its own ledger category,
excluded from business operating profit and owner XP. Goals uses
`WeeklyChallengeText` for singular/plural days remaining.

The weekly save section is decoded strictly and staged with the other morning
sections. If its dates do not fit an otherwise valid saved morning, only that
weekly candidate is discarded. The restored world logs the recovery and the
normal morning setup starts a fresh challenge for the remaining week, with no
fabricated prior progress or repeated draw. Other section validation and the
morning-only save boundary remain unchanged.

Day-one targets are checked against actual default service for seeds 1, 7 and
42, applying all ten definitions and every eligible selected dish to each
detached observation. The observed maximum was 19 served, 11 good reviews and
8 sales of one dish; review targets are therefore 12 and the smaller dish goal
is 9, with daily serve targets 24/36. The random selected challenge alone is
insufficient evidence because it may hide an easier unselected definition.
**Group bookings (FK-131, #343):** The single accepted next-day group uses a
soft joined-group hold from 75 minutes before its slot. Existing diners retain
their physical reservations and leave normally. A matching booked party's
shared queue counter pauses only while its current valid held group is actually
occupied or dirty, from the slot up to (excluding) slot+30 displayed minutes.
The read-only predicate never selects another group, erases spent patience or
moves the deadline on retry. Missing, free/clean, stale and wrong-day holds get
ordinary patience. The party controller's once-per-world-tick guard remains.

Dirty reserved tables form one narrow staff-selection exception: eligible
reserved bussing precedes other positive saved job tiers and distance scores.
Before the booked party seats, OPEN cleanup jobs for its current held joined
group wait while a prior diner still physically owns any group seat. Every
departure dirties the joined members, so cleaning them mid-meal both delays
the remaining diners' food and must be repeated. These jobs keep their IDs,
post times and failure counts; the last physical seat release restores their
eligibility and reservation priority. No already-claimed bus job is preempted.
Jobs set Off and role/target eligibility remain absolute; no saved priority
changes. The one claim exception is a floor mop still navigating before its
first WORK step: an eligible reserved bus task returns that same mop to the
normal queue without counting a failed attempt. Existing motion finishes its
real edge before the new task runs. Actual mopping, service and carried food
are never interrupted. Once the matching booked party is seated in that held
joined group, reserved urgency ends: partial departures still create ordinary
bus jobs, which cannot take priority over that party's remaining meals merely
because its booking stays active until everyone leaves. Empty dirty groups rank
before occupied groups when
the normal hold chooses a new group. Tick-driven booking presentation refreshes
only on a changed day, phase or held group; player actions refresh immediately.

Customer advances, their application and refunds retain the existing exact
ledger movements and operating-profit exclusions. The report labels the service
day's applied amount as "Deposit taken off the bill". Main's paid-order replay
guard returns before counting any cost, sale or booked bill a second time.
Saving stays at the existing morning checkpoint with no new booking save fields.

`tools/booking_soak.gd` is a manual fixed 24-seed diagnostic, not a CI loop. It
forces six-person offers, moves the three actual starter tables into a joined
group and stages level 2/next morning, while keeping ordinary arrivals, stock
purchases, staff, kitchen, patience and eating duration. Each seed reports model
settlement separately from actual seating, paid members and advance application
or refund; it is not proof for every 6–10-person layout. The occupied-at-slot
regression alone discloses a later legal 16:15 slot, staged long meals, delayed
unrelated arrivals and real extra ingredient purchases to isolate the reservation
boundary. It observes complete physical admission before releasing the diners;
the fixed slot+30 grace, ordinary staff capacity and patience remain unchanged.
The required lifecycle result is six actual booked seats and settlement backed
by unique real paid orders, a bill covering the advance and reconciled sales.
The manual soak succeeds when most cases are seated and settled without a
no-seat result or accounting errors. Both tools still report all-six-paid
observations separately. Ordinary already-claimed bussing can wait on an
occupied table and delay a later ready meal; this existing service limitation
is reported rather than extending booking-specific preemption after seating.

**Lighting and frontage (FK-055):** Main owns one `lighting_rig.tscn` with a
warm directional key (main's colour, energy and shadows), low-energy cool fill
and warm ambient light, so exposure matches the pre-rig shop. A native procedural
sky gives a soft warm gradient: sky and ground share one horizon colour with wide
curves, so there is no horizon line or black lower half. Directional lights
illuminate geometry only, so the fill does not add a second visible sun.
Compatibility settings and the existing tone-mapping exposure/white point remain;
only the key light casts shadows (default Compatibility shadow settings, as on
main before the rig); Web FPS with shadows still needs measuring. Environment, sky and sky-material resources are
local to each scene instance. Web FPS and appearance require actual validation.

`RoomDressing` reads the actual entrance runs and outward OUTSIDE terrain to
place native window panes and decorative wall lamps on the street frontage, a
doormat at the door, and doorway-width grey pavement (one native `floorHalf`
per entry cell) touching the entry edge. It preserves imported transforms under
the shared ArtScale wrapper. Only pavement's named wood surface receives a
private tint mixed from palette swatches (Charcoal, cooled with Slate blue and
lifted with Cream, so it reads grey under the warm key); shared kit materials
are unchanged. Cutaway mode and camera quarters change stable wall attachments'
visibility without reallocating models. Terrain/world replacement rebuilds and
releases the old dressing. Dressing adds no lights, simulation cells, collision,
random draws or saved state; functional lamps remain the separate lamp issue.
`NeighbourhoodDressing` is a separate view-only child of `ShopView` (FK-242).
Main binds the maximum supported lease footprint separately from the actual
service lot; all current built cells and native entrance/alley paving also
participate in exclusion. Native pads, mats, windows and the name board remain
owned by `RoomDressing`. Additional copied pavement is clipped around those
actual transformed boxes and the maximum reserve; it never covers future
buyable land. Static road/crossing/kerb/building/roof/lamp copies are batched by
material, with no new lights or shadows into the shop. Made models use the
central furniture scale once; all source-kit and original rig resources remain
unchanged.

Three reused Mini guest views and one pooled occasional car follow fixed
presentation paths using monotonic display seconds, independently of the sim
clock. Whole animated sweeps clear the maximum lot, door approach and paving
edges. They are not agents, physics bodies, navigation or input targets, and
never enter the shop's item/agent maps, RNG streams or save providers. Normal
frame processing stays enabled; the photo-only `set_review_time` override pins
both real transforms and animation phase without changing game state. Read-only
`capture_state` exposes actual observations for native and timing tools.
Terrain/lot changes reconfigure a cached geometry signature while retaining
actor nodes/time; world replacement frees the old controller and atomically
binds the new world's reserve through `show_world`.

The neighbourhood stands on a ground of its own (#421, #424): `NeighbourhoodGround`
builds, in the street's local frame, a meadow, lawn and packed-earth back lane, flat
contact shadows, hedge rows, scattered trees, bushes and flowers, and a ring of
trees that closes a square clearing of `WORLD_HALF` metres around the maximum
lot. It is three vertex-coloured, flat-shaded, shadowless meshes (three draw calls),
parented under `NeighbourhoodDressing/Ground`, outside `Static` because it
deliberately lies under the whole lot. Placement comes from an integer hash of each
position (no RNG), colours from the existing swatches, and it is rebuilt only when
the street frame or lot changes. Every colour and planting knob lives in a `GroundSkin`
resource (`NeighbourhoodDressing.ground_skin`, default `GroundSkin.standard()`), so a
future site's neighbourhood and cuisine can re-skin the ground and tree line without
touching the geometry or the camera edge. The road, pavement and kerbs run on to the tree
line (actors keep their original span), and a low kerb step edges the pavement
where it meets grass. The clearing is the camera's world edge:
`CameraRig.set_world_bounds` (Main sets `NeighbourhoodDressing.world_rect()` after
framing) caps zoom to `world_zoom_limit()` so that, from any allowed pan and at
any rotation, the farthest visible ground point (`view_reach`) stays inside it.

The buildings are a street preset of their own (#422): `StreetSet` is a resource holding every
palette (wall, roof, door, hedge and bloom colours from the existing swatches), the allowed roof shapes
(gable front or side, hip, pyramid, shed, flat, false front), the wall heights, the fence styles, the
house count and the list of `ShopStyle` businesses (id, walls, awning stripes, blank sign board, door
and the one small thing it sets out: crate of loaves, flower buckets, portholes, jars, a table and
stools). Like `GroundSkin` it is swapped as a whole, so a seaside street (#425) supplies its own set:
`NeighbourhoodDressing.street_set` (null = `StreetSet.standard()`), part of every cache key.
`NeighbourhoodBuildings` plans and meshes it. Planning is cheap and pure: an integer hash of each
building's index and `StreetSet.seed_salt` (`NeighbourhoodGround.hash01`, no RNG) picks sizes,
heights, roofs and colours, avoiding the previous building's choice so neighbours differ. Two
shopfronts per side sit `GAP` (1.4 m) from the maximum lot, sharing the street line with awnings
over the paving and a 0.22 m hairline between row neighbours; five houses across the road each get a
lot (front fence line at 8.7 m from the street edge) with a gate, a path to the door, side and back
hedges, a mailbox, flower beds and a bush or small tree. Meshing is generated vertex-coloured boxes
and slabs (flat-shaded, shadowless, one surface per building, about 8.7k triangles in all, built in
about 20 ms and cached with the ground by street frame); no new art packs, and the old `shopfront`,
`house_body` and `gable_roof` models are no longer loaded. Near shops are kept off the lot by
geometry rather than a fade: the camera pitch is 54.7 degrees, so a point h metres up hides 0.5 h
of ground per axis along a diagonal view, and every near shop and roof stays under 2.7 m with a gap
of 1.4 m, so no resting view lets one hide any lot ground (checked per diagonal in
`test_neighbourhood_buildings.gd`). The ground builder receives the footprints and house lots so it
plants nothing on them, stretches the far lawn under the lots, and bakes lawn shadows for every
building (walls at wall height plus a narrower roof core at full height). Planning exposes
`building_footprints()`, `lot_footprints()` and `building_boxes_in_view()` for tools and tests.

Street furniture, night lamps and small life (#423) sit on top of the street set and stay view-only
(no colliders, nav, sim, saves, RNG or `Light3D`). `StreetSet.furniture` is a list of `StreetPropSpec`
(kind, count, kerb or wall zone), so a seaside street swaps the whole prop list with its other palettes;
the list, metal/red/bin colours, bird and leaf colours, bird and leaf counts and the sign sway angle are
all part of `StreetSet.signature()`. `NeighbourhoodFurniture` plans and meshes it in the street's local
frame: planter trees, benches, bins, a bike rack, a hydrant, a bus stop and a postbox stand only in the free
band of the near pavement (`BAND_LO` 0.56 m to `BAND_HI` 2.14 m from the street line, short of the near
walking lane at 2.255 m), never in front of the maximum lot (plus 0.5 m), the door approaches, the native
entrance pads and paths (0.2 m margin), a walking sweep, a neighbouring shop's door (0.75 m each side,
2.3 m deep) or another prop (0.3 m). A spot is the lowest-scoring free 0.25 m step along the street, scored by
`NeighbourhoodGround.hash01` (no RNG), distance from the lot, a cost for sitting near the same kind, and a
bonus for wall props in front of a shop and bins beside a bench. All props are one flat-shaded vertex-coloured
shadowless mesh (`PropBody`) and every prop, plus each street lamp's foot, has a baked translucent contact
shadow in one flat mesh (`PropShadows`) laid just above the paving, so everything stands on its own shadow;
shadow polygons are the convex hull of the footprint and the footprint pushed along the key light's ground run.
The planner runs on every dressing rebuild (a few milliseconds, no cache); `furniture_plan()` exposes it.
`NeighbourhoodBuildings` adds a flower box under each neighbouring shop window (the toy and pet shops
set a display shelf there instead) and a hanging sign bracket on each shop.

Night lamps: `Main._refresh_day_light` calls `NeighbourhoodDressing.set_night(DayNightView.street_night(look))`,
a smoothstep of the day's interior light (0 by day, 1 from dusk), so the street comes on with the shop. The
two street lamps get an emissive bulb mesh (emission energy and tint follow the night level), a soft additive
glow disc on the pavement and a camera-facing additive halo, all unlit meshes under `Life` that are hidden by
day: no `Light3D` is added.

Back gardens, softer roofs and shops (#440). The standard business set is a bakery, florist, sweet shop, tea
room, toy shop and pet shop (the laundromat is gone; `Accent.TOYS` and `Accent.PETS` add a rocking horse
and a dog bed out front, and a window display: blocks, a teddy and bunting, or a fish tank and a sleeping cat).
The roof palette is eight gentle warm and pastel swatch tones, and roof colours (like heights and roof shapes)
never repeat between neighbours in a row. Each house lot is `BACK_YARD` (2.6 m) deeper behind the back wall;
`NeighbourhoodBuildings._plan_garden` plans its back garden from integer hashes (no RNG): the garden ground is
the lot minus the side and back hedges (`GARDEN_SIDE`, `GARDEN_HEDGE`) and the eave, a doorstep patch in front
of the back door stays clear, then a flower border (55%), stepping stones (60%) and three or four of a small set
(vegetable bed, shed, washing line, swing, slide, table with parasol or jug, bench, fruit tree, birdbath; no
ponds or pools) each go at the best free spot by a per-kind preference plus hash noise, never overlapping, never
repeating the previous house's choices if another exists. `Plan.garden`, `garden_zone` and `doorstep` expose the
plan to tests (`tests/world/test_neighbourhood_gardens.gd` checks every item stays in its lot, off the hedges, the
doorstep and the lanes across twelve salts and two shifts). Gardens are drawn into the house's own mesh (no new
draw calls, about 4k more triangles in all) with opaque baked contact shadows in the lawn's shadow tone
(`lawn_shadow`, from the ground skin) swept along the key light's run (`light_shift`); both are part of the
buildings cache key, as are the new `StreetSet` fields (`soil`, `laundry_colors`, `play_colors`, `window_glows`).

Night windows (#440): every `_window` (and the shop display glass) can emit a warm quad just proud of its glass,
by integer hash: 12% stay dark (curtains), 63% stay lit all night, 12% go dark at an early bedtime and 13% later
(`GLOW_TIERS`). The quads of each tier are one unlit vertex-coloured mesh (`WindowGlow0..2`, three draw calls under
`Life`) with its own emissive material per dressing, driven by `NeighbourhoodDressing.set_night(level, late)`:
`level` is the same `DayNightView.street_night` as the lamps (tiers are hidden at 0) and `late` is
`DayNightView.street_late(minute, close_minute)`, 0 until closing time and 1 150 minutes later, which fades tier 1 out between 0.3 and 0.5
and tier 2 between 0.8 and 0.95. Main passes both from the day's minute (`day_light_minute()`); no `Light3D`
is added. The meshes are cached next to the buildings (`_window_cache`, same key); `window_state()` exposes the
tiers for tests and captures.

`NeighbourhoodLife` is the small life, a pure function of the dressing's display clock (the review time pins it),
applied from `_apply_time` so it stops with the dressing's processing. Hanging signs swing about their bracket
(`sign_angle`, at most `sign_sway_degrees`); each bird alternates between two spots on the lawn beside the lot
(`bird_pose`: pecks, looks up, hops two cycles in three, turns back; its own shadow is one MultiMesh); a few leaves
(one MultiMesh, `leaf_transform`) lift off the planter trees, tumble along the pavement and shrink away. Birds
stay outside the lot and every building and hop under 0.15 m. The whole addition is 15 draw calls and about
2,200 triangles; `tests/world/test_neighbourhood_props.gd` bounds both and checks the clear zones across
salts, lot sizes and the four rotations.

The camera still frames only the shop with its original defaults and expansion
glides. Main adds a three-metre extension to only the street-facing pan clamp;
the other sides and initial focus, yaw, pitch and zoom are unchanged. Frame-time
comparisons use the same normal-process harness, 60 warm-up plus 300 post-draw
intervals, in an exclusive local render lane; before/after values and adapter
limits belong in the PR, not an invented hardware or FPS acceptance threshold.

The floor shader adds a subtle multiplicative plank pattern while retaining its
existing paint colour and camera-controlled build-grid parameters (D25: it is
pattern 0 of `floor_finish.gdshader`, unchanged).

### Food and plate presentation (FK-054)
- `FoodPresentation` reads order, plate-ledger and agent-presentation state.
  Serving nodes and approved recipe models are warmed at layout boundaries;
  carried dishes inherit the smoothed person's palm/tray transform.
- Tabletop measurements retain the selected native horizontal triangles.
  At layout refresh, their merged outlines are inset by the measured plate
  radius plus 1 mm. Seat positions keep their rectangular inset where it
  fits; unsupported positions project to the cached safe outline, including
  round-table edges and counter cutouts. Degenerate or too-small surfaces
  retain the existing bounds fallback. Polygon construction and mesh reads
  never run in frame sync.
- READY food uses the actual pass basis, with three slots along one centered
  row. Further groups stack at the existing 0.025 m layer spacing. This fits
  the shallow native counter depth at every rotation without changing the
  kitchen's task, timing or plate ownership.

### Daily weather
`SimWorld.weather` is a separate `WeatherState` value per world, with stable
SUNNY 0 / CLOUDY 1 / RAIN 2 kinds and a chosen morning `day`; day 0 means unchosen.
`WeatherTuning` reads the relative 50/30/20 weights from
`data/balance/weather.tres`. Finite, nonnegative weights and a finite positive
sum are validated before selection. `ensure_today` consumes exactly one
`randf` from the caller's current `GameState.rng(&"weather")` for a new morning;
a repeated morning consumes none, and zero-weight bins stay impossible even
at the upper endpoint. No state/world retains that RNG across a new run.
Weather has no arrival, patience, economy, vibe or simulation-tick effect.

Main registers the existing save system's `weather` section as
`{version:1,day,kind}`. Restore validates into a detached staged value; the day
must match the saved Clock, and installation waits until the whole morning
load succeeds on its final world. Missing legacy sections install Sunny
already chosen for that saved day, without obtaining a weather stream.
Malformed present sections refuse. New mornings select before the existing
`_begin_morning` autosave; no new save point or SaveSystem code is added.
`WeatherText` centralizes Sunny/Cloudy/Rain, the forecast line and named icon
aliases; the future patio may read the value, but no patio behavior is added.

`WeatherView` preserves the original Environment, Sky, reflection, ambient,
directional and exposure settings. Only proven outdoor front pavement gets
private colour treatment and an additional reserved receiver bit `1<<18`
(layer 19); a weak cool OmniLight affects only that bit. Sunny, rebinding and
cleanup restore original material colours and masks. Rain is an unshaded,
shadowless deterministic MultiMesh with complete-column and camera-projected
built-volume exclusion. It uses no simulation RNG. Camera priority 0 precedes
weather priority 1 and Main priority 10, so the mask uses the rendered camera;
unchanged kind/world/dressing skips rebuilding, while terrain/camera changes
invalidate the appropriate cached geometry. HUD/Menu presentation is read-only.

### Concepts: drinks, Café and Bar, opening hours (FK-083)
- **No picker.** The concept is what the shop builds and serves. `VibeTuning`
  knows Café and Bar (`KNOWN_THEMES`, order and labels in `vibe.tres`);
  `theme_item_weights` lets named equipment vote though its category weighs 0
  (coffee machine, drinks fridge, drinks shelf). Fitting items and dishes are
  tagged in data. `CustomerType.liked_themes`/`liked_theme_bonus` (Students:
  Café, Regulars: Bar) multiply the picker weight by `1 + bonus * strength`
  only while that theme is active; otherwise the weight is untouched.
- **Drinks.** `RecipeDef.order_type` is `food`, `coffee` or `drinks`
  (`is_drink()`). Each drink has one step at its station: `coffee`
  (Coffee machine, Kenney cabinet + `kitchenCoffeeMachine`), `drinks_fridge`
  (`kitchenFridgeSmall`), `drinks_shelf` (`bookcaseOpenLow` + Food Kit bottles).
  The croissant is food warmed at the coffee machine. `RestaurantSim.create`
  leaves drinks, and dishes needing a station type the world lacks, off its
  default menu; Main's menu catalogue is what the live stations can make
  (`_cookable_live`, refreshed after every accepted edit, undo and redo via
  `MenuSettings.set_catalogue`: kept dishes keep their choices, new ones join
  drinks switched on and dishes off, removed ones leave and their choices are
  stashed until the next phase change, so an undo/redo brings back price and
  toggle; a dish switched on only because nothing else was left goes off
  again when they return). A loaded morning applies the same live catalogue,
  and a save missing a disabled dish's price loads it off at standard. A
  drink station staff cannot reach from the street (a bar closed on all
  sides) does not count, and pours skip it for a reachable one; the Drinks
  hints then say "staff can't reach the drinks shelf". Edits never buy stock, so undo stays exact: station-only
  supplies for today's menu are topped up when the shop opens
  (`_restock_station_supplies`), and by the next morning order after that.
- **Pour task.** `Kitchen._on_order_placed` sends a drink to `_post_pour`: a
  priority-3 `pour` task for the server role (job Serving, service XP): walk to
  a free station of the type, take the ingredient, make it, set quality from
  server skill and station bonus (READY; the station hold is released here,
  before the walk), carry it to the guest and hand it over (DELIVERED). No
  kitchen fridge, pass or plate. No station: the ticket cancels
  `missing_station`. Step labels use item names ("walking to the drinks shelf").
- **Counters.** `ItemDef.serve_across` marks bar pieces (`bar_section`,
  `bar_end_left/right`, `bar_corner`, and the long `bar_counter`). They are
  1x1 TABLEs; any stool facing one links as its seat (`DiningSeats`).
  `RestaurantSim.across_cell` is the clear, connected cell behind the counter
  opposite a seat; `service_cells` returns it, else the seat's neighbours.
  Order taking, food delivery, drinks and `_serve_order` all use it, so
  ordinary tables behave exactly as before.
- **Visits.** `VisitTuning` (`data/balance/visits.tres`) holds 24 hourly
  weights per order type. `RestaurantSim.visit_kinds()` lists the kinds on
  today's menu (not sold out); with one kind the spawner draws nothing. With
  several, `CustomerSpawner.choose_visit` makes one draw on the customers
  stream weighted by hour x `CustomerType.visit_weights`. Gaps scale by the
  summed weight (`scaled_gap`; exactly the drawn gap at 1.0, which food has
  for every default hour). A drinks-only guest orders only that kind, tries
  serve-across counters first, stays `drink_visit_ticks` and leaves no dirty
  table. A meal guest draws `drink_add_chance` (per type) only when a drink is
  available, then one pick; the drink is a second `Order` (`drink_order`),
  paid with the meal if it arrived, cancelled otherwise, never a reason to leave.
  A coffee-only guest likewise draws `pastry_add_chance` only when a
  `RecipeDef.with_drinks` dish (the croissant) is available; that pastry is
  cooked and plated as usual, the guest starts their coffee once it arrives
  (if patience runs out first, the pastry is cancelled and the coffee is
  still drunk and paid), and the seat is then cleared like a meal's. Both extras use `extra_order`.
- **Parties at counters.** Party seating still looks for one table with
  enough reachable seats. A 1x1 counter piece seats one stool, so groups
  take tables (or the long two-cell bar counter); drinks-only parties do too.
  Counters are mainly for singles, which is most drinks-only traffic.
- **Order counter (#293).** `data/items/order_counter.tres` (Bar & Café, $120,
  level 1) is a 2x1 STATION with `station_type` `order_counter`, so the editor's
  work-cell reachability warning covers it. It reuses the bar counter's
  projection: one work cell is the **staff side** (a server stands there, the
  till), the first seat cell is the guest's **order cell** and the other seat
  cell a **pickup cell**. `RestaurantSim.across_cell` accepts it like a
  `serve_across` piece, so `service_cells` hands a drink across from behind.
  `OrderCounter` (src/sim/restaurant, static helpers, no state) lists the
  counters, a counter's usable cells and its **line**: straight out from the
  order cell while the floor is clear, then bending along the wall (the side
  nearest the street door) for up to `LINE_LENGTH` (6) cells, never on a seat,
  work cell or the door lane. A short queue stands one clear cell apart (3
  places), a longer one packs one per cell (6 places, `queue_cells`). Only a shop that has a usable counter (a clear staff
  cell behind the order cell, the order cell reachable) takes the new path.
  A solo drink/coffee guest (`CustomerAgent._join_counter`; parties, food
  visits and critics keep table service) makes one draw on its own stream
  (`takeaway_wanted`, `VisitTuning.takeaway_share`, 0.3) and its queue patience
  is scaled once by `counter_patience_multiplier` (2.0). Visit: `QUEUED` in the
  line (`counter_stage` LINE; rank by join tick then id picks the line cell, the
  front guest claims a free order cell) -> `WALKING_TO_SEAT` to the order cell
  (TO_COUNTER) -> `ORDERING` there (AT_COUNTER; a priority-3, 15-tick
  `take_order` task (ties with pour/deliver at 3, urgency (#310) breaks the tie;
  a table order is priority 2 and 30 ticks) whose approach
  step is the staff cell, so there is no table order task) ->
  on the order, the guest heads for what was booked at the counter (TO_DEST):
  a free table, nearest first, or, when `takeaway_wanted` or no table is free,
  a takeaway at the pickup cell (or the order cell when there is no pickup
  spot). The order's `table_item_id`/`seat_cell` are that destination, so the
  pour or delivery is the ordinary one. A takeaway guest never sits (the view
  only seats guests at TABLE items), pays when the drink is handed over (state
  `PAYING` straight from `DELIVERED`, then happy), and a takeaway pastry bypasses
  the plate cycle (`Kitchen.bypass_plate`), so nothing is left to bus. Sales are
  the usual `customer_paid`; `RestaurantSim.takeaways_today` feeds
  `DayReport.takeaways` (saved only when above 0) and the evening report's
  "Takeaways: N" line. A guest in the line who waits out the patience leaves as
  `waited_too_long`. A shop without a counter takes no new branch and draws
  nothing extra (`test_a_cafe_without_a_counter_keeps_its_table_service_exactly`
  replays a recorded café). Probe set-up `coffee_counter` is `coffee_shop` plus a
  counter continuing the bar along its row (7, or 8 in the deeper room; x 13-14). Over ten seeds and five
  days it serves 93.8 guests against `coffee_shop`'s 88.0 (sales 558 vs 524,
  profit 98 vs 67): the till order is half as long and the server never walks to
  a table to take it, a takeaway is handed over at the counter, and a full house
  sends a drink-only guest away with a cup instead of nothing (no-table losses
  42 -> 23); guests who time out in the line (`waited too long`, 8 -> 27) are the
  new limit. Capture:
  `bash tools/screenshot.sh --scene=res://tools/order_counter_review.tscn --speed=0 --frames=90,330`.
- **Opening hours.** `OpeningHours` + `data/balance/hours.tres` (06:00 to
  24:00, 4 to 13 hours, 30-minute steps, 6 ticks a minute). Morning only, the
  hours set the clock's display minutes and `open_ticks`, so they ride in the
  existing `clock` section of the morning save; a load with hours outside the
  limits keeps the game and resets only the hours to the default day (logged).
  Wages are paid by the hour (`wage_for_day`; the default day is exactly the
  old daily wage), and the Staff panel shows wages for today's hours. A
  midnight close reads "24:00". The Menu panel shows the hours,
  then Food, then Drinks with named hints for missing stations.
- **Stock.** `EconomyTuning.station_stock` holds default targets for
  station-only ingredients. `ReorderSettings` lists and orders them only
  while a dish on the menu uses them (`set_in_use`; switching one on in the
  morning tops it up at once), and saves their rows only when changed, so
  default orders and saves are unchanged.
- **Food-only compatibility**: `tests/world/test_default_play_golden.gd`
  records two seeded days in the historical manual-stock shop. Its original
  main 6f6495d provenance is retained; current physical traffic has its own
  recorded outcomes and separate throughput comparisons. Probe set-ups `coffee_shop`
  and `bar` build, stock and staff a concept (`ProbeSetups.morning` switches
  on newly unlocked drinks). Tests: `tests/sim/test_concepts.gd`,
  `tests/world/test_concept_session.gd`, counter head clearance in
  `tests/world/test_seated_head_clearance.gd`.

### Waiting benches (FK-106)

- `data/items/waiting_bench.tres` reuses the approved low-back Kenney bench
  wrapper: two waiting places, $35, available from level 1 under Dining >
  Seating. The appended `ItemDef.Category.WAITING` keeps its seat reservations
  separate from `DiningSeats`, table capacity and the restroom threshold.
- A queued guest tries a table first, then `WaitingBench` chooses a free bench
  seat, nearest to the street door and then in placement/seat order. The guest
  walks there using the ordinary guest path and sits only after arriving at
  their reserved cell. Parties keep their existing arrival priority and
  shared least-patient-member deadline; they can use separate waiting spots
  but still move to one dining table together. There is no queue cap.
- Only actual bench arrival grants the one-time
  `VisitTuning.waiting_bench_patience_multiplier` (1.5 in
  `data/balance/visits.tres`). A walking or standing guest gets no bonus. A
  bench booking is released when a table is assigned or the guest leaves;
  removed or inaccessible benches release their stale bookings. No RNG is
  consumed, and a shop without benches keeps its exact existing behavior.
- `RoomRules` requires guest-reachable Dining cells, separate from dining
  seats. A bench more than `waiting_bench_door_distance` (8 grid cells) from
  the nearest street entry produces a normal nonblocking Build warning.
- The view uses the bench's existing seat surface, front and sit animation;
  a queued guest never receives a dining order there. `ReviewVisit.waited_seated`
  selects the `comfortable_wait` quote when the guest's complaint would
  otherwise be slow seating, while retaining food, price and restroom issues.
  The bench uses the ordinary placed-item snapshot. Waiting state is visit-only
  and is never saved; morning autosave remains the only game save point.
- Coverage: `tests/sim/test_waiting_bench.gd` and
  `tests/world/test_waiting_bench_view.gd`. The former includes a real-kitchen
  busy-service comparison. For a rendered seated-party fixture, run
  `bash tools/screenshot.sh --scene=res://tools/waiting_bench_review.tscn --speed=0 --frames=60`.
  Dining seats are explicitly held in that fixture; it is not balance evidence.
  The existing unmodified `--door-queue` capture continues to exercise ordinary
  queue behavior.

### Fish tanks (#125)
- **Content:** `data/items/aquarium.tres` (2×1, $180, level 3, charm 4) and
  `aquarium_large.tres` (3×1, $320, level 5, charm 5), DECOR with `cosy` and
  `seafood` tags and `ItemDef.fish_tank`. Ordinary solid decor: the usual edit
  rules apply. Made art in `assets/made/aquarium/` (see its README section).
- **Fish (view only):** `AquariumView` (a `PropView`) adds 4–6 fish that swim
  `AquariumSwim` loops: wide ellipses with a second harmonic round the tank, a
  small bob, a tail wag, nose along the tangent, so each fish turns at the end
  glass. One school of two or three of a kind shares a loop, each a fixed
  distance behind. Plans come from a local generator seeded by the placed item
  id (never `GameState` streams, never saved); fish time is display seconds.
  Bounds are proved: a fish's centre stays inside the swim box shrunk by the
  fish's half sizes (measured by the build script), so the whole fish stays in
  the glass. `set_review_time` pins a still for captures.
- **Upkeep (sim):** `AquariumCare` keeps each tank's last cleaning day. A tank
  is cloudy once `cloudy_after_days` (4) days have passed: a pure function of
  the day, so no tick, no random draw. `data/balance/aquarium.tres` holds the
  toggle (`maintenance`, on), the days, the cloudy charm share (0.5) and the
  clean's work ticks. `CleanTaskController.sync_tanks()` posts one
  `clean_tank` task ("Clean the fish tank") per cloudy tank: walk to a free
  floor cell beside it, then work. The cleaner takes it; with no cleaner, the
  owner on Floor (never a server). The job is Cleaning. The task is withdrawn
  overnight and posted again while the tank stays cloudy. Placing a tank starts
  it clean; moving keeps its record; removing forgets it.
- **Charm:** `VibeInputs.capture()` takes item id → charm share
  (`AquariumCare.charm_factors()`), carried as `VibeModel.Item.charm_scale`.
  Copies of one definition keep one charm; with any share below 1 the repeats
  are summed fullest first (charm × Σ share_k × decay^k). With no shares the
  old closed-form sum runs unchanged. Main recomputes the vibe each morning and
  when a tank is cleaned (`AquariumCare.changed`).
- **Save:** section `aquarium`, `{version: 1, tanks: [{def_id, origin,
  cleaned_day}]}`, matched to the restored layout by kind and position (item
  ids are not kept by a load). Validated before install; missing rows and old
  saves start a tank clean today. Written only by the morning autosave.
- **Look:** cloudy tanks swap the glass and water for murky copies mixed toward
  the tank's own `plant` green (`ShopView._sync_tanks`). The Inspect panel shows
  the water ("clear, needs a clean in N days" or "cloudy"). No light nodes.
- **Review:** `tools/aquarium_review.tscn` (frames 30, 60, 90; set
  `AQUARIUM_REVIEW_CLOUDY=1` for the cloudy look).

### The restaurant cat (#119)
- **Sim.** `RestaurantCat` (`src/sim/pets/`) is a `RefCounted` owned by `RestaurantSim.cat`. It is **not** a `SimAgent`: it is never in `world.agents`, so it joins no `MovementCoordinator` traffic, reserves no cell or seat and blocks nobody (people and the cat may share a cell). Tuning is `CatTuning` in `data/balance/cat.tres`: unlock level 4, $40 adoption, $2 a day, charm radius 2 and +10%, pet radius 1, walking and nap timings.
- **Where it goes.** `cell_ok`: `Terrain.FLOOR`, guest-walkable (no staff room, no back door), room Dining or Restroom, nothing on the NORMAL layer. Steps use `SimGrid.guest_neighbours`, so it respects wall edges and the corner rule. A bounded breadth-first search (`wander_range` steps, fixed neighbour order) picks strolls and nap trips. Nap spots (`nap_spots`, cached per `grid.version`) are the cells beside a window (an interior or outer window edge, or one of `ExteriorSupport.window_cells`); with no window, the cells beside a wall. The bed spot is the first nap spot in reading order. `begin_day` (from `RestaurantSim.start_day`) puts it there asleep and draws no random number; `layout_changed` (from the grid's `cells_changed`) sends it back if an edit lands on it. A nap lies along the wall, not into it.
- **Random numbers.** Only `GameState.rng(&"cat")`, passed in by Main with `use_rng`; the fallback seed is fixed. Same seed, same path (`tests/sim/test_restaurant_cat.gd`).
- **Charm.** `CustomerAgent._cat_relief` hands back one waiting tick every ~11 while the guest is within `charm_radius` of the cat (`refund_per_tick = b / (1 + b)`, so +10% patience lasts exactly 10% longer), for table waits (`_queue_wait`, and a party's shared wait) and food waits (`_food_wait`). Petting: a guest that `is_waiting_in_shop()` within `pet_radius` sets `petted_cat` once per visit; the cat stands still for `pet_pause_ticks` facing them. `ReviewVisit.petted_cat` selects the `petted_cat` quote (three lines in `data/reviews/quotes.tres`) when the review would otherwise be positive; any real complaint still wins.
- **Money.** The morning Menu panel's `CatOffer` (`MenuPanel.set_cat_offer`, `cat_adoption_requested`) shows from level 4 until adopted. `Main.adopt_cat` charges `Ledger.UPGRADES` once; `_charge_closing_costs` adds `Ledger.CAT_FOOD` (`Cat food`) every day while adopted.
- **Save.** Section `cat`: `{version: 1, adopted, name}` (name defaults to "Biscuit"); position is not saved. A save without the section loads as no cat; a malformed section refuses the load like any other. Morning autosave remains the only save point.
- **View.** `CatView` (a child of `ShopView`, `src/world/cat_view.gd`) loads `assets/made/cat/cat.glb`, scales it by `ArtScale.CAT_SCALE`, draws the sim position blended between its last two cells with the same one-tick-behind alpha as people, and plays `walk` (tempo matched to the step speed), `nap` or `idle`. Hidden until adopted. Capture: `bash tools/screenshot.sh --scene=res://tools/cat_review.tscn --speed=0 --frames=30,70,110` (walking and napping beside a Mini Character, then the shop as played).
- **Art.** `tools/build_cat.py` (Blender) makes `assets/made/cat/cat.glb`; see `assets/made/README.md`.
- Coverage: `tests/sim/test_restaurant_cat.gd`, `tests/world/test_cat_session.gd`.

### The health inspector (#302)
- **Sim.** `src/sim/inspection/`: `InspectionTuning` (`data/balance/inspection.tres`: unlock level 3, 7 days apart, 15% a day, arrival window 15-55% of the open ticks, 600-tick visit, per-finding points, grade lines, factors 1.05 / 1.0 / 0.9 for 7 days), `InspectionModel` (`capture(sim)` reads dirty tables, floor spots, restroom spots, today's spoiled stock value and dirty plates; `evaluate` turns them into `{points, grade, findings}`, worst first), `InspectionText` (all player words) and `InspectionBook` (the schedule, the last grade and day, `arrival_factor(day)`). `RestaurantSim.inspection` owns the book; `RestaurantSim.inspector` is the `InspectorAgent` while a visit is on.
- **A real person.** `InspectorAgent` is a `SimAgent` on the guest layer (`uses_guest_layer()`, which `MovementCoordinator` now asks instead of `is CustomerAgent`): it reserves cells like a guest, at guest priority, and is not a `CustomerAgent`, so it is not in `customers()`: no table, order, payment, review, lost-guest count or arrival gap. Its stops (evenly spread dining cells, one restroom cell, nearest first) come from the grid, with no random number. It looks at each stop for `look_ticks` and gives up a stop after 400 ticks; after `visit_ticks` (or `visit_cap_ticks` at the latest) it walks out. Closing removes it that tick. The grade comes from the shop as the sim read it at the last stop they looked at, so a visit cut short is still graded; one that reached no stop gets no grade and starts no cooldown. The planned arrival tick is re-clamped to the day's open window on arrival. The pass-crowding spill count in `Kitchen` ignores the inspector. Stops avoid the door lane and any item work cell, are found with one flood fill, and a stuck inspector tries the other door after 300 idle ticks and is removed after 600.
- **Random numbers.** Only `GameState.rng(&"inspector")`, passed to `InspectionBook.plan_day` as a callable that Main binds. It is asked for only on a morning a visit is possible (level 3, a week since the last), so games below level 3 never create the stream and every other stream is unchanged. A chance draw and, on a hit, one arrival-tick draw; `planned_day` is saved so a reloaded morning does not draw again.
- **Effect.** `Main._street_factor(day)` is `curb_appeal_factor * inspection.arrival_factor(day)`, fed to `DemandBreakdown` in place of the curb-appeal factor (so the crowd forecast's street line includes the grade). The factor applies on days visit+1 .. visit+7.
- **Save.** Section `inspection`: `{version: 1, last_grade, last_day, planned_day, planned_tick}`. No section loads as never inspected; a malformed one refuses the load.
- **Report and UI.** `DayReport.inspection_lines` (saved only when present) shows as an `Inspection` label in the evening report; `HygieneOverview.Snapshot.inspection_line` adds "Last inspection: B, day 12" (or "none yet" from level 3).
- **View.** Role `inspector` in `PersonPresentation` uses `character-female-a` with a slate repaint of its clothes and a `Clipboard` node on `person.tscn` held at the palms of the carry pose. `WallFinishView.set_inspection_grade` hangs a grade card on the outside of the street window nearest the door (a frontage pane or a window the player cut), like the OPEN sign; `ShopView` keeps it in step with the book. The card stays up until the next inspection replaces it, long after the 7-day nudge ends; with no street window or door it is simply not shown. Capture: `bash tools/screenshot.sh --scene=res://tools/inspector_review.tscn --speed=0 --frames=30,70,110` (`INSPECTOR_REVIEW_GRADE=A|B|C`).
- Coverage: `tests/sim/test_inspection.gd`, `tests/world/test_inspection_session.gd`.
### The disguised food critic (#303)
- Data: `data/balance/critic.tres` (`CriticTuning`): unlock level 2, cooldown 5 days, daily chance 0.2, review weight 3, 2 tells, linger x1.2, quality weight, arrival windows (permille of the open hours; the late odd hour ends at 70%, so they can still be served). Six quotes (3 `critic_good`, 3 `critic_bad`) are in `data/reviews/quotes.tres`.
- `FoodCritic` (`src/sim/critics/food_critic.gd`) rolls the day once in `RestaurantSim.start_day()` (the morning), from the named stream `GameState.rng(&"critic")`, passed as the lazy provider `critic_rng_provider`. The provider is called only when a critic can appear (level reached and out of cooldown), so shops that cannot have one never create the stream and keep their exact saved streams (a test runs a multi-day service with and without the critic system and compares the customer and review streams). On a critic day the guests' timing and orders differ, so later draws on the customer and review streams can shift from a run without one. Four tells exist: a notebook prop, the dearest dish, an odd hour (very early or very late arrival), lingering. Two are drawn.
- The critic is an ordinary solo arrival once their hour has come: `CustomerSpawner` makes the arrival with exactly the draws it always made, then `RestaurantSim.try_disguise_critic()` adds the disguise (`CustomerAgent.disguise_as_critic`). Named regulars, parties and drinks-only visits are skipped; the next lone food guest takes the role, and the critic gives back the repeat-guest cohort slot they took. The 5-day cooldown starts when they arrive (`mark_arrived`), so a day with no fitting arrival costs nothing.
- The review is `ReputationBook.record_critic()`: it scores the visit with the usual `score_visit` (so wait, food quality, vibe and cleanliness all count; the critic's quality weight is higher), appends the stars min(`review_weight`, a quarter of the reviews held, at least 1) times (a fresh shop with 5 reviews gets 1 copy), and picks a `critic_good` / `critic_bad` quote from the critic's own stream. Only a critic who sat and ordered reviews (`customer.order != null`, not removed, not closing); one who never sat, or met no menu or no stock before ordering, gives nothing, and one who ordered but left unserved gives a 1-star review. It is not in `reviews_today` (no ordinary card, no five-star XP); `RestaurantSim.critic_result` feeds `DayReport.critic_lines` ("A food critic visited today", verdict, quote).
- The Inspect panel lists the tells in plain words (`FoodCritic.tell_lines`) and never the word "critic". The notebook is a small box prop in `ShopView` (`Frame.holds_notebook`).
- Saving: the `critic` section holds the last visit day and today's plan (rolled once per day, so a reload neither redraws nor forgets the cooldown). Absent in old saves.
- Review capture: `tools/critic_review.tscn` (`food-critic` in `visual-review.yml`).

### 2.3i Stock panel, auto-reorder and sold-out dishes (FK-033, #54)
- **Served-food accounting (FK-121, #255).** Stock lots retain their actual
  remaining purchase cost, including the charged standing-order premium.
  `PurchaseBasis` shares the premium equally across purchase lines (earlier
  lines receive any whole-unit remainder), then FIFO lots share their total
  across units by quotient and remainder. Partial takes, deliveries, crate
  put-away, expiry and JSON reload conserve that value without repricing it.
  Old lots without cost metadata stay explicitly unrecorded. Aggregate value
  overflow makes the valuation unavailable and never refuses a stock movement.
  Kitchen captures the atomic take's cost on the order once; Main includes it
  only when that order is actually paid, including side drinks. Cancelled or
  unpaid prepared food does not enter the sold-food cost.
  `DayReport.operating_profit()` substitutes this sold-food cost for the signed
  ingredient-purchase net, excluding milestone bonuses and financing as before.
  Raw income/cost dictionaries and `profit()` retain actual cash movement;
  `purchase_basis_operating_profit()` preserves existing goal previews, and
  closing XP/milestone/loan policy still uses the existing ledger input.
  The report shows purchases, spoilage, remaining stock value and cash change
  separately, and hides exact unavailable values. New optional report and batch
  values use decimal strings. A day-scoped spoilage receipt in the existing
  stock save survives the morning reload without expiring stock twice. There
  is no new save section, save point, random stream or random draw.
- **Forecast stock targets (Director's #255 addendum).** Untouched automatic
  targets cover approximately one service plus `EconomyTuning.restock_buffer`.
  `RestockForecast` combines the existing demand guest estimate, enabled
  cookable recipes, repeated ingredients, authored opening-hour visit weights
  and the eligible customer mix's optional drink/pastry chances. It assumes
  equal dish choices within each visit kind; it does not simulate future guests.
  A recipe's primary and optional side portions combine before the buffer is
  applied and rounded up once to a whole portion, then expand into ingredient
  units. This can add up to one extra portion per recipe beyond the fractional
  estimate; the final quantity, cash and storage caps still apply.
  Morning and opening orders use the service being stocked; closing stock and
  build-budget forecasts use the existing next-day demand projection. All use
  the same ordinary cash/storage-limited order planner. Targets never exceed
  the existing 99-unit limit. Evaluating a forecast returns a detached settings
  copy and does not rewrite saved choices. Changing a target fixes that player's
  value; an optional saved `manual` flag preserves it. Legacy targets matching
  their authored defaults remain automatic, while custom legacy targets stay
  fixed. Only the existing morning autosave writes these choices.
- `ReorderSettings` (`src/sim/economy/reorder_settings.gd`) holds `{enabled, target}`
  per ingredient, with optional `manual` metadata as described above. The
  `EconomyTuning.morning_stock` key order remains the fixed buying order. It is
  saved in the `reorder` section at the morning autosave
  only; restore stages a candidate installed after a complete morning load. A save
  without the section uses the defaults; unknown ids are ignored.
- **Morning order:** `ReorderSettings.plan(stock, unit_costs, cash, premium)` tops
  enabled ingredients up to target. The premium applies once to the order total:
  `auto_cost = ceil(list_total * (1 + auto_reorder_premium))` (tier 1: 0.05), in integer basis
  points (at 0.10, 10 x $1 = $11). With short cash each ingredient in the fixed order gets as
  many units as still fit, the partial order priced as its own total; the rest is
  logged and nothing is borrowed. `Economy.buy_auto_order` records each line at list
  price plus one `auto_reorder_premium` ingredients entry. Main's
  `auto_reorder_premium` mirrors the tuning (tests not about pricing may set 0).
- **Expiry:** `_begin_morning()` calls `Stock.expire(day, shelf lives)` before the
  order; `Stock.expiring_on(day)` previews it. "Expire tomorrow" means removed at the
  next morning. Reloading the same morning removes nothing more.
- **Stock panel** (`src/ui/stock_panel.gd`, HUD basket button): since FK-087 an order
  cart open in every phase (2.3j), request signals to Main (`stock_set_auto`,
  `stock_set_target`, and the cart requests). Rows carry display names only; notes report this morning's
  order (read back from the day's ledger: lines noted `auto_reorder:<id>` plus the
  `auto_reorder_premium` entry, so a reloaded morning still shows it), cash
  shortfalls (re-planned on reload) and thrown-out stock (not kept: after a reload
  of the same morning that note is gone, since nothing is thrown out twice).
  The first load of a save from before expiry removes everything already past its
  shelf life once.
- **Sold out:** during OPEN/LAST_ORDERS `RestaurantSim.refresh_sold_out()` (each tick
  and before every order) latches a menu dish for the rest of the day once the
  fridge itself cannot cover it (stock only falls during service). `available_menu()`
  also holds back, without latching, dishes whose last portions are promised to
  accepted tickets (`Kitchen.committed_ingredients()`, cook not yet at the fridge);
  a cancelled ticket returns them. `stock_outs_today` records
  `{ingredient, minute, dishes}`, the minute continuing past closing time during
  last orders (`service_minute()`). Guests draw once over `available_menu()`
  (unchanged stream while nothing is sold out; the same single draw over the shorter
  list afterwards) and leave with `out_of_stock` only when it is empty. A ticket
  cancelled at the fridge still cancels as before. The HUD shows a "Sold out" chip
  during service.
- **Build restock advice (FK-096):** a valid Buy, wall, floor-expansion or
  floor-laying preview may add one advice line under the existing HUD hint,
  "Leaves $75 — tomorrow's restock needs about $93" (`RestockBudgetWarning`),
  passed to `HUD.set_build_state()` as `warning` and drawn in the HUD's amber
  `ADVICE_COLOR` (not red: it is not an error; the cost line keeps its colour).
  It never changes `EditCheck.ok`, prices, refunds, purchase
  permission, stock, paid orders, RNG or saving. Morning advice reserves a
  conservative refill of enabled targets after service (limited by current
  storage and excluding units paid but not yet stocked: orders on their way and
  crates waiting to be put away, the same `_on_the_way()` the real order uses);
  at closing the existing `StockAlerts.forecast` supplies the next morning's
  full order cost after expiry and incoming stock. Both reuse the ordinary order
  planner/premium. This is a budget allowance, not a forecast of future sales or
  operating losses. Invalid actions keep their original refusal, and free
  edits/sales add no advice. Cash changes refresh the hint even when placement
  validity stays unchanged.
- **Report:** `DayReport.low_stock` holds `StockAlerts` sentences: each ingredient
  that sold dishes out (with the time), then tomorrow's forecast (tonight's expiry,
  then the order planned with tonight's cash): expiring units, ingredients the order
  will not cover (switched off or short of cash) and the order's cost.

### 2.3j Storage and deliveries (FK-087, #162)
- **Storage kinds (data).** `IngredientDef.storage` is `FRIDGE`, `FREEZER` or `SHELF`
  (dry). Fridge: beef patty, cheese, lettuce; everything else (bread, buns, soup
  stock, tomatoes and #183's station-only coffee beans, tea, soft drinks, beer,
  wine, pastries) is dry. `ItemDef.storage_kind` + `storage_units` say how much an
  item holds (`capacity` stays the station job count). The fridge holds 40 fridge
  units; the new **Storage shelf** (`storage_shelf`, Kitchen tab, $60, level 1,
  Kenney `bookcaseOpen` with Food Kit barrels, loaves, a carton, bags and a can
  plus two Furniture Kit `cardboardBoxClosed` on top) holds 40 dry units.
  `ShopLayout.pantry_units` is built-in dry storage: the starter shop's back-room
  pantry has 60 (the starter order is 28 fridge and 50 dry units).
- **Capacity contract (director, #154).** `StorageSpace` (src/sim/economy, pure) sums
  units per kind across every ingredient of that kind; items of one kind add up
  (`capacities(grid, pantry, exclude_id)`). Used space is stock on hand **plus
  orders not yet delivered**, so a delivery always fits when it arrives
  (`committed`, `free_units`, `first_overflow`). A hand order that would overfill
  a kind is refused ("Not enough fridge space" / "freezer" / "dry storage"; only
  the added ingredient's own kind is checked, so a cart in another kind never
  blocks it); the
  auto-reorder (`ReorderSettings.plan(..., space)`) buys up to the free space in
  the fixed order and returns `unfit`, which the Stock notes, the log and the
  evening forecast report ("Not enough fridge space to reorder 8."); the panel
  opens itself on a morning when something did not fit. Selling storage the stock
  still needs is refused in Build ("Move stock out first: the fridge stock would
  not fit without it"): `ShopEditor.storage_need` (a Callable Main sets) is checked
  in `check_sell`, which undo and redo also use, so an overflowing undo is refused
  like any other. Old saves over capacity keep every unit; new orders of that kind
  are blocked until it is back under, and the notes say so.
- **Throw out (Jared).** Each Stock row has a two-click Throw out button (the
  first click shows "Click again", any other panel action or closing the
  panel takes it back). `Main.stock_throw_out(id)` removes all of that stock
  with no refund. Like stock that goes off at expiry it moves no money, so it
  adds no ledger line; the log and a Stock note ("Thrown out today (no
  refund): 8 Soup stock.") record it. This is how a shop changing concept, or
  an old over-full save, makes room.
- **Deliveries.** `DeliveryBook` (src/sim/economy, pure) holds paid orders not yet
  delivered: `{due: Vector2i(day, tick), lines, cost, standing}`. **Orders placed
  in the MORNING arrive at once** (Jared), as #156's buys did: the standing order
  and hand orders are paid and stocked immediately and never wait in the book.
  During service an order arrives with the next daytime delivery, every
  `EconomyTuning.delivery_interval_minutes` (180) of opening hours
  (`slot_ticks`, scaled to the clock's service length: 14:00, 17:00, 20:00 on the
  default day). After the last one, in LAST_ORDERS or once closed, it comes with
  the next morning's delivery (`MORNING`, tick -1), unloaded in `_begin_morning`
  before the standing order and the save. There is no separate opening
  delivery; #183's top-up of drink supplies at opening is still bought and
  stocked at opening. Main also delivers on `EventBus.sim_ticked` while OPEN and
  on phase changes (anything overdue, e.g. a tick 0 order in an older save).
  A delivery due during service (OPEN or LAST_ORDERS) is visible (FK-099,
  below): its goods become stock as staff put them away. Anything that lands
  in the morning or once closed is stocked at once, dated the arrival day;
  `RestaurantSim.restock_sold_out()` brings back dishes the goods cover, and
  the Stock notes say what the last daytime delivery brought.
- **Next delivery bar.** `Main.delivery_countdown()`: in the morning "Morning
  orders arrive at once. Next delivery at 14:00" (bar full); during service
  "Next delivery at 14:00" with the wait's fraction; afterwards "Next delivery:
  tomorrow morning".
- **Cart.** The cart (`Main.stock_cart`) is not saved. A cart left from the day
  before is cut to the free space after the morning delivery, in panel order,
  and a note says by how much. Refusals are shown, never silent: storage,
  cash, more than 64 ingredients in one order, or 256 orders on the way; +/+5
  stop at 99 of one ingredient with that reason as the tooltip.
- **Paying and refunds.** Orders are paid when placed: `Economy.pay_order(lines,
  cost, standing)` records ledger lines without stock (hand orders at list price
  under the ingredient's note; standing orders with the `auto_reorder:` notes and
  one premium line), `Economy.receive(lines)` stocks a delivery and
  `buy_auto_order` is now pay + receive. Cancel refunds everything on order,
  premium included, as one `order_refund` ingredients line
  (`Main.stock_cancel_orders`).
- **Standing order.** The morning auto-reorder arrives at once
  (`Economy.buy_auto_order`), so with default settings it is exactly #156's
  order (same ledger lines and stock); targets count units already on order.
  Since standing orders never wait, only hand orders can be cancelled, and
  those are always charged and refunded on the same day (an order still on its
  way at closing arrives first thing next morning, before the player can act).
- **Saving (rule 9).** Pending orders are the `deliveries` save section, written by
  the morning autosave only; a save without it has nothing on order. Because the
  morning delivery is unloaded before that save, the book is normally empty
  there; a saved order (an older or hand-edited save) is delivered by the
  loaded morning. **An order placed after the morning save is lost on reload
  together with its payment**, like everything else since that save (the
  ledger is in the same save): money and goods go back together.
- **Order cart (UI).** `StockPanel.set_view(view)`: groups Fridge / Freezer / Dry
  (freezer only when the shop has freezer space or ingredients) with
  `in stock / capacity units` (plus on order and in the cart) and a fill bar;
  rows with −/+/+5 cart steppers (`cart_requested`), disabled with "Not enough …
  space" when a step would not fit; one label with the count, what is on order,
  expiry and "Not on today's menu"; Throw out (`throw_requested`); the running
  total, Clear cart, Place order
  (disabled with the refusal as its tooltip), what is on order with Cancel order,
  and the Next delivery bar (see above). Ingredients nothing
  on today's menu uses are listed after the used ones in their group, faded,
  "Not on today's menu", still orderable. The HUD Stock button works in every
  phase; the panel closes for the evening report. Reorder settings change in any
  phase and are saved at the next morning.
- **Spoilage.** Freezer ingredients keep at least `freezer_shelf_life_days` (30);
  fridge and dry keep their own `shelf_life_days`.
- **Freezer (FK-099).** The **Freezer** (`freezer`, Kitchen tab, $90, level 2,
  Kenney `kitchenFridgeLarge` on one cell) holds 40 freezer units; **Frozen
  fries** (`frozen_fries`, $1, keeps 30 days) are a freezer ingredient listed
  in `morning_stock` with a target of 0, so the auto-order never buys them
  until the player raises it. No dish uses them yet (Fries still use
  potatoes). The Stock panel lists the freezer's rows only while the shop has
  freezer room or anything frozen (`Main.stock_rows`), so the Freezer group
  appears once a freezer is bought.
- **Visible stock.** `ShopView.set_storage_fill(kind -> 0..1)` from Main (stock on
  hand / capacity per kind, refreshed with the presentation when it changes):
  a storage item's parts tagged `metadata/stock_slot` show the first
  `ceil(fill * slots)` (at least one while any stock is left), view only and
  deterministic. All dry shelves show the shared dry fill, pantry included.
- **Probe.** The default probe is identical to main. `coffee_shop` and `bar` now
  build two storage shelves (`ProbeSetups._storage_shelves`), as a player would:
  without them a concept's supplies do not fit beside the morning's food. Their
  rows are identical to main. `_finish` switches auto-reorder off only for the
  ingredients auto-reorder lists (`_reorder().ids()`), not the greyed rows.
- **Visible deliveries (FK-099, #187).** `DeliveryDock` (src/sim/restaurant,
  pure, owned by `RestaurantSim.dock`) takes a delivery due during service
  (`arrive(lines)`; false, and Main stocks at once, when the shop is not open
  or no route reaches storage). A `CourierAgent` (role `courier`, a world agent
  that holds no task, reservation or random stream) walks the
  `WallRules.delivery_route` along the back alley and up the back door's path
  (street door fallback, where she appears at the entry as guests do) and
  stops in the doorway. Her route starts and ends `ALLEY_REACH` (56) cells
  past the lot, so at the shop's framing and zoomed out to 26 she comes and
  goes out of sight in every camera quarter for back and side walls, so her
  fade at the far ends (below) happens off screen (her first on-screen route
  cell at zoom 26 is at least 10 in, past her 4 fade cells); zoomed further
  out (to 40) it shows. The one exception is closing: `store_all()` ends her
  visit wherever she is, possibly in view, and the view then keeps her last
  drawn figure as a ghost (`ShopView._keep_as_ghost`) that walks on and
  fades out over `GHOST_FADE_SECONDS` (1 s) with the same dither and no
  shadow, then frees it; a ghost is no agent (never picked or selected,
  opens no door, blocks nothing) and `show_world` clears it. She brings one crate per storage
  kind present (fridge, freezer, dry, in that order) and sets them down on the
  receiving cell just inside over `UNLOAD_TICKS` (4): the crate in her hands
  at `DROP_TICK` (2, the lowest point of the kit's 0.33 s `pick-up` bend),
  the rest on top of it once she has stepped away (`all_dropped`, her head
  clear of the stack). Then she walks back out; the dock removes her when
  gone. Off-lot cells are not on the grid, so she walks her planned cells
  without path finding. Guests never share the back door: they plan on the
  guest layer, where its cell is solid.
  - **Carrying.** Each crate is one `put_away` task (role `any`, priority 1,
    timeout 600; steps `STEP_WALK` .. `STEP_PUT_IN` and the fill): walk to the
    crate, pick it up (a wait step: the crate is in the hands
    `PICK_UP_TICKS` (2) ticks after the carrier arrives, the `pick-up` bend's
    lowest point, counted in ticks so a carrier's skill never moves it; then
    `LIFT_TICKS` 2 of work to straighten up), walk to the nearest
    reachable storage of its kind (else any storage: the starter shop's
    pantry is built in, behind the kitchen; else none, and it waits) and put
    it in (`PUT_IN_TICKS` 4), when its goods become stock (`Stock.add`, dated
    today) and `stored(lines)` fires, then fill the shelves (16 more, 20 in
    all as before); `RestaurantSim` then brings sold-out dishes
    back and Main refreshes the HUD and Stock panel. The carry walks to the
    storage's work cell without reserving it, so a cook at the same fridge
    never waits. A dropped task sets the crate down where its carrier stood
    and starts again from there; a failed one (storage sold on the way, say)
    puts it down and posts again, up to `MAX_TRIES` (3), then waits for a
    layout change. `on_done` steps check the crate's state, so a restarted
    task never stocks twice. Crates on a cell are one stack with no gaps
    (`slot` is the layer): whoever lifts one takes the top (the crate on top
    swaps places with the one whose task it is; crates look alike), so none
    is ever left in mid-air. A stack is at most `STACK_CAP` (3) high; a crate
    for a full stack goes to the nearest free cell (`_free_spot`: walkable,
    no door, street entry, work spot or seat, against a wall or item first),
    where it starts a stack of its own. With the stack inside the door full
    the delivery person keeps hold of her crate and the whole delivery goes
    down there as she leaves (`drop_layer` -1). The dock keeps
    `payload["layer"]` (the layer the carrier will lift) and
    `CourierAgent.drop_layer` current for the view.
  - **Who carries (job priority).** With a cleaner on the team it is the
    cleaner's (job Cleaning, their main job); otherwise servers do it as
    Serving (`StaffJobPriorities.ROLE_TASK_JOBS`: front-of-house work, so a
    mid-day order is put away during service rather than left to a Low
    fallback a busy server never reaches); what is still waiting at closing
    is stored. Cooks (Cleaning is Off for them) and the owner (no `any`
    priority) never carry. **Service cost (director, #195):** a shop taking
    several mid-day orders with no cleaner pays a visible cost, as servers
    leave guests to carry crates and goods reach the shelves later (probe,
    4 orders a day, 5 seeds x 5 days: 329 served against 361 when goods
    arrived at once); hiring a cleaner removes it (347 against 353; with one
    order a day 436, identical; measured with the 24-cell route, before
    #204 lengthened her walk to 56). Making servers wait for idle moments was
    tried and cost more (313): goods sat longer and dishes ran out. Closing
    withdraws the carrying tasks and frees their carriers on that tick
    (`StaffAgent.let_go_if_withdrawn`).
  - **Never lose goods.** Paid when ordered; while waiting the goods count as
    on order in `StorageSpace` (`Main._on_the_way()`), so their space stays
    reserved, Build refuses to sell storage they need, and the Stock rows
    show them on order with a note, "Still to be put away: 6 Soup stock.".
    `store_all()` stocks everything not yet put away (crates on the floor, in
    hands or still on the way), withdraws the carrying tasks and ends the
    visit: `RestaurantSim.advance` calls it on the tick service closes (before
    `service_closed`, so the books and forecast see the stock) and
    `start_day()` calls it each morning, so nothing is in transit at the
    morning save (rule 9; nothing new is saved). Morning orders still arrive
    at once, and with no order placed during service the dock does nothing:
    no agent, task or event (`test_no_orders_change_nothing`), so the
    balance probe is unchanged.
  - **View.** `ShopView.bind_dock`: waiting crates are Kenney
    `cardboardBoxClosed` at `CRATE_SCALE` (0.65), one stack per cell at
    `AgentPresentationController.crate_spot`: on a door's receiving cell
    `DOOR_STACK_INSET` towards the door (straddling the threshold), elsewhere
    `CRATE_INSET` off the centre. People never stand in it: the delivery
    person sets it down from the doorway and staff stand `reach_for(layer)`
    from it on the cell (`picker_spot`; the last step in walks there, the
    first step out walks from it): `CRATE_REACH` (0.27, the reach of the
    `pick-up` bend's lowest point) to bend to a crate on the floor,
    `CRATE_REACH_HIGH` (0.33) to reach one on top of another standing
    (`holding-both`, the crate sliding between palms and stack,
    `Frame.crate_slide`). A crate in hand (`Frame.crate_count`, one at a time
    for everyone) hangs `CRATE_GRIP` of its height below the palms (top under
    the chin), follows them through the bend without sinking below its layer,
    eases down from a high layer, and changes between hands and floor at the
    bend's lowest point; it goes into the storage at the put-in moment. The
    delivery person is `character-female-b` in her uniform. People carrying
    while walking play `carry-walk` (`PersonView` builds it from the kit's
    `walk` with the arms of `holding-both`, so legs walk under carrying arms;
    servers' trays use it too); switching among `pick-up`, `holding-both`
    and `carry-walk` blends over 0.12 s so arms (and the crate) never jump.
    The back door's leaf swings out and lies flat against the outside wall
    (`WallSegmentView`, hinged on the side with open ground beside it, clear
    of the path and of anyone on it). Up to square it turns inside the
    opening while its hinge moves out to the wall's outer face (stepping
    `DOOR_TURN_CLEARANCE` off the jamb mid-turn), and only then swings on
    round and slides onto the jamb, so no part of the leaf ever passes
    through the wall (`test_the_leaf_never_passes_through_the_wall` checks
    every mesh vertex at every 1%). Its opening follows the smoothed drawn
    positions, so it swings every frame. The delivery person fades in over the
    first `FADE_CELLS` (4) cells of her walk and out over the last ones
    (`Frame.fade`; `ShopView._apply_fade` gives each surface an opaque
    copy of its material that draws only that share of its pixels, a
    screen-door dither, so she fades as one solid figure with no part
    showing through another; the Compatibility renderer has no per-instance
    alpha and its alpha hash draws wrongly, so the dither is the material's
    own `DISTANCE_FADE_PIXEL_DITHER` with its range set every frame so the
    fade at her distance is the wanted share, `ShopView.dither_range`;
    the dither would also apply in the shadow pass, measured from the
    light, so she casts no shadow while fading and her own once solid),
    so even at the widest zoom she never pops in or out;
    the door's path and the alley are the street pavement cut to one stone
    per cell with a joint, a sliver thick (flush, no side face), its stones
    varying in shade; the alley is solid across the lot and
    `PATH_SOLID_CELLS` past it, then fades into the ground over
    `PATH_FADE_CELLS` (to its end, where she fades in and out); a side
    wall's alley is solid to the shop's front and fades out over
    `PATH_STREET_FADE_CELLS` (3) towards the street instead of stopping
    square. Crates that land on one cell in the same tick (the rest of a
    delivery once she steps away, or the whole delivery on the cell beside a
    full stack) appear one at a time, bottom first, `CRATE_STAGGER_TICKS`
    (2, her bend) apart (view only, and only at play speed, not across a
    fast-forward; the sim has them all down at once: with the stack inside
    the door full she cannot reach the overflow cell from the doorway, and
    walking her there would change the sim). The open
    leaf hinges on the side away from where she comes along the alley when
    both sides are open ground.
  - Tests: `tests/sim/test_delivery_dock.gd` (back-door and street routes,
    stock on carry, closing and morning safety nets, job priority, guests
    never in the back door with deliveries coming and going, no change
    without orders, one back door), `tests/world/test_delivery_view.gd`,
    `tests/world/test_delivery_session.gd`. Captures (by hand):
    `tools/delivery_shots.gd -- <out> [north|east] [up|cutaway]`.
- Tests: `tests/sim/test_storage_space.gd`, `tests/sim/test_delivery_book.gd`,
  `tests/sim/test_delivery_dock.gd`,
  `tests/world/test_delivery_session.gd`, `tests/ui/test_stock_panel.gd`,
  `tests/world/test_stock_session.gd`.

### Thin interior dividers (FK-113)

The starter kitchen's former wall row is now Kitchen floor, with thin wall
segments on its southern boundary and the original pass gap unchanged. Outer
shell cells stay thick. Every authored layout was checked (the Tier 1 layout is
currently the only one). `ShopLayout.legacy_rows` retains the authored terrain
that snapshots 1–7 did not save.

Shop snapshots use version 8 (version 7 is reserved for furniture looks, #220).
`ThinDividers.prepare` reconstructs legacy terrain before ordinary item, room,
wall and finish validation. The pure migration uses the same interior-wall
classification as `ShopFootprint`; nearest bordering floor determines each new
cell's room, with Kitchen winning equal-distance ties, then Restroom, Storage
and Dining, with stable cell order. Only different-room boundaries gain a wall.
Existing window and doorway frames retain enough thick support to remain valid.

Version 8 records `thin_cells` and `thick_cells`, strictly validated against the
original interior cells (no duplicates, overlap or shell/street changes). These
exceptions are normalized into the loaded layout's rows before footprint
construction, so later Expand edits and reloads keep them. Migration runs only
for older versions. Finishes and complete wall-decor spans move to a new thin
face in the same room; unchanged faces take priority and nothing is overwritten.
A missing or invalid destination refunds half the original price, rounded down.
The decoder only stages `load_refund` and plain `load_notes`; Main applies a
refund after complete successful load, before the existing morning checkpoint.
There is no new save point or SaveSystem migration.

### Day and night (FK-109, #208)
- **A pure function of the clock.** `DayLight.minute_for(clock, tick_fraction)` maps the phase to a time of day: prep one hour before opening (never before 06:00), service scaled across the opening hours, last orders running into the evening, and closed late at night. `DayLight.sample(minute)` blends the key frames in `data/look/day_light.tres` (`DayLightTuning`). Nothing is stored or drawn at random, so paused captures are deterministic.
- **Applied each frame** by Main's `_refresh_day_light()` through `DayNightView`:
  - the key light's colour, energy and downward angle (its compass direction is fixed, so light stays upper-left);
  - fill energy, ambient light and the procedural sky;
  - a glow multiplier on hung lit items (neon, string lights, window pools; capped at energy 1);
  - one warm `ShopLights` omni over the floor's middle at dusk and night, so the room glows while the street stays dark.
- **The 10:00 key frame is the authored `lighting_rig.tscn`.** Default morning prep looks exactly as before; the weather and lighting tests pin this.
- **Weather** only tints the pavement and is unaffected. **The title backdrop** keeps the authored morning, because Main is disabled there.
- **Review:** `tools/day_night_review.tscn` with `DAY_NIGHT_STAGE` set to morning, noon, golden, dusk, last_orders or closed (or minute with `DAY_NIGHT_MINUTE`).
- **Chairs up after close** (`ShopView.set_chairs_up`, view only):
  - When closed, each dining chair turns upside down onto its table, side to side so the back hangs over the edge.
  - Both a table's built-in chairs (model children tagged `seat_cell`) and separate chair items linked to its seats are handled. Only the model moves inside its wrapper; the item, cells and saves never change.
  - Tables left dirty at close keep their chairs down. Evening Build and Paint show them down, so picking is unchanged.
  - Morning restores the exact resting transforms.
- **Lamps (#84).**
  - **The items:** six Kenney Furniture Kit lamps in Buy > Lighting (`catalogue_room = &"lighting"`):
    - floor lamps (solid, one cell);
    - side tables with a lamp (`sideTable` with the lamp stacked through PropView `support`);
    - a wall lamp (WALL layer, inside face);
    - a ceiling pendant (FLOOR_DECOR layer, non-blocking, `ItemDef.ceiling`). The pendant's shade shows only with Walls Up; its light keeps shining.
  - **Light:** each lamp has one warm `glow_color` omni (about 2700K), short range and no shadow, with its own meshes left out like the neon sign. Floor, table and pendant lights are added in `ShopView._add_lamp_light`; the wall lamp uses the hung-item `_add_glow`.
  - **Day and night:** `DayNightView.apply_lamps` sets each lamp's light from 35% by day to full once the shop's own lights are on (`DayLight.Look.interior_energy`). Lamps are marked `DayNightView.LAMP_META`, so sign glow doesn't double-scale them.
  - **Light cap:** at most `LAMP_LIGHT_CAP` (8) lamp lights shine, the ones nearest the camera focus (ties broken by instance id). The rest keep their shade, but their light is hidden. This keeps every mesh within the Compatibility renderer's eight lights.
  - **Vibe:** the six ids are in `vibe.tres` `lamp_item_ids`.
  - **Review:** `tools/lamps_review.tscn` (`LAMPS_STAGE`, `LAMPS_WALLS`).

### Sound (FK-067, #117)
- **`Sfx` autoload** (`src/audio/sfx.gd`): one-shot cues and looped ambience on the Effects bus (Settings already sets its volume). It clicks every `BaseButton` in the tree, including the title screen's, through `SceneTree.node_added`, and plays hover on enabled buttons. Each cue has a minimum interval (`SoundThrottle`) so fast-forward bursts play once. Repeats step through a fixed pitch cycle; there are no random draws.
- **Headless and web:** headless runs create no players, but `play` still emits `cue_played`, which tests listen to. On the web nothing plays or queues until the first click, key or touch.
- **`SoundDirector`** (`src/world/sound_director.gd`, owned by Main): listens to `RestaurantSim.customer_arrived` (door bell), `customer_paid` (coins) and `review_recorded` (five stars: chime). Each frame, `refresh()` sets the room tone from the number of guests and plays the stove, fryer and coffee loops while `FoodPresentation.busy_loops` reports a worked station. It is silent outside service and while paused.
- **View hooks:** ShopView plays the back-door creak when a leaf starts to open and a thud when a crate lands at play speed. Main plays the level-up or milestone sting as the evening report opens.
- **Tuning:** streams, gains, intervals and loop levels are in `data/audio/sound_tuning.tres` (`SoundTuning`). Kenney files are in `assets/kenney/audio/`; the made loops are in `assets/made/audio/`.
- **Dining-room ambience** (#366): the room tone, the chatter layers and the table clinks play on the **Ambience** bus (`default_bus_layout.tres`; Settings' Ambience slider, saved as the optional `ambience_volume` key, so older settings files load at 100%). Every level is in `data/audio/ambience.tres` (`AmbienceTuning`): loops and their gains (`room_tone`, `chatter_light/busy/packed`), `room_tone_full_guests`, the crowd size each chatter layer peaks at, the chatter fade and jukebox duck, and one `ClinkSet` per clink kind (at least 4 variants, gain, minimum interval). `SoundDirector` plays `plate` or `glass` on `OrderBook.order_delivered` (the recipe's `is_drink()`), `dish_stack` on a completed `bus_table` task, `sink` when `Kitchen.plates_changed` shows a plate washed (dirty down, clean up) and `cutlery` from a random eating guest at `AmbienceMix.cutlery_rate` (per eater, capped), with exponential gaps. Clinks fire only while open, running (speed above 0) and not `display_only`. `Sfx.play_clink` picks the variant and a pitch within `pitch_spread` (5%) from its own seeded generator (`CLINK_SEED`), never the sim's, throttles each kind, reports `clink_played` headless and plays through `AudioStreamPlayer3D`s at the table with attenuation off, so the camera's listener pans them. Chatter: `AmbienceMix.chatter_levels(crowd, anchors)` crossfades the layers that have a file at equal power by the guests not leaving, fades at `chatter_fade_seconds`, and ducks under a playing jukebox. The chatter loops (`assets/commons/audio/chatter_*.ogg`, 30 s, made from a public-domain recording; see `SOURCE.txt`) sit at -24 dB so the murmur is barely audible (Jared: a few percent of full volume). A null loop keeps its level and plays nothing, and a layer with no file drops out of the crossfade (its neighbours cover it). Adding the files is a `.tres` edit.
- **Music** (`Sfx`, `src/audio/music_tracks.gd`): one player per track (looping, except a playlist track, which plays once via `Sfx.music_stream_for` so it can end and hand over) on the **Music** bus (Settings' Music slider; the bus sits 6 dB under the slider via `SettingsPreferences.MUSIC_TRIM_DB`). `MusicTracks.BY_CONTEXT` is the table from context to its tracks in play order: `title` is Stir It Slow, `service_day` is Buoyant Swing Groove then Kitchen Jamboree, `service_evening` Smoky Vamp (`assets/music/*.ogg`, Ogg q5, leading/trailing silence trimmed so loops have no gap); morning and closed with no report open have none. A one-track context loops; a context with several (day service) plays each once and `Sfx` advances to the next when one finishes (`advance_music`, wrapping round, no RNG; entering a context always starts at its first track), crossfading like a context change. `Sounds.set_music_context(ctx)` says where the game is, and tracks fade (`Sfx.MUSIC_FADE_SECONDS`, 2 s), so a change of context is a crossfade. The title screen sets `title` and clears it on leaving; `SoundDirector.refresh(light, report_open)` sets the service context from the phase and the shop light (the evening report has no song: while it is open, Main passes `_report.visible` every frame and `service_context` counts the shop as still serving, so the day or evening service track carries on under it) (dusk is `MusicTracks.EVENING_LIGHT` of `DayLight.Look.interior_energy`), so opening after dusk goes straight to Smoky Vamp. `SoundDirector` ducks the music (`Sounds.set_music_ducked`) for as long as the shop is open with a counted jukebox, paused or not. A display-only Main (the title backdrop) sets `SoundDirector.display_only` and never touches the music. Silence rules match the cues: no players in headless or `--script` runs (fade levels are still tracked for tests), nothing before the first click on the web. A new track is a table line plus a `set_music_context` call.

### Supplier haggle (FK-136, #327)

The optional morning Stock game inherits the small `Minigame` Control boundary:
`start()`, one `finished(result)` signal, and Skip as -1. `HaggleTuning` in
`data/balance/haggle.tres` supplies rounds, normalized zone widths/speeds and
the maximum discount. Main creates `GameState.rng(&"haggle")` only after the
first accepted start; `HaggleRules.zone_centers` draws all centers once. Marker
animation uses display delta only. Scores are normalized distance from each
zone's center, averaged over three stops, then rounded to whole percentages
within the authored cap (a fractional cap permits only whole percentages below
it, so 10.5% permits at most 10%). Space and mouse share one stop handler, with release
and echo guards; Skip/Escape finish once.

The start spends that morning's attempt even when skipped or closed. Failed
payment/storage checks retain an earned offer. Only the next successful manual
MORNING order spends it; opening expires an unused offer. Repeated setup of the
same morning preserves the attempt. Explicit new-run/load initialization resets
it, including a reload within an existing Main. No haggle state or report note
is serialized, and no save point or SaveSystem code changes. Generic named RNG
states retain their existing next-morning persistence.

`HaggleRules.charge` rounds the discounted order up to a whole dollar using
`total - floor(total * percent / 100)`, with overflow-safe quotient/remainder
arithmetic. Each actual line cost is the difference of charged cumulative list
totals in fixed cart order: nonnegative, no more than its list price, zero for
zero-priced lines, and summing exactly to the displayed charge. The narrow
morning-only `Economy.buy_haggled_order` validates the whole purchase before
recording those actual negative ingredient ledger lines and receiving exactly
those valued lots. It never represents a saving as a refund or positive income.
Ordinary `pay_order`, `PurchaseBasis.allocate`, automatic premiums and pending
delivery/refund behavior are unchanged. FIFO use, expiry and existing stock JSON
carry the actual paid values. The live evening report notes the applied saving
beside stock bought, separately from cost of food served and cash change.

The full-window game blocks underlying GUI; Main and HUD guard action/Open/speed
requests. Camera processing is suspended because WASD/edge pan polls input.
Normal morning completion restores camera processing, prior speed and valid
prior focus. The clock already advances only during service. No general modal
framework, art, fonts, colors or sounds are introduced.

Coverage: `tests/sim/test_haggle.gd`, `tests/ui/test_haggle_game.gd` and
`tests/world/test_haggle_session.gd`, plus existing panel/report regressions.
The unchanged default five-day probe (seeds1,7,42) remains the balance gate.
`tools/haggle_review.tscn` is an explicitly unsaved seed327 fixture: it throws
out starter stock, stages real Space-stop timing and shows the active game at
frame30 and actual 6%-off ($20 list, $19 charged) panel at frame90. These two
existing-job captures are UI evidence, not natural human timing or balance play.

### Creative mode (FK-141, D34, #333)

New game asks Career or Creative (`TitleScreen.show_mode_choice()`; the card is
built in code). `Main.start_fresh_run(..., creative)` records the request in
`GameMode`, and `_new_game()` applies it once with `GameMode.begin_new_game()`.
The in-game Start over keeps the current mode. TODOs there name the later work:
any lot and neighbourhood (#405) and saving a design as a blueprint for career
(#432).

- **One flag.** `GameMode` (`src/sim/progression/game_mode.gd`) is a static
  run-wide `creative` bool, so the sim can read it without a Node. It is the
  `game_mode` save section (`{"creative": bool}`), registered after the
  autoloads and before `owner`, because the owner and menu restores read the
  unlock level. `Main.start()` resets it to career before `initialize()` (it
  is static, so a Creative run must not leak into the next run in the same
  process), and `_wire_session()` pushes the effective level and tier in both
  modes. A save without the section is a career game; a Creative save that
  fails to load starts a new Creative game (with a warning). No
  `save_system.gd` change.
- **Unlocks.** Every unlock check reads `OwnerProgress.effective_level()` and
  `effective_tier()`: the earned values in career, `GameMode.CREATIVE_LEVEL`
  (99, above every authored `unlock_level`) and the top tier in Creative.
  Items, recipes, floors, walls, menu size, the lease upgrade, the cat,
  bookings, customer types, the inspector, critic and rush hour all use them.
  The earned `level`, XP and `career_tier` are not touched and still save.
- **Money.** `Economy.is_free()` gates every money path in one place:
  `add_cash`/`add_cash_for_site` and the ingredient purchases record nothing,
  every affordability check passes, `settle_loan_day` returns `{}` (no loan,
  interest or repayment), and `spendable()` (a huge budget) replaces `cash`
  where planning or refusal text reads it. Stock still arrives and is counted.
  Cash therefore never changes from the starting value.
- **Hidden.** At close a Creative game skips owner XP, milestones, the weekly
  goal and the tier climb. The HUD shows a "Creative" chip in place of cash, the
  loan chip and the owner level; the evening report hides profit, finances,
  cash change, loan, milestones, weekly goal, owner progress and the business
  trend (guests, dishes, reviews, events, team and stock stay). Goals is titled
  "Collections" and shows collections and records without the money ones
  (`ShopRecordsText` `with_money = false`, by record id). Prices read "Free" through
  `Fmt.price()`, `Fmt.price_each()` and `Fmt.for_price_each()`, which equal
  the old career text exactly. The title's Continue reads the autosave's
  `game_mode` section and adds "(Creative)".
- Career is unchanged: the default five-day probe (seeds 1, 7, 42) is identical
  to `main`. Coverage: `tests/sim/test_game_mode.gd`,
  `tests/world/test_creative_session.gd`, `tests/ui/test_creative_title.gd`.

### 2.4 Save system
Lifetime records (FK-145): `ShopRecords` is a pure consumer of the one finalized
`DayReport` in Main's guarded `service_closed` handler. Report previews, returning
from Goals and evening purchases never add another close. Meals plus tips are
revenue; loans, bonuses and refunds are not. Operating-profit bests require the
report's recorded paid-food basis; a first recorded loss is valid, while unknown
profit does not become zero. Reputation is the closing rolling average. Equal
bests retain their original day. Per-dish totals survive missing recipe content;
the UI uses its current display name, or "Former dish", with stable id tie order.

The no-angry-guest streak counts the existing public service-failure departure
reasons, not all unpaid guests or sampled review stars. Closing and administrative
removal do not break it; a paid guest's low review is not an angry departure in
the current lifecycle. Consecutive closed days with no such failures extend it,
including an empty service; a missing day restarts the run. The versioned optional
`shop_records` section stages and validates before whole-load installation, with
empty records for older saves. Counts stay within exact JSON integers; currency
uses decimal strings. It joins only the existing morning autosave. New-record
notices are detached close-local text, retained across report refreshes and cleared
at the next morning. Records award nothing and draw no RNG.

Business trends (FK-123, FK-132): Main keeps thirty detached `BusinessHistory` closing
summaries outside `DayReport` serialization. Reopening the evening report and
advancing to the next morning upsert the current day after evening purchases;
`build_report()` stays a read-only query. The optional `business_history` section
uses decimal strings for signed currency and joins only the existing morning
autosave. Load stages it until the whole morning validates; older saves start
empty. Version 1 saves retain the same row format. The evening report defaults to
seven days, with a 7 / 30 day toggle remembered by the report for the session only;
it never enters a save. Thirty-day charts label every fifth day and shorter
histories show only the rows that exist. Both ranges use the current theme, with separate
dish-profit and guest scales, today's label, unknown-profit gaps and comparisons
between equal recorded-day windows. "Last week" requires two complete weeks.

- JSON in `user://saves/`, with a `version` field and migration functions per version.
- Only sim state is saved, never nodes. The world is rebuilt from sim state on load.
- `SaveSystem.register(key, capture, restore)` replaces a unique section provider; capture returns a dictionary and restore returns success.
- `save_game(slot)` / `load_game(slot)` return errors. Writes use `.tmp`, move the previous final to `.bak`, then publish to an absent final; loads prefer a valid final or recover a valid backup. This is a recoverable transaction, not a filesystem-atomic Windows overwrite or power-loss durability guarantee (Godot 4.7.2's Windows rename removes an existing destination before moving).
- Missing sections are skipped; `MIGRATIONS` maps each old version to one upgrade step. Clock and GameState register state in `_ready`.
- Autosaves remain morning-only. If startup cannot load an existing slot, it
  starts fresh and skips only the next autosave; later morning saves resume.
- RNG seed/state and the master seed use decimal strings to preserve 64-bit integers through JSON parsing.

### First-day guide (FK-060)

`Hints` owns ordered, once-only presentation progress for the first two mornings.
Menu must actually open and close before the Stock hint; later hints observe the
first queued guest, dirty table and visible evening report. Hidden targets and
missed day-one steps are consumed rather than blocking play. `HintsBubble` uses
the shared theme and anchors to HUD controls or the bottom-right corner. Its root,
card and labels ignore mouse input; only its two unfocused buttons receive it.
No hint changes the clock, speed, world or random streams.

Main registers the `hints` save section. Missing sections start complete on an
older save; a new game starts fresh. Settings' “Show guide again” resets in-memory
progress for this morning (or the next morning during service), with persistence
at the next existing morning autosave only. Title Settings hides that run-specific
action. `use_saves = false` and title backdrops suppress guide presentation unless
a review tool explicitly sets `guide_for_tools`. `tools/hints_review.tscn` opts in
for the single first-morning capture in the existing visual-review job.

### Opening week (#494)

`OpeningWeek` (`src/sim/progression/opening_week.gd`) is the pure chain state;
`OpeningWeekSet` / `OpeningGoal` are the authored data in
`data/balance/opening_week.tres`. Main reports observations through one
`_observe_opening(condition, value)` and pays each newly met goal at once with
`Ledger.OPENING_WEEK_BONUS` (non-operating; subtracted from the close's profit
basis like booking advances). Hooks: `menu_set_price` (a real change),
`_on_customer_paid` and owner assignment (drinks on the menu, served today,
owner on the floor, only while open or in last orders), and opening: Grow
together (TABLE-category items and hired servers both above the counts
`_begin_morning` noted, same day and site), decor (DECOR items plus hung wall
decor above the count at the last opening, same site) and drinks. Checking
these at opening means a buy undone or sold before opening pays nothing. The career business-day close checks today's guests served and five-star reviews,
then adds the waiting XP via `OwnerProgress.award_bonus`, shown as `opening_week_xp`
in the report. The `opening_week` save section (version 1: status, completed
ids, pending XP) joins only the morning autosave; a missing section means a
save from before the chain, which joins only on day 7 or earlier.
`_begin_morning` ends a finished or overdue chain before the autosave. Tests of
other features that check exact books call `TestCase.retire_opening_week`.

### 2.5 Testing
Dish quality explanations (FK-063): `DishQuality.breakdown()` snapshots the recipe
base, role skill factor, cooking trait and distinct preparation station bonuses,
then the unchanged 0–1 clamp. Both food and pour tasks store that typed result on
`Order.quality_breakdown` and copy its quality to `Order.quality`. Drinks retain
their existing server-skill calculation without a cooking trait bonus. The skill
weights (`0.7`, `0.1`) are authored in `data/balance/menu.tres` (`MenuTuning`).
The menu shows a read-only best-case estimate from today's eligible workers and
reachable stations beside its existing measured sample. Guest inspection shows
the captured result for each delivered order, including sides. The evening report
averages all delivered orders (food and drinks); count and average round-trip with
historical reports. There are no new save points or random draws.

- **In-repo runner, not GUT** (decision D9). `tools/run_tests.gd` finds `tests/**/test_*.gd`, runs every `test_*` method, and exits non-zero on failure. Tests extend `tests/test_case.gd`, which provides `assert_eq`, `assert_true`, `assert_false`, `assert_almost_eq` and `assert_null`. No downloads and nothing to version-match. The sim is pure logic, so it doesn't need mocks.
- A test also fails if it raises an engine or script error (a null call, `push_error`), even when its asserts pass. So code paths exercised by tests report problems through return values, not `push_error`.
- `tools/check.sh` runs a headless import, a bounded fresh `--check-only` compile of the screenshot entry before autoloads exist (including error-log inspection, because Godot may exit zero for dependency compile errors), then loads every script and resource (`tools/parse_all.gd`, which also catches scenes pointing at missing files), then the tests in two parallel shards (`run_tests.gd --shard=K/N`, every Nth sorted file), each with its own `user://` through `XDG_DATA_HOME`; `TEST_SHARDS=1` runs one process. Untyped declarations are errors (`untyped_declaration=2`). Every diff must pass it.
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

### Named regulars (FK-088)

`RegularCast` and `RegularProfile` (`src/sim/regulars/`) hold a small persistent
cast, authored by `data/regulars/cast.tres`. Solo arrivals of the existing Regular
type belong to sixteen anonymous, deterministic repeat cohorts (their daily
arrival order, cycling without a random draw). Satisfied visits on distinct days
teach the most-enjoyed dish and most-used seat; ties keep the first favourite.
Promotion requires two satisfied visits, at least 2.5 stars, positive vibe (1),
and **day 6 or later**. The five-day balance probe therefore has no promotions,
new regular-stream draws, tips, or changed guest choices. The cast keeps at most
eight lifetime identities, including those who stop coming; departed names are
retained in the saved history and never silently reassigned.

Only an actual promotion asks the session's lazy `GameState.rng(&"regulars")`
provider for a stream. Names, clothing colours, greetings and the next visit date are
seeded; each identity gets a fixed approved Mini Character model. Returning
regulars replace ordinary solo Regular arrivals when due, at most once per day,
rescheduling 2–4 days later. A shortage of eligible arrivals delays a visit rather
than spawning extra guests. Arrival and private guest draws retain their ordinary
order. Parties and other customer types remain anonymous.

A regular tries their favourite seat first, then any usable seat, and orders the
favourite when it is available in their visit's menu section. A missing or sold-out
favourite never prevents another order. The final visit kind is applied once after
choosing the usual, so a food favourite keeps the normal meal duration even when
replacing a coffee or drinks arrival. Having it on the menu adds the authored
0.08 happiness term to their arrival review bonus. Their existing wait and meal
quality determine relationship mood at departure; repeated missing favourites
lower it too. Below 0.2 they stop visiting, and the evening report names them.
`regular_tip` adds a whole-unit `Ledger.TIP` alongside the existing guarded sale:
4% normally, 8% with the favourite on the menu, rounding the latter up so a $5
coffee can produce a $1 bonus. No extra random draw or alternate currency is used.

`Main` stages the `regulars` save section and installs it only after a complete
morning load. Anonymous learning, fixed identities, preferences, moods and due
dates round-trip; absent legacy sections start empty. Only the existing morning
autosave writes them. New promotions and menu edits never save immediately.
The Menu marks active favourites; inspection uses `RegularText` for dish names,
seat coordinates and plain mood words. ShopView attaches a reused star/name/
greeting billboard to the drawn person, and PersonView uses their fixed model
plus a private copy of its clothing colormap tinted in an approved swatch.
The torso UV ramp is measured per model; skin ramps and the separate head mesh
keep their original materials. Greeting lifetime is two sim
seconds, so pausing also pauses it. None of these presenters advances the sim.

Validation: pure cast tests cover gates, learning, cap, calendar and RNG/save
continuation; integration/session tests cover actual arrival, seating, orders,
departure, tips and morning-only persistence. `tools/regulars_probe.gd` is a manual
25-day paired café probe (equipment-free existing concept fixture; stock and
running costs paid, morning raises accepted). `tools/regulars_review.tscn` is an
explicit staged view fixture for two native captures, not balance evidence.

### Tier 2 lease (FK-064)
`data/balance/lease_upgrade.tres` defines the level-3 morning offer, deposit,
rent and extra lot margins. The Director accepted these **provisional** numbers
on 2026-10-29: $300 deposit, $60 daily rent, four extra cells east and north
(none west); a later balance pass can tune them in the data without code changes.
The deposit uses `Ledger.UPGRADES` / `lease_deposit`; closing rent uses
`Ledger.RENT`. Existing loans block upgrading. The Menu morning panel shows
the cost, amber `RestockBudgetWarning`, and a plain cash/loan refusal.

`OwnerProgress.property_tier` joins the existing owner progress snapshot;
missing legacy fields mean Tier 1. Owner restores before shop, so the shop's
floor decoder validates bought cells against the tier's larger template lot.
No new section or save point. No floor, furniture, movement, RNG draw, or
change to the default Tier 1 play. The current live editor's footprint, Build
preview, delivery dock and rendered alley all use the enlarged lot. Recipe,
floor and wall-finish tier gates now read the saved property tier.

Regression coverage: `tests/sim/test_lease_upgrade.gd` and
`tests/world/test_lease_session.gd` exercise eligibility, refusals, exact books,
new floor, alley edge, legacy decoding and both sides of the morning checkpoint.
For native review, `tools/lease_review.gd -- offer|short|expand` opens a seeded,
interactive fixture with explicit synthetic XP/cash and saves disabled.
`--capture-set=<fresh output directory>` captures the offer, cash refusal and
accepted lease in Expand in one bounded manual process, then exits. Attach all
three PNGs to the PR and keep their state metadata outside Git; this capture set
is not part of CI.


### Curb appeal (FK-118)

`CurbAppealInputs` reads supported street-front finish faces and actual hung
anchors. Plain paint and the view-only name board stay neutral. Authored item
families, weights, caps, repeat decay and maximum bonus live in
`data/balance/curb_appeal.tres`; widths and swatches share each family's repeat
allowance. The pure model clamps the score to 0–100 and returns
`1 + score / 100 * max_bonus`, exactly 1 for a bare front and at most 1.10.
Main derives this before refreshing the existing live/forecast demand hook;
there is no second arrival multiplier, RNG fetch/draw or countdown reset.
Edits, undo, support changes and load refresh the derived facts. No score is
saved: the existing morning shop save already contains its inputs.

**A-frame sign (#292).** `a_frame_sign` is an exterior WALL-layer item in a sixth
mount band, `ExteriorSupport.Band.GROUND` (face keys now run to direction 23), so
it reuses the hang request, ghost, undo, sale, morning save row and curb-appeal
path with no new store. It is one cell wide and `unique_per_shop`. Placement rule
(`ExteriorSupport.ground_problem`): the face's outside cell must be the street
pavement **beside** the street door, i.e. the wall shell cell next to a door cell.
The cells straight in front of the door are the guests' entries (where guests
appear and leave), so they are always refused ("Keep the doorway clear"); the sign
therefore never sits on the walking route. It is view-only like every hung item:
it adds nothing to `SimGrid`, so paths, `MovementCoordinator` occupancy and
arrivals are untouched. Its curb-appeal family `a_frame` (weight 6, cap 6) is in
`data/balance/curb_appeal.tres`. The wrapper (`assets/props/a_frame_sign.tscn`) is
two Kenney `paneling` boards leaning to an A, with the diner chalkboard wrapper
(#147) mounted on the front board; no new made model. `StreetSignText` gives its
two lines (the normalized restaurant name, then "Today: " plus the enabled dish
with the best margin, price minus ingredient cost, ties to the lower id, or
Coffee when `MenuThemeText.leading_theme` is the cafe), and `WallFinishView`
refreshes them on a rename, a price change or a menu change. The sign stays
visible when walls are cut away. `tools/a_frame_review.tscn` is the capture.

Build shows the themed meter beside Vibe when the rendered camera faces the
street, including during smooth rotation and Paint. The existing “Tomorrow's
crowd” curb factor supplies its plain bonus line without a new report field.
The named `curb_appeal` manual setup uses disclosed free construction (nominal
catalogue/finish cost $256, fixture charge $0), retains ordinary service and
stock costs, and measures appeal rather than purchase return on investment.
Its default counterpart and the default setup itself remain unchanged.

### Patio (FK-117)

`PatioArea` derives a separate pavement strip from the layout's `patio_depth`
and `patio_cell_price`, beside the existing street door. The starter strip is
four cells deep (56 purchasable cells in the roomier shop, 48 in the original)
at $15 each; the two public door
approach columns stay outside ownership. Bought cells become FLOOR with the
appended `SimGrid.Room.PATIO` kind. They never move the building shell or add
an entry, and an empty purchase never grows the grid. Build's Patio tool marks
the available cells; drag buys and Shift-drag removes empty patio while closed.
Owned gaps beside the doorway reuse clipped native paving without shifting the
street, tinted toward clay (`NeighbourhoodDressing.patio_color`) and framed by
a thin darker edge so the bought patio reads apart from the public pavement. Furniture, people, dirt and build overlays follow its measured surface;
mixed indoor/outdoor previews retain each cell's height and relative seat lift.
`ShopEditor.check_patio` retains the existing connectivity, people, dining,
room and path checks. Removal refunds $7 per cell (half, rounded down), plus
half the laid floor type's price. `ShopEditHistory` restores ownership, floor
looks and exact ledger amounts; purchases and refunds use `Ledger.UPGRADES`.

`ItemDef.outdoor_only` defaults false. Outdoor furniture requires patio under
its whole footprint and authored work/seat cells; indoor furniture cannot use
those cells. `patio_table_2`, `patio_chair` and `patio_waiting_bench` cost
$40/$10/$35 at level 1 and reuse the approved table, lowered-backrest chair and
bench wrappers. Their shared `patio_dark_metal` look maps the existing wood
surface to the kit's `metalDark` donor without changing source models.

`PatioRules` reads the already selected daily weather: Sunny and Cloudy allow
outdoor dining and waiting; Rain skips those seats. The morning weather line
reports the patio's status only when cells are owned. Dining capacity, party
seating and waiting benches use the same eligibility; waiting still uses its
existing arrival bonus and reservations. Service and bussing follow ordinary
grid paths through the street door. Weather closes seating without changing
walkability, creating a stream or drawing randomness.

Waiting benches are not solid, but movement never lets anyone use a seat as
an aisle. So a bench placement or move is refused when it newly cuts off a
door, table seat or station under that rule (`WallRules.seat_cut_off_problem`),
for example a bench across the one-cell patio walkway in front of the tables.

Seats are stops, never aisles, in the editor's placement checks too (#315).
`WallRules.reachable(grid, true)` floods from the street the way movement
lets people walk: a seat cell (any item's `seat_cells`: built-in table seats,
chairs, stools, booths, benches) is reached but never walked on from, and a
diagonal step may not brush a seat at either corner (the coordinator claims
both corner cells). Every furniture buy, move and blueprint stamp
(`ShopEditor._note_seat_cut_off`, through `seat_cut_off_problem`) compares
that flood before and after the edit, and when the edit newly cuts off a
table seat, station, sink, restroom fixture or the door for real people the
placed item gets a seat warning ("Nobody walks through seats: this blocks the
way to a table"), shown with its highlight. It is a placement-time warning:
it shows while the item is placed or moved, joins any warning the item
already has ("Only 3 of 4 seats usable"), and after the commit
`check_current` keeps it on that item only while the grid version is
unchanged (`ShopEditor._seat_cut_note`), so the next layout change of any
kind ends it. A blueprint stamp puts it on the first entry whose placement
completes the cut (`_stamp_culprit`, run only when the stamp cuts something
off). That stays a warning, the
furniture rule (DESIGN 4.3); only waiting benches keep #269's refusal. As in
#269 only what an edit newly cuts off counts, so no existing layout gains a
warning. Since #320 the standing checks walk the same way: the `unreachable`
highlights (`ShopEditor._unreachable`, which probes and the soak treat as a
hard condition), the furniture pass of wall and floor cut-off refusals
(`WallRules.cut_off_problem`), `RoomRules.guest_reachable` (and with it
`restroom_toilets`, which feeds the sim) and the live menu (`MenuAccess`).
Furniture still only warns: the room rules' refusals (`RoomRules.violations`)
and the editor's empty-menu refusal walk across seats (`seats_stop` false), so
a move that leaves the pass, a station or a seat reachable only through seats
gets the seat warning (the pass has its own, `WallRules.CUT_PASS`) and the
highlight, never "The pass needs the kitchen on one side…".

Older shops whose staff can't reach the kitchen that way (#320): the
preserved original template's middle row is all tables and seats, so its
servers had no way to the pass. `AisleRepair.repair` runs once on load, for a
shop snapshot older than version 10 (`ShopEditor.from_dict`) and for a save
that predates the shop section (Main's staging of the original template). It
compares what is cut off walking as people do with what is cut off walking
across seats (items as `_unreachable` names them, street-door cells, toilets)
and, when people miss anything, moves only tables and chairs until they miss
nothing. The search is greedy: each round takes the move that fixes the most,
the shortest on ties (cells moved, plus one for a turn; within `RADIUS` of
where the item stood, fixed tie order, no RNG). It tries only tables and
chairs touching the cut-off cells (tables first), scores a pose with one
flood, and runs the editor's full checks only on a pose that beats the best so
far. A move must be one the editor accepts (fits, same room kind, chairs face
a table, no new room problem, no seat in the doorway, no dining seat lost, the
largest joined table group no smaller, no staff start covered). Load time is
capped: past `MAX_TRIES` poses or `MAX_CHECKS` full checks it gives up and
changes nothing (a repair that fails runs again on each load until the next
morning autosave writes version 10). Each item keeps its variant, colour and placement
order; when no repair is found nothing moves. On the original layout it
turns the west table a quarter where it stands, which opens a lane beside the
pass; the template (`tier1_original.tres`) now holds that arrangement, so a
save from before the shop section gets it too. The issue's first choice, the
current starter's row of turned tables, does not fit this shallower room (its
cells cover the server's start post), and turning all three in place served
fewer guests than the blocked row in the balance probe (84.7 against 93.7 over
five days, seeds 1, 7, 42), while the one-table turn served 100.3 (the deeper
starter 100.7, the roomier 96.3).
`ShopLayout.aisle_moved` drives the HUD's one-morning note ("We moved a few
tables so your staff can reach the kitchen.", `HUD.set_aisle_note`, gone at
opening). It is never saved: the next morning autosave writes version 10,
which is never repaired again.
A seat item (chair, stool, booth, bench) is refused outright
(`ShopEditor.SEAT_IN_DOORWAY`) when one of its seats would stand on a street
door threshold, a door, an entry or just inside a back door, or would fill
the last clear cell straight in from the street door (the door lane,
`MovementCoordinator.lane_cells`, #308), in buys, moves and blueprint stamps.
One seat beside the way in of a two-cell door is allowed (the joined-table
probe fixture on the original layout has one); a table's built-in seats are
left to the path warning. Joined tables and back-to-back booth rows still
pass: each seat is the end of its own walk. A seat reachable only through
another seat (two booths side by side between tables) is warned about,
because real routing cannot reach it either. Dining capacity and sim routing
are unchanged.

Two balance rules keep a patio from overfilling a busy starter shop (#269).
Without them the default shop's one cook and one server were already near
capacity, so extra outdoor covers only lengthened every food wait until guests
indoors and out timed out (served fell about 14%, like adding two indoor
tables). First, `RestaurantSim.patio_keeping_up()` lets an open patio seat take
a new guest only while no ticket waits for the stove and no plate waits at the
pass (`PatioRules.can_seat`); indoor seating never asks. Second, a guest seated
outside is `VisitTuning.patio_patience_multiplier` (1.5) times as patient for
their order and food, applied once in `CustomerAgent.sit_down`. Because staff
and cooks rank guests by the share of patience used (#310), indoor guests are
served first under pressure. Neither rule reads randomness, so a shop without
patio cells is unchanged tick for tick.

The shop snapshot is version 9 with sorted `patio: [[x, y], ...]` rows.
Restore installs owned Patio floor before validating furniture and requires
saved Patio rooms to match that ownership; versions 1–8 have no patio. There
is no new save section or save point: the existing morning
autosave persists cells and outdoor furniture. Curb appeal counts supported
outdoor tables and waiting benches once each, with a shared `patio` family
weight 8, cap 9 and existing repeat decay 0.65 (the 9 came from the three
wide street families, 3 each, so the caps still sum to 100). Chairs add no
separate points.
Rain leaves these visible furniture contributions in place, and the total
curb bonus retains its existing +10% maximum.

The manual `--setup patio` probe keeps the default shop and adds two outdoor
tables beside the door (`ProbeSetups.patio_table_origins`), with every patio
cell, built for free through the real editor; stock and service costs remain
paid, with no cash, XP or stock grants. Daily weather is selected normally.
This fixture measures patio service and weather, not purchase return on
investment; the default setup itself is unchanged.

`tools/patio_review_sunny.tscn` and `tools/patio_review_rain.tscn` are unsaved
visual fixtures, captured with `--speed=0 --frames=60`. Both grant $2,000 and
set the weather without a draw, then pay through normal editor/history commands
for every patio cell, two tables and one waiting bench. Both open, admit ten
guests with fixed private seeds and run 120 normal ticks: in sun four guests
sit outside, in rain the patio stays empty while guests sit indoors. These
captures are separate from natural-weather balance samples. Patio source coverage lives in `tests/sim/test_patio_*.gd`,
`tests/world/test_patio_content.gd` and `tests/world/test_patio_build_session.gd`.

### Demand growth (FK-120)

`DemandTuning` in `data/balance/demand.tres` authors every calibration value.
`DemandBreakdown` multiplies reputation, word of mouth, menu variety, vibe and
the curb-appeal hook (neutral for a bare front), then caps the result at 3. Main latches reputation
and renown each morning; accepted menu and shop edits refresh only the editable
factors. `RestaurantSim.arrival_rate()` multiplies the existing hourly visit rate
by this factor. The existing `CustomerSpawner.scaled_gap` applies it once to the
authored base gaps, with no new random stream or draw. Edits never reset the
arrival countdown.

Calibration (the full paired balance report accompanies the PR):
- Reputation knots 1/3/5 stars give 0.6/1/1.6, with straight interpolation; a
  poor shop loses walk-ins while consistently good reviews allow more growth.
- Each complete happy departure earns 1 renown; each following morning keeps
  95%. Its bonus approaches 1.8, reaching half that bonus at 90 renown, so repeat
  good services build recognition without unlimited arrivals. The first measured
  candidate used 60: default five-day arrivals rose from 103.8 to 119.8 while
  losses doubled and mean profit fell 26.34%. The slower ramp protects early
  starter-shop throughput while retaining the same long-term limit. Its five-day
  confirmation averaged $67.2 against $78.2 on main, within the 25% target band.
- Each distinct enabled dish above the starter 3 adds 0.04, capped at 0.30;
  variety helps without making a long menu the whole strategy.
- Steady vibe maps 0–100 to 0.9–1.15. The actual starter vibe remains 0. Day 1
  alone uses an authored floor of 1 on its effective vibe factor to preserve
  the introductory arrival and random-draw path. Day 1's evening forecast
  already uses the ordinary Day 2 curve.
- The curb hook is exactly 1 for a bare front. At demand above 1, unlocked party sizes blend
  toward authored weights 1/.8/.6/.5/.3/.15 for sizes 1–6, reaching those weights
  at factor 3. This favours smaller groups while allowing larger tables to
  matter. At demand 1 or below, the existing size draw is called unchanged,
  including fixed-size and locked no-draw cases. Capacity clamps after the
  size draw; every drawn private seed and actual-headcount gap are retained.

`DemandState` saves renown, independent award/decay day guards, and the previous
service factor for the morning growth notice. Close awards use the sim's
idempotent complete happy-departure count, never the food/drink payment signal.
Main stages and validates the versioned `demand` section against the saved
morning before installing it. Missing legacy sections start with zero renown
at the saved day, with no retroactive decay. Failed whole loads and new runs
start fresh. Only the existing morning autosave persists this state.

`current_demand_snapshot()` returns detached factors. `forecast_next_demand()`
copies progress, applies next morning's decay once, and combines current shop
facts without awarding live renown, selecting future weather or drawing RNG.
RestaurantSim owns the read-only guest estimate alongside its clock, menu and
spawner. Expected guests are approximate: opening ticks times the mean real menu/hour
visit weight and forecast factor, divided by the mean authored base gap. No
service simulation is hidden in the estimate. The optional detached forecast
round-trips with DayReport; older reports stay valid. DemandText owns the plain
player wording; factors are multiplicative and do not pretend their percentages
add. The HUD's morning notice compares with the immediately preceding service.
Menu and Staff keep their existing controls inside an outer vertical scroll so
both notices and the panels remain readable on short, scaled windows.

The historical thick-divider two-day fixture retains its manual stock,
neutral demand, seed7 and $30 rent, comparing all six recorded fields per day
under current physical traffic. Its private-seat barrier constrains staff
access; current default throughput and thin-layout save migration are covered
separately. The manual-stock Day1 test records current-layout service through
an exact tick, complete named-stream dictionary and canonical event/private-RNG
digest, and compares both complete same-seed plays. Historical before traces
remain outside the project. No compatibility branch exists in production.

### Deeper starter room and aisle pinches (#389)

New games use `tier1_deeper.tres` (`save_layout_id = tier1_deeper`): the roomier shop with three more dining rows added on the street side, so the kitchen, pass, wall segments, lot margins, patio depth, pantry and rent are unchanged and every kitchen coordinate keeps its value. The starter tables sit one row lower than in the roomier shop, leaving a two-cell lane between the pass and their north seats. `Main.LAYOUT` is the deeper base; `Main.ROOMIER_LAYOUT` (`tier1_hole_in_the_wall.tres`, `tier1_roomier`) and `ORIGINAL_LAYOUT` stay selectable by a save's `layout_id`, so older saves load their own size. Neighbourhood, street dressing, patio, camera framing, the A-frame sign and the cat's spots are all derived from the loaded grid.

`AisleRules` (`src/sim/shop/aisle_rules.gd`) finds the walkways people actually use: one route tree each (octile Dijkstra, seats are stops, never aisles) from the street entries to every dining seat (guest steps) and to the pass's dining side, from the pass's dining side to every seat, and from the pass's kitchen side to every station and storage work cell. A route cell is a pinch when both of its sides across one axis are closed (a wall or wall segment, an item, or a seat); doorways, back doors and route endpoints never count, and cells no route crosses are ignored. A one-cell lane to a single seat still counts, because the guest and the server both walk it. Furniture buys, moves and blueprint stamps (`ShopEditor._note_aisle_pinch`) compare pinches before and after and warn on the placed item ("Tight squeeze: people can't pass each other here") when the edit newly makes one; `EditCheck.aisle_pinches` lists the cells, which `BuildPreview` tints red. Like the seat cut-off warning it never refuses, and after the commit `check_current` keeps it on that item until the next layout change (`_aisle_note`). Older layouts never gain it for a squeeze they already had.

### Roomier starter layout and existing saves (#263)

New shops use the 16×14 authored Tier 1 layout, with three tables at columns 3, 7 and 11, a centred pass at (6, 4), two-cell dining, pass and door approaches, and the same $18 rent. The unchanged plant still narrows the outer-right bottom corner; that fringe is outside the central passing corridors. `data/layouts/tier1_original.tres` preserves the previous 14×12 resource exactly. New-shop snapshots add the known `layout_id` value to the existing version-8 shop section; old bases retain their previous markerless shape. Main selects an authored base before decoding: a missing identity or whole shop section means the original base, a known roomier identity selects the new base, and an unknown or malformed present identity fails the load. No save-supplied resource path is loaded.

Lease margins always apply once to that authored base, not to an already leased/expanded snapshot. Candidate plates and owner setup must succeed before the loaded world replaces the live one. The existing morning autosave remains the only write point. Manual probe fixtures adapt their wing/table coordinates to the actual base. Coffee/bar restore the west table to its complete original pose at (2,6), with no quarter turn, retaining ten usable seats and the four-seat group. Their ordinary editor adds the side floor strips needed to reach those private seats: the west strip spans rows 6–9, and the east strip is added only when the base lacks that floor. The coffee plant sits at (5,8), outside the seat approaches. These remain declared free-construction fixtures, with normal paid stock and service; they do not measure construction return on investment.

Guests keep their own routes during deferred seat release; the automatic busser
step-off route is restricted to staff. Wall previews also protect reserved movement
edges and their diagonal corners, including exact undo/redo, while allowing
unrelated walls and removals.

### Viral reviews (#335)

`ViralReview` is pure close-time state with authored `ViralTuning` in
`data/balance/viral.tres`. Main passes actual happy departures divided by
served + lost guests, the existing report's stable best-dish selection, and a
lazy `GameState.rng(&"viral")` provider. Only a qualifying, out-of-cooldown
close asks for that stream. The ten-day interval is between trigger closes.
The next three completed open services use 1.35, 1.233333..., 1.116666...;
calendar gaps, morning reloads and report/forecast queries consume nothing.
A duplicate/stale close neither draws nor consumes. The just-closed factor
stays available for current-day queries while the forecast reads the next one.

The versioned `viral` save provider stages detached state; only a wholly
accepted morning load installs it. Absent old-save sections and new runs are
neutral. Only the existing `_begin_morning()` autosave writes it. Demand
multiplies the separate optional `viral` factor exactly once before the existing
total cap; neutral legacy snapshots retain their shape. `ViralReviewText` owns
the shared plain report, demand and morning wording. The report announcement
sits below all existing review cards so their ordinary top-scroll geometry
stays unchanged.

The existing Visual job adds one two-image `tools/viral_review.tscn` capture.
It is explicitly an unsaved close-data UI fixture, not a played-service or
probability claim: 34 served/happy, 6 lost, soup20/cheese14, fixture-only
chance1. Real Main close and next-morning handlers render the report and
reminder; observers25/75 check visible bounds and unchanged state before
photos30/90. Statistical odds and default balance are validated separately.

### Seasons and market prices (#340)

`Season.kind_for_day()` derives Spring, Summer, Autumn and Winter from the saved
clock day in 28-day blocks, repeating after day 112. It reads no random stream
and needs no save section. `data/balance/seasons.tres` authors three to five
in-season ingredient IDs and two to three out-of-season IDs per season, with
0.8 and 1.2 purchase multipliers. Startup validates the lists against the loaded
ingredient catalogue, including duplicates and overlap.

`Season.purchase_unit_cost()` is the one seasonal price calculation. It rounds
the adjusted unit to the nearest whole currency unit before the existing order
premium or haggle. This preserves integer purchase lines: a $3 ingredient is
$2 in season and $4 out of season; many $1 or $2 ingredients round to their
ordinary price. The authored ingredient, recipe sale price and quality are never
changed. `Main._unit_costs(day)` supplies the same prices to the cart, paid order
lines, automatic purchases and Stock display. Current purchases use today's day;
next-morning forecasts pass tomorrow explicitly, including a season boundary.
Paid deliveries and FIFO stock lots retain their recorded purchase cost.

The HUD date includes the season. Stock rows show an optional `In season` or
`Pricey this season` tag; a dish's ingredient details identify in-season items.
Tags appear only when the rounded price really differs from the base price
(`SeasonText.ingredient_tag` takes the base cost): at today's $1-$3 prices only
$3 items (the seafood) move, so a listed $1 or $2 item stays untagged.
The existing visual-review job adds one paused real morning Stock capture,
showing those tags and the HUD date together.

### Sites and the property market (FK-087, D28, D30) — design
Status: design for #164, revised after review. Parts 2, 4 and 6 can be built
before part 1; buying a lot and switching wait for part 1 (#408).

**Career tier (D30).** `OwnerProgress.career_tier` (1 to 6, global, saved in
`owner`) is separate from the home lease. Today's `property_tier` (1 or 2)
only meant "the home lease is expanded"; part 1 moved it into each site's own
data (`lease_expanded`, built: see "Save sections"), and a missing career tier loads as 1, or 2 when the
old `property_tier` was 2 or the owner was already at Tier 2's level (#419). Tier 2 needs owner level 3 (the level today's lease
offer needs), with or without buying the lease. Tiers 3 to 6 need an owner
level **and** the active site's closing reputation. Tiers are climbed in order,
checked at each close and never lost:
`data/balance/career_tiers.tres` (placeholders: Tier 3 level 6 and 4.0
stars, Tier 4 level 9 and 4.2, Tier 5 level 12 and 4.4, Tier 6 level 15 and
4.5). The evening report announces a new tier. Content gates (`unlock_tier`
on items, recipes, floors and wall finishes) read `career_tier`; the lease
offer needs `career_tier >= 2`, and lease size and rent read the site's own
`lease_expanded`.

**Lots (data).** `data/lots/<id>.tres` is a `LotDef`: `id`,
`display_name`, `blurb`, `base_layout` (its own `ShopLayout` and lot
margins, which also bound its maximum footprint), `price` (move-in ready) or
`fixer_price` plus `renovation_bill` and `renovation_days` (2 to 5),
`daily_rent`, `min_tier`, `min_reputation` (0 = none), `guest_mix`
(`Dictionary[StringName, float]` over existing customer types), `upstairs_allowed`
and `tags: Array[StringName]` (`&"seaside"`, `&"rooftop"`). `ContentDB`
validates them like recipes; a bad lot fails the load. The starter shop is the
implicit home lot and is never listed. `_base_for_saved_shop` gains a lookup
by lot id.
Built (#405, part 2, browse only): `LotDef` (`src/sim/content/lot_def.gd`)
has the fields above plus `expansion_price` and `expanded_daily_rent` (every
lot can expand, Jared 2026-11-13; charged since #465, see "Lot rent and
expansion").
`ContentDB.validate_lots` refuses a missing or unbuildable-looking layout
(no floor, uneven rows, no street entry, an unknown starting item), anything
but exactly one way to pay (a price, or a fixer price with a renovation bill
and 2 to 5 days), zero rent, an expansion that is free or lowers the rent, a
tier outside 1 to 6, stars outside 0 to 5, a guest mix that is empty, has a
non-positive share or names an unknown customer type (read from
`data/customers/types.tres`), an unknown or duplicated tag, and the id
`home`. The starter lots are `town_fixer_upper` (fixer-upper, 3 days,
upstairs), `seaside_cliff` (Tier 3 and 4.2 stars) and `skyscraper_rooftop`
(Tier 4 and 4.3 stars), each with its own `data/layouts/lot_*.tres` (the
starter's kitchen block in a different-sized shell); placeholder numbers.
`PropertyMarket` (`src/sim/sites`, pure) decides: `shown(career_tier)` (from
Tier 3), `listing` (cheapest to open first: the price, or fixer price plus
renovation bill; then name, id) and the tier and star locks (stars at one
decimal, like `CareerTier`). `PropertyText` (`src/ui`) holds every line of the
screen, including tag perks ("Fresh catch", "Rooftop bar", plus "Room for an
upstairs") and the guest summary from the customer types' own names ("mostly
foodies" from half the mix, else the top two). The Menu's header has a
Property button from Tier 3 (`MenuPanel.set_property_available`, set by
`set_menu_visible`); it opens `PropertyPanel` (`main.gd`
`set_property_visible`, a morning view like Goals that closes back to the
Menu and is dismissed wherever Goals is).
Capture: `tools/screenshot.sh --property-review --speed=0 --frames=12` (Tier 3
with $9,000 on the live owner: the fixer-upper's Buy button enabled).

**Buying a lot (#464, part 1b).** `PropertyMarket.purchase_refusal(lot, tier,
reputation, owned, site_count, limits, cash, loan)` gives the first reason,
in order: `OWNED`, `LOCKED` (tier, stars, or below the market tier), `LIMIT`
(`SiteLimitTuning`, `data/balance/sites.tres`: `sites_by_tier` = 1, 1, 2, 2,
3, unlimited for Tiers 1 to 6), `LOAN` (an open loan, like the lease), `CASH`
(less than `cost_to_open`); `NONE` when it can be bought.
`purchase_charges(lot)` is the price as `LOT_PURCHASE`, or the fixer price as
`LOT_PURCHASE` plus the renovation bill as `RENOVATION`, both booked to the
active site (non-operating, so they show as "New premises" and "Renovation"
on its report but never reach its profit, XP or history). `PropertyText`
words the Buy button ("Buy for $8,500", "Owned", "Locked", "Buy") and the
card's reason line ("Not enough cash: you need $500 more.", "Your tier allows
2 restaurants. Reach Tier 5 to run more.", "Pay off your loan before buying a
lot.", "You own this lot."). `main.gd` `buy_lot(lot_id)` (the panel's
`buy_requested`) refuses with `lot_purchase_refusal` (also "Buy property in
the morning."), builds the new site's sections (`_new_site_sections`: only a
`shop` section, the lot's `base_layout` as a fresh `ShopEditor` saves it, no
trays, lease not expanded, plus an empty `staff` section: a new site starts
with nobody, Jared 2026-11-13; plus a copy of the active site's `menu`
section, taken once at purchase (dishes, enabled flags and prices, with the name set to the lot's; not
the daily special or signature), Jared 2026-11-13; every other per-site section takes its
new-game default on the first switch, as a load does), and adds it with `SiteBook.add_site(lot.id, lot.id,
lot.display_name, today, sections, renovation_days)`: the site id is the lot
id. `_base_for_saved_shop` resolves a lot's `save_layout_id`
(`lot_<id>`) to its `base_layout`. Nothing is saved at the purchase (code rule
9); the next morning's autosave writes it. Bought from the panel, the site is
offered at once (`offer_new_site`, Jared 2026-11-13): the card asks "Work at
your new place today?" (a fixer-upper: "Design it today?"); "Go there now" /
"Design it now" calls `switch_site`, "Stay here today" returns to the market.
It marks the morning's site choice as made, so the card does not follow.

**Lot rent and expansion (#465, Jared 2026-11-13).** A bought lot's site pays
its `LotDef.daily_rent`, or `expanded_daily_rent` once its own
`lease_expanded` is set, whether it is active (`_charge_closing_costs`, as
`RENT`) or away and unmanaged (`AwaySites.plan_close`, as `AWAY_SITE_RENT`).
`AwaySites.lot_rent(lot, home_rent, definition, expanded)` is the one rule:
the home lot keeps `_home_rent()` exactly, any other lot reads its
`LotDef.rent(expanded)`; only a lot missing from the data is still unknown
(charged nothing, with a warning). Rent runs from the day a lot is bought:
its first close is that day's, and a renovating site pays on every close
(away, or active and closed with "Close for today"). A site with renovation
days left is always closed for `plan_close`, even with a manager (it cannot
open), and `_close_away_sites` plans before the renovation countdown so the
last renovation day still counts as one.
Every lot can expand once. `LotDef` has its own margins, `expansion_west`,
`expansion_east` and `expansion_north` (0 to `MAX_EXPANSION_CELLS` = 32 each,
at least one above 0; the street side never grows), checked by
`validate_lots` with the expansion as a lease (`LotDef.lease_upgrade(home)`
must be a valid `LeaseUpgrade`: its price is the deposit, its expanded rent
the daily rent). Placeholders: the fixer-upper 0/4/3, the seaside cliff
0/4/2, the rooftop 1/2/1 (west/east/north). `main.gd` `_lease_for(base)`
picks the terms by the authored base layout (a lot's own, else the home
`LEASE`), and the offer, its refusal, `lease_buy`, `_lease_layout`, the shop
restore and the scenery reserve all read it, so the Menu offers "Deposit
$4,000 · Daily rent $95" at the fixer-upper and the purchase grows that
lot's own `base_layout`. Home is unchanged.

**Unstaffed sites (#464).** `StaffRoster.from_dict` and
`RestaurantSim.set_staff_roster` accept a roster without a cook or a server
(0 to 6 people); `StaffRoster.is_staffed()` says whether it can run a
service. `can_let_go` still keeps an established roster's last cook and
server. While a roster lacks either, `draw_candidates` gives the first
candidates those roles (same draws, so a staffed roster's pool is unchanged).
Locks read `main.gd` `closing_reputation()`: the active site's reputation once
it has closed a day (its `business_history` has a row), the value `CareerTier`
read at that close; NAN before the first close, so a first-morning lock line
reads "Locked: needs 4.2 stars" instead of quoting the starting 3.0.

**Morning site card (#464, Jared 2026-11-13).** `SiteCard`
(`src/ui/site_card.tscn`, every line in `site_card.gd`) shows at the end of
`_begin_morning` once a morning (`_site_card_day`) when the owner has two or
more sites and the first-morning owner picker is not up; a dim backdrop
blocks the world until a choice. One row per site (active first): its name,
"Yesterday's takings: $412" (`SiteMorning.takings`: that site's own `SALE`,
`TIP` and `AWAY_SITE_INCOME` ledger entries for yesterday) or "Renovating: 3
days", "Manager: Ana" or "No manager" (the active roster, or the frozen
`staff` section), and a button: "Stay here" on the current site (and
Escape), "Work here" or, while renovating, "Design here" (calls
`switch_site`), or, disabled, the real reason from `site_switch_refusal`
("Close Build first", "Finish the haggle first", "Choose your owner first",
"From tomorrow", "Mornings only"). A refused pick is logged
(`_log_switch_refusal`). The status line is "Yesterday's takings: $X" (gross
`SALE` and `TIP`) for the site the owner worked, "Yesterday's earnings
(after the manager): $X" (`SiteMorning.away_earnings`, net) for a managed
away site, "Closed yesterday" for an unmanaged one, or "Renovating: N days".
While the card is up, `_unhandled_input` swallows every key but Escape (no
Build, Paint or owner-mode keys under it). A switch marks the card shown for that day, so the
arriving site's morning does not show it again. Opening the restaurant hides
it, and it cannot be shown outside the morning. Capture:
`tools/screenshot.sh --site-card-review --speed=0 --frames=12,30` (Tier 5, the
fixer-upper bought, the seaside lot added as a ready site; frame 30 shows the
same-day question for the seaside lot).

**Lot-only content.** `ItemDef` and `IngredientDef` gain `lot_tags` (empty =
everywhere). The catalogue, blueprint stamps and stock panel show a tagged
entry only at a site whose lot shares a tag. Lot-only items stay with their
site when furniture moves (part 5).

**Save sections.** Every registered section is classed once in
`src/sim/sites/site_sections.gd`; a test fails when one is missing.
- **Global:** `owner`, `game_state` (seed and RNG streams), `clock` (day and
  phase), the economy books (`ledger`, `loan`), `blueprints`, `milestones`,
  `weekly_challenge`, `hints`, `weather`, `collection_toasts` (a collection
  is celebrated once per career), and the new `sites` section.
- **Per site:** `shop`, `menu`, `daily_special`, `signature`, `staff`,
  `plates`, `reviews`, `regulars`, `reorder`, `deliveries`, `demand`, `viral`,
  `business_history`, `shop_records`, `cat`, `inspection`, `critic`,
  `bookings`, `rush_hour`, `aquarium`, plus two split out in part 1: `pantry`
  (the kitchen stock, split out of `economy` in #411) and `site_hours`
  (opening hours, split out of `clock` in #408).

Built (#408 part 1): `site_hours` is `{"version": 1, "open_minute",
"close_minute", "open_ticks"}`, captured from the live `SimClock` and staged
like every per-site section; the morning load and the switch install it on
the clock (`_stage_site_hours`, `_install_staged_sections`). The `clock`
section keeps its own copy of the hours, which simply follows the active
site; a save from before the section keeps the clock's hours, a frozen copy
without it opens on the default day, and hours outside the limits reset to
the default day with the load's note rather than refusing. The lease is the
`shop` section's `"lease_expanded": bool` (main.gd `lease_expanded`), read by
`_lease_layout`, `LeaseUpgrade.offered/refusal(progress, expanded, ...)` and
`_home_rent` (which reads the home site's frozen `shop` when another site is
active). `OwnerProgress.property_tier` is no longer saved: an old save's
value 2 is read once as the site's lease when its `shop` has no
`lease_expanded`, and set back to 1 once the load has installed.

**Where a site's own fields live (#413).** `SiteBook` (`src/sim/sites`)
holds the active site id and one row per site: id, lot, name, manager (a
member id in that site's own `staff` section) and, for an inactive site, its
frozen day and per-site sections, kept in loaded-file JSON shape. Fields that
only change while a site is active (such as `lease_expanded`) belong in its
per-site sections and swap with it. Fields that change while it is inactive
(renovation days left) go on its book row, which needs a new `sites`
VERSION: the decoder refuses unknown keys rather than drop them.

**Switching (part 1).** Only in the morning, before opening, and only after
the departing site's morning has run (restock bought, staff changes, plans
made): that morning's results stay with it. Steps:
1. Capture the departing site's per-site sections into its frozen copy in
   `sites`, with today as its frozen day. Deliveries due later stay in its
   book.
2. **Thaw** the target's frozen copy in memory: each per-site section with
   day-bound state gets a `thaw(frozen_day, today)` step (demand decays across
   the gap like `DemandState.begin_morning`; the daily special clears;
   signature, viral and rush-hour days shift or lapse; delivery due days move
   forward by the gap, once, here only).
3. Stage the thawed copy through a new
   `SaveSystem.restore_sections(sections, keys)` (#412): every per-site
   provider restores from the dictionary in registration order; if one
   refuses, all of them are restored again from a capture taken first, so the
   active site is exactly as it was (in place: the pantry keeps its `Stock`
   object). The switch then clears main.gd's `_loaded_*` staging, which holds
   the rolled-back copy. A refusal never starts a new game. Global sections are never touched
   (except that rewiring, like any reload, redraws the customers RNG stream). (#411
   already split the old single `economy` section into the global books and
   the per-site `pantry`; `SiteSections` lists both sides.)
4. Install, then rewire the session: the existing post-load setup in
   `start()` (RNG binding, cleanliness, reviews, customer types, editor,
   clock attach, build session) moves into one `_wire_session()` used by both
   start and switch, and the old sim's signals disconnect first.
5. Run the target's morning entry (`_begin_morning` without the autosave),
   then autosave once.
Owner is global and already installed, so its order before `shop` and `menu`
still holds.
Built so far (#408 C3): `main.gd` `switch_site(target)`, called by the
morning site card since #464. Validation and install are `_validate_staged_sections` and
`_install_staged_sections`, shared with the morning load (which also stages
the global sections); the switch carries today's weather to the new world. A
frozen copy without a `pantry` gets an empty one (the pantry restores in
place, so skipping it would keep the departing stock); other missing sections
take their load defaults. A refusal after a successful restore restores the
departing capture again (for the pantry) and clears the staging. The
morning's one supplier haggle is the owner's and is not reset by a switch
(an offer won and not yet spent still applies at the arriving site). Today's
main.gd report state follows the site (#408 D2): the haggle receipt names
its site, so the saving shows only on that site's report; the arriving
morning resets dishes sold, food cost, expiry, the auto-order and delivery
notes; and notes kept nowhere else (hand throw-outs, a trimmed cart, staff
notices, team activity, menu access losses) are dropped on a switch.

**Managers and away sites.** A new staff role **Manager** (hired at Tier 3,
skill is the existing service skill). An inactive site with a manager earns,
at each close of the active site:
`min(rate × mean, mean)` over its last 7 recorded in-person
`business_history` days (`dish_profit_recorded` only; fewer rows use what
exists; none means 0). `rate` is 0.70 at skill 1 rising to 1.00 at skill 5.
That mean is already net of its wages and rent, so a managed site pays nothing
else. An unmanaged inactive site stays closed and pays only its rent. Away
days are never written into a site's history. No RNG (D24 amended: a
deterministic summary, not a seeded sim).
Built so far (#408 D2): `StaffMember.MANAGER` (`&"manager"`, primary skill
`service`, wage in `tier1_economy.tres`). `StaffMember.ROLES` stays the floor
roles; `StaffRoster.draw_candidates(day, rng, managers)` adds Manager to the
role draw only from `data/balance/site_managers.tres` `hire_tier` (3), with
the same number of draws, so pools below it are unchanged (a test pins them),
and `main.gd` refuses a manager hire below that tier. A manager does no floor
work anywhere: `RestaurantSim.set_staff_roster` gives them no agent (so no
tasks), and `_charge_closing_costs` pays their wage from the roster.
`main.gd` `assign_site_manager(member_id)` (tests only, no UI) stores a
Manager of the active roster on the active site's book row; it clears when
that member leaves (`_prune_site_manager`, after a hire/let-go and each
morning's roster install). At the active site's close, after its own costs
and booking, `_close_away_sites` applies `AwaySites.plan_close` (pure,
`src/sim/sites/away_sites.gd`) to every frozen site and books each movement
with `Economy.add_cash_for_site` to the site that made it, so the active
site's report, history, records and XP never see it:
- A **valid manager** (the row's id is a Manager in that site's frozen
  `staff`) earns `round(min(rate × mean, mean))` over the last
  `history_days` (7) recorded rows of its frozen `business_history`, as
  `AWAY_SITE_INCOME`; `rate` runs linearly from `rate_at_skill_1` (0.70) to
  `rate_at_skill_5` (1.00). A **negative mean is paid as a loss**: the
  formula is applied as written, and min() takes the whole mean, since a
  manager never does better than the owner did (and the mean already
  includes the wages and rent that would otherwise make the loss).
- **No valid manager** (or still renovating, or a manager with no recorded
  day to go on yet: away days never build history, so such a site would
  otherwise never pay; its line reads "Pier Shack (closed: your manager
  needs a day you ran there first): rent -$70", #465): rent only, as
  `AWAY_SITE_RENT`. `AwaySites.lot_rent` gives the home lot's lease rule and
  any other lot's own rent, expanded or not (#465, "Lot rent and
  expansion").
- **Bookings**: an accepted booking whose service day is today or earlier
  lapses, managed or not: `BOOKING_REFUND` of the deposit to that site, and
  its frozen `bookings` section is rewritten in place
  (`SiteBook.set_frozen_section`, JSON shape, frozen day kept), so the thaw
  finds nothing more to refund.
The evening report lists one line per other site (`DayReport.away_site_lines`,
saved in the report only when present): "Pier Shack (managed): +$84",
"Pier Shack (closed): rent -$40". A one-site game adds no save field and
books nothing here.

**Staff transfer (#473, part 5).** In the morning (`can_edit_staff`, so
never mid-service), the Staff panel's "Send to…" `MenuButton` on an
employee lists the owner's other sites (renovating ones included: a crew can
be ready for the opening day). `StaffTransfer` (`src/sim/staff`, pure) has
the rules, in order: an unknown person (`UNKNOWN`), the departing site's last
cook or server (`LAST_OF_ROLE`, `StaffRoster.can_let_go`, the same rule as
letting go), a Manager to a site that already has a running manager
(`HAS_MANAGER`: its book row names a Manager on its own staff,
`AwaySites.manager_skill > 0`, the same test `plan_close` uses; a Manager
on the staff whom the row does not name does not block one), a full
destination (`FULL`,
`StaffRoster.CAPACITY`). `StaffTransfer.move` takes the person out with
`let_go` and into the destination with `StaffRoster.accept_transfer`, as they
are: skill, trait, wage, growth (mood, XP, raise history, quit day), job
priorities and lifetime work. Ids are unique only within one roster, so an id
already used at the destination (by an employee or a candidate) becomes
`<id>_2`, `<id>_3`... `main.gd` `staff_transfer(id, target)` reads the
target's frozen `staff` section (or the starter team a copy without one would
load), moves the person, reinstalls the live roster (the agent leaves at
once) and writes the destination back with `SiteBook.set_frozen_section`
(frozen day kept). A Manager who moves becomes the destination's manager on
its book row, so it earns while the owner is away; the departing site's row
clears through `_prune_site_manager`. A Manager hired at a site runs it once the
owner leaves: `switch_site`, past its last refusal, calls
`_adopt_site_manager` on the departing site, which, when its row names no
valid manager, sets the row to `AwaySites.best_manager` of its staff
(highest skill, ties to the smaller id; deterministic). The morning site card
then shows them. A refused transfer is logged ("Could not send them to …"). No ledger entry (no fee, no
severance), no RNG and no save: the next morning autosave, or the switch's,
writes both sites. Wages are unchanged: the person is paid at a site's close
only while that site is active, as for any frozen roster. The panel words
the refusals in `StaffPanel.transfer_refusal_text` ("Second (already has a
manager)", "Second (team is full)" on a disabled item; a last cook or server
disables the button with "Keep at least one cook and one server here.").

**Ledger.** Each ledger entry records the site that made it (an id; entries
from saves before part 1 belong to the home site). The day report, business
history, records and XP read only the active site's entries for the day, so a
departing site's morning spending stays in its own books. New categories `AWAY_SITE_INCOME`, `AWAY_SITE_RENT`,
`LOT_PURCHASE` and `RENOVATION`, all in `DayReport.NON_OPERATING_CATEGORIES`,
so they never reach the active site's operating profit, XP, records,
business history or weekly challenge.

**Limits and renovation.** `data/balance/sites.tres`: sites allowed by career
tier (2 at Tier 3, 3 at Tier 5, unlimited at Tier 6). A fixer-upper's site
stores `renovation_days_left`, and the days count down at each close of
whichever site is active.
Built (#464): the `sites` section is VERSION 2. A row may carry
`"renovation_days_left"`: a whole number 1 to `LotDef.MAX_RENOVATION_DAYS`,
written only while above 0 (0 or anything else present is refused). Version 1
still loads (the migration: every site ready) and saves as version 2.
`SiteBook.add_site(..., renovation_days)`, `renovation_days_left(id)`,
`count_down_renovations()` (called at the top of `_close_away_sites`, so only
with two or more sites; returns the ids that became ready) and `owns_lot`.
While above 0 the site can be switched to and designed (D28; Jared
2026-11-13), but cannot open to guests. `main.gd site_opening_refusal()`
gives "Still renovating: 2 days left", else, for an unstaffed roster, "Hire a
cook and a server before you open". `_refresh_opening_block` (after each
menu-catalogue refresh, so every morning, switch and Build change, and after
each hire or let-go) puts it on `SimClock.opening_refusal` (not saved; while
set, `start_service` refuses) and the HUD: the Open shop button reads "Close
for today" with the reason, and emits `close_day_requested`.
A layout with no cookable dish (`_menu_access_error`, `MenuAccess.NO_DISH`)
gets its own refusing notice back once the site's reason clears, so Open shop
stays disabled (no "Close for today"); as before, it is not on the clock,
since a legacy layout the access check flags can still serve.
`close_for_today()` then ends the day without a service:
`SimClock.close_without_opening()` (MORNING to CLOSED, only while a refusal
is set), the dock's stock is put away, and `_on_service_closed` runs the
ordinary close (wages, rent, away sites, the countdown, the report with no
guests). It is not a business day (`_closed_day`): no `business_history` row
(so `closing_reputation()` stays NAN at a site that never served, and
manager averages skip it), no trending-post or demand close, no owner XP,
goals, records or tier climb; the weekly goal is evaluated with nothing
earned so its saved day still follows the calendar. The evening report's away line adds "; renovating, 2 days left",
then "; renovation done, ready to open". A fixer-upper bought on day D with 3
days can open on day D+3 once it has a cook and a server.

**Bookings.** A group booking belongs to its site. If that site is not
active on the booked day, the booking lapses at that day's close with the
deposit refunded (`BOOKING_REFUND`) and no reputation change. New offers come
only to the active site. Built so far (#414): `SiteThaw` refunds such a
booking when its site is switched back to; since #408 D2 the close of the
active site settles it on its day (`AwaySites`), so the thaw's refund is only
a safety net (a booking that slipped past a close).

**Weekly challenge.** It stays global and counts the active site's sales. A
featured dish the active site cannot cook simply makes no progress that day.

**Prestige (part 6).** `Prestige.score(grid, content)` is pure: the sum of
placed items' `prestige`, clamped to the lowest `prestige_cap` present (slots,
pool table, neon). Staff that add prestige (sommelier, pianist) come later.
Golden Ladles (0 to 3) come from data thresholds and are awarded only on a
good critic review, kept per site in `critic`.

**Later parts.** Moving furniture between sites (part 5; staff transfer is built, #473),
bar gambling income (part 7), upstairs (part 8).
