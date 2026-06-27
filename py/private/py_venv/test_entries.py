import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

import entries


class EntriesTest(unittest.TestCase):
    def test_json_lines_preserve_symlink_text_and_file_bytes(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            symlink = root / "venv/lib/site-packages/example"
            script = root / "venv/bin/example"
            content = "#!/bin/sh\nexec \"$0\" '$@'\n"
            params = root / "entries.params"
            params.write_text(
                "\n".join([
                    json.dumps({
                        "kind": "symlink",
                        "output": str(symlink),
                        "target": "../../../../wheel/site-packages/example",
                    }),
                    json.dumps({
                        "kind": "file",
                        "output": str(script),
                        "content": content,
                        "executable": True,
                    }),
                ]),
            )

            entries.main(["@" + str(params)])

            self.assertEqual(
                os.readlink(symlink),
                "../../../../wheel/site-packages/example",
            )
            self.assertEqual(script.read_bytes(), content.encode())
            self.assertEqual(stat.S_IMODE(script.stat().st_mode), 0o755)


if __name__ == "__main__":
    unittest.main()
