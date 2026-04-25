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
    property grid_orientation : String
    property first_row_offset : String
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
      @grid_orientation = "pointy"
      @first_row_offset = "even"
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
      @grid_orientation = "pointy"
      @first_row_offset = "even"
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
          json.field "grid" do
            json.object do
              json.field "width", @cols
              json.field "height", @rows
              json.field "hex_size", @hex_radius
              json.field "orientation", @grid_orientation
              json.field "first_row_offset", @first_row_offset
              json.field "show_grid", @show_grid
              json.field "show_coordinates", @show_coordinates
            end
          end

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
      apply_grid_config(data["grid"]?) if data["grid"]?
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

    def load_hexmap(path : String) : String?
      data = JSON.parse(File.read(path))

      reset
      @project_path = nil
      @source_path = path
      apply_grid_config(data["grid"]?)
      clear_ported_layer_content

      skipped_types = [] of String

      data["layers"]?.try(&.as_a?).try do |layers|
        layers.each do |layer_data|
          layer_type = layer_data["type"]?.try(&.as_s?) || ""

          case layer_type
          when "background"
            import_background_layer(path, layer_data)
          when "fill"
            import_fill_layer(layer_data)
          when "border"
            import_border_layer(layer_data)
          when "hexside"
            import_hexside_layer(layer_data)
          when "path"
            import_path_layer(layer_data)
          when "freeform_path"
            import_freeform_path_layer(layer_data)
          when "text"
            import_text_layer(layer_data)
          when "asset"
            import_asset_layer(path, layer_data)
          when ""
          else
            skipped_types << layer_type
          end
        end
      end

      if skipped_types.empty?
        "Opened #{File.basename(path)}"
      else
        "Opened #{File.basename(path)} (skipped #{skipped_types.uniq.sort.join(", ")})"
      end
    rescue
      nil
    end

    def save_hexmap(path : String) : Nil
      tmp_path = ""
      tmp_path = "#{path}.tmp"
      File.write(tmp_path, JSON.build do |json|
        json.object do
          json.field "version", 1
          json.field "grid" do
            write_hexmap_grid(json)
          end
          json.field "layers" do
            json.array do
              if layer = background_layer
                write_hexmap_background_layer(json, layer, path)
              end
              if layer = terrain_layer
                write_hexmap_fill_layer(json, layer)
              end
              if layer = hexside_layer
                write_hexmap_hexside_layer(json, layer)
              end
              if layer = border_layer
                write_hexmap_border_layer(json, layer)
              end
              if layer = path_layer
                write_hexmap_path_layer(json, layer)
              end
              if layer = freeform_path_layer
                write_hexmap_freeform_path_layer(json, layer)
              end
              if layer = text_layer
                write_hexmap_text_layer(json, layer)
              end
              if layer = asset_layer
                write_hexmap_asset_layer(json, layer, path)
              end
            end
          end
        end
      end)
      File.rename(tmp_path, path)
      @source_path = path
    rescue error
      File.delete(tmp_path.not_nil!) if File.exists?(tmp_path.not_nil!)
      raise error
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
      path = File.expand_path("../../../assets/assets/tac85/#{file_name}", __DIR__)
      File.exists?(path) ? path : nil
    end

    private def clear_ported_layer_content : Nil
      if layer = background_layer
        layer.clear_image
        layer.offset_x = 0.0
        layer.offset_y = 0.0
        layer.scale = 1.0
        layer.visible = true
        layer.opacity = 100
      end

      if layer = terrain_layer
        layer.clear_fills
        layer.visible = true
        layer.opacity = 100
      end

      border_layer.try(&.clear_borders)
      hexside_layer.try(&.clear_hexsides)
      path_layer.try(&.clear_paths)
      freeform_path_layer.try(&.clear_paths)
      text_layer.try(&.clear_texts)
      asset_layer.try(&.clear_assets)

      @fill_radius = 0
      @pending_path_anchor = nil
      @selected_border_object = nil
      @selected_hexside_object = nil
      @selected_path_object = nil
      @selected_freeform_path_object = nil
      @selected_text_object = nil
      @selected_asset_object = nil
      @active_tool = "Fill"
      @active_layer_index = 1
    end

    private def apply_grid_config(grid_data : JSON::Any?) : Nil
      return unless grid = grid_data

      @cols = (grid["width"]?.try(&.as_i?) || @cols).to_i32.clamp(1, 500)
      @rows = (grid["height"]?.try(&.as_i?) || @rows).to_i32.clamp(1, 500)
      @hex_radius = json_number(grid["hex_size"]?) || @hex_radius
      @hex_radius = @hex_radius.clamp(6.0, 256.0)
      @grid_orientation = normalize_orientation(grid["orientation"]?.try(&.as_s?))
      @first_row_offset = normalize_row_offset(grid["first_row_offset"]?.try(&.as_s?))
      @show_grid = grid["show_grid"]?.try(&.as_bool?) != false
      @show_coordinates = grid["show_coordinates"]?.try(&.as_bool?) || false
    end

    private def import_background_layer(project_path : String, data : JSON::Any) : Nil
      layer = background_layer
      return unless layer

      apply_layer_base(layer, data)
      image_path = data["edited_image_path"]?.try(&.as_s?)
      image_path = data["image_path"]?.try(&.as_s?) if image_path.nil? || image_path.try(&.empty?)

      if path = image_path
        resolved_path = resolve_project_asset_path(project_path, path)
        layer.load_image(resolved_path) unless resolved_path.empty?
      end

      layer.offset_x = json_number(data["offset_x"]?) || 0.0
      layer.offset_y = json_number(data["offset_y"]?) || 0.0
      layer.scale = (json_number(data["scale"]?) || 1.0).clamp(0.05, 20.0)
    end

    private def import_fill_layer(data : JSON::Any) : Nil
      layer = terrain_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["hexes"]?.try(&.as_h?).try do |hexes|
        hexes.each do |key, value|
          coords = axial_key_to_offset(key)
          next unless coords
          next unless valid_hex_coord?(coords[0], coords[1])

          color = color_from_json(value, layer.accent)
          layer.set_fill(coords[0], coords[1], color)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_border_layer(data : JSON::Any) : Nil
      layer = border_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["borders"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          start_coords = axial_coords_to_offset(
            (object_data["hex_a_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_a_r"]?.try(&.as_i?) || 0).to_i32,
          )
          end_coords = axial_coords_to_offset(
            (object_data["hex_b_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_b_r"]?.try(&.as_i?) || 0).to_i32,
          )
          next unless valid_hex_coord?(start_coords[0], start_coords[1]) && valid_hex_coord?(end_coords[0], end_coords[1])

          color = color_from_json(object_data["color"]?, layer.accent)
          object = BorderObject.new(
            start_coords[0],
            start_coords[1],
            end_coords[0],
            end_coords[1],
            color,
            json_number(object_data["width"]?) || 3.0,
            normalize_line_type(object_data["line_type"]?.try(&.as_s?)),
          )
          layer.add_border(object)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_hexside_layer(data : JSON::Any) : Nil
      layer = hexside_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["hexsides"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          start_coords = axial_coords_to_offset(
            (object_data["hex_a_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_a_r"]?.try(&.as_i?) || 0).to_i32,
          )
          end_coords = axial_coords_to_offset(
            (object_data["hex_b_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_b_r"]?.try(&.as_i?) || 0).to_i32,
          )
          next unless valid_hex_coord?(start_coords[0], start_coords[1]) && valid_hex_coord?(end_coords[0], end_coords[1])

          color = color_from_json(object_data["color"]?, layer.accent)
          object = HexsideObject.new(
            start_coords[0],
            start_coords[1],
            end_coords[0],
            end_coords[1],
            color,
            json_number(object_data["width"]?) || 4.0,
            object_opacity(object_data["opacity"]?),
          )
          layer.add_hexside(object)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_path_layer(data : JSON::Any) : Nil
      layer = path_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["paths"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          start_coords = axial_coords_to_offset(
            (object_data["hex_a_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_a_r"]?.try(&.as_i?) || 0).to_i32,
          )
          end_coords = axial_coords_to_offset(
            (object_data["hex_b_q"]?.try(&.as_i?) || 0).to_i32,
            (object_data["hex_b_r"]?.try(&.as_i?) || 0).to_i32,
          )
          next unless valid_hex_coord?(start_coords[0], start_coords[1]) && valid_hex_coord?(end_coords[0], end_coords[1])

          color = color_from_json(object_data["color"]?, layer.accent)
          object = PathObject.new(
            start_coords[0],
            start_coords[1],
            end_coords[0],
            end_coords[1],
            color,
            json_number(object_data["width"]?) || 3.0,
            normalize_line_type(object_data["line_type"]?.try(&.as_s?)),
            object_opacity(object_data["opacity"]?),
          )
          layer.add_path(object)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_freeform_path_layer(data : JSON::Any) : Nil
      layer = freeform_path_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["paths"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          points = [] of Tuple(Float64, Float64)
          object_data["points"]?.try(&.as_a?).try do |items|
            items.each do |item|
              if coords = item.as_a?
                next unless coords.size >= 2
                x = json_number(coords[0]?) || 0.0
                y = json_number(coords[1]?) || 0.0
                points << {x, y}
              end
            end
          end
          next unless points.size >= 2

          color = color_from_json(object_data["color"]?, layer.accent)
          object = FreeformPathObject.new(
            points,
            color,
            json_number(object_data["width"]?) || 3.0,
            object_opacity(object_data["opacity"]?),
          )
          layer.add_path(object)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_text_layer(data : JSON::Any) : Nil
      layer = text_layer
      return unless layer

      apply_layer_base(layer, data)
      first_color = nil.as(Qt6::Color?)

      data["objects"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          color = color_from_json(object_data["color"]?, layer.accent)
          object = TextObject.new(
            object_data["text"]?.try(&.as_s?) || "Text",
            json_number(object_data["x"]?) || 0.0,
            json_number(object_data["y"]?) || 0.0,
            object_data["font_family"]?.try(&.as_s?) || "Avenir Next",
            ((json_number(object_data["font_size"]?) || 12.0).round.to_i).clamp(6, 144),
            object_data["bold"]?.try(&.as_bool?) || false,
            object_data["italic"]?.try(&.as_bool?) || false,
            color,
            normalize_alignment(object_data["alignment"]?.try(&.as_s?)),
            object_opacity(object_data["opacity"]?),
            json_number(object_data["rotation"]?) || 0.0,
          )
          layer.add_text(object)
          first_color ||= color
        end
      end

      layer.accent = first_color.not_nil! if first_color
    end

    private def import_asset_layer(project_path : String, data : JSON::Any) : Nil
      layer = asset_layer
      return unless layer

      apply_layer_base(layer, data)

      data["objects"]?.try(&.as_a?).try do |objects|
        objects.each do |object_data|
          image_path = object_data["image"]?.try(&.as_s?)
          resolved_path = image_path.try { |value| resolve_project_asset_path(project_path, value) }
          object = AssetObject.new(
            json_number(object_data["x"]?) || 0.0,
            json_number(object_data["y"]?) || 0.0,
            resolved_path,
            scale: json_number(object_data["scale"]?) || 1.0,
            rotation: json_number(object_data["rotation"]?) || 0.0,
            opacity: object_opacity(object_data["opacity"]?),
            snap_to_hex: object_data["snap_to_hex"]?.try(&.as_bool?) != false,
          )
          layer.add_asset(object)
        end
      end
    end

    private def write_hexmap_grid(json : JSON::Builder) : Nil
      json.object do
        json.field "hex_size", @hex_radius
        json.field "hex_size_mm", hex_size_mm
        json.field "width", @cols
        json.field "height", @rows
        json.field "orientation", @grid_orientation
        json.field "line_width", 1.0
        json.field "edge_color", "#000000"
        json.field "show_center_dots", false
        json.field "show_coordinates", @show_coordinates
        json.field "first_row_offset", @first_row_offset
        json.field "center_dot_size", 3.0
        json.field "center_dot_color", "#000000"
        json.field "coord_position", "top"
        json.field "coord_format", "numeric_dot"
        json.field "show_border", false
        json.field "border_color", "#000000"
        json.field "coord_offset_y", 0.0
        json.field "coord_font_scale", 18
        json.field "coord_start_one", false
        json.field "border_margin", 2.0
        json.field "border_fill", false
        json.field "border_fill_color", "#ffffff"
        json.field "half_hexes", false
        json.field "grid_style", "lines"
        json.field "center_dot_outline", false
        json.field "center_dot_outline_width", 1.0
        json.field "center_dot_outline_color", "#ffffff"
        json.field "grid_opacity", 100
        json.field "center_dot_opacity", 100
        json.field "coord_opacity", 100
        json.field "megahex_opacity", 100
        json.field "megahex_enabled", false
        json.field "megahex_radius", 1
        json.field "megahex_mode", "hex_edges"
        json.field "megahex_color", "#646464"
        json.field "megahex_width", 3.0
        json.field "megahex_offset_q", 0
        json.field "megahex_offset_r", 0
        json.field "canvas_bg_color", "#2b2b2b"
        json.field "show_grid", @show_grid
        json.field "global_lighting_enabled", false
        json.field "global_lighting_color", "#ffdc64"
        json.field "global_lighting_opacity", 0
        json.field "grain_enabled", false
        json.field "grain_intensity", 20
        json.field "grain_scale", 1.0
        json.field "grain_monochrome", true
        json.field "grain_seed", 42
      end
    end

    private def write_hexmap_background_layer(json : JSON::Builder, layer : BackgroundLayer, output_path : String) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "background", "crystal_background")
        image_path = layer.image_path
        json.field "image_path", export_image_reference(output_path, image_path) if image_path
        json.field "offset_x", layer.offset_x
        json.field "offset_y", layer.offset_y
        json.field "scale", layer.scale
        json.field "clip_to_grid", false
      end
    end

    private def write_hexmap_fill_layer(json : JSON::Builder, layer : TerrainLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "fill", "crystal_fill")
        json.field "hexes" do
          json.object do
            layer.fills.each do |coords, color|
              q, r = offset_to_axial(coords[0], coords[1])
              json.field "#{q},#{r}", hex_color_string(color)
            end
          end
        end
        json.field "dot_colors" do
          json.object do
          end
        end
        json.field "coord_colors" do
          json.object do
          end
        end
      end
    end

    private def write_hexmap_hexside_layer(json : JSON::Builder, layer : HexsideLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "hexside", "crystal_hexside")
        json.field "hexsides" do
          json.array do
            layer.objects.each do |object|
              hex_a_q, hex_a_r = offset_to_axial(object.col_a, object.row_a)
              hex_b_q, hex_b_r = offset_to_axial(object.col_b, object.row_b)

              json.object do
                json.field "hex_a_q", hex_a_q
                json.field "hex_a_r", hex_a_r
                json.field "hex_b_q", hex_b_q
                json.field "hex_b_r", hex_b_r
                json.field "color", hex_color_string(object.color)
                json.field "width", object.width
                json.field "opacity", object.opacity
                json.field "random_seed", 0
              end
            end
          end
        end
      end
    end

    private def write_hexmap_border_layer(json : JSON::Builder, layer : BorderLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "border", "crystal_border")
        json.field "borders" do
          json.array do
            layer.objects.each do |object|
              hex_a_q, hex_a_r = offset_to_axial(object.col_a, object.row_a)
              hex_b_q, hex_b_r = offset_to_axial(object.col_b, object.row_b)

              json.object do
                json.field "hex_a_q", hex_a_q
                json.field "hex_a_r", hex_a_r
                json.field "hex_b_q", hex_b_q
                json.field "hex_b_r", hex_b_r
                json.field "color", hex_color_string(object.color)
                json.field "width", object.width
                if object.line_type != "solid"
                  json.field "line_type", object.line_type
                  json.field "element_size", 4.0
                  json.field "gap_size", 4.0
                end
              end
            end
          end
        end
      end
    end

    private def write_hexmap_path_layer(json : JSON::Builder, layer : PathLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "path", "crystal_path")
        json.field "paths" do
          json.array do
            layer.objects.each do |object|
              hex_a_q, hex_a_r = offset_to_axial(object.col_a, object.row_a)
              hex_b_q, hex_b_r = offset_to_axial(object.col_b, object.row_b)

              json.object do
                json.field "hex_a_q", hex_a_q
                json.field "hex_a_r", hex_a_r
                json.field "hex_b_q", hex_b_q
                json.field "hex_b_r", hex_b_r
                json.field "color", hex_color_string(object.color)
                json.field "width", object.width
                json.field "line_type", object.line_type if object.line_type != "solid"
                json.field "opacity", object.opacity if object.opacity != 1.0
                json.field "random_seed", 0
              end
            end
          end
        end
      end
    end

    private def write_hexmap_freeform_path_layer(json : JSON::Builder, layer : FreeformPathLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "freeform_path", "crystal_freeform_path")
        json.field "paths" do
          json.array do
            layer.objects.each do |object|
              json.object do
                json.field "points" do
                  json.array do
                    object.points.each do |point|
                      json.array do
                        json.number point[0]
                        json.number point[1]
                      end
                    end
                  end
                end
                json.field "color", hex_color_string(object.color)
                json.field "width", object.width
                json.field "opacity", object.opacity if object.opacity != 1.0
              end
            end
          end
        end
      end
    end

    private def write_hexmap_text_layer(json : JSON::Builder, layer : TextLayer) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "text", "crystal_text")
        json.field "objects" do
          json.array do
            layer.objects.each do |object|
              json.object do
                json.field "text", object.text
                json.field "x", object.x
                json.field "y", object.y
                json.field "font_family", object.font_family
                json.field "font_size", object.font_size
                json.field "bold", object.bold if object.bold
                json.field "italic", object.italic if object.italic
                json.field "color", hex_color_string(object.color)
                json.field "alignment", object.alignment
                json.field "opacity", object.opacity if object.opacity != 1.0
                json.field "rotation", object.rotation if object.rotation != 0.0
              end
            end
          end
        end
      end
    end

    private def write_hexmap_asset_layer(json : JSON::Builder, layer : AssetLayer, output_path : String) : Nil
      json.object do
        write_hexmap_layer_base(json, layer, "asset", "crystal_asset")
        json.field "objects" do
          json.array do
            layer.objects.each do |object|
              json.object do
                json.field "image", export_image_reference(output_path, object.image_path)
                json.field "x", object.x
                json.field "y", object.y
                json.field "scale", object.scale
                json.field "rotation", object.rotation if object.rotation != 0.0
                json.field "opacity", object.opacity if object.opacity != 1.0
                json.field "snap_to_hex", object.snap_to_hex
              end
            end
          end
        end
      end
    end

    private def write_hexmap_layer_base(json : JSON::Builder, layer : MapLayer, type : String, id : String) : Nil
      json.field "id", id
      json.field "name", layer.name
      json.field "visible", layer.visible
      json.field "opacity", layer.opacity / 100.0
      json.field "type", type
    end

    private def apply_layer_base(layer : MapLayer, data : JSON::Any) : Nil
      layer.name = data["name"]?.try(&.as_s?) || layer.name
      layer.visible = data["visible"]?.try(&.as_bool?) != false
      layer.opacity = layer_opacity_percent(data["opacity"]?)
    end

    private def resolve_project_asset_path(project_path : String, asset_path : String) : String
      return "" if asset_path.empty?
      return asset_path if Path[asset_path].absolute? && File.exists?(asset_path)

      if asset_path.starts_with?("builtin:")
        relative_path = asset_path.sub(/^builtin:/, "")
        return File.expand_path(relative_path, builtin_assets_root)
      end

      File.expand_path(asset_path, File.dirname(project_path))
    end

    private def builtin_assets_root : String
      File.expand_path("../../../assets/assets", __DIR__)
    end

    private def export_image_reference(output_path : String, image_path : String?) : String
      return "" unless image_path

      absolute = File.expand_path(image_path)
      if relative = child_path_within(absolute, builtin_assets_root)
        return "builtin:#{relative}"
      end

      base_dir = File.dirname(File.expand_path(output_path))
      if relative = relative_path_from(base_dir, absolute)
        return relative
      end

      absolute
    end

    private def resolve_slice_path(slice_path : String, image_path : String) : String
      return image_path if Path[image_path].absolute?

      File.expand_path(image_path, File.dirname(slice_path))
    end

    def world_bounds : Qt6::RectF
      return Qt6::RectF.new(0.0, 0.0, 0.0, 0.0) if @cols <= 0 || @rows <= 0

      min_x = Float64::INFINITY
      min_y = Float64::INFINITY
      max_x = -Float64::INFINITY
      max_y = -Float64::INFINITY

      @rows.times do |row|
        @cols.times do |col|
          hex_points(col, row).each do |point|
            min_x = point.x if point.x < min_x
            min_y = point.y if point.y < min_y
            max_x = point.x if point.x > max_x
            max_y = point.y if point.y > max_y
          end
        end
      end

      Qt6::RectF.new(min_x, min_y, max_x - min_x, max_y - min_y)
    end

    def map_width : Float64
      world_bounds.width
    end

    def map_height : Float64
      world_bounds.height
    end

    def horizontal_step : Float64
      if @grid_orientation == "flat"
        @hex_radius * 1.5
      else
        Math.sqrt(3.0) * @hex_radius
      end
    end

    def vertical_step : Float64
      if @grid_orientation == "flat"
        Math.sqrt(3.0) * @hex_radius
      else
        @hex_radius * 1.5
      end
    end

    def hex_center(col : Int32, row : Int32) : Qt6::PointF
      q, r = offset_to_axial(col, row)
      x = if @grid_orientation == "flat"
            (1.5 * q) * @hex_radius + layout_origin_x
          else
            (Math.sqrt(3.0) * q + (Math.sqrt(3.0) / 2.0) * r) * @hex_radius + layout_origin_x
          end
      y = if @grid_orientation == "flat"
            ((Math.sqrt(3.0) / 2.0) * q + Math.sqrt(3.0) * r) * @hex_radius + layout_origin_y
          else
            (1.5 * r) * @hex_radius + layout_origin_y
          end
      Qt6::PointF.new(x, y)
    end

    def hex_points(col : Int32, row : Int32) : Array(Qt6::PointF)
      center = hex_center(col, row)
      points = [] of Qt6::PointF

      6.times do |index|
        angle = hex_corner_start_angle + (Math::PI / 3.0) * index
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
      q, r = offset_to_axial(col, row)
      s = -q - r
      {q, r, s}
    end

    private def offset_to_axial(col : Int32, row : Int32) : Tuple(Int32, Int32)
      if @grid_orientation == "flat"
        q = col
        r = if @first_row_offset == "odd"
              row - ((col - (col & 1)) // 2)
            else
              row - ((col + (col & 1)) // 2)
            end
      else
        q = if @first_row_offset == "odd"
              col - ((row - (row & 1)) // 2)
            else
              col - ((row + (row & 1)) // 2)
            end
        r = row
      end

      {q.to_i32, r.to_i32}
    end

    private def axial_coords_to_offset(q : Int32, r : Int32) : Tuple(Int32, Int32)
      if @grid_orientation == "flat"
        row = if @first_row_offset == "odd"
                r + ((q - (q & 1)) // 2)
              else
                r + ((q + (q & 1)) // 2)
              end
        {q.to_i32, row.to_i32}
      else
        col = if @first_row_offset == "odd"
                q + ((r - (r & 1)) // 2)
              else
                q + ((r + (r & 1)) // 2)
              end
        {col.to_i32, r.to_i32}
      end
    end

    private def axial_key_to_offset(key : String) : Tuple(Int32, Int32)?
      parts = key.split(",", 2)
      return nil unless parts.size == 2

      q = parts[0].to_i?
      r = parts[1].to_i?
      return nil unless q && r

      axial_coords_to_offset(q.to_i32, r.to_i32)
    end

    private def json_number(value : JSON::Any?) : Float64?
      return nil unless value

      value.as_f? || value.as_i?.try(&.to_f64)
    end

    private def color_from_json(value : JSON::Any?, default : Qt6::Color) : Qt6::Color
      return default unless value

      if string_value = value.as_s?
        parse_hex_color(string_value, default)
      else
        Qt6::Color.new(
          (value["red"]?.try(&.as_i?) || default.red).to_i32,
          (value["green"]?.try(&.as_i?) || default.green).to_i32,
          (value["blue"]?.try(&.as_i?) || default.blue).to_i32,
          (value["alpha"]?.try(&.as_i?) || default.alpha).to_i32,
        )
      end
    end

    private def parse_hex_color(value : String, default : Qt6::Color) : Qt6::Color
      clean = value.starts_with?("#") ? value[1..] : value

      case clean.size
      when 3
        r = "#{clean[0]}#{clean[0]}".to_i?(16)
        g = "#{clean[1]}#{clean[1]}".to_i?(16)
        b = "#{clean[2]}#{clean[2]}".to_i?(16)
        return default unless r && g && b

        Qt6::Color.new(r, g, b, 255)
      when 4
        a = "#{clean[0]}#{clean[0]}".to_i?(16)
        r = "#{clean[1]}#{clean[1]}".to_i?(16)
        g = "#{clean[2]}#{clean[2]}".to_i?(16)
        b = "#{clean[3]}#{clean[3]}".to_i?(16)
        return default unless a && r && g && b

        Qt6::Color.new(r, g, b, a)
      when 6
        r = clean[0, 2].to_i?(16)
        g = clean[2, 2].to_i?(16)
        b = clean[4, 2].to_i?(16)
        return default unless r && g && b

        Qt6::Color.new(r, g, b, 255)
      when 8
        a = clean[0, 2].to_i?(16)
        r = clean[2, 2].to_i?(16)
        g = clean[4, 2].to_i?(16)
        b = clean[6, 2].to_i?(16)
        return default unless a && r && g && b

        Qt6::Color.new(r, g, b, a)
      else
        default
      end
    end

    private def hex_color_string(color : Qt6::Color) : String
      if color.alpha < 255
        "#%02x%02x%02x%02x" % {color.alpha, color.red, color.green, color.blue}
      else
        "#%02x%02x%02x" % {color.red, color.green, color.blue}
      end
    end

    private def object_opacity(value : JSON::Any?, default : Float64 = 1.0) : Float64
      opacity = json_number(value)
      return default unless opacity

      if opacity > 1.0
        (opacity / 100.0).clamp(0.0, 1.0)
      else
        opacity.clamp(0.0, 1.0)
      end
    end

    private def layer_opacity_percent(value : JSON::Any?, default : Int32 = 100) : Int32
      opacity = json_number(value)
      return default unless opacity

      if opacity > 1.0
        opacity.round.to_i32.clamp(0, 100)
      else
        (opacity * 100.0).round.to_i32.clamp(0, 100)
      end
    end

    private def normalize_orientation(value : String?) : String
      value == "flat" ? "flat" : "pointy"
    end

    private def normalize_row_offset(value : String?) : String
      value == "odd" ? "odd" : "even"
    end

    private def normalize_line_type(value : String?) : String
      case value
      when "dashed", "dotted"
        value.not_nil!
      when "lined"
        "dashed"
      else
        "solid"
      end
    end

    private def normalize_alignment(value : String?) : String
      case value
      when "center", "right"
        value.not_nil!
      else
        "left"
      end
    end

    private def layout_origin_x : Float64
      @hex_radius * 2.0
    end

    private def layout_origin_y : Float64
      @hex_radius * 2.0
    end

    private def hex_corner_start_angle : Float64
      @grid_orientation == "flat" ? 0.0 : Math::PI / 6.0
    end

    private def hex_size_mm : Float64
      (Math.sqrt(3.0) * @hex_radius) * 25.4 / 96.0
    end

    private def child_path_within(path : String, parent : String) : String?
      normalized_path = File.expand_path(path)
      normalized_parent = File.expand_path(parent)
      prefix = "#{normalized_parent}/"

      return "" if normalized_path == normalized_parent
      return nil unless normalized_path.starts_with?(prefix)

      normalized_path.byte_slice(prefix.bytesize, normalized_path.bytesize - prefix.bytesize)
    end

    private def relative_path_from(base_dir : String, target_path : String) : String?
      normalized_base = File.expand_path(base_dir)
      normalized_target = File.expand_path(target_path)
      return "." if normalized_base == normalized_target

      base_prefix = absolute_path_prefix(normalized_base)
      target_prefix = absolute_path_prefix(normalized_target)
      return nil unless base_prefix == target_prefix

      base_parts = normalized_base.split('/').reject(&.empty?)
      target_parts = normalized_target.split('/').reject(&.empty?)
      common_length = 0
      max_common = {base_parts.size, target_parts.size}.min

      while common_length < max_common && base_parts[common_length] == target_parts[common_length]
        common_length += 1
      end

      relative_parts = [] of String
      (base_parts.size - common_length).times { relative_parts << ".." }
      relative_parts.concat(target_parts[common_length..]) if common_length < target_parts.size
      relative_parts.empty? ? "." : relative_parts.join("/")
    end

    private def absolute_path_prefix(path : String) : String
      return "/" if path.starts_with?("/")
      return path[0, 3] if path.size >= 3 && path[1] == ':' && (path[2] == '/' || path[2] == '\\')

      ""
    end

    def hex_label(col : Int32, row : Int32) : String
      letter = ('A'.ord + col).chr
      "#{letter}#{(row + 1).to_s.rjust(2, '0')}"
    end

  end
end
