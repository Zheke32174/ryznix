from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NIXP = ROOT / "bin" / "nixp.py"
HASH = "0123456789abcdfghijklmnpqrsvwxyz"


def config_value(tt: pathlib.Path) -> dict:
    return {
        "schema": "ryznix.runtime/v1",
        "expected_uid": 2000,
        "tmp_root": "/data/local/tmp",
        "rish": "~/rish",
        "ubuntu_root": "/data/local/tmp/ubuntu",
        "busybox": "/data/local/tmp/busybox",
        "ryzkern": "/data/local/tmp/ryzkern",
        "run_dir": "/data/local/tmp/run",
        "servers": {"ds": "/data/local/tmp/ds-server", "pm": "/data/local/tmp/pm-server"},
        "nix": {
            "tt": str(tt),
            "boot_root": "/data/local/tmp/nix-boot",
            "store": "/data/local/tmp/nix-boot/store",
            "shim": "/data/local/tmp/nix-boot/shim/lib",
            "var": "/data/local/tmp/nix-boot/var",
            "home": "/data/local/tmp/nix-boot/home",
            "glibc_store_name": f"{HASH}-glibc-test",
            "nix_store_name": f"{HASH}-nix-test",
            "ca_bundle_store_name": f"{HASH}-nss-cacert-test",
            "ca_bundle_relative_path": "etc/ssl/certs/ca-bundle.crt",
        },
        "claims": {"nix_compatibility_launcher_uses_proot": True},
    }


def write_config(root: pathlib.Path, *, placeholder: bool = False) -> pathlib.Path:
    tt = root / "tt"
    tt.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    tt.chmod(0o755)
    value = config_value(tt)
    if placeholder:
        value["nix"]["glibc_store_name"] = "REPLACE_ME"
    path = root / "runtime.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def run_cli(config: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(NIXP), "--config", str(config), *args],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class NixpTests(unittest.TestCase):
    def test_render_uses_locked_store_identities_and_proot_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            result = run_cli(config, "--render", "--", "build", "nixpkgs#hello")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"GLIBC={HASH}-glibc-test", result.stdout)
            self.assertIn(f"NIXPKG={HASH}-nix-test", result.stdout)
            self.assertIn("exec proot", result.stdout)
            self.assertIn("build 'nixpkgs#hello'", result.stdout)
            syntax = subprocess.run(
                ["sh", "-n"], input=result.stdout, text=True, check=False,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(syntax.returncode, 0, syntax.stderr)

    def test_forwarded_arguments_cannot_break_the_rendered_command(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            hostile = "x; touch /tmp/nixp-owned"
            result = run_cli(config, "--render", "--", "eval", hostile)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("'x; touch /tmp/nixp-owned'", result.stdout)
            syntax = subprocess.run(["sh", "-n"], input=result.stdout, text=True, check=False)
            self.assertEqual(syntax.returncode, 0)

    def test_placeholder_store_identity_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp), placeholder=True)
            result = run_cli(config, "--render", "--", "--version")
            self.assertEqual(result.returncode, 2)
            self.assertIn("exact locked Nix store basename", result.stderr)

    def test_doctor_labels_proot_as_nix_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            config = write_config(pathlib.Path(temp))
            result = run_cli(config, "--doctor")
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report["uses_proot"])
            self.assertEqual(report["scope"], "nix-compatibility-only")


if __name__ == "__main__":
    unittest.main()
