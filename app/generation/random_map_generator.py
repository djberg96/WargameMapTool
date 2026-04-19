"""Procedural random map generation algorithm.

Generates terrain fills and river edges for a hex grid using value noise,
topology shaping, and steepest-descent river tracing.
"""

from __future__ import annotations

import random as _random_mod
from dataclasses import dataclass

from PySide6.QtGui import QColor

from app.hex.hex_math import (
    Hex,
    HEX_DIRECTIONS,
    axial_to_offset,
    hex_distance,
    hex_edge_key,
    hex_neighbor,
)
from app.hex.hex_grid_config import HexGridConfig


@dataclass
class TerrainColors:
    """Color mapping for each terrain role."""
    ground: QColor
    hill1: QColor
    hill2: QColor
    hill3: QColor
    water: QColor
    forest: QColor


@dataclass
class GeneratorSettings:
    """All parameters for map generation."""
    map_type: str          # "continental", "coast", "island"
    coast_side: str        # "north", "south", "east", "west"
    water_pct: float       # 0.0 - 1.0
    mountain_pct: float    # 0.0 - 1.0
    forest_pct: float      # 0.0 - 1.0
    river_count: int       # 0 - 20
    fill_edges: bool       # generate hexside edges at terrain transitions
    colors: TerrainColors
    seed: int
    grid_config: HexGridConfig
    forest_on_hill_pct: float = 0.0  # 0.0 - 1.0, forest inside hill regions
    max_hill_level: int = 3       # 1 = only hill1, 2 = hill1+hill2, 3 = all three
    role_textures: dict[str, str] | None = None  # role -> texture_id
    texture_zoom: float = 1.0


@dataclass
class MapGenerationResult:
    """Output of the generation algorithm."""
    fills: dict[Hex, QColor]
    river_edges: list[tuple[Hex, Hex]]
    # Fill edges: (hex_a, hex_b, color, texture_id_or_None)
    edge_borders: list[tuple[Hex, Hex, QColor, str | None]]
    # Texture fills grouped by role: role -> list of hexes (only for textured roles)
    texture_fills: dict[str, list[Hex]] | None = None


def generate_map(settings: GeneratorSettings) -> MapGenerationResult:
    """Run the full map generation pipeline."""
    rng = _random_mod.Random(settings.seed)
    cfg = settings.grid_config
    all_hexes = cfg.get_all_hexes()

    if not all_hexes:
        return MapGenerationResult(fills={}, river_edges=[], edge_borders=[])

    hex_set = set(all_hexes)

    # Step 1: Generate raw noise heightmap
    passes = _calc_passes(cfg)
    raw_height = _value_noise(all_hexes, hex_set, rng, passes)

    # Step 2: Apply topology bias
    height = _apply_topology(raw_height, all_hexes, settings)

    # Step 3: Normalize to [0, 1]
    height = _normalize(height)

    # Step 4: Assign terrain roles
    terrain = _assign_terrain(height, all_hexes, settings)

    # Step 5: Forest overlay (second noise layer)
    forest_rng = _random_mod.Random(settings.seed + 1)
    forest_noise = _value_noise(all_hexes, hex_set, forest_rng, max(2, passes - 1))
    forest_noise = _normalize(forest_noise)
    _overlay_forest(terrain, forest_noise, all_hexes, settings)

    # Step 5b: Forest-on-hill overlay
    if settings.forest_on_hill_pct > 0:
        _overlay_forest_on_hills(terrain, forest_noise, all_hexes, hex_set, settings)

    # Step 6: Map roles to colors
    fills = _terrain_to_fills(terrain, all_hexes, settings.colors)

    # Step 7: Generate fill edges at terrain transitions
    edge_borders: list[tuple[Hex, Hex, QColor, str | None]] = []
    if settings.fill_edges:
        edge_borders = _generate_fill_edges(
            terrain, fills, height, all_hexes, hex_set, settings
        )

    # Step 6b: Map roles to texture fills (for roles with texture assigned)
    texture_fills = _terrain_to_texture_fills(terrain, all_hexes, settings)

    # Step 8: Trace rivers
    river_edges = _trace_rivers(height, terrain, all_hexes, hex_set, settings, rng)

    return MapGenerationResult(
        fills=fills, river_edges=river_edges, edge_borders=edge_borders,
        texture_fills=texture_fills,
    )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _calc_passes(cfg: HexGridConfig) -> int:
    """Determine smoothing passes based on grid size."""
    import math
    n = max(cfg.width, cfg.height)
    return max(3, min(8, 2 + int(math.sqrt(n))))


