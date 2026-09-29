"""Run with python3 game/tests/features/console/test_git_snapshot.py."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).resolve().parents[3] / "scripts/git_snapshot.py"
spec = importlib.util.spec_from_file_location("git_snapshot", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SnapshotTest(unittest.TestCase):
    def test_real_repository_metadata_without_contents_or_untracked_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], text=True)

            git("init", "-q")
            (root / "example.txt").write_text("private content not for console\n")
            git("add", "example.txt")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "commit", "-qm", "Example subject")
            before = git("rev-parse", "HEAD").strip()
            (root / "example.txt").write_text("modified content\n")
            (root / "untracked.txt").write_text("untracked content\n")
            data = module.snapshot(root)
            self.assertEqual(data["rev-parse HEAD"], before)
            self.assertIn("Example subject", data["log"])
            self.assertIn("example.txt", data["show"])
            self.assertIn("M example.txt", data["status"])
            self.assertEqual(data["ls-files"], "example.txt")
            self.assertNotIn("content", str(data))
            self.assertNotIn("untracked.txt", str(data))
            self.assertEqual(git("rev-parse", "HEAD").strip(), before)
            self.assertEqual((root / "example.txt").read_text(), "modified content\n")
            git("checkout", "--detach", "-q")
            self.assertEqual(module.snapshot(root)["branch"], "(detached HEAD)")

    def test_missing_repository_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(subprocess.CalledProcessError):
                module.snapshot(Path(directory))


if __name__ == "__main__":
    unittest.main()
