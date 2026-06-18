"""Repository rules for Python interpreter toolchains.

Includes rules for downloading PBS interpreters and registering local interpreters.
"""

load("@bazel_features//:features.bzl", features = "bazel_features")
load(":exclude_feature.bzl", "INTERPRETER_FEATURES")

_PYTHON_VERSION_FLAG = "@aspect_rules_py//py/private/interpreter:python_version"
_RPY_VERSION_FLAG = "@rules_python//python/config_settings:python_version"
_FREETHREADING_FLAG = "@aspect_rules_py//py/private/interpreter:freethreaded"
_EXCLUDE_FEATURE_FLAG = "@aspect_rules_py//py/private/interpreter:exclude_feature"

def _python_interpreter_impl(rctx):
    """Downloads and extracts a Python interpreter from PBS."""
    url = rctx.attr.url
    platform = rctx.attr.platform

    python_version = rctx.attr.python_version
    sha256 = rctx.attr.sha256
    strip_prefix = rctx.attr.strip_prefix
    rctx.download_and_extract(
        url = [url],
        sha256 = sha256,
        stripPrefix = strip_prefix,
    )

    # Determine the Python binary path
    is_macos = "apple-darwin" in platform
    is_windows = "windows" in platform
    python_bin = "python.exe" if is_windows else "bin/python3"
    version_parts = python_version.split(".")
    major = version_parts[0]
    minor = version_parts[1]
    micro = version_parts[2] if len(version_parts) > 2 else "0"

    if is_macos and rctx.os.name.lower().startswith("mac os"):
        # Match rules_python's PBS repository setup so extensions link to the
        # relocatable dylib rather than its build-host install name:
        # https://github.com/bazel-contrib/rules_python/blob/1.7.0/python/private/python_repository.bzl#L111-L124
        suffix = "t" if rctx.attr.freethreaded else ""
        dylib = "libpython{}.{}{}.dylib".format(major, minor, suffix)
        install_name_tool = rctx.which("install_name_tool")
        if not install_name_tool:
            fail("install_name_tool is required to register the macOS Python C toolchain")
        result = rctx.execute([
            install_name_tool,
            "-id",
            "@rpath/{}".format(dylib),
            "lib/{}".format(dylib),
        ])
        if result.return_code:
            fail("install_name_tool failed: {}".format(result.stderr))

    # Delete terminfo symlink loops on newer PBS releases (linux only)
    if "linux" in platform:
        rctx.delete("share/terminfo")

    rctx.file("BUILD.bazel", content = _build_file_content(
        freethreaded = rctx.attr.freethreaded,
        major = major,
        minor = minor,
        micro = micro,
        platform = platform,
        python_bin = python_bin,
    ))

    if not features.external_deps.extension_metadata_has_reproducible:
        return None

    # The macOS archive is rewritten on macOS hosts but not cross-build hosts,
    # so its repository output is not host-independent.
    return rctx.repo_metadata(reproducible = not is_macos)

def _feature_filegroups(major, minor, is_windows):
    """Generate per-feature filegroup targets and config_settings.

    Returns a tuple of (feature_targets_str, all_feature_exclude_patterns).
    The exclude patterns are used to carve out feature files from the core filegroup.
    """
    if is_windows:
        return "", []

    lines = []
    all_excludes = []

    for feature_name, feature_info in INTERPRETER_FEATURES.items():
        patterns = [
            p.format(major = major, minor = minor)
            for p in feature_info["include"]
        ]
        all_excludes.extend(patterns)

        lines.append("""\
config_setting(
    name = "_exclude_{feature}",
    flag_values = {{"{flag}": "{feature}"}},
)
""".format(feature = feature_name, flag = _EXCLUDE_FEATURE_FLAG))

        lines.append("""\
filegroup(
    name = "_feature_{feature}",
    srcs = glob({patterns}, allow_empty = True),
)
""".format(feature = feature_name, patterns = repr(patterns)))

    return "\n".join(lines), all_excludes

