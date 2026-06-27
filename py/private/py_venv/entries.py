"""Materialize the cheap leaf entries in a build-time venv.

Bazel passes one compact JSON object per parameter-file line. Each entry
describes one declared output, so this tool only needs to recreate the exact
symlink text or file bytes chosen during analysis.
"""

import argparse
import json
import os
from pathlib import Path


def main(argv=None):
    parser = argparse.ArgumentParser(fromfile_prefix_chars="@")
    parser.add_argument("entries", nargs="+")
    args = parser.parse_args(argv)

    for encoded_entry in args.entries:
        entry = json.loads(encoded_entry)
        output = Path(entry["output"])
        output.parent.mkdir(parents=True, exist_ok=True)

        kind = entry["kind"]
        if kind == "symlink":
            os.symlink(entry["target"], output)
        elif kind == "file":
            output.write_bytes(entry["content"].encode())
            if entry["executable"]:
                output.chmod(0o755)
        else:
            raise ValueError("unknown venv entry kind: {}".format(kind))


if __name__ == "__main__":
    main()
