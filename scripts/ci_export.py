"""Prepare a clean CI checkout and export a platform app."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("platform", choices=["Windows", "Linux", "macOS", "Android", "iOS", "Web"])
parser.add_argument("--godot", default="godot")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
os.chdir(root)
# Ziva is optional editor tooling, not a runtime dependency.
shutil.rmtree(root / "addons/ziva_agent", ignore_errors=True)
serial = root / "addons/codis_serial"
manifest = serial / "codis_serial.gdextension"
if args.platform in ("Web", "iOS"):
    manifest.unlink(missing_ok=True)
else:
    shutil.copyfile(serial / "codis_serial.gdextension.example", manifest)
paths = {"Windows": "windows/CodisIDE.exe", "Linux": "linux/CodisIDE.x86_64",
         "macOS": "macos/CodisIDE.zip", "Android": "android/CodisIDE.apk",
         "iOS": "ios/CodisIDE.zip", "Web": "web/index.html"}
out = root / "dist" / paths[args.platform]
out.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([args.godot, "--headless", "--editor", "--import", "--path", str(root)], check=True)
subprocess.run([args.godot, "--headless", "--path", str(root), "--export-release", args.platform, str(out)], check=True)
if not out.is_file():
    raise SystemExit(f"Export did not create {out}")
