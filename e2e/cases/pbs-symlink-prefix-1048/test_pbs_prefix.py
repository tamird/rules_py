"""Exercise a PBS-backed venv from a Bazel action working directory."""

import argparse
import os
import subprocess
import sys

def _verify_prefixes(expected_cwd: str) -> None:
    assert os.path.samefile(os.getcwd(), expected_cwd), (os.getcwd(), expected_cwd)
    assert os.path.samefile(os.environ["PWD"], expected_cwd), (
        os.environ["PWD"],
        expected_cwd,
    )
    assert os.path.isabs(sys.base_prefix), sys.base_prefix
    assert os.path.isdir(sys.base_prefix), sys.base_prefix
    assert sys.base_prefix != "/install", sys.path
    assert os.path.isabs(sys.base_exec_prefix), sys.base_exec_prefix
    assert os.path.isdir(sys.base_exec_prefix), sys.base_exec_prefix
    assert sys.base_exec_prefix != "/install", sys.path
    assert os.path.isabs(sys.executable), sys.executable
    assert os.path.isfile(sys.executable), sys.executable
    assert os.path.isabs(sys._base_executable), sys._base_executable
    assert os.path.isfile(sys._base_executable), sys._base_executable

    pyvenv_cfg = os.path.join(os.path.dirname(sys.executable), "..", "pyvenv.cfg")
    with open(pyvenv_cfg, encoding="utf-8") as cfg:
        config = cfg.read()
    config_values = {}
    for line in config.splitlines():
        key, separator, value = line.partition("=")
        assert separator and key.strip() and value.strip(), line
        config_values[key.strip().lower()] = value.strip()
    assert config_values["relocatable"] == "true", config_values
    home = config_values.get("home")

    expect_missing_home = os.name != "nt" and sys.version_info[:2] in {
        (3, 11),
        (3, 12),
    }
    assert (home is None) == expect_missing_home, (home, sys.version_info)

    if not sys.flags.no_site:
        assert os.path.isabs(sys.prefix), sys.prefix
        assert os.path.isdir(sys.prefix), sys.prefix
        assert sys.prefix != sys.base_prefix, (sys.prefix, sys.base_prefix)

    stdlib = os.path.join(
        sys.base_prefix,
        "lib",
        f"python{sys.version_info.major}.{sys.version_info.minor}",
    )
    assert os.path.isdir(stdlib), (stdlib, sys.path)

    import _ctypes  # noqa: F401


def _verify_child(options: list[str], expected_cwd: str) -> None:
    subprocess.run(
        [
            sys.executable,
            *options,
            __file__,
            "--expected-cwd",
            expected_cwd,
        ],
        check=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-cwd", required=True)
    parser.add_argument("--test-children", action="store_true")
    args = parser.parse_args()

    _verify_prefixes(args.expected_cwd)
    if args.test_children:
        _verify_child([], args.expected_cwd)
        _verify_child(["-S"], args.expected_cwd)
        _verify_child(["-BS"], args.expected_cwd)
