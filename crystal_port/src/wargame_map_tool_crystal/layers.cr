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

  class PathLayer < MapLayer
    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      painter.pen = Qt6::QPen.new(Qt6::Color.new(174, 82, 54), 3.0)
      points = state.route_hexes.map do |hex|
        state.screen_point(state.hex_center(hex[0], hex[1]))
      end

      points.each_cons(2) do |segment|
        painter.draw_line(segment[0], segment[1])
      end

      painter.brush = Qt6::Color.new(174, 82, 54)
      points.each do |point|
        painter.draw_ellipse(Qt6::RectF.new(point.x - 4.0, point.y - 4.0, 8.0, 8.0))
      end
    end
  end

  class LabelLayer < MapLayer
    def paint(painter : Qt6::QPainter, state : MapState) : Nil
      painter.pen = Qt6::Color.new(54, 60, 92)
      painter.font = Qt6::QFont.new(point_size: 11, bold: true)

      state.label_hexes.each do |entry|
        center = state.screen_point(state.hex_center(entry[1], entry[2]))
        painter.draw_text(Qt6::PointF.new(center.x + 10.0, center.y - 10.0), entry[0])
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