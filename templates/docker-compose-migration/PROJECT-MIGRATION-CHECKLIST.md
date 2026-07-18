# Project Migration Checklist

Copy this file per project (e.g. `checklist-ozCarLab.md`) and check items off as you go. It intentionally mirrors the phases in `migration-plan.md` (`~/docker-audit/migration-plan.md`) — this is the reusable, per-project version of that plan's execution pattern. Standards referenced below are defined in `COMPOSE-STANDARD.md`.

Project name: ________________________  Date started: ________________

---

## 1. Discovery

- [ ] Source path (Windows): `E:\...`
- [ ] Destination path (WSL): `/home/masoud/...`
- [ ] Git state: tracked? remote? last commit date? uncommitted changes?
- [ ] Compose files present: `docker-compose.yml` / `compose.yaml` / overrides — list all
- [ ] Database type: MySQL / PostgreSQL / MariaDB / MongoDB / none
- [ ] Database data location: named volume / anonymous volume / bind mount / container writable layer (**flag writable-layer-only as highest risk**)
- [ ] Backup status: does a usable backup already exist? how old is it?
- [ ] Existing container names (are any hardcoded via `container_name`?)
- [ ] Existing restart policies (any `always`/`unless-stopped` to remove?)
- [ ] Existing published ports (which will need `${VAR:-default}` treatment?)
- [ ] Existing networks (any external/shared networks to account for?)
- [ ] Existing volumes (named vs anonymous; which must become `external: true` in the new file?)

## 2. Backup

- [ ] **Physical copy of the database data directory taken first** — the primary, required
      pre-migration backup for a bind-mounted database. Read-only from the source (e.g. mount the
      source `:ro` into a throwaway copy container) so the backup step itself can never write to
      the original. This copy is now an isolated artifact, safely separate from the original.
- [ ] Physical copy verified non-empty and structurally plausible (system files present, a
      per-schema subdirectory exists, sizes are non-trivial) — full logical verification isn't
      always possible at this stage if the source is permission-protected; that's expected, not a
      blocker.
- [ ] Backup stored somewhere **other than** the source being migrated (per the end-state goal:
      Windows backup store, or at minimum a separate directory).
- [ ] **Logical dump taken from the isolated physical copy — not from the original, and not
      deferred until after cutover.** Start a temporary, disposable database container against
      *the copy* (never the original), confirm it opens cleanly (see Gotchas below), then run
      `mysqldump`/`pg_dump` against it. Stop and remove the temporary container once the dump is
      verified.
- [ ] Logical dump verified: file exists, is non-empty, contains real schema (`CREATE TABLE` /
      `CREATE DATABASE`) and application data — not just a header. Don't rely solely on counting
      `INSERT` statements; some tables may legitimately be empty, and some dump styles don't use
      `INSERT` at all.

**Lesson learned (revised twice):** the first pass through this checklist took a logical dump
from a temporary container before the copy step, directly risking the original. A later revision
overcorrected by deferring the logical dump until *after* cutover, to be taken from the new WSL
stack — but that stack starts with an empty, freshly-created volume, so a dump taken there
doesn't contain the real data at all and validates nothing. The correct sequence is the one
above: physical copy first (fast, low-risk, no credentials needed, fully protects the original),
then a logical dump from that already-isolated copy, before cutover — this is both safer (the
original is never opened by a database process, ever) and more meaningful (it proves the actual
migrated data opens cleanly and dumps correctly, not an empty placeholder).

## 2a. Temporary verification container — constraints

When starting a temporary database container against the physical copy to produce the logical
dump:
- Same database image/version as the original project (check the original compose file) —
  opening a datadir with a *different* major version than it was created with risks a one-way
  upgrade or a startup failure.
- Mount **only** the physical copy at the database's data path — never the original.
- Unique, obviously-temporary container name; no published host port; no restart policy; not
  attached to the project's real Compose network or its final named volume.
