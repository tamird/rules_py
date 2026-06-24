"""Regression: a known (install_tree) wheel forced onto assemble_venv's
`site.addsitedir` fallback must not execute its root `.pth` files more
than a wheel that stayed on the direct-symlink path.

The hazard: if `_format_imp` uses `site.addsitedir()` on a known wheel's
natural root, its root `.pth` files are already projected into the venv
by `top_level_to_site_pkgs`, so site startup executes the projected copy
and then `addsitedir()` executes the original — a double execution.

Setup: two `py_unpacked_wheel`s, each emitting `PyWheelsInfo` and carrying a
distinct root `.pth` that appends a unique sentinel to `sys.path`. Both wheels
contribute to the PEP 420 namespace `shared`. The first declares its concrete
entry, while the second omits namespace-entry metadata and is therefore routed
through `_format_imp`'s fallback. The first stays on the projected layout.

What we assert: each wheel's root `.pth` must fire the SAME number of times,
regardless of whether its namespace portion was projected or left on the
fallback. We do not assert an absolute count of one: rules_py's launcher
processes the venv site-packages as a site dir twice, so every *projected* root
`.pth` already fires twice — a pre-existing, symmetric baseline. The hazard is
asymmetric: if only the fallback wheel gets its root re-scanned with
`addsitedir`, its sentinel lands extra times. Asserting symmetry isolates that
regression from the launcher's per-site-dir scan count.

A known install_tree wheel routed onto the fallback path must emit a
plain path entry (never re-scanned), not `site.addsitedir`, so its root
`.pth` count matches a wheel that stayed on the direct-symlink path.
"""

import sys

SENTINEL_A = "rules_py_pth_sentinel_a"
SENTINEL_B = "rules_py_pth_sentinel_b"


def main():
    count_a = sys.path.count(SENTINEL_A)
    count_b = sys.path.count(SENTINEL_B)
    print(f"{SENTINEL_A}: {count_a} time(s) on sys.path")
    print(f"{SENTINEL_B}: {count_b} time(s) on sys.path")

    # Sanity: both wheels and both namespace portions are importable.
    import apkg
    import bpkg
    from shared import a, b

    print(
        f"imported apkg={apkg.VALUE} bpkg={bpkg.VALUE} "
        f"shared-owners={a.OWNER},{b.OWNER}"
    )

    if count_a < 1 or count_b < 1:
        print("FAIL: a wheel-root .pth did not execute at all.")
        sys.exit(1)

    if count_a != count_b:
        print(
            "FAIL: wheel-root .pth executions are asymmetric "
            f"({SENTINEL_A}={count_a}, {SENTINEL_B}={count_b}). The fallback "
            "wheel was routed through site.addsitedir(), which re-scanned its "
            "wheel root and re-executed a root .pth already projected into the "
            "venv site-packages. A known install_tree wheel on the fallback "
            "path must use a plain path entry, not addsitedir."
        )
        sys.exit(1)

    print("PASS: both wheel-root .pth files executed the same number of times.")


if __name__ == "__main__":
    main()
