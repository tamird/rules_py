"""Action-level PBS venv regression target."""

load("@aspect_rules_py//py:defs.bzl", "py_binary")

def pbs_action_probe(name, python_version, test_children, test_venv):
    """Run a PBS-backed binary from a non-runfiles action cwd."""
    py_binary(
        name = name,
        srcs = ["test_pbs_prefix.py"],
        expose_venv = test_venv,
        main = "test_pbs_prefix.py",
        python_version = python_version,
    )

    commands = [
        "root=$$(pwd)",
        "mkdir -p $(@D)/cwd",
        "cd $(@D)/cwd",
        "\"$$root/$(execpath :{name})\" --expected-cwd \"$$PWD\" {children}".format(
            children = "--test-children" if test_children else "",
            name = name,
        ),
    ]
    tools = [":" + name]
    srcs = []

    if test_venv:
        commands.append(
            (
                "\"$$root/$(execpath :{name}.venv)\" " +
                "\"$$root/$(location test_pbs_prefix.py)\" " +
                "--expected-cwd \"$$PWD\""
            ).format(name = name),
        )
        tools.append(":" + name + ".venv")
        srcs.append("test_pbs_prefix.py")

    commands.append("touch \"$$root/$@\"")
    native.genrule(
        name = name + "_output",
        srcs = srcs,
        outs = [name + ".stamp"],
        cmd = "\n".join(commands),
        tools = tools,
    )
