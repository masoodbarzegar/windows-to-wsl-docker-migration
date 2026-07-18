# Project Migration Checklist — `react-app`

Project name: `react-app`
Source (Windows): `E:\LocalDev\React\react-app`
Destination (WSL): `/home/masoud/personal/react/react-app`

Plain `create-react-app` scaffold — a client-side-only "Todo App" using `localStorage` for state
(no backend, no API calls, no database). Second source-copy-only migration in a row, for a
different reason than `multi-container-app`: here there was never anything server-side to persist
at all, by the app's own design (all state lives in the browser).

## 1. Read-only preflight — complete

- [x] No git repository (`git status` → "not a git repository") — matches original audit.
- [x] Single copy confirmed: filesystem search found exactly one `react-app` directory across
      C:, D:, E:.
- [x] Existing Docker configuration identified: `docker-compose.yml` (single `app` service,
      `node:18`, bind-mounts `.:/app` + `/app/node_modules` + redundant `./src:/app/src` +
      `./public:/app/public`, port `3000:3000`, `npm start`) and a matching `Dockerfile`
      (`node:18`, `npm install` at build, `CMD ["npm", "start"]`).
- [x] No persistent data, bind-mounted volumes beyond the app source itself, named volumes, or
      external dependencies: no `.env` files anywhere, `package.json` has zero backend/API
      dependencies, `src/App.js` confirmed to be a pure client-side component using
      `localStorage` for its only state. Zero current Docker footprint for this project (no
      containers, images, or volumes referenced it).
- [x] No genuine blocker found — proceeded directly with migration per approval.

## 2. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/react/react-app`, excluding only `node_modules/`.
      Exit 0.
- [x] Whole-tree checksum verification (`rsync -avhcn`) both immediately after the copy and again
      after the full migration/restart — zero files differing either time (only the top-level
      directory entry's own mtime changed, from adding `compose.yaml`/`.env.docker` alongside the
      preserved originals — not a change to any original file).

## 3. Compose normalization — complete

- [x] Original `docker-compose.yml`/`Dockerfile` left completely untouched in place (preserved
      source), matching the convention used for every prior project with a pre-existing compose
      file (`login`, `quizGame`).
- [x] New `compose.yaml` added alongside it (`name: react-app_wsl`), making only the minimum
      changes required to run under this migration's conventions: dropped the deprecated
      `version: "3.8"` key, parameterized the host port via `.env.docker`
      (`APP_PORT=3002` — `3000` and `3001` were already held by other running WSL stacks).
      Everything else — the redundant duplicate bind mounts, the `CHOKIDAR_USEPOLLING` env var,
      the exact `npm start` command — copied verbatim. No modernization, no redesign.

## 4. Validation — complete

- [x] Stack built and started (`docker compose up -d --build`) — clean `npm install` and
      `react-scripts start`, no errors.
- [x] Homepage (`GET /`) → 200, correct `create-react-app` HTML shell.
- [x] `GET /static/js/bundle.js` → 200 — confirms the actual React bundle serves correctly, not
      just the static shell (this app's real content only renders client-side in a browser, so a
      plain `curl` of `/` can't show the rendered Todo list, but a 200 on the shell plus a 200 on
      the bundle together confirm the dev server is serving the app correctly end-to-end).
- [x] Restart validated (`docker compose restart`): container restarts cleanly, both `/` and the
      bundle re-confirmed 200 afterward.

## Notes / deviations

- Stack left running as instructed; no cleanup performed.
- Original Windows source confirmed untouched throughout (checksum-verified identical both
  immediately after copy and again at the end of the migration).
- No database, no recovery workflow, no framework changes. Nothing else to leave untouched — no
  archive or duplicate existed for this project.
