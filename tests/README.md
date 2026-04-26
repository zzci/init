# e2e tests

Black-box tests that build the image and run real containers. Each case asserts
one behavior contract.

## Run

```bash
./run.sh             # all cases
./run.sh '03*'       # only matching cases
KEEP=1 ./run.sh      # keep .tmp/ for debugging
```

## Layout

```
tests/
  run.sh        # builds image once, runs cases/*.sh, tallies pass/fail
  lib.sh       # helpers: build_image, mkwork, srv_template, srv_run,
                #          start_ctr, wait_ready, list_active, list_disabled,
                #          assert_eq, assert_contains, assert_file, ...
  cases/
    01_startup.sh         # boot + missing-config tolerance
    02_zsrv_enable.sh     # all enable variants (true/empty/value/pre-baked)
    03_zsrv_disable.sh    # disable moves to .disabled/, false-y synonyms
    04_init_sh.sh         # init.sh hook + ZSRV runs after init.sh
    05_sctl.sh            # list/enable/disable/restart/show live
    06_inject.sh          # COPY --from=zzci/init / / into alpine
    07_signals.sh         # SIGTERM via tini forwards to supervisord
  .tmp/                   # per-test work mounts (gitignored, auto-cleaned)
```

## Env

| Var        | Default         | Purpose |
|------------|-----------------|---------|
| `IMAGE`    | `zzci/init:e2e` | image tag built and tested |
| `TMP_BASE` | `tests/.tmp`    | scratch dir for `/work` mounts |
| `KEEP`     | `0`             | set to `1` to retain `TMP_BASE` after run |

## Adding a case

1. Copy an existing case file to `cases/NN_name.sh`.
2. `set -uo pipefail` and `. "$(dirname "$0")/../lib.sh"`.
3. Use `mkwork`, `srv_template`, `srv_run`, `init_hook` to set up `/work`.
4. `start_ctr` + `wait_ready` to boot the container.
5. Use `assert_eq` / `assert_contains` / `assert_file` to verify; track failures
   in a `fail` counter and `exit $fail`.
6. Always `trap "stop_ctr $cid" EXIT` so containers are cleaned up even on
   error.
