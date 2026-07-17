from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "bin" / "ryznix-runtime.py"


def config_value(rish: pathlib.Path) -> dict:
    return {
        "schema": "ryznix.runtime/v1",
        "expected_uid": 2000,
        "tmp_root": "/data/local/tmp",
        "rish": str(rish),
        "ubuntu_root": "/data/local/tmp/ubuntu",
        "busybox": "/data/local/tmp/busybox",
        "ryzkern": "/data/local/tmp/ryzkern",
        "run_dir": "/data/local/tmp/run",
        "servers": {
            "ds": "/data/local/tmp/ds-server",
            "pm": "/data/local/tmp/pm-server",
        },
        "nix": {},
        "claims": {
            "authoritative_kernel": False,
            "root_authority": False,
            "core_runtime_uses_proot": False,
            "nix_compatibility_launcher_uses_proot": True,
        },
    }


def write_config(root: pathlib.Path) -> pathlib.Path:
    rish = root / "rish"
    rish.write_text("#!/bin/sh\ncat >/dev/null\n", encoding="utf-8")
    rish.chmod(0o755)
    path = root / "runtime.json"
    path.write_text(json.dumps(config_value(rish)), encoding="utf-8")
    return path


def run_cli(config: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RUNTIME), "--config", str(config), *args],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class RuntimeTests(unittest.TestCase):
    def test_shell_render_has_explicit_authority_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            result = run_cli(config, "shell", "--render")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Android kernel remains authoritative", result.stdout)
            self.assertIn('test "$(id -u)" = 2000', result.stdout)
            syntax = subprocess.run(
                ["sh", "-n"], input=result.stdout, text=True, check=False,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(syntax.returncode, 0, syntax.stderr)

    def test_shell_command_is_quoted_as_one_command(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            hostile = "value; touch /tmp/ryznix-test-owned"
            result = run_cli(config, "shell", "--render", "--", "printf", "%s", hostile)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("touch /tmp/ryznix-test-owned", result.stdout)
            self.assertIn("'value; touch /tmp/ryznix-test-owned'", result.stdout)
            syntax = subprocess.run(["sh", "-n"], input=result.stdout, text=True, check=False)
            self.assertEqual(syntax.returncode, 0)

    def test_kernel_action_vocabulary_and_quoting(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            result = run_cli(config, "kernel", "--render", "exec", "--", "/data/local/tmp/example", "a; id")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout,
                "exec /data/local/tmp/ryzkern exec /data/local/tmp/example 'a; id'\n",
            )
            blocked = run_cli(config, "kernel", "--render", "status", "extra")
            self.assertEqual(blocked.returncode, 2)
            self.assertIn("accepts no extra arguments", blocked.stderr)

    def test_init_config_is_private_and_non_destructive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            example = root / "example.json"
            example.write_text(json.dumps(config_value(root / "rish")), encoding="utf-8")
            output = root / "config" / "runtime.json"
            result = subprocess.run(
                [
                    sys.executable, str(RUNTIME), "init-config",
                    "--example", str(example), "--output", str(output),
                ],
                cwd=ROOT, check=False, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o600)
            second = subprocess.run(
                [
                    sys.executable, str(RUNTIME), "init-config",
                    "--example", str(example), "--output", str(output),
                ],
                cwd=ROOT, check=False, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(second.returncode, 2)
            self.assertIn("refusing to replace", second.stderr)


if __name__ == "__main__":
    unittest.main()
