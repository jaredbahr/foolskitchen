# Restock budget warning (#177)

The warning is advice in the existing Build hint. It never changes a placement
check, cash, stock, paid orders, random state or saves. The player can proceed.

## Seed survey

`expanded_restock_survey.gd` runs the original expanded-shop invariant scenario
with seeds 1–50, retaining its assertions. The five-day scenario spends $115 on
a wing and table, and reloads before day 3. Baseline: accepted main
`65d84b2df7aaee70c3acbcdae6dc6e6d01423025`.

Only seed 41 starved: day 5 had $71 before a $75 full reorder, a $4 shortage,
leaving four tomatoes unbought. The other 49 seeds had no cash shortage. All 50
completed, with zero engine errors and zero non-restock invariant failures.
The original tomato assertion for seed 41 remains recorded in
`restock-seed-survey.json`; no test assertion was removed or weakened.

## Integrated validation

Runtime source: `b2257620d09fca0bcbb2991e95f06f91b25e5e3c`, including accepted
main `4f8d14c08d0f06f6b2e24b2579e7b760c91c8d47` (the final back-door fixes).

- `bash tools/check.sh`: 492 scripts parsed, 1,497 tests passed, zero failed.
- Six focused warning tests cover threshold equality, successful real floor
  and item purchases below reserve, immediate cash-change hint refresh,
  enabled targets, the closing forecast and real prepaid incoming orders.
- Paired production `BalanceProbeCore.run_case` calls: default and
  expanded_tables, seeds 1–5 and 41, five days each. All statistics are
  byte-identical to accepted main. Both complete JSON reports have SHA-256
  `8e2d3898cc2b32bd17085639af8cc524a0796fad93b8e33712288b8deb541366`.
- Native Compatibility capture: real five-cell floor preview, $150 cash,
  $75 price, $75 remaining and $93 estimated reserve. The warning is visible,
  placement remains allowed and there are zero engine errors. Reproduce with
  `godot --path . --rendering-method gl_compatibility --script tools/restock_warning_shot.gd -- --out=<fresh-directory>`.
  The existing visual-review job uploads this feature capture and its metadata;
  generated images are not shipped in the repository.

## Estimate limits

Morning advice conservatively allows for refilling enabled targets after
service. Closing advice reuses the next-morning expiry and incoming-order
forecast. Both reuse current storage capacity, prices and the once-per-order
premium. This is a restock allowance, not a forecast of sales, wages or future
losses. In particular, the original $115 day-one expansion leaves $185, above
the $93 allowance; the warning does not predict seed 41's later trading losses.

Rules 9/10/11: held. No additional save, workflow loop or job, or raw internal
names in player text. One feature capture is added to the existing visual job.
