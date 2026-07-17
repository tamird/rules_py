import importlib
from pathlib import Path
import sys

from collision_namespace import shared


expected, first_root = sys.argv[1:3]
assert shared.VALUE == expected, (shared.VALUE, expected)
for unique in ("first", "second"):
    module = importlib.import_module(f"collision_namespace.{unique}")
    assert module.VALUE == unique, (module.VALUE, unique)

wheel_values = []
for entry in sys.path:
    root = Path(entry)
    # Compact venvs keep both complete wheel roots on sys.path. Reverse
    # postorder puts the collision winner first while retaining the loser.
    if not any(part.endswith(".install") for part in root.parts):
        continue
    for unique in ("first", "second"):
        if (root / "collision_namespace" / f"{unique}.py").is_file():
            wheel_values.append(unique)
assert wheel_values == [expected, first_root], wheel_values
