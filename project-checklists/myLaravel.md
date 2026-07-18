# Project Migration Checklist — myLaravel

Project name: myLaravel
Date started: 2026-07-11
Source (Windows): `E:\LocalDev\Laravel\myLaravel`
Source (WSL view): `/mnt/e/LocalDev/Laravel/myLaravel`
Destination (WSL): `/home/masoud/personal/laravel/myLaravel`

Standards referenced: `~/docker-audit/templates/docker-compose-migration/COMPOSE-STANDARD.md`

---

## 1. Discovery

- [x] **Source path (Windows):** `E:\LocalDev\Laravel\myLaravel`
- [x] **Destination path (WSL):** `/home/masoud/personal/laravel/myLaravel` (confirmed not yet created)
- [x] **Git state:** Not a git repository (`git status` fails with "not a git repository" at the
      project root). No `.git` directory anywhere under the project. No remote, no history to
      preserve beyond the working tree itself.
- [x] **Compose files present:** `docker-compose.yml` (single file, no overrides). Services:
      `app`, `node`, `webserver`, `db`, `phpmyadmin`.
- [x] **Dockerfiles present:** `docker/php/Dockerfile` (PHP 8.2-FPM + Composer), `docker/node/Dockerfile`
      (Node 18-alpine). `.dockerignore` present at project root (`node_modules`, `*.log`, `*.lock`, `*.env`).
- [x] **`.env` files (names only):** `src/.env`, `src/.env.example`. Not read for values. Key
      names present in `src/.env` (confirmed via key-name-only scan): the standard Laravel set
      including `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`,
      `DB_PASSWORD`, plus `APP_*`, `MAIL_*`, `AWS_*`, `REDIS_*`, `VITE_*` keys. No values were read.
- [x] **Database type:** MySQL 8 (`image: mysql:8` in the compose file).
- [x] **Database data location:** **Bind mount** — `./dbdata:/var/lib/mysql`. Not a Docker-managed
      volume. `dbdata` is a real MySQL 8 datadir on the Windows filesystem (see Database risk below).
- [x] **Backup status:** **None found.** No `.sql` dump, no volume, no archive anywhere referencing
      this project's data. This is the highest-risk finding of this checklist.
- [x] **Existing container names, restart policies, ports, mounts, networks, volumes:**
  - The compose file itself has **no `container_name`** on any service and **no `restart:` policy**
    on any service already — both already satisfy the target standard as-is, nothing to remove.
  - Five stopped containers exist in Docker under the `mylaravel` compose project
    (`mylaravel-webserver-1`, `mylaravel-app-1`, `mylaravel-phpmyadmin-1`, `mylaravel-node-1`,
    `mylaravel-db-1`), all `Exited (0) 14 months ago`, restart policy `no`.
  - **Important:** those containers are bind-mounted to `E:\LocalDevelopments\myLaravel\...` —
    a *different, already-deleted* path, not the `E:\LocalDev\Laravel\myLaravel` project this
    checklist is migrating. They are historical remnants of an earlier, separate copy of this
    project and are **unrelated to the source being migrated here**. Confirmed via
    `docker inspect` — this migration's actual source path has no current container, volume, or
    network referencing it at all.
  - No Docker volume named anything like `mylaravel*` exists (consistent with the bind-mount
    finding above — there was never a named volume to find).
  - One network exists, `mylaravel_laravel_network` (bridge) — belongs to the old, unrelated
    `mylaravel` compose project above, not to this migration's source.
  - Two built images exist from the old project: `mylaravel-app` (873MB), `mylaravel-node` (181MB) —
    also tied to the old, already-deleted source path, not this one.
  - Original compose file's ports: `app` 9000:9000, `node` 5174:5174, `webserver` 80:80, `db`
    3306:3306, `phpmyadmin` 8081:80.
