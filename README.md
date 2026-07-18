# Windows to WSL Docker Migration Playbook

A practical engineering playbook documenting the migration of real-world Docker development environments from Windows to WSL.

This repository captures an end-to-end migration project involving **13 successfully migrated development environments**, including audit, planning, database recovery, validation, cleanup, and reusable migration templates.

> **This is not a Docker tutorial.**
>
> It is an engineering reference built from real migration work, with an emphasis on repeatability, recoverability, and evidence-based decision making.

---

# Migration Workflow

```text
                    ┌──────────────────────┐
                    │ Windows Source       │
                    │ (Read-only)          │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Evidence Backup      │
                    │ Physical copy        │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Recovery             │
                    │ Compatibility check  │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Logical Dump         │
                    │ Database export      │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ WSL Migration        │
                    │ Docker Compose       │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Validation           │
                    │ Restart verification │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Cleanup              │
                    │ Remove legacy Docker │
                    └──────────────────────┘
```

---

# Goals

- Migrate Docker-based development environments from Windows to WSL
- Preserve application source code and Git history
- Preserve local changes and recoverability
- Standardize Docker Compose projects
- Document reusable migration workflows
- Minimize project-specific modifications
- Base every migration decision on verifiable evidence

---

# Repository Structure

```text
templates/
    Reusable migration templates
    Docker Compose standards
    Migration checklist
    Helper scripts

project-checklists/
    Migration records for every project

migration-plan.md
    Master tracker

docker-audit-report.md
    Initial audit report

*.tsv
    Discovery inventories
```

---

# Engineering Principles

- Physical backup before any destructive action
- Never modify the original Windows source
- Preserve Git history, branches, stash, and local changes
- Restore databases into fresh WSL-native named volumes
- Validate every migration
- Prefer minimal project-specific changes
- Separate evidence from documentation
- Make decisions based on observable evidence

---

# What is Included

- Windows → WSL migration methodology
- Docker audit workflow
- Validation checklists
- Recovery procedures
- Cleanup strategy
- Reusable Docker Compose templates
- Lessons learned from multiple migrations

---

# What is Intentionally Excluded

This repository does **not** contain:

- Raw database files
- Physical backups
- Logical dumps
- Recovery working copies
- Temporary migration artifacts
- Machine-specific configuration
- Credentials or infrastructure secrets

Those artifacts remain outside Git by design.

---

# Project Outcome

| Result | Count |
|---------|------:|
| Successfully migrated | 13 |
| Archived | 1 |
| Deferred | 1 |

The migration framework has been validated across multiple real-world projects and is preserved here as a reusable engineering reference.

---

# License

MIT
