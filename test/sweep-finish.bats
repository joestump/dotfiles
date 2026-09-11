#!/usr/bin/env bats
# sweep-finish — the completion record
#
# Every scheduled sweep's last act is sweeps/lib/executable_sweep-finish, which
# writes ~/sweeps/results/<job>/<UTC>.json. harness counts crush's exit 0 as a
# success even when the model stopped mid-sentence having done nothing, so this
# record is the only reliable signal that a run finished. These tests pin that
# the record is complete, and that a mangled argument is rejected loudly rather
# than written as a wrong record.
#
# @joestump 09/11/2026 - Added with the lean sweep profile.
load test_helper

SF="$REPO_ROOT/sweeps/lib/executable_sweep-finish"

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  export SWEEP_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
}

@test "sweep-finish: writes one complete record and prints its path" {
  run bash "$SF" --job morning-brief --outcome ok --summary "Brief sent, 2 items." \
    --counts '{"merged":2}' --errors '["gitea 502 once"]' --signal-sent true
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  case "$output" in
    "$SWEEP_RESULTS_DIR"/morning-brief/*.json) ;;
    *) echo "record landed outside the job's results dir: $output"; false ;;
  esac
  run jq -e '
    .job == "morning-brief" and .outcome == "ok" and .summary == "Brief sent, 2 items."
    and .counts.merged == 2 and .errors == ["gitea 502 once"] and .signal_sent == true
    and (.finished_at | test("^[0-9]{8}T[0-9]{6}Z$"))
    and (.host | length > 0) and (.identity | length > 0)' "$output"
  [ "$status" -eq 0 ]
}

@test "sweep-finish: counts and errors default to empty, signal-sent to false" {
  run bash "$SF" --job issue-sweep --outcome noop --summary "Nothing to groom."
  [ "$status" -eq 0 ]
  run jq -e '.counts == {} and .errors == [] and .signal_sent == false and .outcome == "noop"' "$output"
  [ "$status" -eq 0 ]
}

@test "sweep-finish: requires job, outcome and summary" {
  run bash "$SF" --job pr-sweep --outcome ok
  [ "$status" -eq 2 ]
  run bash "$SF" --outcome ok --summary "x"
  [ "$status" -eq 2 ]
  [ ! -d "$SWEEP_RESULTS_DIR" ]
}

@test "sweep-finish: rejects an outcome outside the four it records" {
  run bash "$SF" --job pr-sweep --outcome done --summary "x"
  [ "$status" -eq 2 ]
  [ ! -d "$SWEEP_RESULTS_DIR/pr-sweep" ]
}

@test "sweep-finish: rejects counts that are not an object and errors that are not an array" {
  run bash "$SF" --job pr-sweep --outcome ok --summary "x" --counts '[1,2]'
  [ "$status" -eq 2 ]
  run bash "$SF" --job pr-sweep --outcome ok --summary "x" --counts 'not json'
  [ "$status" -eq 2 ]
  run bash "$SF" --job pr-sweep --outcome ok --summary "x" --errors '{"a":1}'
  [ "$status" -eq 2 ]
  [ ! -d "$SWEEP_RESULTS_DIR/pr-sweep" ]
}

@test "sweep-finish: signal-sent must be true or false" {
  run bash "$SF" --job pr-sweep --outcome ok --summary "x" --signal-sent yes
  [ "$status" -eq 2 ]
}

@test "sweep-finish: a job name cannot escape the results directory" {
  run bash "$SF" --job ../escape --outcome ok --summary "x"
  [ "$status" -eq 2 ]
  run bash "$SF" --job a/b --outcome ok --summary "x"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/escape" ]
}

@test "sweep-finish: an unknown flag is a usage error, not a silent drop" {
  run bash "$SF" --job pr-sweep --outcome ok --summary "x" --count '{}'
  [ "$status" -eq 2 ]
}
