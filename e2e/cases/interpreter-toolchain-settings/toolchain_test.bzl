"""Analysis checks for the selected Python toolchains."""

_RUNTIME_TOOLCHAIN = "@bazel_tools//tools/python:toolchain_type"
_PY_CC_TOOLCHAIN = "@rules_python//python/cc:toolchain_type"

def _interpreter_toolchain_check_impl(ctx):
    runtime = ctx.toolchains[_RUNTIME_TOOLCHAIN].py3_runtime
    toolchain = ctx.toolchains[_PY_CC_TOOLCHAIN]
    cc_toolchain = toolchain.py_cc_toolchain

    if runtime == None:
        fail("Python {} runtime toolchain was not resolved".format(ctx.attr.python_version))
    if runtime.interpreter == None:
        fail("Python {} runtime toolchain is not hermetic".format(ctx.attr.python_version))
    if runtime.interpreter != ctx.file.expected_interpreter:
        fail(
            "expected Python {} PBS interpreter {}, got {}".format(
                ctx.attr.python_version,
                ctx.file.expected_interpreter,
                runtime.interpreter,
            ),
        )

    version_info = runtime.interpreter_version_info
    actual = "{}.{}".format(version_info.major, version_info.minor)
    if actual != ctx.attr.python_version:
        fail("expected Python {} runtime, got {}".format(ctx.attr.python_version, actual))
    if toolchain.toolchain_label != ctx.attr.expected_cc_toolchain.label:
        fail("expected Python C toolchain {}, got {}".format(ctx.attr.expected_cc_toolchain.label, toolchain.toolchain_label))
    if cc_toolchain.python_version != ctx.attr.python_version:
        fail("expected Python {} C toolchain, got {}".format(ctx.attr.python_version, cc_toolchain.python_version))
    if ctx.attr.expect_abi3 and cc_toolchain.headers_abi3 == None:
        fail("Python {} C toolchain has no ABI3 headers".format(ctx.attr.python_version))
    if not ctx.attr.expect_abi3 and cc_toolchain.headers_abi3 != None:
        fail("Python {} free-threaded C toolchain unexpectedly has ABI3 headers".format(ctx.attr.python_version))
    if cc_toolchain.libs == None:
        fail("Python {} C toolchain has no libraries".format(ctx.attr.python_version))
    return []

interpreter_toolchain_check = rule(
    implementation = _interpreter_toolchain_check_impl,
    attrs = {
        "expect_abi3": attr.bool(mandatory = True),
        "expected_cc_toolchain": attr.label(mandatory = True),
        "expected_interpreter": attr.label(allow_single_file = True, mandatory = True),
        "python_version": attr.string(mandatory = True),
    },
    toolchains = [
        _RUNTIME_TOOLCHAIN,
        _PY_CC_TOOLCHAIN,
    ],
)