def _build_file_content(major, minor, micro, platform, python_bin, freethreaded):
    """Generate the full BUILD.bazel content for an interpreter repo."""

    is_windows = "windows" in platform
    feature_targets, feature_excludes = _feature_filegroups(major, minor, is_windows)

    if is_windows:
        core_include = '["**/*.py", "**/*.pyd", "**/*.dll", "**/*.exe", "include/**", "Lib/**"]'
        core_exclude = '["Lib/**/test/**", "Lib/**/tests/**", "**/__pycache__/*.pyc*"]'
        suffix = "t" if freethreaded else ""
        python_libs = [
            "python3{}.dll".format(suffix),
            "python{}{}{}.dll".format(major, minor, suffix),
            "libs/python3{}.lib".format(suffix),
            "libs/python{}{}{}.lib".format(major, minor, suffix),
        ]
        interface_targets = """
cc_import(
    name = "_python_interface",
    interface_library = "libs/python{major}{minor}{suffix}.lib",
    system_provided = True,
)

cc_import(
    name = "_python_abi3_interface",
    interface_library = "libs/python3{suffix}.lib",
    system_provided = True,
)
""".format(major = major, minor = minor, suffix = suffix)
        full_header_deps = '[":python_headers_abi3", ":_python_interface"]'
        abi3_header_deps = '[":_python_abi3_interface"]'
    else:
        core_include = '["bin/**", "lib/**"]'
        core_exclude = repr(
            [
                "lib/**/*.a",
                "lib/python{}.{}/**/test/**".format(major, minor),
                "lib/python{}.{}/**/tests/**".format(major, minor),
                "**/__pycache__/*.pyc*",
            ] +
            feature_excludes,
        )
        suffix = "t" if freethreaded else ""
        if "apple-darwin" in platform:
            python_libs = ["lib/libpython{}.{}{}.dylib".format(major, minor, suffix)]
        else:
            python_libs = [
                "lib/libpython{}.{}{}.so".format(major, minor, suffix),
                "lib/libpython{}.{}{}.so.1.0".format(major, minor, suffix),
            ]
        interface_targets = ""
        full_header_deps = '[":python_headers_abi3"]'
        abi3_header_deps = "[]"

    python_includes = [
        "include",
        "include/python{}.{}{}".format(major, minor, suffix),
    ]
    if not freethreaded:
        python_includes.append("include/python{}.{}m".format(major, minor))

    # Build the select() expressions for optional features
    feature_selects = ""
    if not is_windows:
        for feature_name in INTERPRETER_FEATURES.keys():
            feature_selects += """\
    + select({{
        ":_exclude_{feature}": [],
        "//conditions:default": [":_feature_{feature}"],
    }})
""".format(feature = feature_name)

    return """\
load("@rules_python//python:py_runtime.bzl", "py_runtime")
load("@rules_python//python:py_runtime_pair.bzl", "py_runtime_pair")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@aspect_rules_py//py/private/exec_tools:defs.bzl", "py_exec_tools_toolchain")
load("@aspect_rules_py//py/private/interpreter:py_cc_toolchain.bzl", "py_cc_toolchain")

package(default_visibility = ["//visibility:public"])

# --- Optional interpreter features ---

{feature_targets}

# --- Core + optional filegroups ---

filegroup(
    name = "_core",
    srcs = glob(
        include = {core_include},
        exclude = {core_exclude},
    ),
)

filegroup(
    name = "files",
    srcs = [":_core"]
{feature_selects}    ,
)

py_runtime(
    name = "py3_runtime",
    files = [":files"],
    interpreter = "{python_bin}",
    interpreter_version_info = {{
        "major": "{major}",
        "minor": "{minor}",
        "micro": "{micro}",
    }},
    python_version = "PY3",
)

py_runtime_pair(
    name = "runtime_pair",
    py2_runtime = None,
    py3_runtime = ":py3_runtime",
)

{interface_targets}

filegroup(
    name = "_python_headers",
    srcs = glob(["include/**/*.h"]),
)

cc_library(
    name = "python_headers_abi3",
    hdrs = [":_python_headers"],
    includes = {python_includes},
    deps = {abi3_header_deps},
)

cc_library(
    name = "python_headers",
    deps = {full_header_deps},
)

cc_library(
    name = "libpython",
    hdrs = [":_python_headers"],
    srcs = {python_libs},
)

py_cc_toolchain(
    name = "py_cc_toolchain",
    headers = ":python_headers",
    headers_abi3 = ":python_headers_abi3",
    libs = ":libpython",
    python_version = "{major}.{minor}",
)

py_exec_tools_toolchain(
    name = "exec_tools_toolchain",
)
""".format(
        python_bin = python_bin,
        major = major,
        minor = minor,
        micro = micro,
        feature_targets = feature_targets,
        feature_selects = feature_selects,
        interface_targets = interface_targets,
        full_header_deps = full_header_deps,
        abi3_header_deps = abi3_header_deps,
        python_libs = repr(python_libs),
        python_includes = repr(python_includes),
        core_include = core_include,
        core_exclude = core_exclude,
    )

