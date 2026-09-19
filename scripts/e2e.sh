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

# case | command | format | expected exit | diagnostic code | extra arguments
cases="
compatible|check|text|0|
compatible|check|json|0|
append|check|text|0|storage.entry.added
storage-renamed|check|text|0|storage.entry.label.changed
storage-removed|storage|text|1|storage.entry.removed
storage-removed|abi|text|0|
storage-moved|storage|text|1|storage.entry.slot.changed
struct-change|storage|text|1|storage.entry.type.changed
storage-gap-shrink|check|text|0|storage.gap.changed
storage-gap-unsafe|storage|text|1|storage.entry.slot.changed
storage-gap-dynamic|storage|text|1|storage.entry.removed
storage-gap-finished|check|text|0|storage.gap.changed
transient-moved|storage|text|1|storage.entry.slot.changed
transient-append|check|text|0|storage.entry.added
transient-removed|storage|text|1|storage.entry.removed
abi-function-removed|abi|json|1|abi.function.removed
abi-fallback-kind|abi|text|1|abi.function.removed
abi-fallback-kind|storage|text|0|
abi-function-removed|storage|text|0|
abi-event-indexed|abi|text|1|abi.event.indexed.changed
invalid-json|check|json|2|artifact.json.invalid
unsupported-artifact|check|text|2|artifact.layout.missing
ambiguous-build-info|check|text|2|artifact.contract.ambiguous
contract-selector|check|text|2|artifact.contract.ambiguous|
contract-selector|check|text|0||--contract Alpha
contract-selector|check|text|1|storage.entry.slot.changed|--contract Beta
contract-selector|check|json|1|storage.entry.slot.changed|--contract contracts/Beta.sol:Beta
contract-selector|check|text|2|artifact.contract.missing|--contract Nope
namespaced-storage|check|text|2|artifact.namespaced-storage.unsupported
schema-solc-0.5-to-0.8|check|json|0|
schema-solc-0.6-to-0.8|check|text|0|
schema-unsupported|check|text|2|storage.type.encoding.unsupported
fractional-offset|check|text|2|artifact.field.invalid
fractional-offset|check|json|2|artifact.field.invalid
missing-file|check|text|2|
missing-file|check|json|2|cli.input.unreadable
"

while IFS='|' read -r case command format expected code extra; do
  [[ -n "$case" ]] || continue
  old="fixtures/$case/old.json"
  new="fixtures/$case/new.json"
  output="$tmp/$case.$command.$format.out"
  checks=$((checks + 1))

  # `$extra` is deliberately unquoted so that a column can hold several
  # arguments, such as `--contract NAME`.
  # shellcheck disable=SC2086
  set +e
  "$binary" "$command" "$old" "$new" --format "$format" $extra >"$output"
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
  # shellcheck disable=SC2086
  "$binary" "$command" "$old" "$new" --format "$format" $extra >"$tmp/repeat.out"
  set -e
  if ! cmp -s "$output" "$tmp/repeat.out"; then
    fail "$case $command $format: repeated run differs"
  fi
done <<< "$cases"

# A compatible pair reports nothing at all.
if [[ -s "$tmp/compatible.check.text.out" ]]; then
  fail "compatible check printed output"
fi

# Transient findings name their own namespace, so a report tells the two
# address spaces apart.
checks=$((checks + 1))
if ! grep -qF -- "transientStorage[" "$tmp/transient-moved.storage.text.out"; then
  fail "transient-moved: the finding does not name the transient namespace"
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

# An operational failure answers in the requested format, so a JSON reader
# never has to parse prose.
checks=$((checks + 1))
set +e
"$binary" unknown-command fixtures/compatible/old.json fixtures/compatible/new.json --format json >"$tmp/args.json"
status=$?
set -e
if [[ "$status" != "2" ]]; then
  fail "argument failure: exit $status, expected 2"
fi
if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$tmp/args.json"; then
  fail "argument failure: stdout is not valid JSON"
fi
if ! grep -q -- "cli.argument.invalid" "$tmp/args.json"; then
  fail "argument failure: output does not mention cli.argument.invalid"
fi

expect_exit "--help" 0 --help
expect_exit "no arguments" 2
expect_exit "unknown command" 2 check-fixtures
expect_exit "unknown format" 2 check fixtures/compatible/old.json fixtures/compatible/new.json --format yaml
expect_exit "--contract without a value" 2 check fixtures/compatible/old.json fixtures/compatible/new.json --contract

if [[ "$failures" -ne 0 ]]; then
  echo "e2e: $checks checks, $failures failed" >&2
  exit 1
fi

echo "e2e: $checks checks passed"
