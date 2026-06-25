import importlib

import collision_order
from collision_order import shared


assert collision_order.VALUE == "reset_final", collision_order.VALUE
assert shared.VALUE == "reset_final", shared.VALUE
for surviving in ("reset_after", "reset_final"):
    module = importlib.import_module(f"collision_order.{surviving}")
    assert module.VALUE == surviving, (module.VALUE, surviving)
try:
    importlib.import_module("collision_order.reset_before")
except ModuleNotFoundError:
    pass
else:
    raise AssertionError("pre-reset module survived: reset_before")
