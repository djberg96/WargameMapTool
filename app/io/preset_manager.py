"""Grid config preset management - save/load/delete presets."""

from __future__ import annotations

import json
import os

from app.hex.hex_grid_config import HexGridConfig
from app.io.user_data import get_builtin_presets_dir, get_presets_dir


def _sanitize_name(name: str) -> str:
    """Strip path separators and dots to prevent directory traversal."""
    return name.replace("/", "_").replace("\\", "_").replace("..", "_").strip()


def _resolve_preset_path(name: str, *dirs: str | None) -> str | None:
    """Find a preset JSON file, tolerating whitespace in filenames."""
    for d in dirs:
        if not d or not os.path.isdir(d):
            continue
        exact = os.path.join(d, f"{name}.json")
        if os.path.exists(exact):
            return exact
        for f in os.listdir(d):
            if f.endswith(".json") and f[:-5].strip() == name:
                return os.path.join(d, f)
    return None


def list_presets() -> list[str]:
    """Return sorted list of preset names (without .json extension)."""
    names: set[str] = set()
    for d in (get_presets_dir(), get_builtin_presets_dir("grid")):
        if d and os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json"):
                    names.add(f[:-5].strip())
    return sorted(names)


def save_preset(name: str, config: HexGridConfig) -> None:
    """Save config as preset. Overwrites existing."""
    name = _sanitize_name(name)
    path = os.path.join(get_presets_dir(), f"{name}.json")
    data = config.serialize()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def load_preset(name: str) -> HexGridConfig:
    """Load preset by name. Checks user dir first, then built-in."""
    name = _sanitize_name(name)
    path = _resolve_preset_path(name, get_presets_dir(), get_builtin_presets_dir("grid"))
    if path:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return HexGridConfig.deserialize(data)
    raise FileNotFoundError(f"Preset '{name}' not found")


def delete_preset(name: str) -> bool:
    """Delete a preset file from user dir. Returns False if built-in only."""
    name = _sanitize_name(name)
    path = _resolve_preset_path(name, get_presets_dir())
    if path:
        os.remove(path)
        return True
    return False


def is_builtin_preset(name: str) -> bool:
    """Check if a preset exists only as a built-in (not in user dir)."""
    name = _sanitize_name(name)
    if _resolve_preset_path(name, get_presets_dir()):
        return False
    return _resolve_preset_path(name, get_builtin_presets_dir("grid")) is not None
