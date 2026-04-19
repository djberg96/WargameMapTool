"""Dialog for procedural random map generation."""

from __future__ import annotations

import random as _random_mod

from PySide6.QtCore import QPointF, QSize, Qt
from PySide6.QtGui import QColor, QIcon, QPainter, QPen, QPixmap, QPolygonF
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSlider,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from app.commands.command_stack import CommandStack
from app.commands.random_map_commands import RandomMapCommand
from app.generation.random_map_generator import (
    GeneratorSettings,
    MapGenerationResult,
    TerrainColors,
    generate_map,
)
from app.hex.hex_math import Hex, hex_corners, hex_to_pixel
from app.hex.hex_grid_config import HexGridConfig
from app.io.palette_manager import ColorPalette, list_palettes, load_palette
from app.io.texture_library import LibraryTexture, load_catalog
from app.layers.fill_layer import FillLayer, HexTexture
from app.models.project import Project


# ---------------------------------------------------------------------------
# Terrain role auto-assignment keywords
# ---------------------------------------------------------------------------
_ROLE_KEYWORDS: dict[str, list[str]] = {
    "ground": ["ground", "open", "plains", "grass", "field"],
    "hill1":  ["hill_1", "hill1", "low_hill"],
    "hill2":  ["hill_2", "hill2", "mid_hill"],
    "hill3":  ["hill_3", "hill3", "high_hill", "mountain"],
    "water":  ["water", "sea", "lake", "ocean"],
    "forest": ["forest", "wood", "bocage", "jungle", "orchard", "tree"],
}

# Default terrain colors (fallback when no palette match)
_DEFAULT_COLORS: dict[str, str] = {
    "ground": "#94ae5c",
    "hill1":  "#c88256",
    "hill2":  "#b9543e",
    "hill3":  "#91413c",
    "water":  "#5ad7e2",
    "forest": "#3e5b2f",
}

_THUMB_SIZE = 48


# ---------------------------------------------------------------------------
# Texture picker dialog
# ---------------------------------------------------------------------------

