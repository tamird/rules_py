"""Nested entries with one import name keep FileFinder precedence."""

from importlib.util import find_spec
from pathlib import Path
import sys

import shape_ns.package


assert shape_ns.package.VALUE == "package"
extension = find_spec("shape_ns.extension")
assert extension is not None
assert extension.origin is not None
assert extension.origin.endswith("shape_ns/extension.so"), extension.origin

site_packages = next(
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages" and Path(entry).is_relative_to(sys.prefix)
)
assert (site_packages / "shape_ns" / "package").is_symlink()
assert (site_packages / "shape_ns" / "package.py").is_symlink()
assert (site_packages / "shape_ns" / "extension.so").is_symlink()
assert (site_packages / "shape_ns" / "extension.py").is_symlink()
