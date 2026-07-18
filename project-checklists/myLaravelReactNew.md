# Project Migration Checklist — myLaravelReactNew

Project name: myLaravelReactNew
Source (Windows): `E:\LocalDev\Laravel\myLaravelReactNew`
Destination (WSL): `/home/masoud/personal/laravel/myLaravelReactNew`
Status: **Migration complete, cleanup pending.**

**This checklist only records what differs from the validated `myLaravel`/`myLaravelReact`
migrations. Anything not mentioned here is materially identical.**

## 1. Discovery — differences only

- **This is the official `laravel/react-starter-kit`** (git remote confirms it), TypeScript
  (`tsconfig.json`, `vite.config.ts`, `components.json` — shadcn/ui), unlike `myLaravelReact`'s
  plain-JS setup. Same Inertia/React architecture family, more "stock."
- **Git-tracked, with 5 uncommitted local changes**: `bootstrap/cache/.gitignore`,
  `composer.json`, `database/seeders/DatabaseSeeder.php`, `package-lock.json`, `package.json`.
  Repo lives at `src/.git` (nested, same pattern as previously catalogued). `rsync` copies the
  working tree as-is, uncommitted changes included — no special handling needed, but worth
  knowing before assuming "what's in git" is "what's deployed."
- PHP Dockerfile adds `RUN docker-php-ext-install exif` (image extension, not present in the
  other two projects) — handled automatically since we build from this project's own Dockerfile.
- Node Dockerfile is more elaborate (bakes in `npm install` + `COPY . .` at build time) but has
  **no `CMD`/entrypoint line at all** — falls through to the base image's default (`node` REPL),
  which is why `tty: true` is set in the original compose file. Net runtime behavior is the same
  as `myLaravel`/`myLaravelReact`: the dev server does not auto-start. Preserved as-is.
- `.dockerignore` lives in `src/`, not the project root (the other two had it at root) — no
  functional effect: the PHP Dockerfile doesn't `COPY` app code at build time either way, so this
  only affects docker build context transfer size, not behavior.
- Old container's MySQL image digest identical to both prior migrations
  (`sha256:2764fe573c51062d1eadd39a78cc60aa85359bffec2451b7a9660f531bcfb53e`) — same
  `lower_case_table_names=2` recovery path expected, will still be verified.
- Old containers (`mylaravelreactnew-*`) bind-mounted to the already-deleted
  `E:\LocalDevelopments\Laravel\myLaravelReactNew` — same pattern, unrelated to this migration.
- `dbdata` has 7 binlogs (vs. 10 for `myLaravel`, 2 for `myLaravelReact`) — no procedural effect.
- One extra unused env key in `myLaravelReact`'s `.env` not present here (`VITE_DEV_SERVER_URL`)
  — trivial, app-level, not a Compose concern (mirrors the same kind of trivial diff already
  seen between `myLaravel` and `myLaravelReact`).

## 2. Ports — proactively assigned before first `up` (per the new operational lesson)

Currently occupied by already-running stacks at time of writing:
`80, 8080, 8092, 9000, 9001, 5173, 5174, 5175, 3306` (the last from an unrelated WSL-native
project, `sadaqa_new_api_mysql`).

| Variable | Original default | Assigned (conflict-free) |
|---|---|---|
| `WEB_HTTP_PORT` | 80 | **8093** |
| `APP_FPM_PORT` | 9000 | **9002** |
| `VITE_DEV_PORT` | 5173 | **5176** |
| `PHPMYADMIN_PORT` | 8081 | 8081 (still free) |

## 2a. Backup

- [x] Physical copy of `dbdata` (WSL-side, evidence/safety copy) —
      `~/docker-audit/project-checklists/myLaravelReactNew-backups/dbdata-copy`. All top-level
      entries match source exactly; original confirmed untouched afterward.
