"""Runtime coverage for ordinary targets importing directly from wheel roots."""

import importlib.metadata
import os
import subprocess
import sys
import sysconfig
from pathlib import Path


def assert_wheel_runtime() -> None:
    import collision
    import runtime_namespace.first
    import runtime_namespace.second

    assert collision.WINNER == "second"
    if os.environ.get("RULES_PY_MANIFEST_ONLY_CHILD") == "1":
        assert type(collision.__loader__).__name__ == "_ManifestSourceFileLoader"
    assert runtime_namespace.first.VALUE == "first"
    assert runtime_namespace.second.VALUE == "second"
    assert importlib.metadata.version("runtime-wheel-first") == "1.0"
    assert importlib.metadata.version("runtime-wheel-second") == "2.0"

    entry_points = importlib.metadata.entry_points()
    group = (
        entry_points.select(group="runtime.group")
        if hasattr(entry_points, "select")
        else entry_points.get("runtime.group", ())
    )
    matching = [entry_point for entry_point in group if entry_point.name == "second"]
    assert matching
    assert all(entry_point.load()() == "second" for entry_point in matching)


def run_manifest_only_child() -> None:
    import runtime_namespace.first
    import runtime_namespace.second

    config = (
        Path(sysconfig.get_paths()["purelib"]) / "_aspect_rules_py_imports.txt"
    )
    logical_roots = [
        line
        for line in config.read_text().splitlines()
        if "_runtime_wheel_" in line
    ]
    assert len(logical_roots) == 2
    physical_roots = {
        "_runtime_wheel_first.install": Path(
            runtime_namespace.first.__file__,
        ).parents[1],
        "_runtime_wheel_second.install": Path(
            runtime_namespace.second.__file__,
        ).parents[1],
    }
    manifest_lines = []
    for logical_root in logical_roots:
        matching = [
            physical_root
            for target, physical_root in physical_roots.items()
            if target in logical_root
        ]
        assert len(matching) == 1
        manifest_lines.append(f"{logical_root} {matching[0]}\n")

    manifest = Path(os.environ["TEST_TMPDIR"]) / "wheel.MANIFEST"
    manifest.write_text("".join(manifest_lines))
    env = dict(os.environ)
    env["RULES_PY_MANIFEST_ONLY_CHILD"] = "1"
    env["RUNFILES_MANIFEST_FILE"] = str(manifest)
    env["RUNFILES_MANIFEST_ONLY"] = "1"
    env.pop("RUNFILES_DIR", None)
    subprocess.run([sys.executable, os.path.abspath(__file__)], check=True, env=env)


assert_wheel_runtime()
if os.environ.get("RULES_PY_MANIFEST_ONLY_CHILD") != "1":
    run_manifest_only_child()
