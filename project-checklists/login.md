# Project Migration Checklist — `login`

Project name: `login`
Source (Windows): `E:\LocalDev\React\login`
Destination (WSL): `/home/masoud/personal/react/login`

Custom vanilla-PHP backend (own `Router`/`MiddlewarePipeline` classes, no framework) + Create React
App frontend + MySQL 8.0. First project migrated outside the Laravel/quizGame family this cycle,
and the first from the `login` family the original audit ranked #1 ("Critical," needs a decision,
not just a copy).

## Authoritative-source resolution

A dedicated read-only investigation (no changes made) preceded this migration. Three copies
existed:

1. `E:\LocalDevelopments\React\login` — not a git repo; `backend`/`frontend` source folders
   already deleted; currently has a **running** `mysql_db` container, but its datadir contains
   **only system schemas** (confirmed via `SHOW DATABASES` and a direct datadir listing) — no
   application data at all.
2. `E:\LocalDev\React\login` — full git repo, remote `github.com/masoodbarzegar/react-auth.git`,
   14+ branches all on `origin`. Checked-out branch `feature/backend-tests` (HEAD `e1110a9`,
   2025-03-31) contains the merged JWT-auth + centralized-route-guard work, materially ahead of
   its own `master`. Real, non-empty application data (`mydatabase.users`, 25 rows). Most recent
   verified development activity in the family, including a substantial uncommitted rewrite never
   pushed.
3. `E:\LocalDev\React\react-login` — not a git repo; oldest (Jan 2025), no JWT anywhere in the
   backend; its `db_data` folder is an empty stub (compose declares a named volume instead, and no
   matching volume exists anywhere on the system) — no recoverable database at all.

**Chosen: copy #2.** Ruled the other two out by direct evidence (empty DB + deleted source;
no git, no JWT, no recoverable DB), not by inference. See `migration-plan.md`'s "Audit
corrections" for the correction this investigation made to the original audit's framing of the
"running container" risk.

## 1. Pre-migration git state (recorded before any copy)

- Branch: `feature/backend-tests`
- HEAD: `e1110a9d3150b14a7ad559025b34ea6d68298d53` (2025-03-31, "feat: Implement frontend JWT
  authentication and centralized route protection")
- Remote: `origin` → `https://github.com/masoodbarzegar/react-auth.git`
- Stash: one entry (`stash@{0}: On feature/logging-system-backend: !!GitHub_Desktop<...>`)
- Tracked modifications: 46 files, +19,288/-17,558 lines relative to HEAD — a substantial
  uncommitted rewrite (JWT middleware refinements, redux-persist, `apiClient` refactor, route
  guards) never committed or pushed.
- Untracked: 45 files/dirs, including a nascent PHPUnit test suite (`backend/tests/`,
  `phpunit.xml`, `backend/config/database.test.php`) with mtimes on 2025-05-02 — i.e. real work
  done *after* the last commit.

## 2. Backup — complete

- [x] Physical evidence backup (`~/docker-audit/project-checklists/login-backups/dbdata-copy`),
      read-only mount, verified 198/198 files identical to source by name+size; source mtimes
      confirmed unchanged before and after.
- [x] **Self-caught error, corrected**: the first `lower_case_table_names` compatibility probe was
      accidentally run directly against the evidence-backup path (not a disposable copy) with a
      writable mount, and mysqld's failed startup wrote to `ibdata1` before aborting. Caught via
      the mtime-verification step immediately after. Original Windows source confirmed untouched
      throughout. The mutated evidence backup and the recovery copy derived from it were both
      discarded and freshly redone (clean read-only backup → clean NTFS recovery copy) before
      continuing. Lesson: the compatibility probe must always target a disposable copy, never the
      evidence-backup path, even by accident of a writable mount.
- [x] Compatibility probe (redone cleanly): confirmed the same `lower_case_table_names` mismatch
      as every prior MySQL project (server `0` vs. data dictionary `2`).
- [x] NTFS-hosted sparse-preserving recovery copy
      (`/mnt/e/Dev-Backups/login/dbdata-recovery-copy`), isolated recovery container with
      `--lower-case-table-names=2`. Real data confirmed: one schema (`mydatabase`), one table
      (`users`), 25 rows.
- [x] Logical dump (`~/docker-audit/project-checklists/login-backups/login-logical-20260718-002103.sql`)
      created and verified: `CREATE DATABASE` present, 25 row-tuples, checksum recorded
      (`1cc10e4c...`), **and** test-restored into a separate fresh throwaway container to confirm
      the dump actually restores cleanly before relying on it.
- [x] Recovery container removed; source and evidence backup both reconfirmed untouched (mtime
      check) after use.

## 3. Copy — complete

- [x] `rsync` source → `/home/masoud/personal/react/login`, excluding only `backend/vendor/`,
      `frontend/node_modules/`, and the old `db_data/` (superseded by a fresh named volume, same
      convention as every prior MySQL migration). Exit 0, no permission-denied cases.
- [x] Post-copy git state verified: branch, HEAD, remote, stash list, and untracked-file count
      (45) all identical to the pre-migration record above.
- [x] **One apparent tracked-diff discrepancy investigated and explained, not a copy defect**:
      destination's diff stat (+19,262/-17,559) differed slightly from source's
      (+19,288/-17,558). Root cause: a pre-existing case mismatch between the git index
      (`backend/src/config.php`, lowercase) and the actual on-disk filename (`Config.php`) —
      invisible on the source's case-insensitive NTFS/9P filesystem, surfaced only because
      WSL-native ext4 is case-sensitive. Confirmed via SHA-256 that `Config.php`'s content is
      byte-identical between source and copy, and confirmed via `git ls-files -s` that this exact
      mismatch already exists in the source's own git index (both repos report the same blob for
      the same lowercase path) — not introduced by the migration. A tree-wide scan found no other
      instance of this in the repo. Whole-tree checksum comparison (`rsync -avhcn`) additionally
      confirmed every tracked and untracked file matches source byte-for-byte (only the `.git/`
      directory *entry* itself, not its contents, showed as changed).

