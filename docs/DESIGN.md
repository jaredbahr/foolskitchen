# Fool's Kitchen: Game Design

Status: v0.2 (2026-10-23), revised after the [TasteMaker audit](research/TASTEMAKER_AUDIT.md). Game director: Claude. Owner: Jared. "TBD" items need a decision before the phase that uses them.

## 1. Pitch

A low-poly 3D restaurant tycoon game. You're one guy who starts with a hole-in-the-wall shop and builds it into a restaurant chain. Staff and customers run on their own, like the Sims. You design the space, set the menu, hire, and buy your way up the property ladder. Short optional mini-games give bonuses.

- **Inspiration:** TasteMaker (Steam app 1289340), for ideas only. We keep what players love (relaxing, build your own place, it runs itself) and fix what they criticise (shallow content, stuck AI, no long progression). Nothing is copied: no assets, names or UI.
- **Who it's for:** a friend asked Jared for this game. Their complaint about TasteMaker is that eventually there's *nothing left to do*, so long-term goals are the top design priority. Also for Jared's family (his wife is a big Sims fan). **The audience is adults**, so humour can be dry and cheeky; it doesn't need to be kid-safe (D15). Hobby scope. Single player, offline.
- **Clean-room rule:** inspiration only. We work from public information and videos of TasteMaker being played, and we never copy, decompile or reverse-engineer it.
- **Name:** "Fool's Kitchen", possessive: it's your kitchen, and you're the fool cooking in it.
- **No story.** Just the progression.

## 2. Pillars

