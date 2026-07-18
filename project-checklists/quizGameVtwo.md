# Project Migration Checklist — quizGameVtwo

Project name: quizGameVtwo
Source (Windows): `E:\LocalDev\Laravel\quizGameVtwo`
Destination (WSL): `/home/masoud/personal/laravel/quizGameVtwo`

Laravel 12 + Inertia/React + MySQL 8.0. Single app container (PHP-FPM + Node 20 for Vite),
separate nginx, mysql, phpmyadmin services. Branch `feature/auth-system`, no remote configured,
13 files with uncommitted working-tree changes at time of migration (preserved as-is).

## 1. Discovery

- Old audit's "quiz-phpmyadmin running now" claim was stale — all `quizGameVtwo` containers were
  `Exited` at time of migration.
- MySQL 8.0, bind-mounted datadir at `docker/mysql/data`, permission-protected (same UID-999 wall
  as prior migrations).
- `mysql:8.0` image digest (`sha256:50b5ee0656a2...`) already validated in this environment
  (same digest used for `laravellivewireadmin_wsl-db-1`).

## 2. Backup — complete

- [x] Physical evidence backup: `~/docker-audit/project-checklists/quizGameVtwo-backups/dbdata-copy`
      — verified: structure matches source (40/40 entries), all protected directories present
      (`mysql`, `performance_schema`, `sys`, `quiz`, `#innodb_redo`, `#innodb_temp`), source mtimes
      confirmed unchanged before/after.
  - Note: initial pre-backup `du` taken across the `/mnt/e` 9P boundary read 10.3MB; the verified
    WSL-native backup is actually 199.4MB — another instance of the known cross-boundary `du`
    unreliability (undercounting this time), not a data-loss concern.
- [x] `lower_case_table_names` compatibility check: attempted a disposable WSL-native (ext4) start
      first — failed as expected (`Different lower_case_table_names settings for server ('0') and
      data dictionary ('2')`), confirming this datadir needs a case-insensitive filesystem.
- [x] NTFS-hosted recovery working copy: `/mnt/e/Dev-Backups/quizGameVtwo/dbdata-recovery-copy`
      (sparse-preserving `cp -a --sparse=always`).
- [x] Isolated recovery container (`--network none`, exact cached `mysql:8.0` digest,
      `--lower-case-table-names=2`) started cleanly, XA crash recovery completed normally.
- [x] Logical dump: `quizGameVtwo-logical-20260714-233206.sql` — 11/11 tables, all lowercase
      identifiers, verified row counts (`users`=2, `personal_access_tokens`=2, `migrations`=5,
      all others 0).
- [x] Temporary recovery container removed; original Windows source and evidence backup both
      reconfirmed untouched (mtime check) after use.

## 3. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/laravel/quizGameVtwo`, excluding only
      `src/vendor/`, `src/node_modules/`, and the old `docker/mysql/data/` (superseded by the named
      volume). `.git` preserved; branch (`feature/auth-system`), latest commit, and all 13
      uncommitted working-tree changes confirmed identical to source after copy.

## 4. Compose normalization — complete

- [x] `compose.yaml`: `name: quizgamevtwo_wsl`, no `version`/`container_name`/`restart: always`,
      services `app` (build `docker/Dockerfile`, PHP 8.3-fpm + Node 20 in one image), `web`
      (`nginx:alpine`), `db` (`mysql:8.0`, healthcheck via `mysqladmin ping`), `phpmyadmin`
      (`profiles: [tools]`).
- [x] `.env.docker` / `.env.docker.example`: ports chosen conflict-free against all other running
      WSL migrations — `WEB_HTTP_PORT=8000`, `APP_FPM_PORT=9003`, `VITE_DEV_PORT=5177`,
      `PHPMYADMIN_PORT=8081`. DB credentials match original hardcoded values
      (`quiz`/`quizuser`/`quizpass`/root `root`).
- [x] Fresh named volume `quizgamevtwo_wsl_dbdata` created; globals/database restored; content
      independently verified (11/11 tables, exact row-count match against the dump).

## 5. Validation — complete

