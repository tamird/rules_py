from importlib.util import find_spec
from importlib.metadata import distributions
from pathlib import Path
import sys

from collision_order import second


assert second.VALUE == "second", second.VALUE
assert find_spec("collision_order.first") is None
assert second.sibling_value() == "second"
assert len(list(distributions(name="collision-native"))) == 1

venv_site_packages = next(
    Path(entry)
    for entry in sys.path
    if Path(entry).name == "site-packages" and Path(entry).is_relative_to(sys.prefix)
)
assert (venv_site_packages / "collision_order").is_symlink()
assert (venv_site_packages / "collision_native-1.0.dist-info").is_symlink()
