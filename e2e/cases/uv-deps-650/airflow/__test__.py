#!/usr/bin/env python3

from importlib.util import find_spec

airflow_spec = find_spec("airflow")
assert airflow_spec is not None
assert airflow_spec.origin is not None, airflow_spec

import sys
assert sys.version_info.major == 3
assert sys.version_info.minor == 13
