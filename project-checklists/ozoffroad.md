# Project Migration Checklist — `ozoffroad`

Project name: `ozoffroad`
Source (Windows): `E:\LocalDev\ozoffroad`
Destination (WSL): `/home/masoud/personal/laravel/ozoffroad`

CakePHP 4.x application, PostgreSQL. Sibling project to the already-migrated `ozCarLab`
(same private git server, same PHP/CakePHP/Postgres era and conventions — even this app's own
`SECURITY_SALT` default literally reads `-OzCar-`, suggesting its config was originally templated
from ozCarLab's own). **Source-only migration** — no recoverable database was found anywhere on
the source machine (see "Database" section below); this was confirmed via read-only investigation
*before* any migration work began, not discovered mid-migration.

## Authoritative-source resolution (read-only investigation, prior to approval)

Two copies existed: `/mnt/e/LocalDev/ozoffroad` (canonical active-dev location) and
`/mnt/e/Ozcar newest backup/backup/ozoffroad` (explicitly a backup folder). A full recursive
`diff -rq` (excluding `vendor/`/`.git/`, which are reproducible) found **zero differing files** —
confirmed via direct checksums on the gitignored `config/app.php` and `.idea/workspace.xml` too.
Identical git state in both: branch `master`, HEAD `5ce211a6` (2023-09-27), remote
`ssh://[redacted-user]@[redacted-ip]:2248/repositories/ozoffroad.git` (a private company git
server, not GitHub), identical uncommitted
`composer.json`/`composer.lock` modifications, no stash, no untracked files. This is a true
backup snapshot, not a divergent fork — chose the canonical `LocalDev` copy since both are
identical.

## Database — explicitly excluded, evidence recorded

- [x] **No local PostgreSQL installation was found.** Checked every standard Windows install
      location on C: (`Program Files\PostgreSQL`, `Program Files (x86)\PostgreSQL`,
      `ProgramData\PostgreSQL`) — none exist.
- [x] **No local PostgreSQL data directory was found.** Searched both C: and E: drives for
      `PG_VERSION` (the canonical datadir marker file) — zero matches anywhere.
- [x] **No dump or backup was found.** Searched both copies' trees for `*.sql`/`*data*`-named
      files or directories — none, beyond the CakePHP framework's own generic
      `config/schema/sessions.sql`/`i18n.sql` reference files (unused — this app's own
      `config/app.php` sets `'Session' => ['defaults' => 'php']`, i.e. native file-based sessions,
      confirming these framework files were never actually wired up).
- [x] **Therefore no database migration was possible.** This is recorded as an evidence-based
      finding, not an error: the app's own (gitignored, present-on-disk, identical-on-both-copies)
      `config/app.php` specifies a PostgreSQL connection to `127.0.0.1` with real credentials
      (username/password: `[redacted]`/`[redacted]`, database `ozoffroad`) — but no corresponding
      data exists anywhere discoverable on this machine. No speculative recovery was attempted.

## 1. Git preservation — complete

- [x] Pre-copy git state recorded: branch `master`, HEAD `5ce211a6529e6b3a0f1ad5a82b23320e8697b590`,
      remote `origin` → the private SSH server above, no stash, `composer.json`/`composer.lock`
      showing as modified (+1023/-1355), no untracked files.
- [x] Source copied to `/home/masoud/personal/laravel/ozoffroad`, excluding only `vendor/`.
- [x] Post-copy git state verified identical on every dimension (branch, HEAD, remote, stash,
      diff stat down to the exact same +1023/-1355, no untracked files). Whole-tree checksum
      comparison (`rsync -avhcn`) confirmed no real content difference was introduced — only
      `.git/index` itself (bookkeeping, not tracked content) showed as touched.

## 2. Dockerization — complete (infrastructure), app itself has a pre-existing blocker

No Docker artifacts existed in the source at all (not previously Dockerized, unlike `ozCarLab`).
Built from scratch, modeled closely on `ozCarLab`'s proven Dockerfile/compose shape (same
PHP 7.3 + Apache + `pdo_pgsql` stack, chosen to match the sibling project's era and minimize
unknown PHP8-compatibility risk in old CakePHP 4.0 code — not a modernization decision).

- [x] `Dockerfile`: `php:7.3-apache`, `intl`/`pdo_pgsql`/`gd`/`zip` extensions (matching
      `composer.json`'s actual requirements — `intervention/image` needs `gd`, `vipsoft/unzip`
      needs `zip`, CakePHP core needs `intl`). `AllowOverride All` enabled so the app's own
      committed root `.htaccess` (which rewrites everything into `webroot/`) runs exactly as
      authored, rather than reimplementing that routing decision in the vhost config.
