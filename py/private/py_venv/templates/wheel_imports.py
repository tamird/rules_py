"""Add complete wheel roots during venv site initialization."""

import os
import sys


_MANIFEST = None
_KNOWN_PATHS = None


def _append(path):
    global _KNOWN_PATHS
    path = os.path.abspath(path)
    normalized = os.path.normcase(path)
    if _KNOWN_PATHS is None:
        # Site initialization only appends paths, so this set stays current.
        _KNOWN_PATHS = {
            os.path.normcase(os.path.abspath(entry))
            for entry in sys.path
            if isinstance(entry, str)
        }
    if normalized not in _KNOWN_PATHS and os.path.exists(path):
        sys.path.append(path)
        _KNOWN_PATHS.add(normalized)


def _manifest_entries(path):
    entries = {}
    with open(path, encoding="utf-8") as manifest:
        for line in manifest:
            line = line.rstrip("\r\n")
            if line.startswith(" "):
                logical, target = line[1:].split(" ", 1)
                logical = logical.replace(r"\s", " ").replace(r"\n", "\n").replace(r"\b", "\\")
                target = target.replace(r"\n", "\n").replace(r"\b", "\\")
            else:
                logical, _, target = line.partition(" ")
                target = target or logical
            entries[logical] = target
    return entries


def add(logical, venv_escape):
    """Resolve and add one known, root-.pth-free wheel import root."""
    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if runfiles_dir and os.environ.get("RUNFILES_MANIFEST_ONLY") != "1":
        _append(os.path.join(runfiles_dir, logical))
        return

    manifest = os.environ.get("RUNFILES_MANIFEST_FILE")
    if not manifest:
        _append(os.path.join(sys.prefix, venv_escape, logical))
        return

    global _MANIFEST
    if _MANIFEST is None:
        _MANIFEST = _manifest_entries(manifest)

    prefix = logical
    while prefix:
        target = _MANIFEST.get(prefix)
        if target is not None:
            suffix = logical[len(prefix) :].lstrip("/")
            _append(os.path.join(target, suffix.replace("/", os.sep)))
            return
        prefix = prefix.rpartition("/")[0]
