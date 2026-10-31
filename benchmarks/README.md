# Benchmarks

Wall-clock budgets, not tests. They measure timings (ms budgets, Stopwatch
asserts, frame and open times, GPU runs) and fail on a loaded machine for
reasons that have nothing to do with correctness. So they live outside
`test/`: no test run (`flutter test`, `wp-test.sh run <wt> test`, `wp-test.sh full`,
CI) ever picks them up.

Start one deliberately by its path, on quiet hardware (for example in the
core review before a release):

`wp-test.sh run <worktree> --host mac benchmarks/<path>`

Files that prove the logic of the same code stay in `test/`; only the timing
parts live here. Shared helpers come from `test/` through imports, as in
`generators/`.
