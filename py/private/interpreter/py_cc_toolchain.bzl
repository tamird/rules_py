"""Compatibility wrapper for rules_python's Python C toolchain."""

load("@rules_python//python:features.bzl", "features")
load("@rules_python//python/cc:py_cc_toolchain.bzl", _py_cc_toolchain = "py_cc_toolchain")

def py_cc_toolchain(name, headers, headers_abi3, libs, python_version):
    """Declare a C toolchain across supported rules_python versions."""

    kwargs = {
        "name": name,
        "headers": headers,
        "libs": libs,
        "python_version": python_version,
    }

    # headers_abi3 was added in rules_python 1.7; rules_py supports 1.0:
    # https://github.com/bazel-contrib/rules_python/blob/1.7.0/python/features.bzl#L23-L30
    if getattr(features, "headers_abi3", False):
        kwargs["headers_abi3"] = headers_abi3
    _py_cc_toolchain(**kwargs)

def _local_py_cc_toolchain_impl(ctx):
    if ctx.attr.actual == None:
        fail("Local Python runtime '{}' has no C toolchain. Set py_cc_toolchain on interpreters.local() before building native extensions.".format(ctx.attr.runtime_name))

    toolchain = ctx.attr.actual[platform_common.ToolchainInfo]
    if not hasattr(toolchain, "py_cc_toolchain"):
        fail("Local Python C toolchain '{}' does not provide py_cc_toolchain".format(ctx.attr.actual.label))

    actual_version = toolchain.py_cc_toolchain.python_version
    if actual_version != ctx.attr.python_version:
        fail("Local Python runtime '{}' requires C toolchain version {}, but '{}' provides {}".format(
            ctx.attr.runtime_name,
            ctx.attr.python_version,
            ctx.attr.actual.label,
            actual_version,
        ))
    return [toolchain]

local_py_cc_toolchain = rule(
    implementation = _local_py_cc_toolchain_impl,
    attrs = {
        "actual": attr.label(providers = [platform_common.ToolchainInfo]),
        "python_version": attr.string(),
        "runtime_name": attr.string(mandatory = True),
    },
    provides = [platform_common.ToolchainInfo],
)
