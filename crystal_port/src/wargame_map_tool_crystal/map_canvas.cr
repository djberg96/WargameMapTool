require "qt6"
require "./map_state"

module WargameMapToolCrystal
  class MapCanvas
    getter widget : Qt6::EventWidget

    def initialize(@state : MapState, @status_callback : Proc(String, Nil), @hover_callback : Proc(String, Nil))
      @widget = Qt6::EventWidget.new
      @widget.set_minimum_size(860, 620)
      @widget.focus_policy = Qt6::FocusPolicy::StrongFocus
      @widget.mouse_tracking = true
      wire_events
    end

    def refresh(message : String? = nil) : Nil
      @widget.update
      if text = message
        @status_callback.call(text)
      end
    end

    private def wire_events : Nil
      @widget.on_mouse_press do |event|
        @state.dragging = true
        @state.last_pointer = event.position
        @widget.set_focus
        @status_callback.call("Panning map canvas")
      end

      @widget.on_mouse_move do |event|
        if @state.dragging
          dx = event.position.x - @state.last_pointer.x
          dy = event.position.y - @state.last_pointer.y
          @state.pan_x += dx
          @state.pan_y += dy
          @state.last_pointer = event.position
          refresh
        else
          update_hover(event.position)
        end
      end

      @widget.on_mouse_release do |event|
        update_hover(event.position)
        if @state.dragging
          @state.dragging = false
          @status_callback.call("View settled at #{@state.zoom.round(2)}x")
        end
      end

      @widget.on_leave do |_event|
        @state.hover_hex = nil
        @hover_callback.call("Hover: outside map")
        refresh
      end

      @widget.on_wheel do |event|
        factor = event.angle_delta.y >= 0 ? 1.12 : 0.89
        @state.zoom_at(event.position, factor)
        refresh("Zoom #{@state.zoom.round(2)}x")
      end

      @widget.on_key_press do |event|
        case event.key
        when 43, 61
          center = Qt6::PointF.new(@widget.size.width / 2.0, @widget.size.height / 2.0)
          @state.zoom_at(center, 1.12)
          refresh("Zoom #{@state.zoom.round(2)}x")
        when 45
          center = Qt6::PointF.new(@widget.size.width / 2.0, @widget.size.height / 2.0)
          @state.zoom_at(center, 0.89)
          refresh("Zoom #{@state.zoom.round(2)}x")
        when 48
          @state.reset_view
          refresh("View reset")
        end
      end

      @widget.on_paint_with_painter do |event, painter|
        painter.antialiasing = true
        painter.fill_rect(event.rect, Qt6::Color.new(238, 232, 220))
        draw_map_frame(painter)
        draw_layers(painter)
        draw_grid_overlay(painter)
        draw_hover(painter)
        draw_hud(painter)
      end
    end

    private def update_hover(position : Qt6::PointF) : Nil
      @state.hover_hex = @state.pick_hex(position)

      if hover = @state.hover_hex
        @hover_callback.call("Hover: #{@state.hex_label(hover[0], hover[1])}")
      else
        @hover_callback.call("Hover: outside map")
      end

      refresh
    end

    private def draw_map_frame(painter : Qt6::QPainter) : Nil
      bounds = @state.screen_rect(@state.world_bounds)
      painter.pen = Qt6::QPen.new(Qt6::Color.new(104, 96, 84), 2.0)
      painter.brush = Qt6::Color.new(248, 245, 239)
      painter.draw_rect(bounds)
    end

    private def draw_layers(painter : Qt6::QPainter) : Nil
      @state.layers.each do |layer|
        next unless layer.visible

        layer.paint(painter, @state)
      end
    end

    private def draw_grid_overlay(painter : Qt6::QPainter) : Nil
      grid_pen = Qt6::QPen.new(Qt6::Color.new(183, 175, 159), 1.0)

      @state.rows.times do |row|
        @state.cols.times do |col|
          center = @state.screen_point(@state.hex_center(col, row))

          next unless @state.show_grid

          points = @state.hex_points(col, row).map { |point| @state.screen_point(point) }
          painter.pen = grid_pen
          6.times do |index|
            painter.draw_line(points[index], points[(index + 1) % 6])
          end

          next unless @state.show_coordinates && col.even? && row.even?

          painter.pen = Qt6::Color.new(96, 92, 84)
          painter.draw_text(Qt6::PointF.new(center.x + 6.0, center.y - 7.0), @state.hex_label(col, row))
        end
      end
    end

    private def draw_hover(painter : Qt6::QPainter) : Nil
      hover = @state.hover_hex
      return unless hover

      center = @state.screen_point(@state.hex_center(hover[0], hover[1]))
      painter.pen = Qt6::QPen.new(@state.active_layer.accent, 3.0)
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.draw_ellipse(Qt6::RectF.new(center.x - 15.0, center.y - 15.0, 30.0, 30.0))
      painter.pen = Qt6::Color.new(46, 48, 54)
      painter.draw_text(Qt6::PointF.new(center.x + 10.0, center.y + 18.0), @state.active_tool)
    end

    private def draw_hud(painter : Qt6::QPainter) : Nil
      painter.pen = Qt6::Color.new(56, 52, 48)
      painter.font = Qt6::QFont.new(point_size: 11, bold: true)
      painter.draw_text(Qt6::PointF.new(20.0, 28.0), "Tool #{@state.active_tool} | Layer #{@state.active_layer.name} | Zoom #{@state.zoom.round(2)}x")
      painter.font = Qt6::QFont.new(point_size: 10)
      painter.draw_text(Qt6::PointF.new(20.0, 48.0), "Crystal Qt6 vertical slice for WargameMapTool")
    end
  end
end