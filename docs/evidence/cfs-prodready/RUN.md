# Local test run (this machine)

Date: 2026-08-19

## Command

```sh
RUN_BUNDLE=0 tests/run.sh
bash tests/bundle-contract.sh
swift build -c release
```

`tests/run.sh` with default `RUN_BUNDLE=1` is the single entry for
local / CI / no-mistakes. CI sets `RUN_BUNDLE=0` and runs `bundle.sh`
in a separate job.

## Result

**exit 0**

| suite | result |
|---|---|
| panel-contract | pass |
| ui-contract | pass |
| `--selftest` (31 checks) | pass |
| cli-contract | pass |
| hygiene | pass |
| bundle-contract | pass (universal `x86_64` + `arm64`, identifier `com.flo.color-filter-scheduler`) |
| `swift build -c release` | pass (host-arch arm64) |

## Color Filters / live Mac

Pre-test and post-test identical:

- enabled `1`
- intensity `0.7912975193298969`
- type `16`

`com.flo.color-filter-scheduler` (Lisbon, Automatic on) unchanged.
`~/Applications/Color Filter Scheduler.app` still present.
`~/Applications/Night Walker.app` was not created.
`install.sh` / `uninstall.sh` were not run.
LaunchAgent was not rewritten.

Live-toggle coverage (cli-contract): one `--set-enabled` flip and one
frozen-time `--reconcile --apply`, both restored via the `.build`
binary’s SPI setters.