python_interpreter = repository_rule(
    implementation = _python_interpreter_impl,
    attrs = {
        "freethreaded": attr.bool(default = False),
        "platform": attr.string(mandatory = True),
        "python_version": attr.string(default = ""),
        "sha256": attr.string(default = ""),
        "strip_prefix": attr.string(default = "python"),
        "url": attr.string(default = ""),
    },
)

def _platform_setting_name(flag, value):
    """Generate a unique config_setting name for a flag/value pair."""

    # Extract the last path component of the flag label as a readable prefix,
    # e.g. "@aspect_rules_py//uv/private/constraints/platform:platform_libc"
    # -> "platform_libc_glibc"
    name = flag.split(":")[-1] if ":" in flag else flag.split("/")[-1]
    return "{}_is_{}".format(name, value)

def _version_setting_name(major_minor):
    """Generate config_setting name for a Python version."""
    return "python_version_is_" + major_minor.replace(".", "_")

def _freethreaded_setting_name(value):
    """Generate config_setting name for the freethreaded flag."""
    return "freethreaded_is_" + ("true" if value else "false")

def _python_toolchains_impl(rctx):
    """Creates toolchain() registrations pointing to interpreter repos."""
    content = [
        'load("@bazel_skylib//lib:selects.bzl", "selects")',
        'load("@aspect_rules_py//py/private/interpreter:current_py_toolchain.bzl", "current_py_toolchain")',
        'load("@aspect_rules_py//py/private/interpreter:py_cc_toolchain.bzl", "local_py_cc_toolchain")',
        'package(default_visibility = ["//visibility:public"])',
    ]

    # First pass: collect all unique flag/value pairs and version/freethreaded
    # combos so we generate each config_setting exactly once.
    seen_settings = {}  # name -> (flag, value)
    seen_versions = {}  # major_minor -> True
    seen_freethreaded = {}  # bool -> True
    toolchain_infos = []

    for entry in rctx.attr.toolchains:
        info = json.decode(entry)
        platform_settings = info.get("platform_target_settings", {})
        setting_names = []
        for flag, value in platform_settings.items():
            name = _platform_setting_name(flag, value)
            if name not in seen_settings:
                seen_settings[name] = (flag, value)
            setting_names.append(name)

        # A local repository owns these settings because it also records
        # whether its interpreter exists on this machine.
        if not info.get("is_local", False):
            python_version = info["python_version"]
            seen_versions[python_version] = True
            seen_freethreaded[info.get("freethreaded", False)] = True

        toolchain_infos.append((info, setting_names))

    # Emit hub-local version config_settings so toolchain resolution doesn't
    # need to fetch individual interpreter repos.
    for major_minor in seen_versions.keys():
        group_name = _version_setting_name(major_minor)
        content.append("""
config_setting(
    name = "_{group}_our_major_minor",
    flag_values = {{"{our_flag}": "{major_minor}"}},
)

config_setting(
    name = "_{group}_rpy_major_minor",
    flag_values = {{"{rpy_flag}": "{major_minor}"}},
)

selects.config_setting_group(
    name = "{group}",
    match_any = [
        ":_{group}_our_major_minor",
        ":_{group}_rpy_major_minor",
    ],
)
""".format(
            group = group_name,
            major_minor = major_minor,
            our_flag = _PYTHON_VERSION_FLAG,
            rpy_flag = _RPY_VERSION_FLAG,
        ))

    # Emit hub-local freethreaded config_settings
    for value in seen_freethreaded.keys():
        name = _freethreaded_setting_name(value)
        content.append("""
config_setting(
    name = "{name}",
    flag_values = {{"{flag}": "{value}"}},
)
""".format(
            name = name,
            flag = _FREETHREADING_FLAG,
            value = "true" if value else "false",
        ))

    # Emit config_settings for platform target settings
    for name, (flag, value) in seen_settings.items():
        content.append("""
config_setting(
    name = "{name}",
    flag_values = {{"{flag}": "{value}"}},
)
""".format(name = name, flag = flag, value = value))

    # Second pass: emit toolchain() registrations
    for info, platform_setting_names in toolchain_infos:
        extra_config_settings = info.get("config_settings", [])
        extra_target_compatible = info.get("target_compatible_with", [])
        extra_exec_compatible = info.get("exec_compatible_with", [])

        is_local = info.get("is_local", False)
        if is_local:
            version_setting = "@{repo}//:is_matching_python_version".format(repo = info["repo"])
            freethreaded_setting = "@{repo}//:is_matching_freethreaded".format(repo = info["repo"])
        else:
            version_setting = ":" + _version_setting_name(info["python_version"])
            freethreaded_setting = ":" + _freethreaded_setting_name(info.get("freethreaded", False))

        target_settings = [
            version_setting,
            freethreaded_setting,
        ] + [":" + name for name in platform_setting_names] + extra_config_settings

        target_compatible_with = info["compatible_with"] + extra_target_compatible
        exec_compatible_with = info["compatible_with"] + extra_exec_compatible

        # Bazel expands :all registrations in lexicographic name order:
        # https://bazel.build/extending/toolchains#registering_and_building_with_toolchains
        # Prefixing every C registration before the interpreter name preserves
        # the runtime registrations' existing build-flavor priority.
        py_cc_name = "py_cc_" + info["name"]

        if is_local:
            local_py_cc_name = "_" + py_cc_name
            actual = info.get("py_cc_toolchain", "")
            local_py_cc = """local_py_cc_toolchain(
    name = "{name}",
{actual}    python_version = "{python_version}",
    runtime_name = "{runtime_name}",
)\n\n""".format(
                name = local_py_cc_name,
                actual = '    actual = "{}",\n'.format(actual) if actual else "",
                python_version = info.get("python_version", ""),
                runtime_name = info["name"],
            )
            py_cc_target = ":" + local_py_cc_name
        else:
            local_py_cc = ""
            py_cc_target = info["py_cc_toolchain"]
        exec_target_settings = (
            "    target_settings = {},\n".format(target_settings) if is_local else ""
        )

        content.append("""
# The Python interpreter toolchain has no exec_compatible_with: the interpreter
# runs on the TARGET platform (inside the virtualenv), not on the exec host.
# Setting exec_compatible_with = platform_constraints would prevent this
# toolchain from being selected during cross-compilation (e.g. building an
# arm64 image on an amd64 host), because the exec platform (amd64) would not
# satisfy the arm64 exec constraint.  The target_compatible_with constraint is
# sufficient to pick the right interpreter for the target.
toolchain(
    name = "{name}",
    target_compatible_with = {target_compatible_with},
    target_settings = {target_settings},
    toolchain = "@{repo}//:runtime_pair",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
)

{local_py_cc}toolchain(
    name = "{py_cc_name}",
    target_compatible_with = {target_compatible_with},
    target_settings = {target_settings},
    toolchain = "{py_cc_target}",
    toolchain_type = "@rules_python//python/cc:toolchain_type",
)

# Exec tools toolchain: selected by exec platform (not target platform) so
# that build actions using the interpreter (e.g. compileall) get a runnable
# binary on the build host regardless of the target platform being built for.
toolchain(
    name = "{name}_exec_tools",
    exec_compatible_with = {exec_compatible_with},
{exec_target_settings}    toolchain = "@{repo}//:exec_tools_toolchain",
    toolchain_type = "@aspect_rules_py//py/private/toolchain:exec_tools_toolchain_type",
)
""".format(
            name = info["name"],
            repo = info["repo"],
            exec_compatible_with = exec_compatible_with,
            exec_target_settings = exec_target_settings,
            target_compatible_with = target_compatible_with,
            target_settings = target_settings,
            local_py_cc = local_py_cc,
            py_cc_name = py_cc_name,
            py_cc_target = py_cc_target,
        ))

    content.append("""
exports_files(
    ["BUILD.bazel"],
    visibility = ["//visibility:public"],
)

current_py_toolchain(
    name = "current_py_toolchain",
)
""")

    rctx.file("BUILD.bazel", content = "\n".join(content))

    if not features.external_deps.extension_metadata_has_reproducible:
        return None
    return rctx.repo_metadata(reproducible = True)

