import importlib
import subprocess
import sys
from importlib.metadata import distributions

import collision_order
from collision_order import shared as ordinary_shared
from collision_namespace import shared


expected = sys.argv[1]
assert collision_order.VALUE == expected, (collision_order.VALUE, expected)
assert ordinary_shared.VALUE == expected, (ordinary_shared.VALUE, expected)
assert shared.VALUE == expected, (shared.VALUE, expected)
for unique in ("first", "second"):
    module = importlib.import_module(f"collision_order.{unique}")
    assert module.VALUE == unique, (module.VALUE, unique)
    module = importlib.import_module(f"collision_namespace.{unique}")
    assert module.VALUE == unique, (module.VALUE, unique)
    metadata = list(distributions(name=f"collision-{unique}"))
    assert len(metadata) == 1, [str(item.locate_file("")) for item in metadata]
result = subprocess.run(
    [sys.prefix + "/bin/collision-order"],
    check=True,
    capture_output=True,
    text=True,
)
assert result.stdout == expected + "\n", result.stdout
