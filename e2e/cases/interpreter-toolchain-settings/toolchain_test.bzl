"""Checks selected Python runtime and exec-tools toolchains."""

_RUNTIME_TOOLCHAIN = "@bazel_tools//tools/python:toolchain_type"
_EXEC_TOOLS_TOOLCHAIN = "@rules_python//python:exec_tools_toolchain_type"

def _interpreter_toolchain_check_impl(ctx):
    runtime = ctx.toolchains[_RUNTIME_TOOLCHAIN].py3_runtime
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
    return []

interpreter_toolchain_check = rule(
    implementation = _interpreter_toolchain_check_impl,
    attrs = {
        "expected_interpreter": attr.label(allow_single_file = True, mandatory = True),
        "python_version": attr.string(mandatory = True),
    },
    toolchains = [_RUNTIME_TOOLCHAIN],
)

def _exec_toolchain_check_impl(ctx):
    exec_tools = ctx.toolchains[_EXEC_TOOLS_TOOLCHAIN].exec_tools
    if exec_tools.exec_interpreter == None:
        fail("PBS exec toolchain has no interpreter")
    if exec_tools.exec_runtime == None:
        fail("PBS exec toolchain has no runtime")
    if exec_tools.exec_runtime.interpreter != ctx.file.expected_interpreter:
        fail(
            "expected PBS exec runtime {}, got {}".format(
                ctx.file.expected_interpreter,
                exec_tools.exec_runtime.interpreter,
            ),
        )

    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.run(
        arguments = [
            "-c",
            "import json, pathlib, sys; pathlib.Path(sys.argv[1]).write_text(json.dumps(sys.version_info[:2]))",
            output.path,
        ],
        executable = exec_tools.exec_interpreter[DefaultInfo].files_to_run,
        mnemonic = "ExecInterpreterSmoke",
        outputs = [output],
    )
    return [DefaultInfo(files = depset([output]))]

exec_toolchain_check = rule(
    implementation = _exec_toolchain_check_impl,
    attrs = {
        "expected_interpreter": attr.label(allow_single_file = True, mandatory = True),
    },
    toolchains = [_EXEC_TOOLS_TOOLCHAIN],
)