python_toolchains = repository_rule(
    implementation = _python_toolchains_impl,
    attrs = {
        "toolchains": attr.string_list(),
    },
)

def _local_python_interpreter_impl(rctx):
    """Probes and registers a local (non-PBS) Python interpreter."""

    # Resolve the interpreter binary path
    interpreter_path = rctx.attr.interpreter_path
    env_var = rctx.attr.env

    if not interpreter_path and not env_var:
        fail("Either interpreter_path or env must be set")
    if interpreter_path and env_var:
        fail("Only one of interpreter_path or env may be set")

    if env_var:
        env_value = rctx.os.environ.get(env_var, "")
        if not env_value:
            _write_inactive_build(rctx, "Environment variable {} is not set".format(env_var))
            return

        # Resolve the python3 binary within the environment prefix
        is_windows = "win" in rctx.os.name.lower()
        if is_windows:
            interpreter_path = env_value + "/Scripts/python.exe"
        else:
            interpreter_path = env_value + "/bin/python3"

    # Check the interpreter exists
    path = rctx.path(interpreter_path)
    if not path.exists:
        _write_inactive_build(rctx, "Interpreter not found at {}".format(interpreter_path))
        return

    # Probe the interpreter for version info
    probe_script = rctx.attr._probe_script
    result = rctx.execute(
        [interpreter_path, rctx.path(probe_script)],
        timeout = 10,
    )
    if result.return_code != 0:
        _write_inactive_build(
            rctx,
            "Probe failed (exit {}): {}".format(result.return_code, result.stderr),
        )
        return

    probe = json.decode(result.stdout)
    major = str(probe["major"])
    minor = str(probe["minor"])
    micro = str(probe["micro"])

    # Allow explicit version override
    python_version = rctx.attr.python_version
    if python_version:
        parts = python_version.split(".")
        major = parts[0]
        minor = parts[1]
        micro = parts[2] if len(parts) > 2 else micro
    else:
        python_version = "{}.{}.{}".format(major, minor, micro)

    major_minor = "{}.{}".format(major, minor)

    rctx.file("BUILD.bazel", content = """\
load("@aspect_rules_py//py/private/exec_tools:defs.bzl", "py_exec_tools_toolchain")
load("@rules_python//python:py_runtime.bzl", "py_runtime")
load("@rules_python//python:py_runtime_pair.bzl", "py_runtime_pair")
load("@bazel_skylib//lib:selects.bzl", "selects")

package(default_visibility = ["//visibility:public"])

config_setting(
    name = "_is_our_major_minor",
    flag_values = {{
        "{our_flag}": "{major_minor}",
    }},
)

config_setting(
    name = "_is_our_major_minor_micro",
    flag_values = {{
        "{our_flag}": "{version}",
    }},
)

config_setting(
    name = "_is_rpy_major_minor",
    flag_values = {{
        "{rpy_flag}": "{major_minor}",
    }},
)

config_setting(
    name = "_is_rpy_major_minor_micro",
    flag_values = {{
        "{rpy_flag}": "{version}",
    }},
)

selects.config_setting_group(
    name = "is_matching_python_version",
    match_any = [
        ":_is_our_major_minor",
        ":_is_our_major_minor_micro",
        ":_is_rpy_major_minor",
        ":_is_rpy_major_minor_micro",
    ],
)

config_setting(
    name = "is_matching_freethreaded",
    flag_values = {{
        "{freethreaded_flag}": "false",
    }},
)

py_runtime(
    name = "py3_runtime",
    interpreter_path = "{interpreter_path}",
    interpreter_version_info = {{
        "major": "{major}",
        "minor": "{minor}",
        "micro": "{micro}",
    }},
    python_version = "PY3",
)

py_runtime_pair(
    name = "runtime_pair",
    py2_runtime = None,
    py3_runtime = ":py3_runtime",
)

py_exec_tools_toolchain(
    name = "exec_tools_toolchain",
)
""".format(
        our_flag = _PYTHON_VERSION_FLAG,
        rpy_flag = _RPY_VERSION_FLAG,
        freethreaded_flag = _FREETHREADING_FLAG,
        version = python_version,
        major_minor = major_minor,
        interpreter_path = interpreter_path,
        major = major,
        minor = minor,
        micro = micro,
    ))

