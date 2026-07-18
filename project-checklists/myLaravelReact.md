# Project Migration Checklist — myLaravelReact

Project name: myLaravelReact
Source (Windows): `E:\LocalDev\Laravel\myLaravelReact`
Destination (WSL): `/home/masoud/personal/laravel/myLaravelReact`
Status: **Migration complete, cleanup pending.**

**This checklist only records what differs from the validated `myLaravel` migration
(`~/docker-audit/project-checklists/myLaravel.md`). Anything not mentioned here is materially
identical to that migration.**

## 1. Discovery — differences only

- Node dev server host port originally **5173** (not 5174) — reassigned to **5175** at runtime
  due to a live conflict, see §4.
- Node service `command: npm run dev` is commented out in the original compose file (`tty: true`
  used instead) — preserved as-is, not "fixed" to auto-start.
- Old container's MySQL image digest identical to `myLaravel`'s
  (`sha256:2764fe573c51062d1eadd39a78cc60aa85359bffec2451b7a9660f531bcfb53e`) — confirmed the
  `lower_case_table_names=2` incompatibility recurred exactly as expected.
- Old containers (`mylaravelreact-*`) bind-mounted to the already-deleted
  `E:\LocalDevelopments\Laravel\myLaravelReact` — unrelated to this migration's source, untouched.
- Not a git repository (same as `myLaravel`).
- `dbdata` has 2 binlogs (vs. 10) — less write history, no procedural difference.
- **Schema is materially different**: no custom application tables — only the 9 standard Laravel
  scaffolding tables. The application itself is a Laravel + Inertia.js + React starter
  (Breeze-style: `dashboard`, `profile.*`, `sanctum.csrf-cookie` routes), not a server-rendered
  Blade app — functional validation was adapted accordingly (see §5).

## 2. Backup

- [x] Physical copy of `dbdata` (WSL-side, evidence/safety copy) —
      `~/docker-audit/project-checklists/myLaravelReact-backups/dbdata-copy`. All top-level
      entries match source exactly (empty `diff`); original confirmed untouched afterward
      (`ibdata1`/`binlog.000001` mtimes unchanged).
- [x] Recovery required and performed — WSL-native ext4 is case-sensitive and this datadir
      requires `lower_case_table_names=2` (case-insensitive-only), so a fresh copy was taken
      directly onto NTFS (`E:\Dev-Backups\myLaravelReact\dbdata-recovery-copy`; case-insensitivity
      reconfirmed via the same filename-collision test used for `myLaravel`, on the same
      already-proven drive). Temporary container (`--network none`, no ports, exact original
      image digest, `--lower-case-table-names=2`) started cleanly — no InnoDB errors, no
      corruption, same benign world-writable `auto.cnf` removal as `myLaravel`. Confirmed via
      SQL: `version 8.4.5`, `lower_case_table_names=2`, `laravel` database present.
- [x] Logical dump taken from the isolated recovery copy —
      `myLaravelReact-logical-20260712-133812.sql` (10,088 bytes, SHA-256
      `0b03f916e10e8027486f43c40397030cb1aefad0a27b94c9c458765266f6d6e6`). 9 tables, no
      uppercase/mixed-case identifiers found (low case-sensitivity risk for restore). Temporary
      container removed afterward; original Windows source untouched throughout.

## 3. Copy

- [x] `rsync` source → `/home/masoud/personal/laravel/myLaravelReact` — real copy, exit code 23
      (same expected pattern: every error confined to `dbdata/`'s UID-999 permission wall,
      nothing outside it). 19,886 files, 212M at the destination.

## 4. Compose normalization

- [x] `compose.yaml` placed — project name `mylaravelreact_wsl`, `mysql:8.4.5` pinned, fresh
      non-external named volume, node `command`/`tty` preserved as original. `docker compose
      config` validated cleanly (exit 0).
- [x] **Port conflicts resolved at runtime** (not anticipated during Discovery — three of this
      project's default ports were already held by the concurrently-running
      `laravelLivewireAdmin_wsl` and `myLaravel_wsl` stacks):
      `VITE_DEV_PORT` 5173→**5175**, `APP_FPM_PORT` 9000→**9001**, `WEB_HTTP_PORT` 80→**8092**.
      Resolved via `.env.docker`/`.env.docker.example`, exactly the mechanism
      `COMPOSE-STANDARD.md` rule 6 exists for — no compose file change needed.

## 5. Validation

- [x] Fresh `db` healthy; `SELECT @@version` → `8.4.5`, `SELECT @@lower_case_table_names` → `0`
      (normal Linux default); `laravel` database present, empty.
- [x] Dump imported, exit code 0. All 9 tables present, matching the dump exactly; row counts
      independently verified equal (`migrations`: 3, `sessions`: 1, `users`: 1; all others 0 in
      both dump and restore).
- [x] Application started (`app`, `node`, `webserver`) after resolving the port conflicts above;
      logs clean across all four services.
- [x] Functional validation **adapted for this app's architecture** (Inertia/React, not
      server-rendered Blade): homepage returns HTTP 200 with a correct Inertia payload
      (`"auth":{"user":null}`, `"canLogin":true`, `"canRegister":true`, Laravel 12.12.0, PHP
      8.2.32); `/login` and `/register` return 200; `/dashboard` correctly returns **302**
      (auth-protected route redirecting an unauthenticated session) — this specifically proves
      the restored `users`/`sessions` tables are being read correctly by the app's auth
      middleware, a more meaningful check here than a static content comparison would have been.
- [x] Restart validated (`docker compose restart`, not `-v`) — db returns healthy, homepage still
      200, `/dashboard` still correctly 302 afterward.

## 6. Cutover

- [x] New WSL stack running: `mylaravelreact_wsl-{app,db,node,webserver}-1`, `db` healthy.
- [ ] Old Windows-side stack — N/A, nothing runs against this source; the unrelated old
      `mylaravelreact-*` containers remain stopped and untouched.
- [x] Zero Docker bind mounts reference a Windows path — confirmed via `docker compose config`.
- [ ] **Cleanup pending** — nothing removed yet (Windows source, both backup copies, NTFS
      recovery copy, both dumps, old Docker resources all still in place), awaiting separate
      approval.

## Post-migration dump

`myLaravelReact-post-migration-20260712-135811.sql` (13,533 bytes, SHA-256
`561b3c1916eeff86fe1f2165bd8f04f350aaca57e27f20b7835efeede5d9681e`) — table set confirmed
identical to the pre-migration dump.

---

## Notes / deviations

- Stray top-level `nginx.conf` exists here too (same pattern as `myLaravel`) — confirmed
  byte-identical to `myLaravel`'s stray file. Left as-is, not referenced by compose.
- **Framework required no modification.** Every step reused the exact validated `myLaravel`
  sequence; the only adaptations were runtime port reassignment (already anticipated by the
  standard) and swapping the functional-validation routes to match this app's different
  architecture (both expected, project-specific applications of the existing process, not
  changes to the process itself).
- **New operational lesson recorded** (see `migration-plan.md` §8): before the first
  `docker compose up` for any remaining project, proactively inspect currently occupied host
  ports and assign project-specific `.env.docker` values before startup, instead of discovering
  conflicts reactively one at a time.
