import sys
from pathlib import Path


site_packages = (
    Path(sys.prefix)
    / "lib"
    / f"python{sys.version_info.major}.{sys.version_info.minor}"
    / "site-packages"
)
entries = sorted(path.name for path in (site_packages / "directory_marker.pth").iterdir())
assert entries == ["first.txt", "second.txt"], entries
