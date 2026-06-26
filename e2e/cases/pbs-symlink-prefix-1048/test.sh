#!/usr/bin/env bash

set -euo pipefail

# The root module's Python 3.12 toolchain comes from rules_python, while the
# e2e module uses rules_py's PBS extension. Exercise the original #1048
# producer explicitly as well as the rules_py action probes in this package.
cd "$(dirname "$0")/../../.."
bazel test --//py/private/interpreter:python_version=3.12 -- \
    //:sdist_fallback_with_anyarch_wheel_build_test
