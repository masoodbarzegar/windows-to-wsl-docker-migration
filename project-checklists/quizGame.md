# Project Migration Checklist — `quizGame`

Project name: `quizGame`
Source (Windows): `E:\LocalDev\Laravel\quizGame`
Destination (WSL): `/home/masoud/personal/laravel/quizGame`

Laravel 12 + Vite + MySQL 8. Same "successor of a lost project" pattern as `myLaravel`/
`myLaravelReact`/`myLaravelReactNew`: no git repository, single copy on disk (confirmed via
filesystem search — no duplicates, unlike the `quizGameV*` family which needed a duplicate-
resolution decision). `DB_HOST=db` in the app's own `.env` matches the standard service name
directly, so no network alias was needed (unlike `quizGameVthree`/`Vfour`).

First migration to apply the new **evidence-backup-immutability invariant** end-to-end (recorded
in `migration-plan.md` after the `login` migration): both the compatibility probe and the
recovery step used a disposable copy throughout; the evidence backup itself was mounted `:ro` at
every step and independently reconfirmed byte-identical (checksum) afterward.

## 1. Discovery

- No git repository anywhere in the tree (`git status` → "not a git repository").
- Single copy confirmed: filesystem search for `quizGame` (excluding the `quizGameV*` family)
  found exactly one directory (`E:\LocalDev\Laravel\quizGame`) and one archive
  (`E:\LocalDev\quizGame.rar`, untouched, not opened).
- `docker-compose.yml`: standard 5-service shape (`app`/`node`/`webserver`/`db`/`phpmyadmin`),
  `db` pinned to `mysql:8` (already cached locally at digest `2764fe573c51...`).
- All prior containers already `Exited` (14 months).

## 2. Backup — complete

- [x] Physical evidence backup (`~/docker-audit/project-checklists/quizGame-backups/dbdata-copy`),
      read-only mount, verified 191/191 files identical to source by name+size (28/28 at the top
      level); source mtimes confirmed unchanged before and after.
- [x] Compatibility probe run against a disposable throwaway copy in the scratchpad directory
      (never the evidence backup) — applying the new framework invariant from the start. Confirmed
      the same `lower_case_table_names` mismatch as every prior MySQL project (server `0` vs. data
      dictionary `2`). Evidence backup independently reconfirmed byte-identical (SHA-256 checksum
      against source) after the probe.
- [x] NTFS-hosted sparse-preserving recovery copy (`/mnt/e/Dev-Backups/quizGame/dbdata-recovery-copy`),
      isolated recovery container with `--lower-case-table-names=2`. Real data confirmed minimal
      but genuine: one schema (`laravel`), 9 tables (stock Laravel scaffold —
      `cache`/`cache_locks`/`failed_jobs`/`job_batches`/`jobs`/`migrations`/
      `password_reset_tokens`/`sessions`/`users`), only `migrations` (3 rows,
      the three default Laravel bootstrap migrations) and `sessions` (1 row) non-empty. `users` is
      empty — this project never progressed past its initial `laravel new` + `migrate`.
- [x] Logical dump (`~/docker-audit/project-checklists/quizGame-backups/quizGame-logical-20260718-095059.sql`)
      created and verified: 9 `CREATE TABLE` statements, checksum recorded (`f8a65019...`), and
      test-restored into a separate fresh throwaway container (row counts re-confirmed: migrations
      3, sessions 1) before relying on it.
- [x] Recovery container removed; source and evidence backup both reconfirmed untouched (mtime
      check) after use.

## 3. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/laravel/quizGame`, excluding only `src/vendor/`,
      `src/node_modules/`, and the old `dbdata/` (superseded by a fresh named volume). Exit 0, no
      permission-denied cases.

## 4. Compose normalization — complete

- [x] `compose.yaml`: `name: quizgame_wsl`, no `container_name`, no auto-restart, `db` healthcheck
      with `condition: service_healthy`, `phpmyadmin` under `profiles: [tools]`.
