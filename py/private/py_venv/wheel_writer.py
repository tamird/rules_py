"""Writes synthetic wheel install trees for venv runtime tests."""

import argparse
import json
from pathlib import Path, PurePosixPath


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--files-json", required=True)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    files: dict[str, str] = json.loads(args.files_json)
    for path, content in files.items():
        destination = args.output.joinpath(*PurePosixPath(path).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
