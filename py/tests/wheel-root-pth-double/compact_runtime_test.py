"""Compact private venvs import complete wheel roots in precedence order."""

import importlib.resources
import sys
from importlib.metadata import distribution
from pathlib import Path

import apkg
import bpkg


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
