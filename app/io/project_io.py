"""Save and load .hexmap project files."""

from __future__ import annotations

import json
import os

from app.hex.hex_grid_config import HexGridConfig
from app.layers.asset_layer import AssetLayer
from app.layers.background_layer import BackgroundImageLayer
from app.layers.border_layer import BorderLayer
from app.layers.draw_layer import DrawLayer
from app.layers.fill_layer import FillLayer
from app.layers.freeform_path_layer import FreeformPathLayer
from app.layers.hexside_layer import HexsideLayer
from app.layers.path_layer import PathLayer
from app.layers.sketch_layer import SketchLayer
from app.layers.text_layer import TextLayer
from app.models.project import Project


LAYER_TYPES = {
    "fill": FillLayer,
    "asset": AssetLayer,
    "background": BackgroundImageLayer,
    "border": BorderLayer,
    "draw": DrawLayer,
    "text": TextLayer,
    "hexside": HexsideLayer,
    "path": PathLayer,
    "freeform_path": FreeformPathLayer,
    "sketch": SketchLayer,
}


def save_project(project: Project, file_path: str) -> None:
    project_dir = os.path.dirname(os.path.abspath(file_path))

    # Pass project_dir to background layers so they can save edited PNGs
    for layer in project.layer_stack:
        if isinstance(layer, BackgroundImageLayer):
            layer.project_dir = project_dir

    layer_dicts = []
    for layer in project.layer_stack:
        d = layer.serialize()
        # Relativize file paths for portability
        if d.get("type") == "asset":
            for obj in d.get("objects", []):
                img = obj.get("image", "")
                if img and os.path.isabs(img):
                    try:
                        obj["image"] = os.path.relpath(img, project_dir)
                    except ValueError:
                        pass  # different drive on Windows
        elif d.get("type") == "background":
            img = d.get("image_path", "")
            if img and os.path.isabs(img):
                try:
                    d["image_path"] = os.path.relpath(img, project_dir)
                except ValueError:
                    pass
        layer_dicts.append(d)

    data = {
        "version": 1,
        "grid": project.grid_config.serialize(),
        "layers": layer_dicts,
    }

    # Atomic write: use a temp file then replace to avoid corrupting the
    # project file if the process is interrupted during writing.
    tmp_path = file_path + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, file_path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        raise

    project.file_path = file_path
    project.dirty = False


def load_project(file_path: str) -> Project:
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    project = Project()
    project.grid_config = HexGridConfig.deserialize(data.get("grid", {}))

    base_dir = os.path.dirname(os.path.abspath(file_path))

    for layer_data in data.get("layers", []):
        if not isinstance(layer_data, dict):
            continue
        layer_type = layer_data.get("type", "")
        cls = LAYER_TYPES.get(layer_type)
        if cls is None:
            continue

        # Resolve relative image paths
        if layer_type == "asset":
            for obj in layer_data.get("objects", []):
                img = obj.get("image", "")
                if img and not os.path.isabs(img):
                    obj["image"] = os.path.join(base_dir, img)
        elif layer_type == "background":
            img = layer_data.get("image_path", "")
            if img and not os.path.isabs(img):
                layer_data["image_path"] = os.path.join(base_dir, img)
            edit_img = layer_data.get("edited_image_path", "")
            if edit_img and not os.path.isabs(edit_img):
                layer_data["edited_image_path"] = os.path.join(base_dir, edit_img)

        layer = cls.deserialize(layer_data)
        project.layer_stack.add_layer(layer)

    project.file_path = file_path
    project.dirty = False
    return project
