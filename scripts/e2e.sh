#!/usr/bin/env bash
#
# End-to-end checks for the native CLI.
#
# Builds the executable, runs every fixture pair from `fixtures/` through it as
# a real process, and checks the exit code, the diagnostic code that must
# appear, JSON validity for `--format json`, and that two runs of the same
# input produce identical bytes. The analysis itself performs no network
# access; as with any build, a cold module cache is populated from the registry
# before the first compile.
#
# Run from anywhere:  scripts/e2e.sh

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

binary="_build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe"

if ! command -v python3 >/dev/null 2>&1; then
  echo "e2e: python3 is required to validate JSON output" >&2
  exit 1
fi

echo "e2e: building $binary"
moon build --target native

if [[ ! -x "$binary" ]]; then
  echo "e2e: executable not found at $binary" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

checks=0
failures=0

fail() {
  failures=$((failures + 1))
  echo "e2e: FAIL $*" >&2
}

# case | command | format | expected exit | diagnostic code that must appear
cases="
compatible|check|text|0|
compatible|check|json|0|
append|check|text|0|storage.entry.added
storage-removed|storage|text|1|storage.entry.removed
storage-removed|abi|text|0|
storage-moved|storage|text|1|storage.entry.slot.changed
struct-change|storage|text|1|storage.entry.type.changed
abi-function-removed|abi|json|1|abi.function.removed
abi-function-removed|storage|text|0|
abi-event-indexed|abi|text|1|abi.event.indexed.changed
invalid-json|check|json|2|artifact.json.invalid
unsupported-artifact|check|text|2|artifact.layout.missing
ambiguous-build-info|check|text|2|artifact.contract.ambiguous
missing-file|check|text|2|
"

while IFS='|' read -r case command format expected code; do
  [[ -n "$case" ]] || continue
  old="fixtures/$case/old.json"
  new="fixtures/$case/new.json"
  output="$tmp/$case.$command.$format.out"
  checks=$((checks + 1))

  set +e
  "$binary" "$command" "$old" "$new" --format "$format" >"$output"
  status=$?
  set -e

  if [[ "$status" != "$expected" ]]; then
    fail "$case $command $format: exit $status, expected $expected"
  fi

  if [[ -n "$code" ]] && ! grep -q -- "$code" "$output"; then
    fail "$case $command $format: output does not mention $code"
  fi

  if [[ "$format" == "json" ]] &&
    ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$output"; then
    fail "$case $command $format: output is not valid JSON"
  fi

  # The same input twice must produce the same bytes.
  set +e
  "$binary" "$command" "$old" "$new" --format "$format" >"$tmp/repeat.out"
  set -e
  if ! cmp -s "$output" "$tmp/repeat.out"; then
    fail "$case $command $format: repeated run differs"
  fi
done <<< "$cases"

# A compatible pair reports nothing at all.
if [[ -s "$tmp/compatible.check.text.out" ]]; then
  fail "compatible check printed output"
fi

# Command line surface, checked by exit code as well.
expect_exit() {
  local description="$1" expected="$2"
  shift 2
  checks=$((checks + 1))
  set +e
  "$binary" "$@" >"$tmp/args.out"
  local status=$?
  set -e
  if [[ "$status" != "$expected" ]]; then
    fail "$description: exit $status, expected $expected"
  fi
}

expect_exit "--help" 0 --help
expect_exit "no arguments" 2
expect_exit "unknown command" 2 check-fixtures
expect_exit "unknown format" 2 check fixtures/compatible/old.json fixtures/compatible/new.json --format yaml

if [[ "$failures" -ne 0 ]]; then
  echo "e2e: $checks checks, $failures failed" >&2
  exit 1
fi

echo "e2e: $checks checks passed"
