# Fool's Kitchen

Follow `AGENTS.md` (shared rules for all AI workers). Plans: `docs/DESIGN.md`, `docs/TECH.md`, `docs/ROADMAP.md`.

- Claude is the game director and the builder: keeps the design docs, breaks phases into issues, and builds them with Claude subagents. Every PR gets an independent review before merge. Jared makes taste calls and playtests.
- Godot 4.7.2 can be downloaded in cloud sessions with `bash tools/get_godot.sh`, so run `bash tools/check.sh` before every push.
- **Who does what (cost tiers):** Codex is no longer on the project (Jared, 2026-11-05).
  - Sonnet subagents: the default builder for issues, each in its own worktree from `main`, plus independent read-only reviews.
  - Haiku subagents: very small, mechanical fixes (typos, renames, a missing doc comment, a one-line config change, a trivial check fix). Claude still reviews the result before it merges.
  - Opus: hard problems (movement, architecture, deep bugs), foundation work and final review calls.
  - Several issues can be built in parallel, each on its own `claude/...` branch and PR.
- **Release notes:** `CHANGELOG.md` `## Unreleased` holds every merged change since the last published build (CI requires an entry per PR). When reviewing, check that the entry is accurate and player-readable. When publishing, use the *whole* Unreleased section as the "What's new". Never pick highlights. Then rename it to the version and date.
- Light process: branch, then a PR into `main`, with one review before merge.
- Commits: `git -c user.name=Jared -c user.email=jarebahr@gmail.com commit`.
