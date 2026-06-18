"""Verify unknown wheel topology retains dependency-order precedence."""

import sys

from shared.collision import VALUE


assert VALUE == sys.argv[1], (VALUE, sys.argv[1])
