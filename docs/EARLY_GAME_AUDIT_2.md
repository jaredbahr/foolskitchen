# Early-game audit 2: days 1 to 10 at the home shop

Second early-game pass (2026-11-19), after wave 0 (#490 to #493, #500, #501), the Opening week (#494), Week 2 (#514) and service event cards (#495, #506) merged. Goal (D31): days 1 to 10 should feel like designing a cute shop and watching it run, with something new to do or see every day.

## Summary for Jared

**What I found**
1. **Days 1 to 3 are now busy; days 6 to 10 go quiet again.** A player who follows the goals finishes the Opening week by day 3 and Week 2 by day 5 to 7. From then on the goal tracker is empty, the weekly challenge was already won on day 2 or 3, and new unlocks have dried up. Every day still gets one or two service cards, so it isn't "watching paint dry" any more, but there's nothing to work towards.
2. **Growing the shop barely pays, and the goals steer you into the wrong kind of growth.** Week 2 has you take the bigger lease (rent goes from $18 to $60 a day), hire a cleaner, add tables and a fryer. That leaves the kitchen with one cook. From day 5 to day 10, leaving out goal bonuses, the "engaged" player made about $35 a day; a player who did nothing at all made about $75. What pays is tables plus a cook plus a server (balance probe below). The goal bonuses (about $1,400 by day 7) hide this until they stop.
3. **Unlocks arrive all at once, then stop.** Owner levels 2 to 4 unlock 99 things (44, 30 and 25), and an engaged player reaches level 3 on day 2: one evening report listed **57 unlocks at once**. Levels 5 and 6 add 10 things between them, and levels 7 and up add nothing, so days 5 to 10 bring almost nothing new.
4. **The first goal teaches a lesson the game then punishes.** "Change a dish's price" is easiest to meet by raising prices. A 10% rise costs 4 to 9 "too expensive" walkouts a day for good, and their reviews hold stars at about 3.4 to 3.8, so the player stalls below Tier 3's 4.0. Nothing explains why.
5. **The morning paper is mostly bad news.** Almost every headline is "record" or "N walkouts". Being full is the normal state from day 2, with 10 to 30 guests a day finding no table. No headline ever celebrates a new tier, a level-up or a new regular.
6. **Group bookings never happen.** They unlock at level 2, but an offer needs a joined table group with at least six seats. Nothing tells the player that, and in 10 to 16-day runs no player got a single offer.
7. Smaller points: the week-1 weekly challenge is sized from day 1 (the quietest day) and repeats the Opening week's serving goals, so it pays $120 on day 2 or 3 for nothing extra. Week 2's "Serve 30" is the one goal an engaged player sometimes misses.

**What I fixed (draft PRs)**
- **#640 Week 3: the road to Tier 3.** A third paid goal chain (about $590): hire a second cook, add an oven dish, add a waiting bench, put out an A-frame sign, get eight 5-star reviews in a day, serve 35 in a day, and have a calm 4-star day (Tier 3's rating). It's pure data. In probe runs the tracker now has goals until day 13 or 14, and the engaged player reaches Tier 3 on day 6, 9 or 12 (seeds 2, 3 and 1), where before it never got there by day 10.
- **#646 Daily Ladle: good news and one tip.** New headline groups for a new tier, a level-up, a new regular and a "full house". A day lost mostly to no free table now reads as a busy shop, not a bad one. A tip line names yesterday's biggest reason guests left, with the fix: "12 guests found every seat taken. More tables, and hands to serve them, would fit them in." It also covers prices, waits and stock-outs.
- **#664 (this doc)** also adds the audit driver `tools/early_game_audit.gd`.

**What needs your call** (issues filed, labelled `claude`)
- **Unlock pacing (#647):** spread levels 2 to 4's 99 unlocks out to levels 5 to 9, so something new arrives every day or two. This decides which items arrive when.
- **Week 2's growth path (#648):** swap "Hire a cleaner" for "Hire a second cook", or move the cook into Week 2, and maybe soften the lease rent from $60 to about $40. Taste and economy call.
- **Price lesson (#649):** reword the first goal ("move any dish's price up or down... guests notice") or make a small rise cost less. Wording and tuning call.
- **Bookings (#650):** lower `min_party_size` to 4 (a four-seat table), or tell the player that bookings need joined tables. Design call. Fully specifiable once you pick.

## How it was measured

- `tools/early_game_audit.gd` (new, hand-run, never in CI) plays the real Main scene with saving off and service cards on, answering each card with its first choice. It prints one JSON line per day: arrivals, served, lost by reason, the ledger, cash, stars, level, XP, tier, unlocks, milestones, the Opening week and Week 2 goals shown and done, the weekly challenge, service cards, bookings, regulars, rushes, records, reviews and the morning paper.
  - `--player=engaged` follows the goals through the existing `week_two` probe player: raise prices 10%, add a lamp, work the floor, add a drinks shelf, then a table and a server, then the lease, floor, a four-seat table, a fryer and fries, and a cleaner. After this PR it also follows Week 3 if that chain is present: back to standard prices, a second cook, an oven and pizza, a waiting bench.
  - `--player=passive` changes nothing.
- Runs: Normal at seeds 1, 2 and 3 for the engaged player, Normal at seed 1 for the passive player, Easy at seed 1 for the passive player (Easy runs the business for you), each for 10 days. Then Week 3 runs for 16 to 21 days.
  - The engaged player can't start on Easy: Easy resets prices each morning, so the probe's day-1 price goal fails. That is how Easy should behave, not a bug.
- `tools/balance_probe.sh --days 10 --seeds 1,2` over six set-ups, to see which growth actually pays.
- Screenshots from `tools/screenshot.sh`: the day-1 morning with the Daily Ladle and the Opening week tracker, and the day-1 evening report. They're attached to the PR, not committed.

## What a player sees and does, day by day (Normal, engaged, seed 1)

| Day | Arrive | Served | Lost (why) | Profit | Cash | Stars | Lvl / Tier | What's new | Goals on screen afterwards |
|---|---:|---:|---|---:|---:|---|---|---|---|
| 1 Thu | 19 | 13 | 6 too expensive | +85 | 385 | 3.0→3.2 | 1 / 1 | 3 goals paid ($120), "lights flicker" card | decor, serve 15, drink |
| 2 Fri | 37 | 27 | 5 no table, 4 too expensive | +497 | 882 | →3.8 | **3 / 2** | **57 unlocks at once**, Tier 2, weekly +$120, goals +$340, flyers card | grow together |
| 3 Sat | 65 | 28 | **32 no table** | +252 | 1134 | →3.5 | 3 / 2 | rush (sports day), off-menu card | grow together done → Week 2 |
| 4 Sun | 36 | 26 | 4 no table, 6 too expensive | −8 | 1126 | →3.6 | 4 / 2 | 17 unlocks, lease, fryer, cleaner, Week 2 goals +$600, first regular | serve 30 |
| 5 Mon | 41 | 24 | 9 no table, 5 too expensive | +50 | 1176 | →3.7 | 4 / 2 | 2 cards | serve 30 |
| 6 Tue | 47 | 24 | 18 no table | +7 | 1183 | →3.4 | 5 / 2 | 4 unlocks, 2 regulars, inspection C | serve 30 |
| 7 Wed | 57 | 30 | 22 no table | +162 | 1345 | →3.5 | 5 / 2 | blogger review, rush | **none** |
| 8 Thu | 46 | 27 | 16 no table | −19 | 1326 | →3.4 | 5 / 2 | 1 card, weekly "Sell 46 burgers" | **none** |
| 9 Fri | 53 | 27 | 26 no table | +84 | 1410 | →3.8 | 6 / 2 | 2 unlocks, 2 regulars | **none** |
| 10 Sat | 63 | 27 | 25 no table, 9 too expensive | +23 | 1433 | →3.6 | 6 / 2 | 1 card | **none** |

The passive player (seed 1) serves 19 to 22 a day from 6 seats, loses 8 to 26 a day to "no table", makes +$16 to +$283 a day and ends day 10 with $1,440, more than the engaged player's $1,433, and at 3.9 to 4.3 stars. On Easy the passive player ends with $1,370 and reaches Tier 3 on day 10. No day had a loss bigger than −$44, cash never got near zero, and there were no soft-locks or loans in any run.

### Ten-day balance probe (mean of seeds 1 and 2, no service cards)

| Set-up | Served | Lost | Wages | Rent | Profit (10 days) |
|---|---:|---:|---:|---:|---:|
| default (do nothing) | 198 | 118 (112 no table) | 550 | 180 | **925** |
| extra cook only | 204 | 120 | 850 | 180 | 739 |
| more tables only | 178 | 110 (29 waited too long) | 550 | 180 | 573 |
| **tables + cook + server** | **296** | 55 | 1100 | 180 | **1509** |
| grown (tables, coffee, 5 dishes) | 174 | 202 | 550 | 180 | 537 |
| week_two player (incl. ~$1,400 goal bonuses) | 268 | 218 | 858 | 474 | 1475 |

Takeaway: tables alone or a cook alone each *lose* money. Seats plus a cook plus a server together earn about $60 a day more than standing still. The Week 2 player ends level with standing still only because of about $1,300 in goal bonuses, which pay for its about $765 of purchases and its higher rent and wages.

## Diagnosis

### Dull stretches
- **Days 6 to 10 (engaged) and 8 to 10 (passive).** No goals on the tracker, the weekly challenge is done or far off, and new unlocks have run dry. The service cards (one or two a day) are now the only thing that changes from day to day.
- **Days 2 to 7 (passive).** The same three Opening week goals sit on the tracker for six days ("Change a price", "Place decor", "Put a drink on"). That's fine: each is one click away. The paper's tip line (#646) now gives this player a reason to act.

### Confusing moments
- **"Too expensive" after the price goal.** The goal invites a change in either direction. Raising prices is the obvious move, and it quietly costs guests and stars for the rest of the game.
- **Always full, never fixed.** From day 2, 10 to 30 guests a day leave for "no table" whatever the player builds. Before #646 the morning paper reported it as "N walkouts" every day, which reads as failure.
- **Bookings:** unlocked at level 2, then never seen.
- **The unlock wall:** a 57-item list on day 2 can't be read, and none of it is explained.

### Money traps
- **The Week 2 growth path** (above): the lease more than triples rent, and the cleaner and server add $45 a day in wages, but served guests go from about 21 to about 27 because one cook can't keep up. Leaving out goal bonuses, days 5 to 10 made about $35 a day against the passive player's $75.
- No losses on days 1 to 4 in any run. Day 2 was −$24 or −$35 only when the probe bought "Flyers for hire" ($40), a choice the player makes knowingly.

### Reward cadence (Normal, engaged)
| | Day 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Goal payouts | $120 | $340 | $150 | $600 | – | – | $100 | – | – | – |
| Weekly challenge | – | $120 | – | – | – | – | – | – | – | – |
| Level-up unlocks | – | 57 | – | 17 | – | 4 | – | – | 2 | – |
| Milestones | 1 | 4 | 4 | – | 1 | 1 | – | – | 1 | – |
| Service cards | 1 | 1 | 1 | 1 | 2 | 1 | 2 | 1 | 2 | 1 |

More than 90% of the goal and challenge cash and of the unlocks land in the first four days. After #640, Week 3 adds rewards on days 8 to 14 (an engaged run paid $80 + $80 + $40 on day 8, $100 on day 11 and $150 on day 13).

### Meaningful decisions per day
Mornings: days 1 to 4 each have two or three goal-driven choices (what to buy, whom to hire, prices). Days 5 to 10 have none until Week 3. Service: one or two cards every day. Bookings: none. Unlock choices: a flood on days 2 to 4, then hardly any.

## Ranked fixes

| # | Fix | Impact | Effort | Status |
|---|---|---|---|---|
| 1 | **Week 3 goal chain:** the road to Tier 3, with the second cook as its first goal | High: fills days 6 to 14 and steers growth into the kind that pays | S (data) | **#640** |
| 2 | **Daily Ladle:** good-news headlines and one actionable tip | Med: turns "always full" into a nudge, celebrates progress | S | **#646** |
| 3 | **Spread unlocks** from levels 2 to 4 out to levels 5 to 9 | High: something new every day or two | M (data and tests), taste | #647 |
| 4 | **Week 2 growth path:** a second cook instead of the cleaner; consider lease rent $60 → $40 | High: removes the money trap | S data, taste and economy | #648 |
| 5 | **Price goal lesson:** wording that warns guests notice, or a gentler response to a small rise | Med | S, taste | #649 |
| 6 | **Bookings reachable early:** `min_party_size` 6 → 4 or a hint about joining tables | Med: a dormant feature comes alive | S | #650 |
| 7 | **Week-1 weekly challenge:** don't draw a "serve N" challenge while the Opening week runs, or size it from forecast demand rather than day 1 | Low | S | proposal here |
| 8 | **Unlock report:** group a long unlock list by category ("12 decor, 6 recipes...") with a "See all" | Med: makes the day-2 flood readable | M, UI | proposal; folds into #3 |

## Not changed, by design
- Service cards were answered with their first choice, so "Flyers for hire" ($40) often cost the probe money on day 2. A real player chooses.
- No-table walkouts are high in every set-up. That's the intended pressure to expand (D16). The fix is to make the right expansion visible and worth it (#1, #2, #4), not to cut demand.
