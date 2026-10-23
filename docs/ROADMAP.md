# Fool's Kitchen: Roadmap

Hobby pace: there are no dates, only exit criteria. Each phase ends with a playable build. Placeholder art is fine until Phase 4.

## Phase 0: Foundation
- [ ] Install Godot 4 (latest stable) and record the version in `docs/TECH.md` and `AGENTS.md`.
- [ ] Create the project skeleton (the folder layout in TECH.md 2.1), autoloads as stubs, and GUT installed.
- [ ] `tools/check.sh` (headless parse and import, plus GUT) passing.
- [ ] An isometric camera (pan, zoom, rotate in 90 degree steps) over a flat test floor.

**Exit criteria:** the project opens, the camera works, and the checks are green.

## Phase 1: One kitchen, one day (MVP)
- [ ] Clock with day start and end, and speeds of pause, 1x, 2x and 4x.
- [ ] A fixed layout: a door, 4 tables, 1 stove, 1 counter.
- [ ] Customers: arrive, sit, order, wait (patience), eat, pay, leave.
- [ ] One chef and one server on the task board.
- [ ] 3 recipes and a simple ingredient stock.
- [ ] HUD: money, time, customer moods. A summary screen at the end of the day.
- [ ] Save and load.

**Exit criteria:** you can play 3 days in a row, money goes up or down for understandable reasons, and the sim unit tests are green.

## Phase 2: Build mode and menu
- [ ] Grid placement, rotation, selling and moving items, with a navmesh rebake.
- [ ] Path validation warnings.
- [ ] A menu screen: choose dishes and set prices.
- [ ] Shops: an ingredient market and a furniture catalogue.
- [ ] Hiring screen, wages, and staff skill.

**Exit criteria:** you can redesign the restaurant and see the effect on throughput.

## Phase 3: Progression
- [ ] Owner XP and levels, and reputation stars from reviews.
- [ ] Unlock tables for recipes and items.
- [ ] Property tiers 1 to 3 (cart, diner, bistro), with buy or rent.
- [ ] Themes: a theme score and its effects.
- [ ] The first 3 mini-games (chop, plating, haggle).

**Exit criteria:** you can climb from a cart to a bistro in about 3 to 5 hours of play.

## Phase 4: Look and feel
- [ ] Final low-poly models for the core set (see TECH.md section 3).
- [ ] Character animations: walk, carry, cook, eat, sit.
- [ ] Audio: ambient sound, UI sounds, music.
- [ ] Lighting with a day and night tint, and particles (steam, smoke).
- [ ] A UI art pass.

## Phase 5: Expansion
- [ ] Property tiers 4 and up, including the bar and the night shift.
- [ ] Multiple locations with background sim and managers.
- [ ] Events: critic, inspector, rush hour.
- [ ] More mini-games and themes.
- [ ] A balance pass, and playtests with family and friends.

## Phase 6 (optional): Release prep
- [ ] Steam page and build, settings menu, controller support, achievements.
