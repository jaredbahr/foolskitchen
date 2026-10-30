#!/usr/bin/env python3
"""Render actual issue247 receipts; failures and unrecorded accounting stay visible."""
from __future__ import annotations
import argparse
import csv
import json
import math
from pathlib import Path
from statistics import mean

SETUPS = ("default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor",
          "trays_2", "trays_4", "extra_cleaner", "expanded_tables", "coffee_shop", "bar",
          "fryer_coffee", "joined_tables", "grown", "neglected")
COLUMNS = ("arrivals", "served", "lost", "sales", "wages", "rent", "ingredients", "profit",
           "cash", "owner_xp", "owner_level")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--feature", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    arms = {"baseline": json.loads(args.baseline.read_text())}
    if args.feature:
        arms["feature"] = json.loads(args.feature.read_text())
    lines = ["# Actual demand probe measurements", "",
             "Historical profit is all signed Ledger cash movements, including upgrades, milestone bonuses and financing. "
             "Purchase-based report operating profit is separate. Consumed-food operating profit, sold-food purchase cost, "
             "spoilage value and inventory purchase value are not recorded; combined target pending #255.", "",
             "Grown uses free expanded tables, coffee machine and storage; five real enabled cookable dishes. "
             "Stock and running costs are paid. Neglected uses ordinary 2× standard prices and organic reviews. "
             "Trays4 failure is retained: $207 after initial stock cannot cover $210 in upgrades. No cash grant.", ""]
    indexed = {}
    integrity = {}
    for arm, receipt in arms.items():
        cases = {(r["setup"], r["days"], r["seed"]): r for r in receipt["cases"]}
        expected = {(setup, days, seed) for setup in SETUPS for days in (5, 14) for seed in range(1, 6)}
        if len(receipt["cases"]) != 150 or len(cases) != 150 or set(cases) != expected:
            raise ValueError(f"{arm}: need exactly150 unique requested case results")
        indexed[arm] = cases
        prefixes = []
        for setup in SETUPS:
            for seed in range(1, 6):
                short, long = cases[setup, 5, seed], cases[setup, 14, seed]
                if "stats" in short and "stats" in long:
                    prefixes.append({"setup": setup, "seed": seed,
                                     "equal": short["stats"]["daily"] == long["stats"]["daily"][:5]})
        failures = [r for r in receipt["cases"] if "error" in r]
        integrity[arm] = {"source": receipt["source"], "case_results": len(cases),
            "successful_cases": len(cases) - len(failures), "failures": failures,
            "prefix_comparisons": prefixes, "all_observed_prefixes_equal": all(r["equal"] for r in prefixes),
            "original_source_unchanged": receipt.get("original_source_unchanged"),
            "consumed_food_target": "pending #255; no substituted metric"}
        lines.extend([f"## {arm}: {receipt['source']}", "",
                      f"{len(cases)} requested case results; {len(cases) - len(failures)} successful, "
                      f"{len(failures)} explicit failures. No derived/reused runs.", ""])
        for days in (5, 14):
            lines.extend([f"### {days} days", "",
                "| Setup | Seed | Arrivals | Served | Lost | Sales | Wages | Rent | Ingredients | Cash profit | Ending cash | Owner XP | Level |",
                "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"])
            for setup in SETUPS:
                rows = []
                for seed in range(1, 6):
                    case = cases[setup, days, seed]
                    if "error" in case:
                        lines.append(f"| {setup} | {seed} | FAILED: {case['error']} |" + " — |" * 10)
                    else:
                        row = case["stats"]
                        rows.append(row)
                        lines.append("| " + " | ".join([setup, str(seed)] + [str(row[k]) for k in COLUMNS]) + " |")
                if len(rows) == 5:
                    lines.append("| " + " | ".join([setup, "mean"] + [f"{mean(r[k] for r in rows):.1f}" for k in COLUMNS]) + " |")
                else:
                    lines.append(f"| {setup} | mean | UNAVAILABLE: {len(rows)}/5 successful |" + " — |" * 10)
            lines.append("")
        with (args.out / f"{arm}-daily.csv").open("w", newline="") as output:
            fields = ["source", "setup", "window", "seed", "day", "arrivals", "served", "lost",
                      "ledger_cash_profit", "cash", "purchase_based_operating_profit",
                      "demand_status", "demand_total", "consumed_food_status", "ledger_categories"]
            writer = csv.DictWriter(output, fieldnames=fields)
            writer.writeheader()
            for (setup, days, seed), case in cases.items():
                for day in case.get("stats", {}).get("daily", []):
                    demand = day["current_demand"]
                    row = {k: day[k] for k in fields if k in day}
                    row.update(source=receipt["source"], setup=setup, window=days, seed=seed,
                        demand_status=demand["status"], demand_total=demand.get("snapshot", {}).get("total", "unavailable"),
                        ledger_categories=json.dumps(day["ledger_categories"], sort_keys=True))
                    writer.writerow(row)
    targets = {"combined_consumed_food_operating_profit": "pending #255"}
    if "feature" in indexed:
        def stats(arm: str, setup: str, days: int) -> list[dict]:
            selected = [indexed[arm][setup, days, seed] for seed in range(1, 6)]
            if any("error" in r for r in selected):
                raise ValueError(f"Target setup failed: {arm}/{setup}/{days}")
            return [r["stats"] for r in selected]
        baseline5 = mean(r["profit"] for r in stats("baseline", "default", 5))
        feature5 = mean(r["profit"] for r in stats("feature", "default", 5))
        targets["default5_cash_profit"] = {"baseline_mean": baseline5, "feature_mean": feature5,
            "relative_change": (feature5 - baseline5) / baseline5 if baseline5 > 0 else None,
            "passed": abs(feature5 - baseline5) <= baseline5 * .25 if baseline5 > 0 else None}
        default14 = stats("feature", "default", 14)
        early = mean(day["ledger_cash_profit"] for r in default14 for day in r["daily"] if day["day"] <= 2)
        late = mean(day["ledger_cash_profit"] for r in default14 for day in r["daily"] if day["day"] >= 12)
        targets["default14_daily_cash_profit"] = {"early_days1_2_mean": early, "late_days12_14_mean": late,
            "ratio": late / early if early > 0 else None, "passed": late >= 2 * early if early > 0 else None}
        default_total = mean(r["profit"] for r in default14)
        for setup in ("expanded_tables", "grown"):
            total = mean(r["profit"] for r in stats("feature", setup, 14))
            targets[setup + "14_cash_profit"] = {"default_mean": default_total, "setup_mean": total,
                "ratio": total / default_total if default_total > 0 else None,
                "passed": total >= 1.3 * default_total if default_total > 0 else None}
        demand_days = []
        unavailable = []
        for seed, row in enumerate(stats("feature", "neglected", 14), 1):
            daily = row["daily"]
            if [day["day"] for day in daily] != list(range(1, 15)):
                unavailable.append({"seed": seed, "reason": "missing or duplicated daily observations"})
            for day in daily:
                demand = day["current_demand"]
                factor = demand.get("snapshot", {}).get("total")
                if demand.get("status") != "available" or isinstance(factor, bool) \
                        or not isinstance(factor, (float, int)) or not math.isfinite(factor) or factor <= 0:
                    unavailable.append({"seed": seed, "day": day["day"],
                                        "reason": "unavailable or invalid demand factor"})
                else:
                    demand_days.append({"day": day["day"], "factor": factor})
        complete = not unavailable and len(demand_days) == 70
        windows = {day: mean(r["factor"] for r in demand_days if r["day"] == day)
                   for day in range(1, 15)} if complete else {}
        targets["neglected14_actual_demand"] = {"daily_seed_means": windows,
            "status": "available" if complete else "unavailable: need all70 valid demand observations",
            "valid_observations": len(demand_days), "unavailable_observations": unavailable,
            "minimum_daily_mean": min(windows.values()) if windows else None,
            "below1_days": [d for d, factor in windows.items() if factor < 1],
            "passed": any(factor < 1 for factor in windows.values()) if windows else None}
    lines.extend(["## Target results", "", "```json", json.dumps(targets, indent=2), "```", ""])
    (args.out / "REPORT.md").write_text("\n".join(lines))
    (args.out / "results.json").write_text(json.dumps({"integrity": integrity, "targets": targets}, indent=2) + "\n")


if __name__ == "__main__":
    main()
