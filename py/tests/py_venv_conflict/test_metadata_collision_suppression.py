from importlib.metadata import distributions
from pathlib import Path
import sys


matches = list(distributions(name="collision-metadata-shared"))
assert len(matches) == 1, [str(match.locate_file("")) for match in matches]
assert matches[0].metadata["Summary"] == "_metadata_suppressible_second"

venv_site_packages = next(
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages" and Path(entry).is_relative_to(sys.prefix)
)
assert (venv_site_packages / "collision_metadata_shared-1.0.dist-info").is_symlink()
