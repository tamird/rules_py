"""Differently shaped entries with one import name keep FileFinder precedence."""

from importlib.util import find_spec
from pathlib import Path
import sys

import shape_package


assert shape_package.VALUE == "package"
extension = find_spec("shape_extension")
assert extension is not None
assert extension.origin is not None
assert extension.origin.endswith("shape_extension.so"), extension.origin

site_packages = next(
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages" and Path(entry).is_relative_to(sys.prefix)
)
assert (site_packages / "shape_package").is_symlink()
assert (site_packages / "shape_package.py").is_symlink()
assert (site_packages / "shape_extension.so").is_symlink()
assert (site_packages / "shape_extension.py").is_symlink()
