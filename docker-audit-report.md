# Docker Audit Report

Generated: 2026-07-11 (updated same day with a second pass)
Scope: Docker Desktop (WSL2 backend) on this machine — all containers, images, volumes, networks, build cache, plus Docker-related project files under `/home/masoud` (§1-§7), and a follow-up pass (§8) scoped strictly to the Windows development folders `E:\LocalDev` and `E:\LocalDevelopments`.

**This audit is strictly read-only.** No Docker resource, and no file on Windows, WSL, or elsewhere, was created, deleted, started, stopped, moved, or modified. The only state-changing action taken across both passes was installing the `unrar` package (at your explicit request) so archive contents could be listed.

---

## 1. Executive summary

| Resource | Total | Active/Running | Size | Reclaimable |
|---|---|---|---|---|
| Images | 39 | 30 referenced by a container | 46.32GB | 21.49GB (46%) |
| Containers | 68 (66 visible to CLI + 2 Docker Desktop extension containers) | 3 running (CLI) + up to 2 extension containers | 1.45GB (writable layers) | 915.2MB (63%) |
| Local Volumes | 4 | 3 in use | 656.2MB | 167.9kB |
| Networks | 19 | — | — | — |
| Build cache | 241 entries | 0 active | 3.254GB | 3.254GB (100%) |

**The single most important finding:** almost every database container (MySQL/PostgreSQL) stores its data in a **bind mount to the host filesystem**, not a Docker-managed volume. Several of those bind-mount source paths are on Windows drives, and **10 containers (18 individual mounts) point to `E:\LocalDevelopments\...` paths that no longer exist on Windows** — the projects were apparently relocated to `E:\LocalDev\...` at some point, but the old containers were never recreated against the new path. Since bind-mount data lives on the host, not inside Docker, **that data is not something Docker cleanup can lose — it is already gone**. There is nothing to back up for those 10 containers.

Conversely, there are still-live bind-mounted databases whose host directories **do** exist and have **not** been backed up anywhere (`ozcarlab`, `quizgamevtwo`, `quizgamevfour`, `laravellivewireadmin`, the `login` project). Those need attention **before** any Windows/WSL cleanup.

---

## 2. Docker resource inventory

Full machine-readable detail is in `containers.tsv`, `images.tsv`, `volumes.tsv`, `networks.tsv`, `mounts.tsv`, `compose-projects.tsv`, `archive-matches.tsv` (all in this directory, tab-separated, one row per resource).

### 2.1 Containers (66 visible via `docker ps -a`, + 2 Docker Desktop extension containers not visible to the CLI)

- **Currently running (3):** `sadaqa_new_api_mysql` (mysql:8.0), `mysql_db` (mysql:8.0, project `login`), `quiz-phpmyadmin` (phpmyadmin).
- **Docker Desktop Extension containers (not in `docker ps -a` in this context):** `dixtdf_image-tools-desktop-extension-service` and `maltus_docker-logs-viewer-desktop-extension-service`. These run inside Docker Desktop's internal extensions VM and are visible only via `docker compose ls`. They are Docker Desktop infrastructure (an Image Tools extension and a Docker Logs Viewer extension), not your project data — classified **KEEP**, manage them from Docker Desktop's Extensions UI, not the CLI.
- **16 duplicate stopped containers** all named randomly (`amazing_shirley`, `flamboyant_yonath`, etc.) run from the same `sales-api` image with the same bind mount to `~/python-learning/sales-analytics-service` — clearly repeated `docker run` invocations without `--rm`. Classified **SAFE TO RECREATE** — these are pure clutter once you've confirmed you don't need their exited-state logs.
- Classification counts across all 66 containers:
  - PROBABLY UNUSED: 22 (source project data already gone from host)
  - SAFE TO RECREATE: 39 (19 duplicate `sales-api` runs, 11 with live E:\LocalDev source, 4 with live WSL source, 3 standalone `helloapi`, 1 named-volume-safe extra)
  - BACKUP FIRST: 6 (live DB data not yet archived anywhere)
  - UNKNOWN / INVESTIGATE: 0 remaining (resolved during investigation — see §4)

### 2.2 Images (39)

