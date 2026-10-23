# TasteMaker Audit

Date: 2026-10-23. Purpose: learn what TasteMaker gets right and wrong, and decide what Fool's Kitchen keeps, fixes and adds.

**Method and limits:** this audit is based on the Steam store page, a player-review theme summary (Vaporlens), a Steam community strategy guide, and forum and early-access reviews. It is not from playing the game. Review themes are weighted by how often players mention them, not by measured play. Several complaints date from early access (2021), and the game reached 1.0 in April 2023, so some may be fixed. Anything not confirmed by a source is marked *(unverified)*.

## 1. Fact sheet

| | |
|---|---|
| Developer and publisher | Jelle Booij (solo developer) |
| Early access | 18 Feb 2021 |
| Full release | 21 Apr 2023 |
| Price | $11.99 USD |
| Steam reviews | Very Positive, about 83% of about 1,250 reviews |
| Modes | Tutorial, 6 scenarios (3 challenges each), creative sandbox |
| View | 3D, isometric, stylised, low system requirements |
| Players' tags | Management, Sandbox, Cooking, Building, Relaxing, Time Management |

## 2. Systems as they work in TasteMaker

| System | How it works |
|---|---|
| **Land and building** | Start on a small plot and buy adjacent land as cash allows. Walls, floors, stairs, second floors. A staircase can serve as an entrance. |
| **Kitchen equipment** | Stoves, ovens, fryers, mixers, cutting boards, dishwashers, fridges and freezers, shelves, and plate and pan cabinets. Bigger versions hold more per tile. Most equipment can be used from diagonal tiles. |
| **Ingredients** | Stored on shelves, in fridges and in freezers (meat). Players ask for better visibility of stock. |
| **Menu** | Pick dishes (fries, nuggets, chicken, burgers, bread, cakes, avocado dishes) and set prices. Recommended practice is to price near the "standard" price. |
| **Staff** | Hire with individual strengths (a good cook can be a bad server). Set task priorities. Fast but clumsy workers are recommended as cleaners. Players re-roll the hiring pool until they get good candidates. |
| **Guest rating** | Built from wait time, hygiene, bladder (toilets and sinks), price, food quality (upgraded equipment), decor near the guest, and menu variety. The rating drives customer flow. |
| **Decor** | Scored only from items near guests. Some items (brooms) subtract. Cheap candles are the best value. Windows and wallpapers do nothing. Players exploit the scoring. |
| **Hygiene** | Rats upset guests. Toilets matter: guests relieve themselves on the floor if there are none, and the game doesn't hide it. |
| **Cats** | Can be hired *(their exact role is unverified)*. Very popular with players. |
| **Failure** | No strict failure conditions. Players see this as a positive. |
| **Scenarios** | Six goal-based maps, for example "profit X with fries and nuggets only" or "reach income Y". |

## 3. What players like (keep)

1. **Relaxing, low stress, no harsh failure.** This matches our D3: no game over.
2. **Building and expanding** your own place, including new floors.
3. **The restaurant runs itself once it's set up.** Watching it is satisfying, which matches our "auto mode".
4. **Clean UI and time controls.**
5. **Charming art and low system requirements.** This matches our Compatibility renderer and low-poly style.
6. **Cats.** A small charm feature with outsized goodwill.
7. **Sandbox mode** for stress-free building.

## 4. What players dislike (fix)

Weights are the share of mention strength in the review summary. Higher means more common.

