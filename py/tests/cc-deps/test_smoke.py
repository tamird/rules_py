import subprocess
import sys

import native_module


assert native_module.answer() == 42

subprocess.run(
    [
        sys.executable,
        "-I",
        "-c",
        "import native_module; assert native_module.answer() == 42",
    ],
    check=True,
)
