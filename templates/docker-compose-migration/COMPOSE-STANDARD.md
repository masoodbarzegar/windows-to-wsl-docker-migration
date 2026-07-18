# Compose Standard for Windows → WSL Migrations

This is the standard every migrated development project should follow, extracted from the working `laravelLivewireAdmin` reference migration (`~/personal/laravel/laravelLivewireAdmin/compose.yaml`, `DOCKER-MIGRATION-NOTES.md`). It is a **standard to apply with judgment, not a file to copy blindly** — see `README.md` for the distinction.

Each rule below states the requirement, why it exists, and what it looks like in practice.

---

### 1. No top-level `version` field

The `version:` key is obsolete in the current Compose Specification and is ignored (with a warning) by modern `docker compose`. Omit it entirely.

### 2. No explicit `container_name`

A hardcoded `container_name` is unique per Docker daemon. It blocks running two copies of a stack side by side (a second migrated project, a feature-branch stack, this same project checked out twice) with a hard name collision. Let Compose auto-generate names (`<project>-<service>-<n>`) — `docker compose exec <service> ...` still addresses services by name regardless.

### 3. No `restart: always` or `restart: unless-stopped`

Those policies exist for unattended production uptime, not a WSL dev inner loop. On a dev machine they cause containers to silently survive reboots/`wsl --shutdown`, holding ports and mounting stale code without you noticing. Omit `restart:` entirely (equivalent to `restart: "no"`, Compose's default) unless a project has a deliberate, documented reason to survive unattended restarts — treat that as an explicit exception, not a default.

### 4. Development containers start only when explicitly requested

Nothing should auto-start via `restart:` policies (rule 3), and optional/inspection services (phpMyAdmin, pgAdmin, mailhog, etc.) must require an explicit `--profile` flag (rule 11). `docker compose up -d` should bring up only what you actually need for day-to-day development — the app stack, not every convenience tool.

### 5. Compose project name must be explicit and unique

Set the top-level `name:` key rather than relying on Compose's implicit directory-name derivation. Two reasons: (a) it guarantees a named/external volume resolves to the volume you intend regardless of where the project directory sits or gets renamed, and (b) it guarantees isolation — a WSL migration of a project that has an old Windows-side Compose project of the same logical name must use a **different** project name (the established convention: append `_wsl`, e.g. `laravellivewireadmin_wsl`) so `docker compose` commands can never target, recreate, rename, or stop the old project's containers.

```yaml
name: ${COMPOSE_PROJECT_NAME:-changeme_wsl}
```

### 6. Host-facing ports configurable through an environment file

Every published port should be `${VAR:-default}`, with the default matching current/expected behavior so the file works unmodified out of the box. This avoids editing the compose file itself to resolve a port conflict — override in `.env.docker` instead.

```yaml
ports:
  - "${APP_PORT:-8080}:80"
```

### 7. Databases should not publish host ports unless genuinely needed

Application containers and admin tools (phpMyAdmin/pgAdmin) reach the database over the internal Compose network using the service name (rule 8) — they never need a host-published port. Leave the database's port unpublished by default; document (commented out, ready to uncomment) how to add one for the rare case a native host-side client needs direct access.

### 8. Containers communicate using Compose service names

Nginx talks to PHP-FPM as `app:9000`, the app talks to the database as `db:5432`/`db:3306`, phpMyAdmin/pgAdmin talk to the database as `db`. Never hardcode `127.0.0.1`, `localhost`, or a Windows host IP between containers — only the host machine's own port-forwarding uses `localhost`.

### 9. Named volumes declared explicitly

Every volume with data that must survive a container recreation gets a named volume, declared under the top-level `volumes:` key. Anonymous volumes and bind-mounted "data directories" make migration and backup harder to reason about — see rule 15 on Windows bind mounts specifically.

### 10. Existing migrated volumes may be `external` only when intentionally reusing existing data

When (and only when) a migration is deliberately attaching to a Docker volume that already has real data in it (the exact scenario in the `laravelLivewireAdmin` reference migration), declare it explicitly:

```yaml
volumes:
  dbdata:
    external: true
    name: existing_volume_name_here
```

`external: true` makes Compose refuse to start if the named volume doesn't already exist, rather than silently creating an empty one — this is the safety property that matters. For a brand-new project with no prior data, leave the volume as a plain declaration (no `external`) and let Compose create/manage it normally.

### 11. phpMyAdmin or pgAdmin must be behind a `tools` profile

```yaml
phpmyadmin:
  profiles: [tools]
```
A service with no `profiles:` key always starts; a service with a profile only starts when requested. `docker compose up -d` → app stack only. `docker compose --profile tools up -d` → app stack + the admin tool. This is the standardized on/off switch for anything that's a convenience, not a dependency.

### 12. Healthchecks for databases

Every database service gets a `healthcheck:` — `mysqladmin ping` for MySQL, `pg_isready` for PostgreSQL. Without one, Compose (and any dependent service) has no way to distinguish "container process started" from "database actually accepting connections," which is the single most common source of flaky first-boot failures in a multi-container dev stack.

### 13. Application dependency on database health where supported

The service that directly talks to the database uses the long-form `depends_on` with `condition: service_healthy`, not the short form (which only waits for the container process to start):

```yaml
depends_on:
  db:
    condition: service_healthy
```
Services that don't talk to the database directly (e.g. a web server that only proxies to the app service) can keep the short-form, start-order-only dependency.

### 14. Secrets belong in local, ignored env files

Real credentials go in `.env.docker` (or equivalent), which is git-ignored. The compose file itself contains no real secrets — only `${VAR:-safe_dev_default}` references. Add the real file to `.gitignore` as part of every migration, not as an afterthought.

### 15. Example env files contain only safe development placeholders

`.env.docker.example` is tracked in git and must never contain a real password, key, or token — only obvious placeholders (`secret`, `changeme`, `root`) that make it clear a real value belongs in the copied `.env.docker`, and that double as harmless local-dev defaults.

### 16. Windows bind mounts must not remain after migration

A completed migration has **no** bind mount, named volume source path, `build.context`, or `env_file` pointing at `/mnt/e/...`, `/mnt/c/...`, or any `E:\`/`C:\` path. Every path in the compose file is relative to the project directory, which now lives entirely under WSL (`/home/masoud/...`). This is the concrete, checkable definition of "migrated" — see the Validation section of `PROJECT-MIGRATION-CHECKLIST.md`.

### 17. `docker compose down` must never use `-v` during ordinary development

`docker compose down -v` deletes named volumes along with the containers — in a dev stack with a real (possibly `external`) database volume, this is indistinguishable from data loss until it's too late. Plain `docker compose down` (no `-v`) is the standard day-to-day command. Deleting a volume is a deliberate, separate, explicit action — never a side effect of routine teardown.

---

## Quick reference: rule → compose.yaml feature

| Rule | Compose feature |
|---|---|
| 1, 2, 3 | Simply omitted from the file |
| 4, 11 | `profiles:` |
| 5 | top-level `name:` |
| 6, 7 | `${VAR:-default}` in `ports:` |
| 8 | service names as hostnames, no hardcoded IPs |
| 9, 10 | top-level `volumes:`, optional `external: true` + `name:` |
| 12 | `healthcheck:` |
| 13 | `depends_on: <service>: condition: service_healthy` |
| 14, 15 | `--env-file .env.docker` + `.gitignore` |
| 16 | every path relative, none under `/mnt/*` or `E:\`/`C:\` |
| 17 | operational discipline, not a YAML feature — document it, don't rely on the tooling to prevent it |
