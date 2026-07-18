# Docker Compose Migration Template Package

This package turns the working `laravelLivewireAdmin` WSL migration into a reusable standard for every remaining Windows → WSL project migration listed in `~/docker-audit/migration-plan.md`.

## What this package is

A distilled, reusable version of the process that already worked once, live, on `laravelLivewireAdmin`:
- `COMPOSE-STANDARD.md` — the 17 rules that setup follows, with the reasoning behind each one.
- `PROJECT-MIGRATION-CHECKLIST.md` — the same phases from `migration-plan.md` (Discovery → Backup → Copy → Compose normalization → Validation → Cutover), turned into a per-project, fill-in-the-blanks checklist.
- `compose.mysql-laravel.example.yaml` / `compose.postgres-laravel.example.yaml` — generic starting points for the two database engines the audit found in use (`mysql`, `postgres`), built directly from the validated `laravelLivewireAdmin/compose.yaml`.
- `.env.docker.example` — the generic environment-variable surface every migrated project should expose.
- `migrate-project.sh` — a conservative, non-destructive script that only prepares a destination and reports on it. It never starts a container or deletes anything.

## What is reusable as-is

- The **rules** in `COMPOSE-STANDARD.md` — these apply to every project, no exceptions, unless you make and document a deliberate one (e.g. rule 3's "unattended restart" exception).
- The **checklist structure** in `PROJECT-MIGRATION-CHECKLIST.md` — copy it per project, fill it in.
- The **`.env.docker.example` variable names** — `COMPOSE_PROJECT_NAME`, `APP_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `PHPMYADMIN_PORT`, `PGADMIN_PORT` — keep these names consistent across projects so the pattern stays predictable.
- **`migrate-project.sh`** — safe to run against any project's source/destination pair unmodified; it doesn't know or care what's inside the project.

## What must still be adapted per project

Every line in the example Compose files marked `CHANGE-ME` needs a real value:
- `COMPOSE_PROJECT_NAME` — always unique; append `_wsl` specifically when an old Windows-side project of the same logical name still exists (this is what kept `laravelLivewireAdmin`'s migration isolated from the old containers).
- `build:` context paths and bind-mount source paths — match this project's actual directory layout (not every project has a `docker/php` + `src/` split; some have PHP and app code together, some have no Node/Vite dev server at all).
- The database engine block — not every project needs both templates; pick MySQL or PostgreSQL, delete the other's leftover service if you started from a copy of both.
- `external: true` / `name:` on the `dbdata` volume — **only** uncomment this when deliberately reusing an existing volume with real data (per the audit, most projects don't have one yet; `laravelLivewireAdmin` did). For a project with no prior Docker-managed volume, leave it as a plain declaration.
- phpMyAdmin/pgAdmin image tags — re-pin to whatever version you've actually tested for that project if `5.2.1` / `8.12` aren't what you want.
- Port defaults — if you plan to run several migrated stacks concurrently, give each project distinct default ports in its own `.env.docker` rather than colliding on `8080`/`8081` for all of them.

## How to use the checklist

1. Copy `PROJECT-MIGRATION-CHECKLIST.md` to something like `checklist-<project>.md` (in the project's own directory, or wherever you're tracking migration work).
2. Work through Discovery first, in full, before touching anything — it's what tells you whether this project even needs the MySQL or Postgres template, whether it has real unbacked-up data, and whether a Windows-side old project of the same name exists (which decides the `_wsl` naming question).
3. Don't skip Backup, even for a project that looks low-risk — it's the cheapest phase and the one that makes every later mistake reversible.
4. Compose normalization is where you actually copy from the relevant `compose.*.example.yaml` and fill in the `CHANGE-ME` values.
5. Validation is not optional and not just "does `docker compose config` succeed" — the checklist deliberately includes a real functional workflow check and a `docker compose restart` survival check, because a stack that "worked" only because it was never restarted isn't actually validated.
6. Cutover explicitly requires separate approval before deleting anything — the checklist will not let you tick that box implicitly.

## How to run the helper script in dry-run mode

```bash
cd ~/docker-audit/templates/docker-compose-migration
./migrate-project.sh --source "/mnt/e/LocalDev/Laravel/quizGameVtwo" \
                      --destination "$HOME/personal/laravel/quizGameVtwo" \
                      --dry-run
```

This prints every planned action (`mkdir`, the exact `rsync` command, the inventory report path, whether a `docker compose config` check would run) **without performing any of them**. Drop `--dry-run` to actually copy once you're satisfied with the plan. The script will refuse to run at all if the destination already exists and is non-empty — there is no `--force` flag, by design.

The script never starts or stops a container, never deletes a file, never touches a Docker resource, and never modifies anything under `--source`. It only creates a destination, copies into it, and writes a report. Everything after that (backup restoration, Compose normalization, bringing the stack up, validation, cutover) is a manual, deliberate step you take by hand, guided by `PROJECT-MIGRATION-CHECKLIST.md`.

## Why this is a standard, not a blind copy-paste solution

Every project the earlier audits found is a little different: some have a Node dev server in the `app` container and some don't, some already have real unbacked-up database folders and some are starting fresh, some share a project name with a still-present old Windows-side Compose project and most don't, some will run concurrently with other migrated stacks and most (for now) won't. A template that's copied and run unmodified would either silently do the wrong thing (e.g. an `external: true` volume reference that doesn't exist yet, causing a hard failure — or worse, no `external` flag on a volume that should have one, silently creating a second, empty, decoy volume next to the real data) or overwrite defaults that don't fit.

What's actually reusable is the **reasoning** in `COMPOSE-STANDARD.md` (why no `container_name`, why profiles, why `external` volumes are conditional) and the **shape** of the process in `PROJECT-MIGRATION-CHECKLIST.md` (discover before backing up, back up before copying, validate before cutover, never delete without separate approval). The YAML files are a fast starting point for that shape, not a substitute for reading the Discovery section of the checklist for the specific project in front of you.

## Files in this package

```
docker-compose-migration/
├── README.md                              (this file)
├── COMPOSE-STANDARD.md                    the 17 rules + rationale
├── PROJECT-MIGRATION-CHECKLIST.md         copy per project
├── compose.mysql-laravel.example.yaml     generic MySQL + Laravel starting point
├── compose.postgres-laravel.example.yaml  generic PostgreSQL + Laravel starting point
├── .env.docker.example                    generic env var surface
└── migrate-project.sh                     non-destructive copy + inventory helper
```
