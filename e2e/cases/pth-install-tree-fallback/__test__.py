"""Regular directories overlay while colliding files remain last-wins."""

import sys

import apkg
import bpkg
import shared

assert apkg.VALUE == "apkg"
assert bpkg.VALUE == "bpkg"
assert shared.OWNER == "b"
assert "rules_py_itf_sentinel_a" not in sys.path
assert "rules_py_itf_sentinel_b" in sys.path
