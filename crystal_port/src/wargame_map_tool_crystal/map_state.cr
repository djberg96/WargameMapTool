require "json"
require "qt6"
require "./layers"

module WargameMapToolCrystal
  VERSION = "0.1.0"

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
    property source_path : String?
    property hover_hex : Tuple(Int32, Int32)?
    property hover_screen : Qt6::PointF?
    property selected_path_object : PathObject?
    property selected_text_object : TextObject?
    property selected_asset_object : AssetObject?
    getter layers : Array(MapLayer)
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
      @source_path = nil
      @hover_hex = nil
      @hover_screen = nil
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @cols = 18
      @rows = 14
      @hex_radius = 28.0
      @layers = build_default_layers
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
      @source_path = nil
      @hover_hex = nil
      @hover_screen = nil
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @cols = 18
      @rows = 14
      @hex_radius = 28.0
      @layers = build_default_layers
    end

    def reset_view : Nil
      @zoom = 1.0
      @pan_x = 54.0
      @pan_y = 48.0
    end

    def active_layer : MapLayer
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

    def background_layer : BackgroundLayer?
      @layers.each do |layer|
        return layer.as(BackgroundLayer) if layer.is_a?(BackgroundLayer)
      end

      nil
    end

    def text_layer : TextLayer?
      @layers.each do |layer|
        return layer.as(TextLayer) if layer.is_a?(TextLayer)
      end

      nil
    end

    def path_layer : PathLayer?
      @layers.each do |layer|
        return layer.as(PathLayer) if layer.is_a?(PathLayer)
      end

      nil
    end

    def asset_layer : AssetLayer?
      @layers.each do |layer|
        return layer.as(AssetLayer) if layer.is_a?(AssetLayer)
      end

      nil
    end

    def text_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(TextLayer)
      end

      nil
    end

    def asset_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(AssetLayer)
      end

      nil
    end

    def path_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(PathLayer)
      end

      nil
    end

    def add_text_label(text : String) : Bool
      clean_text = text.strip
      return false if clean_text.empty?

      layer = text_layer
      return false unless layer

      anchor = if hover = @hover_hex
                 hex_center(hover[0], hover[1])
               else
                 Qt6::PointF.new(world_bounds.x + world_bounds.width / 2.0, world_bounds.y + world_bounds.height / 2.0)
               end

      object = TextObject.new(clean_text, anchor.x + 10.0, anchor.y - 10.0, color: layer.accent, bold: true)
      layer.add_text(object)
      @selected_path_object = nil
      @selected_asset_object = nil
      @selected_text_object = object
      true
    end

    def add_asset(image_path : String, scale : Float64 = 0.5) : Bool
      clean_path = image_path.strip
      return false if clean_path.empty?

      layer = asset_layer
      return false unless layer

      anchor = if hover = @hover_hex
                 hex_center(hover[0], hover[1])
               else
                 Qt6::PointF.new(world_bounds.x + world_bounds.width / 2.0, world_bounds.y + world_bounds.height / 2.0)
               end

      object = AssetObject.new(anchor.x, anchor.y, clean_path, scale: scale)
      return false unless object.has_image?

      snap_asset_to_hex(object) if object.snap_to_hex

      layer.add_asset(object)
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = object
      true
    end

    def selected_path_present? : Bool
      object = @selected_path_object
      layer = path_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def clear_path_selection : Nil
      @selected_path_object = nil
    end

    def duplicate_selected_path : PathObject?
      source = @selected_path_object
      layer = path_layer
      return nil unless source && layer

      delta_col = 1
      delta_row = 0

      if hover = @hover_hex
        delta_col = hover[0] - source.col_a
        delta_row = hover[1] - source.row_a
      elsif !valid_hex_coord?(source.col_a + delta_col, source.row_a + delta_row) || !valid_hex_coord?(source.col_b + delta_col, source.row_b + delta_row)
        delta_col = 0
        delta_row = 1
      end

      unless valid_hex_coord?(source.col_a + delta_col, source.row_a + delta_row) && valid_hex_coord?(source.col_b + delta_col, source.row_b + delta_row)
        delta_col = 0
        delta_row = 0
      end

      object = PathObject.new(
        source.col_a + delta_col,
        source.row_a + delta_row,
        source.col_b + delta_col,
        source.row_b + delta_row,
        color: source.color,
        width: source.width,
        line_type: source.line_type,
        opacity: source.opacity,
      )

      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = object
      layer.add_path(object)
      object
    end

    def duplicate_selected_asset : AssetObject?
      source = @selected_asset_object
      layer = asset_layer
      return nil unless source && layer

      x = source.x
      y = source.y

      if hover = @hover_hex
        anchor = hex_center(hover[0], hover[1])
        x = anchor.x
        y = anchor.y
      elsif source.snap_to_hex
        x += horizontal_step
      else
        x += 24.0
        y += 18.0
      end

      object = AssetObject.new(
        x,
        y,
        source.image_path,
        scale: source.scale,
        rotation: source.rotation,
        opacity: source.opacity,
        snap_to_hex: source.snap_to_hex,
      )

      snap_asset_to_hex(object) if object.snap_to_hex

      layer.add_asset(object)
      @selected_text_object = nil
      @selected_asset_object = object
      object
    end

    def selected_text_present? : Bool
      object = @selected_text_object
      layer = text_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def clear_text_selection : Nil
      @selected_text_object = nil
    end

    def selected_asset_present? : Bool
      object = @selected_asset_object
      layer = asset_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def clear_asset_selection : Nil
      @selected_asset_object = nil
    end

    def select_hovered_text : TextObject?
      object = hovered_text_object
      @selected_path_object = nil
      @selected_asset_object = nil
      @selected_text_object = object
      object
    end

    def hovered_text_object : TextObject?
      screen = @hover_screen
      layer = text_layer
      return nil unless screen && layer

      layer.nearest_text(self, screen)
    end

    def select_hovered_asset : AssetObject?
      object = hovered_asset_object
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = object
      object
    end

    def select_hovered_path : PathObject?
      object = hovered_path_object
      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = object
      object
    end

    def hovered_path_object : PathObject?
      screen = @hover_screen
      layer = path_layer
      return nil unless screen && layer

      layer.nearest_path(self, screen)
    end

    def hovered_asset_object : AssetObject?
      screen = @hover_screen
      layer = asset_layer
      return nil unless screen && layer

      layer.nearest_asset(self, screen)
    end

    def snap_asset_to_hex(object : AssetObject) : Bool
      center = nearest_hex_center(Qt6::PointF.new(object.x, object.y))
      return false unless center

      object.x = center.x
      object.y = center.y
      true
    end

    def save_slice(path : String) : Nil
      File.write(path, JSON.build do |json|
        json.object do
          json.field "version", 1
          json.field "source_path", @source_path if @source_path

          json.field "background" do
            if layer = background_layer
              json.object do
                json.field "image_path", layer.image_path if layer.image_path
                json.field "offset_x", layer.offset_x
                json.field "offset_y", layer.offset_y
                json.field "scale", layer.scale
                json.field "visible", layer.visible
                json.field "opacity", layer.opacity
              end
            else
              json.null
            end
          end

          json.field "text_objects" do
            if layer = text_layer
              json.array do
                layer.objects.each do |object|
                  object.write_json(json)
                end
              end
            else
              json.array do
              end
            end
          end

          json.field "path_objects" do
            if layer = path_layer
              json.array do
                layer.objects.each do |object|
                  object.write_json(json)
                end
              end
            else
              json.array do
              end
            end
          end

          json.field "asset_objects" do
            if layer = asset_layer
              json.array do
                layer.objects.each do |object|
                  object.write_json(json)
                end
              end
            else
              json.array do
              end
            end
          end
        end
      end)

      @project_path = path
    end

    def load_slice(path : String) : Bool
      data = JSON.parse(File.read(path))

      reset
      @project_path = path
      @source_path = data["source_path"]?.try(&.as_s?)

      background_data = data["background"]?
      if background_data && (layer = background_layer)
        if image_path = background_data["image_path"]?.try(&.as_s?)
          resolved_path = resolve_slice_path(path, image_path)
          return false unless layer.load_image(resolved_path)
        else
          layer.clear_image
        end

        layer.offset_x = background_data["offset_x"]?.try(&.as_f?) || 0.0
        layer.offset_y = background_data["offset_y"]?.try(&.as_f?) || 0.0
        layer.scale = background_data["scale"]?.try(&.as_f?) || 1.0
        layer.visible = background_data["visible"]?.try(&.as_bool?) || true
        layer.opacity = background_data["opacity"]?.try(&.as_i?) || 100
      end

      text_layer.try(&.clear_texts)
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      data["text_objects"]?.try(&.as_a?).try do |objects|
        if layer = text_layer
          objects.each do |object_data|
            layer.add_text(TextObject.from_json(object_data))
          end
        end
      end

      data["path_objects"]?.try(&.as_a?).try do |objects|
        if layer = path_layer
          layer.clear_paths
          objects.each do |object_data|
            layer.add_path(PathObject.from_json(object_data))
          end
        end
      end

      data["asset_objects"]?.try(&.as_a?).try do |objects|
        if layer = asset_layer
          layer.clear_assets
          objects.each do |object_data|
            asset = AssetObject.from_json(object_data)
            if image_path = asset.image_path
              resolved_path = resolve_slice_path(path, image_path)
              asset.set_image_path(resolved_path)
            end
            layer.add_asset(asset)
          end
        end
      end

      true
    rescue
      false
    end

    private def build_default_layers : Array(MapLayer)
      path_layer = PathLayer.new("Road Net", "Paths", true, Qt6::Color.new(173, 86, 54))
      seed_default_path_objects(path_layer)

      text_layer = TextLayer.new("Operational Labels", "Text", true, Qt6::Color.new(66, 78, 118))
      seed_default_text_objects(text_layer)

      asset_layer = AssetLayer.new("Counters", "Assets", true, Qt6::Color.new(94, 100, 112))
      seed_default_asset_objects(asset_layer)

      [
        BackgroundLayer.new("Background Wash", "Background", true, Qt6::Color.new(200, 184, 148)),
        TerrainLayer.new("Terrain Fill", "Terrain", true, Qt6::Color.new(86, 132, 92)),
        path_layer,
        text_layer,
        asset_layer,
      ] of MapLayer
    end

    private def seed_default_path_objects(layer : PathLayer) : Nil
      layer.add_path(PathObject.new(1, 3, 4, 4, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(4, 4, 7, 5, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(7, 5, 10, 7, color: layer.accent, width: 3.0, line_type: "dashed"))
      layer.add_path(PathObject.new(10, 7, 13, 8, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(13, 8, 16, 10, color: layer.accent, width: 3.0, line_type: "dotted", opacity: 0.9))
    end

    private def seed_default_text_objects(layer : TextLayer) : Nil
      layer.add_text(TextObject.new("Hill 204", hex_center(4, 3).x + 10.0, hex_center(4, 3).y - 10.0, color: layer.accent, bold: true))
      layer.add_text(TextObject.new("Bridge", hex_center(10, 7).x + 10.0, hex_center(10, 7).y - 10.0, color: layer.accent, bold: true))
      layer.add_text(TextObject.new("Depot", hex_center(14, 9).x + 10.0, hex_center(14, 9).y - 10.0, color: layer.accent, bold: true))
    end

    private def seed_default_asset_objects(layer : AssetLayer) : Nil
      layer.add_asset(AssetObject.new(hex_center(3, 2).x, hex_center(3, 2).y, bundled_asset_path("tac85_building-summer_a8p5byyix8hy1ge.png"), scale: 0.5))
      layer.add_asset(AssetObject.new(hex_center(8, 6).x, hex_center(8, 6).y, bundled_asset_path("tac85_building-summer_tw2amtkh0ycpaay.png"), scale: 0.5, rotation: -8.0))
      layer.add_asset(AssetObject.new(hex_center(12, 4).x, hex_center(12, 4).y, bundled_asset_path("tac85_building-summer_xyyob80co6zekmx.png"), scale: 0.5, rotation: 12.0))
      layer.add_asset(AssetObject.new(hex_center(15, 9).x, hex_center(15, 9).y, bundled_asset_path("tac85_building-summer_20przpvea1w32mm.png"), scale: 0.5, opacity: 0.95))
    end

    private def bundled_asset_path(file_name : String) : String?
      path = File.expand_path("../../assets/assets/tac85/#{file_name}", __DIR__)
      File.exists?(path) ? path : nil
    end

    private def resolve_slice_path(slice_path : String, image_path : String) : String
      return image_path if Path[image_path].absolute?

      File.expand_path(image_path, File.dirname(slice_path))
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

    def nearest_hex_center(world : Qt6::PointF) : Qt6::PointF?
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
            best = center
          end
        end
      end

      best
    end

    private def valid_hex_coord?(col : Int32, row : Int32) : Bool
      col >= 0 && col < @cols && row >= 0 && row < @rows
    end

    def hex_label(col : Int32, row : Int32) : String
      letter = ('A'.ord + col).chr
      "#{letter}#{(row + 1).to_s.rjust(2, '0')}"
    end

  end
end