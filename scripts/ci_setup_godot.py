"""Download a pinned official Godot editor and matching export templates."""
from pathlib import Path
import os
import platform
import shutil
import urllib.request
import zipfile

version = "4.7.2"
base = f"https://github.com/godotengine/godot/releases/download/{version}-stable/"
cache = Path.home() / ".codis-godot"
cache.mkdir(exist_ok=True)
system = platform.system()
asset = {"Windows": "win64.exe.zip", "Linux": "linux.x86_64.zip", "Darwin": "macos.universal.zip"}[system]
editor = cache / "editor.zip"
urllib.request.urlretrieve(base + f"Godot_v{version}-stable_{asset}", editor)
with zipfile.ZipFile(editor) as archive:
    archive.extractall(cache)
if system == "Darwin":
    executable = cache / "Godot.app/Contents/MacOS/Godot"
else:
    executable = next(cache.glob("Godot_*" + (".exe" if system == "Windows" else ".x86_64")))
executable.chmod(0o755)
if system == "Windows":
    dest = Path(os.environ["APPDATA"]) / "Godot/export_templates"
elif system == "Darwin":
    dest = Path.home() / "Library/Application Support/Godot/export_templates"
else:
    dest = Path.home() / ".local/share/godot/export_templates"
templates = cache / "templates.tpz"
urllib.request.urlretrieve(base + f"Godot_v{version}-stable_export_templates.tpz", templates)
with zipfile.ZipFile(templates) as archive:
    archive.extractall(cache / "export")
shutil.copytree(cache / "export/templates", dest / f"{version}.stable", dirs_exist_ok=True)
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
    env.write(f"GODOT_BIN={executable}\n")
