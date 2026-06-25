#!/usr/bin/env bash
#
# These checks register synthetic target and exec Python toolchains in a nested
# module so they cannot affect the parent e2e workspace's toolchain resolution.
set -uo pipefail

case_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$case_dir" || exit 1

BAZEL="${BAZEL:-bazel}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

analyze() {
    local target_toolchain="$1"
    local exec_toolchain="$2"
    local target="$3"

    "$BAZEL" cquery \
        --extra_execution_platforms=//:exec_platform \
        "--extra_toolchains=${target_toolchain},${exec_toolchain}" \
        --lockfile_mode=off \
        --platforms=//:target_platform \
        -- "$target"
}

expect_success() {
    local output

    if ! output="$(analyze "$@" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail "$3 failed analysis"
    fi
}

expect_failure() {
    local target_toolchain="$1"
    local exec_toolchain="$2"
    local expected="$3"
    local output

    if output="$(analyze "$target_toolchain" "$exec_toolchain" //:fixture 2>&1)"; then
        fail "//:fixture accepted incompatible bytecode runtimes"
    fi
    if [[ "$output" != *"$expected"* ]]; then
        printf '%s\n' "$output" >&2
        fail "//:fixture failed without the expected bytecode diagnostic"
    fi
}

expect_success \
    //:target_runtime_toolchain \
    //:exec_runtime_toolchain \
    //:fixture
expect_failure \
    //:target_runtime_toolchain \
    //:magic_mismatched_exec_runtime_toolchain \
    "pyc identity target=(3, 13, 3571), exec=(3, 13, 3627)"
expect_failure \
    //:target_runtime_toolchain \
    //:version_mismatched_exec_runtime_toolchain \
    "pyc identity target=(3, 13, 3571), exec=(3, 14, 3571)"
expect_failure \
    //:target_runtime_toolchain \
    //:mismatched_exec_runtime_toolchain \
    "pyc identity target=(3, 13, 3571), exec=(3, 14, 3627)"
expect_failure \
    //:target_runtime_toolchain \
    //:ordinary_exec_runtime_toolchain \
    "pyc identity target=(3, 13, 3571), exec=None"
expect_success \
    //:ordinary_target_runtime_toolchain \
    //:mismatched_exec_runtime_toolchain \
    //:fixture
expect_success \
    //:ordinary_target_runtime_toolchain \
    //:ordinary_exec_runtime_toolchain \
    //:fixture
expect_success \
    //:target_runtime_toolchain \
    //:mismatched_exec_runtime_toolchain \
    //:fixture_without_precompilation

echo "PASS: whl_install validates target and exec .pyc runtimes"
