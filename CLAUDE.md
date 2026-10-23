# Fool's Kitchen

Follow `AGENTS.md` (shared rules for all AI workers). Plans: `docs/DESIGN.md`, `docs/TECH.md`, `docs/ROADMAP.md`.

- Claude is the game director: keeps the design docs, breaks phases into issues, builds foundation pieces, and reviews every PR. OpenAI workers take `worker-ready` issues and open PRs that close them. Jared makes taste calls and playtests.
- Godot 4.7.2 can be downloaded in cloud sessions with `bash tools/get_godot.sh`, so run `bash tools/check.sh` before every push.
- Light process: branch, then a PR into `main`, with one review before merge.
- Commits: `git -c user.name=Jared -c user.email=jarebahr@gmail.com commit`.
