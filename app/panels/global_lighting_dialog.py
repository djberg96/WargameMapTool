"""Non-modal dialog for configuring the global lighting tint and grain overlay."""

from __future__ import annotations

import random as _random

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QCheckBox, QColorDialog, QDialog, QGroupBox, QHBoxLayout,
    QLabel, QPushButton, QSlider, QSpinBox, QVBoxLayout,
)

from app.panels.tool_options.helpers import update_color_btn


class GlobalLightingDialog(QDialog):
    """Live-preview dialog to set a color tint and grain overlay over the hex map area."""

    def __init__(self, project, canvas, parent=None):
        super().__init__(parent, Qt.WindowType.Window)
        self.setWindowTitle("Global Lighting")
        self.setModal(False)
        self.setFixedWidth(300)

        self._project = project
        self._canvas = canvas

        cfg = project.grid_config

        root = QVBoxLayout(self)
        root.setContentsMargins(10, 10, 10, 10)
        root.setSpacing(8)

        # Enable toggle
        self._enable_cb = QCheckBox("Enable Global Lighting")
        self._enable_cb.setChecked(cfg.global_lighting_enabled)
        self._enable_cb.toggled.connect(self._on_enabled)
        root.addWidget(self._enable_cb)

        # --- Tint group ---
        grp = QGroupBox("Tint")
        gl = QVBoxLayout(grp)
        gl.setContentsMargins(8, 6, 8, 6)
        gl.setSpacing(6)

        # Color row
        color_row = QHBoxLayout()
        color_row.addWidget(QLabel("Color:"))
        self._color_btn = QPushButton()
        self._color_btn.setFixedSize(32, 32)
        update_color_btn(self._color_btn, cfg.global_lighting_color)
        self._color_btn.setToolTip("Pick tint color")
        self._color_btn.clicked.connect(self._on_pick_color)
        color_row.addWidget(self._color_btn)
        color_row.addStretch()
        gl.addLayout(color_row)

        # Opacity row
        opacity_row = QHBoxLayout()
        opacity_row.addWidget(QLabel("Opacity:"))
        self._opacity_slider = QSlider(Qt.Orientation.Horizontal)
        self._opacity_slider.setRange(0, 100)
        pct = int(round(cfg.global_lighting_opacity / 255 * 100))
        self._opacity_slider.setValue(pct)
        self._opacity_slider.valueChanged.connect(self._on_opacity)
        opacity_row.addWidget(self._opacity_slider, stretch=1)
        self._opacity_lbl = QLabel(f"{pct}%")
        self._opacity_lbl.setFixedWidth(36)
        opacity_row.addWidget(self._opacity_lbl)
        gl.addLayout(opacity_row)

        root.addWidget(grp)

        # --- Grain group ---
        grain_grp = QGroupBox("Grain")
        gg = QVBoxLayout(grain_grp)
        gg.setContentsMargins(8, 6, 8, 6)
        gg.setSpacing(6)

        # Enable checkbox
        self._grain_enable_cb = QCheckBox("Enable Grain")
        self._grain_enable_cb.setChecked(cfg.grain_enabled)
        self._grain_enable_cb.toggled.connect(self._on_grain_enabled)
        gg.addWidget(self._grain_enable_cb)

        # Intensity slider (0-100)
        intensity_row = QHBoxLayout()
        intensity_row.addWidget(QLabel("Intensity:"))
        self._grain_intensity_slider = QSlider(Qt.Orientation.Horizontal)
        self._grain_intensity_slider.setRange(0, 100)
        self._grain_intensity_slider.setValue(cfg.grain_intensity)
        self._grain_intensity_slider.valueChanged.connect(self._on_grain_intensity)
        intensity_row.addWidget(self._grain_intensity_slider, stretch=1)
        self._grain_intensity_lbl = QLabel(f"{cfg.grain_intensity}%")
        self._grain_intensity_lbl.setFixedWidth(36)
        intensity_row.addWidget(self._grain_intensity_lbl)
        gg.addLayout(intensity_row)

        # Scale slider (10-100 integer → 1.0-10.0 float)
        scale_row = QHBoxLayout()
        scale_row.addWidget(QLabel("Scale:"))
        self._grain_scale_slider = QSlider(Qt.Orientation.Horizontal)
        self._grain_scale_slider.setRange(10, 100)
        self._grain_scale_slider.setValue(int(round(cfg.grain_scale * 10)))
        self._grain_scale_slider.valueChanged.connect(self._on_grain_scale)
        scale_row.addWidget(self._grain_scale_slider, stretch=1)
        self._grain_scale_lbl = QLabel(f"{cfg.grain_scale:.1f}x")
        self._grain_scale_lbl.setFixedWidth(36)
        scale_row.addWidget(self._grain_scale_lbl)
        gg.addLayout(scale_row)

        # Monochrome checkbox
        self._grain_mono_cb = QCheckBox("Monochrome")
        self._grain_mono_cb.setChecked(cfg.grain_monochrome)
        self._grain_mono_cb.toggled.connect(self._on_grain_mono)
        gg.addWidget(self._grain_mono_cb)

        # Seed row with Randomize button
        seed_row = QHBoxLayout()
        seed_row.addWidget(QLabel("Seed:"))
        self._grain_seed_spin = QSpinBox()
        self._grain_seed_spin.setRange(0, 999999)
        self._grain_seed_spin.setValue(cfg.grain_seed)
        self._grain_seed_spin.valueChanged.connect(self._on_grain_seed)
        seed_row.addWidget(self._grain_seed_spin)
        randomize_btn = QPushButton("Randomize")
        randomize_btn.clicked.connect(self._on_grain_randomize)
        seed_row.addWidget(randomize_btn)
        seed_row.addStretch()
        gg.addLayout(seed_row)

        root.addWidget(grain_grp)

        # Close button
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.close)
        root.addWidget(close_btn, alignment=Qt.AlignmentFlag.AlignRight)

    # ------------------------------------------------------------------
    # Tint slots
    # ------------------------------------------------------------------

    def _on_enabled(self, checked: bool) -> None:
        self._project.grid_config.global_lighting_enabled = checked
        self._project.dirty = True
        self._canvas.update()

    def _on_pick_color(self) -> None:
        color = QColorDialog.getColor(
            self._project.grid_config.global_lighting_color, self, "Lighting Tint Color"
        )
        if color.isValid():
            self._project.grid_config.global_lighting_color = color
            update_color_btn(self._color_btn, color)
            self._project.dirty = True
            self._canvas.update()

    def _on_opacity(self, v: int) -> None:
        self._opacity_lbl.setText(f"{v}%")
        self._project.grid_config.global_lighting_opacity = int(round(v / 100 * 255))
        self._project.dirty = True
        self._canvas.update()

    # ------------------------------------------------------------------
    # Grain slots
    # ------------------------------------------------------------------

    def _on_grain_enabled(self, checked: bool) -> None:
        self._project.grid_config.grain_enabled = checked
        self._project.dirty = True
        self._canvas.update()

    def _on_grain_intensity(self, v: int) -> None:
        self._grain_intensity_lbl.setText(f"{v}%")
        self._project.grid_config.grain_intensity = v
        self._project.dirty = True
        self._canvas.update()

    def _on_grain_scale(self, v: int) -> None:
        scale = v / 10.0
        self._grain_scale_lbl.setText(f"{scale:.1f}x")
        self._project.grid_config.grain_scale = scale
        self._project.dirty = True
        self._canvas.update()

    def _on_grain_mono(self, checked: bool) -> None:
        self._project.grid_config.grain_monochrome = checked
        self._project.dirty = True
        self._canvas.update()

    def _on_grain_seed(self, v: int) -> None:
        self._project.grid_config.grain_seed = v
        self._project.dirty = True
        self._canvas.update()

    def _on_grain_randomize(self) -> None:
        new_seed = _random.randint(0, 999999)
        self._grain_seed_spin.setValue(new_seed)
