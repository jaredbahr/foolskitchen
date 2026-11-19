# Guests with personality

Design for guest types, quirks and how reviews and the morning paper talk about them. Owner: the director. Tone is D31: cosy and cute with light parody, never mean, made for adults (D15).

## For Jared: the short version

**The cast (10 types).** The four we have stay as they are: **Regulars** (the baseline), **Students** (cheap, patient, coffee), **Foodies** (pay well, judge the food) and **Families** (groups, patient, need the restroom). Six new ones give each location its own crowd:
- **Tourists** (Seaside Cliff, Boardwalk): pay more, love local dishes, never come back.
- **Office crowd** (Skyline Rooftop): a lunchtime wave that pays well and won't wait.
- **Walkers** (Seaside Cliff): muddy boots, hot drinks, happy to wait out the rain.
- **Surfers** (Boardwalk): big groups, cold drinks, afternoons.
- **Farmers** (Old Mill): early, hungry, thrifty, a second plate.
- **Foragers** (Woodland, once it opens): patient, curious, love anything local.

**Quirks (12, one guest in eight or so has one).** Small and readable, each with one icon and one testable effect: the **Shutterbug** (photographs every dish, always posts a review), the **Chatterbox** (stays longer, leaves happier), the **Lunch-breaker** (in a hurry, thrilled when it's quick), plus the window-seat lover, the dog walker, the birthday table, the sweet tooth, the big eater, the indecisive one, the early bird, the "maybe famous" guest in sunglasses and the critic in disguise (already in the game, #303).

**Decisions for you** (each lists options; my pick is first):
1. **T1. How often do quirks show up?** One in eight guests / one in four / one in sixteen.
2. **T2. When do quirks start?** Owner level 3 / day 1 / level 5.
3. **T3. How do you see a quirk?** A small icon over the guest plus a line when you inspect them / the inspect line only / a speech bubble when they arrive.
4. **T4. Should a quirk ever cost you?** Small trade-offs both ways / only upsides.
5. **T5. Tourists and regulars.** Tourists never become regulars / one in twenty "falls in love" and returns as a named regular.
6. **T6. The office crowd at lunch.** A soft lunch window (mostly 11:30 to 2) / strictly lunch only.
7. **T7. "Maybe famous" guest.** Draws a small crowd for an hour / just a funny review line / leave it out.
8. **T8. Dogs inside.** Dogs only where there's outdoor seating / anywhere, with a water bowl item.

**What I'm building now (separate PRs):** tourists and the office crowd (#471), with each location's guest mix now really shaping who walks in there (today the mix only shows on the property card), then the quirk data and three quirks end to end (Shutterbug, Chatterbox, Lunch-breaker) with their review quotes. The rest is filed as issues (see the last section).

---

## 1. Principles

- **Readable at a glance.** A type is told apart by what it orders, how long it waits and how it reviews; a quirk by one icon and one line. No hidden stats the player can't learn.
- **One effect each.** Every quirk changes one number or one choice in the sim, so it can be tested, tuned and explained in a sentence.
- **Never mean.** Guests are silly, not stupid; the joke is affection. No mocking bodies, ages, jobs or money troubles.
- **The place picks the crowd.** Each location's `LotDef.guest_mix` decides who walks in there (D28, D39). The home shop keeps today's mix exactly.
- **Deterministic and cheap.** Types draw from the existing `customers` stream as today. Quirks use their own lazy named stream (`quirks`), so the arrival stream (who arrives, when, how many) is unchanged by them. No new save state: a quirk lives on a guest for one visit.

## 2. The cast

Numbers are multipliers on today's baseline (Regular = 1.0). Party is min–max, with pairs from level 2 and bigger groups from level 5 as today (#493). "Lots" lists the locations that draw them and their share of that location's mix.

| Type | Likes | Spend | Patience | Party | Reviews | Lots (share) | Status |
|---|---|---|---|---|---|---|---|
| **Regular** | anything; the bar theme | 1.0 | 1.0 | 1–2 | 1.0 | Home (most), Boardwalk 0.35, Old Mill 0.4 | built |
| **Student** | coffee, cheap plates; café theme | 0.8 | 1.3 | 1–2 | 0.9 | Home, Old Mill 0.25 | built |
| **Foodie** | good food (quality weight 0.4); evening menus | 1.4 | 0.9 | 1–2 | 1.4 | Home (grows with stars), Rooftop 0.3 | built |
| **Family** | patient groups; restroom | 1.1 | 1.4 | 2–4 | 1.1 | Home (from level 4), Boardwalk 0.35 | built |
| **Tourist** | local and seafood dishes (+0.3 stars) | 1.3 | 1.0 | 1–4 | 1.3 | Seaside Cliff 0.55, Boardwalk 0.3 | building (#471) |
| **Office crowd** | quick lunches; arrive 11:30–14:00 | 1.25 | 0.7 | 1–3 | 0.8 | Rooftop 0.6 | building (#471) |
| **Walker** | hot drinks, hearty food; shrug off rain | 1.0 | 1.2 | 1–2 | 1.0 | Seaside Cliff 0.3 | issue |
| **Surfer** | cold drinks, fries; patio seats; afternoons | 0.9 | 1.2 | 2–4 | 1.1 | Boardwalk 0.25 | issue |
| **Farmer** | big plates, pies; early; a second dish | 0.85 | 1.2 | 1–2 | 0.8 | Old Mill 0.35 | issue |
| **Forager** | local and foraged dishes; quiet seats | 0.9 | 1.4 | 1–2 | 1.2 | Woodland 0.6 | issue (lot not built) |

**Notes per type**
- **Tourist.** One-time visitors: they never become regulars (T5). Less fussy about price (a higher budget). A dish tagged `seafood`, or one carrying one of the location's own tags (a boardwalk soft serve at a seaside lot), gives a small happiness bonus; when #626's Local tag lands, Local dishes count too. Review chance is a little higher: they post about their holiday.
- **Office crowd.** Mostly arrive in a lunch window (11:30–14:00 on the shop clock); outside it their arrival weight drops to a fifth (T6). Short queue and food patience, a good budget. A slow lunch is their biggest complaint.
- **Walker.** Come up the cliff path in any weather: in rain their arrival weight holds while others drop. A hot drink with their meal is likely. Often bring a dog (the dog-walker quirk is twice as likely for them).
- **Surfer.** Arrive in twos to fours, mostly in the afternoon, prefer the patio, order cold drinks and fries. Relaxed: patient but not big spenders.
- **Farmer.** Early: weighted to the first two hours. Thrifty but hungry: one in three orders a second dish (the big-eater quirk is twice as likely for them). Low review chance: they've better things to do.
- **Forager.** Patient, curious, love anything local or foraged (#608). Very rarely bring you a basket of mushrooms (a tiny free stock gift, issue later).

**How a lot's mix shapes arrivals (with #471).** Today `LotDef.guest_mix` only shows on the property card; arrivals everywhere use the reputation weights. With #471, at the home shop arrivals stay exactly as today. At any other location the lot's `guest_mix` share replaces the type's reputation weight, but a type still waits for its owner-level unlock, and the room's theme bonus and the evening multipliers still apply. The location types (tourists, office crowd and the later four) have zero reputation weight, so they never arrive at the home shop, which has no mix.

## 3. Quirks

A quirk is a small personality on top of the type: one icon, one line in the inspect panel, one effect. At most one per guest. In a party only one member can have one (the birthday table belongs to the party). A regular, a critic or a booked guest never also gets a random quirk.

**Rolling.** When an ordinary guest arrives, and once the owner level is at least the quirk unlock (T2), the `quirks` stream draws once: with the quirk chance (T1) the guest gets one, picked by weight among quirks that suit their type and the location. Below the unlock, no draw happens.

| Quirk | What you see (T3) | Sim effect (testable) | Review line hook | Status |
|---|---|---|---|---|
| **Shutterbug**: photographs every dish | camera icon; holds up a phone when food lands | Always writes a review when served (review chance 1.0) | 4–5 stars: `photo_happy` quotes | built |
| **Chatterbox**: tells the whole room about their week | speech-dots icon; leans across the table | Stays 50% longer at the table (holds the seat), +0.5 raw stars | 4–5 stars: `chatty_happy` quotes | building |
| **Lunch-breaker**: on a strict lunch hour | watch icon; taps wrist | Patience x0.6; if food arrives inside half their food patience, +1 raw star | fast: `quick_lunch`; slow: their usual slow-food line | building |
| **Window seat**: always asks for the window | window icon | Prefers a free seat next to a window; +0.5 raw stars when they get one | `window_happy` | issue |
| **Dog walker**: brings a very good dog | paw icon; a dog sits by the chair (art) | Prefers outdoor seats (T8); +0.5 stars outdoors; leaves if only indoor seats and dogs-inside is off | `dog_happy` | issue |
| **Birthday table**: a party celebrating | balloon icon over the table | Party orders one extra dessert or drink if on the menu; booking-style review weight 2 when served well | `birthday` | issue |
| **Sweet tooth** | cupcake icon | Always adds a pastry when one is on the menu | `sweet` | issue |
| **Big eater** | double plate icon | Orders a second dish (one more ticket, one more sale) | `big_eater` | issue |
| **Indecisive** | question-mark icon | Takes twice as long to order (holds the server a little) | `indecisive` | issue |
| **Early bird** | sunrise icon | Only rolled in the first hour; patience x1.3 | (ordinary lines) | issue |
| **Maybe famous**: sunglasses indoors | sparkle icon | T7: the next hour's arrivals come 15% faster | `maybe_famous` | issue, needs T7 |
| **Critic in disguise** | notebook, hat, orders the dearest dish | Already built (#303): a weighted review | `critic_good`, `critic_bad` | built |

**Trade-offs (T4).** The Chatterbox holds a seat longer (fewer covers on a busy night) and the Lunch-breaker walks out sooner. That keeps quirks a little interesting to manage, never punishing.

**Showing them (T3, placeholder until art).** The inspect panel gets one plain line per quirk ("Takes a photo of every dish."). The day log notes the first of each quirk per day. The icon over the head reuses the regular-guest billboard (`regular_guest_indicator.gd`) with a short text glyph until the director draws icons.

## 4. Reviews and the paper

- **Review quotes.** Each quirk with a hook adds a group to `data/reviews/quotes.tres` (the `ReviewQuotes.CAUSES` list). A quirk group replaces the ordinary positive cause only when the score is 4 or 5 and no complaint was bigger, the same rule the cat and the waiting bench use. A bad visit still says what went wrong. Voice: short, warm, a little silly, under 90 characters, no real brands or people. First groups (6 lines each to start):
  - `photo_happy`: "Took forty photos of my soup. Ate it warm anyway."
  - `chatty_happy`: "Told the waiter my whole week. He laughed in all the right places."
  - `quick_lunch`: "In and out before my boss noticed. Delicious getaway."
- **Type-flavoured quotes (later).** Tourists and the office crowd use the ordinary groups for now. A later pass (issue) can add per-type variants such as "Best holiday meal yet. The gulls agreed." and "Lunch meeting ran long. Worth it."
- **Morning paper.** One brief per day at most, from yesterday's quirk tally, in the paper's notes: "A guest photographed every dish yesterday. Their phone needs a nap." (issue, with headline templates for big days, such as a birthday table or the maybe-famous guest).
- **Evening report.** The guest mix line already lists types by report name; tourists and the office crowd show up there automatically.

## 5. Data model

- `CustomerType` gains: `local_dish_bonus` (raw stars for a dish tagged `seafood` or with one of the lot's tags), `arrival_window_start` / `arrival_window_end` (shop-clock minutes; 0 and 0 means all day) and `off_window_weight` (the weight multiplier outside the window).
- `GuestQuirk` (`src/sim/customers/guest_quirk.gd`) and `GuestQuirkCatalogue` (`data/customers/quirks.tres`): id, inspect line, icon hint, weight, allowed types, and effect fields (`review_chance_override`, `linger_multiplier`, `patience_multiplier`, `review_bonus`, `fast_food_fraction` and `fast_food_bonus`, `review_cause`).
- `RestaurantSim` takes the active lot's mix and tags (`configure_lot_guests`; the home shop passes none) and a lazy `quirk_rng_provider` (the named `quirks` stream). With no provider no quirk ever appears.
- `CustomerAgent.quirk_id` and the quirk's effects, applied once when the guest is set up; `ReviewVisit.quirk_cause`, `local_dish_bonus` and `quirk_bonus` carry them to the review.

## 6. Determinism and saves

- The `customers` stream is never touched by quirks. At the home shop with quirks below their unlock, a seeded run is identical to today. Above the unlock, quirk effects change waits and reviews by design; the PR records the balance probe before and after.
- Nothing new is saved: types and quirks are authored data, and a guest's quirk lasts one visit (saves happen only at the morning autosave, when no guest is in the shop). Old saves load unchanged.

## 7. Filed as issues

See the issue links in the PR. In short: walkers, surfers, farmers, foragers (one issue each, Codex, once their lot or data exists); window seat, sweet tooth, big eater, indecisive and early bird quirks (Codex); dog walker and birthday table (need T8 and art, director); maybe famous (needs T7); quirk icons over heads (art, director); morning-paper quirk briefs and type-flavoured review quotes (writing, director).
