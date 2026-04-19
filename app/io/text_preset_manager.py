"""Text style preset management - save/load/delete named text presets."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

from app.io.user_data import get_builtin_presets_dir, get_text_presets_dir


@dataclass
class TextPreset:
    """A named collection of text style settings."""

    name: str
    font_family: str = "Arial"
    font_size: float = 12.0
    bold: bool = False
    italic: bool = False
    underline: bool = False
    color: str = "#000000"
    alignment: str = "left"
    opacity: float = 1.0
    rotation: float = 0.0
    outline: bool = False
    outline_color: str = "#ffffff"
    outline_width: float = 1.0
    over_grid: bool = False

    def serialize(self) -> dict:
        return {
            "name": self.name,
            "font_family": self.font_family,
            "font_size": self.font_size,
            "bold": self.bold,
            "italic": self.italic,
            "underline": self.underline,
            "color": self.color,
            "alignment": self.alignment,
            "opacity": self.opacity,
            "rotation": self.rotation,
            "outline": self.outline,
            "outline_color": self.outline_color,
            "outline_width": self.outline_width,
            "over_grid": self.over_grid,
        }

    @classmethod
    def deserialize(cls, data: dict) -> TextPreset:
        return cls(
            name=data.get("name", "Unnamed"),
            font_family=data.get("font_family", "Arial"),
            font_size=data.get("font_size", 12.0),
            bold=data.get("bold", False),
            italic=data.get("italic", False),
            underline=data.get("underline", False),
            color=data.get("color", "#000000"),
            alignment=data.get("alignment", "left"),
            opacity=data.get("opacity", 1.0),
            rotation=data.get("rotation", 0.0),
            outline=data.get("outline", False),
            outline_color=data.get("outline_color", "#ffffff"),
            outline_width=data.get("outline_width", 1.0),
            over_grid=data.get("over_grid", False),
        )


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


def list_text_presets() -> list[str]:
    """Return sorted list of text preset names (without .json extension)."""
    names: set[str] = set()
    for d in (get_text_presets_dir(), get_builtin_presets_dir("text")):
        if d and os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json"):
                    names.add(f[:-5].strip())
    return sorted(names)


def save_text_preset(preset: TextPreset) -> None:
    """Save text preset to disk. Overwrites existing."""
    name = _sanitize_name(preset.name)
    path = os.path.join(get_text_presets_dir(), f"{name}.json")
    data = preset.serialize()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def load_text_preset(name: str) -> TextPreset:
    """Load text preset by name. Checks user dir first, then built-in."""
    name = _sanitize_name(name)
    path = _resolve_preset_path(name, get_text_presets_dir(), get_builtin_presets_dir("text"))
    if path:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return TextPreset.deserialize(data)
    raise FileNotFoundError(f"Text preset '{name}' not found")


def delete_text_preset(name: str) -> bool:
    """Delete a text preset file from user dir. Returns False if built-in only."""
    name = _sanitize_name(name)
    path = _resolve_preset_path(name, get_text_presets_dir())
    if path:
        os.remove(path)
        return True
    return False


def is_builtin_text_preset(name: str) -> bool:
    """Check if a preset exists only as a built-in (not in user dir)."""
    name = _sanitize_name(name)
    if _resolve_preset_path(name, get_text_presets_dir()):
        return False
    return _resolve_preset_path(name, get_builtin_presets_dir("text")) is not None
