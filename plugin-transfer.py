#!/usr/bin/env python3
"""Back up installed profile bundles; restore through the supported dsh CLI.

The archive contains plugin packages, not node_modules or host packages.
Dependencies are resolved by the destination package manager and may need network.
Desktop restoration requires the Desktop-installed CLI and a fully quit app.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shlex
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone

FORMAT = 1
HOME = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def safe_relative(value):
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise ValueError(f"Invalid archive path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in (".", "..") for p in value.split("/")):
        raise ValueError(f"Unsafe archive path: {value!r}")
    return path


def package_tar(root):
    """Archive installed files without running npm lifecycle scripts or packing peers."""
    root = root.resolve()
    output = io.BytesIO()
    native = False
    with tarfile.open(fileobj=output, mode="w:gz") as tar:
        for directory, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = sorted(d for d in dirs if d not in ("node_modules", ".git"))
            for name in dirs:
                if (Path(directory) / name).is_symlink():
                    raise ValueError(f"Package directory symlink cannot be migrated: {Path(directory) / name}")
            for name in sorted(files):
                file = Path(directory) / name
                if file.is_symlink():
                    raise ValueError(f"Package file symlink cannot be migrated: {file}")
                native |= file.suffix.lower() in (".node", ".dll", ".exe", ".dylib", ".so")
                tar.add(file, arcname="package/" + file.relative_to(root).as_posix(), recursive=False)
    return output.getvalue(), native


def backup(args):
    profiles = HOME / "profiles"
    result = {"format": FORMAT, "createdAt": datetime.now(timezone.utc).isoformat(),
              "platform": sys.platform, "machine": platform.machine(), "profiles": []}
    payloads = {}
    directories = [profiles / args.profile] if args.profile else sorted(profiles.iterdir())
    for directory in directories:
        manifest_path = directory / "package.json"
        if not manifest_path.is_file():
            if args.profile:
                raise ValueError(f"Initialize profile first: {directory.name}")
            continue
        manifest = read_json(manifest_path)
        dependencies = manifest.get("dependencies", {})
        bundles = manifest.get("dsh", {}).get("profile", {}).get("bundles", [])
        records = []
        for name in sorted(dependencies):
            safe_relative(name)
            root = directory / "node_modules" / name
            installed = read_json(root / "package.json")
            if not installed.get("dsh", {}).get("bundle"):
                print(f"Skip non-bundle dependency: {name}")
                continue
            if installed.get("name") != name:
                raise ValueError(f"Installed package identity mismatch: {name}")
            # Host packages must come from the destination Harness, never the backup.
            if name == "@deepseek-ai/dsh" or name.startswith("@deepseek-ai/dsh-"):
                raise ValueError(f"Host package in profile dependencies; not portable: {name}")
            filename = "packages/" + digest((directory.name + "/" + name).encode()) + ".tgz"
            data, native = package_tar(root)
            payloads[filename] = data
            records.append({"name": name, "version": installed["version"], "archive": filename,
                            "sha256": digest(data), "enabled": name in bundles, "native": native})
        if records:
            order = [name for name in bundles if name in {r["name"] for r in records}]
            result["profiles"].append({"name": directory.name, "order": order, "plugins": records})
    if not result["profiles"]:
        raise ValueError("No installed external plugin bundles found")
    output = Path(args.out).expanduser().resolve() if args.out else HOME.parent / "dsh-backups"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ("dsh-plugins-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zip:
        zip.writestr("manifest.json", json.dumps(result, ensure_ascii=False, indent=2))
        for name, data in payloads.items():
            zip.writestr(name, data)
    archive.chmod(0o600)
    print(f"Plugin backup: {archive}")
    for profile in result["profiles"]:
        print(profile["name"] + ": " + ", ".join(r["name"] + "@" + r["version"] for r in profile["plugins"]))
    print("Contains plugin code only; configuration, plugin-owned data and dependencies are NOT included.")
    return archive


def validate(archive):
    """Validate every member before writing extracted packages or starting installation."""
    with zipfile.ZipFile(archive) as zip:
        names = zip.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate ZIP members")
        manifest = json.loads(zip.read("manifest.json"))
        if manifest.get("format") != FORMAT:
            raise ValueError("Unsupported plugin backup format")
        expected = {"manifest.json"}
        seen_profiles = set()
        payloads = {}
        for profile in manifest["profiles"]:
            profile_name = profile["name"]
            safe_relative(profile_name)
            if "/" in profile_name or profile_name in seen_profiles:
                raise ValueError("Invalid or duplicate profile name")
            seen_profiles.add(profile_name)
            seen = set()
            for record in profile["plugins"]:
                name = record["name"]
                safe_relative(name)
                if name in seen or name.startswith("@deepseek-ai/dsh-") or name == "@deepseek-ai/dsh":
                    raise ValueError(f"Duplicate or host package: {name}")
                seen.add(name)
                path = record["archive"]
                safe_relative(path)
                if not path.startswith("packages/") or path in expected:
                    raise ValueError("Invalid package member")
                expected.add(path)
                data = zip.read(path)
                if digest(data) != record["sha256"]:
                    raise ValueError(f"Package checksum mismatch: {name}")
                with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
                    paths = set()
                    package_manifest = None
                    for member in tar.getmembers():
                        safe_relative(member.name)
                        if not member.name.startswith("package/") or not member.isfile() or member.name in paths:
                            raise ValueError(f"Unsafe package member: {member.name}")
                        paths.add(member.name)
                        if member.name == "package/package.json":
                            package_manifest = json.load(tar.extractfile(member))
                    if not package_manifest or package_manifest.get("name") != name or package_manifest.get("version") != record["version"]:
                        raise ValueError(f"Package identity mismatch: {name}")
                    if not package_manifest.get("dsh", {}).get("bundle"):
                        raise ValueError(f"Not a Harness bundle: {name}")
                payloads[path] = data
            if len(profile["order"]) != len(set(profile["order"])) or set(profile["order"]) != {r["name"] for r in profile["plugins"] if r["enabled"]}:
                raise ValueError("Invalid enabled bundle order")
        if set(names) != expected or not seen_profiles:
            raise ValueError("Unexpected ZIP members or empty backup")
    return manifest, payloads


def restore(args):
    manifest, payloads = validate(Path(args.archive).expanduser().resolve())
    selected = [p for p in manifest["profiles"] if not args.profile or p["name"] == args.profile]
    if not selected:
        raise ValueError("Requested profile is absent from archive")
    destination = Path(args.staging).expanduser().resolve() if args.staging else HOME.parent / ("dsh-plugin-restore-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    if destination.exists():
        raise ValueError(f"Use a new staging directory: {destination}")
    commands = []
    for profile in selected:
        by_name = {r["name"]: r for r in profile["plugins"]}
        ordered = profile["order"] + sorted(n for n in by_name if n not in profile["order"])
        for name in ordered:
            record = by_name[name]
            if record["native"] and (manifest["platform"] != sys.platform or manifest["machine"] != platform.machine()):
                raise ValueError(f"Native package requires matching OS/architecture: {name}")
            package = destination / record["archive"]
            commands.append((profile["name"], record, package))
    destination.mkdir(parents=True)
    for profile, record, package in commands:
        package.parent.mkdir(parents=True, exist_ok=True)
        package.write_bytes(payloads[record["archive"]])
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    instructions = ["请通过当前应用的 plugin_manager 恢复以下本地插件归档。",
                    "先确认当前 profile 与清单一致；不要直接编辑 profile 文件或运行 pnpm。",
                    "先列出已安装 bundle，再按顺序 install_bundle；保留其他插件。",
                    "不要自动授予版本豁免或批准构建脚本；失败时停止并报告。"]
    for profile, record, package in commands:
        instructions.append(f"profile={profile}: {record['name']}@{record['version']}; target={package}; enabled={str(record['enabled']).lower()}")
    instructions.append("安装后检查运行时插件条目与界面功能；本清单不恢复用户配置或插件自己的数据。")
    (destination / "INSTALL-IN-APP.txt").write_text("\n".join(instructions) + "\n", encoding="utf-8")
    print(f"Validated packages extracted to: {destination}")
    print(f"Development Desktop install instructions: {destination / 'INSTALL-IN-APP.txt'}")
    print("Keep this directory: installed local tarball sources may be needed for later reinstalls.")
    print("Dependencies may require network. No host files, profile manifests, configuration or exemptions are copied.")
    print("For development Desktop: add each .tgz using the application's plugin manager; keep disabled plugins disabled.")
    for profile, record, package in commands:
        command = [args.cli or "dsh", "plugin", "--profile", profile, "add", str(package), "--ignore-scripts"]
        print(subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command))
    if not args.cli:
        print("Preparation only. Supply --cli <dsh executable> to install (Desktop requires its installed carrier CLI; quit Desktop first).")
        return destination
    if not args.app_closed:
        raise ValueError("Quit the target Harness and pass --app-closed before CLI installation")
    if any(not record["enabled"] for _, record, _ in commands):
        raise ValueError("Backup includes disabled bundles. Use application plugin manager to restore their enable states; CLI auto-restore refused.")
    child_env = {**os.environ, "DSH_HOME": str(HOME)}
    for profile, record, package in commands:
        subprocess.run([args.cli, "plugin", "--profile", profile, "add", str(package), "--ignore-scripts"], env=child_env, check=True)
    print("Installation commands succeeded. Existing plugins are retained; existing bundle order is not overwritten. Restart and verify in Plugins.")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    back = subs.add_parser("backup")
    back.add_argument("--out")
    back.add_argument("--profile")
    rest = subs.add_parser("restore")
    rest.add_argument("archive")
    rest.add_argument("--profile")
    rest.add_argument("--staging")
    rest.add_argument("--cli", help="Exact supported dsh executable; never a source CLI for desktop")
    rest.add_argument("--app-closed", action="store_true", help="Confirm target Harness is fully quit")
    args = parser.parse_args()
    try:
        (backup if args.action == "backup" else restore)(args)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, tarfile.TarError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Plugin transfer failed: {error}\n")


if __name__ == "__main__":
    main()