1. **Watching it run is the fun, and it's readable.** At a glance you can see who's waiting, what's cooking, and why a customer left. Click anyone to see what they're doing and why.
2. **Every tier changes how you play.** Each property tier adds a new decision, not just bigger numbers. (This fixes TasteMaker's top complaint.)
3. **It never breaks.** Agents never get stuck for long. Edits re-check paths. A broken sim is a bug, never the player's fault.
4. **Your place, your style (Sims-style building).** Decorating counts as much as profit: colour palettes, wallpaper, lighting, chandeliers. This is Jared's favourite part, so the build tools get first-class effort.
5. **Mini-games are optional seasoning.** Skipping one never blocks progress. Playing one gives a bonus.

## 3. Core loop

```
Morning (closed): plan menu and prices, buy stock, hire, rebuild
   -> Open: the service day runs on its own; you watch, nudge, assign the owner, play mini-games
      -> Last orders, then close (D2)
         -> Evening report: profit and loss, reviews, XP, unlocks
            -> Morning ...
```

- **Day length:** a service day takes about 5 to 8 minutes real time at 1x. Speeds: pause, 1x, 2x, 4x. Morning and evening are paused menu phases.
- **Meta loop:** reputation and owner level unlock recipes, items, themes and property tiers. Career milestones mark the way.

## 4. Systems

### 4.1 People (auto mode)

**Customers**
- **Lifecycle:** arrive, queue, get seated, order, wait, eat, pay, review, leave. Patience drops while waiting, and they leave angry when it runs out.
- **Needs:** food quality, wait time, price fairness, cleanliness, decor, and restroom (from Tier 2).
- **Types** (they unlock with tiers and themes, and change who comes): Regular, Student (cheap, patient), Family (groups, kid-friendly menu), Foodie (quality-sensitive, tips well), Critic (Tier 5 event). Each type has preferences and a patience and budget profile.
- **Restroom need is family-friendly:** an unmet need means an unhappy guest who leaves early. There is no mess on the floor.

**Staff**
- **Roles:** Cook, Server, Cleaner (Tier 1 to 2). Then Host, Dishwasher and Bartender (Tier 3 to 4), and Manager (Tier 6, runs other locations).
- **Stats:** skill per role (cooking, service, cleaning) from 1 to 5, speed, wage, and mood.
- **Traits** (one or two each, shown at hire): for example Fast, Clumsy, Charming, Tidy, Lazy.
- **Growth:** staff earn XP in the role they work and level up their skill. Better staff ask for raises.
- **Priorities:** a per-staff priority matrix (like the Sims or RimWorld): each role's tasks set to high, normal, low or off.
- **"Why" readout:** click anyone to see their current task, its target, the time on task, and their top need.

**Owner (you)**
- Click-to-assign (D4): pick a station or role, he walks there and works it, using the same task system as staff. Mini-games launch from his station.

**Pets (Tier 2 unlock)**
- **Restaurant cat:** removes pests, gives a small charm bonus, and guests can pet it. Purely charming, no upkeep beyond food.

### 4.2 Kitchen, menu and food
- **Order chain:** a server takes the order and a ticket goes on the board. A cook fetches ingredients from storage, preps (cutting board), and cooks (stove, fryer or oven). The plate goes to the pass, a server delivers it, the guest eats, and the table needs bussing before it can be reused.
- **Plate cycle (Phase 2):** a limited plate stock. Dirty plates go to the sink or dishwasher, and running out of clean plates stalls the kitchen. TasteMaker players liked this as a puzzle but hated it when it broke.
- **Recipe:** ingredients, steps (prep station and time, cook station and time), base quality, standard price, unlock tier and level, and theme tags.
- **Quality** = recipe base, then cook skill, then equipment tier, then ingredient freshness. Each factor is shown in the dish tooltip so you can see why quality is what it is.
- **Pricing:** the player sets a price per dish, shown against the "standard" price. Guests weigh price against quality and their type's budget.
- **Stock:** ingredients have shelf life. There's a stock panel, a low-stock alert, and optional automatic reordering at a small premium.
- **Carry capacity:** one plate by default. Trays (an upgrade) allow 2, then 4. This fixes TasteMaker's "one plate per trip" tedium.
- **Recipe discovery (later):** combine ingredients in a mini-game to unlock variants.

### 4.3 Build mode
- **Grid:** 0.5 m. Walls, floors, doors, windows, tables, chairs, stations, storage, decor.
- **Footprints show working tiles** (where a worker stands), so layouts are readable before you place them.
- **Live path check:** unreachable tables or stations are highlighted as you build. It warns but doesn't block.
- **Blueprints:** save a group of items (for example a 4-seat table cluster or a fry station) and stamp it again. This answers TasteMaker's "space management" pain.
- **When you can edit:** walls, rooms and stations can only be changed while closed (morning or evening). Decor and furniture can move while open, and every edit triggers a path re-check and agent re-plan.
- **Land:** buy adjacent plots to expand. A second floor is a Tier 4 upgrade.

### 4.4 Decor and themes
- **Colour everywhere:** walls, floors and most furniture have paint and material slots, chosen from curated palette swatches (Sims-style). Recolouring is free, so it encourages experimenting.
- **Lighting as decor:** lamps, sconces and chandeliers (Tier 3+) add ambience and change the room's light.
- **Ambience per seat:** decor within a radius of each seat. Each item type has diminishing returns (the 1st candle counts fully, the 5th barely counts), and **variety earns a bonus**. This stops TasteMaker's candle-stacking exploit.
- **Negative items:** a mop or bin next to a table subtracts ambience.
- **Theme score:** the share of placed items tagged with a theme. Above the threshold, the restaurant counts as that theme (Diner, Italian, Sushi, Fine Dining, and more later).
- **Theme effects:** which customer types come, how much price they accept, and a bonus for on-theme dishes.

### 4.5 Economy and progression
- **Income:** meals and tips. **Costs:** ingredients, wages, rent or mortgage, utilities, upgrades, and loan interest.
- **Evening report:** a profit-and-loss table, best and worst dishes, review quotes, the reasons customers left (with counts), and trend graphs over 7 and 30 days.
- **Reputation:** 0 to 5 stars from a rolling average of the last N reviews. Drives arrival rate and customer types.
- **Owner level (XP):** from profit, happy guests and milestones. Unlocks recipes, items and tiers.
- **Career milestones:** goals that change how you play (for example "serve 50 guests in a day", "reach 3 stars", "run a profitable week with a Foodie theme"). These replace TasteMaker's samey scenarios.
- **Loan rule (D3):** if cash ends the day below 0, the bank covers it with a loan at interest, repaid from daily income. While a loan is open, property and big upgrades are locked. There is no game over.

**Property ladder**

| Tier | Property | Unlock | The new decision it adds |
|---|---|---|---|
| 1 | Hole-in-the-wall (rented, tiny) | start | menu and price basics, your first hire |
| 2 | Corner diner (rented) | level 3 | seating layout, restroom, cleaner, the cat |
| 3 | Bistro (rent or buy) | level 6 | themes, plate cycle, staff specialisation |
| 4 | Restaurant and piano bar (buy) | level 10 | drinks, evening service with live piano, a second floor |
| 5 | Fine dining (buy) | level 15 | critics, premium ingredients, chandeliers and a dress code |
| 6 | The chain (several sites) | level 20 | managers run other sites in a simplified background sim |

- **Owning vs renting:** buying costs more up front, removes rent, and allows structural upgrades and a second floor.
- **Moving up:** you can keep an old property or sell it.
- **Second location (the friend's request):** unlocks at Tier 3. You can keep your previous shop running as a second site. Switch between sites at any time. The one you're not at runs in the simplified background sim, and both feed the same bank account. Tier 6 grows this into a chain with managers.
- **No running out of things to do:** the late game has no end state. A chain to grow, rotating weekly challenges, a collection of every recipe, item and theme, and sandbox mode.

### 4.6 Mini-games (start with 3)
| Mini-game | Trigger | Reward | If skipped |
|---|---|---|---|
| Chop rhythm | owner assigned to prep | faster prep and a quality bonus | normal speed |
| Plating | a "VIP order" event (Tier 3+) | big tip and reputation | normal plating |
| Supplier haggle | the morning buying screen | stock discount | list price |

Later candidates: critic visit (Tier 5), rush-hour expedite, cooking contest, recipe discovery.

### 4.7 Events (Phase 5)
Rush hour, health inspector, critic, broken equipment, a viral review, a power cut.

## 5. Out of scope (for now)
Multiplayer, a story or campaign, scenario mode (career milestones replace it), character creation beyond basic choices, mod support, consoles, AI running inside the game (no API calls at runtime), and toilet humour beyond the restroom need.

## 6. Decisions
| # | Question | Decision | Date |
|---|---|---|---|
| D1 | Game name | "Fool's Kitchen" (working title, fine for now) | 2026-10-23 |
| D2 | How the day ends | A timer, then last orders: no new customers, and those already seated finish | 2026-10-23 |
| D3 | Fail state | No game over. Going broke triggers an automatic bank loan (4.5) | 2026-10-23 |
| D4 | Owner control | Click-to-assign: pick a station, the owner walks there and works it | 2026-10-23 |
| D5 | Engine | Godot 4.7.2, Compatibility renderer (TECH.md section 1) | 2026-10-23 |
| D12 | First person | Management and building stay top-down. **V** walks the restaurant in first person as the owner. Cooking mini-games play in first person at the station. The sim keeps running throughout. | 2026-10-23 |
| D13 | Art mood | Warm and cosy (wood, warm light). **Consistency beats detail:** one palette, one lighting setup, one level of model detail (TECH section 3) | 2026-10-23 |
| D14 | Owner look | One fixed character for now | 2026-10-23 |
| D15 | Audience | Adults. Humour can be cheeky; not designed for kids | 2026-10-24 |
| D16 | Hiring payoff | An extra hire alone doesn't pay at Tier 1. It pays off once you expand (more seats, trays): hiring and building go together | 2026-10-24 |
| D17 | Loan interest | 4 to 6% a day on the open principal (start at 5%) | 2026-10-24 |
| D18 | First public build | Held until more visual work lands (better props, people, food and lighting) | 2026-10-24 |
| D19 | Visual consistency | One style everywhere: people, furniture, equipment, food, decor and UI come from one approved source or style lock. No flip-flopping styles | 2026-10-24 |
| D20 | Art set | All Kenney (CC0): Furniture Kit, Food Kit, Mini Characters, Game Icons. Rules in `docs/ART_STYLE.md` | 2026-10-24 |
| D21 | Focus | Building, designing and themes plus the self-running management sim come first and get polished. First person (D12) and mini-games are deferred; if added, mini-games are short moments for emergencies or clean-ups. Themes are designed by the player, never auto-built | 2026-10-24 |
| D22 | Player-led look | The player decides how the restaurant looks. We offer many assets and variants (colours, materials, styles of the same piece) so there are several ways to design any space; no single "correct" look. Reviews judge Kenney-style consistency (D19), not taste | 2026-10-25 |
| D23 | Restaurant designer | The game is a restaurant designer with a management sim underneath, in a Sims-like design language (Build and Buy modes, browsable catalogue, forgiving tools). The player builds the space (walls, windows, interior rooms, restrooms, floor, paint, decor, later entertainment) and chooses the concept (diner, coffee shop, bar or a mix) through what they build and serve, never a picker. The menu and theming are part of the design fun | 2026-10-27 |
| D11 | Platform | Both: a web build (play from a link) and a Windows download, from the same Godot project | 2026-10-23 |
| D6 | Starting property | A rented hole-in-the-wall shop with 2 to 3 tables (not an outdoor food cart: indoor is simpler to simulate and to build) | 2026-10-23 |
| D7 | Mode structure | Career mode only at first. A sandbox comes in Phase 5. No scenario mode. | 2026-10-23 |
| D8 | Restroom need | Kept, family-friendly (an unmet need means the guest leaves unhappy, no mess) | 2026-10-23 |
| D9 | Unit tests | An in-repo headless test runner, not GUT (no third-party download, nothing to version-match) | 2026-10-23 |
| D10 | Agent movement | Grid pathfinding owned by the sim (`AStarGrid2D`), not the navmesh (TECH 2.3) | 2026-10-23 |

## 7. Open questions
None right now.
