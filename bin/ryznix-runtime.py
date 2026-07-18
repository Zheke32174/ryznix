#!/usr/bin/env python3
"""Typed local frontend for the rootless Ryznix Android runtime."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shlex
import subprocess
import sys
from typing import Any

SCHEMA = "ryznix.runtime/v1"
ALLOWED_KERNEL_ACTIONS = {"status", "heal", "route", "exec"}


class RuntimeError_(RuntimeError):
    pass


def expand_local_path(value: str) -> pathlib.Path:
    return pathlib.Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def require_remote_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.startswith("/") or any(ch in value for ch in "\n\r\0"):
        raise RuntimeError_(f"{label} must be an absolute remote path")
    return value.rstrip("/") or "/"


def load_config(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError_(
            f"runtime config not found: {path}; copy config/runtime.example.json and review every path"
        ) from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError_(f"invalid runtime config {path}: {exc}") from exc
    if not isinstance(value, dict) or value.get("schema") != SCHEMA:
        raise RuntimeError_(f"runtime config schema must be {SCHEMA}")
    if not isinstance(value.get("expected_uid"), int) or value["expected_uid"] < 1:
        raise RuntimeError_("expected_uid must be a positive integer")
    for key in ("tmp_root", "ubuntu_root", "busybox", "ryzkern", "run_dir"):
        require_remote_path(value.get(key), key)
    servers = value.get("servers")
    if not isinstance(servers, dict):
        raise RuntimeError_("servers must be an object")
    require_remote_path(servers.get("ds"), "servers.ds")
    require_remote_path(servers.get("pm"), "servers.pm")
    rish = value.get("rish")
    if not isinstance(rish, str) or not rish.strip():
        raise RuntimeError_("rish must be a local path")
    return value


def quote(value: object) -> str:
    return shlex.quote(str(value))


def render_boot(config: dict[str, Any]) -> str:
    tmp_root = require_remote_path(config["tmp_root"], "tmp_root")
    busybox = require_remote_path(config["busybox"], "busybox")
    run_dir = require_remote_path(config["run_dir"], "run_dir")
    ds = require_remote_path(config["servers"]["ds"], "servers.ds")
    pm = require_remote_path(config["servers"]["pm"], "servers.pm")
    ubuntu = require_remote_path(config["ubuntu_root"], "ubuntu_root")
    uid = config["expected_uid"]
    return "\n".join(
        [
            "set -eu",
            f"T={quote(tmp_root)}",
            f"BB={quote(busybox)}",
            f"RUN={quote(run_dir)}",
            f"U={quote(ubuntu)}",
            f"DS={quote(ds)}",
            f"PM={quote(pm)}",
            f"test \"$(id -u)\" = {quote(uid)} || {{ echo 'ryznix: unexpected Android uid' >&2; exit 77; }}",
            'test -x "$BB" || { echo "ryznix: busybox missing" >&2; exit 69; }',
            'test -x "$DS" || { echo "ryznix: ds-server missing" >&2; exit 69; }',
            'test -x "$PM" || { echo "ryznix: pm-server missing" >&2; exit 69; }',
            'test -x "$U/usr/bin/bash" || { echo "ryznix: Ubuntu bash missing" >&2; exit 69; }',
            '"$BB" mkdir -p "$RUN"',
            'if ! { ps -A 2>/dev/null || ps; } | "$BB" grep -q "[d]s-server"; then',
            '  "$BB" rm -f "$RUN/ds.req"',
            '  setsid sh -c "while true; do \"$DS\"; sleep 1; done" </dev/null >/dev/null 2>&1 &',
            "fi",
            'if ! { ps -A 2>/dev/null || ps; } | "$BB" grep -q "[p]m-server"; then',
            '  "$BB" rm -f "$RUN/pm.req"',
            '  setsid sh -c "while true; do \"$PM\"; sleep 1; done" </dev/null >/dev/null 2>&1 &',
            "fi",
            '"$BB" sleep 1',
            'export LD_LIBRARY_PATH="$T/lib:$T/termux/lib:$T/system/usr/lib"',
            'export PATH="$U/usr/local/bin:$U/usr/bin:$U/bin:$U/usr/sbin:$U/sbin:$T:$T/bin:$T/termux/bin:/system/bin:/system/xbin"',
            'export HOME="$U/root"',
            'export TERM="${TERM:-xterm-256color}"',
            '[ ! -f "$U/super-profile.sh" ] || . "$U/super-profile.sh"',
        ]
    )


def strip_separator(arguments: list[str]) -> list[str]:
    return arguments[1:] if arguments[:1] == ["--"] else arguments


def render_shell(config: dict[str, Any], command: list[str]) -> str:
    command = strip_separator(command)
    lines = [render_boot(config)]
    if command:
        command_text = shlex.join(command)
        lines.append(f'exec "$U/usr/bin/bash" --norc -c {quote(command_text)}')
    else:
        lines.extend(
            [
                "echo 'RYZNIX — rootless multi-runtime Android userspace'",
                "echo 'userspace control plane active; Android kernel remains authoritative'",
                'exec "$U/usr/bin/bash" --norc -i </dev/tty',
            ]
        )
    return "\n".join(lines) + "\n"


def validate_kernel_args(action: str, arguments: list[str]) -> list[str]:
    arguments = strip_separator(arguments)
    if action not in ALLOWED_KERNEL_ACTIONS:
        raise RuntimeError_(f"unsupported kernel action: {action}")
    if action in {"route", "exec"} and not arguments:
        raise RuntimeError_(f"kernel action {action} requires a target")
    if action in {"status", "heal"} and arguments:
        raise RuntimeError_(f"kernel action {action} accepts no extra arguments")
    return arguments


def render_kernel(config: dict[str, Any], action: str, arguments: list[str]) -> str:
    arguments = validate_kernel_args(action, arguments)
    executable = require_remote_path(config["ryzkern"], "ryzkern")
    return "exec " + shlex.join([executable, action, *arguments]) + "\n"


def invoke_rish(config: dict[str, Any], script: str) -> int:
    rish = expand_local_path(config["rish"])
    if not rish.is_file() or not os.access(rish, os.X_OK):
        raise RuntimeError_(f"rish launcher missing or not executable: {rish}")
    result = subprocess.run([str(rish)], input=script, text=True, check=False)
    return result.returncode


def doctor(config_path: pathlib.Path, remote: bool) -> int:
    config = load_config(config_path)
    rish = expand_local_path(config["rish"])
    report: dict[str, Any] = {
        "schema": "ryznix.doctor/v1",
        "config": str(config_path),
        "config_valid": True,
        "rish": str(rish),
        "rish_executable": rish.is_file() and os.access(rish, os.X_OK),
        "expected_uid": config["expected_uid"],
        "claims": config.get("claims", {}),
    }
    if remote:
        checks = [
            f"uid=$(id -u); test \"$uid\" = {quote(config['expected_uid'])}",
            f"test -x {quote(config['busybox'])}",
            f"test -x {quote(config['ryzkern'])}",
            f"test -x {quote(config['servers']['ds'])}",
            f"test -x {quote(config['servers']['pm'])}",
            f"test -x {quote(config['ubuntu_root'] + '/usr/bin/bash')}",
            "printf 'REMOTE_OK\\n'",
        ]
        result = subprocess.run(
            [str(rish)], input="set -eu\n" + "\n".join(checks) + "\n", text=True,
            check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) if report["rish_executable"] else None
        report["remote"] = {
            "attempted": True,
            "returncode": result.returncode if result else None,
            "ok": bool(result and result.returncode == 0 and "REMOTE_OK" in result.stdout),
            "stderr": result.stderr if result else "rish unavailable",
        }
    print(json.dumps(report, indent=2, sort_keys=True))
    healthy = report["rish_executable"] and (not remote or report.get("remote", {}).get("ok", False))
    return 0 if healthy else 1


def init_config(source: pathlib.Path, output: pathlib.Path) -> int:
    if output.exists():
        raise RuntimeError_(f"refusing to replace existing config: {output}")
    value = json.loads(source.read_text(encoding="utf-8"))
    if value.get("schema") != SCHEMA:
        raise RuntimeError_("bundled example config has an unexpected schema")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp-{os.getpid()}")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, output)
    print(output)
    return 0


def build_parser() -> argparse.ArgumentParser:
    root = pathlib.Path(__file__).resolve().parents[1]
    default_config = pathlib.Path(os.environ.get("RYZNIX_CONFIG", "~/.config/ryznix/runtime.json")).expanduser()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path, default=default_config)
    sub = parser.add_subparsers(dest="command", required=True)

    init_p = sub.add_parser("init-config")
    init_p.add_argument("--example", type=pathlib.Path, default=root / "config" / "runtime.example.json")
    init_p.add_argument("--output", type=pathlib.Path, default=default_config)

    doctor_p = sub.add_parser("doctor")
    doctor_p.add_argument("--remote", action="store_true")

    shell_p = sub.add_parser("shell")
    shell_p.add_argument("--render", action="store_true")
    shell_p.add_argument("args", nargs=argparse.REMAINDER)

    kernel_p = sub.add_parser("kernel")
    kernel_p.add_argument("--render", action="store_true")
    kernel_p.add_argument("action", choices=sorted(ALLOWED_KERNEL_ACTIONS))
    kernel_p.add_argument("args", nargs=argparse.REMAINDER)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "init-config":
            return init_config(args.example.resolve(), args.output.expanduser().resolve())
        config_path = args.config.expanduser().resolve()
        if args.command == "doctor":
            return doctor(config_path, args.remote)
        config = load_config(config_path)
        if args.command == "shell":
            script = render_shell(config, args.args)
            if args.render:
                print(script, end="")
                return 0
            return invoke_rish(config, script)
        if args.command == "kernel":
            script = render_kernel(config, args.action, args.args)
            if args.render:
                print(script, end="")
                return 0
            return invoke_rish(config, script)
    except (RuntimeError_, OSError, json.JSONDecodeError) as exc:
        print(f"ryznix: {exc}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