class TexturePickerDialog(QDialog):
    """Modal dialog for selecting a texture from the library."""

    def __init__(
        self,
        parent=None,
        selected_id: str | None = None,
        thumb_cache: dict[str, QPixmap] | None = None,
    ):
        super().__init__(parent)
        self.setWindowTitle("Select Texture")
        self.setMinimumSize(400, 350)
        self.selected_texture: LibraryTexture | None = None

        self._catalog = load_catalog()
        self._thumb_cache: dict[str, QPixmap] = thumb_cache if thumb_cache is not None else {}
        self._selected_id = selected_id

        self._build_ui()
        self._refresh_grid()

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)

        # Search
        search_row = QHBoxLayout()
        search_row.addWidget(QLabel("Search:"))
        self._search_edit = QLineEdit()
        self._search_edit.setPlaceholderText("Filter by name...")
        self._search_edit.setClearButtonEnabled(True)
        self._search_edit.textChanged.connect(self._refresh_grid)
        search_row.addWidget(self._search_edit, 1)
        root.addLayout(search_row)

        # Filters
        filter_row = QHBoxLayout()
        self._game_combo = QComboBox()
        self._game_combo.addItem("All Games")
        games = sorted({t.game for t in self._catalog.textures if t.game})
        self._game_combo.addItems(games)
        self._game_combo.currentIndexChanged.connect(self._refresh_grid)
        filter_row.addWidget(QLabel("Game:"))
        filter_row.addWidget(self._game_combo, 1)

        self._cat_combo = QComboBox()
        self._cat_combo.addItem("All Categories")
        cats = sorted({t.category for t in self._catalog.textures if t.category})
        self._cat_combo.addItems(cats)
        self._cat_combo.currentIndexChanged.connect(self._refresh_grid)
        filter_row.addWidget(QLabel("Category:"))
        filter_row.addWidget(self._cat_combo, 1)
        root.addLayout(filter_row)

        # Scrollable thumbnail grid
        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        self._grid_widget = QWidget()
        self._grid_layout = QGridLayout(self._grid_widget)
        self._grid_layout.setSpacing(4)
        self._scroll.setWidget(self._grid_widget)
        root.addWidget(self._scroll, 1)

        # Bottom buttons
        btn_row = QHBoxLayout()
        btn_row.addStretch()
        clear_btn = QPushButton("Clear (No Texture)")
        clear_btn.clicked.connect(self._on_clear)
        btn_row.addWidget(clear_btn)
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(self.reject)
        btn_row.addWidget(cancel_btn)
        root.addLayout(btn_row)

    def _get_filtered_textures(self) -> list[LibraryTexture]:
        textures = list(self._catalog.textures)
        game = self._game_combo.currentText()
        if game != "All Games":
            textures = [t for t in textures if t.game == game]
        cat = self._cat_combo.currentText()
        if cat != "All Categories":
            textures = [t for t in textures if t.category == cat]
        search = self._search_edit.text().strip().lower()
        if search:
            textures = [t for t in textures if search in t.display_name.lower()]
        return sorted(textures, key=lambda t: t.display_name.lower())

    def _refresh_grid(self) -> None:
        # Clear existing widgets
        while self._grid_layout.count():
            item = self._grid_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        textures = self._get_filtered_textures()
        cols = 3
        cell_w = _THUMB_SIZE + 16
        for i, tex in enumerate(textures):
            # Container for thumbnail + label
            cell = QWidget()
            cell.setFixedWidth(cell_w)
            vl = QVBoxLayout(cell)
            vl.setContentsMargins(0, 0, 0, 0)
            vl.setSpacing(1)

            btn = QPushButton()
            btn.setFixedSize(_THUMB_SIZE + 8, _THUMB_SIZE + 8)
            btn.setIconSize(QSize(_THUMB_SIZE, _THUMB_SIZE))
            btn.setToolTip(tex.display_name)

            thumb = self._get_thumb(tex)
            if thumb:
                btn.setIcon(QIcon(thumb))

            # Highlight selected
            if self._selected_id and tex.id == self._selected_id:
                btn.setStyleSheet("border: 2px solid #4488ff;")

            btn.clicked.connect(lambda checked=False, t=tex: self._on_select(t))
            vl.addWidget(btn, 0, Qt.AlignmentFlag.AlignHCenter)

            lbl = QLabel(tex.display_name)
            lbl.setFixedWidth(cell_w)
            lbl.setAlignment(Qt.AlignmentFlag.AlignHCenter)
            lbl.setWordWrap(True)
            lbl.setStyleSheet("font-size: 9px; color: #aaa;")
            vl.addWidget(lbl)

            self._grid_layout.addWidget(cell, i // cols, i % cols)

    def _get_thumb(self, tex: LibraryTexture) -> QPixmap | None:
        if tex.id in self._thumb_cache:
            return self._thumb_cache[tex.id]
        from PySide6.QtGui import QImage
        path = tex.file_path()
        img = QImage(path)
        if img.isNull():
            self._thumb_cache[tex.id] = None
            return None
        scaled = img.scaled(
            _THUMB_SIZE, _THUMB_SIZE,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        pm = QPixmap.fromImage(scaled)
        self._thumb_cache[tex.id] = pm
        return pm

    def _on_select(self, tex: LibraryTexture) -> None:
        self.selected_texture = tex
        self.accept()

    def _on_clear(self) -> None:
        self.selected_texture = None
        self.accept()


# ---------------------------------------------------------------------------
# Preview widget
# ---------------------------------------------------------------------------

class _MapPreviewWidget(QWidget):
    """Renders a scaled-down hex map preview with terrain fills and rivers."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumHeight(200)
        self._result: MapGenerationResult | None = None
        self._grid_config: HexGridConfig | None = None

    def set_data(self, result: MapGenerationResult, grid_config: HexGridConfig) -> None:
        self._result = result
        self._grid_config = grid_config
        self.update()

    def clear(self) -> None:
        self._result = None
        self._grid_config = None
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, False)

        # Background
        painter.fillRect(self.rect(), QColor("#2b2b2b"))

        if self._result is None or self._grid_config is None:
            painter.setPen(QColor("#888888"))
            painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter,
                             "Click 'Preview' to generate")
            painter.end()
            return

        cfg = self._grid_config
        layout = cfg.create_layout()

        # Calculate bounds of all hex centers to determine scale
        bounds = cfg.get_map_pixel_bounds()
        if bounds.isEmpty():
            painter.end()
            return

        # Scale to fit widget with margin
        margin = 6
        avail_w = self.width() - margin * 2
        avail_h = self.height() - margin * 2
        if avail_w <= 0 or avail_h <= 0:
            painter.end()
            return

        scale_x = avail_w / bounds.width()
        scale_y = avail_h / bounds.height()
        scale = min(scale_x, scale_y)

        rendered_w = bounds.width() * scale
        rendered_h = bounds.height() * scale
        offset_x = (self.width() - rendered_w) / 2
        offset_y = (self.height() - rendered_h) / 2

        painter.translate(offset_x, offset_y)
        painter.scale(scale, scale)
        painter.translate(-bounds.x(), -bounds.y())

        # Draw filled hexagons
        for h, color in self._result.fills.items():
            corners = hex_corners(layout, h)
            poly = QPolygonF([QPointF(x, y) for x, y in corners])
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(color)
            painter.drawPolygon(poly)

        # Draw fill edges between different terrains
        if self._result.edge_borders:
            from app.hex.hex_math import hex_edge_key, hex_edge_vertices
            for hex_a, hex_b, color, _tex_id in self._result.edge_borders:
                # Find the direction from hex_a to hex_b
                for d in range(6):
                    from app.hex.hex_math import hex_neighbor
                    if hex_neighbor(hex_a, d) == hex_b:
                        v1, v2 = hex_edge_vertices(layout, hex_a, d)
                        pen = QPen(color, max(1.0, cfg.hex_size * 0.08))
                        pen.setCosmetic(False)
                        painter.setPen(pen)
                        painter.drawLine(
                            QPointF(v1[0], v1[1]), QPointF(v2[0], v2[1])
                        )
                        break

        # Draw rivers on top
        if self._result.river_edges:
            pen = QPen(QColor("#4488ff"), max(1.0, cfg.hex_size * 0.06))
            pen.setCosmetic(False)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            for hex_a, hex_b in self._result.river_edges:
                ax, ay = hex_to_pixel(layout, hex_a)
                bx, by = hex_to_pixel(layout, hex_b)
                painter.drawLine(QPointF(ax, ay), QPointF(bx, by))

        painter.end()


# ---------------------------------------------------------------------------
# Main dialog
# ---------------------------------------------------------------------------

class RandomMapDialog(QDialog):
    """Non-modal dialog for creating a procedurally generated random map."""

    def __init__(self, project: Project, command_stack: CommandStack, parent=None):
        super().__init__(parent)
        self._project = project
        self._command_stack = command_stack
        self._result: MapGenerationResult | None = None

        # Current terrain colors (role -> QColor)
        self._terrain_colors: dict[str, QColor] = {
            role: QColor(hex_str) for role, hex_str in _DEFAULT_COLORS.items()
        }
        # Current terrain textures (role -> texture_id or None)
        self._terrain_textures: dict[str, str | None] = {
            role: None for role in _DEFAULT_COLORS
        }
        # Shared thumbnail cache (persists across TexturePickerDialog openings)
        self._thumb_cache: dict[str, QPixmap] = {}

        self.setWindowTitle("Create Random Map")
        self.setMinimumWidth(420)
        self.setModal(False)
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        self._build_ui()
        self._load_initial_palette()
        self._on_preview()  # generate initial preview

    # ----- UI construction --------------------------------------------------

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setSpacing(6)

        # -- Map Type --
        grp = QGroupBox("Map Type")
        form = QFormLayout(grp)
        self._type_combo = QComboBox()
        self._type_combo.addItems(["Continental", "Coast", "Island"])
        self._type_combo.currentIndexChanged.connect(self._on_type_changed)
        form.addRow("Type:", self._type_combo)

        self._coast_side_combo = QComboBox()
        self._coast_side_combo.addItems(["North", "South", "East", "West"])
        self._coast_side_combo.setCurrentIndex(1)  # default South
        self._coast_side_label = QLabel("Coast side:")
        form.addRow(self._coast_side_label, self._coast_side_combo)
        self._coast_side_label.setVisible(False)
        self._coast_side_combo.setVisible(False)
        root.addWidget(grp)

        # -- Terrain parameters --
        grp = QGroupBox("Terrain")
        form = QFormLayout(grp)

        self._water_slider, self._water_label = self._make_slider(0, 100, 15)
        form.addRow("Water:", self._make_slider_row(self._water_slider, self._water_label))

        self._mountain_slider, self._mountain_label = self._make_slider(0, 100, 40)
        form.addRow("Mountains:", self._make_slider_row(self._mountain_slider, self._mountain_label))

        self._max_hill_combo = QComboBox()
        self._max_hill_combo.addItems(["Hill 1", "Hill 2", "Hill 3"])
        self._max_hill_combo.setCurrentIndex(2)  # default Hill 3
        form.addRow("Max Level:", self._max_hill_combo)

        self._forest_slider, self._forest_label = self._make_slider(0, 100, 35)
        form.addRow("Forest:", self._make_slider_row(self._forest_slider, self._forest_label))

        self._forest_hill_slider, self._forest_hill_label = self._make_slider(0, 100, 0)
        self._forest_hill_slider.setToolTip(
            "Forest patches inside hill regions (only where fully surrounded by hills)"
        )
        form.addRow("Forest on Hill:", self._make_slider_row(self._forest_hill_slider, self._forest_hill_label))

        self._fill_edges_cb = QCheckBox("Fill Edges")
        self._fill_edges_cb.setToolTip(
            "Place hexside lines at terrain transitions, colored by the lower terrain"
        )
        self._fill_edges_cb.setChecked(True)
        form.addRow("", self._fill_edges_cb)

        root.addWidget(grp)

        # -- Terrain Fills --
        grp = QGroupBox("Terrain Fills")
        form = QFormLayout(grp)

        self._palette_combo = QComboBox()
        palettes = list_palettes()
        self._palette_combo.addItems(palettes)
        if "Classic" in palettes:
            self._palette_combo.setCurrentText("Classic")
        self._palette_combo.currentTextChanged.connect(self._on_palette_changed)
        form.addRow("Palette:", self._palette_combo)

        # Terrain role combos + color buttons + texture buttons
        self._role_combos: dict[str, QComboBox] = {}
        self._role_btns: dict[str, QPushButton] = {}
        self._role_tex_btns: dict[str, QPushButton] = {}
        roles = [
            ("ground", "Ground:"),
            ("hill1", "Hill 1:"),
            ("hill2", "Hill 2:"),
            ("hill3", "Hill 3:"),
            ("water", "Water:"),
            ("forest", "Forest:"),
        ]
        for role, label in roles:
            combo = QComboBox()
            combo.setMinimumWidth(100)
            btn = QPushButton()
            btn.setFixedSize(24, 24)
            self._update_color_btn(btn, self._terrain_colors[role])
            btn.clicked.connect(lambda checked=False, r=role: self._pick_color(r))
            combo.currentIndexChanged.connect(
                lambda idx, r=role, c=combo: self._on_role_combo_changed(r, c)
            )

            # Texture button
            tex_btn = QPushButton("None")
            tex_btn.setFixedWidth(80)
            tex_btn.setToolTip("Click to select texture, right-click to clear")
            tex_btn.clicked.connect(lambda checked=False, r=role: self._pick_texture(r))
            tex_btn.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
            tex_btn.customContextMenuRequested.connect(
                lambda pos, r=role: self._clear_texture(r)
            )

            row = QWidget()
            hl = QHBoxLayout(row)
            hl.setContentsMargins(0, 0, 0, 0)
            hl.addWidget(combo, 1)
            hl.addWidget(btn)
            hl.addWidget(tex_btn)
            form.addRow(label, row)

            self._role_combos[role] = combo
            self._role_btns[role] = btn
            self._role_tex_btns[role] = tex_btn

        # Texture zoom slider
        self._tex_zoom_slider, self._tex_zoom_label = self._make_slider(10, 500, 100)
        self._tex_zoom_label.setFixedWidth(38)
        self._tex_zoom_slider.valueChanged.connect(
            lambda v: self._tex_zoom_label.setText(f"{v / 100:.1f}x")
        )
        self._tex_zoom_label.setText("1.0x")
        form.addRow("Tex Zoom:", self._make_slider_row(self._tex_zoom_slider, self._tex_zoom_label))

        root.addWidget(grp)

        # -- Seed --
        grp = QGroupBox("Seed")
        hl = QHBoxLayout(grp)
        self._seed_spin = QSpinBox()
        self._seed_spin.setRange(0, 999999)
        self._seed_spin.setValue(_random_mod.randint(0, 999999))
        hl.addWidget(self._seed_spin, 1)
        randomize_btn = QPushButton("Randomize")
        randomize_btn.clicked.connect(
            lambda: self._seed_spin.setValue(_random_mod.randint(0, 999999))
        )
        hl.addWidget(randomize_btn)
        self._seed_spin.valueChanged.connect(self._on_seed_changed)
        root.addWidget(grp)

        # -- Preview --
        grp = QGroupBox("Preview")
        vl = QVBoxLayout(grp)
        self._preview = _MapPreviewWidget()
        vl.addWidget(self._preview)
        root.addWidget(grp)

        # -- Bottom buttons --
        btn_row = QHBoxLayout()
        btn_row.addStretch()
        self._apply_btn = QPushButton("Apply")
        self._apply_btn.setDefault(True)
        self._apply_btn.clicked.connect(self._on_apply)
        btn_row.addWidget(self._apply_btn)
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.close)
        btn_row.addWidget(close_btn)
        root.addLayout(btn_row)

    # ----- Helpers ----------------------------------------------------------

    @staticmethod
    def _make_slider(lo: int, hi: int, default: int) -> tuple[QSlider, QLabel]:
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setRange(lo, hi)
        slider.setValue(default)
        label = QLabel(str(default))
        label.setFixedWidth(28)
        label.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        slider.valueChanged.connect(lambda v, lbl=label: lbl.setText(str(v)))
        return slider, label

    @staticmethod
    def _make_slider_row(slider: QSlider, label: QLabel) -> QWidget:
        w = QWidget()
        hl = QHBoxLayout(w)
        hl.setContentsMargins(0, 0, 0, 0)
        hl.addWidget(slider, 1)
        hl.addWidget(label)
        return w

    @staticmethod
    def _update_color_btn(btn: QPushButton, color: QColor) -> None:
        btn.setStyleSheet(
            f"background-color: {color.name()}; border: 1px solid #555;"
        )

    def _pick_color(self, role: str) -> None:
        from PySide6.QtWidgets import QColorDialog
        color = QColorDialog.getColor(self._terrain_colors[role], self, f"Pick {role} color")
        if color.isValid():
            self._terrain_colors[role] = color
            self._update_color_btn(self._role_btns[role], color)

    # ----- Texture handling -------------------------------------------------

    def _pick_texture(self, role: str) -> None:
        dlg = TexturePickerDialog(
            self,
            selected_id=self._terrain_textures.get(role),
            thumb_cache=self._thumb_cache,
        )
        if dlg.exec() == QDialog.DialogCode.Accepted:
            if dlg.selected_texture is not None:
                self._terrain_textures[role] = dlg.selected_texture.id
                self._update_tex_btn(role, dlg.selected_texture.display_name)
            else:
                self._terrain_textures[role] = None
                self._update_tex_btn(role, None)

    def _clear_texture(self, role: str) -> None:
        self._terrain_textures[role] = None
        self._update_tex_btn(role, None)

    def _update_tex_btn(self, role: str, display_name: str | None) -> None:
        btn = self._role_tex_btns[role]
        if display_name:
            # Truncate long names
            shown = display_name if len(display_name) <= 10 else display_name[:9] + "\u2026"
            btn.setText(shown)
            btn.setStyleSheet("border: 1px solid #4488ff; color: #4488ff;")
            btn.setToolTip(f"Texture: {display_name}\nRight-click to clear")
        else:
            btn.setText("None")
            btn.setStyleSheet("")
            btn.setToolTip("Click to select texture, right-click to clear")

    # ----- Palette handling -------------------------------------------------

    def _load_initial_palette(self) -> None:
        name = self._palette_combo.currentText()
        if name:
            self._on_palette_changed(name)

    def _on_palette_changed(self, name: str) -> None:
        try:
            palette = load_palette(name)
        except FileNotFoundError:
            return

        # Populate role combos with palette color names
        for combo in self._role_combos.values():
            combo.blockSignals(True)
            combo.clear()
            for pc in palette.colors:
                combo.addItem(pc.name, pc.color)
            combo.blockSignals(False)

        # Auto-assign colors to roles by name matching
        self._auto_assign_palette(palette)

    def _auto_assign_palette(self, palette: ColorPalette) -> None:
        for role, keywords in _ROLE_KEYWORDS.items():
            combo = self._role_combos[role]
            matched = False
            for i, pc in enumerate(palette.colors):
                name_lower = pc.name.lower()
                if any(kw in name_lower for kw in keywords):
                    combo.setCurrentIndex(i)
                    self._terrain_colors[role] = QColor(pc.color)
                    self._update_color_btn(self._role_btns[role], self._terrain_colors[role])
                    matched = True
                    break
            if not matched and combo.count() > 0:
                # Use first available color as fallback
                combo.setCurrentIndex(0)
                self._terrain_colors[role] = QColor(combo.itemData(0))
                self._update_color_btn(self._role_btns[role], self._terrain_colors[role])

    def _on_role_combo_changed(self, role: str, combo: QComboBox) -> None:
        idx = combo.currentIndex()
        if idx >= 0:
            color_str = combo.itemData(idx)
            if color_str:
                self._terrain_colors[role] = QColor(color_str)
                self._update_color_btn(self._role_btns[role], self._terrain_colors[role])

    # ----- Map type ---------------------------------------------------------

    def _on_seed_changed(self, _value: int) -> None:
        self._on_preview()

    def _on_type_changed(self, index: int) -> None:
        is_coast = self._type_combo.currentText() == "Coast"
        self._coast_side_label.setVisible(is_coast)
        self._coast_side_combo.setVisible(is_coast)

    # ----- Generation -------------------------------------------------------

    def _build_settings(self) -> GeneratorSettings:
        colors = TerrainColors(
            ground=QColor(self._terrain_colors["ground"]),
            hill1=QColor(self._terrain_colors["hill1"]),
            hill2=QColor(self._terrain_colors["hill2"]),
            hill3=QColor(self._terrain_colors["hill3"]),
            water=QColor(self._terrain_colors["water"]),
            forest=QColor(self._terrain_colors["forest"]),
        )
        # Collect role->texture_id mapping (only roles with texture set)
        role_textures: dict[str, str] = {}
        for role, tex_id in self._terrain_textures.items():
            if tex_id is not None:
                role_textures[role] = tex_id

        return GeneratorSettings(
            map_type=self._type_combo.currentText().lower(),
            coast_side=self._coast_side_combo.currentText().lower(),
            water_pct=self._water_slider.value() / 100.0,
            mountain_pct=self._mountain_slider.value() / 100.0,
            forest_pct=self._forest_slider.value() / 100.0,
            forest_on_hill_pct=self._forest_hill_slider.value() / 100.0,
            river_count=0,
            fill_edges=self._fill_edges_cb.isChecked(),
            colors=colors,
            seed=self._seed_spin.value(),
            grid_config=self._project.grid_config,
            max_hill_level=self._max_hill_combo.currentIndex() + 1,
            role_textures=role_textures if role_textures else None,
            texture_zoom=self._tex_zoom_slider.value() / 100.0,
        )

    def _on_preview(self) -> None:
        settings = self._build_settings()
        self._result = generate_map(settings)
        self._preview.set_data(self._result, self._project.grid_config)

    def _on_apply(self) -> None:
        # Generate if not previewed yet
        if self._result is None:
            self._on_preview()

        if self._result is None:
            return

        # Find the fill layer
        fill_layer = None
        for layer in self._project.layer_stack:
            if isinstance(layer, FillLayer):
                fill_layer = layer
                break

        if fill_layer is None:
            return

        # Role labels for layer names
        role_labels = {
            "ground": "Ground", "hill1": "Hill 1", "hill2": "Hill 2",
            "hill3": "Hill 3", "water": "Water", "forest": "Forest",
        }

        # Build separate texture layers per role
        texture_layers: list[tuple[str, dict[Hex, HexTexture]]] = []
        textured_hexes: set[Hex] = set()
        if self._result.texture_fills:
            zoom = self._tex_zoom_slider.value() / 100.0
            for role, hex_list in self._result.texture_fills.items():
                tex_id = self._terrain_textures.get(role)
                if tex_id is None:
                    continue
                layer_name = role_labels.get(role, role.title())
                tex_fills = {
                    h: HexTexture(texture_id=tex_id, zoom=zoom)
                    for h in hex_list
                }
                texture_layers.append((layer_name, tex_fills))
                textured_hexes.update(hex_list)

        # Color fills: exclude hexes that go into texture layers
        new_fills = {
            h: c for h, c in self._result.fills.items()
            if h not in textured_hexes
        }

        # Create and execute the command
        cmd = RandomMapCommand(
            fill_layer=fill_layer,
            layer_stack=self._project.layer_stack,
            new_fills=new_fills,
            river_edges=[],
            river_preset=None,
            edge_borders=self._result.edge_borders,
            texture_layers=texture_layers if texture_layers else None,
            texture_zoom=self._tex_zoom_slider.value() / 100.0,
        )
        self._command_stack.execute(cmd)
        self.close()
