"""Tests for permissive wheel-collision precedence."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_python//python:defs.bzl", "PyInfo")
load("//py:defs.bzl", "py_binary", "py_library", "py_test")
load("//py/private:providers.bzl", "PyWheelsInfo")
load("//py/private/toolchain:types.bzl", "PY_TOOLCHAIN")

def _wheel_impl(ctx):
    py_runtime = ctx.toolchains[PY_TOOLCHAIN].py3_runtime
    install_tree = ctx.actions.declare_directory(ctx.label.name + ".install")
    major = py_runtime.interpreter_version_info.major
    minor = py_runtime.interpreter_version_info.minor
    command = """
set -eu
site="$1/lib/python$2.$3/site-packages"
mkdir -p "$site/collision_namespace"
printf 'VALUE = %s\n' "$4" > "$site/collision_namespace/shared.py"
printf 'VALUE = %s\n\ndef main():\n    print(VALUE)\n' "$4" > "$site/collision_namespace/$5.py"
metadata="$site/$7"
mkdir -p "$metadata"
printf 'Metadata-Version: 2.1\nName: collision-%s\nVersion: 1.0\n' "$5" > "$metadata/METADATA"
"""
    metadata_name = ctx.attr.metadata_name or "collision_{}-1.0.dist-info".format(ctx.attr.value)
    top_levels = (
        "collision_namespace",
        metadata_name,
    )
    directory_top_levels = top_levels
    console_scripts = ()
    if ctx.attr.ordinary_kind == "directory":
        command += """
mkdir -p "$site/collision_order"
printf 'VALUE = %s\n' "$4" > "$site/collision_order/__init__.py"
printf 'VALUE = %s\n' "$4" > "$site/collision_order/shared.py"
printf 'VALUE = %s\n' "$4" > "$site/collision_order/$5.py"
"""
        top_levels = ("collision_order",) + top_levels
        directory_top_levels = top_levels
        console_scripts = ("collision-order=collision_namespace.{}:main".format(ctx.attr.value),)
    elif ctx.attr.ordinary_kind == "file":
        command += """
printf 'VALUE = %s\n' "$4" > "$site/collision_order"
"""
        top_levels = ("collision_order",) + top_levels
        console_scripts = ("collision-order=collision_namespace.{}:main".format(ctx.attr.value),)
    if ctx.attr.root_pth_name:
        if ctx.attr.root_pth_directory:
            command += """
mkdir -p "$site/$6.pth"
printf '%s\n' "$5" > "$site/$6.pth/$5.txt"
"""
            directory_top_levels += (ctx.attr.root_pth_name + ".pth",)
        else:
            command += """
