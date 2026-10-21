#!/usr/bin/env python3
"""Embed UxPlay and the GStreamer runtime used by the app into a macOS bundle."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


PLUGINS = (
    "libgstapp.dylib",
    "libgstaudiofx.dylib",
    "libgstaudioconvert.dylib",
    "libgstaudioresample.dylib",
    "libgstautodetect.dylib",
    "libgstcoreelements.dylib",
    "libgstlevel.dylib",
    "libgstlibav.dylib",
    "libgstosxaudio.dylib",
    "libgstplayback.dylib",
    "libgstrtp.dylib",
    "libgsttypefindfunctions.dylib",
    "libgstudp.dylib",
    "libgstvideoconvertscale.dylib",
    "libgstvideoparsersbad.dylib",
    "libgstvolume.dylib",
)


def run(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def dependencies(binary: Path) -> list[str]:
    output = run("otool", "-L", str(binary))
    items = [line.strip().split(" (compatibility version", 1)[0]
             for line in output.splitlines()[1:] if line.strip()]
    install_id = run("otool", "-D", str(binary)).splitlines()
    if len(install_id) > 1:
        items = [item for item in items if item != install_id[1].strip()]
    return items


def rpaths(binary: Path) -> list[str]:
    output = run("otool", "-l", str(binary))
    return re.findall(r"\s+path (.+?) \(offset \d+\)", output)


def set_rpath(binary: Path, wanted: str) -> None:
    for existing in rpaths(binary):
        if existing.startswith("/"):
            run("install_name_tool", "-delete_rpath", existing, str(binary))
    if wanted not in rpaths(binary):
        run("install_name_tool", "-add_rpath", wanted, str(binary))


def set_library_id(binary: Path, name: str) -> None:
    output = run("otool", "-D", str(binary)).splitlines()
    if len(output) > 1 and output[1].strip():
        run("install_name_tool", "-id", f"@rpath/{name}", str(binary))


def minimum_os(binary: Path) -> tuple[int, ...] | None:
    output = run("vtool", "-show-build", str(binary))
    versions = re.findall(r"\bminos (\d+(?:\.\d+){1,2})", output)
    return max((tuple(map(int, version.split("."))) for version in versions), default=None)


def bundle(args: argparse.Namespace) -> None:
    app = args.app.resolve()
    contents = app / "Contents"
    executable = contents / "MacOS/iPhoneMirroring15"
    helpers = contents / "Helpers"
    frameworks = contents / "Frameworks"
    plugins = contents / "PlugIns/GStreamer"
    licenses = contents / "Resources/ThirdPartyLicenses"
    uxplay_source = args.uxplay.resolve()
    scanner_source = args.plugin_scanner.resolve()

    for path in (executable, uxplay_source, scanner_source, args.uxplay_license.resolve()):
        if not path.is_file():
            raise FileNotFoundError(f"Required runtime file not found: {path}")
    if not os.access(uxplay_source, os.X_OK) or not os.access(scanner_source, os.X_OK):
        raise PermissionError("UxPlay and the GStreamer plugin scanner must be executable")

    for directory in (frameworks, helpers, plugins):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True, exist_ok=True)
    licenses.mkdir(parents=True, exist_ok=True)
    uxplay = helpers / "uxplay"
    scanner = helpers / "gst-plugin-scanner"
    shutil.copy2(uxplay_source, uxplay)
    shutil.copy2(scanner_source, scanner)
    shutil.copy2(args.uxplay_license, licenses / "UxPlay-GPL-3.0.txt")

    queue: list[tuple[Path, Path, str]] = [
        (executable, executable, "@executable_path/../Frameworks"),
        (uxplay, uxplay, "@executable_path/../Frameworks"),
        (scanner, scanner, "@executable_path/../Frameworks"),
    ]
    for filename in PLUGINS:
        source = args.plugin_dir / filename
        if not source.is_file():
            raise FileNotFoundError(f"Required GStreamer plugin not found: {source}")
        destination = plugins / filename
        shutil.copy2(source, destination)
        queue.append((source, destination, "@loader_path/../../Frameworks"))

    bundled: dict[str, Path] = {}
    processed: set[Path] = set()
    while queue:
        source, destination, runpath = queue.pop()
        destination = destination.resolve()
        if destination in processed:
            continue
        processed.add(destination)
        set_rpath(destination, runpath)
        if destination.suffix == ".dylib":
            set_library_id(destination, destination.name)

        for dependency in dependencies(destination):
            if dependency.startswith(("/System/Library/", "/usr/lib/", "@")):
                continue
            dependency_path = Path(dependency)
            if not dependency_path.is_file():
                raise FileNotFoundError(f"Cannot bundle {dependency} required by {destination}")
            name = dependency_path.name
            framework_copy = frameworks / name
            resolved = dependency_path.resolve()
            previous = bundled.get(name)
            if previous is not None and previous != resolved:
                raise RuntimeError(f"Two different libraries use the install name {name}")
            if previous is None:
                bundled[name] = resolved
                shutil.copy2(dependency_path, framework_copy)
                queue.append((dependency_path, framework_copy, "@loader_path"))
            run("install_name_tool", "-change", dependency, f"@rpath/{name}", str(destination))

    # Confirm no bundled Mach-O still depends on a package-manager install path.
    binaries = [executable, uxplay, scanner, *frameworks.glob("*.dylib"), *plugins.glob("*.dylib")]
    for binary in binaries:
        for dependency in dependencies(binary):
            if dependency.startswith("/") and not dependency.startswith(("/System/Library/", "/usr/lib/")):
                raise RuntimeError(f"Unbundled dependency remains in {binary}: {dependency}")
            if dependency.startswith("@rpath/") and not (frameworks / dependency.removeprefix("@rpath/")).exists():
                raise RuntimeError(f"Bundled dependency is missing: {dependency} required by {binary}")

    versions = [minimum_os(binary) for binary in binaries]
    runtime_minimum = max((version for version in versions if version is not None), default=None)
    if runtime_minimum:
        info_path = contents / "Info.plist"
        with info_path.open("rb") as info_file:
            info = plistlib.load(info_file)
        info["LSMinimumSystemVersion"] = ".".join(map(str, runtime_minimum))
        with info_path.open("wb") as info_file:
            plistlib.dump(info, info_file, sort_keys=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--uxplay", type=Path, required=True)
    parser.add_argument("--plugin-dir", type=Path, required=True)
    parser.add_argument("--plugin-scanner", type=Path, required=True)
    parser.add_argument("--uxplay-license", type=Path, required=True)
    try:
        bundle(parser.parse_args())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Runtime bundling failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
