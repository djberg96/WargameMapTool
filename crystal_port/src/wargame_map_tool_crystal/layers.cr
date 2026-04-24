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

  class AssetLayer < MapLayer
    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      return unless state.show_assets

      painter.pen = Qt6::QPen.new(Qt6::Color.new(76, 80, 90), 2.0)

      state.asset_hexes.each_with_index do |hex, index|
        center = state.screen_point(state.hex_center(hex[0], hex[1]))
        rect = Qt6::RectF.new(center.x - 14.0, center.y - 12.0, 28.0, 24.0)
        fill = index.even? ? Qt6::Color.new(224, 214, 190) : Qt6::Color.new(198, 210, 216)
        painter.fill_rect(rect, fill)
        painter.draw_rect(rect)
        painter.draw_text(Qt6::PointF.new(rect.x + 5.0, rect.y + 16.0), "#{index + 1}")
      end
    end
  end
end