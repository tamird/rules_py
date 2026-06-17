"""Analysis tests for py_unpacked_wheel metadata validation."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(":py_unpacked_wheel.bzl", "py_unpacked_wheel")

def _scripts_metadata_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = [action for action in target.actions if action.mnemonic == "PyUnpackedWheel"]
    asserts.equals(env, 1, len(actions))
    if actions:
        metadata_args = [
            actions[0].argv[index + 1]
            for index in range(len(actions[0].argv) - 1)
            if actions[0].argv[index] == "--expected-metadata"
        ]
        asserts.equals(env, 1, len(metadata_args))
        if metadata_args:
            expected = json.decode(metadata_args[0])
            asserts.equals(
                env,
                ctx.attr.scripts_known,
                "console_scripts" in expected,
            )
            if ctx.attr.scripts_known:
                asserts.equals(env, [], expected.get("console_scripts"))
    return analysistest.end(env)

_scripts_metadata_test = analysistest.make(
    _scripts_metadata_test_impl,
    attrs = {"scripts_known": attr.bool(mandatory = True)},
)

def py_unpacked_wheel_test_suite():
    write_file(
        name = "_py_unpacked_wheel_fixture_file",
        out = "py_unpacked_wheel_fixture.whl",
        content = [""],
        tags = ["manual"],
    )
    py_unpacked_wheel(
        name = "_py_unpacked_wheel_empty_scripts_fixture",
        src = ":_py_unpacked_wheel_fixture_file",
        console_scripts_known = True,
        tags = ["manual"],
    )
    _scripts_metadata_test(
        name = "py_unpacked_wheel_empty_scripts_test",
        scripts_known = True,
        target_under_test = ":_py_unpacked_wheel_empty_scripts_fixture",
    )
    py_unpacked_wheel(
        name = "_py_unpacked_wheel_unknown_scripts_fixture",
        src = ":_py_unpacked_wheel_fixture_file",
        tags = ["manual"],
        top_levels = ["fixture"],
    )
    _scripts_metadata_test(
        name = "py_unpacked_wheel_unknown_scripts_test",
        scripts_known = False,
        target_under_test = ":_py_unpacked_wheel_unknown_scripts_fixture",
    )
