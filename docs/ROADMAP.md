# Fool's Kitchen: Roadmap

Hobby pace: there are no dates, only exit criteria. Each phase ends with a playable build. Placeholder art (primitive shapes, free CC0 Kenney packs) is fine until Phase 4.

## How work flows
- **Claude (director):** keeps the design, breaks phases into issues, builds the foundation pieces other work depends on, and reviews every PR against its issue and `AGENTS.md`.
- **OpenAI workers:** take issues labelled `worker-ready`. One issue per PR, `Closes #N`.
- **Jared:** taste and lore calls, playtests each phase build, merges or asks for changes.
- Each phase has a tracking issue (`Phase N: ...`) that lists its task issues.

## Up next: the Codex queue (set 2026-10-29)
Codex takes `worker-ready` issues in this order; the director validates, reviews and merges every PR, and builds only what needs art judgement. Each wave can run in parallel inside itself.

**Wave 1, ready now (game logic, data and UI with tests)**
- #209 Grid on/off in normal play too (remembered, HUD button, setting) — first, it's small
- #189 Warn when a build edit cuts staff off from menu dishes
- #196 Bar-snack fries from frozen fries
- #197 Bakery menu section
- #203 Waiting bench by the door
- #113 Dish quality breakdown
- #179 Hygiene overview in Build
- #108 Title screen, then #110 First-day guide
- #211 Pick your owner character (hooks into #108's New game if merged)
- #126 Seafood menu (data; the deck-plank floor after #202)
- #114 Tier 2 lease upgrade (more lot to expand)

