# Changelog

Every merged change gets an entry here, in the PR that makes it (CI checks this). When a build is published, the whole **Unreleased** section becomes that release's "What's new", word for word. Then it's renamed to the version and date, and a new empty **Unreleased** section starts above it. Nothing is dropped or summarised away.

Format: one line per change, starting with who sees it.
- **Players** = something you can see or do in the game.
- **Under the hood** = systems, tools and docs.

Each line ends with its PR number.

## Unreleased

### Players
- A top bar shows the day, time, shop phase and cash, with pause and speed buttons, floating cash changes, and buttons to open the shop or start the next day. (#33)
- The camera's pan area is centred on the shop with a 2 m margin, so it can't drift into empty space. (#36)
- The starter shop now appears in 3D with warm furniture placeholders and two staff walking a temporary demonstration route. (#34)
- The game opens on a warm wooden test floor with a 0.5 m build grid (press **G** to toggle). The isometric camera pans with WASD, screen edges or middle-mouse drag, zooms with the wheel, and rotates in 90° steps with Q and E. (#22)
- Day clock and speed controls: each day runs morning → open → last orders → closed. **Space** pauses or resumes, and **1**, **2** and **3** set 1×, 2× and 4× speed. (#15)
- An evening report screen (not yet shown during play): profit, income and costs by category, dishes sold with the best seller marked, guests served versus lost, why guests left, and review quotes. (#25)

### Content
- Starter content as data: 7 ingredients, 3 recipes (burger, grilled cheese, tomato soup) and 8 items (door, two-seat table, chair, fridge, prep counter, stove, pass counter, potted plant). (#23)
- The Tier 1 "hole-in-the-wall" shop layout: a kitchen along the back, the pass in the dividing wall, three two-seat tables and the street door. (#26)

### Under the hood
- Guests find reachable seats, queue, order through servers, eat and pay. Bounded waits recover blocked routes, and closing clears every visit with a reason for the daily report. (#35)
- Shop layouts are data files, and `ShopBuilder` turns one into a running simulation. (#26)
- Staff task system with self-healing: staff claim jobs, walk to stations and wait their turn. A job that runs too long is handed back, a blocked route is re-planned, and a deleted target cancels its job. Staff buried under new furniture walk out, and two workers can no longer deadlock over stations. A chaos stress test proves this on every change. (#24)
- Grid and pathfinding for the shop floor: 8-way movement without corner cutting, furniture placement with rotation, and seat and work-spot reservations. (#21)
- A deterministic simulation clock: fixed ticks, the speed never changes the tick length, and saves keep the day length. (#15)
- Typed content definitions with validation (unique ids, valid references, known stations). (#23)
- Saving and loading: versioned save slots, with old saves upgraded automatically. A backup copy means a crash while saving can't destroy your save: loading falls back to the last good copy. The clock and random seeds are saved, so a loaded day continues exactly. (#30)
- Money and stock: every cash change is recorded with a reason (sales, tips, ingredients, wages, rent…) for the daily report. Ingredients are tracked in dated batches, used oldest first, and expire after their shelf life. You can't spend money you don't have yet (loans come later). (#31)
- Release notes process: every PR must add a line here (checked by CI), and a published build's "What's new" is this whole section. (#32)
- Automatic checks on every pull request and on `main`. (#16)
- Godot 4.7.2 project skeleton, a built-in test runner, and a strict checks script (untyped code, broken references and leaks fail the build). (#5)
- The game plan: TasteMaker audit, design v0.2, tech plan, roadmap, decisions D1–D14, AI worker rules and the issue template. (#1, #5, #13, #14)
