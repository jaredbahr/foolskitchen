# Fool's Kitchen

[![Checks](https://github.com/jaredbahr/foolskitchen/actions/workflows/check.yml/badge.svg)](https://github.com/jaredbahr/foolskitchen/actions/workflows/check.yml)

A low-poly 3D restaurant tycoon game (Godot 4). You run a restaurant: staff and customers act on their own, you design the place and set the menu, and you grow from a food cart to several properties. Optional mini-games give bonuses.

- Design: [docs/DESIGN.md](docs/DESIGN.md)
- TasteMaker audit: [docs/research/TASTEMAKER_AUDIT.md](docs/research/TASTEMAKER_AUDIT.md)
- Tech plan: [docs/TECH.md](docs/TECH.md)
- Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)
- What's new: [CHANGELOG.md](CHANGELOG.md)
- AI worker rules: [AGENTS.md](AGENTS.md)
- Tasks: GitHub issues (template in `.github/ISSUE_TEMPLATE/task.md`)

## Play a build
- **Get it:** open [Actions → Build](https://github.com/jaredbahr/foolskitchen/actions/workflows/build.yml), pick the latest green run (or click **Run workflow**), and download the `FoolsKitchen-…` artifact. Published versions are on the [Releases](https://github.com/jaredbahr/foolskitchen/releases) page.
- **Windows:** unzip `FoolsKitchen-windows.zip` and run `FoolsKitchen.exe`. It's unsigned, so Windows SmartScreen may warn the first time: **More info → Run anyway**.
- **Web:** unzip `FoolsKitchen-web.zip` and serve the folder (for example `python -m http.server` inside it), then open `http://localhost:8000`. Opening `index.html` straight from disk doesn't work in browsers.
- Saves live in the browser (web) or in `%APPDATA%\Godot\app_userdata\Fool's Kitchen` (Windows). **F10** starts a new game.

## Make a build
`bash tools/get_godot.sh && bash tools/get_export_templates.sh && bash tools/export.sh` (writes `export/FoolsKitchen-windows.zip` and `export/FoolsKitchen-web.zip`). To publish: rename `## Unreleased` in `CHANGELOG.md` to `## vX.Y.Z (date)`, merge, then push the tag `vX.Y.Z`. The release notes are that whole section, word for word.
