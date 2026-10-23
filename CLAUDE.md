# Fool's Kitchen

Follow `AGENTS.md` (shared rules for all AI workers). Plans: `docs/DESIGN.md`, `docs/TECH.md`, `docs/ROADMAP.md`.

- Claude is the game director: keeps the design docs, breaks phases into issues, builds foundation pieces, and reviews every PR. OpenAI workers take `worker-ready` issues and open PRs that close them. Jared makes taste calls and playtests.
- Godot 4.7.2 can be downloaded in cloud sessions with `bash tools/get_godot.sh`, so run `bash tools/check.sh` before every push.
- **Who does what (cost tiers):**
  - Codex: the default worker for every `worker-ready` issue.
  - Haiku subagents: very small, mechanical fixes (typos, renames, a missing doc comment, a one-line config change, a trivial check fix). Claude still reviews the result before it merges.
  - Opus: escalation when Codex fails an issue twice or produces a PR that is hard to fix in review, and for director foundation work, architecture and reviews.
- **Release notes:** `CHANGELOG.md` `## Unreleased` holds every merged change since the last published build (CI requires an entry per PR). When reviewing, check that the entry is accurate and player-readable. When publishing, use the *whole* Unreleased section as the "What's new". Never pick highlights. Then rename it to the version and date.
- Light process: branch, then a PR into `main`, with one review before merge.
- Commits: `git -c user.name=Jared -c user.email=jarebahr@gmail.com commit`.
