<div align="center">
  <img src="web/public/apple-touch-icon.png" alt="DEVKAT logo" width="160" />

  <h1>DEVKAT</h1>

  <p><strong>Strava for AI coding sessions.</strong></p>
  <p>Track your Claude, Codex, Cursor, and Pi work. Turn it into sharp, shareable stats.</p>

  <p>
    <a href="https://github.com/runnon/devkat/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/runnon/devkat?style=social"></a>
    <a href="https://github.com/runnon/devkat/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/runnon/devkat?label=release"></a>
    <a href="https://github.com/runnon/devkat/actions/workflows/gitleaks.yml"><img alt="Secret scan" src="https://github.com/runnon/devkat/actions/workflows/gitleaks.yml/badge.svg"></a>
  </p>
</div>

DEVKAT watches your AI coding tools, computes the stats that actually feel like a session, and gives you a place to browse, compare, and copy good-looking cards.

No terminal screenshots. No hand-written brag posts. No pastebin archaeology.

Just the session:

- **Duration**: active coding time
- **Volume**: lines added and removed
- **Pace**: lines changed per hour
- **Scope**: files touched
- **Burn**: tokens used
- **Source**: Claude, Codex, Cursor, Pi, or a merged multi-tool session

## Install

macOS users can install the background sync daemon with one command:

```sh
curl -fsSL https://raw.githubusercontent.com/runnon/devkat/main/scripts/install.sh | sh
```

Then log in when prompted. DEVKAT installs `devkat-push`, starts a lightweight `launchd` agent, and keeps your sessions synced automatically.

```sh
devkat-push --status
devkat-push --list
devkat-push --sync-all
```

## What It Does

DEVKAT has three pieces:

- **`devkat-push`**: a Swift CLI that runs locally on your Mac, parses AI coding session data, and syncs aggregate stats.
- **iOS app**: a native SwiftUI app for browsing sessions, leaderboards, and copy-ready overlays.
- **Web app**: a React/Vite version of the same dashboard and overlay composer.

The daemon scans:

- Claude Code transcripts in `~/.claude/projects`
- Codex state in `~/.codex`
- Cursor composer history
- Pi agent sessions in `~/.pi`

It merges overlapping work into coherent sessions, deduplicates re-syncs, and updates every five minutes plus on Claude, Codex, and Cursor activity.

## Privacy

DEVKAT is built for developer data to stay boring.

The local daemon sends aggregate metrics only: durations, line counts, token counts, file counts, source labels, models, repo aliases, and branch names. It does **not** upload your source code, prompts, responses, diffs, file contents, or raw transcripts.

Credentials are stored in the macOS keychain. Secret scanning runs in CI because this repository is public.

## Why

Developers already share what they shipped with AI. The artifact is usually a terminal screenshot, a messy thread, or a vague post.

DEVKAT makes the work legible:

- see which sessions were fast, deep, or expensive
- compare weekly volume and token burn
- copy cards that look native on X, LinkedIn, Discord, Slack, or wherever your team hangs out
- keep a local-first trail of how AI actually changes your development rhythm

## Develop

Clone the repo:

```sh
git clone https://github.com/runnon/devkat.git
cd devkat
```

Build and test the CLI:

```sh
cd devkat-cli
swift test
swift run devkat-push --list
```

Run the web app:

```sh
cd web
npm install
npm run dev
```

Open the iOS app:

```sh
open DEVKAT.xcodeproj
```

Local services use Supabase and PostHog. Start from `.env.example`, keep real values in `.env` or platform-specific local env files, and never commit secrets.

## Repo Map

```text
DEVKAT/        SwiftUI iOS app
devkat-cli/    Swift Package for the parser and devkat-push daemon
web/           React + Vite dashboard and overlay composer
supabase/      Database schema, RLS policies, and RPC migrations
scripts/       Install script and App Store preview tooling
```

## Contributing

Good contributions make DEVKAT more accurate, more private, or better looking.

Useful places to start:

- parser fixes for new Claude, Codex, Cursor, or Pi session formats
- tighter session merging and deduplication
- better overlay templates
- clearer onboarding and diagnostics
- privacy and security hardening

Before opening a PR, run the relevant checks:

```sh
cd devkat-cli && swift test
cd web && npm run build
```

## Star The Repo

If DEVKAT fits the way you work, star it. It helps other AI-heavy developers find the project, and it tells us which weird little tools are worth polishing next.
