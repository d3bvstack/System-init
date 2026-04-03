# Reference Documentation Index

Welcome to the technical reference for this repository. Use this index to quickly find the information you need.

## Finding Answers by Task

### "I want to know what a script does"

See the [Script Contracts](script-contracts.md) reference, which documents:
- Invocation mode and arguments
- Required environment and dependencies
- Side effects (what the script changes on the system)
- Idempotency characteristics (safe to re-run?)

Quick links:
- [scripts/setup.sh](script-contracts.md#scriptssetupsh) — Base system bootstrap and reboot
- [scripts/post-setup.sh](script-contracts.md#scriptspost-setupsh) — Post-reboot dispatcher
- [scripts/onboot-update.sh](script-contracts.md#scriptsonboot-updatesh) — 12-hour debounced updater
- [scripts/automount-disks.sh](script-contracts.md#scriptsautomount-diskssh) — Detect and automount EXT4/NTFS
- [systemd/onboot-update.service](script-contracts.md#systemdonboot-updateservice) — Service unit and hardening policy

Hooks:
- [10-install-onboot-update.sh](script-contracts.md#post-setup-hooks-10-install-onboot-updatesh) — Install updater hook
- [20-run-automount-disks.sh](script-contracts.md#post-setup-hooks-20-run-automount-diskssh) — Run automount hook

### "A script failed. How do I fix it?"

See the [Failure Modes & Troubleshooting](troubleshooting.md) reference, organized by stage:

**Stage 1 (Base Setup):**
- [apt update/upgrade failures](troubleshooting.md#failure-apt-update-or-upgrade-fails)
- [group creation issues](troubleshooting.md#failure-group-creation-fails-for-seat)
- [code-insiders install problems](troubleshooting.md#failure-code-insiders-install-fails)

**Stage 2 (Post-Setup Dispatcher):**
- [execution context rejected](troubleshooting.md#failure-script-rejects-execution-context)
- [missing hook/source files](troubleshooting.md#failure-missing-hooksource-files)
- [local extension hook failures](troubleshooting.md#failure-local-extension-hook-breaks-dispatcher)

**Disk Automounting:**
- [no disks configured](troubleshooting.md#failure-no-disks-configured)
- [mount or ownership failures](troubleshooting.md#failure-mount-or-ownership-operations-fail)
- [restore from fstab backup](troubleshooting.md#recovery-restore-fstab-backup)

**On-Boot Updater:**
- [service not running at boot](troubleshooting.md#failure-updater-does-not-run-at-boot)
- [service skips due to debounce](troubleshooting.md#failure-updater-runs-but-immediately-skips)

[Diagnostics Checklist](troubleshooting.md#diagnostics-checklist) — What to include when reporting issues.

## Available Documents

| Document | Purpose | When to Use |
|----------|---------|------------|
| [script-contracts.md](script-contracts.md) | Technical specification for each script | Understanding what a script does, required inputs, side effects, or whether it's idempotent |
| [troubleshooting.md](troubleshooting.md) | Error diagnosis and recovery procedures | Fixing failures, understanding error messages, or recovering from partial completion |

## Quick Reference: By Script

| Script | Contract | Failures | Stage |
|--------|----------|----------|-------|
| `scripts/setup.sh` | [link](script-contracts.md#scriptssetupsh) | [link](troubleshooting.md#stage-1-scriptssetupsh) | 1 |
| `scripts/post-setup.sh` | [link](script-contracts.md#scriptspost-setupsh) | [link](troubleshooting.md#stage-2-scriptspost-setupsh) | 2 |
| `scripts/automount-disks.sh` | [link](script-contracts.md#scriptsautomount-diskssh) | [link](troubleshooting.md#scriptsautomount-diskssh) | 2 |
| `scripts/onboot-update.sh` | [link](script-contracts.md#scriptsonboot-updatesh) | [link](troubleshooting.md#scripts-onboot-updatesh-and-onboot-updateservice) | boot |
| `systemd/onboot-update.service` | [link](script-contracts.md#systemdonboot-updateservice) | [link](troubleshooting.md#scripts-onboot-updatesh-and-onboot-updateservice) | boot |
