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

  class HexsideObject
    property col_a : Int32
    property row_a : Int32
    property col_b : Int32
    property row_b : Int32
    property color : Qt6::Color
    property width : Float64
    property opacity : Float64

    def initialize(
      col_a : Int32,
      row_a : Int32,
      col_b : Int32,
      row_b : Int32,
      @color : Qt6::Color = Qt6::Color.new(70, 108, 154),
      @width : Float64 = 4.0,
      @opacity : Float64 = 1.0,
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
        (color_data.try { |value| value["red"]?.try(&.as_i?) } || 70).to_i32,
        (color_data.try { |value| value["green"]?.try(&.as_i?) } || 108).to_i32,
        (color_data.try { |value| value["blue"]?.try(&.as_i?) } || 154).to_i32,
        (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
      )

      new(
        (data["col_a"]?.try(&.as_i?) || 0).to_i32,
        (data["row_a"]?.try(&.as_i?) || 0).to_i32,
        (data["col_b"]?.try(&.as_i?) || 0).to_i32,
        (data["row_b"]?.try(&.as_i?) || 0).to_i32,
        color,
        data["width"]?.try(&.as_f?) || 4.0,
        data["opacity"]?.try(&.as_f?) || 1.0,
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

      painter.save
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = 0.28
      painter.draw_line(start_point, end_point)
      painter.restore
    end

    private def canonical_pair?(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : Bool
      row_a < row_b || (row_a == row_b && col_a <= col_b)
    end
  end

  class HexsideLayer < MapLayer
    getter objects : Array(HexsideObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of HexsideObject
    end

    def add_hexside(object : HexsideObject) : Nil
      @objects.reject! { |existing| existing.edge_key == object.edge_key }
      @objects << object
    end

    def clear_hexsides : Nil
      @objects.clear
    end

    def hexside_count : Int32
      @objects.size.to_i32
    end

    def remove_hexside(object : HexsideObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def hexside_at(col_a : Int32, row_a : Int32, col_b : Int32, row_b : Int32) : HexsideObject?
      probe = HexsideObject.new(col_a, row_a, col_b, row_b)
      @objects.find { |object| object.edge_key == probe.edge_key }
    end

    def nearest_hexside(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = 10.0) : HexsideObject?
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
        pen.cap_style = Qt6::PenCapStyle::RoundCap

        painter.save
        painter.pen = pen
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.opacity = (layer_opacity * object.opacity).clamp(0.0, 1.0)
        painter.draw_line(start_point, end_point)
        painter.restore
      end

      if selected = state.selected_hexside_object
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

  class FreeformPathObject
    HANDLE_HIT_DISTANCE = 12.0

    property points : Array(Tuple(Float64, Float64))
    property color : Qt6::Color
    property width : Float64
    property opacity : Float64

    def initialize(
      points : Array(Tuple(Float64, Float64)),
      @color : Qt6::Color = Qt6::Color.new(82, 122, 164),
      @width : Float64 = 3.0,
      @opacity : Float64 = 1.0,
    )
      @points = points.map { |point| {point[0].to_f64, point[1].to_f64} }
    end

    def point_count : Int32
      @points.size.to_i32
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "width", @width
        json.field "opacity", @opacity
        json.field "points" do
          json.array do
            @points.each do |point|
              json.object do
                json.field "x", point[0]
                json.field "y", point[1]
              end
            end
          end
        end
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
        (color_data.try { |value| value["red"]?.try(&.as_i?) } || 82).to_i32,
        (color_data.try { |value| value["green"]?.try(&.as_i?) } || 122).to_i32,
        (color_data.try { |value| value["blue"]?.try(&.as_i?) } || 164).to_i32,
        (color_data.try { |value| value["alpha"]?.try(&.as_i?) } || 255).to_i32,
      )

      points = [] of Tuple(Float64, Float64)
      data["points"]?.try(&.as_a?).try do |items|
        items.each do |item|
          x = if value = item["x"]?
                value.as_f? || (value.as_i? || 0).to_f64
              else
                0.0
              end
          y = if value = item["y"]?
                value.as_f? || (value.as_i? || 0).to_f64
              else
                0.0
              end
          points << {x.to_f64, y.to_f64}
        end
      end

      new(
        points,
        color,
        data["width"]?.try(&.as_f?) || 3.0,
        data["opacity"]?.try(&.as_f?) || 1.0,
      )
    end

    def screen_distance_to(state : MapState, point : Qt6::PointF) : Float64
      return Float64::INFINITY if @points.size < 2

      best_distance = Float64::INFINITY
      (@points.size - 1).times do |index|
        start_point = state.screen_point(Qt6::PointF.new(@points[index][0], @points[index][1]))
        end_point = state.screen_point(Qt6::PointF.new(@points[index + 1][0], @points[index + 1][1]))
        distance = distance_to_segment(point, start_point, end_point)
        best_distance = distance if distance < best_distance
      end

      best_distance
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      screen_points = build_screen_points(state)
      return if screen_points.size < 2

      selection_pen = Qt6::QPen.new(accent, @width + 4.0)
      selection_pen.style = Qt6::PenStyle::DashLine
      selection_pen.cap_style = Qt6::PenCapStyle::RoundCap

      painter.save
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = 0.9
      draw_screen_segments(painter, screen_points)
      painter.pen = Qt6::QPen.new(accent, 2.0)
      painter.brush = Qt6::Color.new(250, 248, 242)
      screen_points.each do |screen_point|
        painter.draw_ellipse(Qt6::RectF.new(screen_point.x - 5.0, screen_point.y - 5.0, 10.0, 10.0))
      end
      painter.restore
    end

    def point_hit_index(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = HANDLE_HIT_DISTANCE) : Int32?
      best_index = nil
      best_distance = max_distance

      build_screen_points(state).each_with_index do |path_point, index|
        dx = screen_point.x - path_point.x
        dy = screen_point.y - path_point.y
        distance = Math.sqrt(dx * dx + dy * dy)
        next unless distance <= best_distance

        best_distance = distance
        best_index = index.to_i32
      end

      best_index
    end

    def translate(delta_x : Float64, delta_y : Float64) : Nil
      @points.map! do |point|
        {point[0] + delta_x, point[1] + delta_y}
      end
    end

    private def build_screen_points(state : MapState) : Array(Qt6::PointF)
      @points.map { |point| state.screen_point(Qt6::PointF.new(point[0], point[1])) }
    end

    private def draw_screen_segments(painter : Qt6::QPainter, screen_points : Array(Qt6::PointF)) : Nil
      (screen_points.size - 1).times do |index|
        painter.draw_line(screen_points[index], screen_points[index + 1])
      end
    end

    private def distance_to_segment(point : Qt6::PointF, start_point : Qt6::PointF, end_point : Qt6::PointF) : Float64
      dx = end_point.x - start_point.x
      dy = end_point.y - start_point.y
      length_squared = dx * dx + dy * dy
      return Float64::INFINITY if length_squared <= 0.001

      t = (((point.x - start_point.x) * dx) + ((point.y - start_point.y) * dy)) / length_squared
      t = t.clamp(0.0, 1.0)
      projection_x = start_point.x + dx * t
      projection_y = start_point.y + dy * t
      delta_x = point.x - projection_x
      delta_y = point.y - projection_y
      Math.sqrt(delta_x * delta_x + delta_y * delta_y)
    end
  end

  class FreeformPathLayer < MapLayer
    getter objects : Array(FreeformPathObject)

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of FreeformPathObject
    end

    def add_path(object : FreeformPathObject) : Nil
      @objects << object
    end

    def clear_paths : Nil
      @objects.clear
    end

    def path_count : Int32
      @objects.size.to_i32
    end

    def remove_path(object : FreeformPathObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def nearest_path(state : MapState, screen_point : Qt6::PointF, max_distance : Float64 = 10.0) : FreeformPathObject?
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
        next if object.points.size < 2

        pen = Qt6::QPen.new(object.color, object.width)
        pen.cap_style = Qt6::PenCapStyle::RoundCap
        pen.join_style = Qt6::PenJoinStyle::RoundJoin

        painter.save
        painter.pen = pen
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.opacity = (layer_opacity * object.opacity).clamp(0.0, 1.0)
        (object.points.size - 1).times do |index|
          start_point = state.screen_point(Qt6::PointF.new(object.points[index][0], object.points[index][1]))
          end_point = state.screen_point(Qt6::PointF.new(object.points[index + 1][0], object.points[index + 1][1]))
          painter.draw_line(start_point, end_point)
        end
        painter.restore
      end

      if selected = state.selected_freeform_path_object
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

  class SketchObject
    property id : String
    property shape_type : String
    property points : Array(Tuple(Float64, Float64))
    property radius : Float64
    property num_sides : Int32
    property rx : Float64
    property ry : Float64
    property closed : Bool
    property stroke_color : Qt6::Color
    property stroke_width : Float64
    property stroke_type : String
    property dash_length : Float64
    property gap_length : Float64
    property stroke_cap : String
    property fill_enabled : Bool
    property fill_color : Qt6::Color
    property fill_opacity : Float64
    property fill_type : String
    property fill_texture_id : String
    property fill_texture_zoom : Float64
    property fill_texture_rotation : Float64
    property rotation : Float64
    property shadow_enabled : Bool
    property shadow_type : String
    property shadow_color : Qt6::Color
    property shadow_opacity : Float64
    property shadow_angle : Float64
    property shadow_distance : Float64
    property shadow_spread : Float64
    property shadow_size : Float64
    property draw_over_grid : Bool

    def initialize(
      @id : String = "",
      @shape_type : String = "rect",
      points : Array(Tuple(Float64, Float64)) = [] of Tuple(Float64, Float64),
      @radius : Float64 = 30.0,
      @num_sides : Int32 = 6,
      @rx : Float64 = 40.0,
      @ry : Float64 = 30.0,
      @closed : Bool = false,
      @stroke_color : Qt6::Color = Qt6::Color.new(0, 0, 0),
      @stroke_width : Float64 = 2.0,
      @stroke_type : String = "solid",
      @dash_length : Float64 = 8.0,
      @gap_length : Float64 = 4.0,
      @stroke_cap : String = "round",
      @fill_enabled : Bool = false,
      @fill_color : Qt6::Color = Qt6::Color.new(255, 255, 0),
      @fill_opacity : Float64 = 0.3,
      @fill_type : String = "color",
      @fill_texture_id : String = "",
      @fill_texture_zoom : Float64 = 1.0,
      @fill_texture_rotation : Float64 = 0.0,
      @rotation : Float64 = 0.0,
      @shadow_enabled : Bool = false,
      @shadow_type : String = "outer",
      @shadow_color : Qt6::Color = Qt6::Color.new(0, 0, 0),
      @shadow_opacity : Float64 = 0.5,
      @shadow_angle : Float64 = 120.0,
      @shadow_distance : Float64 = 5.0,
      @shadow_spread : Float64 = 0.0,
      @shadow_size : Float64 = 5.0,
      @draw_over_grid : Bool = false,
    )
      @points = points.map { |point| {point[0].to_f64, point[1].to_f64} }
    end

    def center : Tuple(Float64, Float64)
      if @shape_type == "polygon" || @shape_type == "ellipse"
        return @points.first? || {0.0, 0.0}
      end
      return {0.0, 0.0} if @points.empty?

      x_sum = 0.0
      y_sum = 0.0
      @points.each do |point|
        x_sum += point[0]
        y_sum += point[1]
      end
      {x_sum / @points.size, y_sum / @points.size}
    end

    def build_path : Qt6::QPainterPath
      path = Qt6::QPainterPath.new

      case @shape_type
      when "line"
        return path if @points.size < 2
        path.move_to(pointf(@points[0]))
        path.line_to(pointf(@points[1]))
      when "rect"
        return path if @points.size < 2
        x1 = @points[0][0]
        y1 = @points[0][1]
        x2 = @points[1][0]
        y2 = @points[1][1]
        path.add_rect(Qt6::RectF.new(
          {x1, x2}.min,
          {y1, y2}.min,
          (x2 - x1).abs,
          (y2 - y1).abs,
        ))
      when "polygon"
        return path if @points.empty?
        center = @points[0]
        polygon = Qt6::QPolygonF.new(build_polygon_points(center[0], center[1]))
        path.add_polygon(polygon)
        path.close_subpath
      when "ellipse"
        return path if @points.empty?
        center = @points[0]
        path.add_ellipse(Qt6::RectF.new(
          center[0] - @rx,
          center[1] - @ry,
          @rx * 2.0,
          @ry * 2.0,
        ))
      when "freehand"
        return path if @points.size < 2
        if @points.size == 2
          path.move_to(pointf(@points[0]))
          path.line_to(pointf(@points[1]))
        else
          path.move_to(pointf(@points[0]))
          smooth_points = [@points.first] + @points + [@points.last]
          (1...(smooth_points.size - 2)).each do |index|
            p0 = smooth_points[index - 1]
            p1 = smooth_points[index]
            p2 = smooth_points[index + 1]
            p3 = smooth_points[index + 2]
            control_1 = Qt6::PointF.new(
              p1[0] + (p2[0] - p0[0]) / 6.0,
              p1[1] + (p2[1] - p0[1]) / 6.0,
            )
            control_2 = Qt6::PointF.new(
              p2[0] - (p3[0] - p1[0]) / 6.0,
              p2[1] - (p3[1] - p1[1]) / 6.0,
            )
            path.cubic_to(control_1, control_2, pointf(p2))
          end
        end
        path.close_subpath if @closed && @points.size >= 3
      else
        return path
      end

      path
    end

    def transformed_path : Qt6::QPainterPath
      path = build_path
      return path if path.empty? || @rotation == 0.0

      transform = Qt6::QTransform.new
      center_x, center_y = center
      transform.translate(center_x, center_y)
      transform.rotate(@rotation)
      transform.translate(-center_x, -center_y)
      transform.map(path)
    end

    def bounding_rect : Qt6::RectF
      path = transformed_path
      return Qt6::RectF.new(0.0, 0.0, 0.0, 0.0) if path.empty?

      rect = path.bounding_rect
      margin = @stroke_width / 2.0 + 2.0
      Qt6::RectF.new(
        rect.x - margin,
        rect.y - margin,
        rect.width + margin * 2.0,
        rect.height + margin * 2.0,
      )
    end

    def contains_point(point : Qt6::PointF, threshold : Float64 = 8.0) : Bool
      path = transformed_path
      return false if path.empty?

      if @shape_type != "line" && path.contains(point)
        return true
      end

      stroker = Qt6::QPainterPathStroker.new
      stroker.width = Math.max(@stroke_width, threshold * 2.0)
      stroker.create_stroke(path).contains(point)
    end

    def translate(delta_x : Float64, delta_y : Float64) : Nil
      @points.map! do |point|
        {point[0] + delta_x, point[1] + delta_y}
      end
    end

    def selection_corners : Array(Tuple(Float64, Float64))
      path = build_path
      rect = path.bounding_rect
      center_x, center_y = center
      return [{center_x, center_y}] * 4 if rect.width <= 0.0 || rect.height <= 0.0

      margin = @stroke_width / 2.0
      corners = [
        {rect.x - margin, rect.y - margin},
        {rect.x + rect.width + margin, rect.y - margin},
        {rect.x + rect.width + margin, rect.y + rect.height + margin},
        {rect.x - margin, rect.y + rect.height + margin},
      ]

      return corners if @rotation == 0.0

      corners.map { |point| rotate_point(point, {center_x, center_y}, @rotation) }
    end

    def rotation_handle(offset : Float64) : Tuple(Float64, Float64)
      corners = selection_corners
      top_mid = {
        (corners[0][0] + corners[1][0]) / 2.0,
        (corners[0][1] + corners[1][1]) / 2.0,
      }
      center_x, center_y = center
      dx = top_mid[0] - center_x
      dy = top_mid[1] - center_y
      distance = Math.sqrt(dx * dx + dy * dy)
      if distance < 1.0
        dx = 0.0
        dy = -1.0
        distance = 1.0
      end

      {top_mid[0] + (dx / distance) * offset, top_mid[1] + (dy / distance) * offset}
    end

    def rotation_angle_for(point : Tuple(Float64, Float64)) : Float64
      center_x, center_y = center
      Math.atan2(point[0] - center_x, -(point[1] - center_y)) * 180.0 / Math::PI
    end

    def resize_from_anchor(
      anchor : Tuple(Float64, Float64),
      target : Tuple(Float64, Float64),
      source_points : Array(Tuple(Float64, Float64)) = @points,
      source_radius : Float64 = @radius,
      source_rx : Float64 = @rx,
      source_ry : Float64 = @ry
    ) : Nil
      center_x, center_y = source_geometry_center(source_points)
      local_target = rotate_point(target, {center_x, center_y}, -@rotation)
      local_anchor = rotate_point(anchor, {center_x, center_y}, -@rotation)

      case @shape_type
      when "line", "rect"
        return if source_points.size < 2

        x_values = source_points.map(&.[0])
        y_values = source_points.map(&.[1])
        old_width = x_values.max - x_values.min
        old_height = y_values.max - y_values.min
        old_center_x = (x_values.min + x_values.max) / 2.0
        old_center_y = (y_values.min + y_values.max) / 2.0
        new_center_x = (local_target[0] + local_anchor[0]) / 2.0
        new_center_y = (local_target[1] + local_anchor[1]) / 2.0

        if old_width > 0.0 && old_height > 0.0
          scale_x = (local_target[0] - local_anchor[0]).abs / old_width
          scale_y = (local_target[1] - local_anchor[1]).abs / old_height
          @points = source_points.map do |point|
            {
              new_center_x + (point[0] - old_center_x) * scale_x,
              new_center_y + (point[1] - old_center_y) * scale_y,
            }
          end
        else
          @points = [local_anchor, local_target]
        end
      when "polygon"
        new_center_x = (local_target[0] + local_anchor[0]) / 2.0
        new_center_y = (local_target[1] + local_anchor[1]) / 2.0
        new_radius = Math.sqrt((local_target[0] - new_center_x) ** 2 + (local_target[1] - new_center_y) ** 2)
        @points = [{new_center_x, new_center_y}]
        @radius = {new_radius, 5.0}.max
      when "ellipse"
        new_center_x = (local_target[0] + local_anchor[0]) / 2.0
        new_center_y = (local_target[1] + local_anchor[1]) / 2.0
        @points = [{new_center_x, new_center_y}]
        @rx = {(local_target[0] - local_anchor[0]).abs / 2.0, 5.0}.max
        @ry = {(local_target[1] - local_anchor[1]).abs / 2.0, 5.0}.max
      when "freehand"
        return if source_points.size < 2

        x_values = source_points.map(&.[0])
        y_values = source_points.map(&.[1])
        old_center_x = x_values.sum / source_points.size
        old_center_y = y_values.sum / source_points.size
        old_width = {x_values.max - x_values.min, 1.0}.max
        old_height = {y_values.max - y_values.min, 1.0}.max
        new_width = {(local_target[0] - local_anchor[0]).abs, 1.0}.max
        new_height = {(local_target[1] - local_anchor[1]).abs, 1.0}.max
        new_center_x = (local_target[0] + local_anchor[0]) / 2.0
        new_center_y = (local_target[1] + local_anchor[1]) / 2.0
        scale_x = new_width / old_width
        scale_y = new_height / old_height

        @points = source_points.map do |point|
          {
            new_center_x + (point[0] - old_center_x) * scale_x,
            new_center_y + (point[1] - old_center_y) * scale_y,
          }
        end
      else
      end

      @radius = source_radius if @shape_type != "polygon"
      @rx = source_rx if @shape_type != "ellipse"
      @ry = source_ry if @shape_type != "ellipse"
    end

    def paint(painter : Qt6::QPainter, state : MapState, layer_opacity : Float64 = 1.0) : Nil
      path = build_screen_path(state)
      return if path.empty?

      painter.save
      if @fill_enabled && @shape_type != "line"
        fill = Qt6::Color.new(
          @fill_color.red,
          @fill_color.green,
          @fill_color.blue,
          ((255.0 * @fill_opacity * layer_opacity).round.to_i).clamp(0, 255)
        )
        painter.pen = Qt6::QPen.new(Qt6::Color.new(0, 0, 0, 0), 0.0)
        painter.brush = fill
        painter.draw_path(path)
      end

      if @stroke_width > 0.0
        painter.pen = build_pen(state)
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.opacity = layer_opacity.clamp(0.0, 1.0)
        painter.draw_path(path)
      end
      painter.restore
    end

    def screen_path(state : MapState) : Qt6::QPainterPath
      build_screen_path(state)
    end

    def draw_selection(painter : Qt6::QPainter, state : MapState, accent : Qt6::Color) : Nil
      path = build_screen_path(state)
      return if path.empty?

      painter.save
      selection_pen = Qt6::QPen.new(accent, [@stroke_width * state.zoom + 4.0, 2.0].max)
      selection_pen.style = Qt6::PenStyle::DashLine
      painter.pen = selection_pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = 0.9
      painter.draw_path(path)
      painter.restore
    end

    def write_json(json : JSON::Builder) : Nil
      json.object do
        json.field "id", @id unless @id.empty?
        json.field "shape_type", @shape_type
        json.field "points" do
          json.array do
            @points.each do |point|
              json.array do
                json.number point[0]
                json.number point[1]
              end
            end
          end
        end
        json.field "radius", @radius if @shape_type == "polygon"
        json.field "num_sides", @num_sides if @shape_type == "polygon"
        json.field "rx", @rx if @shape_type == "ellipse"
        json.field "ry", @ry if @shape_type == "ellipse"
        json.field "closed", @closed if @shape_type == "freehand" && @closed
        json.field "stroke_color", color_hex(@stroke_color)
        json.field "stroke_width", @stroke_width
        if @stroke_type != "solid"
          json.field "stroke_type", @stroke_type
          json.field "dash_length", @dash_length
          json.field "gap_length", @gap_length
        end
        json.field "stroke_cap", @stroke_cap if @stroke_cap != "round"
        if @fill_enabled
          json.field "fill_enabled", true
          json.field "fill_color", color_hex(@fill_color)
          json.field "fill_opacity", @fill_opacity
          json.field "fill_type", @fill_type if @fill_type != "color"
          if @fill_type == "texture" && !@fill_texture_id.empty?
            json.field "fill_texture_id", @fill_texture_id
            json.field "fill_texture_zoom", @fill_texture_zoom
            json.field "fill_texture_rotation", @fill_texture_rotation
          end
        end
        json.field "rotation", @rotation if @rotation != 0.0
        json.field "draw_over_grid", true if @draw_over_grid
      end
    end

    def self.from_json(data : JSON::Any) : self
      points = [] of Tuple(Float64, Float64)
      data["points"]?.try(&.as_a?).try do |items|
        items.each do |item|
          next unless values = item.as_a?
          next unless values.size >= 2
          x = values[0].as_f? || values[0].as_i?.try(&.to_f64) || 0.0
          y = values[1].as_f? || values[1].as_i?.try(&.to_f64) || 0.0
          points << {x, y}
        end
      end

      new(
        data["id"]?.try(&.as_s?) || "",
        data["shape_type"]?.try(&.as_s?) || "rect",
        points,
        json_number(data["radius"]?) || 30.0,
        (data["num_sides"]?.try(&.as_i?) || 6).to_i32,
        json_number(data["rx"]?) || 40.0,
        json_number(data["ry"]?) || 30.0,
        data["closed"]?.try(&.as_bool?) || false,
        color_from_any(data["stroke_color"]?, Qt6::Color.new(0, 0, 0)),
        json_number(data["stroke_width"]?) || 2.0,
        data["stroke_type"]?.try(&.as_s?) || "solid",
        json_number(data["dash_length"]?) || 8.0,
        json_number(data["gap_length"]?) || 4.0,
        data["stroke_cap"]?.try(&.as_s?) || "round",
        data["fill_enabled"]?.try(&.as_bool?) || false,
        color_from_any(data["fill_color"]?, Qt6::Color.new(255, 255, 0)),
        json_number(data["fill_opacity"]?) || 0.3,
        data["fill_type"]?.try(&.as_s?) || "color",
        data["fill_texture_id"]?.try(&.as_s?) || "",
        json_number(data["fill_texture_zoom"]?) || 1.0,
        json_number(data["fill_texture_rotation"]?) || 0.0,
        json_number(data["rotation"]?) || 0.0,
        data["shadow_enabled"]?.try(&.as_bool?) || false,
        data["shadow_type"]?.try(&.as_s?) || "outer",
        color_from_any(data["shadow_color"]?, Qt6::Color.new(0, 0, 0)),
        json_number(data["shadow_opacity"]?) || 0.5,
        json_number(data["shadow_angle"]?) || 120.0,
        json_number(data["shadow_distance"]?) || 5.0,
        json_number(data["shadow_spread"]?) || 0.0,
        json_number(data["shadow_size"]?) || (json_number(data["shadow_blur_radius"]?) || 5.0),
        data["draw_over_grid"]?.try(&.as_bool?) || false,
      )
    end

    private def build_polygon_points(center_x : Float64, center_y : Float64) : Array(Qt6::PointF)
      sides = Math.max(@num_sides, 3)
      points = [] of Qt6::PointF
      sides.times do |index|
        angle = 2.0 * Math::PI * index / sides - Math::PI / 2.0
        points << Qt6::PointF.new(
          center_x + @radius * Math.cos(angle),
          center_y + @radius * Math.sin(angle)
        )
      end
      points
    end

    private def build_pen(state : MapState) : Qt6::QPen
      pen = Qt6::QPen.new(@stroke_color, [@stroke_width * state.zoom, 1.0].max)
      pen.cap_style = case @stroke_cap
                      when "flat"
                        Qt6::PenCapStyle::FlatCap
                      when "square"
                        Qt6::PenCapStyle::SquareCap
                      else
                        Qt6::PenCapStyle::RoundCap
                      end
      pen.join_style = Qt6::PenJoinStyle::RoundJoin
      pen.style = case @stroke_type
                  when "dashed"
                    Qt6::PenStyle::CustomDashLine
                  when "dotted"
                    Qt6::PenStyle::CustomDashLine
                  else
                    Qt6::PenStyle::SolidLine
                  end
      if @stroke_type != "solid"
        pen_width = [@stroke_width, 0.5].max
        dash_pattern = if @stroke_type == "dotted"
                         [0.1, [@gap_length / pen_width, 0.1].max]
                       else
                         [[@dash_length / pen_width, 0.1].max, [@gap_length / pen_width, 0.1].max]
                       end
        pen.dash_pattern = dash_pattern
      end
      pen
    end

    private def build_screen_path(state : MapState) : Qt6::QPainterPath
      world_path = transformed_path
      return world_path if world_path.empty?

      path = Qt6::QPainterPath.new
      world_path.element_count.times do |index|
        element = world_path.element_at(index)
        point = state.screen_point(Qt6::PointF.new(element.x, element.y))
        case element.type
        when Qt6::PainterPathElementType::MoveTo
          path.move_to(point)
        when Qt6::PainterPathElementType::LineTo
          path.line_to(point)
        when Qt6::PainterPathElementType::CurveTo
          control_1 = point
          control_2 = state.screen_point(world_path.element_at(index + 1).point)
          end_point = state.screen_point(world_path.element_at(index + 2).point)
          path.cubic_to(control_1, control_2, end_point)
        when Qt6::PainterPathElementType::CurveToData
        else
        end
      end
      path
    end

    private def pointf(point : Tuple(Float64, Float64)) : Qt6::PointF
      Qt6::PointF.new(point[0], point[1])
    end

    private def source_geometry_center(points : Array(Tuple(Float64, Float64))) : Tuple(Float64, Float64)
      if @shape_type == "polygon" || @shape_type == "ellipse"
        return points.first? || {0.0, 0.0}
      end
      return {0.0, 0.0} if points.empty?

      x_sum = 0.0
      y_sum = 0.0
      points.each do |point|
        x_sum += point[0]
        y_sum += point[1]
      end
      {x_sum / points.size, y_sum / points.size}
    end

    private def rotate_point(
      point : Tuple(Float64, Float64),
      center_point : Tuple(Float64, Float64),
      degrees : Float64
    ) : Tuple(Float64, Float64)
      radians = degrees * Math::PI / 180.0
      dx = point[0] - center_point[0]
      dy = point[1] - center_point[1]
      {
        Math.cos(radians) * dx - Math.sin(radians) * dy + center_point[0],
        Math.sin(radians) * dx + Math.cos(radians) * dy + center_point[1],
      }
    end

    private def self.json_number(value : JSON::Any?) : Float64?
      return nil unless value

      value.as_f? || value.as_i?.try(&.to_f64)
    end

    private def self.color_from_any(value : JSON::Any?, default : Qt6::Color) : Qt6::Color
      return default unless value

      if color = value.as_s?
        color_from_hex(color, default)
      else
        default
      end
    end

    private def self.color_from_hex(value : String, default : Qt6::Color) : Qt6::Color
      clean = value.starts_with?("#") ? value[1..] : value
      return default unless clean.size == 6 || clean.size == 8

      if clean.size == 6
        red = clean[0, 2].to_i?(16)
        green = clean[2, 2].to_i?(16)
        blue = clean[4, 2].to_i?(16)
        return default unless red && green && blue
        Qt6::Color.new(red, green, blue, 255)
      else
        alpha = clean[0, 2].to_i?(16)
        red = clean[2, 2].to_i?(16)
        green = clean[4, 2].to_i?(16)
        blue = clean[6, 2].to_i?(16)
        return default unless alpha && red && green && blue
        Qt6::Color.new(red, green, blue, alpha)
      end
    end

    private def color_hex(color : Qt6::Color) : String
      "##{component_hex(color.red)}#{component_hex(color.green)}#{component_hex(color.blue)}"
    end

    private def component_hex(value : Int32) : String
      value.clamp(0, 255).to_s(16).rjust(2, '0')
    end
  end

  class SketchLayer < MapLayer
    getter objects : Array(SketchObject)
    property shadow_enabled : Bool
    property shadow_type : String
    property shadow_color : Qt6::Color
    property shadow_opacity : Float64
    property shadow_angle : Float64
    property shadow_distance : Float64
    property shadow_spread : Float64
    property shadow_size : Float64

    def initialize(name : String, kind : String, visible : Bool, accent : Qt6::Color, opacity : Int32 = 100)
      super(name, kind, visible, accent, opacity)
      @objects = [] of SketchObject
      @shadow_enabled = false
      @shadow_type = "outer"
      @shadow_color = Qt6::Color.new(0, 0, 0)
      @shadow_opacity = 0.5
      @shadow_angle = 120.0
      @shadow_distance = 5.0
      @shadow_spread = 0.0
      @shadow_size = 5.0
    end

    def add_object(object : SketchObject) : Nil
      @objects << object
    end

    def remove_object(object : SketchObject) : Bool
      index = @objects.index(object)
      return false unless index

      @objects.delete_at(index)
      true
    end

    def clear_objects : Nil
      @objects.clear
    end

    def sketch_count : Int32
      @objects.size.to_i32
    end

    def nearest_object(screen_point : Qt6::PointF, state : MapState, threshold : Float64 = 8.0) : SketchObject?
      world = state.screen_to_world(screen_point)
      @objects.reverse_each do |object|
        return object if object.contains_point(world, threshold / state.zoom)
      end
      nil
    end

    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      paint_filtered(painter, state, nil)
    end

    def paint_filtered(painter : Qt6::QPainter, state : MapState, draw_over_grid : Bool?) : Nil
      layer_opacity = opacity / 100.0
      paint_shadow(painter, state, layer_opacity, draw_over_grid) if @shadow_enabled && @shadow_opacity > 0.0

      @objects.each do |object|
        next if !draw_over_grid.nil? && object.draw_over_grid != draw_over_grid
        object.paint(painter, state, layer_opacity)
      end

      if selected = state.selected_sketch_object
        return unless @objects.includes?(selected)
        return if !draw_over_grid.nil? && selected.draw_over_grid != draw_over_grid

        selected.draw_selection(painter, state, accent)
      end
    end

    private def paint_shadow(painter : Qt6::QPainter, state : MapState, layer_opacity : Float64, draw_over_grid : Bool?) : Nil
      shadow_alpha = (@shadow_opacity * layer_opacity).clamp(0.0, 1.0)
      return if shadow_alpha <= 0.0

      radians = @shadow_angle * Math::PI / 180.0
      offset_x = Math.cos(radians) * @shadow_distance
      offset_y = Math.sin(radians) * @shadow_distance
      shadow_color = Qt6::Color.new(
        @shadow_color.red,
        @shadow_color.green,
        @shadow_color.blue,
        (255.0 * shadow_alpha).round.to_i.clamp(0, 255)
      )

      @objects.each do |object|
        next if !draw_over_grid.nil? && object.draw_over_grid != draw_over_grid

        path = object.screen_path(state)
        next if path.empty?

        shadow_path = shadow_path_for(object, path, state)
        next if shadow_path.empty?

        painter.save
        painter.clip_path = path if @shadow_type == "inner"
        painter.clipping = true if @shadow_type == "inner"
        painter.translate(offset_x, offset_y)
        painter.pen = Qt6::QPen.new(Qt6::Color.new(0, 0, 0, 0), 0.0)
        painter.brush = shadow_color
        painter.draw_path(shadow_path)
        painter.restore
      end
    end

    private def shadow_path_for(object : SketchObject, path : Qt6::QPainterPath, state : MapState) : Qt6::QPainterPath
      shadow_path = Qt6::QPainterPath.new
      shadow_path.add_path(path) if object.fill_enabled && object.shape_type != "line"

      stroke_width = [object.stroke_width * state.zoom, 1.0].max + @shadow_size + (@shadow_spread / 10.0)
      if object.stroke_width > 0.0 || object.shape_type == "line" || shadow_path.empty?
        stroker = Qt6::QPainterPathStroker.new
        stroker.width = [stroke_width, 1.0].max
        shadow_path.add_path(stroker.create_stroke(path))
      end

      shadow_path.simplified
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
