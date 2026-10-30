#!/usr/bin/env python3
"""Manual issue247 matrix. One Godot at a time; scheduler reserves this clone.

Invoke directly with a pinned immutable source, private output directory and
Maintenance's engine reservation. No network, retries or CI entry point.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

SETUPS = ("default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor",
          "trays_2", "trays_4", "extra_cleaner", "expanded_tables", "coffee_shop",
          "bar", "fryer_coffee", "joined_tables", "grown", "neglected")
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|^\s*(?:ERROR|WARNING):|"
                    r"ObjectDB instances leaked|resources still in use", re.I | re.M)
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def fingerprint(root: Path) -> dict[str, str]:
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob("*")) if p.is_file()
            and not any(part in (".git", ".godot", ".tools", "__pycache__")
                        for part in p.relative_to(root).parts)}


def live_engines() -> list[dict]:
    found = []
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            exe = (p / "exe").resolve(strict=True)
            if "godot" not in exe.name.lower():
                continue
            state = (p / "stat").read_text().split(") ", 1)[1].split()[0]
            if state != "Z":
                found.append({"pid": int(p.name), "cwd": str((p / "cwd").resolve()),
                              "binary": str(exe)})
        except (OSError, ValueError):
            continue
    return found


def case_records(content: str, setup: str, days: int, status: int) -> list[dict]:
    records = [json.loads(line.split("PROBE_CASE ", 1)[1])
               for line in content.splitlines() if line.startswith("PROBE_CASE ")]
    if len(records) != 5 or {r["seed"] for r in records} != set(range(1, 6)):
        raise ValueError("Missing/duplicated case records in " + setup)
    if any(r["setup"] != setup or r["days"] != days for r in records):
        raise ValueError("Mismatched case identity")
    for record in records:
        if "error" in record:
            continue
        daily = record["stats"]["daily"]
        if [r["day"] for r in daily] != list(range(1, days + 1)):
            raise ValueError("Missing daily observation")
        if any(sum(r["ledger_categories"].values()) != r["ledger_cash_profit"] for r in daily):
            raise ValueError("Signed ledger does not reconcile")
        if sum(r["ledger_cash_profit"] for r in daily) != record["stats"]["profit"]:
            raise ValueError("Daily and historical profit differ")
    if status != (2 if any("error" in r for r in records) else 0):
        raise ValueError("Unexpected process exit status")
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--source", required=True)
    parser.add_argument("--arm", choices=("baseline", "feature"), required=True)
    parser.add_argument("--mode", choices=("controls", "matrix"), required=True)
    parser.add_argument("--resume", action="store_true",
                        help="Verify completed commands and continue a stopped matrix; never retry uncertain commands")
    parser.add_argument("--reservation", required=True,
                        help="Maintenance reservation description recorded in receipt")
    args = parser.parse_args()
    root = args.root.resolve()
    args.out.mkdir(parents=True, exist_ok=args.resume)
    if args.resume:
        if args.mode != "matrix":
            raise ValueError("Only matrices can resume")
        source_manifest = json.loads((args.out / "source-manifest.json").read_text())
        current = fingerprint(root)
        if any(current.get(k) != v for k, v in source_manifest.items()):
            raise ValueError("Original source changed; cannot resume")
        if any(not k.endswith((".uid", ".import")) for k in set(current) - set(source_manifest)):
            raise ValueError("New source files appeared; cannot resume")
    else:
        source_manifest = fingerprint(root)
        (args.out / "source-manifest.json").write_text(json.dumps(source_manifest, indent=2) + "\n")
    env = os.environ.copy()
    for name, subdir in (("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
                         ("XDG_DATA_HOME", "data"), ("TMPDIR", "tmp")):
        target = args.out.resolve() / "xdg" / subdir
        target.mkdir(parents=True, exist_ok=args.resume)
        env[name] = str(target)
    env["FK_PROBE_SHA"] = args.source
    receipt = {"source": args.source, "arm": args.arm, "root": str(root),
               "godot": str(args.godot.resolve()), "mode": args.mode,
               "reservation": args.reservation, "private_xdg": {k: env[k] for k in
               ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "TMPDIR")},
               "commands": [], "cases": []}
    if args.resume:
        prior_bytes = (args.out / "receipt.json").read_bytes()
        prior = json.loads(prior_bytes)
        for key in ("source", "arm", "root", "godot", "mode", "private_xdg"):
            if prior[key] != receipt[key]:
                raise ValueError("Resume identity mismatch: " + key)
        prior_hash = hashlib.sha256(prior_bytes).hexdigest()
        archive = args.out / ("receipt-before-resume-" + prior_hash + ".json")
        if not archive.exists():
            archive.write_bytes(prior_bytes)
        receipt = prior
        receipt.setdefault("resumptions", []).append({"epoch": time.time(),
            "prior_receipt_sha256": prior_hash, "reservation": args.reservation})
    completed = {}
    binary = str(args.godot.resolve())
    expected_commands = {"import": [binary, "--headless", "--path", str(root), "--import"]}
    for days in (5, 14):
        for setup in SETUPS:
            expected_commands[f"{setup}-{days}d"] = [binary, "--headless", "--path", str(root),
                "--script", "tools/balance_probe.gd", "--", f"--days={days}",
                "--seeds=1,2,3,4,5", f"--setup={setup}", "--daily=true"]
    logged_cases = {}
    for step in receipt["commands"]:
        label = step["label"]
        logpath = args.out / (label + ".log")
        if label in completed or "exit_code" not in step or step.get("engine_diagnostics") is not False \
                or step["exit_code"] not in (0, 2) or not logpath.is_file() \
                or hashlib.sha256(logpath.read_bytes()).hexdigest() != step.get("log_sha256"):
            raise ValueError("Uncertain or invalid previous command; inspect without retry: " + label)
        if label not in expected_commands or step.get("argv") != expected_commands[label]:
            raise ValueError("Unexpected previous command: " + label)
        content = ANSI.sub("", logpath.read_text(encoding="utf-8", errors="replace"))
        if ERRORS.search(content) or label == "import" and step["exit_code"] != 0:
            raise ValueError("Previous command failed: " + label)
        if label != "import":
            setup, window = label.rsplit("-", 1)
            for record in case_records(content, setup, int(window[:-1]), step["exit_code"]):
                logged_cases[record["setup"], record["days"], record["seed"]] = record
        completed[label] = step
    seen = set()
    for record in receipt["cases"]:
        identity = (record["setup"], record["days"], record["seed"])
        if identity in seen or logged_cases.get(identity) != record:
            raise ValueError("Previous case lacks unique completed-log evidence: " + str(identity))
        seen.add(identity)

    def save() -> None:
        (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def run(label: str, command: list[str]) -> tuple[int, str]:
        if label in completed:
            step = completed[label]
            if command != step["argv"]:
                raise ValueError("Previous command differs: " + label)
            content = ANSI.sub("", (args.out / (label + ".log")).read_text(errors="replace"))
            if ERRORS.search(content):
                raise ValueError("Previous command has diagnostics: " + label)
            print(json.dumps({"verified_previous": label, "exit_code": step["exit_code"]}), flush=True)
            return step["exit_code"], content
        if (args.out / (label + ".log")).exists():
            raise ValueError("Unreceipted log; inspect without retry: " + label)
        active = live_engines()
        if len(active) >= 4 or any(p["cwd"] == str(root) for p in active):
            raise RuntimeError("Engine scheduler preflight failed: " + json.dumps(active))
        step = {"label": label, "argv": command, "live_before": active,
                "started_epoch": time.time()}
        receipt["commands"].append(step)
        save()
        print(json.dumps({"starting": label, "arm": args.arm}), flush=True)
        logpath = args.out / (label + ".log")
        with logpath.open("xb") as log:
            child = subprocess.Popen(command, cwd=root, env=env, stdout=log,
                                     stderr=subprocess.STDOUT)
            step["pid"] = child.pid
            save()
            try:
                status = child.wait(timeout=1800)
            except subprocess.TimeoutExpired:
                child.terminate()
                try:
                    child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                status = 124
        content = ANSI.sub("", logpath.read_text(errors="replace"))
        step.update(exit_code=status, elapsed_seconds=time.time() - step["started_epoch"],
                    log_sha256=hashlib.sha256(logpath.read_bytes()).hexdigest(),
                    engine_diagnostics=bool(ERRORS.search(content)))
        save()
        print(json.dumps({"finished": label, "exit_code": status,
                          "seconds": step["elapsed_seconds"]}), flush=True)
        if step["engine_diagnostics"] or status == 124:
            raise RuntimeError("Engine diagnostics or timeout in " + label + "; no automatic retry")
        return status, content

    status, _ = run("import", [binary, "--headless", "--path", str(root), "--import"])
    if status:
        raise RuntimeError("Import failed")
    if args.mode == "controls":
        status, content = run("observer-controls", [binary, "--headless", "--path", str(root),
                                                    "--script", "tools/demand_probe_control.gd"])
        records = [json.loads(line.split("PROBE_OBSERVER_CONTROL ", 1)[1])
                   for line in content.splitlines() if line.startswith("PROBE_OBSERVER_CONTROL ")]
        receipt["controls"] = records
        receipt["passed"] = status == 0 and len(records) == 1 and records[0]["passed"]
    else:
        for days in (5, 14):
            for setup in SETUPS:
                status, content = run(f"{setup}-{days}d", [binary, "--headless", "--path", str(root),
                    "--script", "tools/balance_probe.gd", "--", f"--days={days}",
                    "--seeds=1,2,3,4,5", f"--setup={setup}", "--daily=true"])
                records = case_records(content, setup, days, status)
                for record in records:
                    identity = (record["setup"], record["days"], record["seed"])
                    previous = [r for r in receipt["cases"]
                                if (r["setup"], r["days"], r["seed"]) == identity]
                    if len(previous) > 1 or previous and previous[0] != record:
                        raise ValueError("Previous case conflicts with completed log: " + str(identity))
                    if not previous:
                        receipt["cases"].append(record)
                save()
        receipt["coverage"] = {"requested_cases": 150, "actual_cases": len(receipt["cases"]),
            "successful_cases": sum("stats" in r for r in receipt["cases"]),
            "failures": [r for r in receipt["cases"] if "error" in r],
            "requested_summary_rows": 180, "daily_records": sum(len(r.get("stats", {}).get("daily", []))
                                                               for r in receipt["cases"])}
        receipt["passed"] = len(receipt["cases"]) == 150
    # Godot import may generate UID/import sidecars; record these separately.
    final_manifest = fingerprint(root)
    receipt["original_source_unchanged"] = all(final_manifest.get(k) == v
                                                 for k, v in source_manifest.items())
    receipt["generated_files"] = sorted(set(final_manifest) - set(source_manifest))
    receipt["passed"] = receipt["passed"] and receipt["original_source_unchanged"]
    receipt["finished_epoch"] = time.time()
    save()
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
