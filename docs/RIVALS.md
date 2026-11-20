# The rival across the street (#173)

Status: **design, decided** (Jared, 2026-11-20). Nothing here is built yet. Section 7 is the build plan. The numbers are placeholders and live in data.

## 1. The idea in one paragraph
When one of your restaurants is clearly winning, a copycat opens beside it. **Chef Reginald Copley**, a smug, recurring rival, opens a knock-off of that very restaurant ("Cool's Kitchen", "Not The Seaside Cliff"). It copies the theme you are winning with, prices 10% under you, and pulls away a share of your guests. You fight back in one of three ways:
- **undercut him:** set your prices below his;
- **out-design him:** push your vibe past his;
- **move on:** change your concept so he's copying yesterday's look.

Every day you win, his morale drops. When it hits zero he closes in a huff, the paper gloats, and you keep his sign as a trophy. Weeks later he's back, somewhere else, with a new name.

## 2. Jared's decisions (2026-11-20)
| # | Question | Decision |
|---|---|---|
| R1 | Who is the villain? | **One recurring chef with knock-off names.** A running gag across the whole game. |
| R2 | Where does he set up? | **A food truck anywhere, a shop where possible.** On a street with shopfronts he takes a building and paints a gaudy sign. Everywhere else he parks a garish food truck by your door. |
| R3 | How does it end, and how hard does it hit? | **Beat him to close him, with a mild sting.** He takes at most about 15% of the guests. Winning days close him early, and he comes back later somewhere else. |
| R4 | When does the first one come? | **When a place is clearly winning**, from career Tier 3. |

## 3. The character
- **Name:** Chef Reginald Copley. "Copley" is the joke.
- **Look:** a too-tall toque, an enormous mustache, and a gold-trimmed chef's jacket. He appears on his sign and his truck, never as a walking agent in v1.
- **Voice:** grand, wounded and petty, and never actually a threat. His lines are written by the director and kept as data.
- **His restaurants:** each one is a knock-off of the restaurant he's copying. The pattern is picked by how many rivals there have been so far, so it's deterministic. Patterns:
  - "Cool's Kitchen": swap one letter or rhyme the first word, by a hand-written table per restaurant name. If no entry exists, fall back to the next pattern.
  - "{name} 2"
  - "Not {name}"
  - "The Real {name}"
  - "{name} Deluxe"
  - "Ye Olde {name}"
  - "{name}-ish"
- Names are cut to 28 characters.

## 4. The rules

### 4.1 When a rival opens
A restaurant is a **winning site** when, at the close of a day you worked there in person:
- it holds **4.0 stars or more**;
- its vibe theme is set (`active_theme` is not empty) with a **vibe score of 50 or more**.

Each site keeps a **winning streak** of in-person closes in a row that meet this. Any other in-person close resets the streak. Away days neither add to nor reset it.

Every morning, if all of these hold, roll the `&"rival"` stream with a **35%** chance:
- no rival is open;
- the cooldown has passed;
- career Tier is 3 or more, and the day is 14 or later;
- some site has a streak of **7 or more**.

The rival targets the site with the longest streak. Ties go to the highest stars, then the lowest site id. Create the stream only when the first roll can happen, so older saves keep the same random draws.

**Cooldown:** 21 days after a rival closes. Only one rival is open at a time, across the whole chain.

### 4.2 What he copies
At opening the rival records:
- `copied_theme`: the target site's active theme;
- `rival_vibe`: 55 plus a 0 to 15 roll;
- `rival_price_ratio`: a fixed 0.90.

### 4.3 The pull
`pull_max` = 0.10 for the first rival, plus 0.02 for each later one, capped at 0.15.

Each morning at the target site, the pull is shrunk by whatever you are doing well:
- **Price:** if your menu's average price ratio is at or below `rival_price_ratio`, multiply by **0.5**. The average is the mean of enabled dishes' price / standard. On difficulty modes with automatic prices this check is skipped.
- **Vibe:** if your vibe score is at least `rival_vibe + 10`, multiply by **0.6**.
- **Concept:** if your active theme differs from `copied_theme`, multiply by **0.4**.