def _write_inactive_build(rctx, reason):
    """Write a BUILD file for an inactive/unavailable local interpreter."""
    rctx.file("BUILD.bazel", content = """\
load("@aspect_rules_py//py/private/exec_tools:defs.bzl", "py_exec_tools_toolchain")
load("@bazel_skylib//lib:selects.bzl", "selects")

package(default_visibility = ["//visibility:public"])

# Inactive local interpreter: {reason}

# Version config_settings that never match (empty flag value won't match
# any real version string).
config_setting(
    name = "_is_our_major_minor",
    flag_values = {{
        "{our_flag}": "INACTIVE_LOCAL_INTERPRETER",
    }},
)

selects.config_setting_group(
    name = "is_matching_python_version",
    match_any = [":_is_our_major_minor"],
)

config_setting(
    name = "is_matching_freethreaded",
    flag_values = {{
        "{freethreaded_flag}": "false",
    }},
)

filegroup(
    name = "runtime_pair",
    srcs = [],
)

py_exec_tools_toolchain(
    name = "exec_tools_toolchain",
)
""".format(
        reason = reason,
        our_flag = _PYTHON_VERSION_FLAG,
        freethreaded_flag = _FREETHREADING_FLAG,
    ))

local_python_interpreter = repository_rule(
    implementation = _local_python_interpreter_impl,
    attrs = {
        "env": attr.string(
            default = "",
            doc = "Environment variable pointing to a Python prefix (e.g. VIRTUAL_ENV).",
        ),
        "interpreter_path": attr.string(
            default = "",
            doc = "Absolute path to a Python interpreter binary.",
        ),
        "python_version": attr.string(
            default = "",
            doc = "Override the detected Python version (major.minor or major.minor.micro).",
        ),
        "_probe_script": attr.label(
            allow_single_file = True,
            default = Label(":probe_interpreter.py"),
        ),
    },
    environ = ["VIRTUAL_ENV"],
    doc = "Register a local (non-downloaded) Python interpreter as a toolchain.",
)