- [x] Recovery required and confirmed — same `lower_case_table_names=2` requirement as both
      prior migrations (exact same original image digest across all three). Fresh copy taken
      directly onto NTFS (`E:\Dev-Backups\myLaravelReactNew\dbdata-recovery-copy`). Temporary
      container (`--network none`, no ports, exact original image digest,
      `--lower-case-table-names=2`) started cleanly — one new benign log line not seen in the
      prior two ("Starting XA crash recovery... finished", standard InnoDB recovery, not an
      error), otherwise identical pattern. Confirmed via SQL: `version 8.4.5`,
      `lower_case_table_names=2`, `laravel` database present.
- [x] Logical dump taken and verified —
      `myLaravelReactNew-logical-20260712-141821.sql` (14,094 bytes, SHA-256
      `2fbd809a9e76988303cafe2a10c7597a8254d60fa2973afd541ca3c659c48e0e`). **11 tables** (9
      standard + `media` + `tasks` — the first of the three successor copies with real custom
      application data). No uppercase/mixed-case identifiers found. Temporary container removed
      afterward; original Windows source untouched throughout.

## 3. Copy

- [x] `rsync` source → `/home/masoud/personal/laravel/myLaravelReactNew` — real copy, exit code
      23 (same expected pattern, errors confined to `dbdata/`'s permission wall). 36,176 files,
      411M at the destination (larger than the other two — real git history + more dependencies).

## 4. Compose normalization

- [x] `compose.yaml` placed — project name `mylaravelreactnew_wsl`, `mysql:8.4.5` pinned, fresh
      non-external named volume, node `tty: true` preserved (no `CMD` in the Dockerfile to
      override anyway). `docker compose config` validated cleanly.
- [x] **Ports assigned proactively before the first `up`** (per the lesson from
      `myLaravelReact`) — `WEB_HTTP_PORT=8093`, `APP_FPM_PORT=9002`, `VITE_DEV_PORT=5176`,
      `PHPMYADMIN_PORT=8081`. **Zero conflicts on first attempt** — confirms the lesson held.

## 5. Validation

- [x] Fresh `db` healthy; `version 8.4.5`, `lower_case_table_names=0`, `laravel` database
      present, empty.
- [x] Dump imported, exit code 0. All 11 tables present, matching the dump exactly; row counts
      independently verified equal (`media`: 1, `migrations`: 6, `sessions`: 1, `tasks`: 11,
      `users`: 1; all others 0 in both dump and restore).
- [x] Application started (`app`, `node`, `webserver`) — all four services' logs clean.
- [x] Functional validation: homepage 200 with correct Inertia payload (`"auth":{"user":null}`,
      starter-kit welcome quote); `/login`/`/register` 200; `/dashboard` and **`/tasks`** (a real
      CRUD resource — `TaskController@{index,store,show,update,destroy}`, confirmed via
      `php artisan route:list`) both correctly 302-redirect unauthenticated access — proves the
      restored data is read correctly by both the standard auth flow and this project's actual
      custom feature.
- [x] Restart validated (`docker compose restart`, not `-v`) — db healthy, homepage 200,
      `/tasks` and `/dashboard` still correctly 302 afterward.

## 6. Cutover

- [x] New WSL stack running: `mylaravelreactnew_wsl-{app,db,node,webserver}-1`, `db` healthy.
- [ ] Old Windows-side stack — N/A, nothing runs against this source; unrelated old
      `mylaravelreactnew-*` containers remain stopped and untouched.
- [x] Zero Docker bind mounts reference a Windows path — confirmed via `docker compose config`.
- [ ] **Cleanup pending** — nothing removed yet, awaiting separate approval.

## Post-migration dump

`myLaravelReactNew-post-migration-20260712-221445.sql` (17,668 bytes, SHA-256
`600e600923a0438885bbcec0581622db01261d4382dd76f489d91172ff98dac9`) — table set confirmed
identical to the pre-migration dump.

---

## Notes / deviations

- Stray top-level `nginx.conf` exists here too — left as-is, not referenced by compose.
- **Framework required no modification.** Third consecutive application of the exact validated
  sequence with zero process changes. The only meaningful "new" element (custom `tasks`/`media`
  business data) changed what functional validation checked, not how the migration was done.
