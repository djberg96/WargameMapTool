require "qt6"

module WargameMapToolCrystal
  VERSION = "0.1.0"

  class LayerInfo
    property name : String
    property kind : String
    property visible : Bool
    property accent : Qt6::Color
    property opacity : Int32

    def initialize(@name : String, @kind : String, @visible : Bool, @accent : Qt6::Color, @opacity : Int32 = 100)
    end
  end

  class MapState
    TOOL_NAMES = ["Background", "Fill", "Path", "Text", "Asset"] of String

    property zoom : Float64
    property pan_x : Float64
    property pan_y : Float64
    property dragging : Bool
    property last_pointer : Qt6::PointF
    property active_tool : String
    property active_layer_index : Int32
    property show_grid : Bool
    property show_coordinates : Bool
    property show_assets : Bool
    property project_path : String?
    property hover_hex : Tuple(Int32, Int32)?
    getter layers : Array(LayerInfo)
    getter cols : Int32
    getter rows : Int32
    getter hex_radius : Float64

    def initialize
      @zoom = 1.0
      @pan_x = 54.0
      @pan_y = 48.0
      @dragging = false
      @last_pointer = Qt6::PointF.new(0.0, 0.0)
      @active_tool = "Fill"
      @active_layer_index = 1
      @show_grid = true
      @show_coordinates = true
      @show_assets = true
      @project_path = nil
      @hover_hex = nil
      @cols = 18
      @rows = 14
      @hex_radius = 28.0
      @layers = [
        LayerInfo.new("Background Wash", "Background", true, Qt6::Color.new(200, 184, 148)),
        LayerInfo.new("Terrain Fill", "Terrain", true, Qt6::Color.new(86, 132, 92)),
        LayerInfo.new("Road Net", "Paths", true, Qt6::Color.new(173, 86, 54)),
        LayerInfo.new("Operational Labels", "Labels", true, Qt6::Color.new(66, 78, 118)),
        LayerInfo.new("Counters", "Assets", true, Qt6::Color.new(94, 100, 112)),
      ] of LayerInfo
    end

    def reset : Nil
      @zoom = 1.0
      @pan_x = 54.0
      @pan_y = 48.0
      @dragging = false
      @last_pointer = Qt6::PointF.new(0.0, 0.0)
      @active_tool = "Fill"
      @active_layer_index = 1
      @show_grid = true
      @show_coordinates = true
      @show_assets = true
      @project_path = nil
      @hover_hex = nil
      @cols = 18
      @rows = 14
      @hex_radius = 28.0
      @layers = [
        LayerInfo.new("Background Wash", "Background", true, Qt6::Color.new(200, 184, 148)),
        LayerInfo.new("Terrain Fill", "Terrain", true, Qt6::Color.new(86, 132, 92)),
        LayerInfo.new("Road Net", "Paths", true, Qt6::Color.new(173, 86, 54)),
        LayerInfo.new("Operational Labels", "Labels", true, Qt6::Color.new(66, 78, 118)),
        LayerInfo.new("Counters", "Assets", true, Qt6::Color.new(94, 100, 112)),
      ] of LayerInfo
    end

    def reset_view : Nil
      @zoom = 1.0
      @pan_x = 54.0
      @pan_y = 48.0
    end

    def active_layer : LayerInfo
      @layers[@active_layer_index]
    end

    def set_active_layer(index : Int32) : Nil
      @active_layer_index = index.clamp(0, @layers.size - 1)
    end

    def layer_visible?(kind : String) : Bool
      @layers.any? { |layer| layer.kind == kind && layer.visible }
    end

    def active_layer_visible=(value : Bool) : Bool
      active_layer.visible = value
      value
    end

    def world_bounds : Qt6::RectF
      Qt6::RectF.new(0.0, 0.0, map_width, map_height)
    end

    def map_width : Float64
      (@cols - 1) * horizontal_step + horizontal_step + @hex_radius
    end

    def map_height : Float64
      (@rows - 1) * vertical_step + @hex_radius * 2.0
    end

    def horizontal_step : Float64
      Math.sqrt(3.0) * @hex_radius
    end

    def vertical_step : Float64
      @hex_radius * 1.5
    end

    def hex_center(col : Int32, row : Int32) : Qt6::PointF
      x = col * horizontal_step + (row.odd? ? horizontal_step / 2.0 : 0.0) + @hex_radius
      y = row * vertical_step + @hex_radius
      Qt6::PointF.new(x, y)
    end

    def hex_points(col : Int32, row : Int32) : Array(Qt6::PointF)
      center = hex_center(col, row)
      points = [] of Qt6::PointF

      6.times do |index|
        angle = Math::PI / 6.0 + (Math::PI / 3.0) * index
        points << Qt6::PointF.new(
          center.x + Math.cos(angle) * @hex_radius,
          center.y + Math.sin(angle) * @hex_radius
        )
      end

      points
    end

    def screen_point(world : Qt6::PointF) : Qt6::PointF
      Qt6::PointF.new(@pan_x + world.x * @zoom, @pan_y + world.y * @zoom)
    end

    def screen_rect(world : Qt6::RectF) : Qt6::RectF
      Qt6::RectF.new(
        @pan_x + world.x * @zoom,
        @pan_y + world.y * @zoom,
        world.width * @zoom,
        world.height * @zoom
      )
    end

    def screen_to_world(screen : Qt6::PointF) : Qt6::PointF
      Qt6::PointF.new((screen.x - @pan_x) / @zoom, (screen.y - @pan_y) / @zoom)
    end

    def zoom_at(screen : Qt6::PointF, factor : Float64) : Nil
      world = screen_to_world(screen)
      @zoom = (@zoom * factor).clamp(0.45, 3.25)
      @pan_x = screen.x - world.x * @zoom
      @pan_y = screen.y - world.y * @zoom
    end

    def terrain_color(col : Int32, row : Int32) : Qt6::Color
      value = Math.sin(col.to_f64 * 0.58) + Math.cos(row.to_f64 * 0.51) + Math.sin((col + row).to_f64 * 0.27)

      case value
      when ..-0.55
        Qt6::Color.new(92, 128, 170)
      when -0.55..0.35
        Qt6::Color.new(144, 164, 104)
      when 0.35..1.05
        Qt6::Color.new(178, 154, 98)
      else
        Qt6::Color.new(122, 116, 104)
      end
    end

    def pick_hex(screen : Qt6::PointF) : Tuple(Int32, Int32)?
      world = screen_to_world(screen)
      best = nil
      best_distance = Float64::INFINITY

      @rows.times do |row|
        @cols.times do |col|
          center = hex_center(col, row)
          dx = center.x - world.x
          dy = center.y - world.y
          distance = Math.sqrt(dx * dx + dy * dy)

          if distance < best_distance
            best_distance = distance
            best = {col, row}
          end
        end
      end

      return nil unless best
      best_distance <= @hex_radius * 1.15 ? best : nil
    end

    def hex_label(col : Int32, row : Int32) : String
      letter = ('A'.ord + col).chr
      "#{letter}#{(row + 1).to_s.rjust(2, '0')}"
    end

    def route_hexes : Array(Tuple(Int32, Int32))
      [{1, 3}, {4, 4}, {7, 5}, {10, 7}, {13, 8}, {16, 10}] of Tuple(Int32, Int32)
    end

    def asset_hexes : Array(Tuple(Int32, Int32))
      [{3, 2}, {8, 6}, {12, 4}, {15, 9}] of Tuple(Int32, Int32)
    end

    def label_hexes : Array(Tuple(String, Int32, Int32))
      [
        {"Hill 204", 4, 3},
        {"Bridge", 10, 7},
        {"Depot", 14, 9},
      ] of Tuple(String, Int32, Int32)
    end
  end
end