#!/usr/bin/env python3
"""Run the optional rootless Nix compatibility layer from a reviewed manifest."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any

SCHEMA = "ryznix.runtime/v1"
STORE_RE = re.compile(r"^[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]{1,160}$")
RELATIVE_RE = re.compile(r"^[A-Za-z0-9._/+?-]{1,240}$")


class NixpError(RuntimeError):
    pass


def quote(value: object) -> str:
    return shlex.quote(str(value))


def expand_local(value: str) -> pathlib.Path:
    return pathlib.Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def absolute_remote(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.startswith("/") or any(ch in value for ch in "\n\r\0"):
        raise NixpError(f"{label} must be an absolute remote path")
    return value.rstrip("/") or "/"


def store_name(value: Any, label: str) -> str:
    if not isinstance(value, str) or not STORE_RE.fullmatch(value):
        raise NixpError(
            f"{label} must be an exact locked Nix store basename, not a placeholder or path"
        )
    return value


def relative_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or value.startswith("/") or ".." in pathlib.PurePosixPath(value).parts:
        raise NixpError(f"{label} must be a safe relative path")
    if not RELATIVE_RE.fullmatch(value):
        raise NixpError(f"{label} contains unsupported characters")
    return value


def load_config(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise NixpError(f"runtime config not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise NixpError(f"invalid runtime config {path}: {exc}") from exc
    if not isinstance(value, dict) or value.get("schema") != SCHEMA:
        raise NixpError(f"runtime config schema must be {SCHEMA}")
    nix = value.get("nix")
    if not isinstance(nix, dict):
        raise NixpError("runtime config must contain a nix object")
    for key in ("boot_root", "store", "shim", "var", "home"):
        absolute_remote(nix.get(key), f"nix.{key}")
    tt = nix.get("tt")
    if not isinstance(tt, str) or not tt.strip():
        raise NixpError("nix.tt must be a local launcher path")
    store_name(nix.get("glibc_store_name"), "nix.glibc_store_name")
    store_name(nix.get("nix_store_name"), "nix.nix_store_name")
    store_name(nix.get("ca_bundle_store_name"), "nix.ca_bundle_store_name")
    relative_path(nix.get("ca_bundle_relative_path"), "nix.ca_bundle_relative_path")
    return value


def render_script(config: dict[str, Any], arguments: list[str]) -> str:
    nix = config["nix"]
    boot = absolute_remote(nix["boot_root"], "nix.boot_root")
    store = absolute_remote(nix["store"], "nix.store")
    shim = absolute_remote(nix["shim"], "nix.shim")
    var = absolute_remote(nix["var"], "nix.var")
    home = absolute_remote(nix["home"], "nix.home")
    glibc = store_name(nix["glibc_store_name"], "nix.glibc_store_name")
    nix_package = store_name(nix["nix_store_name"], "nix.nix_store_name")
    ca_store = store_name(nix["ca_bundle_store_name"], "nix.ca_bundle_store_name")
    ca_rel = relative_path(nix["ca_bundle_relative_path"], "nix.ca_bundle_relative_path")

    command = (
        'exec proot '
        '-b "$S:/nix/store" '
        '-b "$SHIM:/nix/store/shimlib" '
        '-b "$VAR:/nix/var" '
        '-b "$HOMEDIR:/root" '
        '-b /dev -b /proc -b /sys -b /data/local/tmp '
        '-b "$PREFIX/etc/resolv.conf:/etc/resolv.conf" '
        '-w / '
        '"/nix/store/$GLIBC/lib/ld-linux-aarch64.so.1" '
        '--library-path "$LP" '
        '"/nix/store/$NIXPKG/bin/nix" '
        "--extra-experimental-features 'nix-command flakes' "
        "--option substituters 'https://cache.nixos.org' "
        '--option ssl-cert-file "$CACERT" '
        '--option use-sqlite-wal false '
        "--option build-users-group ''"
    )
    if arguments:
        command += " " + shlex.join(arguments)

    lines = [
        "set -eu",
        "unset LD_PRELOAD LD_LIBRARY_PATH",
        f"BOOT={quote(boot)}",
        f"S={quote(store)}",
        f"SHIM={quote(shim)}",
        f"VAR={quote(var)}",
        f"HOMEDIR={quote(home)}",
        f"GLIBC={quote(glibc)}",
        f"NIXPKG={quote(nix_package)}",
        f"CACERT={quote('/nix/store/' + ca_store + '/' + ca_rel)}",
        'test -d "$S" || { echo "nixp: store missing: $S" >&2; exit 69; }',
        'test -d "$SHIM" || { echo "nixp: shim directory missing: $SHIM" >&2; exit 69; }',
        'test -x "$S/$GLIBC/lib/ld-linux-aarch64.so.1" || { echo "nixp: locked glibc loader missing" >&2; exit 69; }',
        'test -x "$S/$NIXPKG/bin/nix" || { echo "nixp: locked Nix binary missing" >&2; exit 69; }',
        'test -r "$S/' + ca_store + '/' + ca_rel + '" || { echo "nixp: locked CA bundle missing" >&2; exit 69; }',
        'LP=/nix/store/shimlib',
        'for d in "$S"/*/lib; do [ -d "$d" ] || continue; LP="$LP:/nix/store/$(basename "$(dirname "$d")")/lib"; done',
        'export PROOT_TMP_DIR="$PREFIX/var/tmp" PROOT_NO_SECCOMP=1',
        'export PROOT_LOADER="$PREFIX/libexec/proot/loader" PROOT_LOADER_32="$PREFIX/libexec/proot/loader32"',
        'mkdir -p "$BOOT/tmp" "$HOMEDIR/.cache/nix/tarball-cache/objects" "$HOMEDIR/.cache/nix/tarball-cache/incoming"',
        'export HOME=/root USER=root TMPDIR="$BOOT/tmp" NIX_SSL_CERT_FILE="$CACERT"',
        'export NIX_STATE_DIR=/nix/var NIX_LOG_DIR=/nix/var/log/nix',
        command,
    ]
    return "\n".join(lines) + "\n"


def invoke(config: dict[str, Any], script: str) -> int:
    tt = expand_local(config["nix"]["tt"])
    if not tt.is_file() or not os.access(tt, os.X_OK):
        raise NixpError(f"configured tt launcher missing or not executable: {tt}")
    return subprocess.run([str(tt), script], check=False).returncode


def doctor(config_path: pathlib.Path) -> int:
    config = load_config(config_path)
    tt = expand_local(config["nix"]["tt"])
    report = {
        "schema": "ryznix.nixp-doctor/v1",
        "config": str(config_path),
        "tt": str(tt),
        "tt_executable": tt.is_file() and os.access(tt, os.X_OK),
        "store_identities_locked": True,
        "uses_proot": True,
        "scope": "nix-compatibility-only",
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["tt_executable"] else 1


def parser() -> argparse.ArgumentParser:
    default = pathlib.Path(os.environ.get("RYZNIX_CONFIG", "~/.config/ryznix/runtime.json")).expanduser()
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--config", type=pathlib.Path, default=default)
    value.add_argument("--render", action="store_true")
    value.add_argument("--doctor", action="store_true")
    value.add_argument("args", nargs=argparse.REMAINDER)
    return value


def main() -> int:
    args = parser().parse_args()
    try:
        config_path = args.config.expanduser().resolve()
        if args.doctor:
            return doctor(config_path)
        config = load_config(config_path)
        forwarded = args.args[1:] if args.args[:1] == ["--"] else args.args
        script = render_script(config, forwarded)
        if args.render:
            print(script, end="")
            return 0
        return invoke(config, script)
    except (NixpError, OSError) as exc:
        print(f"nixp: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
