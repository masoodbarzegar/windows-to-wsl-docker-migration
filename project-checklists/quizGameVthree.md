# Project Migration Checklist — quizGameVthree

Project name: quizGameVthree
Source (Windows): `E:\LocalDev\Laravel\quizGameVthree`
Destination (WSL): `/home/masoud/personal/laravel/quizGameVthree`

Laravel 12 + React 19 + MySQL 8.0. Same Docker scaffolding as `quizGameVtwo` (Dockerfile and
nginx config are byte-identical), but a much simpler/earlier-stage application — no git repo,
`routes/web.php` defines only a single `/` route.

## Audit correction

The original audit's "None found" for this project's DB location was **wrong** — there is a real
bind-mounted MySQL datadir with live data (`quiz` schema, `ibdata1`, binlogs, etc.), same as
`quizGameVtwo`. Recorded in `migration-plan.md` under "Audit corrections."

## 1. Discovery

- No `.git` anywhere in the project — no version-control state to preserve.
- MySQL 8.0, bind-mounted datadir at `docker/mysql/data`, same UID-999 permission wall as every
  prior MySQL migration.
- Dockerfile and `docker/nginx/default.conf` byte-identical to `quizGameVtwo`'s (confirmed by
  direct comparison during preflight) — build reused 100% cached layers.
- `mysql:8.0` image digest (`sha256:50b5ee0656a2...`) already validated 3x prior in this
  environment.

## 2. Backup — complete

- [x] Physical evidence backup: `~/docker-audit/project-checklists/quizGameVthree-backups/dbdata-copy`
      — verified: structure matches source (27/27 entries), all protected directories present
      (`mysql`, `performance_schema`, `sys`, `quiz`, `#innodb_redo`, `#innodb_temp`), source mtimes
      confirmed unchanged before/after.
- [x] `lower_case_table_names` compatibility probe: WSL-native attempt failed as expected
      (identical error to `quizGameVtwo`: `Different lower_case_table_names settings for server
      ('0') and data dictionary ('2')`) — no divergence from the proven workflow.
- [x] NTFS-hosted recovery working copy: `/mnt/e/Dev-Backups/quizGameVthree/dbdata-recovery-copy`
      (sparse-preserving).
- [x] Isolated recovery container (`--network none`, exact cached digest,
      `--lower-case-table-names=2`) started cleanly.
- [x] Logical dump: `quizGameVthree-logical-20260716-212718.sql` — 9/9 tables, all lowercase
      identifiers, verified row counts (`migrations`=3, `sessions`=2, all others 0).
- [x] Temporary recovery container removed; original Windows source and evidence backup both
      reconfirmed untouched (mtime check) after use.

## 3. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/laravel/quizGameVthree`, excluding only
      `src/vendor/`, `src/node_modules/`, and the old `docker/mysql/data/`. No git state to
      preserve (none exists).

## 4. Compose normalization — complete

- [x] `compose.yaml`: `name: quizgamevthree_wsl`, same 4-service shape as `quizGameVtwo` (`app`,
      `web`, `db`, `phpmyadmin` behind `profiles: [tools]`).
- [x] `.env.docker` / `.env.docker.example`: conflict-free ports chosen against all other
      configured WSL migrations (running or not) — `WEB_HTTP_PORT=8001`, `APP_FPM_PORT=9004`,
      `VITE_DEV_PORT=5178`, `PHPMYADMIN_PORT=8082`. DB credentials match original hardcoded values.
- [x] **Genuine gap found and fixed (smallest-possible adjustment, not a workflow divergence)**:
      the app's own `.env` hardcodes `DB_HOST=mysql`, but the standard compose service is named
      `db` — so `mysql` didn't resolve on the network. Root cause confirmed directly (`getent
      hosts mysql` failed, `getent hosts db` succeeded). This same latent mismatch exists in
      `.env` for `quizGameVtwo` too, but never surfaced there because that app's
      `SESSION_DRIVER=file` never touches the DB on every request; this app's
      `SESSION_DRIVER=database` does, so it fails immediately on the homepage. Fixed by adding a
      network alias (`mysql`) to the `db` service in `compose.yaml` — does not touch the app's
      `.env` (preserved exactly as-is) or any application code, purely a Compose networking
      addition so both `db` and `mysql` resolve to the same container.
- [x] Fresh named volume `quizgamevthree_wsl_dbdata` created; database restored; content
      independently verified (9/9 tables, exact row-count match against the dump).

## 5. Validation — complete

- [x] `composer install` — clean; `inertiajs/inertia-laravel` was already properly declared here
      (unlike `quizGameVtwo`, which was missing it) — no PHP-side dependency gap in this project.
- [x] `npm install` — clean, but surfaced a genuine gap: `@inertiajs/react` is imported in
      `resources/js/app.jsx` but was missing from `package.json`'s `dependencies` (confirmed by
      reading the file directly before acting). Same class of pre-existing app-dependency gap as
      `quizGameVtwo`'s missing composer package — fixed with `npm install @inertiajs/react`
      (additive-only, `package.json` updated to `^3.6.1`).
- [x] Storage/bootstrap-cache permission fix applied (same known bind-mount pattern as every
      prior MySQL migration) — `chown -R www-data:www-data storage bootstrap/cache`.
- [x] This project's intended workflow is `npm run dev` (nginx proxies `/@vite*` to port 5173),
      same as `quizGameVtwo` — Vite dev server started manually in the background; no
      `npm run build` attempted (not the project's own designed path).
- [x] Homepage (`/`) validated: HTTP 200, correct rendering, no PHP/SQL errors in body (one
      apparent "500" grep match was a false positive — a Tailwind CSS hex-color utility class,
      not an error).
- [x] Session read/write path specifically validated (this app uses `SESSION_DRIVER=database`,
      exercising the DB connection on every request) — `sessions` row count increased from 2 to 4
      across two test requests, confirming genuine working reads and writes through the `mysql`
      alias, not just a cached/stale response.
- [x] No other routes exist to validate — `routes/web.php` defines only `/`.
- [x] Restart validated (`docker compose restart`): `db` healthy, homepage still 200 with correct
      title, restored data confirmed present (`migrations`=3), `mysql` network alias confirmed
      still resolving post-restart (persists via Compose config, not container-ephemeral). Vite
      dev server (a manually-started background process) needed a manual restart after the
      container restart — same known characteristic as `quizGameVtwo`.

## Notes / deviations

- Stack left running as instructed; no cleanup performed.
- Original Windows source, physical evidence backup, and NTFS recovery copy all confirmed
  untouched throughout and left in place.
- **Follow-up flag for a future session** (not acted on now, per current framework-freeze
  instruction): the `DB_HOST=mysql` vs. service-name-`db` mismatch likely exists silently in
  `quizGameVtwo` and possibly other already-completed migrations too — it just hasn't surfaced
  there because those apps don't hit the database on every request the way this one's
  `SESSION_DRIVER=database` does. Worth a deliberate check once all migrations are complete,
  rather than reopening finished projects now.