- [x] **Is the database folder readable, and does it appear non-empty:** **Partially readable.**
      Top-level `dbdata/` is listable and owned by UID 999 (the containerized MySQL server's
      internal user), mode `drwxr-x---`/`drwxrwxrwx` on the directory itself. Top-level files
      (`ibdata1`, `undo_001`, `undo_002`, `mysql.ibd`, `auto.cnf`, TLS certs, `ib_buffer_pool`)
      are readable and present with plausible non-trivial sizes. **Ten rotated binary logs**
      (`binlog.000001`–`binlog.000010`) are present — direct evidence of real write activity over
      time, not an idle/empty instance. A `laravel/` schema subdirectory exists (proving a
      database named `laravel` was created), but its **contents are not readable** from this
      user account (`Permission denied` — owned by UID 999, same restriction applies to
      `mysql/`, `performance_schema/`, `sys/`, and the two InnoDB temp/redo directories). `du -sh`
      on the whole folder reports 12M, but this **undercounts** — every protected subdirectory,
      including the `laravel/` schema itself, is excluded from that figure. **Conclusion: this is
      almost certainly a real, non-empty, previously-used database. Its exact size and table-level
      contents cannot be confirmed without elevated read access or a container-mediated read.**

## 2. Backup

**Revised approach, corrected a second time:** the first revision of this checklist deferred the
logical dump until *after* cutover, to be taken from the new WSL stack — but that stack starts
with an empty, freshly-created volume, so a dump taken there wouldn't contain the real data at
all and would validate nothing. The corrected sequence: physical copy first (done), then a
**logical dump taken from that already-isolated physical copy — before cutover, and never from
the original**.

- [x] Physical copy of `dbdata` taken — completed via a throwaway, self-removing container with
      the source mounted `:ro`. Original never opened for writing.
- [x] Physical copy verified non-empty and structurally plausible — all system files, all 10
      binlogs, TLS certs, and the protected `laravel`/`mysql`/`performance_schema`/`sys`
      subdirectories are present with sizes/mtimes matching the source.
- [x] Backup stored somewhere other than the source —
      `/home/masoud/docker-audit/project-checklists/myLaravel-backups/dbdata-copy` (~99MB+;
      readable portion alone sums to ~99M, real total is larger once the still-protected
      subdirectories are included).
- [x] Original source confirmed untouched — spot-checked file mtimes on `ibdata1` and
      `binlog.000001` after the copy; both unchanged from their original May 2025 timestamps.
- [x] **Logical dump taken from the isolated physical copy, before cutover** — completed via a
      further-revised approach: `lower_case_table_names=2` (required by the original data
      dictionary) only works on a case-insensitive filesystem, so the isolated copy was retaken
      onto NTFS (`E:\Dev-Backups\myLaravel\dbdata-recovery-copy`, confirmed case-insensitive via
      a filename-collision test) rather than reused from WSL-native storage. A temporary,
      `--network none`, no-published-ports container (exact original image digest
      `sha256:2764fe573c51...`, `--lower-case-table-names=2`) opened it cleanly — no InnoDB
      errors, no corruption. Dump:
      `/home/masoud/docker-audit/project-checklists/myLaravel-backups/myLaravel-logical-20260712-103028.sql`
      (12,231 bytes, SHA-256 `00f967d6b18a4617fbf036a45b934ff86e79e374accdfeaf1540ba1919987654`).
      11 tables, no uppercase/mixed-case identifiers found anywhere (low case-sensitivity risk
      for restore). Temporary container removed after the dump; original Windows source and both
      earlier WSL-side copies (`dbdata-copy`, `dbdata-copy-failed-mysql84-lctn-mismatch`) left
      untouched throughout.
- [x] **Restored into the final WSL-native stack** — imported cleanly (exit 0) into
      `mylaravel_wsl-db-1` (fresh named volume `mylaravel_wsl_dbdata`, `lower_case_table_names=0`,
      normal Linux default). All 11 tables and every row count verified matching the dump. A
      fresh post-migration dump was taken from the final database for the record:
      `myLaravel-post-migration-20260712-131056.sql` (15,849 bytes, SHA-256
      `22f0c94838107eea7a36955768725f23027fcfa54410ae84dc1fc575db1abfed`) — identical table set to
      the pre-migration dump, only cosmetic formatting differences.

## 3. Copy

- [x] `rsync` source → WSL destination — **real copy performed** via `migrate-project.sh`
      (no `--dry-run`). Completed with rsync exit code 23 ("partial transfer due to error") —
      see note below; not a failure of the migration.
