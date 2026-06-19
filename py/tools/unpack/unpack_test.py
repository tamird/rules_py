import json
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


_TOP_LEVELS = {
    "fixture": "directory",
    "fixture-1.0.dist-info": "directory",
    "root_module.py": "file",
}


def _write_member(archive: zipfile.ZipFile, name: str, data: bytes, mode: int) -> None:
    info = zipfile.ZipInfo(name)
    info.external_attr = mode << 16
    archive.writestr(info, data)


def _build_wheel(path: Path, *, legacy_syntax: bool) -> None:
    body = (
        b"raise RuntimeError, None, None\n"
        if legacy_syntax
        else b"def f():\n    return 1\n"
    )
    with zipfile.ZipFile(path, "w") as archive:
        _write_member(archive, "fixture/__init__.py", b"VALUE = 1\n", 0o644)
        _write_member(archive, "root_module.py", body, 0o644)
        _write_member(archive, "fixture-1.0.dist-info/RECORD", b"", 0o644)


def _mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def _run_unpack(
    unpack: Path,
    wheel: Path,
    output: Path,
    python: Path,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(unpack),
            "--into",
            str(output),
            "--wheel",
            str(wheel),
            "--python-version-major",
            str(sys.version_info.major),
            "--python-version-minor",
            str(sys.version_info.minor),
            "--compile-pyc",
            "--python",
            str(python),
            "--expected-metadata",
            json.dumps({"top_levels": _TOP_LEVELS}),
        ],
        capture_output=True,
        text=True,
    )


