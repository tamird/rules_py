"""Exposed venvs retain concrete PEP 561 and stub-only wheel entries."""

from pathlib import Path
import sysconfig


site_packages = Path(sysconfig.get_paths()["purelib"])
assert (site_packages / "apkg" / "py.typed").is_file()
assert (site_packages / "bpkg-stubs" / "__init__.pyi").is_file()
assert (site_packages / "bpkg-stubs" / "py.typed").read_text() == "partial\n"
assert (site_packages / "pthtest_a-1.0.dist-info" / "METADATA").is_file()
assert (site_packages / "pthtest_b-1.0.dist-info" / "METADATA").is_file()