- [x] `.git` preservation — not applicable, no `.git` directory exists in the source.
- [x] Local uncommitted files preserved — not applicable (no git state to diverge from).
- [x] Reinstallable dependency folders (`src/vendor/`, `src/node_modules/`) — copied in full
      (not excluded), consistent with the standard default. 12,680 files, 161M total at the
      destination.

**Note on the rsync exit code:** every one of the reported errors is confined to `dbdata/` —
the private key files, all 10 binlogs, `ibdata1`, the undo logs, and the contents of the
`laravel`/`mysql`/`performance_schema`/`sys`/`#innodb_redo`/`#innodb_temp` subdirectories failed
to copy with `Permission denied`, because `migrate-project.sh` runs as an unprivileged user and
those files are owned by MySQL's internal container UID (999) — the same restriction encountered
throughout Discovery. `src/`, `docker/`, `nginx/`, `docker-compose.yml`, and every other file
outside `dbdata/` copied with zero errors. This is expected and does not affect the migration:
the new WSL stack will use a fresh named volume for its database, not a bind mount to this
folder, and the authoritative database backup is the separately-taken, root-privileged physical
copy at `myLaravel-backups/dbdata-copy` (§2), which does not have this limitation. The
destination's partial `dbdata/` folder is inert — not referenced by the proposed `compose.yaml` —
and can be cleaned up later with your approval; nothing has been deleted.

## 4. Compose normalization

- [ ] `container_name` removed — N/A, none present in the original.
- [ ] `restart:` policy removed — N/A, none present in the original.
- [ ] `version:` field removed — N/A, none present in the original.
- [ ] Explicit, unique top-level `name:` set — **proposed:** `mylaravel_wsl` (distinguishes from
      the old, unrelated `mylaravel` Docker project still on record).
- [ ] Port conflicts resolved — proposed defaults preserve the original values
      (80 / 9000 / 5174 / 8081) but are now overridable via `.env.docker` if any collide with
      another WSL stack running at the same time (e.g. `laravelLivewireAdmin`, whose defaults are
      8080/5173/8081 — note **phpMyAdmin's default port (8081) would collide** with
      `laravelLivewireAdmin`'s if both are ever run with `--profile tools` simultaneously; flagged
      as an assumption below).
- [ ] `tools` profile configured for phpMyAdmin — proposed, not yet applied.
- [ ] Database healthcheck added — proposed, not yet applied.
- [ ] App service's `depends_on` upgraded to `condition: service_healthy` — proposed, not yet applied.
- [ ] Volume declared appropriately — proposed as a **plain (non-external) named volume** `dbdata`,
      since no WSL-side Docker volume exists yet for this project (unlike the `laravelLivewireAdmin`
      pilot, there is nothing pre-existing to adopt with `external: true` here — the volume will
      be newly created and then populated from the backup during actual cutover).
