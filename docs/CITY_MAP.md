# Fool's Kitchen: The City Map (design proposal)

Status: **decided** (Jared's taste calls, 2026-11-19; see "Decided" below). Builds on D24, D28, D31, D33, D39 and D40.
Code names below are the ones the build plan adds. The model, the chain summary and a plain list screen are phase 2 (#639, #645 and the city screen PR).

## For Jared: the short version

**The proposal in five lines**
1. A new **City** screen: an illustrated map of the town. Each neighbourhood shows your shops, the lots for sale and the areas you can't get into yet.
2. Tap one of your shops to see how it's doing: yesterday's takings, its manager, stars, Golden Ladles, team mood and anything that needs you. In the morning you can **go and work there** from the map. Switching still happens only in the morning.
3. Away sites stay a fixed, predictable sum (D24). The map can show tonight's result ahead of time ("Expected tonight: about +$84"), so managing feels like a plan you can see, not a gamble.
4. **Chain goals** run alongside the shops: own shops in more neighbourhoods, keep them managed, and collect **Golden Ladles across the city**. A Golden Ladle in every neighbourhood opens free play, with a little awards night.
5. Today's Property screen becomes the map's **estate agent**: tap a For Sale sign and the same lot card opens. The plain list stays for anyone who prefers it.

**Decided** (Jared, 2026-11-19; full list in "Decided" below): a paper map on the desk; plain, cosy names; both seaside lots in The Seafront; roadworks for areas waiting on a tier and "coming soon" boards for areas with no lot yet; a van ride plus a joke commute card; keep the morning card and add "See the map"; a Golden Ladle in every neighbourhood, then an awards night; the player names the chain.

**The questions as they were put** (details and options in "Taste calls" below)
- **T1. The map's look:** a paper map on the desk, a parody phone app, or a tiny 3D model town.
- **T2. Neighbourhood names:** plain and cosy, punny, or named after the food.
- **T3. Which neighbourhoods, and where each lot goes.** Both seaside lots go in one Seafront?
- **T4. How locked areas look:** fog, roadworks, or "coming soon" boards.
- **T5. Travelling:** a straight switch, a short van ride along the map, or a morning commute card.
- **T6. The morning site card:** keep it, replace it with the map, or let the card open the map.
- **T7. The end goal for free play:** a Ladle total, a Ladle in every neighbourhood, or an awards night.
- **T8. A chain name:** let the player name the chain ("Fool's Kitchen Group") or not.

The model, the engine work and a plain list version of the screen need none of these calls. They are phase 2 in the build plan.

---

## Decided (Jared, 2026-11-19)

Relayed by the director on 2026-11-19. Each line is the option picked from section 11.

| # | Call | Picked |
|---|---|---|
| T1 | The map's look | **A. A paper map on the owner's desk**: a hand-drawn, illustrated town with pins, coffee rings and doodles. |
| T2 | Neighbourhood names | **A. Plain and cosy**: Old Town, Millbrook, The Seafront, Skyline, Pinewood (as shipped in `data/city/city_map.tres`). |
| T3 | Neighbourhoods and lots | **A. As tabled**: five neighbourhoods, both seaside lots in The Seafront. The Woodland Cabin (`woodland_cabin`, coming from the director) goes in Pinewood, which then stops being "coming soon". |
| T4 | Locked areas | **The recommendation**: roadworks (cones, a "Road closed" sign, a digger) for an area waiting on a tier; "coming soon" hoardings with a painted preview for an area with no lot yet. |
| T5 | Travelling | **B + C**: a skippable two-second van ride along the map road, then a jokey commute line. |
| T6 | The morning card | **A**: keep the morning site card and add "See the map". |
| T7 | The free-play goal | **B + C**: a Golden Ladle in every neighbourhood (that has a lot), then a little awards night opens free play. |
| T8 | Chain name | **The recommendation, A**: the player names the chain; the default is "Fool's Kitchen Group". |

**Art is the director's** (the paper map illustration, pins, badges, the van sprite). The screen is built so the art drops in: a background texture slot, a pin scene and a van path per road.

**The D-row, as added to `docs/DESIGN.md` (D41):**

> | D41 | The city map | The chain's home is a **City** screen, a hand-drawn paper map of the town on the owner's desk (pins, coffee rings, doodles), opened from the morning Menu from Tier 3 and from the morning site card's "See the map" (the card stays). Neighbourhoods, with plain cosy names: Old Town (home shop), Millbrook (Old Mill Street), The Seafront (Beachfront Boardwalk and Seaside Cliff), Skyline (Skyline Rooftop; later the downtown club) and Pinewood (the Woodland Cabin). An area waiting on a tier shows roadworks; one with no lot yet shows "coming soon" hoardings. Each shop's pin shows its state and opens its card (yesterday's money, manager, stars, Golden Ladles, team mood, tonight's away result, alerts); in the morning "Work here today" switches site with a skippable two-second van ride along the map road and a jokey commute line. Lots for sale open the property market's card. Chain goals lead to **a Golden Ladle in every neighbourhood** that has a lot, then a little awards night opens free play; the player names the chain (default "Fool's Kitchen Group"). Ladles stay in-person only: the critic visits the active site (docs/CITY_MAP.md) | 2026-11-19 |

## 1. Why, and what it is for

D31: "The long arc grows a chain across the city's neighbourhoods and earns Golden Ladles, then free play."
Today the chain has the pieces but no home:
- Buying is a list of lot cards in Menu > Property (D28).
- Switching is the morning site card (#464).
- Away sites report one line each in the evening report (#408).
- Golden Ladles hide in Goals as "Golden Ladles: 1 of 3", for the active site only.

Nowhere does the player see **the chain as a whole**, where their shops are, or what to aim for next. The City Map is that place: one screen that answers "how is my little empire doing, and where do I go next?"

The design rules it keeps:
- **Pillar 1 still wins.** The map is a short, pleasant stop between days, not a second game. Designing and watching a shop stays the heart of play, so the map always leads back into a shop.
- **Cosy, light parody, never mean (D31).** Jokey names, a parody app or guidebook, and silly little touches on the pins.
- **Deterministic away sites (D24 as amended).** Nothing on the map rolls dice.
- **Mornings only for switching (#408).** The map can be *looked at* any time outside Build. *Going* somewhere stays a morning choice, because the sim swaps the whole site then.

## 2. The map screen

### 2.1 What is on it

```
 ┌──────────────────────────────────────────────────────────────────────────┐
 │  The City                       Chain: 3 shops · ★4.3 · 🥄 2   [List] [×]│
 │ ┌──────────────────────────────────────────────┐ ┌──────────────────────┐ │
 │ │   ~~ fog ~~      PINEWOOD (locked, Tier 5)   │ │ Old Mill Street      │ │
 │ │  ~~~~~~~~~~~        🔒 "Road closed"          │ │ Millbrook · Managed  │ │
 │ │                                              │ │ Yesterday: +$84      │ │
 │ │  MILLBROOK          OLD TOWN                 │ │ (after the manager)  │ │
 │ │   🏠 Old Mill  ───── 🏠 Home  ★ YOU ARE HERE  │ │ Manager: Ana ★★★     │ │
 │ │   (managed, lit)        │                    │ │ Team mood: 🙂        │ │
 │ │                         │     SKYLINE        │ │ Tonight: about +$84  │ │
 │ │  THE SEAFRONT           │      🪧 Rooftop     │ │ ⚠ A booking there    │ │
 │ │   🪧 Boardwalk  🏠 Cliff │      FOR SALE $30k │ │   lapses tonight     │ │
 │ │   (for sale)  (closed)  │                    │ │ [ Work here today ]  │ │
 │ │  ≈≈≈≈≈≈≈ sea ≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈ │ │                      │ │
 │ └──────────────────────────────────────────────┘ └──────────────────────┘ │
 │  ⚠ 2 things need you: Cliff has no manager · Old Mill is ready to open    │
 └──────────────────────────────────────────────────────────────────────────┘
```

- **Neighbourhoods** are soft coloured patches, each with a hand-lettered name and a one-line blurb on hover ("Hedgerows, a mill stream and the best flour in town").
- **Your shops** are pins with a tiny picture of the building, using your awning colour. A small badge shows the state:
  - *Here today:* a "You are here" flag.
  - *Managed:* lights on and an Open sign.
  - *Closed:* shutter down, with a cobweb if it has been closed a while.
  - *Renovating:* scaffolding.
  - *Needs you:* a red speech bubble.
- **Lots for sale** are an estate agent's board with the price ("FOR SALE · $11,500"). Tap it to open the same lot card the Property screen shows, Buy button included.
- **Locked lots** are a board with a padlock and the real reason ("Needs Tier 4 and 4.3 stars"), worded by `PropertyText.lock_line` as today.
- **Locked areas** are neighbourhoods with no lot you can buy yet (all locked, or none written yet, like the coming woodland and downtown). How they look is T4. They always say what opens them.
- **Roads** link the neighbourhoods. They are only decoration, unless T5 picks the van ride.
- **The chain strip** along the top shows the number of shops, the chain's average stars and its Golden Ladles. It opens the chain goals (section 6).
- **The alerts bar** along the bottom says "2 things need you", and tapping an alert picks that shop.
- **[List]** toggles to a plain list: neighbourhood headings, then rows. This is phase 2's whole screen. It stays as an accessible option and a test hook.

### 2.2 Proposed neighbourhoods (placeholder names, T2 and T3)

| Neighbourhood (placeholder) | Lots | Frontage (D39) | Opens |
|---|---|---|---|
| **Old Town** | Home shop (`home`) | small-town street, cars | always |
| **Millbrook** | Old Mill Street (`town_fixer_upper`) | country lane | Tier 3 |
| **The Seafront** | Beachfront Boardwalk (`beachfront_boardwalk`), Seaside Cliff (`seaside_cliff`) | promenade; cliff path | Tier 3 |
| **Skyline** | Skyline Rooftop (`skyscraper_rooftop`); later the downtown club (D39) | city pavement, lift lobby | Tier 4 |
| **Pinewood** | Woodland Cabin (#665; #608 adds its foraging) | forest track | open from Tier 3 and 4.0 stars |

Notes:
- Each lot belongs to exactly one neighbourhood, and the home lot is always in one. The data check enforces both (section 8).
- A neighbourhood with two or more lots (the Seafront) is where future "rivals next door" (#173) and growth by taking over a neighbour (#597) fit naturally.
- "Opens" is the lowest lot gate in the area. It is not a new gate: lots keep their own `min_tier` and `min_reputation` (D28).

### 2.3 How it opens
- From the **Menu header**, a **City** button next to Property, from Tier 3, the tier the market appears (the same gate as `PropertyMarket.shown`).
- From the **morning site card**, a "See the map" link (T6).
- Keyboard: `M` (free today; to be checked against `ShortcutsText`).
- During service it opens read-only: the shops' cards show, and the Go button is disabled with "Mornings only". The clock does **not** pause. The map is small enough to glance at, so we don't need a new pause rule. Auto-pause (`src/ui/auto_pause.gd`) can be added later if playtests ask for it.

## 3. Travelling between sites

Engine rule (unchanged): `switch_site(target)` runs only in the morning, after that morning has run, with no Build, Paint, haggle or owner picker open (`can_switch_site`). The map calls exactly that, and its disabled button gives the same words as `site_switch_refusal` ("Close Build first", "From tomorrow", ...).

**T5: how it feels**
- **A. Straight switch (cheapest).** "Work here today", then a fade, then the arriving shop's morning, as the site card does now.
- **B. A little van ride (recommended).** A two-second animation: your owner's van putters along the map road to the pin, then the fade. It is purely cosmetic and skippable with a click. Cost: one 2D sprite and a path per road. It makes the city feel like one place.
- **C. A morning commute card.** A tiny jokey line while it loads ("You took the scenic route. A goose chased you past the mill."). Cheap, and a nice spot for parody. It combines with A or B.

**Built (#644).** `main.gd` `travel_to_site(target)` calls `switch_site` and, only if it succeeded, `_start_van_ride`, which drives `CityMap.van_path` from the leaving neighbourhood to the arriving one (`VanRide`, `van_ride_seconds` = 2.0; no ride in headless runs, for the same neighbourhood, or without map art). Any click, tap or key skips it. The commute line comes from `data/city/commute_lines.tres` (general lines) plus the arriving neighbourhood's `commute_line`, picked from the day and the destination alone, never the same line twice in a row. `switch_site`'s rules and the morning autosave are untouched.

**T6: the morning site card**
- **A. Keep the card, add "See the map" (recommended for now).** The card is fast and already tested. The map is for looking around.
- **B. The map replaces the card.** On a morning with 2+ shops the map opens instead. This is the most immersive, but slower for a player with two shops who only wants to tap "Stay here".
- **C. The card shows until the chain reaches 4 shops, then the map takes over.** The best of both. It needs a rule for the threshold.

## 4. What the chain view shows per site

Each shop's card on the map, and each row in the list, shows:

| Line | Where it comes from | Example |
|---|---|---|
| Name and neighbourhood | `SiteBook.site_name`, else `AwaySites.display_name`; `CityMap.neighbourhood_for_lot` | "Old Mill Street · Millbrook" |
| Status | active / managed / closed / renovating (`SiteBook`, `AwaySites.manager_skill`) | "Here today", "Managed", "Closed", "Renovating: 2 days" |
| Yesterday | `SiteMorning.takings` (gross, where you worked) or `away_earnings` (net, managed) | "Yesterday's takings: $412" / "Yesterday (after the manager): +$84" |
| Today so far (active site, during service) | the ledger for today, active site | "Today so far: $186" |
| Last 7 days | the ledger per site per day (`ChainStats.site_series`) | a small sparkline, and "7 days: +$1,240" |
| Stars | the site's `reviews` section, `ReputationBook.average()` | "★ 4.3" |
| Golden Ladles | the site's `critic` section (`FoodCritic.golden_ladles`, 0 to 3) | "🥄🥄" |
| Manager | the book row and that site's `staff` | "Manager: Ana (skill 3, keeps 85% of your average)" / "No manager" |
| Team mood | the mean `StaffGrowth.mood` of the site's floor staff, as a face | 🙂 / 😐 / 🙁 |
| Tonight (away sites) | `AwaySites.plan_close` run as a preview, which is exact because it is deterministic | "Tonight: about +$84" / "Tonight: rent and wages -$125" |
| Alerts | `ChainSummary` alerts (below) | "No manager: closed and still paying rent" |

**"Today's takings."** In the morning nothing has been taken yet, so the main figure is **yesterday's**. The active site shows today-so-far during service. Away sites earn at the active site's close (`_close_away_sites`), so during the day they show **Tonight** (the preview), and after the close they show yesterday's figure.

**Alerts** (one plain sentence each, worded in one place, `ChainText`, rule 11). They are deterministic and read from saved state:
- **No manager:** "Closed: no manager. Still paying rent." (D33)
- **The manager has no day to go on:** "Your manager needs a day you ran there first." (#465)
- **Renovation done:** "Renovation done: ready to open."
- **Can't open:** "Hire a cook and a server before it can open." (`StaffRoster.is_staffed`)
- **Losing money:** "Losing money: the last 7 days here averaged -$40." (the mean of the recorded history the manager earns from)
- **A booking lapses:** "A group booking there lapses tonight (deposit refunded)." (`AwaySites.lapse_booking` preview)
- **Low mood:** "The team there is unhappy." (mean mood of 1 or below)
- Later: low stock and spoilage (D33 aging), an expansion on offer, and a critic sighting at the active site.

The alerts are ordered by severity, then by site order, so the same morning always reads the same.

## 5. Managers and away sites on the map

- **A managed shop looks open:** lights on, the Open sign turned, and a tiny manager figure in the doorway with a clipboard. Its card says what the manager keeps of your average: "Ana keeps 85% of what you made here (your last 7 days)". This is D28's 70% to 100%, so the player can see why a better manager matters.
- **An unmanaged shop looks shut:** shutter down, and after 3+ closed days a cobweb and a pile of post. Its card says what it costs ("Closed: rent $70 and wages $55 a night") and offers a shortcut, "Send a manager…", which opens the Staff panel's Send to… list (#473). That only works in the morning, as today.
- **The preview is exact.** `AwaySites` has no RNG, so the "Tonight" line equals what the evening report will book, unless the player changes something before closing (a transfer, a switch). The card words it "about" to leave room for that.
- **Never more than you.** The card never shows a number higher than the in-person average. That is D24's rule made visible: you go back to a shop to grow it, and a manager keeps it ticking over.
- **The evening report** keeps its away lines (#408) and gains one summary line, "Your chain today: +$612 across 3 shops". `ChainStats` adds it up (phase 2, filed as a Codex issue).

## 6. Chain goals and the path to Golden Ladles

### 6.1 How Ladles work today
- A shop earns 0 to 3 Golden Ladles from a **good critic review** while its prestige score allows it (`Prestige.ladles`, `FoodCritic.award_golden_ladles`, D28). They are kept per site in its `critic` section.
- The critic only visits the **active** site, because the critic is part of the in-person sim.
- This is a good thing and we keep it: **you can't manage your way to Ladles.** Every Ladle means you went there, made it lovely and cooked well. The chain goal rewards visiting each shop, not only buying it.

### 6.2 The chain ladder (proposal)
A third goal track beside the career goals and the weekly challenge. It is shown on the map's chain strip and in Goals.
It never fails, each goal pays once (like goal chains, DESIGN "Paid goal chains"), and it only counts things that happened.

| # | Goal (placeholder wording) | Checks |
|---|---|---|
| 1 | **Two's Company:** open a second shop | site count ≥ 2 and it has served a day |
| 2 | **Delegator:** a manager runs a shop for a whole day | an away site was MANAGED at a close |
| 3 | **Neighbourly:** shops in 3 neighbourhoods | distinct neighbourhoods among owned lots |
| 4 | **First Ladle:** a Golden Ladle anywhere | the chain's Ladle total ≥ 1 |
| 5 | **Chain Reaction:** the chain takes $5,000 in a week | `ChainStats` 7-day total |
| 6 | **Full House:** every shop managed or worked for 7 days running | no CLOSED away plan for 7 closes |
| 7 | **Ladle Collector:** 5 Golden Ladles across the chain | chain Ladle total ≥ 5 |
| 8 | **The Whole Town:** a shop in every neighbourhood that has one to buy | coverage |
| 9 | **Golden City:** the free-play goal (T7) | see below |

All numbers are placeholders, to be tuned like `career_tiers.tres`. They would live in data (`data/balance/chain_goals.tres`, rule 3).

### 6.3 The end goal and free play (T7)
- **A. A Ladle total (recommended).** 9 Golden Ladles across the chain (three shops at three each, or spread wider). Clear, countable, and it grows with every shop.
- **B. A Ladle in every neighbourhood.** This pushes the player to make *every kind* of place good (a cliff café and a rooftop bar both earning a Ladle), which is very D39. It is harder to follow at a glance.
- **C. The Golden Ladle Awards night.** Once A or B is met, a one-off evening card: a parody awards show ("And the Ladle for Most Soup goes to…") with a toast from your staff. Then free play opens. It is pure flavour and combines with A or B.

Free play, either way: nothing locks, the chain ladder shows "Complete", the map gets a small golden statue in Old Town, and the site limit (already unlimited at Tier 6) stays as it is. Free play is mostly a feeling plus a celebration, not a new mode. Sandbox (Creative) already exists for the no-money version.

### 6.4 Parody touches (pick freely)
- The map's guidebook: *The Ladle Atlas* (a gentle nod to restaurant guidebooks), with a ladle-shaped north arrow.
- Pins get one-line "reviews" from locals: "Best pie this side of the mill pond. — a goose".
- The chain strip's name: the player names their chain (T8), default "Fool's Kitchen Group". "Group" is a fun corporate parody for a cosy game.

## 7. How this differs from today's Property screen

| | Property screen (today, D28) | City Map (proposed) |
|---|---|---|
| Purpose | shopping: which lot to buy next | the chain's home: where everything is, how it's doing, where to go |
| Shows | lots for sale (and owned ones, as "Owned") | your shops, lots for sale, locked lots, locked areas |
| Layout | a list of cards, cheapest first | a map of neighbourhoods, plus a list toggle |
| Owned shops | a disabled "Owned" button | live status, manager, money, mood, alerts, Go |
| Switching | none (the morning site card does it) | "Work here today" on each shop, mornings only |
| Opens from | the Menu header, Tier 3 | the Menu header, the morning card and `M`, from Tier 3 |
| After | stays as the lot card **inside** the map and as the list view, with no logic duplicated | |

The market's rules (`PropertyMarket`) and words (`PropertyText`) are reused untouched. The map is a new view on top of them.

## 8. What the code needs (whatever Jared picks)

None of this adds saved state, so old saves need no migration (section 10).

- **`CityMapDef` and `NeighbourhoodDef`** (`src/sim/sites/`, Resources, pure data). They are loaded from `data/city/city_map.tres` (rule 3).
  - `NeighbourhoodDef`: `id`, `display_name`, `blurb`, `lots: Array[StringName]`, `map_position: Vector2` (0 to 1 on the map), `coming_soon: String` (a locked area with no lots yet).
  - `CityMapDef.validate(lots)`: every lot in exactly one neighbourhood, `home` in exactly one, unique ids, positions in range, and names that fit. The data test checks the shipped file against the real lots, so a new lot without a neighbourhood fails CI.
  - Pure reads: `neighbourhood_for_lot(lot)`, `neighbourhoods()` in map order, and `state(neighbourhood, owned, tier, reputation, lots)` returning OWNED_HERE, FOR_SALE, LOCKED or COMING_SOON.
- **`ChainSummary`** (pure). It builds one `SiteSummary` per site from a SiteBook, the ledger and each site's per-site sections. The active site's come from a capture of its live sections, so one code path covers both. A summary holds status, yesterday's figure, stars, Ladles, the manager's name and skill, mood, the tonight preview and alerts (as enums, worded elsewhere).
- **`ChainStats`** (pure, the chain-wide API). Per-site and chain totals for takings and away earnings on a day, a 7-day series and total per site, the chain Ladle total, mean stars, and neighbourhood coverage. Chain goals and the evening report line read only this.
- **`ChainText`** (`src/ui`). Every line of the screen, rule 11.
- **`CityPanel`** (`src/ui`, phase 2 as a list). It is built from the shared theme like `PropertyPanel` and `SiteCard`. It emits `site_chosen(id)` and `lot_requested(id)`. The `main.gd` seam stays thin: `set_city_visible`, `_city_rows()` and a handler that calls the existing `switch_site`.

## 9. Build plan

**Phase C0: design (this doc).** A draft PR, so the director can put T1 to T8 to Jared.

**Phase C1: model and engine (no taste calls; this session).**
- C1a `CityMapDef`, `NeighbourhoodDef`, `data/city/city_map.tres` with the placeholder neighbourhoods, validation and tests. One PR.
- C1b `ChainSummary`, `ChainStats`, alert enums and tests. One PR.

**Phase C2: a plain functional screen (no taste calls; this session).**
- C2a `CityPanel` as a list: neighbourhood headings; your shops with status, yesterday, manager and alerts; lots for sale and locked lots with their reason; and Work here today, which calls `switch_site`. It opens from a Menu header **City** button. It has its own test and a review scene. One PR.

**Phase C3: filed as issues** (Codex where no taste call is needed).
- `codex` Evening report: one "Your chain today" line from `ChainStats`.
- `codex` The morning site card shows each away shop's "Tonight" preview and its top alert.
- `codex` A For Sale row on the city screen opens the lot card (it reuses `PropertyPanel`'s card) and buys from there.
- `codex` The map remembers its list or map view per session, plus the `M` shortcut and its entry in `ShortcutsText`.
- `claude` The illustrated map (T1, T4): art, pins and badges, and the neighbourhood patches. Built in #642: `tools/build_city_map.py` draws `assets/made/city_map/` from `data/city/city_map.tres` (rerun it after moving a neighbourhood or road); the city screen lays pins over the drawing from `map_position` inside an `AspectRatioContainer`, so they stay on their spots at any window size. A shop's pin picture follows its state, roadworks and hoardings stand beside their area's name and say what opens it, and "Show list" swaps to the plain list.
- `claude` Chain goals and the Ladle ladder (T7, T8): data, a saved `chain_goals` section with a migration test, and the awards night.
- `claude` Travelling (T5) and the morning card's role (T6).

**Phase C4: later** (backlog): neighbourhood rivals (#173), the downtown club lot (D39), the Woodland Cabin pin going live (#608), weather on the map (rain over the Seafront when it rains there), and a seasonal map dressing.

## 10. Saves and risks

- **Saves.** Phases C1 and C2 add no saved state. Neighbourhoods are static data and summaries are derived. The chain goals (C3) will add a global `chain_goals` section, registered with `SaveSystem.register()` and classed in `SiteSections` as global. A save without it loads with no goals met. *Open:* goals an old chain has already met (two shops, a Ladle) could pay on the first morning or be marked met silently. The recommendation is silently, so an old chain doesn't get a cash flood. There will be a migration test for it.
- **`main.gd` size (8.6k lines).** The screen's seam must stay small: the panel computes nothing, `ChainSummary` does the work, and `main.gd` hands it captured sections.
- **Capturing the active site's sections for the summary** costs a little on every open (`SaveSystem.capture_sections(PER_SITE)`). That's fine for a screen opened by a click, but don't call it every frame.
- **Ladles need in-person play.** This is intended (6.1). The chain ladder must not set a Ladle goal so high that a player has to tour every shop for weeks. Tune it after playtests.
- **Mood is per staff member.** Using the floor staff's mean mood hides one unhappy cook. The card could later name the unhappiest person. Phase 2 keeps the mean.
- **Name clashes.** "Old Mill Street" is a lot, not a neighbourhood. The neighbourhood names (T2) should not repeat lot names.

## 11. Taste calls (with options)

| # | Question | Options | Recommendation |
|---|---|---|---|
| T1 | The map's look | **A.** An illustrated paper map open on the owner's desk (2D, painted, coffee ring, pins). **B.** A parody phone app, "Spoon Maps" / "Gobble Maps", with jokey reviews and a "you are here" dot. **C.** A tiny low-poly 3D model town on a table (each neighbourhood a little diorama). | A for v1 (cheap, cosy, web-safe, fits the Kenney look as flat icons). B's jokes can live inside A as pin reviews. C later if the art budget allows. |
| T2 | Neighbourhood names | **A. Plain and cosy:** Old Town, Millbrook, The Seafront, Skyline, Pinewood. **B. Punny:** Crumpet Corner, Flour Mill Fields, Brine & Dandy, Upper Crust Heights, Whisk Woods. **C. Food-led:** Pie Quarter, Bread Basket, Chowder Coast, Cocktail Heights, Mushroom Hollow. | A for the map, with B's puns as the chain-goal and pin jokes. |
| T3 | Which neighbourhoods and lots | **A.** As in 2.2: five, with both seaside lots in one Seafront. **B.** Six: the Boardwalk and the Cliff in separate areas (Seafront, Headland). **C.** Four: no locked Pinewood until the cabin lot exists. | A. A shared Seafront sets up rivals and growth (#173, #597). |
| T4 | Locked areas | **A.** Soft fog or cloud over the patch, with a sign. **B.** Roadworks: cones, a "Road closed" sign and a digger (jokey). **C.** "Coming soon" hoardings with a painted preview. | B for areas waiting on a tier (it reads as "not yet") and C for areas with no lot yet. |
| T5 | Travelling | A. a straight switch · B. a van ride along the map road · C. a commute joke card | B + C |
| T6 | The morning card | A. keep it + "See the map" · B. the map replaces it · C. the card until 4 shops, then the map | A now, revisit after playtests |
| T7 | The free-play goal | A. 9 Ladles across the chain · B. a Ladle in every neighbourhood · C. an awards night after A or B | A + C |
| T8 | Chain name | A. the player names it (default "Fool's Kitchen Group") · B. a fixed name · C. no chain name, just "Your restaurants" | A |

## 12. Chain goals and the Ladle ladder (#643, design)

Status: **decided** (Jared, 2026-11-19; see 12.5, DESIGN D43). Section 6 sketched the ladder, T7 and T8 settled the ending, and this section turns it into something buildable. Nothing here is built yet; the build plan is 12.6.

### 12.1 What the player sees
- **The chain strip** on the city screen grows a goals line: "Chain goals: 3 of 9 · Next: Neighbourly (shops in 3 neighbourhoods)". Tapping it opens the ladder.
- **The ladder** is a card in Goals, under the career goals: every goal in order, met ones ticked with the day they were met, the next one highlighted, later ones shown but greyed. Nothing is hidden, so the long goal is always in sight.
- **Meeting a goal** gives a toast and a log line at the close it happens, and a line in that evening's report ("Chain goal met: Delegator, +$300"), the same way the week goals pay today.
- **The last goal** (a Golden Ladle in every neighbourhood) sets up the awards night the next morning (C4), and then free play: nothing locks, the ladder reads "Complete", and a small golden statue appears in Old Town on the map (art, #642).

### 12.2 The ladder (with T7 applied)

| # | Placeholder name (C5) | Met when (checked at each close of the active site) | Reward (C1) |
|---|---|---|---|
| 1 | **Two's Company** | you own 2 restaurants and the new one has served a day | $250 |
| 2 | **Delegator** | an away restaurant was run by its manager at a close (`AwaySites` MANAGED) | $300 |
| 3 | **Neighbourly** | you have restaurants in 3 neighbourhoods (`CityMapDef.covered`) | $400 |
| 4 | **Full House** | 7 closes in a row with no away restaurant closed | $500 |
| 5 | **Chain Reaction** | the chain's takings over the last 7 days reach $5,000 (`ChainStats.chain_takings_total`) | $500 |
| 6 | **First Ladle** | any restaurant holds a Golden Ladle (`ChainStats.total_ladles` ≥ 1) | $750 |
| 7 | **The Whole Town** | you have a restaurant in every neighbourhood that has a lot | $1,000 |
| 8 | **Ladle Collector** | Golden Ladles in 3 neighbourhoods | $1,000 |
| 9 | **Golden City** (T7) | a Golden Ladle in every neighbourhood that has a lot | the awards night |

All numbers are placeholders and live in data (`data/balance/chain_goals.tres`), like `goal_chains.tres`. Goals pay once, never fail and don't need to be met in order. The list shows them in order, and later ones can be met early: a Ladle at the home shop meets First Ladle before Two's Company.

### 12.3 How long the last goal takes (C2: kept as designed)
- The critic only comes from **career Tier 5** (`critic.tres` `unlock_tier`), with a 5-day cooldown and a 20% chance each eligible day. They only visit the restaurant you are working that day, and only a good review with enough prestige awards a Ladle.
- "Every neighbourhood" means five places: Old Town, Millbrook, The Seafront, Skyline and Pinewood. Owning five restaurants needs **Tier 6** (Tier 5 allows three).
- So Golden City is a long arc. Roughly: reach Tier 6, own five restaurants, then visit each until the critic awards it a Ladle. That is about 10 or more in-game days per restaurant once its prestige is ready, so 50 or more days after Tier 6. D31 calls this the long arc, so that may be right, but it is Jared's call (C2).

### 12.4 How it is built (no taste needed; for review)
- **Data:** a `ChainGoal` resource (`id`, `title`, `description`, `condition`, `target`, `reward_cash`, `reward_xp`) and a `ChainGoalSet` holding them in order, in `data/balance/chain_goals.tres`. Conditions: SITES_SERVING, MANAGED_CLOSE, NEIGHBOURHOODS, FULL_HOUSE_STREAK, CHAIN_TAKINGS_7, LADLES, LADLE_NEIGHBOURHOODS, ALL_NEIGHBOURHOODS, LADLE_IN_EVERY_NEIGHBOURHOOD. It is validated like the other data (unique ids, positive targets).
- **Facts:** a pure `ChainFacts` is built at each close of the active site, after `_close_away_sites` has booked the away results. It comes from `ChainSummary.build`, `ChainStats` and `CityMapDef` (all merged in #639, #645 and #666). It holds the sites serving, a managed away site tonight, the neighbourhoods covered, the neighbourhoods with a Ladle, the 7-day takings and the closed-site streak.
- **Rules:** a pure `ChainGoals.newly_met(state, facts, set) -> Array[StringName]`, with no RNG. Main pays each newly met goal with a new non-operating ledger category, `CHAIN_GOAL_BONUS`, added to `DayReport.NON_OPERATING_CATEGORIES`, so it never inflates the active site's profit, XP or records. XP goes through `OwnerProgress.award_bonus`. Creative games have no ladder, as with the week goals.
- **Save (rule 9):** a new global section `chain_goals`, version 1, holding:
  - `met`: id to the day it was met;
  - `streak`: the closes in a row with no away restaurant closed;
  - `chain_name`, at most 40 characters, default "Fool's Kitchen Group";
  - `finale_day`: 0 until Golden City.

  It is registered with `SaveSystem.register()`, classed global in `SiteSections`, and written only by the morning autosave. A save without the section starts with nothing met; what it does with goals an old chain already meets is C3. Migration tests cover both a save with no section and a version-1 round trip.
- **UI:** the words live in one place (`ChainText`, rule 11). The chain strip line, the Goals ladder card and the report line. The awards night is its own piece (C4).

### 12.5 Calls for Jared (decided)

**Decided (Jared, 2026-11-19, relayed by the director), each on the recommendation:**
- **C1:** cash **and** a trophy for each goal.
- **C2:** Golden City stays as designed: a Golden Ladle in all five neighbourhoods.
- **C3:** goals an old save already meets are marked met, with no cash, and one welcome note says so.
- **C4:** the awards night is a special edition of *The Daily Ladle*, with a short parody awards bit inside it.
- **C5:** the pun names in 12.2.
- **C6:** a prompt to name the chain the first time you own two restaurants, and the name stays editable on the city screen.

The options as they were put:
| # | Question | Options | Recommendation |
|---|---|---|---|
| C1 | What do chain goals pay? | **A.** Cash and a little XP, like the week goals (the table above). **B.** Trophies only: a plaque or statue on the map and in the shop, no money. **C.** Both: smaller cash plus a trophy per goal. | **C**: money keeps it a tycoon goal, and a trophy you can see is the cosy payoff. |
| C2 | How long should Golden City take? | **A.** As designed: five neighbourhoods, a Ladle each (Tier 6, a long arc of 50+ days after it). **B.** Ladles in 4 of the 5 neighbourhoods. **C.** Keep five, but the critic comes a little more often to a restaurant that has no Ladle yet (a sim change). | **A**, unless playtests say it drags; then **C**. |
| C3 | An old save already meets some goals (two shops, a Ladle). | **A.** Mark them met silently. **B.** Pay them all on the first morning. **C.** Mark them met, no cash, and say so once ("Welcome back: you've already earned 3 chain goals"). | **C**: it is honest and doesn't hand out a cash flood. |
| C4 | What is the awards night? | **A.** A card the morning after Golden City: a parody awards show ("And the Ladle for Most Soup goes to…") with your staff's toast. **B.** A special edition of *The Daily Ladle* (#646) about your chain. **C.** A real evening event at your current restaurant: a party service with a crowd and confetti. | **B**, plus a short version of **A** inside it: it reuses the paper and stays cosy. **C** is lovely but large. |
| C5 | Goal names | **A.** The puns above (Two's Company, Delegator, Neighbourly, Full House, Chain Reaction, First Ladle, The Whole Town, Ladle Collector, Golden City). **B.** Plain names ("Second restaurant", "Three neighbourhoods"…). **C.** Jared's own. | **A**, with Jared editing any he dislikes. |
| C6 | Where to name the chain (T8) | **A.** A prompt the first time you own two restaurants. **B.** Only on the city screen's header, any time. **C.** Both. | **C**: the moment it becomes a chain is the natural time to name it, and it stays editable. |

### 12.6 Build plan
1. **G1 (Codex):** data, `ChainFacts`, `ChainGoals`, the ledger category, the save section and its migration tests. No UI beyond the report line.
2. **G2 (Codex):** the chain strip goals line and the Goals ladder card.
3. **G3 (Codex):** chain naming (C6).
4. **G4 (Claude):** Golden City's awards night (C4) and the statue's hook into the map (the art itself is #642's).
