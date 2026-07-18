# Project Migration Checklist — ozCarLab

Project name: ozCarLab
Source (Windows): `E:\LocalDev\ozCarLab`
Destination (WSL): `/home/masoud/personal/laravel/ozCarLab`

**First migration outside the validated MySQL/Laravel envelope.** PostgreSQL 12.17, two
CakePHP sub-applications (`ozcar`, `ozhub_repo`) served by one combined Apache+PHP container via
name-based virtual hosting. See the framework-extension preflight and version-analysis reports
already produced (§1–§3 of that work) for full technical detail; this checklist tracks execution.

## 1. Discovery — key findings (full detail in the preflight report)

- 3 services (`web`, `db`, `pgadmin`), no separate node/frontend service.
- PostgreSQL 12.17, `en_US.utf8` locale — confirmed clean recovery, no version/locale mismatch.
- `pg_data` bind-mounted (not a named volume, despite a dead `volumes: pg_data:` declaration in
  the original file that's never actually referenced).
- **Both sub-apps' `default` Datasource point to the same `db`/`ozcar` target** — confirmed
  directly in both apps' `config/app.php`.
- **Both apps also reference additional datasource profiles** (`withoutQuote` → `ozcar-live`,
  `phpLive` → MySQL) that are not reachable from the current Docker setup either (no MySQL
  service exists, no external host is configured) — legacy/alternate profiles, out of scope for
  this migration, not something the new stack needs to provide.
- Two independent git repos (`OzCar-Software/website`, `OzCar-Software/hub`), both on feature
  branches (`private-purchase-20-change`, `private-purchase-25`), not main/master.
- **Working-tree change status could not be safely determined for either repo** — `git status`
  (even with `-uno`) timed out at 30-60s bounds, consistent with the 2-minute timeout observed
  during preflight. Branch/HEAD/remote were obtainable quickly; diff status was not, over this
  boundary. Not forced further.
- Name-based Apache vhosts (`oz.local` → `ozcar`, `ozhub.local` → `ozhub_repo`), `AllowOverride
  All` + `.htaccess` present at both app-root and `webroot/` — mod_rewrite required and enabled.
  No default vhost defined — an unmatched Host header falls back to `oz.local` (first-listed).
  Both vhosts reachable via `Host:` header without any hosts-file change.
- Two orphaned/duplicate images exist (`ozcarlab-web` 13.3GB current, `ozcar-web` 10.1GB, 0
  containers) — a cleanup-phase question, not a migration blocker.

## 2. Backup — already complete (see version-analysis report)

- [x] Physical evidence backup: `~/docker-audit/project-checklists/ozCarLab-backups/pg_data-copy`
- [x] Disposable recovery working copy:
      `~/docker-audit/project-checklists/ozCarLab-backups/pg_data-recovery-working`
- [x] Recovery confirmed clean (WAL crash recovery completed, `ready to accept connections`,
      `lc_collate`/`lc_ctype` both `en_US.utf8`)
- [x] Fresh globals dump: `ozcarlab-globals-20260713-000850.sql` (391 bytes)
- [x] Fresh custom-format database dump: `ozcarlab-database-20260713-000850.dump` (~1.02GB,
      471 tables, SHA-256 recorded in the version-analysis report). **Correction:** an earlier
      count of "942" was a `pg_restore --list` double-count bug — the grep pattern matched both
      `TABLE` (schema) and `TABLE DATA` entries per table. True count is 471, matching the older
      backups (464, 470) closely — the earlier claim of "substantial schema growth" is retracted.
- [x] Temporary recovery container removed; original Windows `pg_data` and evidence backup both
      reconfirmed untouched throughout

## 3. Copy

- [x] Real `rsync` source → `/home/masoud/personal/laravel/ozCarLab` completed with
      `--exclude-deps` (`vendor/`, `node_modules/` excluded). `src/ozcar`: 22,578 files. `src/ozhub_repo`:
      21,514 files. Both `.git` directories present and preserved.

## 4. Compose normalization

- [x] `compose.yaml` placed at the live destination — `name: ozcarlab_wsl`, combined Apache+PHP
      `web` service (both sub-app bind mounts + `apache-vhosts.conf`), `db` (`postgres:12.17`,
      healthcheck via `pg_isready`, no published port), `pgadmin` (`dpage/pgadmin4:8.12`, `profiles:
      [tools]`). Top-level `volumes: pgdata:` — plain, non-external (the original's dead
      `pg_data:` declaration deliberately not carried forward).
- [x] `.env.docker` / `.env.docker.example` in place: `WEB_HTTP_PORT=8094`, `PGADMIN_PORT=5050`,
      `DB_DATABASE=ozcar`, `DB_USERNAME=[redacted]`, `DB_PASSWORD=[redacted]` (matches original
      hardcoded values), `PGADMIN_EMAIL`/`PGADMIN_PASSWORD` set. `.gitignore` added, ignoring
      `.env.docker`.
- [x] Fresh named volume `ozcarlab_wsl_pgdata` created by starting only `db`; confirmed healthy,
      PostgreSQL 12.17, `lc_collate`/`lc_ctype` both `en_US.utf8` (matches source, no mismatch).
- [x] Globals dump and custom-format database dump restored into the fresh volume; `DROP DATABASE
      cannot run inside a transaction block` fixed by splitting into two separate `psql -c`
      invocations; table count and content independently verified.

## 5. Validation — complete

- [x] Dockerfile gap #1 (pre-existing, not migration-caused): `ext-zip` was never installed,
      required by `vipsoft/unzip` in both apps. Fixed by adding `libzip-dev` + `zip` to
      `docker-php-ext-install`. Rebuilt and confirmed (`composer check-platform-reqs`:
      `ext-zip ... success`).
- [x] Dockerfile gap #2 (pre-existing, not migration-caused): `ext-gd` was never installed,
      required by `phpoffice/phpspreadsheet` and `setasign/fpdf` in `ozhub_repo`. Fixed by adding
      `libpng-dev`/`libjpeg-dev`/`libfreetype-dev` + `docker-php-ext-configure gd
      --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/` (PHP 7.3 requires this
      older `-dir=` syntax, not the PHP 7.4+ `--with-freetype --with-jpeg` form — verified in an
      isolated `php:7.3-apache` container before applying to the real Dockerfile). Rebuilt and
      confirmed (`ext-gd ... success`).
- [x] `composer install` completed for both `ozcar` and `ozhub_repo` — `vendor/autoload.php`
      present, all platform requirements satisfied. The trailing `App\Console\Installer::postInstall`
      error (`copy(config/app_local.example.php): No such file`) is expected/harmless for this
      project — it never adopted the `app_local.php` pattern (everything is hardcoded in
      `config/app.php` instead) — confirmed non-blocking in both apps.
- [x] Both services started (`web`, `db`; `pgadmin` deliberately not started).
- [x] `oz.local` validated: homepage HTTP 200 (254KB, real DB-backed car-listing content
      confirmed). `/users/login` HTTP 200 with empty body — confirmed by reading
      `UsersController::login()` that this is an intentional AJAX-only endpoint
      (`autoRender = false`, only renders on POST), not a defect.
- [x] `ozhub.local` validated: `/` HTTP 302 → `/user/login` (normal auth redirect for
      unauthenticated session). `/user/login` HTTP 200, correct title "OzCar Hub | Log in".
      Route naming differs from `oz.local` (`/user/login` singular vs. `/users/login` plural) —
      a pre-existing difference between the two sub-apps, not a migration artifact.
- [x] Logs checked: no PHP fatal errors, no Apache errors, no missing-table/extension/permission
      errors in either container from today's traffic. The only errors present in `db` logs are
      timestamped 2026-07-13 and belong to the earlier restore/verification session itself
      (the `DROP DATABASE`-in-transaction issue and a wrong table name in a verification query),
      not to application access.
- [x] PostgreSQL remained healthy throughout.

## 6. Cutover — restart validation complete

- [x] `docker compose restart` — both containers back up, `db` healthy on first poll.
- [x] Post-restart re-validation: `oz.local` homepage still 200/254KB with listing content;
      `ozhub.local` login page still 200 with correct title; no new errors in either log.
- [x] Stack left running as instructed. No cleanup or deletion performed.

---

## Notes / deviations

- **EOL components are explicitly out of migration scope**: PHP 7.3 (EOL Dec 2021), PostgreSQL
  12.17 (EOL Nov 2024), unpinned `dpage/pgadmin4:latest` (pinned to `8.12` in the new file for
  reproducibility only — not a functional upgrade). None of these are upgraded as part of this
  migration; all are recorded here as **follow-up modernization work**, separate from migration.
- The `ozcar-web` orphaned duplicate image and the two extra datasource profiles are noted for
  awareness, not acted on.
- **Dockerfile now diverges from the original** (added `libzip-dev`, `libpng-dev`, `libjpeg-dev`,
  `libfreetype-dev`, and the `zip`/`gd` PHP extensions). This is a necessary fix for pre-existing
  gaps (both apps' `composer.json` already required these extensions; the original Dockerfile
  simply never installed them, likely masked by a stale `vendor/` that pre-dated this
  requirement), not a migration-introduced change — but it is a deviation from "preserve the
  original Dockerfile exactly" worth flagging.
- **Cleanup candidates, not yet acted on**: two large old backup files were copied into `src/`
  during the source copy (app-tree cruft, not evidence — safe to remove from the WSL working copy
  later); the two orphaned Docker images (`ozcarlab-web` 13.3GB, `ozcar-web` 10.1GB) on the
  Windows side remain a separate cleanup question.
