# Fool's Kitchen: Roadmap

Hobby pace: there are no dates, only exit criteria. Each phase ends with a playable build. Placeholder art (primitive shapes, free CC0 Kenney packs) is fine until Phase 4.

## How work flows
- **Claude (director):** keeps the design, breaks phases into issues, builds the foundation pieces other work depends on, and reviews every PR against its issue and `AGENTS.md`.
- **OpenAI workers:** take issues labelled `worker-ready`. One issue per PR, `Closes #N`.
- **Jared:** taste and lore calls, playtests each phase build, merges or asks for changes.
- Each phase has a tracking issue (`Phase N: ...`) that lists its task issues.

## Up next: the build queue (reset 2026-11-19)
**Codex: take the `worker-ready` issues below from the top**, skipping any whose **Depends on** hasn't merged and any that already has an open PR or a claim comment (see `AGENTS.md`). Claude reviews every PR before merge. `codex` = Codex takes it; `both` = Codex may try, Claude takes over if it fails twice.

**Wave O, early-game feel (Jared, 2026-11-20, from a new-game playthrough of days 1 to 3): take these first.**
1. `codex` #704 Early game: guests from opening, a lunch and dinner shape, and rushes that arrive
2. `codex` #705 Service: live toast when guests leave unserved, and a "Paused, press 1x" line
3. `codex` #706 Early game: no dish sells out on days 1 to 3
4. `codex` #707 Evening report: a cash line that adds up
5. `codex` #708 Build catalog: locked item tiles show the item's name
6. `codex` #709 Morning and evening: one panel at a time

**Wave N, early game, the chain and guests (Jared, 2026-11-19; chain goals added from D43, #677): next.**
7. `codex` #676 Early game: no "serve N" weekly challenge while the Opening week runs
8. `codex` #667 Evening report: one "Your chain today" line across all your restaurants
9. `codex` #668 Morning site card: each away restaurant's tonight result and top alert
10. `codex` #670 City screen: open it any time with M (read-only outside the morning)
11. `codex` #669 City screen: buy a lot for sale right from the city screen
12. `codex` #653 Four small guest quirks: sweet tooth, big eater, indecisive, early bird
13. `codex` #663 New guest type: farmers at Old Mill Street (after #653)
14. `codex` #657 New guest type: walkers at the Seaside Cliff
15. `codex` #658 New guest type: surfers at the Beachfront Boardwalk
16. `codex` #659 New guest type: foragers at the Woodland Cabin
17. `codex` #654 Guest quirk: the window-seat lover
18. `codex` #655 Guest quirk: the maybe-famous guest draws a small crowd
19. `codex` #656 One tourist in twenty returns as a named regular
20. `codex` #680 Chain goals G1: the Ladle ladder's data, rules, payouts and save
21. `codex` #681 Chain goals G2: the goals line on the city screen and the ladder card (after #680)
22. `codex` #682 Chain goals G3: name your chain at the second restaurant (after #680)
23. `codex` #684 Birthday table bookings and the dog walker quirk (sim only)
24. `codex` #693 US spelling across all player-facing text, with a guard test
25. `codex` #698 Rival R1: the sim (docs/RIVALS.md, D44)
26. `codex` #699 Rival R2: the rival card, HUD chip, paper and city badge (after #698)
27. `codex` #700 Rival R3: Copley's stunts (after #698)

**Wave L, every location plays differently (Jared, 2026-11-18; D39, #596):**
28. `both` #623 Seaside Cliff: terrace-only seating rule
29. `codex` #605 Seaside Cliff: the daily catch
30. `codex` #604 Old Mill Street: country food, the bread oven and a farm-gate discount
31. `codex` #624 Seaside Cliff: sea-view seats add vibe and price tolerance
32. `codex` #617 Rooftop: guests step out of the lift lobby, in small bursts
33. `both` #629 Seaside Cliff: guests walk up and down the cliff path
34. `both` #626 Local food: each location's own ingredients, a Local tag and bonus
35. `both` #597 Growth steps: each lot grows its own way
36. `codex` #608 Woodland Cabin lot: foraged food and seasonal foraging
37. `both` #606 Skyline Rooftop: cocktails and a tasting menu
38. `both` #590 Walk-up window: a hatch that serves passers-by

**Wave M, engine and polish (after wave L, or alongside it when a wave L issue is blocked):**
39. `both` #548 Dead-end aisles: guard two #545 fixes with tests
40. `both` #587 main.gd seam 4a: the Stock panel binds its own commands
41. `both` #391 Aisle pinch warning: faster hover, more routes
42. `both` #384 Light staff mood
43. `both` #378 Group bookings: the good-service payoff
44. `codex` #371 Sixty more review quotes
45. `both` #356 Day off
46. `both` #324 Broken equipment
47. `both` #339 Dishwasher
48. `both` #328 Chop rhythm mini-game
49. `both` #341 Plating mini-game for VIP guests

**When this list runs out,** take any open issue labelled `worker-ready` and `codex` (then `both`), lowest number first, with the same checks.

Several issues touch the same screens or the same lot files. Running two or three Codex tasks at once is fine; merge `main` into your branch before marking ready, as `AGENTS.md` says.

**Director-scoped (`claude`, art or taste first):** the awards night #683 (after #680); the dog and birthday balloon art #660 (after #684); the rival's art and words #701. Done 2026-11-19: premium decor #206, city map art #642, travel feel #644, guest looks #661 and voices #662.
**Later backlog (`claude` until scoped into `codex` issues):** #164 more sites, #167 makeovers, #169 staff drama, #170 design extras, #171 food depth, #172 more visitors, #173 the rest of the neighbourhood ideas (apps, a changing area; the rival is D44), #159 more entertainment (stage, games corner).

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
