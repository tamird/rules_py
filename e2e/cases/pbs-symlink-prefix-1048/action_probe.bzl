"""Action-level PBS venv regression target."""

load("@aspect_rules_py//py:defs.bzl", "py_binary")

def pbs_action_probe(name, python_version):
    """Run a PBS-backed binary from a non-runfiles action cwd."""
    py_binary(
        name = name,
        srcs = ["test_pbs_prefix.py"],
        expose_venv = True,
        main = "test_pbs_prefix.py",
        python_version = python_version,
    )

    commands = [
        "root=$$(pwd)",
        "mkdir -p $(@D)/cwd",
        "cd $(@D)/cwd",
        (
            "\"$$root/$(execpath :{name})\" " +
            "--expected-cwd \"$$PWD\" --test-children"
        ).format(name = name),
        (
            "\"$$root/$(execpath :{name}.venv)\" " +
            "\"$$root/$(location test_pbs_prefix.py)\" " +
            "--expected-cwd \"$$PWD\""
        ).format(name = name),
        "touch \"$$root/$@\"",
    ]

    native.genrule(
        name = name + "_output",
        srcs = ["test_pbs_prefix.py"],
        outs = [name + ".stamp"],
        cmd = "\n".join(commands),
        tools = [
            ":" + name,
            ":" + name + ".venv",
        ],
    )
