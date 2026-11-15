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

## Work routing: save Claude usage for what needs it (Jared, 2026-11-15)

Claude usage is the scarce resource across all four of Jared's games. Spend it on complex writing, hard problems and
art; push everything else down a tier. Any agent working here, Claude or not, follows this.

- **DeepSeek takes the grunt work, and it is the default for anything trivial.** Before doing a mechanical task
  yourself, hand it to DeepSeek: boilerplate, test scaffolds, repetitive wiring, data and config edits, renames, log,
  diff and CI summaries, first drafts of docs or comments. Run `python3 tools/deepseek.py "<brief>" -f <files>
  [--code --out F]` (`--help` for the rest). Brief it like an issue: the files, the rules, what done looks like. It
  never touches the repo, so you read its output, apply it, run the checks and own the result. Never use it for art,
  story or player-facing words, feel or design, or judgment calls, and never send it secrets. In cloud sessions the
  proxy adds the key; elsewhere set `DEEPSEEK_API_KEY`.
- **Codex takes the middle ground.** Well-specified, testable work that needs a real PR but no taste call becomes an
  issue for Codex (labelled `codex` plus `worker-ready`). Keep its queue stocked with such issues, written with the
  files to read, Do, Don't and Done when. Codex works only the issues assigned to it: it reviews the open issues for
  its own and does not pick up anything else. Review its PRs like any other.
- **Claude keeps complex writing, hard problems and art:** architecture, deep bugs, story and dialogue, art direction
  and judgment, design questions for Jared, reviews and merges. Prefer DeepSeek over a Sonnet or Haiku subagent for
  anything it can do from the files you send it; keep subagents for mechanical work that needs the repo itself.

Rule of thumb: if it can be fully specified in a paragraph and checked by running something, it is DeepSeek's (one
shot) or Codex's (a PR). If it needs taste, the story, or deep reasoning, it is Claude's.
