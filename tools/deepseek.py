#!/usr/bin/env python3
"""Send one delegated task to DeepSeek and print the answer.

A one-shot helper so Claude Code (or anyone) can hand grunt work to DeepSeek
without a harness: boilerplate, test scaffolds, log or diff summaries, data
edits, first drafts of docs. DeepSeek sees only what you send; it never touches
the repo. Review, apply and verify its output yourself.

Usage:
    python3 tools/deepseek.py "Write a GDScript test that ..." -f scripts/a.gd -f tests/b_test.gd
    git diff main | python3 tools/deepseek.py "Summarise this diff in 5 bullets" --stdin
    python3 tools/deepseek.py - < brief.md             # the whole task from stdin
    python3 tools/deepseek.py "..." -f x.gd --code --out /tmp/x_test.gd
    python3 tools/deepseek.py "..." -f x.gd --dry-run      # show what would be sent

Key:
    In Claude Code cloud sessions the network proxy injects the key for
    api.deepseek.com, so nothing needs setting. Elsewhere, set DEEPSEEK_API_KEY.
    Never commit a key.

Options worth knowing:
    --model flash|pro      flash (default) is cheap and fast; pro for harder tasks.
    --effort off|low|high|max
                           reasoning budget. off = no thinking (quickest);
                           default high is the API's own default.
    --code                 print only the fenced code block(s) from the answer.
    --system / -S FILE     extra instructions (house rules, style).

Exit codes: 0 ok, 1 bad arguments or refused input, 2 API or network error,
3 the answer was cut off at --max-tokens.
Token usage goes to stderr so stdout stays clean for piping.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
MODELS = {"flash": "deepseek-flash", "pro": "deepseek-v4-pro"}
DEFAULT_MAX_BYTES = 400_000  # guard against sending a whole tree by accident
RETRY_STATUS = {429, 500, 502, 503, 504}

# Never send these, whatever the caller asks.
SECRET_PATTERNS = [
    ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "id_rsa*", "id_ed25519*",
    "*credentials*", "*secret*", "*.keystore", "export_credentials.cfg",
]

SYSTEM_PROMPT = """You are a careful senior engineer doing one delegated subtask for a lead engineer who will review your work.
- Do exactly what is asked; no extra features, no unrelated refactors.
- When asked for code, return complete files (not fragments) in fenced code blocks with a language tag, one block per file, and put the file path on the line before each block.
- Match the style and conventions of the files you are given.
- Never invent APIs, functions or files you were not shown. If something is unclear or you are unsure an API exists, say so briefly instead of guessing.
- Keep prose short."""


def refuse_secret(path: Path) -> bool:
    name = path.name.lower()
    return any(fnmatch.fnmatch(name, pat) for pat in SECRET_PATTERNS)


def build_user_message(task: str, files: list[str], max_bytes: int) -> str:
    parts = [task.strip()]
    total = len(task.encode())
    for raw in files:
        path = Path(raw)
        if refuse_secret(path):
            sys.exit(f"deepseek: refusing to send {raw}: looks like a secret")
        if not path.is_file():
            sys.exit(f"deepseek: no such file: {raw}")
        text = path.read_text(encoding="utf-8", errors="replace")
        total += len(text.encode())
        if total > max_bytes:
            sys.exit(f"deepseek: input over {max_bytes} bytes at {raw}; send less or raise --max-bytes")
        lang = path.suffix.lstrip(".") or "text"
        parts.append(f"{raw}\n```{lang}\n{text.rstrip()}\n```")
    return "\n\n".join(parts)


def extract_code(answer: str) -> str | None:
    blocks = re.findall(r"```[^\n]*\n(.*?)```", answer, flags=re.S)
    if not blocks:
        return None
    if len(blocks) > 1:
        print(f"deepseek: {len(blocks)} code blocks, joined", file=sys.stderr)
    return "\n".join(b.rstrip("\n") + "\n" for b in blocks)


def call_api(payload: dict, timeout: int) -> dict:
    key = os.environ.get("DEEPSEEK_API_KEY") or "proxy-injected"  # proxy overwrites the header
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    delay = 2
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            body = err.read().decode(errors="replace")[:500]
            if err.code in RETRY_STATUS and attempt < 4:
                print(f"deepseek: HTTP {err.code}, retrying in {delay}s", file=sys.stderr)
            else:
                print(f"deepseek: HTTP {err.code}: {body}", file=sys.stderr)
                sys.exit(2)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as err:
            if attempt == 4:
                print(f"deepseek: network error: {err}", file=sys.stderr)
                sys.exit(2)
            print(f"deepseek: network error ({err}), retrying in {delay}s", file=sys.stderr)
        time.sleep(delay)
        delay *= 2
    sys.exit(2)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", help="the task; '-' reads it from stdin")
    ap.add_argument("--stdin", action="store_true", help="append stdin to the task as input (logs, diffs)")
    ap.add_argument("-f", "--file", action="append", default=[], help="file to include (repeatable)")
    ap.add_argument("--system", default="", help="extra system instructions")
    ap.add_argument("-S", "--system-file", help="read extra system instructions from a file")
    ap.add_argument("--model", choices=sorted(MODELS), default="flash")
    ap.add_argument("--effort", choices=["off", "low", "high", "max"], default="high")
    ap.add_argument("--max-tokens", type=int, default=32_000)
    ap.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    ap.add_argument("--timeout", type=int, default=600, help="seconds per request")
    ap.add_argument("--code", action="store_true", help="print only fenced code from the answer")
    ap.add_argument("--out", help="write the answer (or code) to this file instead of stdout")
    ap.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    args = ap.parse_args()

    task = sys.stdin.read() if args.task == "-" else args.task
    if args.stdin and args.task != "-":
        task += "\n\nInput:\n```\n" + sys.stdin.read().rstrip() + "\n```"
    if not task.strip():
        sys.exit("deepseek: empty task")

    system = SYSTEM_PROMPT
    extra = args.system
    if args.system_file:
        extra += "\n" + Path(args.system_file).read_text(encoding="utf-8")
    if extra.strip():
        system += "\n\nProject rules:\n" + extra.strip()

    payload: dict = {
        "model": MODELS[args.model],
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": build_user_message(task, args.file, args.max_bytes)},
        ],
        "max_tokens": args.max_tokens,
    }
    if args.effort == "off":
        payload["thinking"] = {"type": "disabled"}
    else:
        payload["reasoning_effort"] = args.effort

    if args.dry_run:
        print(json.dumps(payload, indent=2))
        return

    start = time.monotonic()
    data = call_api(payload, args.timeout)
    choice = data["choices"][0]
    answer = choice["message"].get("content") or ""
    usage = data.get("usage", {})
    reasoning = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    print(
        f"deepseek: {data.get('model')} in={usage.get('prompt_tokens')} "
        f"(cached {usage.get('prompt_cache_hit_tokens', 0)}) out={usage.get('completion_tokens')} "
        f"(reasoning {reasoning}) {time.monotonic() - start:.1f}s",
        file=sys.stderr,
    )

    output = answer
    if args.code:
        code = extract_code(answer)
        if code is None:
            print("deepseek: no code block in the answer; printing it whole", file=sys.stderr)
        else:
            output = code
    if args.out:
        Path(args.out).write_text(output, encoding="utf-8")
        print(f"deepseek: wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(output if output.endswith("\n") else output + "\n")

    if choice.get("finish_reason") == "length":
        print("deepseek: answer cut off at --max-tokens", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