- Official/public base images (`mysql`, `postgres`, `nginx`, `phpmyadmin`, `dpage/pgadmin4`, `composer`) → **SAFE TO RECREATE**, trivially re-pulled.
- Project-built images with live source on disk → **SAFE TO RECREATE**.
- `swf_uploader_apis-app` (1.13GB, 8 months old, still referenced by 1 container) → **BACKUP FIRST**: no live project directory exists anywhere on disk; the *only* way to rebuild this image is from `~/Sadaqa-old-archive/swf_uploader_apis.rar` (see §4).
- 12 images from already-relocated/lost projects (`quizgame-app`, `quizgame-node`, `mylaravelreactnew-*`, `mylaravelreact-*`, `mylaravel-*`, `login-backend`, `login-frontend`, `quiz-game-laravel-app`) → **PROBABLY UNUSED**, source already gone, image is now the only remnant of some of these.
- `n-app` (876MB, 13 months old) → **UNKNOWN / INVESTIGATE**: no container references it, and no matching project directory was found anywhere under `~` or `E:\LocalDev`. Worth a manual look (`docker history n-app`) before deciding.

### 2.3 Volumes (4 total — deliberately small; almost everything uses bind mounts instead)

| Volume | Size | Used by | Classification |
|---|---|---|---|
| `laravellivewireadmin_dbdata` | 211.6MB | container `db` (mysql:8.0, project `laravellivewireadmin`) | **BACKUP FIRST** — the one genuine named-volume DB, no archive of it exists |
| `216f58aa8ab2...` (anonymous) | 444.2MB | `react_frontend` → `/app/node_modules` | SAFE TO RECREATE (reinstallable) |
| `0e1923c5a18f...` (anonymous) | 168.5kB | `ozcarlab-pgadmin-1` → `/var/lib/pgadmin` | SAFE TO RECREATE (UI settings only) |
| `a5fb9adc10c7...` (anonymous) | 167.9kB | **none** — no container references it | UNKNOWN / INVESTIGATE — truly orphaned, created 2025-05-02, origin unclear |

### 2.4 Networks (19)

3 Docker defaults (`bridge`/`host`/`none`) → KEEP. 14 compose-managed project networks → SAFE TO RECREATE (compose regenerates them automatically). 2 are orphaned with **zero containers and no matching live project**:
- `whisper-app_default` — explained in §4 (leftover from before the project was renamed to `faster-whisper-project`).
- `quiz-game-laravel_quiznet` — matches image `quiz-game-laravel-app` (0 containers), but no project directory of that exact name was found under `~` or `E:\LocalDev`. Likely an early naming iteration of one of the `quizGame*` projects. **UNKNOWN / INVESTIGATE.**

### 2.5 Build cache

3.254GB across 241 cache layers, 0 marked active/shared with a current build. All of it is reclaimable in principle — **no recommendation to prune yet**, per your instructions; flagged as SAFE TO RECREATE class (build cache is regenerated automatically on next build).

---

## 3. Compose projects (15 identified)

Full detail in `compose-projects.tsv`. Two live under your WSL home directory; the rest reference **Windows paths** that are out of the strict "home directory" scope you specified, but I cross-referenced them anyway since the containers themselves depend on them.

| Project | Config file location | Containers | Status |
|---|---|---|---|
| `sadaqa_new_api` | `/home/masoud/sadaqa_new_api/docker-compose.yml` (WSL) | 4 | 1 running, 3 exited |
| `helloapi` | `/home/masoud/dotnet-learning/HelloApi/docker-compose.yml` (WSL) | 1 | exited |
| `login` | `E:\LocalDevelopments\React\login\docker-compose.yml` (Windows) | 4 | 1 running, 3 exited |
| `laravellivewireadmin` | `E:\LocalDev\Laravel\laravelLivewireAdmin\docker-compose.yml` (Windows) | 4 | exited |
| `ozcarlab` | `E:\LocalDev\ozCarLab\docker-compose.yml` (Windows) | 3 | exited |
| `quizgamevtwo` | `E:\LocalDev\Laravel\quizGameVtwo\docker-compose.yml` (Windows) | 4 | 1 running, 3 exited |
| `quizgamevfour` | `E:\LocalDev\Laravel\quizGameVfour\docker-compose.yml` (Windows) | 4 | exited |
| `quizgame`, `mylaravel`, `mylaravelreact`, `mylaravelreactnew` | `E:\LocalDevelopments\...` (Windows, **path no longer exists**) | 5 each | exited — see §4 |
| `dixtdf_image-tools-desktop-extension` | Docker Desktop extension (`C:\Users\masoo\AppData\Roaming\Docker\extensions\...`) | extension-managed | running |
| `maltus_docker-logs-viewer-desktop-extension` | Docker Desktop extension | extension-managed | restarting |
| `quiz-game-laravel`, `whisper-app` | orphaned — no config file currently tracked | 0 | orphan |

