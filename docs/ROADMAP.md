# Fool's Kitchen: Roadmap

Hobby pace: there are no dates, only exit criteria. Each phase ends with a playable build. Placeholder art (primitive shapes, free CC0 Kenney packs) is fine until Phase 4.

## How work flows
- **Claude (director):** keeps the design, breaks phases into issues, builds the foundation pieces other work depends on, and reviews every PR against its issue and `AGENTS.md`.
- **OpenAI workers:** take issues labelled `worker-ready`. One issue per PR, `Closes #N`.
- **Jared:** taste and lore calls, playtests each phase build, merges or asks for changes.
- Each phase has a tracking issue (`Phase N: ...`) that lists its task issues.

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
- [ ] Shops: ingredient market and furniture catalogue (done), stock panel and auto-reorder (#54)
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
- [ ] First-person walk mode as the owner (D12)
- [ ] Mini-games in first person at the station: chop rhythm, pan flip, plating. Supplier haggle (a menu game).
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

## Phase 5: Expansion
- [ ] Tiers 4 to 6: the piano bar and evening service, a second floor, fine dining and critics, the chain with managers
- [ ] Events (inspector, rush hour, viral review)
- [ ] Sandbox mode
- [ ] More recipes, themes and mini-games
- [ ] A balance pass, and playtests with family and friends

## Phase 6 (optional): Release prep
- [ ] Steam page and build, settings, controller support, achievements