## 4. Compose normalization — complete

- [x] `compose.yaml`: `name: login_wsl`, no `container_name` (the source hard-coded
      `php_backend`/`react_frontend`/`mysql_db`/`phpmyadmin` — exactly the structural collision
      the original audit flagged across all three family copies), no auto-restart, `db`
      healthcheck with `condition: service_healthy`, `phpmyadmin` under `profiles: [tools]`.
- [x] `.env.docker` / `.env.docker.example`: conflict-free ports against all configured WSL
      migrations — `FRONTEND_PORT=3000`, `BACKEND_PORT=8003`, `PHPMYADMIN_PORT=8084`.
- [x] **One project-specific addition (genuine requirement, not a framework change)**: the `db`
      service now sets `MYSQL_DATABASE`/`MYSQL_USER`/`MYSQL_PASSWORD` (official-image-recognized
      vars) matching the app's own long-standing `mydatabase` database with username/password
      `[redacted]`/`[redacted]`. The
      original compose only ever fed `MYSQL_ROOT_PASSWORD` via `env_file`, relying on the
      schema/user having been created once, long ago, by an undocumented manual step that
      Windows' persistent datadir then carried forward silently. A fresh volume needed this made
      explicit. `backend/.env.docker` itself (the app's own source file, git-tracked) was left
      completely untouched.
- [x] Fresh named volume `login_wsl_dbdata` created; dump restored; count re-verified (25) both as
      `root` and as the app's own `user` account (confirms grant scope correct, not just that root
      can see it).

## 5. Validation — complete

- [x] **Genuine deviation found and fixed (bind-mount shadowing, not a new class of issue)**: the
      backend Dockerfile runs `composer install` at build time, but the compose file bind-mounts
      `./backend` over `/var/www/html`, shadowing the image's baked-in `vendor/` with the host
      copy (which correctly excludes `vendor/`) — same underlying pattern as the
      storage/bootstrap-cache fix in every prior Laravel migration, just manifesting as a missing
      `vendor/autoload.php`. Fixed by running `composer install` inside the running container
      once; confirmed it persists across a restart (bind mount, no reinstall needed).
- [x] Auth flow validated end-to-end against the real restored data: unauthenticated `/dashboard`
      and `/verify-auth` correctly 401 (JWT middleware blocks). A fresh test account
      (`migration-test@example.com`) was registered and logged in — deliberately not attempting
      any of the 25 real users' actual passwords — confirming `/register`, `/login` (JWT cookie
      issued), `/verify-auth` (200, correct decoded identity), and `/logout` all function
      correctly.
- [x] **Genuine pre-existing application bug found, left unfixed and documented** (same policy as
      `quizGameVtwo`'s `/login` 500): `GET /dashboard` returns 500 for an authenticated user — the
      router wires it to `DashboardController::index`, but the controller only defines
      `getDashboardData($decoded)`. Confirmed pre-existing and unmodified since copy; the git
      commit that introduced this method calls it "temporary… for demonstration purposes" in its
      own message — an intentionally incomplete feature, not a migration defect.
- [x] Frontend (`create-react-app` dev server) confirmed serving (`GET /` → 200, correct HTML
      shell).
- [x] No unexpected errors in backend logs; only the standard Apache `ServerName` notice.
- [x] Restart validated (`docker compose restart`): `db` returns healthy, `vendor/` persists
      (bind mount), row count correct (26 = 25 restored + 1 test-registered), full auth flow
      re-verified end-to-end, frontend still serves 200.

## Notes / deviations

- Stack left running as instructed; no cleanup performed.
- Original Windows source, physical evidence backup, and NTFS recovery copy all confirmed
  untouched throughout (after the self-caught-and-corrected evidence-backup mutation described
  above). `E:\LocalDevelopments\React\login`, `E:\LocalDev\React\react-login`, and all 29 `.rar`
  archives in `E:\LocalDev\React\backups\` were not touched at all — not migrated, not opened,
  per the resolved authoritative-source decision.
- Two code-level findings in the WSL copy's own source, both left as pre-existing and documented
  rather than fixed: the `config.php`/`Config.php` case mismatch (§3) and the
  `DashboardController::index` missing-method bug (§5).
