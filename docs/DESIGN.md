# Fool's Kitchen: Game Design

Status: draft v0.1 (2026-10-23). Owner: Jared. "TBD" items need a decision before the phase that uses them.

## 1. Pitch

A low-poly 3D restaurant tycoon game in which you are one guy running a restaurant. Staff and customers run on their own, like the Sims. You design the space, set the menu, hire, and buy your way up from a tiny place to several properties. Short optional mini-games break up the management and give bonuses.

- **Inspiration:** TasteMaker (Steam app 1289340), for ideas only. Nothing is copied: no assets, names or UI.
- **Audience:** family and friends, hobby scope. Single player, offline.
- **No story.** Just the progression.

## 2. Pillars

1. **Watching it run is the fun.** The simulation must be readable at a glance: you can see who is waiting, what is burning, and why a customer left.
2. **Every unlock changes how you play.** A new tier opens a new decision, not just bigger numbers.
3. **Your place, your style.** Building and themes are as important as profit.
4. **Mini-games are optional seasoning.** Skipping one never blocks progress. Playing one gives a bonus.

## 3. Core loop

```
Plan (menu, prices, staff, layout)
   -> Service day (auto-sim; player watches, nudges, optional mini-games)
      -> Results (money, ratings, reviews, XP)
         -> Spend (food stock, furniture, decor, upgrades, property)
            -> Plan ...
```

- **Session length:** one service day takes about 5 to 8 minutes real time at 1x speed. Speeds: pause, 1x, 2x, 4x.
- **Meta loop:** reputation and level unlock recipes, furniture, themes and property tiers.

## 4. Systems

### 4.1 Simulation (auto mode)
- **Customers:** arrive based on reputation, time of day, theme and price level. They queue, are seated, order, wait, eat, pay, review and leave. Patience drops while they wait. They leave if it runs out.
- **Staff roles:** chef, server, host, cleaner, and later dishwasher and manager. Each has skill, speed, wage and mood. They pick tasks from a shared task board (see TECH.md).
- **The owner (you):** an avatar you click-to-assign to a station to cover a gap (D4). He uses the same task system as staff. Mini-games are launched from his station.
- **Kitchen flow:** order ticket, then prep, cook and plate stations, then pass, then table. Stations have capacity and a quality modifier.
- **Cleanliness:** dirty tables and floors lower satisfaction. Cleaners or the owner fix it.

### 4.2 Menu and food
- **Recipe:** ingredients, station steps, cook time, base quality, base price, unlock level.
- **Ingredients:** bought in stock, with a shelf life of N days. Running out removes the dish for the day.
- **Pricing:** the player sets a price per dish. Satisfaction compares price with quality and the theme's expectations.
- **Recipe discovery** (later): combine ingredients in a mini-game to unlock variants.

### 4.3 Build mode
- **Grid-based placement:** walls, floors, doors, windows, tables, chairs, kitchen stations, decor.
- Every item has a footprint, cost, theme tags and a "charm" value.
- **Validation:** paths must connect door, tables, kitchen and storage. Show a warning instead of blocking.

### 4.4 Themes
- **Theme score:** the share of placed items carrying a theme's tags. Above a threshold the restaurant counts as that theme (for example Diner, Italian, Sushi, Fine Dining).
- **Effects:** the theme changes which customer types come, how much price they accept, and gives a bonus to on-theme dishes.

### 4.5 Economy and progression
- **Income:** meals and tips. **Costs:** ingredients, wages, rent or mortgage, utilities, upgrades.
- **Reputation:** 0 to 5 stars from a rolling average of reviews. Drives customer count.
- **Owner level (XP):** unlocks recipes, items and property tiers.
- **Property ladder** (draft):

| Tier | Property | Unlock | New decision it adds |
|---|---|---|---|
| 1 | Food cart or stall | start | menu and price basics |
| 2 | Small diner (rented) | level 3 | seating and first hire |
| 3 | Bistro (buy or rent) | level 6 | themes and kitchen layout |
| 4 | Restaurant with bar | level 10 | drinks and the night shift |
| 5 | Fine dining | level 15 | critics and plating quality |
| 6+ | Multiple locations | level 20 | managers who run them while you're away |

- **Owning vs renting:** buying costs more up front, removes rent, and allows structural upgrades.
- **Multiple properties:** a location you aren't at runs as a simplified background sim. Only the active one is fully simulated.

### 4.6 Mini-games (start with 3)
| Mini-game | Trigger | Reward | If skipped |
|---|---|---|---|
| Chop rhythm | owner at the prep station | faster prep and a quality bonus | normal speed |
| Plating | a "VIP order" event | big tip and reputation | normal plating |
| Supplier haggle | the morning buying screen | stock discount | list price |

Later candidates: the food critic visit, a rush-hour "expedite" game, a cooking contest event, recipe discovery.

### 4.7 Events (later)
Rush hour, health inspector, critic, broken equipment, a viral review.

## 5. Out of scope (for now)
Multiplayer, a story or campaign, character creation beyond basic choices, mod support, consoles, and AI running inside the game (no API calls at runtime).

## 6. Decisions
| # | Question | Decision | Date |
|---|---|---|---|
| D1 | Game name | "Fool's Kitchen" (working title, fine for now) | 2026-10-23 |
| D2 | How the day ends | A timer, then last orders: no new customers, and those already seated finish | 2026-10-23 |
| D3 | Fail state | No game over. Going broke triggers an automatic bank loan (rule below) | 2026-10-23 |
| D4 | Owner control | Click-to-assign: pick a station, the owner walks there and works it. Mini-games launch from his station. | 2026-10-23 |
| D5 | Engine | Godot 4, Compatibility renderer (see TECH.md section 1) | 2026-10-23 |

**Loan rule (draft, tune in Phase 3):** if cash ends a day below 0, the bank covers it with a loan at interest. Repayments come out of daily income. While a loan is open, you can't buy property or expensive upgrades. There is no game over.

## 7. Open questions
None right now.