- [x] `compose.yaml`: `name: ozoffroad_wsl`, `web` + `db` (`postgres:12.17`, same pinned version
      as `ozCarLab`) + `pgadmin` (`profiles: [tools]`). **The `db` service is fresh and
      deliberately empty** — no volume was seeded, no schema applied, no data written. Its
      credentials match this app's own already-known `config/app.php` values (not invented) so
      the stack has the standard shape, ready to receive a real dump if one is ever found, but
      holds nothing right now.
- [x] `composer install` run post-mount (vendor excluded from copy, standard pattern).
      `postInstall` script failed on `copy(config/app_local.example.php): No such file` —
      confirmed this template file is genuinely absent from git in **both** source copies, a
      pre-existing gap, not migration-caused. Harmless: `config/bootstrap.php` only loads
      `app_local.php` conditionally (`if (file_exists(...))`), so the app runs fine without it.
- [x] **One environment-file adjustment** (not application source — `config/app.php` is
      gitignored): changed the `default` datasource's `'host'` from `'127.0.0.1'` to `'db'`,
      matching the Compose service name. This is infrastructure wiring, not data reconstruction —
      the `db` service it now points to is empty. Verified working: `PDO pgsql:host=db;...`
      connects successfully from the `web` container.
- [x] `tmp/`/`logs/` directories created (git doesn't track empty dirs; CakePHP needs them for
      cache/session/log writes) and permissioned `www-data:www-data`, same pattern as every prior
      Laravel/CakePHP migration's storage-permission fix.

## 3. Application validation — pre-existing gap found, documented, not fixed

- [x] **Genuine, pre-existing source-completeness gap, confirmed identical on both copies**:
      `src/Application.php:48` unconditionally calls `$this->addPlugin('MobileValidator')` in the
      app's bootstrap path (real, committed application code — not gitignored, not an environment
      file). But `plugins/MobileValidator` was **never committed to git** — `plugins/` contains
      only a `.gitkeep` placeholder, identical on the Windows source and the WSL copy. Confirmed
      via `git ls-files` on both repos and a direct filesystem check. This is not a migration
      defect; the application as committed to this repository cannot boot, on Windows or WSL.
      **Not fixed** — writing a stub plugin would mean inventing application code, explicitly out
      of scope for this migration.
- [x] Effect confirmed app-wide and deterministic, not route-specific: `/`, `/users`, `/admin` all
      return 500 consistently across repeated requests and across a full restart.
- [x] **Additional finding from deeper config review**: `config/app.php`'s `Datasources` array
      contains two more connection blocks beyond `default` — `withoutQuote` (Postgres, database
      `ozcar-live` — likely a shared/production database also used by `ozCarLab`) and `phpLive`
      (MySQL, database `phplive`, probably an old PHPLive! chat-widget integration). **Neither is
      referenced anywhere in `src/` or `plugins/`** (checked via `grep` for the connection names
      and for `getConnection`/`defaultConnectionName` overrides — the only match is in a `bake`
      code-generator scaffold template, not real application code). Treated as inert leftover
      config, not an active external dependency — left completely untouched, no connection
      attempted to either.
- [x] Container-to-container PostgreSQL connectivity validated independently of the broken
      application layer: `PDO pgsql:host=db;port=5432;dbname=ozoffroad` connects successfully
      from the `web` container using the exact driver (`pdo_pgsql`) CakePHP itself uses. This
      confirms the Docker networking and the `db`-host config fix are both correct — the 500 is
      entirely attributable to the missing-plugin gap above, not to database connectivity.
- [x] Restart validated (`docker compose restart`): `db` returns healthy, `web` restarts cleanly,
      the same deterministic 500 (missing plugin) persists — consistent, explainable behavior,
      not Docker instability.

## Notes / deviations

- Stack left running as instructed (both containers up); no cleanup performed.
- Original Windows source (both copies) confirmed untouched throughout (same HEAD, no untracked
  files, mtimes unaffected).
- This is the first migration where the application itself cannot fully render any page — a
  pre-existing, evidence-confirmed gap in the committed source (missing `MobileValidator` plugin),
  not a database issue and not something introduced by this migration. Documented per the same
  policy as every prior "found but not fixed" pre-existing bug (`quizGameVtwo`'s `/login` 500,
  `login`'s `DashboardController::index`, `quizGame`'s Vite host binding) — except this one is
  broader in effect (every route, not one) because it happens at the application bootstrap level.
- No framework changes made.