printf 'import sys; sys.path.append("rules_py_pth_%s")\n' "$5" > "$site/$6.pth"
"""
        top_levels += (ctx.attr.root_pth_name + ".pth",)
    if not ctx.attr.layout_typed:
        directory_top_levels = ()
    ctx.actions.run_shell(
        outputs = [install_tree],
        command = command,
        arguments = [
            install_tree.path,
            str(major),
            str(minor),
            json.encode(ctx.attr.value),
            ctx.attr.value,
            ctx.attr.root_pth_name,
            metadata_name,
        ],
    )
    site_packages = "/".join([
        segment
        for segment in [
            ctx.label.repo_name or ctx.workspace_name,
            ctx.label.package,
            install_tree.basename,
        ]
        if segment
    ] + ["lib/python{}.{}/site-packages".format(major, minor)])
    wheel = struct(
        top_levels = top_levels,
        directory_top_levels = directory_top_levels,
        layout_complete = ctx.attr.layout_complete,
        namespace_top_levels = ("collision_namespace",),
        namespace_entries = (
            "collision_namespace/shared.py",
            "collision_namespace/{}.py".format(ctx.attr.value),
        ),
        namespace_dirs = (),
        regular_roots = (),
        site_packages_rfpath = site_packages,
        console_scripts = console_scripts,
        install_tree = install_tree,
    )
    return [
        DefaultInfo(
            files = depset([install_tree]),
            runfiles = ctx.runfiles(files = [install_tree]),
        ),
        PyInfo(
            imports = depset([site_packages]),
            transitive_sources = depset([install_tree]),
            has_py2_only_sources = False,
            has_py3_only_sources = True,
            uses_shared_libraries = False,
        ),
        PyWheelsInfo(wheels = depset([wheel])),
    ]

_wheel = rule(
    implementation = _wheel_impl,
    attrs = {
        "layout_complete": attr.bool(default = True),
        "layout_typed": attr.bool(default = True),
        "metadata_name": attr.string(),
        "ordinary_kind": attr.string(
            mandatory = True,
            values = ["directory", "file", "none"],
        ),
        "root_pth_directory": attr.bool(),
        "root_pth_name": attr.string(),
        "value": attr.string(mandatory = True),
    },
    toolchains = [PY_TOOLCHAIN],
)

def _collision_error_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_error)
    return analysistest.end(env)

_collision_error_test = analysistest.make(
    _collision_error_test_impl,
    attrs = {
        "expected_error": attr.string(mandatory = True),
    },
    expect_failure = True,
)

def collision_order_test_suite():
    _wheel(
        name = "_collision_first",
        ordinary_kind = "directory",
        value = "first",
        tags = ["manual"],
    )
    _wheel(
        name = "_collision_second",
        ordinary_kind = "directory",
        value = "second",
        tags = ["manual"],
    )
    py_library(
        name = "_collision_branch",
        deps = [":_collision_first"],
        tags = ["manual"],
    )
    py_test(
        name = "later_direct_claimant_wins_test",
        srcs = ["test_collision_order.py"],
        args = ["second"],
        main = "test_collision_order.py",
        package_collisions = "ignore",
        deps = [
            ":_collision_branch",
            ":_collision_second",
        ],
    )
    py_test(
        name = "later_transitive_claimant_wins_test",
        srcs = ["test_collision_order.py"],
        args = ["first"],
        main = "test_collision_order.py",
        package_collisions = "ignore",
        deps = [
            ":_collision_second",
            ":_collision_branch",
        ],
    )
    py_binary(
        name = "_collision_error_binary",
        srcs = ["test_collision_order.py"],
        main = "test_collision_order.py",
        package_collisions = "error",
        tags = ["manual"],
        deps = [
            ":_collision_first",
            ":_collision_second",
        ],
    )
    _collision_error_test(
        name = "collision_error_test",
        expected_error = "top-level `collision_order`",
        target_under_test = ":_collision_error_binary",
    )
    _wheel(
        name = "_collision_untyped",
        layout_typed = False,
        ordinary_kind = "directory",
        value = "untyped",
        tags = ["manual"],
    )
    py_binary(
        name = "_untyped_collision_error_binary",
        srcs = ["test_collision_order.py"],
        main = "test_collision_order.py",
        package_collisions = "ignore",
        tags = ["manual"],
        deps = [
            ":_collision_first",
            ":_collision_untyped",
        ],
    )
    _collision_error_test(
        name = "untyped_collision_error_test",
        expected_error = "do not declare a nonempty, complete `directory_top_levels`",
        target_under_test = ":_untyped_collision_error_binary",
    )

    _wheel(
        name = "_reset_before",
        ordinary_kind = "directory",
        value = "reset_before",
        tags = ["manual"],
    )
    _wheel(
        name = "_reset_file",
        ordinary_kind = "file",
        value = "reset_file",
        tags = ["manual"],
    )
    _wheel(
        name = "_reset_after",
        ordinary_kind = "directory",
        value = "reset_after",
        tags = ["manual"],
    )
    _wheel(
        name = "_reset_final",
        ordinary_kind = "directory",
        value = "reset_final",
        tags = ["manual"],
    )
    py_test(
        name = "collision_type_reset_test",
        srcs = ["test_collision_type_reset.py"],
        main = "test_collision_type_reset.py",
        package_collisions = "ignore",
        deps = [
            ":_reset_before",
            ":_reset_file",
            ":_reset_after",
            ":_reset_final",
        ],
    )

    _wheel(
        name = "_metadata_collision_second",
        metadata_name = "collision_first-1.0.dist-info",
        ordinary_kind = "none",
        tags = ["manual"],
        value = "metadata_second",
    )
    py_binary(
        name = "_metadata_collision_error_binary",
        srcs = ["test_namespace_fallback.py"],
        main = "test_namespace_fallback.py",
        package_collisions = "ignore",
        tags = ["manual"],
        deps = [
            ":_collision_first",
            ":_metadata_collision_second",
        ],
    )
    _collision_error_test(
        name = "metadata_collision_error_test",
        expected_error = "distribution metadata entry `collision_first-1.0.dist-info` is provided by both",
        target_under_test = ":_metadata_collision_error_binary",
    )

    _wheel(
        name = "_collision_incomplete",
        layout_complete = False,
        ordinary_kind = "directory",
        tags = ["manual"],
        value = "incomplete",
    )
    py_binary(
        name = "_incomplete_collision_error_binary",
        srcs = ["test_collision_order.py"],
        main = "test_collision_order.py",
        package_collisions = "error",
        tags = ["manual"],
        deps = [
            ":_collision_first",
            ":_collision_incomplete",
        ],
    )
    _collision_error_test(
        name = "incomplete_collision_error_test",
        expected_error = "top-level `collision_order`",
        target_under_test = ":_incomplete_collision_error_binary",
    )

    _wheel(
        name = "_pth_collision_complete",
        ordinary_kind = "none",
        root_pth_name = "collision_marker",
        tags = ["manual"],
        value = "complete",
    )
    _wheel(
        name = "_pth_collision_incomplete",
        layout_complete = False,
        layout_typed = False,
        ordinary_kind = "none",
        root_pth_name = "collision_marker",
        tags = ["manual"],
        value = "pth_incomplete",
    )
    py_binary(
        name = "_incomplete_pth_collision_error_binary",
        srcs = ["test_namespace_fallback.py"],
        main = "test_namespace_fallback.py",
        package_collisions = "ignore",
        tags = ["manual"],
        deps = [
            ":_pth_collision_complete",
            ":_pth_collision_incomplete",
        ],
    )
    _collision_error_test(
        name = "incomplete_pth_collision_error_test",
        expected_error = "root `.pth` file `collision_marker.pth` collides",
        target_under_test = ":_incomplete_pth_collision_error_binary",
    )

    _wheel(
        name = "_pth_runtime_incomplete",
        layout_complete = False,
        ordinary_kind = "none",
        root_pth_name = "incomplete_marker",
        tags = ["manual"],
        value = "incomplete",
    )
    py_test(
        name = "incomplete_layout_pth_test",
        srcs = ["test_incomplete_layout_pth.py"],
        isolated = False,
        main = "test_incomplete_layout_pth.py",
        package_collisions = "ignore",
        deps = [
            ":_pth_collision_complete",
            ":_pth_runtime_incomplete",
        ],
    )

    _wheel(
        name = "_pth_directory_first",
        ordinary_kind = "none",
        root_pth_directory = True,
        root_pth_name = "directory_marker",
        tags = ["manual"],
        value = "first",
    )
    _wheel(
        name = "_pth_directory_second",
        layout_complete = False,
        ordinary_kind = "none",
        root_pth_directory = True,
        root_pth_name = "directory_marker",
        tags = ["manual"],
        value = "second",
    )
    py_test(
        name = "pth_directory_overlay_test",
        srcs = ["test_pth_directory_overlay.py"],
        main = "test_pth_directory_overlay.py",
        package_collisions = "ignore",
        deps = [
            ":_pth_directory_first",
            ":_pth_directory_second",
        ],
    )

    _wheel(
        name = "_namespace_first",
        ordinary_kind = "none",
        value = "first",
        tags = ["manual"],
    )
    _wheel(
        name = "_namespace_second",
        ordinary_kind = "none",
        value = "second",
        tags = ["manual"],
    )
    py_test(
        name = "namespace_fallback_order_test",
        srcs = ["test_namespace_fallback.py"],
        args = [
            "second",
            "first",
        ],
        main = "test_namespace_fallback.py",
        package_collisions = "ignore",
        deps = [
            ":_namespace_first",
            ":_namespace_second",
        ],
    )
    py_binary(
        name = "_namespace_collision_error_binary",
        srcs = ["test_namespace_fallback.py"],
        main = "test_namespace_fallback.py",
        package_collisions = "error",
        tags = ["manual"],
        deps = [
            ":_namespace_first",
            ":_namespace_second",
        ],
    )
    _collision_error_test(
        name = "namespace_collision_error_test",
        expected_error = "namespace entry `collision_namespace/shared.py`",
        target_under_test = ":_namespace_collision_error_binary",
    )