- Inspect startup logs before trusting it: watch for recovery errors, version-incompatibility
  messages, permission errors, or corruption warnings. If it doesn't come up cleanly, **stop —
  don't attempt an upgrade or repair** as part of a migration; that's a separate, deliberate
  decision.
- Credentials for connecting to a pre-populated datadir are whatever the *original* database was
  actually configured with — passing new bootstrap credentials via environment variables has no
  effect on a non-empty datadir (the image's first-run initialization is skipped entirely when
  data already exists). Avoid the password appearing as a literal `-p<value>` command-line
  argument (visible to anything that can see process listings) — use a short-lived credentials
  file inside the container instead, removed before the container is stopped.
- Stop and remove this container once the dump is verified — nothing about it persists.

## 3. Copy

- [ ] `rsync` source → WSL destination (see `migrate-project.sh --dry-run` first)
- [ ] `.git` preserved (never excluded)
- [ ] Local uncommitted files preserved (rsync copies the working tree as-is, not `git archive`)
- [ ] Reinstallable dependency/cache folders (`vendor/`, `node_modules/`, framework cache dirs) excluded **only if** you intend to reinstall them fresh in WSL — if in doubt, don't exclude; disk space is cheaper than a debugging session over a subtly different dependency tree
- [ ] Copy completed without errors; spot-check a file count or `du -sh` comparison between source and destination

## 4. Compose normalization

- [ ] `container_name` removed from every service
- [ ] `restart: always` / `unless-stopped` removed (or confirmed absent)
- [ ] Top-level `version:` field removed (or confirmed absent)
- [ ] Top-level `name:` set, explicit and unique (append `_wsl` if an old Windows-side project of the same name exists)
- [ ] Port conflicts resolved — cross-check against other projects you may run concurrently; assign a project-specific `.env.docker` default if the standard default (8080, 8081, etc.) is already taken
- [ ] `tools` profile configured for phpMyAdmin/pgAdmin (not started by default)
- [ ] Database healthcheck added
- [ ] App service's `depends_on` upgraded to `condition: service_healthy` for the database
- [ ] Volume declared `external: true` **only if** deliberately reusing an already-existing volume with real data; otherwise a plain (non-external) named volume declaration
- [ ] No path in the file references `/mnt/e`, `/mnt/c`, `E:\`, or `C:\`

## 5. Validation

- [ ] `docker compose -f compose.yaml config` succeeds with no errors
- [ ] Containers report healthy (`docker compose ps` shows `healthy`, not just `running`, for anything with a healthcheck)
- [ ] Database opens (connect with the app's own credentials, not just root)
- [ ] Expected tables/collections exist and look populated, not empty
- [ ] At least one application route/page loads successfully end-to-end
- [ ] One key functional workflow exercised manually (login, a CRUD action, whatever this project's core feature is — not just "the homepage loads")
- [ ] `docker compose logs` reviewed — no repeating errors/warnings in app, web, or db logs
- [ ] Project survives `docker compose restart` (containers come back up and remain healthy — catches state that only "worked" because it was never actually restarted)
- [ ] If real data was restored into the new stack's volume (from the §2 physical copy or logical
      dump), confirm it matches what the logical dump captured — row/table counts consistent,
      nothing silently dropped during restore

## 6. Cutover

- [ ] Old Windows-side stack left **stopped but not removed** — available as a fallback until confidence is high
- [ ] Confirmed zero Docker bind mounts anywhere in the new stack reference a Windows path (`/mnt/*`, `E:\`, `C:\`) — see rule 16 in `COMPOSE-STANDARD.md`
- [ ] Validation window completed (use your own judgment on duration — a few days of normal use is a reasonable minimum before treating the migration as final)
- [ ] Deletion of the old Windows-side source/containers/volume requires **explicit, separate approval** — never a default follow-on step after a successful migration. Nothing in this checklist authorizes deletion by itself.

---

**Notes / deviations from the standard for this project** (fill in — e.g. "no phpMyAdmin needed, project has no MySQL service"):

```
```