- [x] `.env.docker` / `.env.docker.example`: conflict-free ports against all configured WSL
      migrations — `WEB_HTTP_PORT=8095`, `APP_FPM_PORT=9006`, `VITE_DEV_PORT=5180`,
      `PHPMYADMIN_PORT=8085`.
- [x] Fresh named volume `quizgame_wsl_dbdata` created; dump restored; counts re-verified (3
      migrations, 1 session) as both `root` and the app's own `laravel` user.

## 5. Validation — complete

- [x] **Known bind-mount-shadowing pattern, confirmed for both PHP and Node in a single project
      this time**: neither Dockerfile installs dependencies at build time in a way that survives
      the bind mount — `docker/php/Dockerfile` never runs `composer install` at all, and
      `docker/node/Dockerfile` has `npm install` commented out. Fixed the same way as every prior
      project: `composer install` run once inside the running `app` container; for `node`, used
      `docker compose run --rm node npm install` as a one-off (the service's default `command: npm
      run dev` would otherwise crash-loop immediately since `vite` doesn't exist yet). Both persist
      via their bind mounts.
- [x] Storage/bootstrap-cache permissions fixed (`chown www-data:www-data` + `chmod 775`), same
      known pattern as every prior Laravel migration.
- [x] Application validated: homepage (`GET /`) → 200, correct default Laravel welcome page.
      Laravel's built-in health route (`GET /up`) → 200. `php artisan migrate:status` inside the
      container confirms the real restored migration history (3 `Ran` rows) — validates DB
      connectivity through the application layer itself, not just direct SQL against the
      container.
- [x] `routes/web.php` confirmed to genuinely be just the single default welcome route (`route:list`
      shows only `/`, `storage/{path}`, `/up`) — this project really is an untouched scaffold, not
      a validation gap.
- [x] **Pre-existing gap found, left unfixed and documented** (same policy as `quizGameVtwo`'s
      `/login` 500 and `login`'s `DashboardController::index` bug): the Vite dev server starts
      cleanly (confirmed in `node` container logs, "VITE v6.3.5 ready") but isn't reachable on its
      published host port — its own startup banner says "Network: use --host to expose." The
      project's own `vite.config.js` (copied verbatim, unmodified from source) never sets
      `server.host`, unlike `quizGameVtwo`/`Vthree`/`Vfour`'s own `vite.config.js` files, which
      already had `host: true` or `host: '0.0.0.0'` added by their original developer for Docker
      use. Confirmed this is a genuine pre-existing difference (checked all three other
      `quizGameV*` projects' `vite.config.js` for comparison), not a migration defect. Left
      unfixed since the app's actual HTTP layer (homepage, `/up`) is served correctly through
      nginx/PHP-FPM regardless, and speculatively editing `vite.config.js` isn't a "genuine
      project requirement" this validation actually needs.
- [x] No unexpected errors (no `storage/logs/laravel.log` exists yet — fresh app, no requests have
      triggered logged errors).
- [x] Restart validated (`docker compose restart`): `db` returns healthy, homepage and `/up` both
      re-confirmed 200, `migrate:status` re-confirmed identical (3 `Ran` rows), all four
      containers `Up`.

## Notes / deviations

- Stack left running as instructed; no cleanup performed.
- Original Windows source and both backup copies confirmed untouched throughout.
  `E:\LocalDev\quizGame.rar` was not touched or opened — the live source and its database fully
  answered every preservation question without needing it.
- Two findings left as pre-existing and documented rather than fixed: the PHP/Node
  dependency-install gap in the Dockerfiles (§5, fixed as a mechanical post-mount step, not an
  app-behavior change) and the missing Vite `server.host` config (§5, left untouched).
- First migration to apply the evidence-backup-immutability framework invariant from the start —
  no incident this time, unlike `login`.
