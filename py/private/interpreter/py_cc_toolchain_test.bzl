"""Analysis tests for local Python C toolchain registration."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":py_cc_toolchain.bzl", "local_py_cc_toolchain")

_PYTHON_TOOLCHAIN = "@bazel_tools//tools/python:toolchain_type"
_PYTHON_CC_TOOLCHAIN = "@rules_python//python/cc:toolchain_type"
_RUNTIME_ONLY_TOOLCHAINS = {
    "//command_line_option:extra_toolchains": [
        "//py/private/interpreter:_local_python_runtime_registration",
        "//py/private/interpreter:_local_python_cc_registration",
    ],
}
_CC_SELECTION_TOOLCHAINS = {
    "//command_line_option:extra_toolchains": [
        "//py/private/interpreter:all",
    ],
}

def _fake_python_runtime_impl(_ctx):
    return [platform_common.ToolchainInfo()]

_fake_python_runtime = rule(implementation = _fake_python_runtime_impl)

def _fake_py_cc_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        marker = ctx.attr.marker,
        py_cc_toolchain = struct(python_version = ctx.attr.python_version),
    )]

_fake_py_cc_toolchain = rule(
    implementation = _fake_py_cc_toolchain_impl,
    attrs = {
        "marker": attr.string(mandatory = True),
        "python_version": attr.string(mandatory = True),
    },
)

def _toolchain_consumer_impl(_ctx):
    return []

_python_runtime_consumer = rule(
    implementation = _toolchain_consumer_impl,
    toolchains = [_PYTHON_TOOLCHAIN],
)

def _python_cc_consumer_impl(ctx):
    return [ctx.toolchains[_PYTHON_CC_TOOLCHAIN]]

_python_cc_consumer = rule(
    implementation = _python_cc_consumer_impl,
    toolchains = [_PYTHON_CC_TOOLCHAIN],
)

def _forwarding_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, platform_common.ToolchainInfo in target)
    if platform_common.ToolchainInfo in target:
        toolchain = target[platform_common.ToolchainInfo]
        asserts.equals(env, "forwarded", toolchain.marker)
        asserts.equals(env, "3.12", toolchain.py_cc_toolchain.python_version)
    return analysistest.end(env)

_forwarding_test = analysistest.make(_forwarding_test_impl)

def _success_test_impl(ctx):
    env = analysistest.begin(ctx)
    analysistest.target_under_test(env)
    return analysistest.end(env)

_runtime_only_test = analysistest.make(
    _success_test_impl,
    config_settings = _RUNTIME_ONLY_TOOLCHAINS,
)

_cc_selection_test = analysistest.make(
    _forwarding_test_impl,
    config_settings = _CC_SELECTION_TOOLCHAINS,
)

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_error)
    return analysistest.end(env)

_failure_test = analysistest.make(
    _failure_test_impl,
    attrs = {"expected_error": attr.string(mandatory = True)},
    expect_failure = True,
)

def local_py_cc_toolchain_test_suite():
    _fake_python_runtime(
        name = "_local_python_runtime",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    _fake_py_cc_toolchain(
        name = "_local_py_cc_toolchain_3_12",
        marker = "forwarded",
        python_version = "3.12",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    _fake_py_cc_toolchain(
        name = "_local_py_cc_toolchain_3_13",
        marker = "snapshot",
        python_version = "3.13",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    _fake_py_cc_toolchain(
        name = "_local_py_cc_toolchain_3_11",
        marker = "mismatched",
        python_version = "3.11",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    _fake_py_cc_toolchain(
        name = "_pbs_py_cc_toolchain",
        marker = "fallback",
        python_version = "3.12",
        testonly = True,
        visibility = ["//visibility:private"],
    )

    local_py_cc_toolchain(
        name = "_local_py_cc_toolchain_forwarding",
        actual = ":_local_py_cc_toolchain_3_12",
        python_version = "3.12",
        runtime_name = "local_python",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    local_py_cc_toolchain(
        name = "_local_py_cc_toolchain_missing",
        python_version = "3.12",
        runtime_name = "local_python",
        tags = ["manual"],
        testonly = True,
        visibility = ["//visibility:private"],
    )
    local_py_cc_toolchain(
        name = "_local_py_cc_toolchain_mismatch",
        actual = ":_local_py_cc_toolchain_3_11",
        python_version = "3.12",
        runtime_name = "local_python",
        tags = ["manual"],
        testonly = True,
        visibility = ["//visibility:private"],
    )

    native.toolchain(
        name = "_local_python_runtime_registration",
        testonly = True,
        toolchain = ":_local_python_runtime",
        toolchain_type = _PYTHON_TOOLCHAIN,
        visibility = ["//visibility:private"],
    )
    native.toolchain(
        name = "_local_python_cc_registration",
        testonly = True,
        toolchain = ":_local_py_cc_toolchain_missing",
        toolchain_type = _PYTHON_CC_TOOLCHAIN,
        visibility = ["//visibility:private"],
    )
    native.toolchain(
        name = "_local_python_cc_forwarding_registration",
        testonly = True,
        toolchain = ":_local_py_cc_toolchain_forwarding",
        toolchain_type = _PYTHON_CC_TOOLCHAIN,
        visibility = ["//visibility:private"],
    )
    native.toolchain(
        name = "_pbs_python_cc_registration",
        testonly = True,
        toolchain = ":_pbs_py_cc_toolchain",
        toolchain_type = _PYTHON_CC_TOOLCHAIN,
        visibility = ["//visibility:private"],
    )

    _python_runtime_consumer(
        name = "_local_python_runtime_consumer",
        testonly = True,
        visibility = ["//visibility:private"],
    )
    _python_cc_consumer(
        name = "_local_python_cc_consumer",
        testonly = True,
        visibility = ["//visibility:private"],
    )

    _forwarding_test(
        name = "local_py_cc_toolchain_forwarding_test",
        target_under_test = ":_local_py_cc_toolchain_forwarding",
    )
    _runtime_only_test(
        name = "local_py_cc_toolchain_lazy_resolution_test",
        target_under_test = ":_local_python_runtime_consumer",
    )
    _cc_selection_test(
        name = "local_py_cc_toolchain_selection_test",
        target_under_test = ":_local_python_cc_consumer",
    )
    _failure_test(
        name = "local_py_cc_toolchain_missing_test",
        expected_error = "Local Python runtime 'local_python' has no C toolchain",
        target_under_test = ":_local_py_cc_toolchain_missing",
    )
    _failure_test(
        name = "local_py_cc_toolchain_mismatch_test",
        expected_error = "Local Python runtime 'local_python' requires C toolchain version 3.12",
        target_under_test = ":_local_py_cc_toolchain_mismatch",
    )
