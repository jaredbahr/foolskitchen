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

Safety: refuses files whose resolved path or any parent folder looks like a
secret (.env, keys, credentials, ...), binary files, and any input that
contains the value of an environment variable named like *_KEY / *_TOKEN /
*_SECRET / *PASSWORD*. Input is capped at --max-bytes (400 KB).

Exit codes: 0 ok, 1 bad arguments or refused input, 2 API or network error,
3 the answer was cut off at --max-tokens.
Token usage goes to stderr so stdout stays clean for piping.
"""

from __future__ import annotations

import argparse
import fnmatch
import http.client
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
MODELS = {"flash": "deepseek-flash", "pro": "deepseek-v4-pro"}
DEFAULT_MAX_BYTES = 400_000  # guard against sending a whole tree by accident
RETRY_STATUS = {429, 500, 502, 503, 504}
MAX_ATTEMPTS = 4
MAX_TIMEOUT_ATTEMPTS = 2  # a timed-out call may still be billed; don't repeat it often

# Never send a path whose own name or any parent folder matches these.
SECRET_PATTERNS = [
    ".env", ".env.*", ".envrc", ".netrc", ".npmrc", ".pypirc", ".git-credentials",
    "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.jks", "*.tfvars", "*.tfstate",
    "id_rsa*", "id_ecdsa*", "id_ed25519*", ".ssh", ".aws", ".gnupg", ".docker",
    # Name shapes of secret files, not every name with "secret" in it: game code has
    # secret rooms (scripts/world/secret_*.gd must stay sendable).
    "*credentials*", "secret", "secrets", "secret.*", "secrets.*", "*client_secret*",
    "password*", "passwords*", "token", "token.*", "*_token.*", "tokens.*",
    "export_credentials.cfg",
]
SECRET_ENV = re.compile(r"(_KEY|_TOKEN|_SECRET|PASSWORD|_PAT)$|^(API_KEY|TOKEN)$", re.I)

SYSTEM_PROMPT = """You are a careful senior engineer doing one delegated subtask for a lead engineer who will review your work.
- Do exactly what is asked; no extra features, no unrelated refactors.
- When asked for code, return complete files (not fragments) in fenced code blocks with a language tag, one block per file, and put the file path on the line before each block.
- Match the style and conventions of the files you are given.
- Never invent APIs, functions or files you were not shown. If something is unclear or you are unsure an API exists, say so briefly instead of guessing.
- Keep prose short."""


def fail(msg: str, code: int = 1) -> None:
    print(f"deepseek: {msg}", file=sys.stderr)
    sys.exit(code)


def secret_values() -> list[str]:
    return [v for k, v in os.environ.items() if SECRET_ENV.search(k) and len(v) >= 12]


def check_text(label: str, text: str, secrets: list[str]) -> None:
    for value in secrets:
        if value in text:
            fail(f"refusing to send {label}: it contains the value of a secret environment variable")


def check_path(raw: str) -> Path:
    path = Path(raw)
    if not path.is_file():
        fail(f"no such file: {raw}")
    parts = [p.lower() for p in path.parts] + [p.lower() for p in path.resolve().parts]
    for part in parts:
        if any(fnmatch.fnmatch(part, pat) for pat in SECRET_PATTERNS):
            fail(f"refusing to send {raw}: '{part}' looks like a secret")
    return path


def read_input_file(raw: str, budget: int, secrets: list[str]) -> str:
    path = check_path(raw)
    if path.stat().st_size > budget:
        fail(f"input over the byte cap at {raw}; send less or raise --max-bytes")
    data = path.read_bytes()
    if b"\0" in data:
        fail(f"refusing to send {raw}: looks binary")
    text = data.decode("utf-8", errors="replace")
    check_text(raw, text, secrets)
    return text


def build_user_message(task: str, files: list[str], max_bytes: int, secrets: list[str]) -> str:
    parts = [task.strip()]
    total = len(task.encode())
    for raw in files:
        text = read_input_file(raw, max_bytes - total, secrets)
        total += len(text.encode())
        lang = Path(raw).suffix.lstrip(".") or "text"
        parts.append(f"{raw}\n```{lang}\n{text.rstrip()}\n```")
    if total > max_bytes:
        fail(f"input over {max_bytes} bytes; send less or raise --max-bytes")
    return "\n\n".join(parts)


def extract_code(answer: str) -> str | None:
    # Fences only count at the start of a line, so inline ``` in prose or code is ignored.
    blocks = re.findall(r"^```[^\n`]*\n(.*?)^```[ \t]*$", answer, flags=re.S | re.M)
    if not blocks:
        return None
    if len(blocks) > 1:
        print(f"deepseek: {len(blocks)} code blocks, joined", file=sys.stderr)
    return "".join(b if b.endswith("\n") else b + "\n" for b in blocks)


def call_api(payload: dict, timeout: int) -> dict:
    key = os.environ.get("DEEPSEEK_API_KEY") or "proxy-injected"  # the cloud proxy overwrites the header
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    delay, timeouts = 2, 0
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                fail(f"response was not JSON: {raw[:200]!r}", 2)
            if not isinstance(data, dict) or not data.get("choices"):
                fail(f"unexpected response: {str(data)[:300]}", 2)
            return data
        except urllib.error.HTTPError as err:
            body = err.read().decode(errors="replace")[:500]
            if err.code not in RETRY_STATUS or attempt == MAX_ATTEMPTS:
                fail(f"HTTP {err.code}: {body}", 2)
            reason = f"HTTP {err.code}"
        except (TimeoutError, socket.timeout) as err:
            timeouts += 1
            if timeouts >= MAX_TIMEOUT_ATTEMPTS or attempt == MAX_ATTEMPTS:
                fail(f"timed out after {timeout}s ({err}); try a smaller task or --timeout", 2)
            reason = "timeout"
        except (urllib.error.URLError, ConnectionError, http.client.HTTPException) as err:
            if attempt == MAX_ATTEMPTS:
                fail(f"network error: {err}", 2)
            reason = f"network error ({err})"
        print(f"deepseek: {reason}, retrying in {delay}s", file=sys.stderr)
        time.sleep(delay)
        delay *= 2
    fail("gave up", 2)
    return {}


def read_stdin() -> str:
    if sys.stdin.isatty():
        fail("stdin is a terminal; pipe the input in")
    return sys.stdin.buffer.read().decode("utf-8", errors="replace")


def emit(output: str, out: str | None) -> None:
    if out:
        try:
            Path(out).write_text(output, encoding="utf-8")
            print(f"deepseek: wrote {out}", file=sys.stderr)
            return
        except OSError as err:
            print(f"deepseek: could not write {out} ({err}); printing instead", file=sys.stderr)
    sys.stdout.write(output if output.endswith("\n") else output + "\n")


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # Windows consoles default to cp1252
        except (AttributeError, ValueError):
            pass

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

    if args.task == "-" and args.stdin:
        fail("use either a '-' task or --stdin, not both")
    if args.out and not Path(args.out).resolve().parent.is_dir():
        fail(f"--out folder does not exist: {Path(args.out).parent}")

    secrets = secret_values()
    task = read_stdin() if args.task == "-" else args.task
    if args.stdin:
        task += "\n\nInput:\n```\n" + read_stdin().rstrip() + "\n```"
    if not task.strip():
        fail("empty task")
    check_text("the task", task, secrets)

    system = SYSTEM_PROMPT
    extra = args.system
    if args.system_file:
        extra += "\n" + read_input_file(args.system_file, args.max_bytes, secrets)
    check_text("the system text", extra, secrets)
    if extra.strip():
        system += "\n\nProject rules:\n" + extra.strip()

    payload: dict = {
        "model": MODELS[args.model],
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": build_user_message(task, args.file, args.max_bytes, secrets)},
        ],
        "max_tokens": args.max_tokens,
    }
    if args.effort == "off":
        payload["thinking"] = {"type": "disabled"}
    else:
        payload["reasoning_effort"] = args.effort

    if args.dry_run:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return

    start = time.monotonic()
    data = call_api(payload, args.timeout)
    choice = data["choices"][0] or {}
    answer = (choice.get("message") or {}).get("content") or ""
    usage = data.get("usage") or {}
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
    emit(output, args.out)

    if choice.get("finish_reason") == "length":
        print("deepseek: answer cut off at --max-tokens", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
