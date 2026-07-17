"""Add complete wheel roots during venv site initialization."""

import os
import site
import sys


_MANIFEST = None


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
        site.addsitedir(os.path.join(runfiles_dir, logical))
        return

    manifest = os.environ.get("RUNFILES_MANIFEST_FILE")
    if not manifest:
        site.addsitedir(os.path.normpath(os.path.join(sys.prefix, venv_escape, logical)))
        return

    global _MANIFEST
    if _MANIFEST is None:
        _MANIFEST = _manifest_entries(manifest)

    prefix = logical
    while prefix:
        target = _MANIFEST.get(prefix)
        if target is not None:
            suffix = logical[len(prefix) :].lstrip("/")
            site.addsitedir(os.path.join(target, suffix.replace("/", os.sep)))
            return
        prefix = prefix.rpartition("/")[0]
