# Fool's Kitchen

Follow `AGENTS.md` (shared rules for all AI workers). Plans: `docs/DESIGN.md`, `docs/TECH.md`, `docs/ROADMAP.md`.

- Claude is the game director: keeps the design docs, breaks phases into issues, reviews every PR, and builds director-scoped work (movement, art, taste calls) with Claude subagents. Jared makes taste calls and playtests.
- Godot 4.7.2 can be downloaded in cloud sessions with `bash tools/get_godot.sh`, so run `bash tools/check.sh` before every push.
- **Who does what (cost tiers):** Codex is back on the project (Jared, 2026-11-07).
  - Codex: the default worker for every `worker-ready` issue, taken in the order of `docs/ROADMAP.md` "Up next". Jared points Codex at the repo; Codex follows `AGENTS.md`.
  - Sonnet subagents: director-scoped issues (no `worker-ready` label) and independent read-only reviews of every PR, Codex's included.
  - Haiku subagents: very small, mechanical fixes (typos, renames, a missing doc comment, a one-line config change, a trivial check fix). Claude still reviews the result before it merges.
  - Opus: hard problems (movement, architecture, deep bugs), foundation work, escalation when Codex fails an issue twice, and final review calls.
  - Label every open issue with one owner: `codex` (clear brief, testable sim or UI work), `both` (Codex may try; harder, review closely, take over after two failed tries) or `claude` (movement, art, taste or design calls, unscoped backlog; Codex never starts it). Codex issues also need `worker-ready`. An issue without `worker-ready` stays with the director. Write new Codex issues from `.github/ISSUE_TEMPLATE/task.md`: Phase, Depends on, Context (files to read), Do, Don't, Done when.
- **Release notes:** `CHANGELOG.md` `## Unreleased` holds every merged change since the last published build (CI requires an entry per PR). When reviewing, check that the entry is accurate and player-readable. When publishing, use the *whole* Unreleased section as the "What's new". Never pick highlights. Then rename it to the version and date.
- Light process: branch, then a PR into `main`, with one review before merge.
- Commits: `git -c user.name=Jared -c user.email=jarebahr@gmail.com commit`.