def _value_noise(
    hexes: list[Hex],
    hex_set: set[Hex],
    rng: _random_mod.Random,
    passes: int,
) -> dict[Hex, float]:
    """Generate smooth value noise via hex-neighbor averaging."""
    vals = {h: rng.uniform(0.0, 1.0) for h in hexes}

    for _ in range(passes):
        new_vals = {}
        for h in hexes:
            neighbors = []
            for d in range(6):
                nb = hex_neighbor(h, d)
                if nb in hex_set:
                    neighbors.append(nb)
            if neighbors:
                avg = sum(vals[n] for n in neighbors) / len(neighbors)
                new_vals[h] = 0.5 * vals[h] + 0.5 * avg
            else:
                new_vals[h] = vals[h]
        vals = new_vals

    return vals


def _apply_topology(
    raw: dict[Hex, float],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> dict[Hex, float]:
    """Apply topology bias based on map type."""
    if settings.map_type == "continental":
        return dict(raw)
    elif settings.map_type == "coast":
        return _apply_coast_bias(raw, hexes, settings)
    else:  # island
        return _apply_island_bias(raw, hexes, settings)


def _apply_coast_bias(
    raw: dict[Hex, float],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> dict[Hex, float]:
    """Push one side of the map toward lower elevation (water)."""
    cfg = settings.grid_config
    result = {}
    coast_strength = 0.6

    for h in hexes:
        col, row = axial_to_offset(h, cfg.first_row_offset, cfg.orientation)
        # Normalized distance from coast edge (0 = coast side, 1 = opposite)
        if settings.coast_side == "north":
            t = row / max(1, cfg.height - 1)
        elif settings.coast_side == "south":
            t = 1.0 - row / max(1, cfg.height - 1)
        elif settings.coast_side == "west":
            t = col / max(1, cfg.width - 1)
        else:  # east
            t = 1.0 - col / max(1, cfg.width - 1)

        result[h] = raw[h] + t * coast_strength

    return result


def _apply_island_bias(
    raw: dict[Hex, float],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> dict[Hex, float]:
    """Push edges of the map toward lower elevation (water)."""
    cfg = settings.grid_config
    result = {}
    island_strength = 0.8
    cx = (cfg.width - 1) / 2.0
    cy = (cfg.height - 1) / 2.0
    max_dist = max(cx, cy, 1.0)

    for h in hexes:
        col, row = axial_to_offset(h, cfg.first_row_offset, cfg.orientation)
        dx = (col - cx) / max_dist
        dy = (row - cy) / max_dist
        dist = min(1.0, (dx * dx + dy * dy) ** 0.5)
        result[h] = raw[h] - (dist ** 1.5) * island_strength

    return result


def _normalize(vals: dict[Hex, float]) -> dict[Hex, float]:
    """Normalize values to [0, 1] range."""
    if not vals:
        return vals
    lo = min(vals.values())
    hi = max(vals.values())
    span = hi - lo
    if span < 1e-9:
        return {h: 0.5 for h in vals}
    return {h: (v - lo) / span for h, v in vals.items()}


def _assign_terrain(
    height: dict[Hex, float],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> dict[Hex, str]:
    """Assign terrain role to each hex based on elevation quantiles."""
    n = len(hexes)
    if n == 0:
        return {}

    sorted_heights = sorted(height[h] for h in hexes)

    # Water threshold
    water_idx = max(0, min(n - 1, int(n * settings.water_pct)))
    water_level = sorted_heights[water_idx]

    # Mountain thresholds (top mountain_pct fraction, split by max_hill_level)
    max_lvl = max(1, min(3, settings.max_hill_level))
    mtn_start_idx = max(0, min(n - 1, int(n * (1.0 - settings.mountain_pct))))
    hill1_level = sorted_heights[mtn_start_idx]

    if max_lvl >= 2:
        mtn_mid_idx = max(0, min(n - 1, int(n * (1.0 - settings.mountain_pct * 2.0 / 3.0))))
        hill2_level = sorted_heights[mtn_mid_idx]
    else:
        hill2_level = float("inf")

    if max_lvl >= 3:
        mtn_top_idx = max(0, min(n - 1, int(n * (1.0 - settings.mountain_pct / 3.0))))
        hill3_level = sorted_heights[mtn_top_idx]
    else:
        hill3_level = float("inf")

    terrain = {}
    for h in hexes:
        elev = height[h]
        if elev <= water_level and settings.water_pct > 0:
            terrain[h] = "water"
        elif elev >= hill3_level and settings.mountain_pct > 0:
            terrain[h] = "hill3"
        elif elev >= hill2_level and settings.mountain_pct > 0:
            terrain[h] = "hill2"
        elif elev >= hill1_level and settings.mountain_pct > 0:
            terrain[h] = "hill1"
        else:
            terrain[h] = "ground"

    return terrain


def _overlay_forest(
    terrain: dict[Hex, str],
    forest_noise: dict[Hex, float],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> None:
    """Overlay forest on ground hexes based on noise threshold."""
    if settings.forest_pct <= 0:
        return
    threshold = 1.0 - settings.forest_pct
    for h in hexes:
        if terrain[h] == "ground" and forest_noise[h] > threshold:
            terrain[h] = "forest"


def _overlay_forest_on_hills(
    terrain: dict[Hex, str],
    forest_noise: dict[Hex, float],
    hexes: list[Hex],
    hex_set: set[Hex],
    settings: GeneratorSettings,
) -> None:
    """Overlay forest on hill hexes that are fully surrounded by hill/forest.

    Only converts hill hexes to forest if ALL 6 neighbors (that are on the map)
    are also hill or forest hexes — so forest patches stay entirely inside
    hill regions without touching ground or water.
    """
    if settings.forest_on_hill_pct <= 0:
        return

    hill_roles = {"hill1", "hill2", "hill3"}
    allowed_neighbor_roles = hill_roles | {"forest"}

    # Collect candidate hill hexes that are fully interior (all neighbors are hill/forest)
    candidates: list[Hex] = []
    for h in hexes:
        if terrain[h] not in hill_roles:
            continue
        all_ok = True
        for d in range(6):
            nb = hex_neighbor(h, d)
            if nb not in hex_set:
                all_ok = False
                break
            if terrain[nb] not in allowed_neighbor_roles:
                all_ok = False
                break
        if all_ok:
            candidates.append(h)

    if not candidates:
        return

    # Use forest noise to pick which candidates become forest
    threshold = 1.0 - settings.forest_on_hill_pct
    for h in candidates:
        if forest_noise[h] > threshold:
            terrain[h] = "forest"


def _terrain_to_fills(
    terrain: dict[Hex, str],
    hexes: list[Hex],
    colors: TerrainColors,
) -> dict[Hex, QColor]:
    """Convert terrain roles to QColor fills."""
    role_map = {
        "ground": colors.ground,
        "hill1": colors.hill1,
        "hill2": colors.hill2,
        "hill3": colors.hill3,
        "water": colors.water,
        "forest": colors.forest,
    }
    return {h: QColor(role_map[terrain[h]]) for h in hexes}


def _terrain_to_texture_fills(
    terrain: dict[Hex, str],
    hexes: list[Hex],
    settings: GeneratorSettings,
) -> dict[str, list[Hex]] | None:
    """Group hexes by role for roles that have a texture assigned.

    Returns role -> list of hexes, only for roles in settings.role_textures.
    """
    if not settings.role_textures:
        return None
    result: dict[str, list[Hex]] = {}
    for h in hexes:
        role = terrain[h]
        if role in settings.role_textures:
            result.setdefault(role, []).append(h)
    return result if result else None


# Elevation rank for determining which terrain is "lower" at a transition.
# Lower rank = lower terrain = its color is used for the border hexside.
_TERRAIN_RANK = {
    "water": 0,
    "ground": 1,
    "forest": 2,
    "hill1": 3,
    "hill2": 4,
    "hill3": 5,
}


def _generate_fill_edges(
    terrain: dict[Hex, str],
    fills: dict[Hex, QColor],
    height: dict[Hex, float],
    hexes: list[Hex],
    hex_set: set[Hex],
    settings: GeneratorSettings,
) -> list[tuple[Hex, Hex, QColor, str | None]]:
    """Find all hex edges where the terrain type changes.

    Returns (hex_a, hex_b, color, texture_id_or_None) where color is the fill
    of the lower-ranked terrain (e.g. ground at a ground/hill1 border).
    If that role has a texture assigned, texture_id is included.
    """
    role_textures = settings.role_textures or {}
    seen: set[tuple[tuple[int, int], tuple[int, int]]] = set()
    edges: list[tuple[Hex, Hex, QColor, str | None]] = []

    for h in hexes:
        role_h = terrain[h]
        rank_h = _TERRAIN_RANK.get(role_h, 1)
        for d in range(6):
            nb = hex_neighbor(h, d)
            if nb not in hex_set:
                continue
            role_nb = terrain[nb]
            if role_h == role_nb:
                continue  # same terrain, no edge
            key = hex_edge_key(h, nb)
            if key in seen:
                continue
            seen.add(key)
            # Use the color/texture of the lower-ranked terrain
            rank_nb = _TERRAIN_RANK.get(role_nb, 1)
            if rank_h <= rank_nb:
                color = QColor(fills[h])
                lower_role = role_h
            else:
                color = QColor(fills[nb])
                lower_role = role_nb
            tex_id = role_textures.get(lower_role)
            edges.append((h, nb, color, tex_id))

    return edges


def _trace_rivers(
    height: dict[Hex, float],
    terrain: dict[Hex, str],
    hexes: list[Hex],
    hex_set: set[Hex],
    settings: GeneratorSettings,
    rng: _random_mod.Random,
) -> list[tuple[Hex, Hex]]:
    """Trace rivers from high elevation to water/edge via steepest descent.

    Rivers escape local minima by flooding: when stuck, BFS finds the
    lowest spill-over point out of the basin so rivers keep flowing.
    """
    if settings.river_count <= 0:
        return []

    cfg = settings.grid_config

    # Find candidate sources: non-water hexes in top 15% of elevation
    sorted_hexes = sorted(hexes, key=lambda h: height[h], reverse=True)
    top_slice = sorted_hexes[:max(1, len(sorted_hexes) * 15 // 100)]
    non_water = [h for h in top_slice if terrain[h] != "water"]

    # Select sources with good separation
    min_sep = max(3, min(cfg.width, cfg.height) // 4)
    rng.shuffle(non_water)
    sources: list[Hex] = []
    for candidate in non_water:
        if all(hex_distance(candidate, s) >= min_sep for s in sources):
            sources.append(candidate)
        if len(sources) >= settings.river_count:
            break

    # Generous max length so rivers can cross the whole map
    max_length = (cfg.width + cfg.height) * 2
    min_river_length = 10  # discard rivers shorter than this
    river_hexes: set[Hex] = set()  # all hexes already part of a river
    all_river_edges: list[tuple[Hex, Hex]] = []

    for source in sources:
        current = source
        visited_in_river: set[Hex] = set()
        river_edges: list[tuple[tuple[int, int], tuple[int, int]]] = []

        for _ in range(max_length):
            if terrain[current] == "water":
                break
            # Stop if we reached the map edge (river flows off-map)
            if _is_border_hex(current, hex_set):
                break
            # Stop if we merged into an existing river
            if current in river_hexes and current != source:
                break

            visited_in_river.add(current)

            # Find lowest unvisited neighbor (steepest descent)
            best_nb = None
            best_elev = float("inf")
            for d in range(6):
                nb = hex_neighbor(current, d)
                if nb in hex_set and nb not in visited_in_river:
                    if height[nb] < best_elev:
                        best_elev = height[nb]
                        best_nb = nb

            # If stuck (local minimum), flood to find spill-over point
            if best_nb is None or height[best_nb] >= height[current]:
                spill = _find_spill_point(
                    current, height, hex_set, visited_in_river, terrain
                )
                if spill is None:
                    break  # Truly trapped, give up
                best_nb = spill

            river_edges.append(hex_edge_key(current, best_nb))
            current = best_nb

        # Only keep rivers that are long enough
        if len(river_edges) >= min_river_length:
            river_hexes.update(visited_in_river)
            all_river_edges.extend(river_edges)

    # Deduplicate edges (in case of merges)
    seen: set[tuple[tuple[int, int], tuple[int, int]]] = set()
    result: list[tuple[Hex, Hex]] = []
    for edge in all_river_edges:
        if edge not in seen:
            seen.add(edge)
            result.append((Hex(edge[0][0], edge[0][1]), Hex(edge[1][0], edge[1][1])))

    return result


def _is_border_hex(h: Hex, hex_set: set[Hex]) -> bool:
    """True if h has at least one neighbor outside the grid."""
    for d in range(6):
        if hex_neighbor(h, d) not in hex_set:
            return True
    return False


def _find_spill_point(
    start: Hex,
    height: dict[Hex, float],
    hex_set: set[Hex],
    visited: set[Hex],
    terrain: dict[Hex, str],
) -> Hex | None:
    """BFS flood-fill from a local minimum to find the lowest escape point.

    Expands outward from *start* through hexes at or above *start*'s
    elevation, looking for the first hex whose elevation is strictly lower
    than the basin level, or that is water / off-map-adjacent.
    Returns the best spill-over neighbor, or None if no escape exists.
    """
    basin_level = height[start]
    from collections import deque
    queue: deque[Hex] = deque([start])
    seen: set[Hex] = {start}
    best_exit: Hex | None = None
    best_exit_elev = float("inf")

    while queue:
        h = queue.popleft()
        for d in range(6):
            nb = hex_neighbor(h, d)
            if nb in seen or nb not in hex_set:
                continue
            seen.add(nb)

            # Found an exit: lower elevation or water
            if nb not in visited and (
                height[nb] < basin_level or terrain.get(nb) == "water"
            ):
                if height[nb] < best_exit_elev:
                    best_exit_elev = height[nb]
                    best_exit = nb
                continue  # Don't expand past exits

            # Still in the basin — keep expanding
            if height[nb] <= basin_level + 0.05:
                queue.append(nb)

    return best_exit