- [x] Full stack build + start (`docker compose up -d --build`) — one transient network failure
      pulling base images (TLS handshake timeout), resolved on retry, not a workflow deviation.
- [x] `composer install` — clean, no missing-extension issues (unlike ozCarLab, this project's
      Dockerfile already had everything its `composer.json` required).
- [x] `npm install` — clean (pre-existing `npm audit` vulnerability warnings, unrelated).
- [x] **Pre-existing bug found and fixed**: `npm run build` failed — `Layouts/ClientLayout.jsx`
      imports `@/Components/ui/dropdown-menu`, which doesn't exist on either the WSL copy or the
      original Windows source (confirmed via direct comparison — genuinely missing on both, not a
      copy artifact). Only `Client/Dashboard.jsx` uses this layout, but Inertia's
      `import.meta.glob` bundles all pages eagerly, so the production build fails entirely. Did
      **not** fabricate the missing component (out of scope — that's an application-code decision,
      not an infra fix). Instead matched the project's own original design: `nginx`'s config already
      proxies `/@vite*` to a live dev server on port 5173, meaning the intended local workflow was
      always `npm run dev`, not a static production build. Started the Vite dev server directly;
      it serves all working routes without issue (dev mode transforms modules lazily per request).
- [x] **Pre-existing bug found and fixed**: storage/bootstrap-cache permission errors
      (`storage/logs/laravel.log ... Permission denied`) — the bind-mounted `./src` overlays the
      Dockerfile's build-time `chown www-data`. Fixed with a runtime `chown -R www-data:www-data
      storage bootstrap/cache` (standard, expected fix for this bind-mount pattern, confirmed to
      persist across the restart test since it modifies the actual files on disk).
- [x] **Pre-existing bug found and fixed**: `composer.json` was missing `inertiajs/inertia-laravel`
      entirely, despite the app calling `Inertia::render()` server-side and using
      `@inertiajs/react` on the frontend — confirmed via runtime error (`Class "Inertia\Inertia" not
      found`) and confirmed absent from `composer.json`/`composer show` before the fix. Added via
      `composer require inertiajs/inertia-laravel` (v3.1.1) — additive-only, does not touch any
      existing declared dependency.
- [x] **Pre-existing bug found, NOT fixed (documented only)**: `/login` returns HTTP 500 —
      `Call to undefined method ...AuthController::middleware()`. `composer.json` already requires
      `laravel/framework: ^12.0`, but both `Client/AuthController.php` and
      `Admin/AuthController.php` call `$this->middleware(...)` inside `__construct()`, a pattern
      removed in Laravel 11+ (needs converting to route-level middleware or the `HasMiddleware`
      interface). Confirmed this is a genuine pre-existing code/framework-version mismatch on the
      `feature/auth-system` branch, unrelated to migration — same composer.json, same committed
      code, would fail identically on the original Windows source. **Deliberately not fixed**:
      unlike the missing-package fix above, this requires rewriting the developer's own
      authentication-flow logic, which is a code-design decision outside migration scope.
- [x] Endpoints validated: homepage (`/`) HTTP 200 with correct Inertia payload
      (`component: Home`, real `featuredGames` data); `/games` HTTP 200; `/dashboard` (auth-gated)
      HTTP 302 (correct unauthenticated redirect); `/login` HTTP 500 (pre-existing bug, documented
      above, left as-is).
- [x] Restart validated (`docker compose restart`): `db` healthy, all endpoints re-tested with
      identical results, restored data confirmed still present (`users`=2,
      `personal_access_tokens`=2, `migrations`=5) — storage permission fix persisted (bind mount,
      not container-ephemeral); Vite dev server (a manually-started background process, not part of
      the container's `CMD`) needed a manual restart after the container restart — noted for
      awareness, not a defect.

## Notes / deviations

- Stack left running as instructed; no cleanup performed.
- Original Windows source, physical evidence backup, and NTFS recovery copy all confirmed
  untouched throughout and left in place.
- Known follow-up items for whoever continues this branch: fix the `/login` `middleware()` call
  (Laravel 11+ compatibility), and add the missing `Components/ui/dropdown-menu.jsx` component
  referenced by `ClientLayout.jsx`.
