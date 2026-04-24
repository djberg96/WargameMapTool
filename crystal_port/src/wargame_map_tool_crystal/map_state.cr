require "json"
require "qt6"
require "./layers"

module WargameMapToolCrystal
  VERSION = "0.1.0"

  class MapState
    TOOL_NAMES = ["Background", "Fill", "Border", "Hexside", "Path", "Freeform", "Text", "Asset"] of String

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
    property fill_radius : Int32
    property pending_path_anchor : Tuple(Int32, Int32)?
    property selected_border_object : BorderObject?
    property selected_hexside_object : HexsideObject?
    property selected_path_object : PathObject?
    property selected_freeform_path_object : FreeformPathObject?
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
      @fill_radius = 0
      @pending_path_anchor = nil
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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
      @fill_radius = 0
      @pending_path_anchor = nil
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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

    def terrain_layer : TerrainLayer?
      @layers.each do |layer|
        return layer.as(TerrainLayer) if layer.is_a?(TerrainLayer)
      end

      nil
    end

    def text_layer : TextLayer?
      @layers.each do |layer|
        return layer.as(TextLayer) if layer.is_a?(TextLayer)
      end

      nil
    end

    def border_layer : BorderLayer?
      @layers.each do |layer|
        return layer.as(BorderLayer) if layer.is_a?(BorderLayer)
      end

      nil
    end

    def path_layer : PathLayer?
      @layers.each do |layer|
        return layer.as(PathLayer) if layer.is_a?(PathLayer)
      end

      nil
    end

    def freeform_path_layer : FreeformPathLayer?
      @layers.each do |layer|
        return layer.as(FreeformPathLayer) if layer.is_a?(FreeformPathLayer)
      end

      nil
    end

    def hexside_layer : HexsideLayer?
      @layers.each do |layer|
        return layer.as(HexsideLayer) if layer.is_a?(HexsideLayer)
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

    def border_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(BorderLayer)
      end

      nil
    end

    def terrain_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(TerrainLayer)
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

    def freeform_path_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(FreeformPathLayer)
      end

      nil
    end

    def hexside_layer_index : Int32?
      @layers.each_with_index do |layer, index|
        return index.to_i32 if layer.is_a?(HexsideLayer)
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
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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

    def clear_pending_path_anchor : Nil
      @pending_path_anchor = nil
    end

    def begin_pending_path(anchor : Tuple(Int32, Int32)) : Tuple(Int32, Int32)
      activate_path_layer
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @pending_path_anchor = anchor
      anchor
    end

    def create_path_from_pending(target : Tuple(Int32, Int32)) : PathObject?
      anchor = @pending_path_anchor
      layer = path_layer
      return nil unless anchor && layer
      return nil if anchor == target
      return nil unless neighboring_hexes?(anchor[0], anchor[1], target[0], target[1])

      activate_path_layer
      style_source = selected_path_present? ? @selected_path_object : nil
      object = PathObject.new(
        anchor[0],
        anchor[1],
        target[0],
        target[1],
        color: style_source ? style_source.color : layer.accent,
        width: style_source ? style_source.width : 3.0,
        line_type: style_source ? style_source.line_type : "solid",
        opacity: style_source ? style_source.opacity : 1.0,
      )

      layer.add_path(object)
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = object
      @pending_path_anchor = nil
      object
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

      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = object
      layer.add_path(object)
      object
    end

    def selected_freeform_path_present? : Bool
      object = @selected_freeform_path_object
      layer = freeform_path_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def clear_freeform_path_selection : Nil
      @selected_freeform_path_object = nil
    end

    def create_freeform_path(points : Array(Tuple(Float64, Float64))) : FreeformPathObject?
      layer = freeform_path_layer
      return nil unless layer
      return nil unless points.size >= 2

      activate_freeform_path_layer
      style_source = selected_freeform_path_present? ? @selected_freeform_path_object : nil
      object = FreeformPathObject.new(
        points,
        style_source ? style_source.color : layer.accent,
        style_source ? style_source.width : 3.0,
        style_source ? style_source.opacity : 1.0,
      )

      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @pending_path_anchor = nil
      @selected_freeform_path_object = object
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
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_freeform_path_object = nil
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
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = object
      object
    end

    def select_hovered_path : PathObject?
      object = hovered_path_object
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @pending_path_anchor = nil
      @selected_path_object = object
      object
    end

    def select_hovered_freeform_path : FreeformPathObject?
      object = hovered_freeform_path_object
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @pending_path_anchor = nil
      @selected_freeform_path_object = object
      object
    end

    def hovered_freeform_path_object : FreeformPathObject?
      screen = @hover_screen
      layer = freeform_path_layer
      return nil unless screen && layer

      layer.nearest_path(self, screen)
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

          json.field "terrain" do
            if terrain = terrain_layer
              json.object do
                json.field "fill_radius", @fill_radius
                json.field "accent" do
                  json.object do
                    json.field "red", terrain.accent.red
                    json.field "green", terrain.accent.green
                    json.field "blue", terrain.accent.blue
                    json.field "alpha", terrain.accent.alpha
                  end
                end
                json.field "fills" do
                  json.array do
                    terrain.fills.each do |coords, color|
                      json.object do
                        json.field "col", coords[0]
                        json.field "row", coords[1]
                        json.field "color" do
                          json.object do
                            json.field "red", color.red
                            json.field "green", color.green
                            json.field "blue", color.blue
                            json.field "alpha", color.alpha
                          end
                        end
                      end
                    end
                  end
                end
              end
            else
              json.null
            end
          end

          json.field "border_objects" do
            if layer = border_layer
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

          json.field "hexside_objects" do
            if layer = hexside_layer
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

          json.field "freeform_path_objects" do
            if layer = freeform_path_layer
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

      terrain_data = data["terrain"]?
      if terrain_data && (terrain = terrain_layer)
        terrain.clear_fills
        @fill_radius = (terrain_data["fill_radius"]?.try(&.as_i?) || 0).to_i32.clamp(0, 3)

        if accent_data = terrain_data["accent"]?
          terrain.accent = Qt6::Color.new(
            (accent_data["red"]?.try(&.as_i?) || terrain.accent.red).to_i32,
            (accent_data["green"]?.try(&.as_i?) || terrain.accent.green).to_i32,
            (accent_data["blue"]?.try(&.as_i?) || terrain.accent.blue).to_i32,
            (accent_data["alpha"]?.try(&.as_i?) || terrain.accent.alpha).to_i32,
          )
        end

        terrain_data["fills"]?.try(&.as_a?).try do |fills|
          fills.each do |fill_data|
            color_data = fill_data["color"]?
            color = Qt6::Color.new(
              (color_data.try { |value| value["red"]?.try(&.as_i?) } || terrain.accent.red).to_i32,
              (color_data.try { |value| value["green"]?.try(&.as_i?) } || terrain.accent.green).to_i32,
              (color_data.try { |value| value["blue"]?.try(&.as_i?) } || terrain.accent.blue).to_i32,
              (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
            )
            terrain.set_fill(
              (fill_data["col"]?.try(&.as_i?) || 0).to_i32,
              (fill_data["row"]?.try(&.as_i?) || 0).to_i32,
              color,
            )
          end
        end
      end

      @selected_border_object = nil
      @selected_hexside_object = nil
      data["border_objects"]?.try(&.as_a?).try do |objects|
        if layer = border_layer
          layer.clear_borders
          objects.each do |object_data|
            layer.add_border(BorderObject.from_json(object_data))
          end
        end
      end

      data["hexside_objects"]?.try(&.as_a?).try do |objects|
        if layer = hexside_layer
          layer.clear_hexsides
          objects.each do |object_data|
            layer.add_hexside(HexsideObject.from_json(object_data))
          end
        end
      end

      text_layer.try(&.clear_texts)
      @pending_path_anchor = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
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

      data["freeform_path_objects"]?.try(&.as_a?).try do |objects|
        if layer = freeform_path_layer
          layer.clear_paths
          objects.each do |object_data|
            layer.add_path(FreeformPathObject.from_json(object_data))
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
      freeform_path_layer = FreeformPathLayer.new("Freeform Paths", "Freeform Paths", true, Qt6::Color.new(82, 122, 164))
      seed_default_freeform_path_objects(freeform_path_layer)

      border_layer = BorderLayer.new("Borders", "Borders", true, Qt6::Color.new(58, 54, 48))
      hexside_layer = HexsideLayer.new("Hexsides", "Hexsides", true, Qt6::Color.new(70, 108, 154))

      text_layer = TextLayer.new("Operational Labels", "Text", true, Qt6::Color.new(66, 78, 118))
      seed_default_text_objects(text_layer)

      asset_layer = AssetLayer.new("Counters", "Assets", true, Qt6::Color.new(94, 100, 112))
      seed_default_asset_objects(asset_layer)

      [
        BackgroundLayer.new("Background Wash", "Background", true, Qt6::Color.new(200, 184, 148)),
        TerrainLayer.new("Terrain Fill", "Terrain", true, Qt6::Color.new(86, 132, 92)),
        border_layer,
        hexside_layer,
        path_layer,
        freeform_path_layer,
        text_layer,
        asset_layer,
      ] of MapLayer
    end

    private def activate_path_layer : Nil
      if index = path_layer_index
        set_active_layer(index)
      end
    end

    private def activate_freeform_path_layer : Nil
      if index = freeform_path_layer_index
        set_active_layer(index)
      end
    end

    def selected_border_present? : Bool
      object = @selected_border_object
      layer = border_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def selected_hexside_present? : Bool
      object = @selected_hexside_object
      layer = hexside_layer
      return false unless object && layer

      layer.objects.includes?(object)
    end

    def clear_border_selection : Nil
      @selected_border_object = nil
    end

    def clear_hexside_selection : Nil
      @selected_hexside_object = nil
    end

    def create_border(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : BorderObject?
      layer = border_layer
      return nil unless layer
      return nil unless neighboring_hexes?(col_a, row_a, col_b, row_b)
      return nil if layer.border_at(col_a, row_a, col_b, row_b)

      if index = border_layer_index
        set_active_layer(index)
      end

      style_source = selected_border_present? ? @selected_border_object : nil
      object = BorderObject.new(
        col_a,
        row_a,
        col_b,
        row_b,
        style_source ? style_source.color : layer.accent,
        style_source ? style_source.width : 3.0,
        style_source ? style_source.line_type : "solid",
      )

      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
      @selected_hexside_object = nil
      @selected_border_object = object
      layer.add_border(object)
      object
    end

    def create_hexside(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : HexsideObject?
      layer = hexside_layer
      return nil unless layer
      return nil unless neighboring_hexes?(col_a, row_a, col_b, row_b)
      return nil if layer.hexside_at(col_a, row_a, col_b, row_b)

      if index = hexside_layer_index
        set_active_layer(index)
      end

      style_source = selected_hexside_present? ? @selected_hexside_object : nil
      object = HexsideObject.new(
        col_a,
        row_a,
        col_b,
        row_b,
        style_source ? style_source.color : layer.accent,
        style_source ? style_source.width : 4.0,
        style_source ? style_source.opacity : 1.0,
      )

      @selected_border_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
      @selected_hexside_object = object
      layer.add_hexside(object)
      object
    end

    def shared_edge_points(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : Tuple(Qt6::PointF, Qt6::PointF)?
      return nil unless neighboring_hexes?(col_a, row_a, col_b, row_b)

      points_a = hex_points(col_a, row_a)
      points_b = hex_points(col_b, row_b)
      shared = [] of Qt6::PointF

      points_a.each do |point_a|
        points_b.each do |point_b|
          dx = point_a.x - point_b.x
          dy = point_a.y - point_b.y
          if Math.sqrt(dx * dx + dy * dy) <= 0.01
            shared << point_a
            break
          end
        end
      end

      return nil unless shared.size == 2

      {shared[0], shared[1]}
    end

    def adjacent_hexes(col : Int32, row : Int32) : Array(Tuple(Int32, Int32))
      hexes = [] of Tuple(Int32, Int32)

      @rows.times do |candidate_row|
        @cols.times do |candidate_col|
          next if candidate_col == col && candidate_row == row
          next unless neighboring_hexes?(col, row, candidate_col, candidate_row)

          hexes << {candidate_col, candidate_row}
        end
      end

      hexes
    end

    private def seed_default_path_objects(layer : PathLayer) : Nil
      layer.add_path(PathObject.new(1, 3, 4, 4, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(4, 4, 7, 5, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(7, 5, 10, 7, color: layer.accent, width: 3.0, line_type: "dashed"))
      layer.add_path(PathObject.new(10, 7, 13, 8, color: layer.accent, width: 3.0))
      layer.add_path(PathObject.new(13, 8, 16, 10, color: layer.accent, width: 3.0, line_type: "dotted", opacity: 0.9))
    end

    private def seed_default_freeform_path_objects(layer : FreeformPathLayer) : Nil
      layer.add_path(FreeformPathObject.new([
        {hex_center(2, 9).x - 18.0, hex_center(2, 9).y - 12.0},
        {hex_center(3, 8).x - 4.0, hex_center(3, 8).y + 8.0},
        {hex_center(4, 8).x + 16.0, hex_center(4, 8).y - 10.0},
        {hex_center(6, 7).x + 4.0, hex_center(6, 7).y + 12.0},
        {hex_center(7, 6).x + 18.0, hex_center(7, 6).y - 6.0},
      ] of Tuple(Float64, Float64), color: layer.accent, width: 3.5, opacity: 0.92))
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

    def neighboring_hexes?(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : Bool
      return false unless valid_hex_coord?(col_a, row_a) && valid_hex_coord?(col_b, row_b)

      q_a = col_a - ((row_a - (row_a & 1)) // 2)
      r_a = row_a
      s_a = -q_a - r_a

      q_b = col_b - ((row_b - (row_b & 1)) // 2)
      r_b = row_b
      s_b = -q_b - r_b

      ((q_a - q_b).abs + (r_a - r_b).abs + (s_a - s_b).abs) // 2 == 1
    end

    def hexes_in_radius(center_col : Int32, center_row : Int32, radius : Int32 = @fill_radius) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) unless valid_hex_coord?(center_col, center_row)

      limit = radius.clamp(0, [@cols, @rows].min)
      return [{center_col, center_row}] if limit == 0

      center_q, center_r, center_s = offset_to_cube(center_col, center_row)
      hexes = [] of Tuple(Int32, Int32)

      @rows.times do |row|
        @cols.times do |col|
          q, r, s = offset_to_cube(col, row)
          distance = ((center_q - q).abs + (center_r - r).abs + (center_s - s).abs) // 2
          hexes << {col, row} if distance <= limit
        end
      end

      hexes
    end

    private def valid_hex_coord?(col : Int32, row : Int32) : Bool
      col >= 0 && col < @cols && row >= 0 && row < @rows
    end

    private def offset_to_cube(col : Int32, row : Int32) : Tuple(Int32, Int32, Int32)
      q = col - ((row - (row & 1)) // 2)
      r = row
      s = -q - r
      {q, r, s}
    end

    def hex_label(col : Int32, row : Int32) : String
      letter = ('A'.ord + col).chr
      "#{letter}#{(row + 1).to_s.rjust(2, '0')}"
    end

  end
end