The result is the **rival factor**: `1 - pull`. It is never below 0.85.
- **Active site:** a new `rival` factor in `DemandBreakdown.evaluate`, so the HUD and forecast show it.
- **Away site:** `AwaySites` multiplies the managed earnings by the same factor.

### 4.4 Morale and closing
Morale starts at 100 and changes at each close where the target site traded:
- **You won the day:** the in-person pull was at most half of `pull_max`. Morale **−20**.
- **Otherwise,** including away days: **−5**. He gets bored, so even ignoring him ends it in at most 20 days.

At 0 he closes. You get:
- a paper headline;
- a log and report line;
- **his sign as a free wall decor item**, "Copley's Closing Sign" (charm 2; one is added to your stock each time, and it stacks);
- the cooldown starts.

Selling or closing the target site closes the rival at once, with no trophy.

### 4.5 Stunts
Every 3 to 5 days, rolled on the `&"rival"` stream, he pulls a stunt for one day.
- It is a **service event card**, reusing `ServiceEvents` with its boosts and follow-ups.
- **On that day only,** the rival factor drops by 0.05 more, but never below 0.80.
- The card offers a counter:
  - pay a small cost (about $30–60) to cancel the stunt's extra pull;
  - or ignore it.
- Countering doesn't change morale; winning days do.
- The director writes the stunts as data (section 6).

## 5. What the player sees
- **The street:**
  - **The home street:** the rival takes a named slot across the road. This means adding a named house-row building to the starter street.
  - **The Boardwalk:** he takes a terrace shop (a new `NeighbourState.RIVAL`).
  - **Every other lot:** a food truck prop parked at the curb or path edge, near the door but off the walkways.
  - In every case: his sign with the knock-off name, and a tiny Copley face.
- **The rival card:** click his building or truck. It shows:
  - the knock-off name and morale as a bar ("Copley's morale: 60%");
  - what he copied ("Copying: Cozy");
  - his prices ("10% under yours") and his vibe;
  - three hints that tick green when you're beating him on price, vibe or concept.
- **HUD:** a small chip at the target site while he's open: "Rival: Cool's Kitchen". The demand breakdown shows the rival line.
- **Evening report:** "Cool's Kitchen pulled about 6 guests today." On a won day: "You won the day: Copley sulks (morale 40%)."
- **Morning paper:** a `rival` headline group for opening, stunt days and closing, plus one brief line on other days he's open.
- **City map:** a little rival badge on the target restaurant's pin.

## 6. Writing (the director's)
All of it is data, and all of it is in US spelling:
- the knock-off name table;
- 6 to 8 stunts, each with a card title, text and counter text;
- the paper headlines for opening, stunt and closing;
- Copley's sign slogans;
- the card's hint lines.

The director writes these in the R4 issue below, before the UI issues need them.

## 7. Build plan
1. **R1 (Codex), the sim:**
   - `RivalState` as a global save section `rival` (version 1). It holds:
     - status: NONE, OPEN or COOLDOWN;
     - site id, opened day, knock-off name, copied theme, rival vibe, morale, pull_max, the number of rivals so far, and the closed day;
     - the per-site streaks.
   - The rules: pure functions, no RNG except the `&"rival"` stream.
   - The `rival` factor in `DemandBreakdown`, and the away-sites factor.
   - Trophy stock, the report line and the save tests. No UI beyond the report line.
2. **R2 (Codex), the UI:** the rival card, the HUD chip, the demand line, the morning paper group, the city map badge. The words come from data.
3. **R3 (Codex), stunts:** stunt cards through `ServiceEvents`, with the counter choice and the one-day extra pull.
4. **R4 (Claude), art and words:**
   - the food truck;
   - the gaudy shop sign and the RIVAL neighbour state look;
   - the named house slot on the starter street;
   - the Copley sign trophy;
   - all the writing in section 6.

## 8. Not now
- Several rivals at once.
- Copley as a walking agent.
- Rivals that change the guest mix.
- A rival who can win and force you out.
- The parody review and delivery apps and the changing neighborhood from #173 stay in the backlog.