**Wave 2, after wall finishes and decor (#207) merge**
- #205 Smarter cutaway, then #208 Day and night cycle (morning prep, service into the evening, close and wind-down), then #84 Lighting decor
- #198 Restroom decor (mirror, hand dryer, stall partitions)
- #201 Hex tile and terracotta floors, then #202 terrazzo, concrete, carpet
- #161 Menu boards show your menu, theme read-out (after #197)
- #83 Blueprints
- #150 Furniture variants

**Wave 3, the designer core is done**
- #166 Named regulars (first backlog pick)
- #127 Everyday messes (spills, broken plates, grease)
- #99 Food on plates, dirty plates, steam
- #118 Made icons (chef hat, paint brush)

**Then, director-scoped as each comes up**
- #168 Street front, patio and a simple overworld, with exterior wall finishes and weather
- #117 Sound and music
- #85 Tier 1 balance pass (measure first)
- Later backlog: #164 more sites, #167 makeovers, #169 staff drama, #170 design extras, #171 food depth, #172 visitors, #173 neighbourhood, #159 entertainment, #180 café counter, #206 premium decor, #125 aquarium

**Also ready (Jared, 2026-10-29):** #114 Tier 2 is a lease upgrade that grows your lot (no move, keep your build). The cat #119 arrives at shop level 4 (art, director-scoped).

## Phase 0: Foundation
- [ ] Project skeleton, autoload stubs, test runner, `check.sh`, `get_godot.sh` (FK-001, Claude)
- [ ] CI on every PR (FK-003)
- [ ] Isometric camera and test floor (FK-002)

**Exit criteria:** the project opens, the camera works, CI is green.

## Phase 1: One shop, one day (the vertical slice)
The Tier 1 hole-in-the-wall: 1 door, 3 two-seat tables, 1 fridge, 1 prep counter, 1 stove, 1 pass. One cook, one server, and the owner. 3 recipes.

- [ ] Sim clock: a fixed tick, the day phases (morning, open, last orders, closed), speed controls
- [ ] Content resources: `Recipe`, `Ingredient`, `ItemDef` classes, plus the first data files
- [ ] Grid and pathfinding: `SimGrid` on `AStarGrid2D`, item footprints and work cells
- [ ] Task board and the staff agent: claim, timeout, self-heal
- [ ] Customer agent: the state machine, patience, ordering, eating, paying, review
- [ ] Kitchen chain: ticket, fetch, prep, cook, pass, deliver, bus
- [ ] Economy: stock, cash, a daily profit-and-loss total
- [ ] World view: a fixed shop scene, agent visuals interpolating sim positions, placeholder meshes
- [ ] HUD: cash, clock, speed buttons, customer mood icons. Click an agent to see the "why" readout.
- [ ] Evening report screen
- [ ] Owner click-to-assign
- [ ] Save and load (JSON, versioned)
- [ ] Debug overlay (F3)
- [ ] Sim invariant test (several seeded days, no stuck agents, every customer leaves)

**Exit criteria:** you can play 3 days in a row. Money goes up or down for reasons you can see. The invariant test is green. Jared has playtested it.

## Phase 2: Build mode and running the shop
- [x] Grid placement (move, rotate, sell) with live path warnings, closed-only structural edits
- [ ] Blueprints (save and stamp)
- [ ] Paint and colour slots on walls, floors and furniture from palette swatches (Sims-style)
- [ ] Lighting decor (lamps, then chandeliers at Tier 3)
- [x] Menu screen: choose dishes, set prices against the standard price
- [x] Shops: ingredient market and furniture catalogue, stock panel and auto-reorder (#54)
- [x] Walls, doorways and windows (#120)
- [ ] Floor expansion to the back and sides (#153)
- [ ] Sims-style Build and Buy modes: categories, theme filters, undo, eyedropper (#160, D23)
- [ ] Concepts: coffee shop and bar, drinks, counter seating, opening hours (#158, D23)
- [ ] Menu designer: name, sections, unlock tree, menu boards (#161, D23)
- [x] Rooms and restrooms as built rooms (#115, #192)
- [x] Back door foundation (#191); real swinging door and one per shop with visible deliveries (#187, D25)
- [x] Floor types and patterns painted per cell or per room: wide and narrow planks, herringbone, small tiles, checker (Sims-style, D25, #200)
- [ ] More floor types: hex tile, terracotta (#201); terrazzo, concrete, carpet (#202) (D25)
- [x] Smooth motion between sim ticks (presentation only) (#204)
- [x] Wall finishes and wall decor: wallpaper, panels, tile, brick; framed art, menu boards, neon (D26) (#TBD)
- [ ] Waiting bench by the door: more guests wait, longer (D26)
- [ ] Smarter cutaway: lower only the walls facing the camera (#205), then lighting decor (lamps, pendants, chandeliers at Tier 3) next (Jared, 2026-10-29)
- [ ] Sound and music after the designer core: ambience, UI clicks, cooking sounds, a light music loop (Jared, 2026-10-29)
- [x] Hiring pool, traits, wages
- [ ] The priority matrix
- [x] Plate cycle (sink, dirty plates)
- [ ] Cleanliness and the cleaner role
- [ ] Trays (carry capacity upgrade)

**Exit criteria:** you can redesign the shop and see throughput change. Staff choices visibly matter.

## Phase 3: Progression
- [ ] Owner XP, level, reputation stars, review quotes
- [ ] Property Tiers 1 to 3 (hole-in-the-wall, diner, bistro), rent or buy, moving up
- [ ] Unlock tables. The restaurant cat (Tier 2). The restroom need (Tier 2).
- [ ] Decor ambience (diminishing returns, variety) and themes
- [ ] Customer types
- [ ] Career milestones
- [ ] Loan rule
- [ ] Second location from Tier 3: switch sites, background sim, shared cash
- [ ] Staff XP and levelling

**Exit criteria:** you can climb from a hole-in-the-wall to a bistro in about 3 to 5 hours, and each tier plays differently.

## Phase 4: Look and feel
- [ ] Art direction locked: the palette texture, a lighting rig and a style sheet (warm and cosy, D13). Final models for the core set (TECH 3).
- [ ] Animations: walk, carry, cook, eat, sit
- [ ] Lighting over the day, particles (steam, smoke)
- [ ] Audio: ambience, UI sounds, music
- [ ] A UI art pass
- [ ] Web build published for family and friends

## Idea backlog (Jared liked these, 2026-10-27; scheduled after the designer core)
Each is a `phase-later` issue. Pick from here when Phase 2's designer work is solid.
- [ ] More sites run by managers (#164, D24)
- [ ] Named regulars who remember your place (#166): first after the designer core (Jared, D26)
- [ ] Street front and patio, with curb appeal and weather (#168): second (D26); needs a simple overworld (road and neighbourhood around the lot) and outdoor waiting seats when the weather allows; exterior wall finishes (brick front, siding, shopfront) come with it
- [ ] Makeover jobs, renovating to a brief as career side jobs, needing a D7 amendment (#167)
- [ ] Staff relationships and drama (#169)
- [ ] Design extras: collection sets, lighting moods, staff room, blueprint codes (#170)
- [ ] Food depth: signature dish, seasons and market, supplier choice (#171)
- [ ] Visitors: disguised critic, health inspector, group bookings (#172)
- [ ] Neighbourhood: rival, parody review and delivery apps, a changing area (#173)
- [ ] Entertainment: jukebox, stage, games, weekly theme nights (#159)

## Later (D21): first person and mini-games
- [ ] First-person walk mode as the owner (D12)
- [ ] Mini-games, mainly for emergencies and clean-ups (a short first-person moment), maybe station games later

## Phase 5: Expansion
- [ ] Tiers 4 to 6: the piano bar and evening service, a second floor, fine dining and critics, the chain with managers
- [ ] Events (inspector, rush hour, viral review)
- [ ] Sandbox mode
- [ ] More recipes, themes and mini-games
- [ ] A balance pass, and playtests with family and friends

## Phase 6 (optional): Release prep
- [ ] Steam page and build, settings, controller support, achievements