def main() -> None:
    unpack = Path(sys.argv[1])
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        good_wheel = root / "fixture-1.0-py3-none-any.whl"
        _build_wheel(good_wheel, legacy_syntax=False)
        good_out = root / "good"
        ok = _run_unpack(unpack, good_wheel, good_out, Path(sys.executable))
        assert ok.returncode == 0, ok.stderr
        site_packages = (
            good_out
            / "lib"
            / f"python{sys.version_info.major}.{sys.version_info.minor}"
            / "site-packages"
        )
        assert next((site_packages / "fixture" / "__pycache__").glob("*.pyc"))

        legacy_wheel = root / "legacy-1.0-py3-none-any.whl"
        _build_wheel(legacy_wheel, legacy_syntax=True)
        legacy_out = root / "legacy"
        legacy = _run_unpack(
            unpack,
            legacy_wheel,
            legacy_out,
            Path(sys.executable),
        )
        assert legacy.returncode == 0, legacy.stderr
        legacy_site_packages = (
            legacy_out
            / "lib"
            / f"python{sys.version_info.major}.{sys.version_info.minor}"
            / "site-packages"
        )
        assert next(
            (legacy_site_packages / "fixture" / "__pycache__").glob("__init__*.pyc")
        )
        assert not (legacy_site_packages / "__pycache__").exists()
        assert "SyntaxError" in legacy.stdout + legacy.stderr

        false = shutil.which("false")
        assert false is not None
        failed = _run_unpack(unpack, good_wheel, root / "failed", Path(false))
        assert failed.returncode != 0, "expected child interpreter failure"
        assert "CalledProcessError" in failed.stderr

        wheel = root / "fixture-1.0-py3-none-any.whl"
        with zipfile.ZipFile(wheel, "w") as archive:
            _write_member(
                archive,
                "fixture/__init__.py",
                b"class commands:\n    @staticmethod\n    def main():\n        return 0\n",
                0o600,
            )
            _write_member(archive, "root_module.py", b"VALUE = 1\n", 0o600)
            _write_member(archive, "fixture/executable", b"payload\n", 0o700)
            _write_member(
                archive,
                "fixture-1.0.data/scripts/wheel-tool",
                b"#!/usr/bin/python\nprint('tool')\n",
                0o600,
            )
            _write_member(
                archive,
                "fixture-1.0.dist-info/entry_points.txt",
                b"[console_scripts]\nfixture-cli = fixture:commands.main\n",
                0o600,
            )
            _write_member(archive, "fixture-1.0.dist-info/RECORD", b"", 0o600)

        metadata = {
            "console_scripts": ["fixture-cli=fixture:commands.main"],
            "top_levels": _TOP_LEVELS,
        }
        expected_metadata = json.dumps(metadata, sort_keys=True)

        for inherited_umask in (0o077, 0o000):
            output = root / f"install-{inherited_umask:o}"
            output.mkdir(mode=0o700)
            wrapper = (
                "import os, runpy, sys; "
                f"os.umask({inherited_umask}); "
                "script = sys.argv[1]; "
                "sys.argv = sys.argv[1:]; "
                "runpy.run_path(script, run_name='__main__')"
            )
            subprocess.run(
                [
                    sys.executable,
                    "-c",
                    wrapper,
                    str(unpack),
                    "--into",
                    str(output),
                    "--wheel",
                    str(wheel),
                    "--python-version-major",
                    str(sys.version_info.major),
                    "--python-version-minor",
                    str(sys.version_info.minor),
                    "--expected-metadata",
                    expected_metadata,
                    "--compile-pyc",
                    "--python",
                    sys.executable,
                ],
                check=True,
            )

            site_packages = (
                output
                / "lib"
                / f"python{sys.version_info.major}.{sys.version_info.minor}"
                / "site-packages"
            )
            dist_info = site_packages / "fixture-1.0.dist-info"
            pyc = next((site_packages / "fixture" / "__pycache__").glob("*.pyc"))
            root_pyc = next((site_packages / "__pycache__").glob("root_module*.pyc"))

            for directory in (
                output / "lib",
                site_packages.parent,
                site_packages,
                site_packages / "fixture",
                dist_info,
                pyc.parent,
                root_pyc.parent,
                output / "bin",
            ):
                assert _mode(directory) == 0o755
            assert _mode(site_packages / "fixture" / "__init__.py") == 0o644
            assert _mode(site_packages / "fixture" / "executable") == 0o755
            assert _mode(output / "bin" / "wheel-tool") == 0o755
            assert _mode(output / "bin" / "fixture-cli") == 0o755
            assert _mode(dist_info / "INSTALLER") == 0o644
            assert _mode(dist_info / "REQUESTED") == 0o644
            assert _mode(dist_info / "RECORD") == 0o644
            assert _mode(pyc) == 0o644
            assert _mode(root_pyc) == 0o644
            subprocess.run(
                [sys.executable, str(output / "bin" / "fixture-cli")],
                check=True,
                env={"PYTHONPATH": str(site_packages)},
            )

        patch = root / "add-top-level.patch"
        site_packages_rel = (
            f"lib/python{sys.version_info.major}.{sys.version_info.minor}"
            "/site-packages/added.py"
        )
        patch.write_text(
            "--- /dev/null\n"
            f"+++ b/{site_packages_rel}\n"
            "@@ -0,0 +1 @@\n"
            "+VALUE = 1\n"
        )
        changed = subprocess.run(
            [
                sys.executable,
                str(unpack),
                "--into",
                str(root / "changed-install"),
                "--wheel",
                str(wheel),
                "--python-version-major",
                str(sys.version_info.major),
                "--python-version-minor",
                str(sys.version_info.minor),
                "--expected-metadata",
                expected_metadata,
                "--patch",
                str(patch),
                "--patch-strip",
                "1",
            ],
            capture_output=True,
            text=True,
        )
        assert changed.returncode != 0
        assert "Installed wheel metadata changed" in changed.stderr

        unknown_scripts = subprocess.run(
            [
                sys.executable,
                str(unpack),
                "--into",
                str(root / "unknown-install"),
                "--wheel",
                str(wheel),
                "--python-version-major",
                str(sys.version_info.major),
                "--python-version-minor",
                str(sys.version_info.minor),
                "--expected-metadata",
                json.dumps({"top_levels": metadata["top_levels"]}),
            ],
            capture_output=True,
            text=True,
        )
        assert unknown_scripts.returncode == 0, (
            unknown_scripts.stdout + unknown_scripts.stderr
        )

        known_empty_scripts = subprocess.run(
            [
                sys.executable,
                str(unpack),
                "--into",
                str(root / "known-empty-install"),
                "--wheel",
                str(wheel),
                "--python-version-major",
                str(sys.version_info.major),
                "--python-version-minor",
                str(sys.version_info.minor),
                "--expected-metadata",
                json.dumps({"console_scripts": []}),
            ],
            capture_output=True,
            text=True,
        )
        assert known_empty_scripts.returncode != 0
        assert "Installed wheel metadata changed" in known_empty_scripts.stderr, (
            known_empty_scripts.stdout + known_empty_scripts.stderr
        )


if __name__ == "__main__":
    main()
