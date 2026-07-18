# Windows → WSL Docker Migration Playbook

Generated: 2026-07-11
Based on: `docker-audit-report.md`, `containers.tsv`, `images.tsv`, `volumes.tsv`, `networks.tsv`, `mounts.tsv`, `compose-projects.tsv`, `archive-matches.tsv`, `windows-projects.tsv` (all in `~/docker-audit/`)

**This is a planning document only. No command in this file has been executed. No file, container, image, volume, or network has been created, moved, deleted, or modified in producing it.**

Target end state (per your instructions):
- All Docker projects run from WSL (`/home/masoud/...`), not Windows paths.
- Source code lives in WSL.
- Windows (`E:\`) retains only backups and archives — no live project source, no live Docker bind mounts.
- Docker Desktop keeps using the WSL2 backend (already the case — no change needed there).

---

## 1. How to read this document

- **§2** — every project, ranked, with the fields you asked for.
- **§3** — dependencies that constrain migration order.
- **§4** — the execution checklist: numbered phases, each with Goal / Commands / Validation / Rollback.
- **§5** — post-migration keep/delete/archive summary per project.
- **§6** — final target WSL directory layout.
- **§7** — assumptions, open decisions, and things this plan deliberately does not do.
- **§8 / "Framework invariants" / "Audit corrections"** — the living record: what's actually been
  migrated, permanent binding rules discovered along the way, and factual corrections to §2.

---

## 2. Projects ranked by migration priority

Ranking logic: **live risk first** (running containers, source already deleted, unresolved duplication) → **active development** (recent commits) → **process value** (do an easy one early to prove the procedure) → **size/complexity** (tackle the biggest, riskiest one once the procedure is proven) → **dormant/no-Docker-relationship** last.

| # | Project | Tier | Docker dependency | DB location | Backup status | Risk | Complexity | Cleanup benefit |
|---|---|---|---|---|---|---|---|---|
| 1 | **`login` family** (3 copies + 29-archive trail) — see §2.1 | 🔴 Critical | `mysql_db` container **running now**; `php_backend`/`react_frontend` stopped | Bind mount, 3 different `db_data` locations | Partial (29 `.rar` snapshots, none current) | **Highest** — running container may serve stale pre-JWT code while newest work sits unmigrated | High (needs a decision, not just a copy) | Medium |
| 2 | `laravelLivewireAdmin` | 🟠 High | 4 stopped containers, image, **named volume** | Docker-managed named volume (`laravellivewireadmin_dbdata`, 211.6MB) | None | Low | **Low** (cleanest DB migration of the whole set) | Medium |
| 3 | `quizGameVtwo` | 🟠 High | 4 containers, **1 running now** (`quiz-phpmyadmin`) | Bind mount (`docker\mysql\data`) | None | Medium | Medium | Medium |
| 4 | `quizGameVfour` (+ resolve `-1`/`-2` duplicates) | 🟠 High | 4 stopped containers, image | Bind mount, but DB dir not found on disk at this path (app-only stack) | None | Medium | Medium | Medium (+High once duplicates removed) |
| 5 | `ozCarLab` | 🟠 High | 3 stopped containers, images `ozcarlab-web` (13.3GB) + `ozcar-web` (10.1GB) | Bind mount `pg_data`, permission-protected, real | Partial — `ozcar.pg_dump` (9.38GB) + `ozcar_backup.sql` (4.25GB), but ~17 months stale | Medium-High (biggest single project, stale backup) | **High** (multi-service, huge data, two sub-apps) | **Very High** (largest reclaimable footprint) |
| 6 | ~~`swf_uploader_apis` (restore-from-archive)~~ | ⚫ **Archived only — excluded from migration scope (2026-07-18)** | Image exists (1.13GB), **no live source anywhere** | Full raw MySQL datadir inside the `.rar` | Complete (source + DB in `.rar`) | N/A — not migrating | N/A — not migrating | N/A — archive kept as-is, nothing to reclaim |
| 7 | `myLaravel` | 🟡 Medium | None current (successor of a lost project) | Bind mount `dbdata`, real, never Dockerized at this path | None | Medium (unbacked-up real DB data) | Low | Medium |
| 8 | `myLaravelReact` | 🟡 Medium | None current (successor of a lost project) | Bind mount `dbdata`, real | None | Medium | Low | Medium |
| 9 | `myLaravelReactNew` | 🟡 Medium | None current (successor of a lost project) | Bind mount `dbdata`, real | None | Medium | Low | Medium |
| 10 | `quizGame` | 🟡 Medium | None current (successor of a lost project) | Bind mount `dbdata`, real | None | Medium | Low | Medium |
| 11 | `quizGameVthree` | 🟢 Low | Image only (`quizgamevthree-app`, 1.16GB), 0 containers | None found | None | Low | Low | Low-Medium |
| 12 | `herd/my-project` | ⚫ **Deferred — excluded from this migration effort's scope (2026-07-18)** | None | None | None | N/A — not migrating | N/A — not migrating | N/A |
| 13 | `ozoffroad` | 🟢 Low | None | None | None | Low | Low | Low |
| 14 | `multi-container-app` | 🟢 Low | None (zero trace in Docker) | None | None | Low | Low | Low |
| 15 | `React/react-app` | 🟢 Low | None (zero trace in Docker) | None | None | Low | Low | Low |
| 16 | `Oxin game` | 🟢 Low | None — not a coding project | None | Partial (`.sql`, `.rar` already there) | Low | Low (archive, don't "migrate") | Low |
| 17 | `myLaravelAPI` / `myLaravelCRUD` / `myLaravelProject` | ⚪ Trivial | None | None | N/A (empty) | None | None | Negligible |
| 18 | `quizGameVfour-1`, `quizGameVfour-2` | ⚪ Cleanup | Duplicate of #4 | None | N/A | None (once diffed) | Low | Low-Medium (disk only) |
| 19 | `react-login` | ⚪ Cleanup | Duplicate of #1 | Bind mount `db_data`, real | None | Low (superseded) | Low | Low-Medium |
| 20 | `React/backups` (29 `.rar`) | ⚪ Archive | Backup trail for #1 | N/A | Is itself the backup | None | Low (relocate, don't migrate) | Low (disk only) |

Already in WSL, **not migration targets**, but affected by the end-state goal (see §5.4): `sadaqa_new_api`, `python-learning/sales-analytics-service`, `python-learning/faster-whisper-project`, `dotnet-learning/HelloApi`.

### 2.1 Why the `login` family is ranked #1

This is the only situation in the whole audit where **a container is running right now against source code that's provably behind your most recent work**:

- `E:\LocalDevelopments\React\login` — the path the running `mysql_db` container (plus stopped `php_backend`/`react_frontend`) bind-mounts to. Its `backend/`/`frontend/` folders are already deleted.
- `E:\LocalDev\React\login` — git-tracked, remote `github.com/masoodbarzegar/react-auth`, latest commit 2025-03-31 "Implement frontend JWT authentication" — not wired to any current Docker resource.
- `E:\LocalDev\React\react-login` — an unversioned duplicate of the *original* (pre-JWT) setup, same container names as the running one.
- `E:\LocalDev\React\backups\*.rar` — 29 dated snapshots (Feb–May 2025) that trace the development history.

Migrating any one of these to WSL without first deciding which is authoritative would just relocate the confusion. This has to be resolved by inspection/decision before it's touched — see Phase 1 in §4.

---

## 3. Dependencies that constrain migration order

1. **`login` family must be reconciled before any of its three copies is migrated** (§2.1). Everything else in the family (backup consolidation, eventual deletion of superseded copies) depends on this decision.
2. **`quizGameVfour-1`/`quizGameVfour-2` should be diffed against `quizGameVfour` before (or immediately after) migrating `quizGameVfour`** — no need to migrate three copies of the same thing to WSL.
3. **`ozCarLab` needs a fresh backup before migration**, not just the existing 17-month-old one — do this after Phases 2–4 have proven the migration procedure works, since it's the highest-stakes single project (13.3GB + 10.1GB images, 6GB+ live DB).
4. **Container name collisions inside the `login` family**: all three copies hard-code `container_name: php_backend / react_frontend / mysql_db` in their compose files. Only one can run in Docker at a time as-is — this is a structural reason the copies can't simply be "all migrated" without renaming, reinforcing the need to pick one.
5. **No cross-project runtime dependencies exist** otherwise — every other project is an independent Laravel/React/.NET/Python stack with its own containers, images, networks, and (mostly) bind-mounted DB. They can be migrated in any order relative to each other; the ranking in §2 is about risk and process, not technical coupling.
6. **Already-WSL projects are unaffected** by any of this and need no migration — only an archive-relocation step (§5.4).

---

## 4. Step-by-step execution checklist

General per-project migration pattern (referenced by each phase below):

```
A. Backup DB data at the source (mysqldump/pg_dump, or tar the bind-mount folder if the DB container can't be started)
B. rsync source tree from E:\... into ~/projects/<category>/<name>  (excludes: vendor, node_modules, .git objects don't need excluding — rsync handles git fine)
C. Rewrite docker-compose.yml bind-mount paths (they're already relative, so this is often a no-op) and any Windows-specific paths in .env files
D. docker compose up -d in WSL; validate
E. Once validated, stop (don't remove) the Windows-side containers; archive the Windows source folder; do NOT delete Windows source until a validation window has passed
```

### Phase 0 — Pre-flight (one-time, applies to everything below)

**Goal:** Create the WSL target layout and a Windows-side backup root, and confirm the environment is ready, before touching any project.

**Commands:**
```bash
# WSL side: create the target layout (see §6 for full tree)
mkdir -p ~/projects/{laravel,react,python,dotnet,archive-staging}

# Confirm Docker Desktop is on the WSL2 backend (should already say "Docker Desktop" / WSL2 kernel)
docker info | grep -E "Operating System|Kernel Version"

# Confirm free space in WSL's virtual disk before pulling ~30GB+ of project data across
df -h ~
```
```powershell
# Windows side (run in PowerShell, not WSL): create a consolidated backup root
New-Item -ItemType Directory -Path "E:\Dev-Backups" -Force
New-Item -ItemType Directory -Path "E:\Dev-Backups\login-history" -Force
```

**Validation:** `~/projects/laravel`, `~/projects/react`, `~/projects/python`, `~/projects/dotnet` exist; `docker info` confirms WSL2 backend; `E:\Dev-Backups` exists.

**Rollback:** Nothing was touched except empty directory creation — delete the empty dirs if you change your mind. No project data is at risk in this phase.

---

### Phase 1 — Resolve the `login` family (must happen before Phase 6)

**Goal:** Decide which `login` copy is authoritative before migrating any of them, and protect the currently-running container's data in the meantime.

**Commands:**
```bash
# 1. Snapshot the RUNNING container's DB right now, before anything else happens to it
docker exec mysql_db mysqldump -u root -p --all-databases > ~/docker-audit/login-mysql_db-snapshot-$(date +%Y%m%d).sql
# (you'll be prompted for the root password used by this container -- not something I have or need)

# 2. Compare what tables/schema the running DB actually has vs. what the newer LocalDev/React/login code expects
docker exec mysql_db mysql -u root -p -e "SHOW TABLES;" mydatabase
grep -riE "migration|schema|CREATE TABLE" /mnt/e/LocalDev/React/login/backend/*.sql 2>/dev/null | head -20

# 3. Read (don't run) the newer copy's backend code to see what auth flow it expects,
#    compared to what's actually running -- this is a manual read, not a scripted step
```

**Validation:** You can answer, in writing: "the running container is / is not serving the JWT-auth version." Save that answer — it decides Phase 6.

**Rollback:** This phase is entirely read-only except for writing a `.sql` dump to your own `~/docker-audit/` folder — nothing to roll back.

**Decision output required before Phase 6:** which of these three you're keeping as canonical:
- (a) `E:\LocalDevelopments\React\login` (the running one, source gone) — if the DB data matters more than the newer frontend work, migrate the DB and re-attach it to the newer `E:\LocalDev\React\login` backend.
- (b) `E:\LocalDev\React\login` (JWT auth work) — most likely correct answer, but confirm the DB schema it expects.
- (c) A merge: newer code + running database.

---

### Phase 2 — Pilot migration: `laravelLivewireAdmin` (prove the procedure on the easiest case)

**Goal:** Move the most recently active, cleanest project (Docker-managed named volume, no bind-mount DB mess) to WSL first, to validate the whole procedure before higher-stakes projects.

**Commands:**
```bash
# A. Backup the named volume (safe, read-only from Docker's perspective)
docker run --rm -v laravellivewireadmin_dbdata:/from -v ~/docker-audit:/to alpine \
  tar czf /to/laravellivewireadmin_dbdata-backup-$(date +%Y%m%d).tar.gz -C /from .

# B. Copy source into WSL
mkdir -p ~/projects/laravel
rsync -avh --progress "/mnt/e/LocalDev/Laravel/laravelLivewireAdmin/" ~/projects/laravel/laravelLivewireAdmin/

# C. Inspect compose file for anything Windows-path-specific (usually nothing, since mounts are relative)
grep -n "E:\\\\\|/mnt/e" ~/projects/laravel/laravelLivewireAdmin/docker-compose.yml

# D. Bring it up in WSL using a NEW volume first (don't touch the original until validated)
cd ~/projects/laravel/laravelLivewireAdmin
docker compose up -d
docker compose ps

# Restore the backed-up data into the new WSL-side volume/container if the fresh container needs seeded data:
docker run --rm -v laravellivewireadmin_dbdata:/to -v ~/docker-audit:/from alpine \
  sh -c "cd /to && tar xzf /from/laravellivewireadmin_dbdata-backup-*.tar.gz"
```

**Validation:**
```bash
docker compose logs --tail 50
curl -I http://localhost:<port-from-compose>   # expect HTTP 200/302, not connection refused
docker exec -it <db-container> mysql -u root -p -e "SHOW TABLES;" laravellivewireadmin  # compare table count to what you expect
```

**Rollback:** The Windows copy (`E:\LocalDev\Laravel\laravelLivewireAdmin`) and its original named volume are untouched — if the WSL copy fails, `docker compose down` in WSL and delete `~/projects/laravel/laravelLivewireAdmin`. Nothing on Windows was modified.

---

### Phase 3 — `quizGameVtwo` (has a running container right now)

**Goal:** Migrate the project currently backing the running `quiz-phpmyadmin` container.

**Commands:**
```bash
# A. Backup the bind-mounted MySQL data directory directly (container likely needs to be stopped for a clean copy,
#    or use mysqldump against the running instance for a consistent snapshot instead)
docker exec quiz-mysql mysqldump -u root -p --all-databases > ~/docker-audit/quizgamevtwo-db-backup-$(date +%Y%m%d).sql

# B. Copy source
rsync -avh --progress "/mnt/e/LocalDev/Laravel/quizGameVtwo/" ~/projects/laravel/quizGameVtwo/

# C/D. Bring up in WSL, restore the dump into the new container's MySQL
cd ~/projects/laravel/quizGameVtwo
docker compose up -d
docker exec -i <new-mysql-container> mysql -u root -p < ~/docker-audit/quizgamevtwo-db-backup-*.sql
```

**Validation:** App reachable on its port; `SHOW TABLES` row/table counts match the pre-migration dump; phpMyAdmin reachable and shows the same schema.

**Rollback:** Stop the WSL stack (`docker compose down`); the Windows containers (`quiz-mysql`, `quiz-phpmyadmin`, etc.) are untouched and can keep running exactly as before until you're satisfied.

---

### Phase 4 — `quizGameVfour` + resolve the `-1`/`-2` duplicates

**Goal:** Migrate the current `quizGameVfour`, and confirm the two duplicate folders are safe to archive/delete rather than also migrating them.

**Commands:**
```bash
# Confirm the duplicates really are identical before deciding not to migrate them
diff -rq "/mnt/e/LocalDev/Laravel/quizGameVfour/src" "/mnt/e/LocalDev/Laravel/quizGameVfour-1/quizGameVfour/src" | head -50
diff -rq "/mnt/e/LocalDev/Laravel/quizGameVfour/src" "/mnt/e/LocalDev/Laravel/quizGameVfour-2/quizGameVfour/src" | head -50

# Migrate the main copy (same pattern as Phase 3)
rsync -avh --progress "/mnt/e/LocalDev/Laravel/quizGameVfour/" ~/projects/laravel/quizGameVfour/
cd ~/projects/laravel/quizGameVfour
docker compose up -d
```

**Validation:** `diff -rq` output is empty or only shows expected noise (`.env`, cache files) — confirms `-1`/`-2` are true duplicates, safe to archive-only. App reachable in WSL on expected port.

**Rollback:** Same as Phase 3 — Windows copy and containers untouched until validated.

---

### Phase 5 — `ozCarLab` (largest, highest-stakes — do this once the procedure is proven)

**Goal:** Migrate the biggest, most complex project, with a **fresh** backup (the existing one is ~17 months stale).

**Commands:**
```bash
# A. Take a FRESH backup first -- the existing ozcar.pg_dump/ozcar_backup.sql are from Feb 2025
docker exec ozcarlab-db-1 pg_dump -U <user> <dbname> > ~/docker-audit/ozcarlab-pg-fresh-$(date +%Y%m%d).sql
# (if the container isn't running, start it read-only-intent first: docker compose up -d db  -- from the ozCarLab dir)

# B. Copy source (this will take a while -- 6GB+ over the 9P bridge)
rsync -avh --progress "/mnt/e/LocalDev/ozCarLab/" ~/projects/laravel/ozCarLab/ \
  --exclude 'ozcar.pg_dump' --exclude 'ozcar_backup.sql'   # move the huge backup files separately, see below

# C. Move (don't duplicate) the two huge backup files straight to the Windows backup root instead of into WSL,
#    since the end goal is "Windows only stores backups" -- these ARE backups, they belong there, not in WSL
#    (illustrative -- run from PowerShell, not WSL, since these are Windows-native files)
#    Move-Item E:\LocalDev\ozCarLab\ozcar.pg_dump E:\Dev-Backups\
#    Move-Item E:\LocalDev\ozCarLab\ozcar_backup.sql E:\Dev-Backups\

# D. Bring up in WSL, restore the fresh dump
cd ~/projects/laravel/ozCarLab
docker compose up -d
docker exec -i <new-postgres-container> psql -U <user> <dbname> < ~/docker-audit/ozcarlab-pg-fresh-*.sql
```

**Validation:** Both sub-apps (`ozcar`, `ozhub_repo`) reachable; `psql -c "\dt"` table list matches pre-migration; row counts on a couple of key tables spot-checked against the fresh dump.

**Rollback:** Windows `ozCarLab` containers/data untouched until validated (note: `pg_data` is permission-protected — do not attempt to directly copy it; use `pg_dump`/`pg_restore` only, which is what the commands above do).

---

### Phase 6 — `login` family final migration (uses the Phase 1 decision)

**Goal:** Migrate the single authoritative `login` copy decided in Phase 1, retiring the other two as archives.

**Commands (template — fill in based on Phase 1's decision):**
```bash
rsync -avh --progress "/mnt/e/LocalDev/React/login/" ~/projects/react/login/
# If Phase 1 decided the RUNNING container's data is what matters, also bring that database across:
docker exec mysql_db mysqldump -u root -p --all-databases > ~/docker-audit/login-final-db-$(date +%Y%m%d).sql
cd ~/projects/react/login
docker compose up -d
docker exec -i <new-mysql-container> mysql -u root -p < ~/docker-audit/login-final-db-*.sql
```

**Validation:** Login/register flow works end-to-end against the WSL stack; JWT auth (if that's the copy you kept) issues and validates tokens correctly.

**Rollback:** Windows-side `mysql_db`/`php_backend`/`react_frontend` untouched until validated.

---

### Phase 7 — `swf_uploader_apis` (restore from archive, not copy — special case)

> **Out of scope as of 2026-07-18** — intentionally excluded from migration; see §8. Left here
> only as historical record of the original plan; do not execute.

**Goal:** Recreate this project in WSL from `~/Sadaqa-old-archive/swf_uploader_apis.rar`, the *only* remaining copy of both its source and database.

**Commands:**
```bash
mkdir -p ~/projects/laravel/swf_uploader_apis
unrar x ~/Sadaqa-old-archive/swf_uploader_apis.rar ~/projects/laravel/swf_uploader_apis/
cd ~/projects/laravel/swf_uploader_apis/swf_uploader_apis
docker compose up -d
# The raw MySQL datadir is inside docker/mysql/data -- point the compose bind mount at it directly,
# or (safer) start a throwaway mysql container against it, mysqldump out, then import into a fresh volume.
```

**Validation:** App boots; MySQL container starts cleanly against the restored datadir (check `docker compose logs db` for InnoDB recovery errors — raw datadir copies can be finicky about a clean shutdown state).

**Rollback:** You're extracting into a new WSL directory — if it doesn't work, delete `~/projects/laravel/swf_uploader_apis` and retry. The `.rar` itself is untouched (extraction is non-destructive to the source archive).

---

### Phase 8 — Successor copies: `myLaravel`, `myLaravelReact`, `myLaravelReactNew`, `quizGame`

**Goal:** These have real, unbacked-up `dbdata` but are not currently used by Docker at all. Decide per-project: resume development (migrate) or retire (backup + archive only).

**Commands (per project, repeat with the right path):**
```bash
# Backup first regardless of the keep/archive decision -- this data has no other copy anywhere
tar czf ~/docker-audit/myLaravel-dbdata-backup-$(date +%Y%m%d).tar.gz -C /mnt/e/LocalDev/Laravel/myLaravel dbdata
# (repeat for myLaravelReact, myLaravelReactNew, quizGame with their respective dbdata paths)

# If resuming development, migrate exactly like Phase 3/4:
rsync -avh --progress "/mnt/e/LocalDev/Laravel/myLaravel/" ~/projects/laravel/myLaravel/
```

**Validation:** `tar tzf` the backup to confirm it's non-empty and readable before considering the Windows copy safe to archive.

**Rollback:** N/A — this phase is backup + optional copy, nothing destructive.

---

### Phase 9 — Consolidate archives and clean up dormant/no-relationship projects

**Goal:** Move backup material to the Windows backup root; leave truly dormant, non-Dockerized projects where they are unless you want them gone.

**Commands:**
```powershell
# Windows side -- consolidate the login backup trail
Move-Item "E:\LocalDev\React\backups\*.rar" "E:\Dev-Backups\login-history\"

# Consolidate the two tiny loose root archives
Move-Item "E:\LocalDev\myLaravel- existing laravel.rar" "E:\Dev-Backups\"
Move-Item "E:\LocalDev\quizGame.rar" "E:\Dev-Backups\"
```

**Validation:** `E:\Dev-Backups` contains the consolidated archive set; `React\backups` is empty or removed.

**Rollback:** These are `Move-Item`, not deletes — reversible by moving back if needed.

**Not migrated, left as-is pending your review:** `herd/my-project`, `ozoffroad`, `multi-container-app`, `React/react-app`, `Oxin game`, `quizGameVthree`, the three empty `myLaravelAPI`/`CRUD`/`Project` folders, `quizGameVfour-1`/`-2`, `react-login`. See §5 for the specific recommendation on each.

---

### Phase 10 — Final verification

**Goal:** Confirm the end state matches your stated goal before considering the migration complete.

**Commands:**
```bash
# Every project's compose file now under ~/projects, none under /mnt/e
grep -rl "docker-compose\|compose.yaml" ~/projects/ | wc -l

# Docker Desktop still on WSL2 backend
docker info | grep -E "Operating System|Kernel Version"

# No container currently bind-mounts anything under /mnt/e or E:\
docker ps -a --format '{{.Names}}' | xargs -I{} docker inspect {} --format '{{.Name}}: {{range .Mounts}}{{.Source}} {{end}}' | grep -i "mnt/e\|E:\\\\"
```

**Validation:** The last command returns nothing — no running or stopped container references a Windows path anymore.

**Rollback:** N/A — this is a read-only verification pass.

---

## 5. Post-migration: keep / delete / archive, per project

| Project | After migration: KEEP | ARCHIVE (move to `E:\Dev-Backups`) | Safe to DELETE (only after archive + validation window) |
|---|---|---|---|
| `login` family | The one authoritative copy, now in WSL | The other two copies + 29 `.rar` backups | The two superseded copies, once WSL version is confirmed working for a few days |
| `laravelLivewireAdmin` | WSL copy + its Docker named volume | — (volume backup can be deleted once WSL volume confirmed) | Windows source, once WSL app + DB validated |
| `quizGameVtwo` | WSL copy | DB dump made in Phase 3 | Windows source + old bind-mount data dir |
| `quizGameVfour` | WSL copy | — | Windows source; **and** `quizGameVfour-1`, `quizGameVfour-2` in full once `diff` confirms they're pure duplicates |
| `ozCarLab` | WSL copy | `ozcar.pg_dump`, `ozcar_backup.sql`, plus the fresh Phase 5 dump | Windows source, once both sub-apps validated in WSL. Also safe to delete the redundant `~/local_dev/ozCarLab` WSL staging copy (6.3GB) once the real migrated copy is confirmed. |
| `swf_uploader_apis` | New WSL copy (restored from archive) | Keep `swf_uploader_apis.rar` regardless — it's your only historical snapshot | Nothing — the empty `~/swf_uploader_apis/docker/mysql` scaffold can be deleted once the real restore (Phase 7) succeeds |
| `myLaravel`/`myLaravelReact`/`myLaravelReactNew`/`quizGame` | WSL copy, only if you decide to resume development | The `dbdata` backup either way | Windows source, once backup confirmed and (if migrating) WSL copy validated |
| `quizGameVthree` | — (unless you want to resume it) | Full folder, as-is | Windows source, once archived |
| `herd/my-project`, `ozoffroad`, `multi-container-app`, `React/react-app` | — | Full folder if you might want it later | Windows source, once archived (no Docker dependency, low risk) |
| `Oxin game` | — | Already mostly a backup itself — move as-is | Nothing extra to do |
| `myLaravelAPI`/`CRUD`/`Project` | — | Nothing (empty) | Yes — immediately, they're empty |
| `react-login` | — | Nothing unique (superseded duplicate) | Yes, once `login` family (Phase 1/6) is resolved |
| `React/backups` (29 `.rar`) | — | Move to `E:\Dev-Backups\login-history\` | Nothing to delete — it IS the archive |

### 5.4 Archive relocation for already-WSL projects

Per your end-state goal ("Windows only stores backups and archives"), the following currently sit **in WSL** but are themselves backup archives, not live projects — they logically belong on the Windows backup store instead, once you're comfortable:

- `~/Sadaqa-old-archive/sadaqa_new_api.rar`, `swf_uploader_apis.rar`, `sadaqat83_sadaqawelfare807_database.sql`
- `~/python-learning/sales-analytics-service.rar`
- `~/dotnet-learning/ProjectManagement*.zip/.rar` (not Docker-related, but same principle applies)

Recommendation: leave them in WSL until Phase 7 (`swf_uploader_apis` restore) is validated — you may still need to re-extract from them — then relocate to `E:\Dev-Backups` as a final tidy-up step, keeping WSL to live source only.

---

## 6. Final target WSL directory layout

```
/home/masoud/
├── projects/
│   ├── laravel/
│   │   ├── laravelLivewireAdmin/       (Phase 2)
│   │   ├── quizGameVtwo/               (Phase 3)
│   │   ├── quizGameVfour/              (Phase 4)
│   │   ├── ozCarLab/                   (Phase 5)
│   │   ├── swf_uploader_apis/          (Phase 7, restored from archive)
│   │   ├── myLaravel/                  (Phase 8, only if resumed)
│   │   ├── myLaravelReact/             (Phase 8, only if resumed)
│   │   ├── myLaravelReactNew/          (Phase 8, only if resumed)
│   │   └── quizGame/                   (Phase 8, only if resumed)
│   ├── react/
│   │   └── login/                      (Phase 6, single authoritative copy)
│   ├── python/
│   │   ├── sales-analytics-service/    (already here)
│   │   └── faster-whisper-project/     (already here)
│   ├── dotnet/
│   │   └── HelloApi/                   (already here)
│   └── sadaqa_new_api/                 (already here, or move under a laravel/ or php/ subfolder if you prefer consistency)
├── docker-audit/                       (existing audit reports + this playbook)
└── (no long-term archive storage here — see §5.4)
```

```
E:\
├── Dev-Backups\                        (new — everything backup/archive lives here)
│   ├── login-history\                  (29 .rar snapshots from React\backups)
│   ├── ozcar.pg_dump
│   ├── ozcar_backup.sql
│   ├── myLaravel- existing laravel.rar
│   ├── quizGame.rar
│   └── ...per-project dbdata/db backups made during migration
├── LocalDev\                           (emptied out project-by-project as each migration + validation window completes)
└── LocalDevelopments\                  (emptied out as Phase 1/6 resolves)
```

---

## 7. Assumptions and open decisions

- **DB credentials**: every backup/restore command above needs the actual MySQL/Postgres root credentials for that specific container — I don't have and didn't try to read these (per the original audit's no-secrets rule). You'll need to supply them at execution time.
- **Windows-side commands**: file moves on `E:\` are shown as PowerShell (`Move-Item`), since that's the native, safest way to manipulate NTFS permissions/attributes correctly — running them from WSL via `/mnt/e` also works but is slower and can occasionally mishandle Windows file locks.
- **Concurrent stacks**: several projects share default ports (3306, 8080, 8081) and (in the `login` family) hard-coded container names. This plan assumes you validate one migrated project at a time (bring it up, check it, take it down or leave it running, then move to the next) rather than running everything simultaneously. If you want several WSL stacks running concurrently long-term, each `docker-compose.yml` will need unique `container_name`s and host ports — not addressed here since it's a design decision, not a migration mechanic.
- **`ozCarLab` backup freshness**: Phase 5 assumes you can start the Postgres container long enough to run `pg_dump`. If it's been broken/unstartable for a while, that needs troubleshooting before Phase 5, which is outside this plan's scope.
- **This plan makes no assumption about timeline** — phases are ordered by risk/dependency, not by calendar. Pace them however you like.
- **Nothing in this document has been executed.** Every command shown is for your future use; re-verify paths and container/volume names at execution time in case anything has changed since this audit (2026-07-11).

---

## 8. Migration Progress Tracker (live status — updated as migrations actually happen)

This section is the running record of what has actually been done, as distinct from §2–§7 which remain the original plan. Update it after each project completes.

| Project | Status |
|---|---|
| **`laravelLivewireAdmin`** | Pilot migration complete (see `~/personal/laravel/laravelLivewireAdmin`). Stack validated, running. |
| **`myLaravel`** | **Migration complete, cleanup pending.** See detail below. |
| **`myLaravelReact`** | **Migration complete, cleanup pending.** See detail below. |
| **`myLaravelReactNew`** | **Migration complete, cleanup pending.** See detail below. |
| **`ozCarLab`** | **Migration complete, cleanup pending.** First migration outside the MySQL/Laravel envelope — PostgreSQL/CakePHP. See detail below. |
| **`quizGameVtwo`** | **Migration complete, cleanup pending.** See detail below. |
| **`quizGameVthree`** | **Migration complete, cleanup pending.** See detail below. |
| **`quizGameVfour`** | **Migration complete, cleanup pending.** See detail below. |
| **`login`** | **Migration complete, cleanup pending.** Authoritative copy resolved via read-only investigation (`/mnt/e/LocalDev/React/login`); see detail below. |
| **`quizGame`** | **Migration complete, cleanup pending.** See detail below. |
| **`swf_uploader_apis`** | **Archived only (not migrated).** Intentionally excluded from migration scope (2026-07-18) — legacy project with no future value. Archive (`swf_uploader_apis.rar`) retained for historical purposes; nothing restored into WSL, no further action planned. |
| **`multi-container-app`** | **Migration complete, cleanup pending.** Source-copy-only, no database recovery phase (ephemeral MongoDB by original design). See detail below. |
| **`ozoffroad`** | **Migration complete, cleanup pending.** Source-only — no recoverable database exists anywhere on the source machine (evidence recorded, not an error). Application itself has a pre-existing, unrelated boot-blocking gap (missing `MobileValidator` plugin, never committed to git). See detail below. |
| **`React/react-app`** | **Migration complete, cleanup pending.** Source-copy-only — plain client-side `create-react-app` scaffold, no backend/database by design. See detail below. |
| **`herd/my-project`** | **Deferred — not migrated.** Explicitly excluded from this migration effort's scope per direct instruction (2026-07-18); no read-only preflight performed. May be reconsidered separately in the future. |
| All others | Not yet started. |

## Audit corrections

Factual corrections to the original read-only audit (§2 table and elsewhere), discovered as a
byproduct of actually executing migrations. The audit itself is not being re-run — these are
noted here so future reads of §2 aren't misled by evidence that later migrations have overturned.

- **`quizGameVthree`'s database location** — the original audit listed "None found" for this
  project's DB. This was wrong: it has a real bind-mounted MySQL datadir with live data (`quiz`
  schema, `ibdata1`, binlogs), structurally identical to `quizGameVtwo`. Discovered during the
  `quizGameVthree` migration preflight (2026-07-16).
- **`quiz-phpmyadmin` "running now" claim** (original audit, informing `quizGameVtwo`'s #3
  priority ranking) — was already stale by the time `quizGameVtwo`'s migration began; all of that
  project's containers were `Exited`. Not a factual error in the audit at the time it was written,
  but a reminder that container-running-state facts age quickly and should be re-verified at
  preflight, not trusted from the original audit alone.
- **`quizGameVfour`'s database location** — the original audit stated "DB dir not found on disk
  at this path (app-only stack)." This was wrong: there is a real bind-mounted MySQL datadir with
  live data, containing two schemas (`quiz` and `quiz_testing`, the latter a real
  intentionally-used test database, not a stray leftover). Discovered during the `quizGameVfour`
  migration (2026-07-16/17).
- **`login` family's "running container" framing** — the original audit worried that the running
  `mysql_db` container (bind-mounted to `E:\LocalDevelopments\React\login`) might be "serving
  stale pre-JWT code while newest work sits unmigrated," implying its data mattered and needed
  reconciling against the newer code. Direct inspection (read-only investigation, 2026-07-17/18)
  showed this database is actually **empty of application data** (only system schemas — confirmed
  via `SHOW DATABASES` and a direct datadir listing) and its `backend`/`frontend` source folders no
  longer exist on disk at all. The real, non-empty application data (`mydatabase.users`, 25 rows)
  and the only git history in the whole family live in the separate `/mnt/e/LocalDev/React/login`
  copy, which was not the copy the audit's "running now" framing had pointed at as the risk.

## Framework invariants (binding on every future migration)

Unlike the per-project "Lessons learned" notes below, these are permanent rules, not project
color. The framework otherwise remains frozen — this is the one exception explicitly carved out:
record binding invariants when a real migration exposes a genuine gap, without reopening the rest
of the workflow.

- **The evidence backup is immutable from the moment it is created until the migration is fully
  complete.** It must never be mounted writable, not even briefly, not even by accident. The
  `lower_case_table_names` compatibility probe and the isolated recovery container must always run
  against a separate disposable working copy — never the evidence-backup path itself. Discovered
  during the `login` migration (2026-07-17/18): the compatibility probe was mounted directly
  against the evidence backup with a writable mount, and mysqld's failed startup wrote to
  `ibdata1` before aborting. The original Windows source was unaffected and the mistake was
  caught immediately via the standard mtime-verification step, but it should never have been
  possible in the first place — the evidence backup existing at all is the safety net for
  "database integrity cannot be proven," and a workflow that can accidentally write to it defeats
  that purpose. Going forward: evidence backup → mount `:ro` for all verification and probing →
  disposable copy (NTFS recovery copy or equivalent) is the only thing ever mounted read-write.

### `login` — complete, cleanup pending

First non-Laravel/non-quizGame project this cycle, and the first migration in the family the
original audit ranked #1 ("Critical," needs a decision, not just a copy). A dedicated read-only
investigation (no changes made) preceded this migration to resolve which of three copies was
authoritative; see the investigation summary earlier in this session and the audit-correction
entry above. Authoritative source: `/mnt/e/LocalDev/React/login` — git-tracked, GitHub remote
(`react-auth`), real non-empty application data, and the most recent verified development activity
in the whole family. The other two copies (`E:\LocalDevelopments\React\login`, DB empty/source
gone; `E:\LocalDev\React\react-login`, no git, pre-JWT, no recoverable DB) were **not** touched.

**Working-tree preservation (highest priority per this migration's instructions):**
- [x] Full pre-migration git state recorded before copying: branch `feature/backend-tests`, HEAD
      `e1110a9` (2025-03-31, JWT auth + centralized route guards), remote `origin` →
      `github.com/masoodbarzegar/react-auth.git`, one stash entry, 46 modified tracked files
      (+19,288/-17,558 lines — a substantial uncommitted rewrite never pushed), 45 untracked files
      including a nascent PHPUnit test suite (`backend/tests/`, `phpunit.xml`,
      `database.test.php`) dated 2025-05-02 — i.e. real work done *after* the last commit.
- [x] Post-copy git state verified against this record: branch, HEAD, remote, stash list, and
      untracked-file count all identical. Tracked-diff stat showed one apparent discrepancy
      (19,262/-17,559 vs. source's 19,288/-17,558) — root-caused, not a copy defect: a
      pre-existing case mismatch between the git index (`backend/src/config.php`, lowercase) and
      the actual on-disk filename (`Config.php`), invisible on the source's case-insensitive
      NTFS/9P filesystem, surfaced only because WSL-native ext4 is case-sensitive. Confirmed via
      direct SHA-256 hashing that `Config.php`'s content is byte-identical between source and
      copy, and confirmed (via `git ls-files -s`) this exact mismatch already exists in the
      source's own git index — not introduced by the migration. Whole-tree checksum comparison
      (`rsync -avhcn`) additionally confirmed every tracked and untracked file matches source
      byte-for-byte (only the `.git/` directory *entry* itself, not its contents, showed as
      changed — ordinary metadata noise).

**Database:**
- [x] Physical (evidence) backup of the real datadir, read-only mount, verified 198/198 files
      identical to source by name+size; source mtimes confirmed unchanged before and after.
- [x] **Self-caught and corrected error**: the first `lower_case_table_names` compatibility probe
      was accidentally mounted directly against the WSL evidence-backup copy (not a disposable
      copy), and since the mount wasn't read-only, mysqld's failed startup wrote to `ibdata1`
      before aborting. Caught immediately via the mtime-verification step. Original Windows source
      confirmed untouched throughout; the mutated evidence backup and downstream recovery copy
      were discarded and both fully redone from a fresh read-only backup before proceeding.
      Recorded here as a lesson, not swept under the rug: the compatibility probe must mount a
      disposable copy, never the evidence-backup path itself, even read-write by accident.
- [x] Compatibility probe confirmed the same `lower_case_table_names` mismatch seen in every
      MySQL project so far (server `0` vs. data dictionary `2`).
- [x] NTFS-hosted sparse-preserving recovery copy, isolated recovery container
      (`--lower-case-table-names=2`), real data confirmed: one application schema (`mydatabase`),
      one table (`users`), 25 rows.
- [x] Logical dump created and verified: table/row count matched (25), checksum recorded, **and**
      test-restored into a separate fresh throwaway container to confirm the dump actually
      restores cleanly (not just that it was produced without error) before relying on it.

**Copy, compose, restore:**
- [x] Source copied to `/home/masoud/personal/react/login`, excluding only `backend/vendor/`,
      `frontend/node_modules/`, and the old `db_data/` (superseded by a fresh named volume, same
      convention as every prior MySQL migration).
- [x] `compose.yaml` standardized: `name: login_wsl`, no `container_name` (the source hard-coded
      `php_backend`/`react_frontend`/`mysql_db`/`phpmyadmin`, which is exactly the structural
      collision the original audit flagged across all three family copies), no auto-restart,
      `db` healthcheck with `condition: service_healthy`, `phpmyadmin` under `profiles: [tools]`.
      **One project-specific addition**: the db service now sets `MYSQL_DATABASE`/`MYSQL_USER`/
      `MYSQL_PASSWORD` (official-image-recognized vars) matching the app's own long-standing
      `mydatabase` database, with username/password `[redacted]`/`[redacted]` — the original
      compose only ever fed `MYSQL_ROOT_PASSWORD` via `env_file`, relying on the schema/user
      having been created once, long ago, by some undocumented manual step that Windows'
      persistent datadir then carried forward silently. A fresh volume needed this made explicit;
      verified the auto-created account can query the restored data with correct scope.
- [x] Dump restored into a fresh named volume (`login_wsl_dbdata`); count re-verified (25) both as
      `root` and as the app's own `user` account.

**Validation:**
- [x] **Genuine deviation found and fixed (bind-mount shadowing, not a new issue)**: the backend
      container's Dockerfile runs `composer install` at build time, but the compose file bind-
      mounts `./backend` over `/var/www/html`, shadowing the image's baked-in `vendor/` with the
      host copy (which correctly excludes `vendor/` per the copy step above) — identical in kind
      to the storage/bootstrap-cache pattern from every prior Laravel migration, just manifesting
      as a missing `vendor/autoload.php` instead. Fixed by running `composer install` inside the
      running container once (persists via the bind mount, confirmed to survive a restart).
- [x] Auth flow validated end-to-end against the **real restored data**: unauthenticated
      `/dashboard` and `/verify-auth` correctly 401 (JWT middleware). A fresh test account
      (`migration-test@example.com`) was registered and logged in — deliberately not attempting
      any of the 25 real users' actual passwords — confirming `/register`, `/login` (JWT cookie
      issued), `/verify-auth` (200, correct decoded identity), and `/logout` all function
      correctly against the restored `users` table.
- [x] **Genuine pre-existing application bug found, left unfixed and documented** (same policy as
      `quizGameVtwo`'s `/login` 500): `GET /dashboard` returns 500 for an authenticated user — the
      router wires it to `DashboardController::index`, but the controller only defines
      `getDashboardData($decoded)`. Confirmed pre-existing in source (unmodified since copy); git
      log for the relevant commit itself calls this method "temporary… for demonstration purposes"
      — an intentionally incomplete feature, not a migration defect.
- [x] Frontend (`create-react-app` dev server) confirmed serving (200, correct HTML shell).
- [x] Restart validated (`docker compose restart`): `db` returns healthy, `vendor/` persists
      (bind mount, no reinstall needed), data count correct (26 = 25 restored + 1 test-registered),
      full auth flow re-verified, frontend still serves.

**Not migrated, left untouched:** `E:\LocalDevelopments\React\login` (empty DB, source already
gone), `E:\LocalDev\React\react-login` (no git, pre-JWT, no recoverable DB), and all 29 `.rar`
archives in `E:\LocalDev\React\backups\` — not opened, since the authoritative copy's own working
tree and database fully answered every preservation question without needing them.

Full detail: `~/docker-audit/project-checklists/login.md`.

### `quizGame` — complete, cleanup pending

Same "successor of a lost project" pattern as `myLaravel`/`myLaravelReact`/`myLaravelReactNew`: no
git repository, single copy (confirmed via filesystem search — no duplicates, unlike the
`quizGameV*` family), standard Laravel 12 + Vite + MySQL 8 layout. `DB_HOST=db` in the app's own
`.env` matches the standard service name directly — no network alias needed. First migration to
apply the new evidence-backup-immutability invariant end-to-end; both the compatibility probe and
recovery step used a disposable copy throughout, evidence backup mounted `:ro` only.

- [x] Physical evidence backup (`~/docker-audit/project-checklists/quizGame-backups/dbdata-copy`),
      read-only mount, verified 191/191 files identical to source by name+size (and 28/28 at the
      top level); source mtimes confirmed unchanged before and after.
- [x] Compatibility probe run against a disposable throwaway copy (never the evidence backup),
      confirmed the same `lower_case_table_names` mismatch as every prior MySQL project; evidence
      backup independently reconfirmed byte-identical (checksum) after the probe.
- [x] NTFS-hosted sparse-preserving recovery copy, isolated recovery container. Real data
      confirmed minimal but genuine: one schema (`laravel`), 9 tables (stock Laravel scaffold —
      `cache`/`jobs`/`sessions`/`users`/etc.), only `migrations` (3 rows) and `sessions` (1 row)
      non-empty — this project never progressed past its initial `laravel new` + `migrate`.
- [x] Logical dump created and verified: table count (9), row counts matched pre-dump values,
      checksum recorded, and test-restored into a separate fresh throwaway container before
      relying on it.
- [x] Source copied to `/home/masoud/personal/laravel/quizGame`, excluding only `src/vendor/`,
      `src/node_modules/`, and the old `dbdata/` (superseded by a fresh named volume). Exit 0.
- [x] `compose.yaml` standardized (`name: quizgame_wsl`, no `container_name`, no auto-restart,
      `db` healthcheck with `condition: service_healthy`, `phpmyadmin` under `profiles: [tools]`,
      ports `WEB_HTTP_PORT=8095`/`APP_FPM_PORT=9006`/`VITE_DEV_PORT=5180`/`PHPMYADMIN_PORT=8085`).
- [x] Dump restored into a fresh named volume (`quizgame_wsl_dbdata`); counts re-verified as both
      `root` and the app's own `laravel` user.
- [x] **Known bind-mount-shadowing pattern, now confirmed for both PHP and Node in one project**:
      neither Dockerfile installs dependencies at build time in a way that survives the bind mount
      (`docker/php/Dockerfile` never runs `composer install`; `docker/node/Dockerfile` has `npm
      install` commented out). Fixed the same way as every prior project: `composer install`
      inside the running `app` container, `docker compose run --rm node npm install` for the
      `node` service (its default `command: npm run dev` would otherwise crash-loop before
      dependencies exist). Storage/bootstrap-cache permissions fixed per the standard pattern.
- [x] Application validated: homepage (`GET /`) and Laravel's built-in health route (`GET /up`)
      both 200 via nginx; `php artisan migrate:status` inside the container confirms the real
      restored migration history (3 `Ran` rows) — DB connectivity validated through the
      application layer, not just direct SQL.
- [x] **Pre-existing gap found, left unfixed and documented** (same policy as `quizGameVtwo`'s
      `/login` 500 and `login`'s `DashboardController::index`): the Vite dev server starts
      cleanly but isn't reachable on its published host port, because the project's own
      `vite.config.js` (copied verbatim, unmodified) never sets `server.host` — unlike
      `quizGameVtwo`/`Vthree`/`Vfour`, whose own developers had already added `host: true` for
      Docker use. Confirmed via the Vite startup banner itself ("Network: use --host to expose").
      Since the app's actual HTTP layer (homepage, `/up`) is served correctly through nginx/PHP-FPM
      regardless, and this project's routing is just the untouched default scaffold, this was left
      as a documented pre-existing limitation rather than a speculative config change.
- [x] Restart validated (`docker compose restart`): `db` returns healthy, homepage and `/up` both
      re-confirmed 200, `migrate:status` re-confirmed identical, all four containers `Up`.

**Not migrated, left untouched:** `E:\LocalDev\quizGame.rar` — not opened, since the live source
and its database fully answered every preservation question without needing it.

Full detail: `~/docker-audit/project-checklists/quizGame.md`.

### `multi-container-app` — complete, cleanup pending

First migration with **no database recovery phase at all** — a small Docker sample/tutorial repo
(`github.com/docker/multi-container-app`) with an intentionally ephemeral MongoDB service (no
volume, by the original author's own design, not a migration gap). Read-only preflight confirmed:
genuinely the Docker tutorial project, no persistent data anywhere, no hidden bind mounts or
external dependencies, no duplicate copies, and a fully clean git state (working-tree "diff" was
100% CRLF/LF line-ending noise, confirmed via `git diff -w` showing zero real content difference).

- [x] Pre-copy git state recorded: branch `main`, HEAD `244c402`, remote `origin` →
      `github.com/docker/multi-container-app`, no stash, no untracked files, 12 files showing as
      "modified" purely from line endings (+1839/-1839, exactly equal).
- [x] Source copied to `/home/masoud/personal/react/multi-container-app`, excluding only
      `app/node_modules/`. Post-copy git state verified identical on every dimension (branch, HEAD,
      remote, stash, diff stat down to the exact same +1839/-1839). Whole-tree checksum comparison
      (`rsync -avhcn`) confirmed no real content difference was introduced — only `.git/index`
      itself (not tracked file content) showed as touched, ordinary per-checkout bookkeeping noise.
- [x] `compose.yaml` standardized (`name: multi-container-app_wsl`, ports parameterized via
      `.env.docker` — `APP_PORT=3001` since `3000` was already held by the running `login_wsl`
      stack). **Deliberately did not add a MongoDB volume** — the original's own `#volumes:` block
      was already commented out, so a fresh volume would have been a real design change, not a
      standardization. The commented-out block was left in place, matching the original author's
      own hint, and the `todo-database` port was not published to the host (internal-network-only),
      matching this migration's convention for every other project's database service.
- [x] Stack built and started; app logs confirm `Mongodb Connected` — container-to-container
      connectivity validated via the internal service DNS name (`todo-database`), exactly as the
      app's own hardcoded connection string expects.
- [x] Application flow validated end-to-end: homepage 200 (real Todo App UI, not a stub), a test
      record was created via the app's own POST route, confirmed both in the re-rendered page and
      via a direct MongoDB query, then removed via the app's own delete route — no expectation of
      persistence, and none needed.
- [x] Restart validated (`docker compose restart`): a second test record was created beforehand
      and confirmed to survive the restart (same container, same writable layer — restart is not
      recreation), app reconnected cleanly afterward, homepage still 200. Then removed the same way.
- [x] Ephemeral-data behavior confirmed structurally consistent with the original design:
      `docker compose config` shows no volume declared for `todo-database`, matching the source's
      own commented-out volume — data survives a restart (same container) but would not survive a
      `down`/recreate, exactly as the original tutorial was built.

**Not migrated, N/A:** no archive or duplicate existed for this project — single source, single
copy, nothing else to leave untouched.

Full detail: `~/docker-audit/project-checklists/multi-container-app.md`.

### `ozoffroad` — complete, cleanup pending

CakePHP 4.x sibling of `ozCarLab` (same private git server, same PHP/Postgres era). Read-only
investigation beforehand found two byte-for-byte identical copies (`LocalDev` vs. an explicitly
named backup folder) — resolved trivially since there was no divergence at all, unlike `login`.

**Database — evidence-based exclusion, not an error:**
- No local PostgreSQL installation found anywhere on the source machine (checked every standard
  Windows install path).
- No local PostgreSQL data directory found (searched both C: and E: for `PG_VERSION`, the
  canonical datadir marker — zero matches).
- No dump or backup found anywhere near either copy.
- Therefore no database migration was possible. Recorded as evidence, not attempted, not invented.
  A fresh, deliberately empty `db` (`postgres:12.17`) service was still stood up as infrastructure
  only, using this app's own already-known `config/app.php` credentials — holding no schema and
  no data.

**Git preservation**: pre/post-copy state verified identical on every dimension (branch, HEAD,
remote, stash, diff stat, whole-tree checksum). Source excluded only `vendor/`.

**Dockerization**: no Docker artifacts existed in the source at all — built from scratch, modeled
on `ozCarLab`'s proven Dockerfile/compose shape (same PHP 7.3 + Apache + `pdo_pgsql`). One
environment-file adjustment (not application source — `config/app.php` is gitignored): changed
the `default` datasource's host from `127.0.0.1` to `db`, matching the Compose service name.
Verified via `PDO pgsql:host=db;...` connecting successfully from the `web` container — confirms
networking and config are correct.

**Genuine pre-existing gap found, left undisturbed** (broadest-impact instance of this migration's
document-don't-fix policy so far): `src/Application.php:48` unconditionally loads a
`MobileValidator` plugin that was **never committed to git** — `plugins/` contains only a
`.gitkeep`, identical on both source copies. Every route 500s, deterministically, before and after
a full restart. Not fixed — writing a stub plugin would mean inventing application code. Also
found (and left untouched, confirmed unused via `grep`): two extra `Datasources` blocks
(`withoutQuote` → `ozcar-live`, `phpLive` → MySQL) referenced nowhere in the app's actual code —
inert leftover config, not an active external dependency.

Full detail: `~/docker-audit/project-checklists/ozoffroad.md`.

### `React/react-app` — complete, cleanup pending

Plain `create-react-app` "Todo App" — client-side only, `localStorage` for state, no backend, no
API, no database by design. No git repository, single copy confirmed, zero Docker footprint
before migration. No genuine blocker found at preflight; proceeded directly with migration.

- [x] Source copied to `/home/masoud/personal/react/react-app`, excluding only `node_modules/`.
      Whole-tree checksum comparison (`rsync -avhcn`) confirmed byte-for-byte identical to source,
      both immediately after the copy and again at the end of the migration.
- [x] Original `docker-compose.yml`/`Dockerfile` left completely untouched (preserved source); a
      new `compose.yaml` was added alongside it with the minimum changes needed to run under this
      migration's conventions — dropped the deprecated `version:` key, parameterized the host port
      (`APP_PORT=3002`, since `3000`/`3001` were already held by other running stacks). Everything
      else, including a redundant duplicate bind-mount the original developer wrote, was kept
      verbatim — no modernization, no redesign.
- [x] Validated: homepage 200 (correct CRA shell) and `/static/js/bundle.js` 200 (confirms the
      actual React bundle serves correctly, since the app's real content only renders client-side
      and can't be observed via a plain `curl` of `/`).
- [x] Restart validated (`docker compose restart`): clean restart, both checks re-confirmed 200.

Full detail: `~/docker-audit/project-checklists/react-app.md`.

### `myLaravel` — complete, cleanup pending

- [x] Source copied to WSL (`/home/masoud/personal/laravel/myLaravel`)
- [x] Compose standardized (`compose.yaml`: no `version:`, no `container_name`, no auto-restart, explicit unique project name `mylaravel_wsl`, MySQL pinned to `mysql:8.4.5`, `tools` profile for phpMyAdmin, healthcheck + `condition: service_healthy`, ports configurable via `.env.docker`)
- [x] Database restored into a fresh WSL-native named volume (`mylaravel_wsl_dbdata`, `lower_case_table_names=0`, normal Linux default) — not a reused/adopted volume, not a raw copy of the Windows datadir
- [x] Application validated (homepage, post detail page, category filter all return correct, database-backed content; logs clean across all services)
- [x] Restart validated (`docker compose restart`, not `-v` — db returns healthy, app responds, data persists)
- [x] Post-migration logical dump created (`myLaravel-post-migration-20260712-131056.sql`, in `~/docker-audit/project-checklists/myLaravel-backups/`)
- [ ] **Cleanup pending** — old Windows source, both pre-migration backup copies, the NTFS recovery copy, and the pre-migration dump are all still in place, deliberately, awaiting a separate approval before anything is removed. The new WSL stack is running and has not been stopped.

Full detail: `~/docker-audit/project-checklists/myLaravel.md`.

### `myLaravelReact` — complete, cleanup pending

Materially identical migration to `myLaravel` — same framework, same recovery sequence, no
modification required. Differences: `VITE_DEV_PORT` originally 5173 (not 5174); node service's
dev-server `command` was already commented out in the original (`tty: true` instead) and was
preserved as-is; this project's schema has no custom application tables (just the 9 standard
Laravel scaffolding tables) — the app itself is a Laravel + Inertia.js + React starter
(Breeze-style), not a server-rendered Blade app like `myLaravel`, so functional validation used
`/login`, `/register`, and a `/dashboard` auth-redirect check instead of content-page checks.
Three host ports (`5173`, `9000`, `80`) collided with the already-running `laravelLivewireAdmin_wsl`
and `myLaravel_wsl` stacks — resolved via `.env.docker` (`VITE_DEV_PORT=5175`, `APP_FPM_PORT=9001`,
`WEB_HTTP_PORT=8092`), exactly the mechanism the standard already provides for this.

- [x] Source copied to WSL (`/home/masoud/personal/laravel/myLaravelReact`)
- [x] Compose standardized (`mylaravelreact_wsl`, `mysql:8.4.5`, same standard as `myLaravel`)
- [x] Database recovered through the validated `lower_case_table_names=2` path — NTFS-hosted
      recovery copy, temporary disconnected container at the exact original image digest,
      confirmed clean startup
- [x] Logical dump verified (`myLaravelReact-logical-20260712-133812.sql`, 9/9 tables, no
      uppercase/mixed-case identifiers)
- [x] Fresh WSL-native named volume created (`mylaravelreact_wsl_dbdata`,
      `lower_case_table_names=0`, normal Linux default)
- [x] Restore validated — 9/9 tables and all row counts independently verified matching the dump
- [x] Application validated (homepage 200 with correct Inertia props, `/login`/`/register` 200,
      `/dashboard` correctly 302-redirects unauthenticated — proves session/auth reads the
      restored `users`/`sessions` tables correctly; logs clean across all services)
- [x] Restart validated — db healthy, homepage 200, `/dashboard` still 302 after restart
- [x] Post-migration logical dump created (`myLaravelReact-post-migration-20260712-135811.sql`,
      in `~/docker-audit/project-checklists/myLaravelReact-backups/`)
- [ ] **Cleanup pending** — same as `myLaravel`: nothing removed yet, awaiting separate approval.

Full detail: `~/docker-audit/project-checklists/myLaravelReact.md`.

### New operational lesson from the `myLaravelReact` migration

- **Before the first `docker compose up` for any remaining project, proactively inspect
  currently occupied host ports and assign project-specific values in `.env.docker` before
  startup — don't discover conflicts reactively.** This migration hit three separate port
  collisions (`5173`, `9000`, `80`) one at a time against the already-running
  `laravelLivewireAdmin_wsl` and `myLaravel_wsl` stacks, each requiring a stop-fix-retry cycle.
  `docker ps --format '{{.Ports}}'` against all currently running stacks, checked once before the
  first `up`, would have caught all three in one pass instead of three.

### `myLaravelReactNew` — complete, cleanup pending

Third consecutive application of the same validated recovery/restore sequence — no new
divergence in the workflow itself. Confirmed the proactive port-assignment lesson above: ports
were checked and assigned before the first `up` this time, and the stack started with zero
conflicts on the first attempt. Differences from the prior two: this is the official
`laravel/react-starter-kit` (TypeScript, git-tracked at `src/.git` with 5 uncommitted local
changes at time of migration — preserved as-is by the copy step); PHP Dockerfile adds the `exif`
extension; node Dockerfile has no `CMD` at all (falls through to the base image default, same net
"no auto-start" behavior as the other two, just reached differently); and — most notably — this
project has real custom application tables (`tasks`, `media`), the first of the three successor
copies to have actual business data beyond Laravel's own scaffolding.

- [x] Source copied to WSL (`/home/masoud/personal/laravel/myLaravelReactNew`)
- [x] Compose standardized (`mylaravelreactnew_wsl`, `mysql:8.4.5`)
- [x] Database recovered through the validated `lower_case_table_names=2` path (NTFS recovery
      copy, temporary disconnected container, exact original image digest — identical across all
      three migrations, confirming the same batch/lineage)
- [x] Logical dump verified (11/11 tables, no uppercase/mixed-case identifiers)
- [x] Fresh WSL-native named volume created (`mylaravelreactnew_wsl_dbdata`,
      `lower_case_table_names=0`)
- [x] Restore validated — 11/11 tables and all row counts independently verified matching
      (`media`: 1, `migrations`: 6, `sessions`: 1, `tasks`: 11, `users`: 1)
- [x] Application validated — homepage 200 with correct Inertia payload; `/login`/`/register`
      200; `/dashboard` and `/tasks` (a full CRUD resource — `TaskController`) both correctly
      302-redirect unauthenticated access, confirming the restored `users`/`sessions` data is
      read correctly by both the standard auth flow and the app's custom feature; logs clean
      across all services
- [x] Restart validated — db healthy, homepage 200, `/tasks` and `/dashboard` still 302 after
      restart
- [x] Post-migration logical dump created
      (`myLaravelReactNew-post-migration-20260712-221445.sql`, table set confirmed identical to
      the pre-migration dump)
- [ ] **Cleanup pending** — nothing removed yet, awaiting separate approval.

Full detail: `~/docker-audit/project-checklists/myLaravelReactNew.md`.

### `ozCarLab` — complete, cleanup pending

**Treated explicitly as a framework extension, not just another project migration** — the first
project outside the validated MySQL/Laravel envelope: PostgreSQL 12.17, two CakePHP
sub-applications (`ozcar`, `ozhub_repo`) served by one combined Apache+PHP container via
name-based virtual hosting, sharing a single `ozcar` database.

- [x] Physical evidence backup of `pg_data` preserved untouched throughout
      (`~/docker-audit/project-checklists/ozCarLab-backups/pg_data-copy`)
- [x] Disposable sparse-preserving recovery working copy (`cp -a --sparse=always`) used to run a
      temporary, digest-pinned, network-isolated PostgreSQL container purely to produce a logical
      export — never treated as the final database
- [x] Version/locale relationship confirmed by evidence before recovery: image, datadir, and
      backups all PostgreSQL 12.x; `lc_collate`/`lc_ctype` both `en_US.utf8`, no mismatch (unlike
      the MySQL migrations, Postgres had no case-insensitive-filesystem requirement to satisfy)
- [x] Fresh globals dump + custom-format database dump produced and verified (471 tables — see
      correction note below)
- [x] Source copied to WSL (`/home/masoud/personal/laravel/ozCarLab`), `--exclude-deps`
      (`vendor/`, `node_modules/`), both `.git` directories preserved
- [x] Compose standardized (`ozcarlab_wsl`, PostgreSQL pinned at `12.17` — matches source, no
      version upgrade — pgAdmin behind `tools` profile, ports via `.env.docker`, dead
      `pg_data:` volume declaration from the original file not carried forward)
- [x] Fresh WSL-native named volume (`ozcarlab_wsl_pgdata`) created; globals + database restored;
      content independently verified
- [x] Two pre-existing PHP extension gaps in the project's own Dockerfile surfaced only once
      `composer install` was run fresh (`ext-zip`, then `ext-gd`) — both diagnosed as pre-existing
      (not migration-caused), fixed one at a time with explicit approval before each Dockerfile
      change and rebuild
- [x] Both applications validated: `oz.local` homepage renders real DB-backed content;
      `ozhub.local` login page renders correctly; auth-gating behaves correctly on both; no
      PHP/Apache/PostgreSQL errors in logs from application traffic
- [x] Restart validated — both services healthy, both apps re-verified clean after
      `docker compose restart`
- [ ] **Cleanup pending** — same pattern as the other three: nothing removed, stack left running,
      awaiting separate approval. Additional ozCarLab-specific cleanup candidates: two large old
      backup files copied into `src/` during the source copy, and the Dockerfile's divergence from
      the original (documented, necessary, not yet reconciled).

Full detail: `~/docker-audit/project-checklists/ozCarLab.md`.

### Lessons learned from the `ozCarLab` migration (framework extension to PostgreSQL/non-Laravel)

- **A `pg_restore --list` table count is easy to double-count.** Matching `"; [0-9]+ [0-9]+ TABLE "` catches
  both the `TABLE` (schema) and `TABLE DATA` entries per table, since `"TABLE DATA"` also starts
  with `"TABLE "`. An initial count of "942 tables" was exactly double the true count of 471 —
  caught and corrected before it propagated into a false claim of schema growth between backups.
  Always verify a TOC-derived count against an independent method (e.g. `grep -c "^[0-9]\+; [0-9]\+ [0-9]\+ TABLE "`
  with a trailing space to exclude `TABLE DATA`, or just filter out lines containing `"DATA"`).
- **PostgreSQL doesn't share MySQL's `lower_case_table_names` filesystem constraint** — the
  NTFS-recovery-copy requirement from the MySQL migrations doesn't generalize; a WSL-native sparse
  copy was sufficient here since Postgres locale/collation is independent of filesystem
  case-sensitivity. Don't assume a technique proven for one database engine transfers to another
  without re-checking the actual constraint it was solving.
- **Misleading HTTP 200s**: both vhosts returned 200 even when completely broken (missing
  `vendor/autoload.php`, PHP fatal errors) before `composer install` had been run. Status code
  alone is not sufficient validation for this stack — always check actual response body content.
- **PHP extension gaps can be masked by a stale `vendor/` and only surface on a fresh
  `composer install`.** Both `ext-zip` and `ext-gd` gaps were pre-existing in the Dockerfile (the
  app's own `composer.json` already required them) but were invisible until dependencies were
  installed fresh in the new environment — not something a pre-migration Dockerfile read alone
  would necessarily have caught; budget for this as a normal part of "first real `composer
  install`" validation on any PHP migration, not just this one.
- **`gd`'s `docker-php-ext-configure` flags are PHP-version-specific**: PHP 7.3 requires the older
  `--with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/` syntax; PHP 7.4+ uses the
  simplified `--with-freetype --with-jpeg` (no paths). Verify in an isolated throwaway container
  against the exact base image before editing the real Dockerfile — this caught the wrong syntax
  before it cost a real rebuild cycle.
- **Two sibling apps sharing one database can still have independently-named routes** —
  `oz.local` uses `/users/login` (plural, AJAX-only, empty body by design), `ozhub.local` uses
  `/user/login` (singular, full page). Don't assume route-naming symmetry between apps just
  because they share a container and a database.

### `quizGameVtwo` — complete, cleanup pending

Fifth migration, back within the proven MySQL/Laravel envelope after `ozCarLab`'s extension into
PostgreSQL/CakePHP. Chosen over the `login` family (originally ranked #1) because `login`
requires resolving a three-way authoritative-copy decision before a migration is even
well-defined, which doesn't fit the simplified per-project completion bar now in effect
(source copied / compose standardized / database restored / app starts / key data visible / one
restart succeeds).

- [x] Physical backup + NTFS recovery copy + isolated recovery container (matching digest,
      `--lower-case-table-names=2` after an empirical test confirmed the mismatch) — fully
      consistent with the proven workflow, no material deviation
- [x] Logical dump verified (11/11 tables, real row counts)
- [x] Source copied preserving `.git`, branch, and all 13 pre-existing uncommitted changes
- [x] Compose standardized (`quizgamevtwo_wsl`, conflict-free ports chosen proactively against all
      other running stacks)
- [x] Fresh named volume, dump restored, verified
- [x] Application started; three pre-existing app-level bugs found during validation (missing
      `dropdown-menu.jsx` component, storage-permission bind-mount issue, missing
      `inertiajs/inertia-laravel` composer package) — two fixed (routed around the missing
      component by using the project's own already-intended `npm run dev` design instead of
      fabricating the component; added the missing composer package since the app already declared
      its need for it via `Inertia::render()` calls), one left deliberately unfixed and documented
      (`/login` 500 — a Laravel 11+ `$this->middleware()` incompatibility in the developer's own
      auth controllers, a code-design decision outside migration scope)
- [x] Homepage, `/games`, and the auth-gated `/dashboard` redirect all validated with real restored
      data; restart test succeeded, permissions and data both persisted
- [ ] **Cleanup pending** — nothing removed, stack left running, same as all prior migrations.

Full detail: `~/docker-audit/project-checklists/quizGameVtwo.md`.

### `quizGameVthree` — complete, cleanup pending

Sixth migration. Chosen as lowest-risk remaining candidate: zero running/stopped containers (no
collision risk), no duplicate-copy decision, no git state to preserve (no `.git` present), and a
Docker scaffold byte-identical to `quizGameVtwo`'s (confirmed — the build reused 100% cached
layers). Also corrected a factual error in the original audit (see "Audit corrections" above):
this project has real live MySQL data, not "None found" as originally recorded.

- [x] Physical backup, `lower_case_table_names` probe (identical mismatch to `quizGameVtwo`, no
      divergence), NTFS recovery copy, isolated recovery container, logical dump (9/9 tables) —
      all exactly the proven workflow, no deviation
- [x] Source copied (no git state to preserve; excluded only `vendor/`/`node_modules/`)
- [x] Compose standardized (`quizgamevthree_wsl`, conflict-free ports `8001`/`9004`/`5178`/`8082`)
- [x] Fresh named volume, dump restored, verified (9/9 tables, exact row-count match)
- [x] **Genuine gap found and fixed, smallest possible adjustment**: app's `.env` hardcodes
      `DB_HOST=mysql`, but the standard's compose service is named `db` — `mysql` didn't resolve.
      Fixed via a network alias on the `db` service (`aliases: [mysql]`), not by touching the
      app's `.env` or any application code. Root cause confirmed directly (`getent hosts`), not
      assumed. **Same latent mismatch likely exists silently in `quizGameVtwo`** (and possibly
      earlier migrations) — it just never surfaced there because that app's
      `SESSION_DRIVER=file` doesn't touch the DB on every request, while this app's
      `SESSION_DRIVER=database` does. Flagged as a follow-up check for after all migrations are
      complete, not acted on retroactively now (per current framework-freeze instruction).
- [x] Missing `@inertiajs/react` npm dependency found (confirmed via direct read of
      `package.json`) and added — additive-only, same class of gap as `quizGameVtwo`'s missing
      composer package
- [x] Homepage validated with real content; session read/write path specifically exercised
      (`sessions` row count increased 2→4 across two test requests, proving genuine DB
      connectivity, not a cached response) — this app's `SESSION_DRIVER=database` made it a
      stronger DB-connectivity test than `quizGameVtwo`'s was
- [x] Restart validated — `db` healthy, homepage still 200, data intact, `mysql` alias still
      resolving post-restart
- [ ] **Cleanup pending** — nothing removed, stack left running, same as all prior migrations.

Full detail: `~/docker-audit/project-checklists/quizGameVthree.md`.

### `quizGameVfour` — complete, cleanup pending

Seventh migration. Most-evolved of the three `quizGame*` projects (own GitHub remote, full
games/questions/game_sessions schema). Carried two duplicate-copy folders (`-1`, `-2`) that the
original audit flagged as needing resolution — resolved via git commit comparison (both
duplicates at the same commit, superseded by the main copy's later history), not file diffing,
avoiding the need for any destructive decision.

- [x] Physical backup, `lower_case_table_names` probe (identical mismatch, no divergence), NTFS
      recovery copy, isolated recovery container, logical dump covering **two** schemas
      (`quiz` + `quiz_testing`, both genuinely present and referenced by the app/test config) —
      all consistent with the proven workflow; the two-schema dump was a project-specific fact
      to accommodate, not a process change
- [x] Source copied (13 uncommitted changes preserved exactly); a new (non-DB) rsync exit-23
      case appeared — a Laravel test-fixture scaffold directory (`storage/framework/
      testing/disks`, empty, root-owned) — verified empty via root-mounted container read and
      treated as acceptable under the same reasoning as the established DB-permission pattern
- [x] Compose standardized (`quizgamevfour_wsl`, ports `8002`/`9005`/`5179`/`8083`); the
      `mysql`-hostname network alias fix (discovered reactively in `quizGameVthree`) was applied
      **proactively** here rather than rediscovered, since this project has the same
      `DB_HOST=mysql` + `SESSION_DRIVER=database` combination
- [x] Fresh named volume, both schemas restored, verified against pre-restore counts
- [x] **Genuine project-specific bug found and fixed**: a duplicated import statement in the
      developer's own `Contact.test.jsx` broke Vite's dependency scan for the whole app (Inertia's
      page-resolution glob crawls all `Pages/**/*.jsx`, including test files). Fixed by removing
      the one duplicate line — confirmed via direct file read, not assumed; not an
      application-logic change (vitest hoists `vi.mock()` regardless of import position)
- [x] Homepage, `/about`, `/contact`, `/login`, and `/games` (real DB-backed content, confirmed
      game name matches the restored row) all validated; auth-gated route correctly redirects
- [x] Restart validated — `db` healthy, all endpoints re-confirmed, restored data intact,
      `mysql` alias still resolving
- [ ] **Cleanup pending** — nothing removed, stack left running, same as all prior migrations.
      `quizGameVfour-1`, `quizGameVfour-2`, and both `.rar` archives were correctly left untouched
      (confirmed superseded, not migrated).

Full detail: `~/docker-audit/project-checklists/quizGameVfour.md`.

### Lessons learned from the `myLaravel` migration

- **Floating image tags are unsafe for database recovery.** Even though `mysql:8` turned out (after investigation) to have not actually drifted in this specific case, relying on a floating tag for anything touching an existing datadir is fragile by construction — pin an explicit version, or better, an exact digest, whenever you're opening data that already exists rather than initializing fresh.
- **`lower_case_table_names` compatibility depends on both datadir metadata *and* filesystem behavior — not just the server version.** The setting is baked into the data dictionary at initialization and can't be changed live; matching it at the server level (`--lower-case-table-names=2`) is necessary but not sufficient — MySQL also requires the underlying filesystem to actually be case-insensitive for that setting to be valid at all.
- **A Windows-created MySQL datadir may need to be recovered on a case-insensitive filesystem before a logical export is possible.** WSL-native storage (ext4) is case-sensitive; a datadir that was originally bind-mounted from NTFS may only open correctly on NTFS (or another case-insensitive filesystem) again, even temporarily, purely to extract a dump.
- **The proven sequence: physical backup first → logical dump from an isolated, filesystem-compatible recovery copy → restore into a fresh WSL-native volume.** Never dump from the original, never treat the raw Windows datadir (or a copy of it) as the final database — it's a transient source for one export, discarded afterward.
- **An `rsync` exit code 23 is acceptable only when the skipped data is privileged database data that's already backed up through another route and intentionally excluded from the final design.** In this migration, `migrate-project.sh`'s partial-transfer result (blocked by the same UID-999 permission wall as everything else in this data's history) was fine specifically because the final Compose design never intended to reuse that bind-mounted folder anyway — the database was always going to be restored via logical dump into a named volume, not carried over as raw files. A partial rsync result should not be waved through by default; it's acceptable here because the gap was already covered by design, not by accident.

## Cleanup log

### 2026-07-18 — limited Docker cleanup (approved scope only)

Pre-cleanup snapshot of every container/image/volume recorded at
`~/docker-audit/project-checklists/cleanup-2026-07-18-snapshot.json` (plus `.mounts.txt` for
per-container mount detail) before anything was touched.

**Removed** — 38 stopped, pre-migration containers and their 17 project-specific images, all
confirmed superseded by an already-validated `_wsl` stack, zero overlap with any active stack,
zero other container references on any target image:

| Old stack | Containers removed | Images removed | Superseded by |
|---|---|---|---|
| `myLaravel` | `mylaravel-app-1`, `-db-1`, `-node-1`, `-webserver-1`, `-phpmyadmin-1` | `mylaravel-app`, `mylaravel-node` | `mylaravel_wsl-*` |
| `myLaravelReact` | `mylaravelreact-*` (5) | `mylaravelreact-app`, `mylaravelreact-node` | `mylaravelreact_wsl-*` |
| `myLaravelReactNew` | `mylaravelreactnew-*` (5) | `mylaravelreactnew-app`, `mylaravelreactnew-node` | `mylaravelreactnew_wsl-*` |
| `quizGame` | `quizgame-app-1`, `-db-1`, `-node-1`, `-webserver-1`, `-phpmyadmin-1` | `quizgame-app`, `quizgame-node` | `quizgame_wsl-*` |
| `quizGameVtwo` | `quiz-mysql`, `quiz-phpmyadmin`, `quiz-laravel-app`, `quiz-nginx` | `quizgamevtwo-app` | `quizgamevtwo_wsl-*` |
| `quizGameVfour` | `quiz-mysql-4`, `quiz-phpmyadmin-4`, `quiz-laravel-app-4`, `quiz-nginx-4` | `quizgamevfour-app` | `quizgamevfour_wsl-*` |
| `quizGameVthree` | — (none existed) | `quizgamevthree-app` | `quizgamevthree_wsl-*` |
| `login` family | `mysql_db`, `php_backend`, `react_frontend`, `phpmyadmin` | `login-backend`, `login-frontend` | `login_wsl-*` |
| `ozCarLab` | `ozcarlab-web-1`, `ozcarlab-db-1`, `ozcarlab-pgadmin-1` | `ozcarlab-web`, `ozcar-web` | `ozcarlab_wsl-*` |
| `laravelLivewireAdmin` | `web`, `app`, `db`, `laravel_livewire_composer` | `laravel-livewire-app`, `laravellivewireadmin-app` | `laravellivewireadmin_wsl-*` |

Also removed: the two anonymous volumes attributable to now-removed containers above —
`0e1923c5...` (old `ozcarlab-pgadmin-1`'s volume; contents verified beforehand to be only
pgAdmin's own internal `pgadmin4.db`/sessions/UI state, not application data) and `216f58aa...`
(old `react_frontend`'s `/app/node_modules` volume; contents verified to be only reproducible npm
packages).

**Approximate disk space reclaimed**: ~35.5GB (summed from each removed image's own reported size
in the pre-cleanup snapshot; the largest single contributors were `ozcarlab-web` at 13.3GB and
`ozcar-web` at 10.1GB — actual host disk delta may differ slightly if any layers were shared with
retained images).

**Explicitly not touched**: any `_wsl` container/image/volume (all 12 active named database
volumes reconfirmed present after cleanup); the other 8 unattributed anonymous volumes;
`swf_uploader_apis`'s resources; Windows source, duplicate copies, or archives (`react-login`,
`E:\LocalDevelopments\React\login`, `E:\Ozcar newest backup\backup\ozoffroad`,
`quizGameVfour-1`/`-2`); any evidence backup, logical dump, or NTFS recovery copy under
`~/docker-audit/project-checklists/*-backups/` or `/mnt/e/Dev-Backups/`; any unrelated Docker
resource (`sales-api`, `helloapi`, python-learning containers, etc.).

**Post-cleanup verification**: the 5 stacks that were running before cleanup (`login`, `quizGame`,
`ozoffroad`, `multi-container-app`, `React/react-app`) were re-confirmed running and responding
correctly afterward (`ozoffroad`'s 500 is its pre-existing, already-documented `MobileValidator`
gap — unchanged, not a cleanup regression). The remaining `_wsl` stacks
(`quizGameVtwo`/`Vthree`/`Vfour`, `ozCarLab`, `myLaravel`/`React`/`ReactNew`,
`laravelLivewireAdmin`) were already stopped before this cleanup began (pre-existing state, unrelated
to today's work) — their images and named volumes are all confirmed intact and unaffected, so they
remain startable exactly as before.

Categories C (Windows-side duplicate copies) and D (backup/dump consolidation) from the proposed
cleanup plan were, per instruction, not acted on.
