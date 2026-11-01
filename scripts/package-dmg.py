#!/usr/bin/env python3
"""Build a versioned drag-to-install DMG without changing previous installers."""
import hashlib
import os
import platform
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def main():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("The release installer requires Apple Silicon macOS.")
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Invalid VERSION")
    destination = ROOT / "dist" / f"Archaive-{version}-arm64.dmg"
    checksum_file = Path(str(destination) + ".sha256")
    if destination.exists() or checksum_file.exists():
        raise SystemExit(f"Refusing to replace {destination.name}; bump VERSION first.")

    run(ROOT / "scripts/build.sh")
    app = ROOT / "dist/Archaive.app"
    with (app / "Contents/Info.plist").open("rb") as file:
        assert plistlib.load(file)["CFBundleShortVersionString"] == version
    run("codesign", "--verify", "--deep", "--strict", app)
    python = ROOT / ".build/dmg-venv/bin/python"
    if not python.exists():
        run("python3", "-m", "venv", python.parent.parent)
    run(python, "-m", "pip", "install", "--disable-pip-version-check",
        "-r", ROOT / "scripts/requirements-dmg.txt")

    with tempfile.TemporaryDirectory(prefix=".dmg-stage-", dir=ROOT / "dist") as temp:
        stage = Path(temp)
        renderer = stage / "dmg-background"
        background = stage / "background.tiff"
        run("xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=13.0",
            "-framework", "AppKit", ROOT / "scripts/dmg-background.m", "-o", renderer)
        run(renderer, background)
        image = stage / destination.name
        run(python, "-m", "dmgbuild", "-s", ROOT / "scripts/dmg-settings.py",
            "-D", f"app={app}", "-D", f"background={background}",
            "-D", f"icon={app / 'Contents/Resources/Archaive.icns'}", "Archaive", image)
        run("hdiutil", "verify", image)
        digest = hashlib.sha256()
        with image.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)
        # Hard linking fails if a destination appeared during the build.
        os.link(image, destination)
        with checksum_file.open("x") as file:
            file.write(f"{digest.hexdigest()}  {destination.name}\n")
        print(f"Created {destination}\nSHA-256: {digest.hexdigest()}")


if __name__ == "__main__":
    main()
