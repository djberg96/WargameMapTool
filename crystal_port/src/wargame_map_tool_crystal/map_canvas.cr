require "qt6"
require "./map_state"

module WargameMapToolCrystal
  class MapCanvas
    CLICK_SELECTION_THRESHOLD = 5.0

    @press_pointer : Qt6::PointF?
    @drag_text_object : TextObject?
    @drag_asset_object : AssetObject?
    @drag_path_object : PathObject?
    @drag_path_endpoint : String?
    @drag_mode : String

    getter widget : Qt6::EventWidget

    def initialize(@state : MapState, @status_callback : Proc(String, Nil), @hover_callback : Proc(String, Nil))
      @widget = Qt6::EventWidget.new
      @widget.set_minimum_size(860, 620)
      @widget.focus_policy = Qt6::FocusPolicy::StrongFocus
      @widget.mouse_tracking = true
      @press_pointer = nil
      @drag_text_object = nil
      @drag_asset_object = nil
      @drag_path_object = nil
      @drag_path_endpoint = nil
      @drag_mode = "pan"
      @drag_moved = false
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
        @press_pointer = event.position
        @drag_text_object = nil
        @drag_asset_object = nil
        @drag_path_object = nil
        @drag_path_endpoint = nil
        @drag_mode = "pan"
        @drag_moved = false

        if @state.active_tool == "Text" && @state.selected_text_present?
          selected = @state.selected_text_object
          hovered = @state.text_layer.try(&.nearest_text(@state, event.position))
          if selected && hovered == selected
            @drag_text_object = selected
            @drag_mode = "text_move"
          end
        elsif @state.active_tool == "Asset" && @state.selected_asset_present?
          selected = @state.selected_asset_object
          hovered = @state.asset_layer.try(&.nearest_asset(@state, event.position))
          if selected && hovered == selected
            @drag_asset_object = selected
            @drag_mode = "asset_move"
          end
        elsif @state.active_tool == "Path" && @state.selected_path_present? && @state.pending_path_anchor.nil?
          selected = @state.selected_path_object
          if selected && (endpoint = selected.endpoint_hit(@state, event.position))
            @drag_path_object = selected
            @drag_path_endpoint = endpoint
            @drag_mode = "path_endpoint_move"
          end
        end

        @widget.set_focus
      end

      @widget.on_mouse_move do |event|
        if @state.dragging
          if press = @press_pointer
            total_dx = event.position.x - press.x
            total_dy = event.position.y - press.y
            @drag_moved ||= Math.sqrt(total_dx * total_dx + total_dy * total_dy) > CLICK_SELECTION_THRESHOLD
          end

          if @drag_moved
            dx = event.position.x - @state.last_pointer.x
            dy = event.position.y - @state.last_pointer.y

            if @drag_mode == "text_move" && (object = @drag_text_object)
              object.x += dx / @state.zoom
              object.y += dy / @state.zoom
            elsif @drag_mode == "asset_move" && (object = @drag_asset_object)
              object.x += dx / @state.zoom
              object.y += dy / @state.zoom
            elsif @drag_mode == "path_endpoint_move" && (path_object = @drag_path_object)
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              if hover = @state.hover_hex
                if @drag_path_endpoint == "start"
                  unless hover[0] == path_object.col_b && hover[1] == path_object.row_b
                    path_object.col_a = hover[0]
                    path_object.row_a = hover[1]
                  end
                elsif @drag_path_endpoint == "end"
                  unless hover[0] == path_object.col_a && hover[1] == path_object.row_a
                    path_object.col_b = hover[0]
                    path_object.row_b = hover[1]
                  end
                end
              end
            else
              @state.pan_x += dx
              @state.pan_y += dy
            end

            @state.last_pointer = event.position
            refresh
          end
        else
          update_hover(event.position)
        end
      end

      @widget.on_mouse_release do |event|
        update_hover(event.position)
        if @state.dragging
          if !@drag_moved && @state.active_tool == "Text"
            if object = @state.select_hovered_text
              refresh("Selected text '#{object.text}'")
            else
              @state.clear_text_selection
              refresh("Cleared text selection")
            end
          elsif !@drag_moved && @state.active_tool == "Path"
            if object = @state.select_hovered_path
              refresh("Selected path #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}")
            elsif hover = @state.hover_hex
              if anchor = @state.pending_path_anchor
                if anchor == hover
                  @state.clear_pending_path_anchor
                  refresh("Canceled pending path at #{@state.hex_label(anchor[0], anchor[1])}")
                elsif object = @state.create_path_from_pending(hover)
                  refresh("Created path #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}")
                else
                  refresh("Path creation failed")
                end
              else
                @state.begin_pending_path(hover)
                refresh("Path start set at #{@state.hex_label(hover[0], hover[1])}")
              end
            else
              @state.clear_pending_path_anchor
              @state.clear_path_selection
              refresh("Cleared path selection")
            end
          elsif !@drag_moved && @state.active_tool == "Asset"
            if object = @state.select_hovered_asset
              refresh("Selected asset '#{object.label}'")
            else
              @state.clear_asset_selection
              refresh("Cleared asset selection")
            end
          elsif @drag_moved && @drag_mode == "text_move"
            if object = @drag_text_object
              refresh("Moved text '#{object.text}'")
            end
          elsif @drag_moved && @drag_mode == "asset_move"
            if object = @drag_asset_object
              @state.snap_asset_to_hex(object) if object.snap_to_hex
              refresh("Moved asset '#{object.label}'")
            end
          elsif @drag_moved && @drag_mode == "path_endpoint_move"
            if object = @drag_path_object
              refresh("Reshaped path #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}")
            end
          elsif @drag_moved
            @status_callback.call("View settled at #{@state.zoom.round(2)}x")
          end

          @state.dragging = false
          @press_pointer = nil
          @drag_text_object = nil
          @drag_asset_object = nil
          @drag_path_object = nil
          @drag_path_endpoint = nil
          @drag_mode = "pan"
          @drag_moved = false
        end
      end

      @widget.on_leave do |_event|
        @state.hover_hex = nil
        @state.hover_screen = nil
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
        draw_pending_path_preview(painter)
        draw_hud(painter)
      end
    end

    private def update_hover(position : Qt6::PointF) : Nil
      @state.hover_screen = position
      @state.hover_hex = @state.pick_hex(position)

      base_message = if hover = @state.hover_hex
                       "Hover: #{@state.hex_label(hover[0], hover[1])}"
                     else
                       "Hover: outside map"
                     end

      if object = @state.hovered_text_object
        base_message = "#{base_message} | Text: #{object.text}"
      end

      if object = @state.hovered_path_object
        base_message = "#{base_message} | Path: #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}"
      elsif @state.active_tool == "Path"
        if anchor = @state.pending_path_anchor
          if hover = @state.hover_hex
            if anchor != hover
              base_message = "#{base_message} | New Path: #{@state.hex_label(anchor[0], anchor[1])}-#{@state.hex_label(hover[0], hover[1])}"
            else
              base_message = "#{base_message} | Click again to cancel path start"
            end
          else
            base_message = "#{base_message} | Pending Path: #{@state.hex_label(anchor[0], anchor[1])}"
          end
        end
      end

      if object = @state.hovered_asset_object
        base_message = "#{base_message} | Asset: #{object.label}"
      end

      if base_message.includes?("|")
        @hover_callback.call(base_message)
      else
        @hover_callback.call(base_message)
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

    private def draw_pending_path_preview(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Path"
      return unless anchor = @state.pending_path_anchor

      start_point = @state.screen_point(@state.hex_center(anchor[0], anchor[1]))

      painter.save
      painter.pen = Qt6::QPen.new(@state.active_layer.accent, 2.0)
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = 0.8
      painter.draw_ellipse(Qt6::RectF.new(start_point.x - 10.0, start_point.y - 10.0, 20.0, 20.0))

      if hover = @state.hover_hex
        unless hover == anchor
          style_source = @state.selected_path_object if @state.selected_path_present?
          pen = Qt6::QPen.new(style_source ? style_source.color : @state.active_layer.accent, style_source ? style_source.width : 3.0)
          pen.style = case style_source.try(&.line_type)
                      when "dashed"
                        Qt6::PenStyle::DashLine
                      when "dotted"
                        Qt6::PenStyle::DotLine
                      else
                        Qt6::PenStyle::DashLine
                      end

          end_point = @state.screen_point(@state.hex_center(hover[0], hover[1]))
          painter.pen = pen
          painter.opacity = style_source ? style_source.opacity.clamp(0.0, 1.0) : 0.75
          painter.draw_line(start_point, end_point)
        end
      end

      painter.restore
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