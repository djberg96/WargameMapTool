require "qt6"

module WargameMapToolCrystal
  abstract class MapLayer
    property name : String
    property kind : String
    property visible : Bool
    property accent : Qt6::Color
    property opacity : Int32

    def initialize(@name : String, @kind : String, @visible : Bool, @accent : Qt6::Color, @opacity : Int32 = 100)
    end

    abstract def paint(painter : Qt6::QPainter, state : MapState) : Nil
  end

  class BackgroundLayer < MapLayer
    @image : Qt6::QImage?

    getter image_path : String?
    property offset_x : Float64
    property offset_y : Float64
    property scale : Float64

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @image_path = nil
      @offset_x = 0.0
      @offset_y = 0.0
      @scale = 1.0
      @image = nil
    end

    def load_image(path : String) : Bool
      image = Qt6::QImage.from_file(path)
      return false if image.null?

      @image = image.convert_to_format(Qt6::ImageFormat::ARGB32)
      @image_path = path
      true
    end

    def clear_image : Nil
      @image = nil
      @image_path = nil
    end

    def has_image? : Bool
      image = @image
      !image.nil? && !image.null?
    end

    def image_size_text : String
      image = @image
      return "wash only" unless image && !image.null?

      "#{image.width}x#{image.height} px"
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      painter.save
      painter.opacity = opacity / 100.0

      bounds = state.screen_rect(state.world_bounds)
      painter.fill_rect(bounds, Qt6::Color.new(244, 238, 227))

      band_height = bounds.height / 4.0
      4.times do |index|
        tint = index.even? ? Qt6::Color.new(231, 224, 209) : Qt6::Color.new(239, 233, 221)
        painter.fill_rect(
          Qt6::RectF.new(bounds.x, bounds.y + band_height * index, bounds.width, band_height),
          tint
        )
      end

      image = @image
      if image && !image.null?
        painter.smooth_pixmap_transform = true
        target = state.screen_rect(Qt6::RectF.new(@offset_x, @offset_y, image.width * @scale, image.height * @scale))
        painter.draw_image(target, image)
      end

      painter.restore
    end
  end

  class TerrainLayer < MapLayer
    getter fills : Hash(Tuple(Int32, Int32), Qt6::Color)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @fills = {} of Tuple(Int32, Int32) => Qt6::Color
    end

    def set_fill(col : Int32, row : Int32, color : Qt6::Color) : Bool
      existing = @fills[{col, row}]?
      return false if existing && existing.red == color.red && existing.green == color.green && existing.blue == color.blue && existing.alpha == color.alpha

      @fills[{col, row}] = color
      true
    end

    def clear_fill(col : Int32, row : Int32) : Bool
      @fills.delete({col, row}) != nil
    end

    def clear_fills : Nil
      @fills.clear
    end

    def fill_at(col : Int32, row : Int32) : Qt6::Color?
      @fills[{col, row}]?
    end

    def fill_count : Int32
      @fills.size.to_i32
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      state.rows.times do |row|
        state.cols.times do |col|
          center = state.screen_point(state.hex_center(col, row))
          radius = (6.0 * state.zoom).clamp(3.2, 12.0)
          painter.pen = Qt6::QPen.new(state.terrain_color(col, row), 1.0)
          painter.brush = state.terrain_color(col, row)
          painter.draw_ellipse(Qt6::RectF.new(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0))
        end
      end

      layer_opacity = opacity / 100.0
      @fills.each do |coords, color|
        polygon = Qt6::QPolygonF.new(
          state.hex_points(coords[0], coords[1]).map { |point| state.screen_point(point) }
        )

        painter.save
        painter.pen = Qt6::QPen.new(color, 1.0)
        painter.brush = color
        painter.opacity = (layer_opacity * 0.82).clamp(0.0, 1.0)
        painter.draw_polygon(polygon)
        painter.restore
      end
    end
  end

  class BorderObject
    property col_a : Int32
    property row_a : Int32
    property col_b : Int32
    property row_b : Int32
    property color : Qt6::Color
    property width : Float64
    property line_type : String

    def initialize(
      col_a : Int32,
      row_a : Int32,
      col_b : Int32,
      row_b : Int32,
      @color : Qt6::Color = Qt6::Color.new(58, 54, 48),
      @width : Float64 = 3.0,
      @line_type : String = "solid",
    )
      if canonical_pair?(col_a, row_a, col_b, row_b)
        @col_a = col_a
        @row_a = row_a
        @col_b = col_b
        @row_b = row_b
      else
        @col_a = col_b
        @row_a = row_b
        @col_b = col_a
        @row_b = row_a
      end
    end

    def edge_key : Tuple(Int32, Int32, Int32, Int32)
      {@col_a, @row_a, @col_b, @row_b}
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "col_a", @col_a
        json.field "row_a", @row_a
        json.field "col_b", @col_b
        json.field "row_b", @row_b
        json.field "width", @width
        json.field "line_type", @line_type
        json.field "color" do
          json.object do
            json.field "red", @color.red
            json.field "green", @color.green
            json.field "blue", @color.blue
            json.field "alpha", @color.alpha
          end
        end
      end
    end

    def self.from_json(data : JSON::Any) : self
      color_data = data["color"]?
      color = Qt6::Color.new(
        (color_data.try { |value| value["red"]?.try(&.as_i?) } || 58).to_i32,
        (color_data.try { |value| value["green"]?.try(&.as_i?) } || 54).to_i32,
        (color_data.try { |value| value["blue"]?.try(&.as_i?) } || 48).to_i32,
        (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
      )

      new(
        (data["col_a"]?.try(&.as_i?) || 0).to_i32,
        (data["row_a"]?.try(&.as_i?) || 0).to_i32,
        (data["col_b"]?.try(&.as_i?) || 0).to_i32,
        (data["row_b"]?.try(&.as_i?) || 0).to_i32,
        color,
        data["width"]?.try(&.as_f?) || 3.0,
        data["line_type"]?.try(&.as_s?) || "solid",
      )
    end

    def screen_distance_to(state : MapState, point : Qt6::PointF) : Float64
      edge = state.shared_edge_points(@col_a, @row_a, @col_b, @row_b)
      return Float64::INFINITY unless edge

      start_point = state.screen_point(edge[0])
      end_point = state.screen_point(edge[1])
      dx = end_point.x - start_point.x
      dy = end_point.y - start_point.y
      length_squared = dx * dx + dy * dy
      return Float64::INFINITY if length_squared <= 0.001

      t = (((point.x - start_point.x) * dx) + ((point.y - start_point.y) * dy)) / length_squared
      t = t.clamp(0.0, 1.0)
      projection_x = start_point.x + dx * t
      projection_y = start_point.y + dy * t
      distance_x = point.x - projection_x
      distance_y = point.y - projection_y
      Math.sqrt(distance_x * distance_x + distance_y * distance_y)
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      edge = state.shared_edge_points(@col_a, @row_a, @col_b, @row_b)
      return unless edge

      start_point = state.screen_point(edge[0])
      end_point = state.screen_point(edge[1])
      selection_pen = Qt6::QPen.new(accent, @width + 4.0)
      selection_pen.style = Qt6::PenStyle::DashLine

      painter.save
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = 0.92
      painter.draw_line(start_point, end_point)
      painter.restore
    end

    private def canonical_pair?(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : Bool
      row_a < row_b || (row_a == row_b && col_a <= col_b)
    end
  end

  class BorderLayer < MapLayer
    getter objects : Array(BorderObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of BorderObject
    end

    def add_border(object : BorderObject) : Nil
      @objects.reject! { |existing| existing.edge_key == object.edge_key }
      @objects << object
    end

    def clear_borders : Nil
      @objects.clear
    end

    def border_count : Int32
      @objects.size.to_i32
    end

    def remove_border(object : BorderObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def border_at(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : BorderObject?
      probe = BorderObject.new(col_a, row_a, col_b, row_b)
      @objects.find { |object| object.edge_key == probe.edge_key }
    end

    def nearest_border(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = 10.0) : BorderObject?
      best = nil
      best_distance = max_distance

      @objects.each do |object|
        distance = object.screen_distance_to(state, screen_point)
        next unless distance <= best_distance

        best_distance = distance
        best = object
      end

      best
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      layer_opacity = opacity / 100.0

      @objects.each do |object|
        edge = state.shared_edge_points(object.col_a, object.row_a, object.col_b, object.row_b)
        next unless edge

        start_point = state.screen_point(edge[0])
        end_point = state.screen_point(edge[1])
        pen = Qt6::QPen.new(object.color, object.width)
        pen.style = case object.line_type
                    when "dashed"
                      Qt6::PenStyle::DashLine
                    when "dotted"
                      Qt6::PenStyle::DotLine
                    else
                      Qt6::PenStyle::SolidLine
                    end

        painter.save
        painter.pen = pen
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.opacity = layer_opacity
        painter.draw_line(start_point, end_point)
        painter.restore
      end

      if selected = state.selected_border_object
        return unless @objects.includes?(selected)

        selected.draw_selection(painter, state, accent)
      end
    end
  end

  class PathObject
    property col_a : Int32
    property row_a : Int32
    property col_b : Int32
    property row_b : Int32
    property color : Qt6::Color
    property width : Float64
    property line_type : String
    property opacity : Float64

    def initialize(
      @col_a : Int32,
      @row_a : Int32,
      @col_b : Int32,
      @row_b : Int32,
      @color : Qt6::Color = Qt6::Color.new(174, 82, 54),
      @width : Float64 = 3.0,
      @line_type : String = "solid",
      @opacity : Float64 = 1.0,
    )
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "col_a", @col_a
        json.field "row_a", @row_a
        json.field "col_b", @col_b
        json.field "row_b", @row_b
        json.field "width", @width
        json.field "line_type", @line_type
        json.field "opacity", @opacity
        json.field "color" do
          json.object do
            json.field "red", @color.red
            json.field "green", @color.green
            json.field "blue", @color.blue
            json.field "alpha", @color.alpha
          end
        end
      end
    end

    def self.from_json(data : JSON::Any) : self
      color_data = data["color"]?
      color = Qt6::Color.new(
        (color_data.try { |value| value["red"]?.try(&.as_i?) } || 174).to_i32,
        (color_data.try { |value| value["green"]?.try(&.as_i?) } || 82).to_i32,
        (color_data.try { |value| value["blue"]?.try(&.as_i?) } || 54).to_i32,
        (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
      )

      new(
        (data["col_a"]?.try(&.as_i?) || 0).to_i32,
        (data["row_a"]?.try(&.as_i?) || 0).to_i32,
        (data["col_b"]?.try(&.as_i?) || 0).to_i32,
        (data["row_b"]?.try(&.as_i?) || 0).to_i32,
        color,
        data["width"]?.try(&.as_f?) || 3.0,
        data["line_type"]?.try(&.as_s?) || "solid",
        data["opacity"]?.try(&.as_f?) || 1.0,
      )
    end

    def screen_distance_to(state : MapState, point : Qt6::PointF) : Float64
      start_point = state.screen_point(state.hex_center(@col_a, @row_a))
      end_point = state.screen_point(state.hex_center(@col_b, @row_b))
      dx = end_point.x - start_point.x
      dy = end_point.y - start_point.y
      length_squared = dx * dx + dy * dy

      return Math.sqrt((point.x - start_point.x) ** 2 + (point.y - start_point.y) ** 2) if length_squared <= 0.001

      t = (((point.x - start_point.x) * dx) + ((point.y - start_point.y) * dy)) / length_squared
      t = t.clamp(0.0, 1.0)
      projection_x = start_point.x + dx * t
      projection_y = start_point.y + dy * t
      distance_x = point.x - projection_x
      distance_y = point.y - projection_y
      Math.sqrt(distance_x * distance_x + distance_y * distance_y)
    end

    def endpoint_hit(state : MapState, point : Qt6::PointF, max_distance : Float64 = 12.0) : String?
      start_point = state.screen_point(state.hex_center(@col_a, @row_a))
      end_point = state.screen_point(state.hex_center(@col_b, @row_b))

      start_distance = Math.sqrt((point.x - start_point.x) ** 2 + (point.y - start_point.y) ** 2)
      end_distance = Math.sqrt((point.x - end_point.x) ** 2 + (point.y - end_point.y) ** 2)

      if start_distance <= max_distance && start_distance <= end_distance
        "start"
      elsif end_distance <= max_distance
        "end"
      end
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      start_point = state.screen_point(state.hex_center(@col_a, @row_a))
      end_point = state.screen_point(state.hex_center(@col_b, @row_b))
      selection_pen = Qt6::QPen.new(accent, @width + 4.0)
      selection_pen.style = Qt6::PenStyle::DashLine

      painter.save
      painter.pen = selection_pen
      painter.opacity = 0.9
      painter.draw_line(start_point, end_point)
      painter.pen = Qt6::QPen.new(accent, 2.0)
      painter.brush = Qt6::Color.new(250, 248, 242)
      painter.draw_ellipse(Qt6::RectF.new(start_point.x - 6.0, start_point.y - 6.0, 12.0, 12.0))
      painter.draw_ellipse(Qt6::RectF.new(end_point.x - 6.0, end_point.y - 6.0, 12.0, 12.0))
      painter.restore
    end
  end

  class PathLayer < MapLayer
    getter objects : Array(PathObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of PathObject
    end

    def add_path(object : PathObject) : Nil
      @objects << object
    end

    def clear_paths : Nil
      @objects.clear
    end

    def path_count : Int32
      @objects.size.to_i32
    end

    def remove_path(object : PathObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def nearest_path(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = 10.0) : PathObject?
      best = nil
      best_distance = max_distance

      @objects.each do |object|
        distance = object.screen_distance_to(state, screen_point)
        next unless distance <= best_distance

        best_distance = distance
        best = object
      end

      best
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      layer_opacity = opacity / 100.0

      @objects.each do |object|
        start_point = state.screen_point(state.hex_center(object.col_a, object.row_a))
        end_point = state.screen_point(state.hex_center(object.col_b, object.row_b))
        pen = Qt6::QPen.new(object.color, object.width)
        pen.style = case object.line_type
                    when "dashed"
                      Qt6::PenStyle::DashLine
                    when "dotted"
                      Qt6::PenStyle::DotLine
                    else
                      Qt6::PenStyle::SolidLine
                    end

        painter.save
        painter.pen = pen
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.opacity = (layer_opacity * object.opacity).clamp(0.0, 1.0)
        painter.draw_line(start_point, end_point)
        painter.restore
      end

      if selected = state.selected_path_object
        return unless @objects.includes?(selected)

        selected.draw_selection(painter, state, accent)
      end
    end
  end

  class TextObject
    property text : String
    property x : Float64
    property y : Float64
    property font_family : String
    property font_size : Int32
    property bold : Bool
    property italic : Bool
    property color : Qt6::Color
    property alignment : String
    property opacity : Float64
    property rotation : Float64

    def initialize(
      @text : String,
      @x : Float64,
      @y : Float64,
      @font_family : String = "Avenir Next",
      @font_size : Int32 = 12,
      @bold : Bool = false,
      @italic : Bool = false,
      @color : Qt6::Color = Qt6::Color.new(54, 60, 92),
      @alignment : String = "left",
      @opacity : Float64 = 1.0,
      @rotation : Float64 = 0.0,
    )
    end

    def paint(painter : Qt6::QPainter, state : MapState, layer_opacity : Float64 = 1.0) : Nil
      return if @text.empty?

      font = make_font
      screen = state.screen_point(Qt6::PointF.new(@x, @y))

      painter.save
      painter.font = font
      painter.pen = @color
      painter.opacity = (layer_opacity * @opacity).clamp(0.0, 1.0)
      painter.translate(screen.x, screen.y)
      painter.rotate(@rotation) if @rotation != 0.0
      painter.draw_text(Qt6::PointF.new(text_x_offset, 0.0), @text)
      painter.restore
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      return if @text.empty?

      screen = state.screen_point(Qt6::PointF.new(@x, @y))
      selection_pen = Qt6::QPen.new(accent, 2.0)
      selection_pen.style = Qt6::PenStyle::DashLine

      painter.save
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.translate(screen.x, screen.y)
      painter.rotate(@rotation) if @rotation != 0.0
      painter.draw_rect(selection_rect)
      painter.restore
    end

    private def make_font : Qt6::QFont
      Qt6::QFont.new(@font_family, @font_size, @bold, @italic)
    end

    private def text_x_offset : Float64
      metrics = make_font.metrics_f
      case @alignment
      when "center"
        -metrics.horizontal_advance(@text) / 2.0
      when "right"
        -metrics.horizontal_advance(@text)
      else
        0.0
      end
    end

    private def selection_rect : Qt6::RectF
      metrics = make_font.metrics_f
      padding = 4.0
      x = text_x_offset - padding
      y = -metrics.ascent - padding
      width = metrics.horizontal_advance(@text) + padding * 2.0
      height = metrics.height + padding * 2.0
      Qt6::RectF.new(x, y, width, height)
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "text", @text
        json.field "x", @x
        json.field "y", @y
        json.field "font_family", @font_family
        json.field "font_size", @font_size
        json.field "bold", @bold
        json.field "italic", @italic
        json.field "alignment", @alignment
        json.field "opacity", @opacity
        json.field "rotation", @rotation
        json.field "color" do
          json.object do
            json.field "red", @color.red
            json.field "green", @color.green
            json.field "blue", @color.blue
            json.field "alpha", @color.alpha
          end
        end
      end
    end

    def self.from_json(data : JSON::Any) : self
      color_data = data["color"]?
      color = Qt6::Color.new(
        (color_data.try { |value| value["red"]?.try(&.as_i?) } || 54).to_i32,
        (color_data.try { |value| value["green"]?.try(&.as_i?) } || 60).to_i32,
        (color_data.try { |value| value["blue"]?.try(&.as_i?) } || 92).to_i32,
        (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
      )

      new(
        data["text"]?.try(&.as_s?) || "Text",
        data["x"]?.try(&.as_f?) || 0.0,
        data["y"]?.try(&.as_f?) || 0.0,
        data["font_family"]?.try(&.as_s?) || "Avenir Next",
        (data["font_size"]?.try(&.as_i?) || 12).to_i32,
        data["bold"]?.try(&.as_bool?) || false,
        data["italic"]?.try(&.as_bool?) || false,
        color,
        data["alignment"]?.try(&.as_s?) || "left",
        data["opacity"]?.try(&.as_f?) || 1.0,
        data["rotation"]?.try(&.as_f?) || 0.0,
      )
    end
  end

  class TextLayer < MapLayer
    getter objects : Array(TextObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of TextObject
    end

    def add_text(object : TextObject) : Nil
      @objects << object
    end

    def remove_text(object : TextObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def clear_texts : Nil
      @objects.clear
    end

    def text_count : Int32
      @objects.size.to_i32
    end

    def nearest_text(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = 28.0) : TextObject?
      best = nil
      best_distance = max_distance

      @objects.each do |object|
        anchor = state.screen_point(Qt6::PointF.new(object.x, object.y))
        dx = anchor.x - screen_point.x
        dy = anchor.y - screen_point.y
        distance = Math.sqrt(dx * dx + dy * dy)
        next unless distance <= best_distance

        best_distance = distance
        best = object
      end

      best
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      layer_opacity = opacity / 100.0
      @objects.each do |object|
        object.paint(painter, state, layer_opacity)
      end

      if selected = state.selected_text_object
        return unless @objects.includes?(selected)

        selected.draw_selection(painter, state, accent)
      end
    end
  end

  class AssetObject
    @image : Qt6::QImage?

    getter image_path : String?
    property x : Float64
    property y : Float64
    property scale : Float64
    property rotation : Float64
    property opacity : Float64
    property snap_to_hex : Bool

    def initialize(
      @x : Float64,
      @y : Float64,
      image_path : String? = nil,
      @scale : Float64 = 1.0,
      @rotation : Float64 = 0.0,
      @opacity : Float64 = 1.0,
      @snap_to_hex : Bool = true,
    )
      @image = nil
      @image_path = nil
      set_image_path(image_path)
    end

    def set_image_path(path : String?) : Bool
      if path.nil? || path.not_nil!.empty?
        @image = nil
        @image_path = nil
        return false
      end

      image = Qt6::QImage.from_file(path.not_nil!)
      return false if image.null?

      @image = image.convert_to_format(Qt6::ImageFormat::ARGB32)
      @image_path = path
      true
    end

    def has_image? : Bool
      image = @image
      !image.nil? && !image.null?
    end

    def label : String
      if path = @image_path
        File.basename(path).sub(/\.[^.]+$/, "")
      else
        "Asset"
      end
    end

    def world_width : Float64
      image = @image
      if image && !image.null?
        image.width * @scale
      else
        28.0 * @scale.clamp(0.5, 2.4)
      end
    end

    def world_height : Float64
      image = @image
      if image && !image.null?
        image.height * @scale
      else
        24.0 * @scale.clamp(0.5, 2.4)
      end
    end

    def world_rect : Qt6::RectF
      width = world_width
      height = world_height
      Qt6::RectF.new(@x - width / 2.0, @y - height / 2.0, width, height)
    end

    def contains_world_point(point : Qt6::PointF) : Bool
      rect = world_rect
      point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height
    end

    def paint(painter : Qt6::QPainter, state : MapState, layer_opacity : Float64 = 1.0, accent : Qt6::Color = Qt6::Color.new(94, 100, 112)) : Nil
      screen = state.screen_point(Qt6::PointF.new(@x, @y))
      alpha = (layer_opacity * @opacity).clamp(0.0, 1.0)
      image = @image

      painter.save
      painter.opacity = alpha
      painter.translate(screen.x, screen.y)
      painter.rotate(@rotation) if @rotation != 0.0

      if image && !image.null?
        painter.smooth_pixmap_transform = true
        width = image.width * @scale * state.zoom
        height = image.height * @scale * state.zoom
        painter.draw_image(Qt6::RectF.new(-width / 2.0, -height / 2.0, width, height), image)
      else
        width = 28.0 * @scale.clamp(0.5, 2.4) * state.zoom
        height = 24.0 * @scale.clamp(0.5, 2.4) * state.zoom
        rect = Qt6::RectF.new(-width / 2.0, -height / 2.0, width, height)
        painter.pen = Qt6::QPen.new(Qt6::Color.new(76, 80, 90), 2.0)
        painter.brush = accent
        painter.draw_rect(rect)
        painter.pen = Qt6::Color.new(248, 245, 239)
        painter.font = Qt6::QFont.new(point_size: (9.0 * state.zoom.clamp(0.8, 1.5)).round.to_i, bold: true)
        painter.draw_text(Qt6::PointF.new(rect.x + 4.0, rect.y + height / 2.0 + 4.0), label[0, 3].upcase)
      end

      painter.restore
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      screen = state.screen_point(Qt6::PointF.new(@x, @y))
      width = world_width * state.zoom
      height = world_height * state.zoom
      selection_pen = Qt6::QPen.new(accent, 2.0)
      selection_pen.style = Qt6::PenStyle::DashLine

      painter.save
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.translate(screen.x, screen.y)
      painter.rotate(@rotation) if @rotation != 0.0
      painter.draw_rect(Qt6::RectF.new(-width / 2.0, -height / 2.0, width, height))
      painter.restore
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "image_path", @image_path if @image_path
        json.field "x", @x
        json.field "y", @y
        json.field "scale", @scale
        json.field "rotation", @rotation
        json.field "opacity", @opacity
        json.field "snap_to_hex", @snap_to_hex
      end
    end

    def self.from_json(data : JSON::Any) : self
      new(
        data["x"]?.try(&.as_f?) || 0.0,
        data["y"]?.try(&.as_f?) || 0.0,
        data["image_path"]?.try(&.as_s?),
        data["scale"]?.try(&.as_f?) || 1.0,
        data["rotation"]?.try(&.as_f?) || 0.0,
        data["opacity"]?.try(&.as_f?) || 1.0,
        data["snap_to_hex"]?.try(&.as_bool?) || true,
      )
    end
  end

  class AssetLayer < MapLayer
    getter objects : Array(AssetObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of AssetObject
    end

    def add_asset(object : AssetObject) : Nil
      @objects << object
    end

    def clear_assets : Nil
      @objects.clear
    end

    def asset_count : Int32
      @objects.size.to_i32
    end

    def remove_asset(object : AssetObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def nearest_asset(state : MapState, screen_point : Qt6::PointF) : AssetObject?
      world = state.screen_to_world(screen_point)

      @objects.reverse_each do |object|
        return object if object.contains_world_point(world)
      end

      nil
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      return unless state.show_assets

      layer_opacity = opacity / 100.0
      @objects.each do |object|
        object.paint(painter, state, layer_opacity, accent)
      end

      if selected = state.selected_asset_object
        return unless @objects.includes?(selected)

        selected.draw_selection(painter, state, accent)
      end
    end
  end
end