- [ ] No path in the file references `/mnt/e`, `/mnt/c`, `E:\`, or `C:\` — confirmed already true
      in the original (all paths are relative); will remain true in the proposed file.

## 5. Validation

- [x] `docker compose -f compose.yaml config` succeeds **in the final destination**
      (`/home/masoud/personal/laravel/myLaravel/compose.yaml`) — re-validated after placement, no
      errors, no path anywhere resolves outside `/home/masoud/personal/laravel/myLaravel`.
- [x] Containers report healthy — `mylaravel_wsl-db-1` healthy; `app`/`node`/`webserver` running,
      no healthcheck defined on them (consistent with the standard's scope).
- [x] Database opens — fresh instance, `mysql:8.4.5`, `lower_case_table_names=0` (normal Linux
      default), confirmed via `SELECT @@version` / `SELECT @@lower_case_table_names`.
- [x] Expected tables exist — all 11 tables present, identical set to the verified dump
      (`cache`, `cache_locks`, `categories`, `failed_jobs`, `job_batches`, `jobs`, `migrations`,
      `password_reset_tokens`, `posts`, `sessions`, `users`).
- [x] Application route works — homepage (`/`) returns HTTP 200 and renders real data ("Blog
      Homepage", Posts 1-3, Categories 1-4); post detail page (`/posts/1`) returns 200 with
      correct content; category filter (`/?category_id=1`) correctly filters the post list.
- [x] Key functional workflow works — the homepage's own database-backed post/category listing
      *is* the core functionality of this app; confirmed rendering restored data correctly.
- [x] Logs reviewed — `app`, `node`, `webserver`, `db` all clean; no errors/exceptions found.
- [x] Survives `docker compose restart` (not `down -v`) — `db` returns to healthy, homepage
      still returns 200, all restored rows (3 posts, 4 categories) still present afterward.
- [x] Real data restored into the new stack's volume, confirmed matching the §2 logical dump —
      row counts identical for every populated table (categories: 4, migrations: 5, posts: 3,
      sessions: 1), all known-empty tables (`cache`, `cache_locks`, `failed_jobs`, `job_batches`,
      `jobs`, `password_reset_tokens`, `users`) remain present and empty. A fresh post-migration
      dump (`myLaravel-post-migration-20260712-131056.sql`) has an identical table set to the
      pre-migration dump; the only diff is cosmetic (`mysqldump` explicitly restating
      `CHARACTER SET utf8mb4` on some columns in the newer dump where the older one omitted it
      as redundant) — no data or schema semantic difference.

**Case-sensitivity note (styling not yet independently verified):** the homepage loads Tailwind
via an external CDN script tag rather than a locally built asset — visual styling wasn't checked
via these `curl`-based tests. Per your instruction, any missing styling is a separate concern
from the database migration, not a migration failure, and would need a browser-based check to
confirm either way.

## 6. Cutover

- [x] **New WSL stack is now running**: `mylaravel_wsl-{app,db,node,webserver}-1`, `db` healthy,
      populated with the real, verified, restored data.
- [ ] Old Windows-side stack left stopped but available — N/A for this source path specifically
      (nothing currently runs against it); the *unrelated* old `mylaravel-*` containers pointing
      at the deleted `E:\LocalDevelopments\myLaravel` path are already stopped and untouched.
- [x] Zero Docker bind mounts reference a Windows path — confirmed via the re-validated
      `docker compose config` output above; every mount source resolves under
      `/home/masoud/personal/laravel/myLaravel`.
- [ ] Validation window completed — pending.
- [ ] Deletion of the Windows source requires **explicit, separate approval** — not requested,
      not proposed, not performed.

---

## Notes / deviations from the standard for this project

- Two nginx configs exist on disk: `nginx/default.conf` (the one actually referenced by
  `docker-compose.yml`) and an unused, stray top-level `nginx.conf` with a different document
  root and slightly different config. The proposed compose file continues referencing
  `nginx/default.conf` only. The stray file is left exactly as-is by the copy step — not deleted,
  not resolved, flagged for your awareness.
- **`lower_case_table_names` incompatibility discovered during the first temp-container
  verification attempt.** The original datadir's data dictionary requires
  `lower_case_table_names=2`; a plain `mysql:8` container defaults to `0`, and MySQL refuses to
  open a datadir under a mismatched setting (by design — it aborts rather than risk corruption).
  Confirmed this is **not** an image-drift issue: the exact original image
  (`mysql:8`, digest `sha256:2764fe573c51...`, `MYSQL_VERSION=8.4.5-1.el9`) is still cached
  locally and is bit-for-bit what both the original container and the failed retry used. The
  touched copy from that attempt was preserved as
  `myLaravel-backups/dbdata-copy-failed-mysql84-lctn-mismatch` (evidence, not deleted); a fresh,
  untouched copy was retaken into `myLaravel-backups/dbdata-copy`. `compose.yaml`'s `db` service
  is now pinned to `mysql:8.4.5` (never the floating `mysql:8`) and documents the intended
  restore workflow (temporary compatible container → logical dump → fresh volume → restore →
  run normally without `lower_case_table_names=2` unless the schema proves it's needed).
- `app`'s host-published port 9000 (raw PHP-FPM) is preserved by default per "preserve existing
  behavior," though nothing in the stack appears to need PHP-FPM reachable directly from the
  host — nginx reaches it internally via the service name. Worth reconsidering whether to drop
  it once the migration is validated; not changed unilaterally here.
