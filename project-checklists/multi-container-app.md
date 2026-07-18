# Project Migration Checklist — `multi-container-app`

Project name: `multi-container-app`
Source (Windows): `E:\LocalDev\multi-container-app`
Destination (WSL): `/home/masoud/personal/react/multi-container-app`

A small Docker "getting started" sample/tutorial repo (`github.com/docker/multi-container-app`) —
Node.js/Express/EJS "todo app" + MongoDB. First migration with **no database recovery phase at
all**: the project's own `compose.yaml` has always had its MongoDB volume commented out, so data
is intentionally ephemeral by the original author's design, not a migration gap to work around.

## 1. Read-only preflight (completed before any copy)

- [x] Confirmed genuinely the Docker sample/tutorial project: `README.md` ("This is a repo for new
      users getting started with Docker"), git remote (`github.com/docker/multi-container-app`),
      and code contents (a minimal Express/EJS/Mongoose todo app) all match.
- [x] Confirmed no persistent application data requiring preservation: `compose.yaml`'s only
      volume declaration is commented out; no `dbdata`/`data`/`mongo`-named directories anywhere
      in the tree; zero Docker footprint existed for this project before migration (no containers,
      images, or volumes referenced it).
- [x] Confirmed no hidden bind-mounted volumes or external dependencies: full recursive listing is
      13 files; MongoDB connection string is hardcoded to `mongodb://todo-database:27017/todoapp`
      (matches the compose service name exactly, no external host); no `.env` files anywhere, no
      secrets.
- [x] Confirmed no duplicate copies elsewhere: broad search across C:, D:, E:, and the WSL
      destination tree found exactly one copy.
- [x] Pre-copy git state recorded: branch `main`, HEAD `244c4022238786c39a946d5c0faeb1237c8f01cf`
      (2024-04-11, "Merge pull request #24 from lebe24/Docker-UI-update"), remote `origin` →
      `https://github.com/docker/multi-container-app`, no stash, no untracked files. Working tree
      showed 12 files as "modified" (+1839/-1839, exactly equal insertions/deletions) — verified
      via `git diff -w` (ignore-whitespace) that this is **entirely CRLF-vs-LF line-ending noise**,
      zero real content difference from HEAD.
- [x] Confirmed no recovery workflow needed: no database exists to back up, probe for
      compatibility, or restore.

## 2. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/react/multi-container-app`, excluding only
      `app/node_modules/`. Exit 0.
- [x] Post-copy git state verified identical to the pre-copy record on every dimension: branch,
      HEAD, remote, stash, and diff stat (down to the exact same +1839/-1839, still 100%
      whitespace-only per `git diff -w`).
- [x] Whole-tree checksum comparison (`rsync -avhcn`) confirmed no real content difference was
      introduced by the copy — only `.git/index` itself (git's own bookkeeping file, not tracked
      content) showed as touched, ordinary per-checkout noise.

## 3. Compose normalization — complete

- [x] `compose.yaml`: `name: multi-container-app_wsl`, no `container_name`, no auto-restart, ports
      parameterized via `.env.docker` (`APP_PORT=3001` — `3000` was already held by the running
      `login_wsl-frontend-1` stack; `LIVERELOAD_PORT=35729`, unchanged).
- [x] **Deliberately did not add a MongoDB volume.** The original project's own `#volumes:` block
      was already commented out — adding one now would have been a real design change to a
      tutorial app, not a standardization. Left the same comment in place (matching the original
      author's own hint), consistent with "do not modernize or redesign the tutorial application."
- [x] `todo-database` port not published to the host (internal-network-only), matching this
      migration's convention for every other project's database service — the app only ever
      talked to it via the internal service DNS name, never via a host-exposed port.

## 4. Validation — complete

- [x] Stack built and started (`docker compose up -d --build`) — both services `Up` on first try,
      no dependency-install gaps this time (Dockerfile's `npm ci` step is not shadowed, since
      `app/node_modules` is excluded from the copy but installed fresh at build time inside the
      image itself, not via a runtime bind-mount-shadowed step like the PHP/Laravel projects).
- [x] Container-to-container MongoDB connectivity validated: app logs show `Mongodb Connected`
      immediately on startup, using the internal service DNS name `todo-database` exactly as the
      app's own hardcoded connection string expects.
- [x] Application flow validated end-to-end: homepage (`GET /`) → 200, real rendered Todo App UI
      (not a stub/error page). Created a test record via the app's own `POST /` route, confirmed
      it both in the re-rendered homepage and via a direct `mongosh` query against the running
      `todo-database` container, then removed it via the app's own `POST /todo/destroy` route —
      no expectation of persistence, and the record was deliberately not kept.
- [x] Restart validated (`docker compose restart`): a second test record was created beforehand
      specifically to prove restart behavior, confirmed to survive the restart (same container,
      same writable layer — a restart is not a recreation), app reconnected cleanly (`Mongodb
      Connected` again in logs), homepage still 200. Removed the same way afterward.
- [x] Ephemeral-data behavior confirmed structurally consistent with the original design:
      `docker compose config` shows no volume declared for `todo-database`, matching the source's
      own commented-out volume exactly — data survives a simple restart (same container) but would
      not survive a `down`/recreate, exactly as the original tutorial was built to behave.
- [x] Original Windows source reconfirmed clean/untouched throughout (same HEAD, no untracked
      files) after the full migration.

## Notes / deviations

- Stack left running as instructed; no cleanup performed beyond removing the two deliberately
  created, non-persistent test records (consistent with "no expectation of persistence" — matches
  the ephemeral design itself, not a migration cleanup step).
- No archive or duplicate copy existed for this project anywhere — nothing else to leave untouched
  or note.
- No framework changes made. This project's only genuine deviation from every prior migration is
  structural (no database recovery phase needed at all), not a workflow change.