**Note on scope:** most of these compose config files live on the Windows `E:\` drive, not under `/home/masoud`, so instruction §3 ("search under home directory") did not surface them directly — I found them via `docker compose ls` and cross-referenced against `/mnt/e` (WSL's view of the Windows drive) to verify bind-mount paths. If you want a proper file-level audit of the Windows-side project folders themselves (as opposed to just verifying paths Docker references), that would need a separate pass explicitly scoped to `E:\LocalDev` — let me know.

---

## 4. Key dependency findings (the important part)

### 4.1 Data that is already lost — nothing to back up

Containers for `quizgame`, `mylaravel`, `mylaravelreact`, `mylaravelreactnew`, and the `login` frontend/backend app containers, bind-mount to `E:\LocalDevelopments\...\dbdata` / `\src` paths that **do not exist on the Windows filesystem anymore** (verified via `/mnt/e`). Since bind mounts are just a window onto the host filesystem — Docker never copies or owns that data — its absence on disk means it's genuinely gone, not "at risk." These containers/images are classified **PROBABLY UNUSED**; recreating them from source is also not possible (the old source folders are gone too, though newer copies exist at `E:\LocalDev\...` under different container names — see below, don't confuse the two).

Exception: the `login` project's *database* (`mysql_db`, still running) bind-mounts to `E:\LocalDevelopments\React\login\db_data`, which **does still exist** — this one is live and needs attention (§4.3).

### 4.2 `swf_uploader_apis` — image survives, source doesn't, but the archive is a real backup

- Docker still has the built image `swf_uploader_apis-app` (1 container references it), but there is **no project source directory anywhere on disk** except an empty scaffold at `~/swf_uploader_apis/docker/mysql` (created *today*, no files inside — looks like an in-progress restore you may have already started).
- `~/Sadaqa-old-archive/swf_uploader_apis.rar` (460MB) **does contain a full backup**: source code, `.env`, and critically the **entire raw MySQL data directory** (`docker/mysql/data/mysql`, `/performance_schema`, InnoDB redo logs, etc.) — this is a genuine, complete database backup, not just source code.
- **Classification: BACKUP FIRST / KEEP.** Do not delete this `.rar` under any circumstances — it is currently the only copy of both the code and the database for this project.

### 4.3 Live data with no archive yet — back these up before any cleanup

| Project | Live data location | Backed up? |
|---|---|---|
| `login` (mysql_db, **running now**) | `E:\LocalDevelopments\React\login\db_data` (~9.2MB+, measured size likely undercounted — see §4.5) | **No archive found** |
| `ozcarlab` postgres | `E:\LocalDev\ozCarLab\pg_data` | **No** — and the one "backup" (`AustralianFleetSales200616.sql.tar.gz`) is only 112 bytes compressed, almost certainly empty/failed, **not usable** |
| `quizgamevtwo` mysql | `E:\LocalDev\Laravel\quizGameVtwo\docker\mysql\data` (~8.7MB+) | **No** |
| `quizgamevfour` mysql | `E:\LocalDev\Laravel\quizGameVfour\docker\mysql\data` (~9.2MB+) | **No** |
| `laravellivewireadmin` mysql | named volume `laravellivewireadmin_dbdata` (211.6MB) | **No** |

### 4.4 `sadaqa_new_api` and `sales-analytics-service` — already backed up, redundantly safe

`~/Sadaqa-old-archive/sadaqa_new_api.rar` and `~/python-learning/sales-analytics-service.rar` both contain full project backups (the sadaqa one includes the raw MySQL datadir too) **in addition to** the live project directories still on disk. These are in good shape — keep the archives as an extra safety net, no urgent action needed.

### 4.5 A filesystem measurement caveat

I ran read-only `du -sh` against the still-existing bind-mount paths to gauge real data size. Two important caveats:
- `E:\LocalDev\ozCarLab\pg_data` and several MySQL `data` subdirectories returned "Permission denied" for their internal subfolders (owned by the container's internal DB user, e.g. postgres UID 999) — the totals reported (e.g. "9.2MB") are **undercounts**; real size is likely larger. I could not get an accurate figure through this read-only WSL path.
- `du` on `E:\LocalDev\Laravel\laravelLivewireAdmin\src` and both `ozCarLab\src\ozcar` / `ozhub_repo` returned nonsensical values (644 petabytes / "Infinity") — this is a known WSL↔Windows 9P-filesystem artifact (almost certainly a symlink loop somewhere under `vendor/`), not a real size. Treat these as unmeasured; check actual folder size from Windows File Explorer if you need a real number.

### 4.6 Duplicate / stray project copies

- **ozCarLab exists in three places**: the Windows copy Docker actually uses (`E:\LocalDev\ozCarLab`), a 6.3GB WSL-native copy at `~/local_dev/ozCarLab/src` (its own `pg_data` folder is empty — not a live database, just a stray directory), and the containers themselves. The WSL copy appears to be a manual backup/staging copy, not something Docker depends on.
- `whisper-app` under `~/python-learning/` is an **empty leftover directory** — the real, current project is `~/python-learning/faster-whisper-project` (has a live Dockerfile). This explains the orphaned `whisper-app_default` network. No data risk.
- `~/dotnet-learning/ProjectManagement*.zip/.rar` archives (4 of them) are **not Docker-related at all** — no Dockerfile or compose file exists for that project anywhere.

---

## 5. Archive inventory (`archive-matches.tsv`)

28 archives found under `~` (zip/rar/tar.gz), 4 of them `.rar` (contents listed after installing `unrar` at your request; nothing was extracted). Highlights already covered above (§4.2, §4.4). The remainder are minor static-asset zips (fonts, JSON coordinate data, a small resources bundle, a composer vendor bundle) embedded inside the `~/local_dev/ozCarLab` source tree — not standalone project backups, low relevance to Docker cleanup decisions.

One non-archive file worth flagging: `~/Sadaqa-old-archive/sadaqat83_sadaqawelfare807_database.sql` — a 534MB **uncompressed** raw SQL dump sitting next to `sadaqa_new_api.rar`. It doesn't match any currently bind-mounted Docker volume path directly; looks like a manual export, possibly of `sadaqa_website` (a separate Laravel project at `~/sadaqa_website`, not currently Dockerized) rather than `sadaqa_new_api`. Worth a manual look if that data matters to you.

---

## 6. Full classification tables

See the TSV files for the complete, per-resource classification (`KEEP` / `BACKUP FIRST` / `SAFE TO RECREATE` / `PROBABLY UNUSED` / `UNKNOWN / INVESTIGATE`) with risk notes:

- `containers.tsv` — 66 rows
- `images.tsv` — 39 rows
- `volumes.tsv` — 4 rows
- `networks.tsv` — 19 rows
- `mounts.tsv` — 62 rows (every mount on every container, with bind-source-exists check)
- `compose-projects.tsv` — 15 rows
- `archive-matches.tsv` — 28 rows

---

## 7. Open items / suggested next steps (no action taken — your call)

1. **Before touching anything on `E:\LocalDev\`:** back up `quizGameVtwo\docker\mysql\data`, `quizGameVfour\docker\mysql\data`, and the `laravellivewireadmin_dbdata` named volume. None of these have an archive today. (Correction from the initial pass: `ozCarLab` *does* have backups — `ozcar.pg_dump` (9.38GB) and `ozcar_backup.sql` (4.25GB), both dated Feb 6, 2025 — but they are ~17 months old relative to the live `pg_data`; take a fresh one before migrating. See §8.)
2. **Back up the running `login` project's DB** (`E:\LocalDevelopments\React\login\db_data`) — it's live and unarchived. See §8 for a bigger complication: there are three copies of this project and the running container may not be using the newest code.
3. Investigate `n-app` image and `quiz-game-laravel_quiznet` network — unclear origin, not matched to any project found.
4. Decide what to do with the in-progress-looking `~/swf_uploader_apis/docker/mysql` empty scaffold — if you're mid-restore from the `.rar`, finish or clean it up deliberately.
5. Confirm whether `~/local_dev/ozCarLab` (6.3GB WSL copy) is still needed, or was already superseded by the Windows copy.
6. Once backups above are confirmed, the 22 "PROBABLY UNUSED" containers/images (already-lost `E:\LocalDevelopments` projects) and the 19 duplicate `sales-api` runs are your safest cleanup targets — but per your instructions, I have not run or recommended any deletion command, and won't until you say so.

No `docker` state was changed in the course of this audit.

---

## 8. Windows Project Inventory

*(Second-pass audit, scoped strictly to `E:\LocalDev` and `E:\LocalDevelopments` — no other part of the E: drive was scanned. Still fully read-only; nothing was created, moved, deleted, or modified. Full per-project detail is in `windows-projects.tsv`, 23 rows.)*

### 8.1 What's there

23 project directories were inventoried across the two roots (plus 2 tiny loose `.rar` archives at the `E:\LocalDev` root, and a 29-file `.rar` backup collection under `React/backups`). Indicators checked per project: git repo, Dockerfile, compose file, database-looking folder (`dbdata`/`db_data`/`pg_data`), `.env` files (names only — no values read), and package-manager markers.

| Project | Git | Docker files | DB folder | Package manager | Last activity |
|---|---|---|---|---|---|
| `herd/my-project` | no | no | no | composer, npm | 2025-05-05 |
| `Laravel/laravelLivewireAdmin` | **yes** | yes | no (named volume) | composer, npm | **2025-10-26** |
| `Laravel/myLaravel` | no | yes | yes (dbdata) | composer, npm | 2025-05-03 |
| `Laravel/myLaravelAPI` | no | no | no | — | empty (0 files) |
| `Laravel/myLaravelCRUD` | no | no | no | — | empty (0 files) |
| `Laravel/myLaravelProject` | no | no | no | — | empty (0 files) |
| `Laravel/myLaravelReact` | no | yes | yes (dbdata) | composer, npm | 2025-05-04 |
| `Laravel/myLaravelReactNew` | yes (in `src/`) | yes | yes (dbdata) | composer, npm | 2025-05-05 |
| `Laravel/quizGame` | no | yes | yes (dbdata) | composer, npm | 2025-05-16 |
| `Laravel/quizGameVfour` | yes | yes | no | composer, npm | 2025-06-13 |
| `Laravel/quizGameVfour-1/quizGameVfour` | yes | yes | no | composer, npm | 2025-06-02 |
| `Laravel/quizGameVfour-2/quizGameVfour` | yes | yes | no | composer, npm | 2025-06-02 |
| `Laravel/quizGameVthree` | no | yes | no | composer, npm | 2025-05-18 |
| `Laravel/quizGameVtwo` | yes | yes | no | composer, npm | 2025-05-18 |
| `multi-container-app` | yes | yes | no | npm | 2024-04-11 |
| `Oxin game` | no | no | no | — | 2025-05-02 |
| `ozCarLab` | yes (nested x2) | yes | yes (pg_data, protected) | composer, npm | 2025-02-13 |
| `ozoffroad` | yes | no | no | composer | 2023-09-27 |
| `React/backups` | no | no | no | — | 2025-05-03 |
| `React/login` | **yes** | yes | yes (db_data, protected) | composer, npm | **2025-03-31** |
| `React/react-app` | no | yes | no | npm | unclear |
| `React/react-login` | no | yes | yes (db_data, protected) | npm | 2025-01-14 |
| *(LocalDevelopments)* `React/login` | no | no (deleted) | yes (db_data) | — | source gone |

### 8.2 Docker-relationship matches against the first audit

Cross-referenced every project above against `containers.tsv`, `images.tsv`, `compose-projects.tsv`, and `mounts.tsv` from the first audit:

- **Currently used by Docker (path matches a live/stopped container exactly):** `laravelLivewireAdmin`, `quizGameVfour`, `quizGameVtwo` (has a container running right now), `ozCarLab`, and `LocalDevelopments\React\login` (its `mysql_db` container is running right now).
- **Previously used by Docker (image/data proves a prior run, but no current container references this exact path):** `quizGameVthree` (its image `quizgamevthree-app` still exists in Docker), `LocalDev\React\login` (has its own `db_data`, proving it was run via compose at some point).
- **No Docker relationship — successor copies of lost projects:** `myLaravel`, `myLaravelReact`, `myLaravelReactNew`, `quizGame`. Each has its own `dbdata` folder, but the *actual* stopped Docker containers for these project families bind-mount to the now-deleted `E:\LocalDevelopments\...` paths, not these `E:\LocalDev\...` copies. These copies were never wired up to Docker themselves.
- **No Docker relationship at all:** `herd/my-project`, `myLaravelAPI/CRUD/Project` (empty), `multi-container-app`, `Oxin game`, `ozoffroad`, `React/react-app`.

### 8.3 Duplicate detection

Four duplicate clusters found:

1. **`quizGameVfour` family** — `Laravel/quizGameVfour` (last commit 2025-06-13) vs. `Laravel/quizGameVfour-1/quizGameVfour` and `Laravel/quizGameVfour-2/quizGameVfour` (both last commit 2025-06-02, identical 449-file counts to each other). The `-1` and `-2` folders are snapshot duplicates of an older state of the same repo, nested one directory level deeper than expected (likely from an archive extraction). **Duplicate of `quizGameVfour`.**
2. **The `login` project family — the most significant finding of this pass.** There are (at least) **three physical copies plus a 29-file backup archive trail**:
   - `E:\LocalDevelopments\React\login` — the path the **currently-running** `mysql_db` container actually uses. Its `backend/` and `frontend/` source folders are already deleted; only `db_data`/`db_init` remain.
   - `E:\LocalDev\React\login` — a **separate, git-tracked, more recently developed** copy (remote `github.com/masoodbarzegar/react-auth`, latest commit **2025-03-31**, "Implement frontend JWT authentication"), with its own `db_data`. Not referenced by any current Docker resource.
   - `E:\LocalDev\React\react-login` — an un-versioned duplicate whose compose file uses the **exact same container names** (`php_backend`, `react_frontend`, `mysql_db`) as the original `LocalDevelopments` setup — a manual snapshot/backup, not independent work.
   - `E:\LocalDev\React\backups\*.rar` — 29 dated archives (`login-w1.rar` through `login-w17*.rar`, Feb–May 2025), the incremental backup trail that led to the `React/login` git history.

   **The practical risk:** the Docker container that's actually running right now may be serving older, pre-JWT-auth code, while the newest work sits untouched on disk. Before migrating anything, confirm which copy is authoritative.
3. **`ozCarLab`** exists in three places total across both audits: the Windows copy Docker uses (`E:\LocalDev\ozCarLab`), a 6.3GB WSL-native staging copy (`~/local_dev/ozCarLab`, first audit §4.6), and the containers themselves.
4. **`myLaravel` / `myLaravelReact` / `myLaravelReactNew` / `quizGame`** each exist as a "successor" copy at `E:\LocalDev\Laravel\...` alongside an older, now-mostly-deleted original at `E:\LocalDevelopments\Laravel\...` referenced by stopped Docker containers (first audit §4.1). Not exact duplicates (the old copies are largely gone), but the same project lineage.

### 8.4 Migration recommendations

Full per-project recommendation is in `windows-projects.tsv`. Summary:

| Recommendation | Projects |
|---|---|
| **Move to WSL** | `laravelLivewireAdmin` (most active, cleanest DB setup), `quizGameVfour`, `quizGameVtwo` (running now), `ozCarLab` (backup first — see below), and the `login` family (**after** resolving which copy is authoritative — see §8.3.2) |
| **Archive only** | `myLaravel`, `myLaravelReact`, `myLaravelReactNew`, `quizGame` (all: backup the real `dbdata` first), `quizGameVthree`, `herd/my-project`, `multi-container-app`, `ozoffroad`, `Oxin game`, `React/react-app`, `React/backups` (already an archive) |
| **Safe to delete after verification** | `myLaravelAPI`, `myLaravelCRUD`, `myLaravelProject` (empty, nothing to verify), `quizGameVfour-1`, `quizGameVfour-2` (verify no unique diff vs. `quizGameVfour` first), `React/react-login` (verify its `db_data` has nothing unique vs. the other login copies first) |
| **Keep on Windows** | none — nothing here depends on a Windows-only tool/service; every project is a standard web/PHP/Node stack that runs identically under WSL |

### 8.5 Caveats specific to this pass

- File-system access to Windows paths goes through WSL's 9P bridge, which is slow for large trees; the `ozCarLab` scan was capped at 20,001 files (still enough to confirm its shape) rather than run to completion.
- Every `dbdata`/`db_data`/`pg_data` folder found is permission-protected (owned by the database container's internal UID, e.g. 999) and could not be sized or read into — their presence and protection state confirm they hold real data, but exact size is unconfirmed for any of them.
- `.env` file *names* are reported per project (per your instructions); no `.env` contents were read.

No files were created, moved, deleted, or modified on the Windows drive during this pass.