| # | Complaint | Weight | Root cause (our reading) |
|---|---|---|---|
| C1 | **Shallow, too little content, gets boring fast** | 0.96 | No long progression arc: scenarios plus a sandbox, and no career ladder. |
| C2 | **Bugs: stuck equipment, staff stop working, dishes break** | 0.54 | Fragile agent and task logic with no recovery. |
| C3 | **Inefficient staff AI**: ignores dirty dishes, gets overwhelmed, few controls | 0.29 | Weak task prioritisation and nothing to show *why* staff act as they do. |
| C4 | **Not worth full price** (or "development abandoned") | 0.41 | A symptom of C1. |
| C5 | **Tedious micromanagement and waiting**: one plate per trip, little control over quality | 0.21 | Throughput limits with no upgrade path. |
| C6 | **Scenarios repetitive, too similar to the sandbox** | 0.13 | The goals don't change how you play. |
| C7 | **Space management** is the hardest part (the community guide's top tip) | n/a | Tight plots, chairs blocking paths, few layout tools. |
| C8 | **Decor exploits**: candles and pictures stacked for score | 0.04 | Linear scoring with no variety rule. |
| C9 | **Redesigning during service breaks things** (stuck customers, blocked orders) | n/a | Live edits with no re-validation. |

## 5. What players ask for (add)

| Request | Weight | Our answer |
|---|---|---|
| More content and features | 0.69 | The property ladder, recipe unlocks, themes, and content defined in data files so it's cheap to add (DESIGN 4.5, TECH 2.2). |
| Better staff: specialisations, levelling, smarter dish pickup | 0.65 | Staff XP and traits, a priority matrix, and a "why" readout (DESIGN 4.1). |
| More building and decor options | 0.64 | Themes, a variety-based decor score, saved layout blueprints. |
| More customer variety | 0.59 | Customer types tied to themes and tiers (DESIGN 4.1). |
| Day and night cycle, the ability to close | 0.56 | Opening hours, last orders (D2), and lighting that changes over the day. |
| Better financial statistics | 0.12 | A daily profit-and-loss report and trend graphs. |
| Stock visibility and control | 0.06 | A stock panel, low-stock alerts, and automatic reordering. |

## 6. Fool's Kitchen response

| TasteMaker gap | Fool's Kitchen design answer | Where |
|---|---|---|
| C1 shallow / no arc | **A career ladder**: food cart, then diner, bistro, bar, fine dining, then a chain. Each tier adds a *new decision*, not just bigger numbers. | DESIGN 4.5 |
| C2 stuck AI | **Self-healing agents**: every task has a timeout; a stuck agent drops the task, re-paths, and the task goes back on the board. Automated tests check that no agent stays stuck. | TECH 2.3, ROADMAP P1 |
| C3 opaque AI | **A "why" readout**: click any staff member or customer to see their current task and need. A task board that shows priorities. | DESIGN 4.1 |
| C5 one plate per trip | **Trays as an upgrade** (carry 2, then 4). Better equipment changes quality in ways you can see. | DESIGN 4.2 |
| C6 samey scenarios | Instead of scenarios, **career milestones and optional weekly challenges** that tie into progression. | DESIGN 4.5 |
| C7 space | **Layout blueprints** (save and stamp a table or kitchen cluster), clear footprints that show where workers stand, and path checks shown live. | DESIGN 4.3 |
| C8 decor exploits | **Decor uses diminishing returns per item type plus a variety bonus**, and is scored within a radius of each seat. | DESIGN 4.4 |
| C9 live-edit breakage | **Big structural edits only while closed.** Small decor edits are allowed while open. Every edit re-checks paths, and agents re-plan. | DESIGN 4.3 |
| Toilet humour | **Kept family-friendly**: restrooms are a need, and failing it means an unhappy guest who leaves. No mess on the floor. | DESIGN 4.1 |
| Cats loved | **A restaurant cat** as an early unlock. It catches pests and gives a small charm bonus. | DESIGN 4.1 |

## 7. Where we deliberately differ
- **No scenario mode at launch.** The career mode *is* the game. A sandbox comes later (Phase 5).
- **Mini-games.** TasteMaker has none. Ours are optional and add a bonus (DESIGN 4.6).
- **The owner avatar** (click-to-assign, D4). TasteMaker has no player character.
- **Multiple locations.** TasteMaker has one restaurant per save.

## Sources
- [TasteMaker on Steam](https://store.steampowered.com/app/1289340/TasteMaker/)
- [Vaporlens review theme summary](https://vaporlens.app/app/1289340/taste_maker.md)
- [Steam community guide: General Tips and Achievements](https://steamcommunity.com/sharedfiles/filedetails/?id=3296695712)
- [Curated Critiques early-access review (2021)](https://curatedcritiques.wales/2021/02/21/tastemaker-early-access-review/)
- [Steambase review aggregate](https://steambase.io/games/tastemaker/steam-charts)
- [GOG listing](https://www.gog.com/en/game/tastemaker_restaurant_simulator)
