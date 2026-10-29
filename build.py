"""Build the mod into a .pak (and optionally a .zip) using LSLib's Divine.exe.

Settings are read from build_config.yaml next to this script.

Usage:
    python build.py
    python build.py --config other_config.yaml
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent


def load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}

    for key in ("divine_path", "mod_folder", "output_dir"):
        if not config.get(key):
            sys.exit(f"Missing '{key}' in {path}")

    config.setdefault("compression", "lz4")
    config.setdefault("create_zip", True)
    return config


def resolve(path_str: str, base: Path) -> Path:
    path = Path(path_str)
    return path if path.is_absolute() else (base / path).resolve()


def run_divine(divine: Path, *args: str) -> None:
    cmd = [str(divine), "--game", "bg3", *args]
    print("Running:", " ".join(f'"{c}"' if " " in c else c for c in cmd))
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.exit(f"Divine.exe failed with exit code {result.returncode}")


def stage(divine: Path, source: Path, staging: Path) -> Path:
    """Copy the mod to a staging folder and convert Localization/*.xml to the game's .loca format."""
    staged = staging / source.name
    shutil.copytree(source, staged)
    for xml in (staged / "Localization").rglob("*.xml"):
        loca = xml.with_suffix(".loca")
        run_divine(divine, "--action", "convert-loca", "--source", str(xml), "--destination", str(loca))
        if not loca.is_file():
            sys.exit(f"Divine.exe did not create {loca}")
        xml.unlink()
    return staged


def build_pak(divine: Path, source: Path, pak: Path, compression: str) -> None:
    run_divine(divine, "--action", "create-package", "--source", str(source),
               "--destination", str(pak), "--compression-method", compression)
    if not pak.is_file():
        sys.exit(f"Divine.exe finished but {pak} was not created")


def build_zip(pak: Path) -> Path:
    zip_path = pak.with_suffix(".zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(pak, arcname=pak.name)
    return zip_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the mod .pak with Divine.exe")
    parser.add_argument(
        "--config",
        type=Path,
        default=ROOT / "build_config.yaml",
        help="Path to the build config YAML (default: build_config.yaml)",
    )
    args = parser.parse_args()

    config_path = args.config.resolve()
    config = load_config(config_path)
    base = config_path.parent

    divine = resolve(config["divine_path"], base)
    source = resolve(config["mod_folder"], base)
    output_dir = resolve(config["output_dir"], base)

    if not divine.is_file():
        sys.exit(f"Divine.exe not found at: {divine}")
    if not source.is_dir():
        sys.exit(f"Mod folder not found at: {source}")

    output_dir.mkdir(parents=True, exist_ok=True)
    pak = output_dir / f"{source.name}.pak"

    with tempfile.TemporaryDirectory() as staging:
        staged = stage(divine, source, Path(staging))
        build_pak(divine, staged, pak, str(config["compression"]))
    print(f"Built {pak} ({pak.stat().st_size} bytes)")

    if config["create_zip"]:
        zip_path = build_zip(pak)
        print(f"Built {zip_path}")


if __name__ == "__main__":
    main()
