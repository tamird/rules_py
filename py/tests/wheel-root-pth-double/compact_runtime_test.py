"""Compact private venvs import complete wheel roots in precedence order."""

import importlib.resources
import os
import re
import site
import sys
from importlib.metadata import distribution
from pathlib import Path

import apkg
import bpkg
import _aspect_rules_py_wheel_imports as wheel_imports


roots = [
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages"
    and any(part in {"compact_a", "compact_b"} for part in Path(entry).parts)
]
assert len(roots) == 2, roots
assert "compact_b" in roots[0].parts, roots
assert "compact_a" in roots[1].parts, roots

assert Path(apkg.__file__).is_relative_to(roots[1]), apkg.__file__
assert Path(bpkg.__file__).is_relative_to(roots[0]), bpkg.__file__
assert importlib.resources.read_text(apkg, "data.txt") == "wheel-backed data\n"
assert distribution("pthtest-a").version == "1.0"
assert distribution("pthtest-b").version == "1.0"

venv_site_packages = next(
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages" and Path(entry).is_relative_to(sys.prefix)
)
assert not (venv_site_packages / "apkg").exists()
assert not (venv_site_packages / "bpkg").exists()
assert not (venv_site_packages / "pthtest_a-1.0.dist-info").exists()
assert not (venv_site_packages / "pthtest_b-1.0.dist-info").exists()

pth = next(
    path
    for path in venv_site_packages.glob("*.pth")
    if "_aspect_rules_py_wheel_imports.add(" in path.read_text()
)
imports = re.findall(r'\.add\("([^"]+)", "([^"]+)"\)', pth.read_text())
assert len(imports) == 2, imports

def _scan(*_args, **_kwargs):
    raise AssertionError("compact wheel roots must not be scanned")

original_addsitedir = site.addsitedir
original_listdir = os.listdir
original_scandir = os.scandir
original_abspath = os.path.abspath
normalizations = []

def _abspath(path):
    normalizations.append(path)
    return original_abspath(path)

try:
    site.addsitedir = _scan
    os.listdir = _scan
    os.scandir = _scan
    os.path.abspath = _abspath
    before = list(sys.path)
    wheel_imports._KNOWN_PATHS = None
    add_calls = 2 * len(imports) + 2
    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if (runfiles_dir and os.environ.get("RUNFILES_MANIFEST_FILE") and
        os.environ.get("RUNFILES_MANIFEST_ONLY") != "1" and
        any(not (Path(runfiles_dir) / logical).exists() for logical, _ in imports)):
        add_calls += 2 * len(imports) + 1
    for logical, escape in imports:
        wheel_imports.add(logical + "/.", escape)
        wheel_imports.add(logical, escape)
    wheel_imports.add(imports[0][0] + "/missing", imports[0][1])
    assert sys.path == before, sys.path

    if os.environ.get("RUNFILES_MANIFEST_ONLY") != "1":
        runfiles_dir = os.environ.pop("RUNFILES_DIR", None)
        manifest = os.environ.pop("RUNFILES_MANIFEST_FILE", None)
        try:
            os.environ["RUNFILES_DIR"] = "/nonexistent-runfiles"
            add_calls += 2 * len(imports)
            for logical, escape in imports:
                wheel_imports.add(logical, escape)
            assert sys.path == before, sys.path
        finally:
            if runfiles_dir is not None:
                os.environ["RUNFILES_DIR"] = runfiles_dir
            if manifest is not None:
                os.environ["RUNFILES_MANIFEST_FILE"] = manifest
    assert len(normalizations) == len(before) + add_calls, normalizations
finally:
    site.addsitedir = original_addsitedir
    os.listdir = original_listdir
    os.scandir = original_scandir
    os.path.abspath = original_abspath
