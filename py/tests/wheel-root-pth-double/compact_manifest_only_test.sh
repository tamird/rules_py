#!/usr/bin/env bash
set -euo pipefail

package="${TEST_SRCDIR}/_main/py/tests/wheel-root-pth-double"
source_venv="${package}/._compact_runtime_test.venv"
venv="${TEST_TMPDIR}/manifest-only-venv"
site_packages="${venv}/lib/python3.9/site-packages"
manifest="${TEST_TMPDIR}/runfiles_manifest"

mkdir -p "${venv}/bin" "${site_packages}"
cp "${source_venv}/lib/python3.9/site-packages/"*.py "${site_packages}/"
cp "${source_venv}/lib/python3.9/site-packages/"*.pth "${site_packages}/"
base_python="$("${source_venv}/bin/python" -c 'import sys; print(sys._base_executable)')"
printf '%s\n' "home = $(dirname "${base_python}")" > "${venv}/pyvenv.cfg"
sed -n '2,$p' "${source_venv}/pyvenv.cfg" >> "${venv}/pyvenv.cfg"
ln -s "${base_python}" "${venv}/bin/python"

printf '%s %s\n' \
  '_main/py/tests/wheel-root-pth-double/compact_a' "$(cd "${package}/compact_a" && pwd -P)" \
  '_main/py/tests/wheel-root-pth-double/compact_b' "$(cd "${package}/compact_b" && pwd -P)" \
  > "${manifest}"

env -u RUNFILES_DIR \
  RUNFILES_MANIFEST_ONLY=1 \
  RUNFILES_MANIFEST_FILE="${manifest}" \
  "${venv}/bin/python" -B -I "${package}/compact_runtime_test.py"

env -u RUNFILES_MANIFEST_ONLY \
  RUNFILES_DIR="${TEST_TMPDIR}/nonexistent-runfiles" \
  RUNFILES_MANIFEST_FILE="${manifest}" \
  "${venv}/bin/python" -B -I "${package}/compact_runtime_test.py"
