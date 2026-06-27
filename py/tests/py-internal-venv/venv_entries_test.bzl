"""Analysis checks for venv entry batching."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _count_mnemonic(actions, mnemonic):
    return len([action for action in actions if action.mnemonic == mnemonic])

def _outputs_for_mnemonic(actions, mnemonic):
    return [
        output.short_path
        for action in actions
        if action.mnemonic == mnemonic
        for output in action.outputs.to_list()
    ]

def _assert_entries(env, actions, venv_name):
    entry_actions = [
        action
        for action in actions
        if action.mnemonic == "PyVenvEntries"
    ]
    asserts.equals(env, 1, len(entry_actions))
    if len(entry_actions) != 1:
        return
    asserts.equals(
        env,
        [
            "py/tests/py-internal-venv/{}/bin/cowsay".format(venv_name),
            "py/tests/py-internal-venv/{}/lib/python3.9/site-packages/cowsay".format(venv_name),
            "py/tests/py-internal-venv/{}/lib/python3.9/site-packages/cowsay-6.1.dist-info".format(venv_name),
        ],
        sorted([output.short_path for output in entry_actions[0].outputs.to_list()]),
    )
    asserts.true(
        env,
        _count_mnemonic(actions, "UnresolvedSymlink") > 0,
        "bin links should keep their per-output symlink actions",
    )

def _assert_fallback(env, actions, venv_name):
    asserts.equals(env, 0, _count_mnemonic(actions, "PyVenvEntries"))
    prefix = "py/tests/py-internal-venv/{}/".format(venv_name)
    for mnemonic, relative_path in [
        ("FileWrite", "bin/cowsay"),
        ("UnresolvedSymlink", "lib/python3.9/site-packages/cowsay"),
        ("UnresolvedSymlink", "lib/python3.9/site-packages/cowsay-6.1.dist-info"),
    ]:
        path = prefix + relative_path
        asserts.true(
            env,
            path in _outputs_for_mnemonic(actions, mnemonic),
            "fallback should keep {} as {}".format(path, mnemonic),
        )

def _private_venv_entries_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_entries(env, analysistest.target_actions(env), "._test.venv")
    return analysistest.end(env)

_WINDOWS_CONFIG_SETTINGS = {
    "//command_line_option:platforms": str(Label("//py/tests/py-internal-venv:_windows_x86_64")),
}

private_venv_entries_test = analysistest.make(_private_venv_entries_test_impl)

def _exposed_venv_entries_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_fallback(env, analysistest.target_actions(env), "._exposed_test.venv")
    return analysistest.end(env)

exposed_venv_entries_test = analysistest.make(_exposed_venv_entries_test_impl)

def _explicit_venv_entries_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_fallback(env, analysistest.target_actions(env), "._explicit_venv")
    return analysistest.end(env)

explicit_venv_entries_test = analysistest.make(_explicit_venv_entries_test_impl)

def _windows_private_venv_entries_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_fallback(env, analysistest.target_actions(env), "._test.venv")
    return analysistest.end(env)

def _windows_exposed_venv_entries_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_fallback(env, analysistest.target_actions(env), "._exposed_test.venv")
    return analysistest.end(env)

windows_private_venv_entries_test = analysistest.make(
    _windows_private_venv_entries_test_impl,
    config_settings = _WINDOWS_CONFIG_SETTINGS,
)
windows_exposed_venv_entries_test = analysistest.make(
    _windows_exposed_venv_entries_test_impl,
    config_settings = _WINDOWS_CONFIG_SETTINGS,
)
