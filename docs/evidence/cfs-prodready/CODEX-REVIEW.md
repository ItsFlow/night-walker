# Codex review — security-sensitive surface

Date: 2026-08-19
Tool: `codex exec review --uncommitted` (model `gpt-5.6-sol`)
Scope: `CMediaAccessibility.h`, `CLI.swift`, `ColorFilters.swift`,
`bundle.sh`, `dmg.sh`, LaunchAgent template, `install.sh`, `uninstall.sh`.

Independent review of the production-readiness patches on `fm/cfs-prodready`.
Constraints treated as non-bugs: historical bundle id, SPI signatures,
ad-hoc sign only, no notarization / Hardened Runtime / TCC helper.

## Verdict

Two real defects in the uncommitted patch; both fixed on this branch after
the review. No remaining open defect in the scoped files that Codex proved.

## Findings

### P1 — CI live-toggle fails closed on a clean runner — **fixed**

`tests/cli-contract.sh` treated a missing Color Filters preference
(`ORIG_ENABLED` empty) as a test **failure**, then still ran
`--reconcile --apply`. On GitHub Actions `macos-latest` that can:

1. Fail the new `Headless suite` job even when the app is correct.
2. Create a `com.apple.mediaaccessibility` key the restore path cannot
   put back (restore no-ops when the snapshot is empty).

**Fix landed:** skip all live mutation (`--set-enabled` flip and
`--reconcile --apply`) when the pre-test snapshot has no enabled or
intensity key. Read-only CLI checks still run.

### P2 — `--render-panel` cwd confine missed symlink escape — **fixed**

`confinedDir` used `standardizedFileURL`, which normalizes `.` / `..`
but does **not** resolve a symlink. A cwd-relative symlink to `/tmp`
would pass the prefix check and write the evidence PNGs outside cwd.

**Fix landed:** resolve symlinks on both cwd and the candidate path
before the prefix check.

## Already closed (Codex did not re-open)

- SPI header signatures left alone.
- CLI fail-closed on NaN / Inf / out-of-range lat/lon and non-finite
  offsets; `--set-intensity` finite 0…1; setter ignores NaN.
- `--render-panel` no longer writes `Settings.shared`.
- `install.sh` refuses if `Color Filter Scheduler.app` exists
  (override `--replace-login-item`).
- LaunchAgent paths set via `PlistBuddy` (XML-escaped; spaces in
  `Night Walker.app` verified).
- `uninstall.sh` refuses the legacy app; bundle-id check before delete.
- Ad-hoc `codesign --sign - --identifier com.flo.color-filter-scheduler`
  (no `--deep`, no Hardened Runtime).

## Residual risk (unchanged, not defects)

- Ad-hoc signature: Gatekeeper unidentified-developer, right-click Open.
- Private MediaAccessibility SPI; no TCC prompt (OS design).
- Shared bundle id with the captain live app — install/uninstall now
  refuse that collision instead of hijacking it.
- `--engine-reconcile` on the bundled binary still applies this
  process’s UserDefaults; help text says so; tests use `.build/`.
