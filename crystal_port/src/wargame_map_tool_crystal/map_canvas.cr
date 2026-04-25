require "qt6"
require "./map_state"

module WargameMapToolCrystal
  class MapCanvas
    CLICK_SELECTION_THRESHOLD   = 5.0
    MIN_FREEFORM_POINT_DISTANCE = 2.0
    SKETCH_HANDLE_SIZE          = 6.0
    SKETCH_HANDLE_HIT_RADIUS    = 10.0
    SKETCH_ROTATE_HANDLE_OFFSET = 26.0
    KEY_C                       = 67
    KEY_V                       = 86
    CONTROL_MODIFIER            = 0x04000000
    META_MODIFIER               = 0x10000000

    @press_pointer : Qt6::PointF?
    @drag_text_object : TextObject?
    @drag_asset_object : AssetObject?
    @drag_sketch_object : SketchObject?
    @drag_path_object : PathObject?
    @drag_path_endpoint : String?
    @drag_freeform_path_object : FreeformPathObject?
    @drag_freeform_point_index : Int32?
    @hovered_border_edge : Tuple(Int32, Int32, Int32, Int32)?
    @hovered_hexside_edge : Tuple(Int32, Int32, Int32, Int32)?
    @last_hexside_drag_edge : Tuple(Int32, Int32, Int32, Int32)?
    @freeform_draw_points : Array(Tuple(Float64, Float64))
    @sketch_draw_points : Array(Tuple(Float64, Float64))
    @hovered_path_endpoint : String?
    @fill_drag_count : Int32
    @hexside_drag_count : Int32
    @drag_mode : String
    @sketch_preview_start : Qt6::PointF?
    @sketch_preview_end : Qt6::PointF?
    @sketch_resize_anchor : Tuple(Float64, Float64)?
    @sketch_resize_points : Array(Tuple(Float64, Float64))
    @sketch_resize_radius : Float64
    @sketch_resize_rx : Float64
    @sketch_resize_ry : Float64
    @sketch_rotate_initial : Float64
    @sketch_rotate_initial_angle : Float64
    @sketch_move_points : Array(Tuple(Float64, Float64))
    @sketch_move_center : Tuple(Float64, Float64)?
    @sketch_move_pointer_offset : Tuple(Float64, Float64)?

    getter widget : Qt6::EventWidget

    def initialize(@state : MapState, @status_callback : Proc(String, Nil), @hover_callback : Proc(String, Nil))
      @widget = Qt6::EventWidget.new
      @widget.set_minimum_size(860, 620)
      @widget.focus_policy = Qt6::FocusPolicy::StrongFocus
      @widget.mouse_tracking = true
      @press_pointer = nil
      @drag_text_object = nil
      @drag_asset_object = nil
      @drag_sketch_object = nil
      @drag_path_object = nil
      @drag_path_endpoint = nil
      @drag_freeform_path_object = nil
      @drag_freeform_point_index = nil
      @hovered_border_edge = nil
      @hovered_hexside_edge = nil
      @last_hexside_drag_edge = nil
      @freeform_draw_points = [] of Tuple(Float64, Float64)
      @sketch_draw_points = [] of Tuple(Float64, Float64)
      @hovered_path_endpoint = nil
      @fill_drag_count = 0
      @hexside_drag_count = 0
      @drag_mode = "pan"
      @sketch_preview_start = nil
      @sketch_preview_end = nil
      @sketch_resize_anchor = nil
      @sketch_resize_points = [] of Tuple(Float64, Float64)
      @sketch_resize_radius = 0.0
      @sketch_resize_rx = 0.0
      @sketch_resize_ry = 0.0
      @sketch_rotate_initial = 0.0
      @sketch_rotate_initial_angle = 0.0
      @sketch_move_points = [] of Tuple(Float64, Float64)
      @sketch_move_center = nil
      @sketch_move_pointer_offset = nil
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
        @drag_sketch_object = nil
        @drag_path_object = nil
        @drag_path_endpoint = nil
        @drag_freeform_path_object = nil
        @drag_freeform_point_index = nil
        @hovered_border_edge = nil
        @hovered_hexside_edge = nil
        @last_hexside_drag_edge = nil
        @freeform_draw_points.clear
        @sketch_draw_points.clear
        @fill_drag_count = 0
        @hexside_drag_count = 0
        @drag_mode = "pan"
        @sketch_preview_start = nil
        @sketch_preview_end = nil
        @sketch_resize_anchor = nil
        @sketch_move_points.clear
        @sketch_move_center = nil
        @sketch_move_pointer_offset = nil
        @drag_moved = false

        handled_press = false

        if @state.active_tool == "Border"
          @state.hover_screen = event.position
          @state.hover_hex = @state.pick_hex(event.position)
          update_hovered_border_edge(event.position)

          if event.button == 2
            if edge = @hovered_border_edge
              if object = border_object_for_edge(edge)
                if (layer = @state.border_layer) && layer.remove_border(object)
                  @state.clear_border_selection if @state.selected_border_object == object
                  refresh("Removed border #{edge_label(edge)}")
                  @state.dragging = false
                  @press_pointer = nil
                  @drag_mode = "border_remove"
                  handled_press = true
                end
              end
            end
          end
        elsif @state.active_tool == "Hexside"
          @state.hover_screen = event.position
          @state.hover_hex = @state.pick_hex(event.position)
          update_hovered_hexside_edge(event.position)

          if event.button == 1
            if edge = @hovered_hexside_edge
              unless hexside_object_for_edge(edge)
                @hexside_drag_count = paint_hexside(edge)
                @drag_mode = "hexside_paint"
              end
            end
          elsif event.button == 2
            if edge = @hovered_hexside_edge
              @hexside_drag_count = clear_hexside(edge)
              @drag_mode = "hexside_erase"
              handled_press = @hexside_drag_count > 0
            end
          end
        elsif @state.active_tool == "Freeform"
          @state.hover_screen = event.position
          @state.hover_hex = @state.pick_hex(event.position)

          if event.button == 1
            selected = @state.selected_freeform_path_object
            if selected && (point_index = selected.point_hit_index(@state, event.position))
              @drag_freeform_path_object = selected
              @drag_freeform_point_index = point_index
              @drag_mode = "freeform_point_move"
              handled_press = true
            elsif selected && @state.hovered_freeform_path_object == selected
              @drag_freeform_path_object = selected
              @drag_mode = "freeform_move"
              handled_press = true
            else
              world = @state.screen_to_world(event.position)
              @freeform_draw_points = [{world.x.to_f64, world.y.to_f64}] of Tuple(Float64, Float64)
              @drag_mode = "freeform_pending"
            end
          elsif event.button == 2
            if object = @state.hovered_freeform_path_object
              if (layer = @state.freeform_path_layer) && layer.remove_path(object)
                @state.clear_freeform_path_selection if @state.selected_freeform_path_object == object
                refresh("Removed freeform path")
                @state.dragging = false
                @press_pointer = nil
                @drag_mode = "freeform_remove"
                handled_press = true
              end
            end
          end
        elsif @state.active_tool == "Sketch"
          @state.hover_screen = event.position
          @state.hover_hex = @state.pick_hex(event.position)

          if event.button == 1
            selected = @state.selected_sketch_object if @state.selected_sketch_present?
            hovered = @state.hovered_sketch_object
            hovered ||= @state.sketch_layer.try(&.nearest_object(event.position, @state))
            if selected && start_sketch_handle_interaction(event.position, selected)
              handled_press = true
            elsif selected && hovered == selected
              handled_press = begin_sketch_move_interaction(selected, event.position)
            elsif hovered
              @state.selected_sketch_object = hovered
              handled_press = begin_sketch_move_interaction(hovered, event.position)
              refresh
            else
              world = snapped_sketch_world_point(@state.screen_to_world(event.position), @state.sketch_shape_type != "freehand")
              if @state.sketch_shape_type == "freehand"
                @sketch_draw_points << {world.x.to_f64, world.y.to_f64}
                @drag_mode = "sketch_freehand_pending"
              else
                @sketch_preview_start = world
                @sketch_preview_end = world
                @drag_mode = "sketch_pending"
              end
            end
          elsif event.button == 2
            if object = @state.hovered_sketch_object
              if (layer = @state.sketch_layer) && layer.remove_object(object)
                @state.clear_sketch_selection if @state.selected_sketch_object == object
                refresh("Removed sketch #{object.shape_type}")
                @state.dragging = false
                @press_pointer = nil
                @drag_mode = "sketch_remove"
                handled_press = true
              end
            end
          end
        end

        if !handled_press && @state.active_tool == "Fill"
          if hover = @state.pick_hex(event.position)
            @state.hover_hex = hover
            if event.button == 1
              @fill_drag_count = paint_fill(hover)
              @drag_mode = "fill_paint"
            elsif event.button == 2
              @fill_drag_count = clear_fill(hover)
              @drag_mode = "fill_erase"
            end
          end
        elsif !handled_press && @state.active_tool == "Text" && @state.selected_text_present?
          selected = @state.selected_text_object
          hovered = @state.text_layer.try(&.nearest_text(@state, event.position))
          if selected && hovered == selected
            @drag_text_object = selected
            @drag_mode = "text_move"
          end
        elsif !handled_press && @state.active_tool == "Asset" && @state.selected_asset_present?
          selected = @state.selected_asset_object
          hovered = @state.asset_layer.try(&.nearest_asset(@state, event.position))
          if selected && hovered == selected
            @drag_asset_object = selected
            @drag_mode = "asset_move"
          end
        elsif !handled_press && @state.active_tool == "Path" && @state.selected_path_present? && @state.pending_path_anchor.nil?
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
            elsif @drag_mode == "fill_paint"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              if hover = @state.hover_hex
                @fill_drag_count += paint_fill(hover)
              end
            elsif @drag_mode == "fill_erase"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              if hover = @state.hover_hex
                @fill_drag_count += clear_fill(hover)
              end
            elsif @drag_mode == "hexside_paint"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              update_hovered_hexside_edge(event.position)
              if edge = @hovered_hexside_edge
                @hexside_drag_count += paint_hexside(edge)
              end
            elsif @drag_mode == "hexside_erase"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              update_hovered_hexside_edge(event.position)
              if edge = @hovered_hexside_edge
                @hexside_drag_count += clear_hexside(edge)
              end
            elsif @drag_mode == "freeform_pending" || @drag_mode == "freeform_draw"
              @drag_mode = "freeform_draw"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              append_freeform_draw_point(@state.screen_to_world(event.position))
            elsif @drag_mode == "asset_move" && (object = @drag_asset_object)
              object.x += dx / @state.zoom
              object.y += dy / @state.zoom
            elsif @drag_mode == "sketch_move" && (sketch_object = @drag_sketch_object)
              current_world = @state.screen_to_world(event.position)
              apply_sketch_move(sketch_object, current_world)
            elsif @drag_mode == "sketch_resize" && (sketch_object = @drag_sketch_object)
              if anchor = @sketch_resize_anchor
                current_world = snapped_selected_sketch_world_point(@state.screen_to_world(event.position))
                sketch_object.resize_from_anchor(
                  anchor,
                  {current_world.x.to_f64, current_world.y.to_f64},
                  @sketch_resize_points,
                  @sketch_resize_radius,
                  @sketch_resize_rx,
                  @sketch_resize_ry,
                )
              end
            elsif @drag_mode == "sketch_rotate" && (sketch_object = @drag_sketch_object)
              current_world = @state.screen_to_world(event.position)
              sketch_object.rotation = @sketch_rotate_initial + (
                sketch_object.rotation_angle_for({current_world.x.to_f64, current_world.y.to_f64}) - @sketch_rotate_initial_angle
              )
            elsif @drag_mode == "path_endpoint_move" && (path_object = @drag_path_object)
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              if hover = @state.hover_hex
                if @drag_path_endpoint == "start"
                  if @state.neighboring_hexes?(hover[0], hover[1], path_object.col_b, path_object.row_b)
                    path_object.col_a = hover[0]
                    path_object.row_a = hover[1]
                  end
                elsif @drag_path_endpoint == "end"
                  if @state.neighboring_hexes?(path_object.col_a, path_object.row_a, hover[0], hover[1])
                    path_object.col_b = hover[0]
                    path_object.row_b = hover[1]
                  end
                end
              end
            elsif @drag_mode == "freeform_point_move"
              if (freeform_object = @drag_freeform_path_object) && (point_index = @drag_freeform_point_index)
                if point_index >= 0 && point_index < freeform_object.points.size
                  world = @state.screen_to_world(event.position)
                  freeform_object.points[point_index] = {world.x.to_f64, world.y.to_f64}
                  @state.hover_screen = event.position
                  @state.hover_hex = @state.pick_hex(event.position)
                end
              end
            elsif @drag_mode == "freeform_move"
              if freeform_object = @drag_freeform_path_object
                previous_world = @state.screen_to_world(@state.last_pointer)
                current_world = @state.screen_to_world(event.position)
                freeform_object.translate(
                  current_world.x.to_f64 - previous_world.x.to_f64,
                  current_world.y.to_f64 - previous_world.y.to_f64,
                )
                @state.hover_screen = event.position
                @state.hover_hex = @state.pick_hex(event.position)
              end
            elsif @drag_mode == "sketch_pending" || @drag_mode == "sketch_draw"
              @drag_mode = "sketch_draw"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              @sketch_preview_end = snapped_sketch_world_point(@state.screen_to_world(event.position), true)
            elsif @drag_mode == "sketch_freehand_pending" || @drag_mode == "sketch_freehand_draw"
              @drag_mode = "sketch_freehand_draw"
              @state.hover_screen = event.position
              @state.hover_hex = @state.pick_hex(event.position)
              append_sketch_draw_point(@state.screen_to_world(event.position))
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
          if @drag_mode == "fill_paint"
            count = @fill_drag_count
            label = if hover = @state.hover_hex
                      @state.hex_label(hover[0], hover[1])
                    else
                      "terrain"
                    end
            refresh(count <= 1 ? "Filled #{label}" : "Filled #{count} hexes")
          elsif @drag_mode == "fill_erase"
            count = @fill_drag_count
            label = if hover = @state.hover_hex
                      @state.hex_label(hover[0], hover[1])
                    else
                      "terrain"
                    end
            refresh(count <= 1 ? "Cleared fill #{label}" : "Cleared #{count} fills")
          elsif @drag_mode == "hexside_paint"
            count = @hexside_drag_count
            label = if edge = @last_hexside_drag_edge
                      edge_label(edge)
                    else
                      "hexside"
                    end
            refresh(count <= 1 ? "Created hexside #{label}" : "Created #{count} hexsides")
          elsif @drag_mode == "hexside_erase"
            count = @hexside_drag_count
            label = if edge = @last_hexside_drag_edge
                      edge_label(edge)
                    else
                      "hexside"
                    end
            refresh(count <= 1 ? "Removed hexside #{label}" : "Removed #{count} hexsides")
          elsif @drag_mode == "freeform_draw"
            append_freeform_draw_point(@state.screen_to_world(event.position), true)
            if object = @state.create_freeform_path(@freeform_draw_points)
              refresh("Created freeform path with #{object.point_count} points")
            else
              refresh("Freeform path creation failed")
            end
          elsif @drag_mode == "sketch_draw"
            if start_point = @sketch_preview_start
              end_point = @sketch_preview_end || @state.screen_to_world(event.position)
              if object = @state.create_sketch_from_drag(start_point, end_point)
                refresh("Created sketch #{object.shape_type}")
              else
                refresh("Sketch creation failed")
              end
            else
              refresh("Sketch creation failed")
            end
          elsif @drag_mode == "sketch_freehand_draw"
            append_sketch_draw_point(@state.screen_to_world(event.position), true)
            if object = @state.create_sketch_freehand(@sketch_draw_points)
              refresh("Created sketch #{object.shape_type}")
            else
              refresh("Sketch creation failed")
            end
          elsif !@drag_moved && @state.active_tool == "Text"
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
                elsif !@state.neighboring_hexes?(anchor[0], anchor[1], hover[0], hover[1])
                  refresh("Choose a neighboring hex from #{@state.hex_label(anchor[0], anchor[1])}")
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
          elsif !@drag_moved && @state.active_tool == "Border"
            if edge = @hovered_border_edge
              if object = border_object_for_edge(edge)
                @state.selected_text_object = nil
                @state.selected_asset_object = nil
                @state.selected_path_object = nil
                @state.clear_pending_path_anchor
                @state.selected_border_object = object
                refresh("Selected border #{edge_label(edge)}")
              elsif object = @state.create_border(edge[0], edge[1], edge[2], edge[3])
                refresh("Created border #{edge_label(object.edge_key)}")
              else
                refresh("Border placement failed")
              end
            else
              @state.clear_border_selection
              refresh("Cleared border selection")
            end
          elsif !@drag_moved && @state.active_tool == "Hexside"
            if edge = @hovered_hexside_edge
              if object = hexside_object_for_edge(edge)
                @state.selected_border_object = nil
                @state.selected_text_object = nil
                @state.selected_asset_object = nil
                @state.selected_path_object = nil
                @state.selected_freeform_path_object = nil
                @state.clear_pending_path_anchor
                @state.selected_hexside_object = object
                refresh("Selected hexside #{edge_label(edge)}")
              elsif object = @state.create_hexside(edge[0], edge[1], edge[2], edge[3])
                refresh("Created hexside #{edge_label(object.edge_key)}")
              else
                refresh("Hexside placement failed")
              end
            else
              @state.clear_hexside_selection
              refresh("Cleared hexside selection")
            end
          elsif !@drag_moved && @state.active_tool == "Freeform"
            if object = @state.select_hovered_freeform_path
              refresh("Selected freeform path (#{object.point_count} points)")
            else
              @state.clear_freeform_path_selection
              refresh("Cleared freeform path selection")
            end
          elsif !@drag_moved && @state.active_tool == "Sketch"
            if object = @state.select_hovered_sketch
              refresh("Selected sketch #{object.shape_type}")
            else
              @state.clear_sketch_selection
              refresh("Cleared sketch selection")
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
          elsif @drag_moved && @drag_mode == "freeform_point_move"
            if object = @drag_freeform_path_object
              refresh("Moved freeform control point (#{object.point_count} points)")
            end
          elsif @drag_moved && @drag_mode == "freeform_move"
            if object = @drag_freeform_path_object
              refresh("Moved freeform path (#{object.point_count} points)")
            end
          elsif @drag_moved && @drag_mode == "sketch_move"
            if sketch_object = @drag_sketch_object
              refresh("Moved sketch #{sketch_object.shape_type}")
            end
          elsif @drag_moved && @drag_mode == "sketch_resize"
            if sketch_object = @drag_sketch_object
              refresh("Resized sketch #{sketch_object.shape_type}")
            end
          elsif @drag_moved && @drag_mode == "sketch_rotate"
            if sketch_object = @drag_sketch_object
              refresh("Rotated sketch #{sketch_object.shape_type}")
            end
          elsif @drag_moved
            @status_callback.call("View settled at #{@state.zoom.round(2)}x")
          end

          @state.dragging = false
          @press_pointer = nil
          @drag_text_object = nil
          @drag_asset_object = nil
          @drag_sketch_object = nil
          @drag_path_object = nil
          @drag_path_endpoint = nil
          @drag_freeform_path_object = nil
          @drag_freeform_point_index = nil
          @freeform_draw_points.clear
          @sketch_draw_points.clear
          @fill_drag_count = 0
          @hexside_drag_count = 0
          @last_hexside_drag_edge = nil
          @drag_mode = "pan"
          @sketch_preview_start = nil
          @sketch_preview_end = nil
          @sketch_resize_anchor = nil
          @sketch_resize_points.clear
          @sketch_resize_radius = 0.0
          @sketch_resize_rx = 0.0
          @sketch_resize_ry = 0.0
          @sketch_rotate_initial = 0.0
          @sketch_rotate_initial_angle = 0.0
          @sketch_move_points.clear
          @sketch_move_center = nil
          @sketch_move_pointer_offset = nil
          @drag_moved = false
        end
      end

      @widget.on_leave do |_event|
        @state.hover_hex = nil
        @state.hover_screen = nil
        @hovered_border_edge = nil
        @hovered_hexside_edge = nil
        @hovered_path_endpoint = nil
        @hover_callback.call("Hover: outside map")
        refresh
      end

      @widget.on_wheel do |event|
        factor = event.angle_delta.y >= 0 ? 1.12 : 0.89
        @state.zoom_at(event.position, factor)
        refresh("Zoom #{@state.zoom.round(2)}x")
      end

      @widget.on_key_press do |event|
        command_pressed = (event.modifiers & CONTROL_MODIFIER) != 0 || (event.modifiers & META_MODIFIER) != 0

        if command_pressed && event.key == KEY_C && @state.active_tool == "Sketch"
          if object = @state.copy_selected_sketch
            refresh("Copied sketch #{object.shape_type}")
          else
            refresh("Select a sketch to copy")
          end
          next
        elsif command_pressed && event.key == KEY_V && @state.active_tool == "Sketch"
          if object = @state.paste_sketch_from_clipboard
            refresh("Pasted sketch #{object.shape_type}")
          else
            refresh("Copy a sketch before pasting")
          end
          next
        end

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
        when 16777216
          if @state.active_tool == "Path" && (anchor = @state.pending_path_anchor)
            @state.clear_pending_path_anchor
            refresh("Canceled pending path at #{@state.hex_label(anchor[0], anchor[1])}")
          end
        when 16777219, 16777223
          if @state.active_tool == "Path"
            if anchor = @state.pending_path_anchor
              @state.clear_pending_path_anchor
              refresh("Canceled pending path at #{@state.hex_label(anchor[0], anchor[1])}")
            elsif object = (@state.selected_path_object if @state.selected_path_present?)
              label = "#{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}"
              if (layer = @state.path_layer) && layer.remove_path(object)
                @state.clear_path_selection
                refresh("Deleted path #{label}")
              else
                refresh("Path delete failed")
              end
            end
          elsif @state.active_tool == "Border"
            if object = (@state.selected_border_object if @state.selected_border_present?)
              label = edge_label(object.edge_key)
              if (layer = @state.border_layer) && layer.remove_border(object)
                @state.clear_border_selection
                refresh("Deleted border #{label}")
              else
                refresh("Border delete failed")
              end
            end
          elsif @state.active_tool == "Hexside"
            if object = (@state.selected_hexside_object if @state.selected_hexside_present?)
              label = edge_label(object.edge_key)
              if (layer = @state.hexside_layer) && layer.remove_hexside(object)
                @state.clear_hexside_selection
                refresh("Deleted hexside #{label}")
              else
                refresh("Hexside delete failed")
              end
            end
          elsif @state.active_tool == "Freeform"
            if object = (@state.selected_freeform_path_object if @state.selected_freeform_path_present?)
              if (layer = @state.freeform_path_layer) && layer.remove_path(object)
                @state.clear_freeform_path_selection
                refresh("Deleted freeform path")
              else
                refresh("Freeform path delete failed")
              end
            end
          elsif @state.active_tool == "Sketch"
            if object = (@state.selected_sketch_object if @state.selected_sketch_present?)
              if (layer = @state.sketch_layer) && layer.remove_object(object)
                @state.clear_sketch_selection
                refresh("Deleted sketch #{object.shape_type}")
              else
                refresh("Sketch delete failed")
              end
            end
          end
        end
      end

      @widget.on_paint_with_painter do |event, painter|
        painter.antialiasing = true
        painter.fill_rect(event.rect, Qt6::Color.new(238, 232, 220))
        draw_map_frame(painter)
        draw_layers(painter)
        draw_grid_overlay(painter)
        draw_hover(painter)
        draw_hovered_border_edge(painter)
        draw_hovered_hexside_edge(painter)
        draw_pending_path_preview(painter)
        draw_pending_freeform_preview(painter)
        draw_pending_sketch_preview(painter)
        draw_selected_sketch_handles(painter)
        draw_hovered_path_endpoint(painter)
        draw_hud(painter)
      end
    end

    private def update_hover(position : Qt6::PointF) : Nil
      @state.hover_screen = position
      @state.hover_hex = @state.pick_hex(position)
      update_hovered_border_edge(position)
      update_hovered_hexside_edge(position)
      @hovered_path_endpoint = nil

      if @state.active_tool == "Path" && @state.pending_path_anchor.nil? && (object = (@state.selected_path_object if @state.selected_path_present?))
        @hovered_path_endpoint = object.endpoint_hit(@state, position)
      end

      base_message = if hover = @state.hover_hex
                       "Hover: #{@state.hex_label(hover[0], hover[1])}"
                     else
                       "Hover: outside map"
                     end

      if object = @state.hovered_text_object
        base_message = "#{base_message} | Text: #{object.text}"
      end

      if object = @state.hovered_freeform_path_object
        base_message = "#{base_message} | Freeform: #{object.point_count} points"
      end

      if object = @state.hovered_sketch_object
        base_message = "#{base_message} | Sketch: #{object.shape_type}"
      end

      if object = @state.hovered_path_object
        base_message = "#{base_message} | Path: #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}"
        if endpoint = @hovered_path_endpoint
          base_message = "#{base_message} | Drag #{endpoint} handle"
        end
      elsif @state.active_tool == "Border"
        if edge = @hovered_border_edge
          if border_object_for_edge(edge)
            base_message = "#{base_message} | Border: #{edge_label(edge)}"
          else
            base_message = "#{base_message} | New Border: #{edge_label(edge)}"
          end
        end
      elsif @state.active_tool == "Hexside"
        if edge = @hovered_hexside_edge
          if hexside_object_for_edge(edge)
            base_message = "#{base_message} | Hexside: #{edge_label(edge)}"
          else
            base_message = "#{base_message} | New Hexside: #{edge_label(edge)}"
          end
        end
      elsif @state.active_tool == "Path"
        if anchor = @state.pending_path_anchor
          if hover = @state.hover_hex
            if anchor != hover
              if @state.neighboring_hexes?(anchor[0], anchor[1], hover[0], hover[1])
                base_message = "#{base_message} | New Path: #{@state.hex_label(anchor[0], anchor[1])}-#{@state.hex_label(hover[0], hover[1])}"
              else
                base_message = "#{base_message} | Choose a neighboring hex from #{@state.hex_label(anchor[0], anchor[1])}"
              end
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
      if @state.active_tool == "Fill"
        preview_color = @state.terrain_layer.try(&.accent) || @state.active_layer.accent
        @state.hexes_in_radius(hover[0], hover[1]).each do |hex|
          polygon = Qt6::QPolygonF.new(
            @state.hex_points(hex[0], hex[1]).map { |point| @state.screen_point(point) }
          )

          painter.save
          painter.pen = Qt6::QPen.new(preview_color, 2.0)
          painter.brush = preview_color
          painter.opacity = 0.28
          painter.draw_polygon(polygon)
          painter.restore
        end
      end

      if @state.active_tool == "Border" && @hovered_border_edge
        painter.pen = Qt6::QPen.new(@state.active_layer.accent, 3.0)
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.draw_ellipse(Qt6::RectF.new(center.x - 15.0, center.y - 15.0, 30.0, 30.0))
      else
        painter.pen = Qt6::QPen.new(@state.active_layer.accent, 3.0)
        painter.brush = Qt6::Color.new(0, 0, 0, 0)
        painter.draw_ellipse(Qt6::RectF.new(center.x - 15.0, center.y - 15.0, 30.0, 30.0))
      end
      painter.pen = Qt6::Color.new(46, 48, 54)
      painter.draw_text(Qt6::PointF.new(center.x + 10.0, center.y + 18.0), @state.active_tool)
    end

    private def paint_fill(hex : Tuple(Int32, Int32)) : Int32
      return 0 unless layer = @state.terrain_layer

      changed = 0
      @state.hexes_in_radius(hex[0], hex[1]).each do |coords|
        changed += 1 if layer.set_fill(coords[0], coords[1], layer.accent)
      end
      changed
    end

    private def clear_fill(hex : Tuple(Int32, Int32)) : Int32
      return 0 unless layer = @state.terrain_layer

      changed = 0
      @state.hexes_in_radius(hex[0], hex[1]).each do |coords|
        changed += 1 if layer.clear_fill(coords[0], coords[1])
      end
      changed
    end

    private def paint_hexside(edge : Tuple(Int32, Int32, Int32, Int32)) : Int32
      object = @state.create_hexside(edge[0], edge[1], edge[2], edge[3])
      return 0 unless object

      @last_hexside_drag_edge = object.edge_key
      1
    end

    private def clear_hexside(edge : Tuple(Int32, Int32, Int32, Int32)) : Int32
      object = hexside_object_for_edge(edge)
      layer = @state.hexside_layer
      return 0 unless object && layer

      removed = layer.remove_hexside(object)
      return 0 unless removed

      @state.clear_hexside_selection if @state.selected_hexside_object == object
      @last_hexside_drag_edge = edge
      1
    end

    private def append_freeform_draw_point(world : Qt6::PointF, force : Bool = false) : Nil
      point = {world.x.to_f64, world.y.to_f64}

      if last = @freeform_draw_points.last?
        dx = point[0] - last[0]
        dy = point[1] - last[1]
        return if !force && Math.sqrt(dx * dx + dy * dy) < MIN_FREEFORM_POINT_DISTANCE
      end

      @freeform_draw_points << point
    end

    private def append_sketch_draw_point(world : Qt6::PointF, force : Bool = false) : Nil
      point = {world.x.to_f64, world.y.to_f64}

      if last = @sketch_draw_points.last?
        dx = point[0] - last[0]
        dy = point[1] - last[1]
        return if !force && Math.sqrt(dx * dx + dy * dy) < MIN_FREEFORM_POINT_DISTANCE
      end

      @sketch_draw_points << point
    end

    private def snapped_sketch_world_point(world : Qt6::PointF, allow_snap : Bool = true) : Qt6::PointF
      return world unless allow_snap && @state.sketch_snap_to_grid

      @state.snap_sketch_world_point(world)
    end

    private def snapped_selected_sketch_world_point(world : Qt6::PointF) : Qt6::PointF
      return world unless @state.sketch_snap_to_grid

      @state.snap_sketch_world_point(world)
    end

    private def begin_sketch_move_interaction(object : SketchObject, position : Qt6::PointF) : Bool
      @drag_sketch_object = object
      @drag_mode = "sketch_move"
      @sketch_move_points = object.points.map { |point| {point[0], point[1]} }
      center_x, center_y = object.center
      current_world = @state.screen_to_world(position)
      @sketch_move_center = {center_x, center_y}
      @sketch_move_pointer_offset = {
        current_world.x.to_f64 - center_x,
        current_world.y.to_f64 - center_y,
      }
      true
    end

    private def apply_sketch_move(sketch_object : SketchObject, current_world : Qt6::PointF) : Nil
      return unless original_center = @sketch_move_center
      return unless pointer_offset = @sketch_move_pointer_offset
      return if @sketch_move_points.empty?

      desired_center = Qt6::PointF.new(
        current_world.x - pointer_offset[0],
        current_world.y - pointer_offset[1]
      )
      snapped_center = snapped_selected_sketch_world_point(desired_center)
      delta_x = snapped_center.x.to_f64 - original_center[0]
      delta_y = snapped_center.y.to_f64 - original_center[1]

      sketch_object.points = @sketch_move_points.map do |point|
        {point[0] + delta_x, point[1] + delta_y}
      end
    end

    private def start_sketch_handle_interaction(position : Qt6::PointF, object : SketchObject) : Bool
      handle = screen_point(object.rotation_handle(SKETCH_ROTATE_HANDLE_OFFSET / @state.zoom))
      if handle_hit?(position, handle, SKETCH_HANDLE_HIT_RADIUS)
        current_world = @state.screen_to_world(position)
        @drag_sketch_object = object
        @drag_mode = "sketch_rotate"
        @sketch_rotate_initial = object.rotation
        @sketch_rotate_initial_angle = object.rotation_angle_for({current_world.x.to_f64, current_world.y.to_f64})
        return true
      end

      corners = object.selection_corners
      corners.each_with_index do |corner, index|
        corner_screen = screen_point(corner)
        next unless handle_hit?(position, corner_screen, SKETCH_HANDLE_HIT_RADIUS)

        @drag_sketch_object = object
        @drag_mode = "sketch_resize"
        @sketch_resize_anchor = corners[(index + 2) % 4]
        @sketch_resize_points = object.points.map { |point| {point[0], point[1]} }
        @sketch_resize_radius = object.radius
        @sketch_resize_rx = object.rx
        @sketch_resize_ry = object.ry
        return true
      end

      false
    end

    private def draw_pending_sketch_preview(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Sketch"
      return unless preview = build_pending_sketch_preview_object

      painter.save
      preview.paint(painter, @state, 0.72)
      preview.draw_selection(painter, @state, @state.active_layer.accent)
      painter.restore
    end

    private def draw_selected_sketch_handles(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Sketch"
      return unless object = (@state.selected_sketch_object if @state.selected_sketch_present?)

      corners = object.selection_corners.map { |point| screen_point(point) }
      return if corners.empty?

      painter.save
      accent = Qt6::Color.new(0, 120, 255)
      handle_pen = Qt6::QPen.new(accent, 1.5)
      line_pen = Qt6::QPen.new(accent, 1.0)
      painter.pen = handle_pen
      painter.brush = Qt6::Color.new(255, 255, 255)

      corners.each do |corner|
        painter.draw_rect(Qt6::RectF.new(
          corner.x - SKETCH_HANDLE_SIZE,
          corner.y - SKETCH_HANDLE_SIZE,
          SKETCH_HANDLE_SIZE * 2.0,
          SKETCH_HANDLE_SIZE * 2.0,
        ))
      end

      rotation_handle = screen_point(object.rotation_handle(SKETCH_ROTATE_HANDLE_OFFSET / @state.zoom))
      top_mid = Qt6::PointF.new(
        (corners[0].x + corners[1].x) / 2.0,
        (corners[0].y + corners[1].y) / 2.0,
      )
      painter.pen = line_pen
      painter.draw_line(top_mid, rotation_handle)
      painter.pen = handle_pen
      painter.brush = Qt6::Color.new(0, 200, 0)
      painter.draw_ellipse(
        Qt6::RectF.new(
          rotation_handle.x - SKETCH_HANDLE_SIZE,
          rotation_handle.y - SKETCH_HANDLE_SIZE,
          SKETCH_HANDLE_SIZE * 2.0,
          SKETCH_HANDLE_SIZE * 2.0,
        )
      )
      painter.restore
    end

    private def build_pending_sketch_preview_object : SketchObject?
      if @drag_mode == "sketch_freehand_pending" || @drag_mode == "sketch_freehand_draw"
        return nil if @sketch_draw_points.size < 2

        object = build_preview_sketch_object("freehand", @sketch_draw_points.dup)
        object.closed = @state.sketch_freehand_closed && @sketch_draw_points.size >= 3
        return object
      end

      return nil unless @drag_mode == "sketch_pending" || @drag_mode == "sketch_draw"
      return nil unless start_point = @sketch_preview_start
      return nil unless end_point = @sketch_preview_end

      delta_x = end_point.x.to_f64 - start_point.x.to_f64
      delta_y = end_point.y.to_f64 - start_point.y.to_f64
      distance = Math.sqrt(delta_x * delta_x + delta_y * delta_y)

      case @state.sketch_shape_type
      when "line"
        return nil if distance < 1.0

        build_preview_sketch_object("line", [
          {start_point.x.to_f64, start_point.y.to_f64},
          {end_point.x.to_f64, end_point.y.to_f64},
        ])
      when "polygon"
        return nil if distance < 1.0

        object = build_preview_sketch_object("polygon", [{start_point.x.to_f64, start_point.y.to_f64}])
        object.radius = distance
        object.num_sides = @state.sketch_polygon_sides
        object
      when "ellipse"
        width = delta_x.abs
        height = delta_y.abs
        center_x = (start_point.x.to_f64 + end_point.x.to_f64) / 2.0
        center_y = (start_point.y.to_f64 + end_point.y.to_f64) / 2.0
        radius_x = width / 2.0
        radius_y = height / 2.0

        if @state.sketch_perfect_circle
          radius = {radius_x, radius_y}.min
          return nil if radius < 1.0

          object = build_preview_sketch_object("ellipse", [{center_x, center_y}])
          object.rx = radius
          object.ry = radius
          object
        else
          return nil if radius_x < 1.0 || radius_y < 1.0

          object = build_preview_sketch_object("ellipse", [{center_x, center_y}])
          object.rx = radius_x
          object.ry = radius_y
          object
        end
      else
        return nil if delta_x.abs < 1.0 || delta_y.abs < 1.0

        build_preview_sketch_object("rect", [
          {start_point.x.to_f64, start_point.y.to_f64},
          {end_point.x.to_f64, end_point.y.to_f64},
        ])
      end
    end

    private def build_preview_sketch_object(
      shape_type : String,
      points : Array(Tuple(Float64, Float64))
    ) : SketchObject
      layer = @state.sketch_layer
      style_source = @state.selected_sketch_object if @state.selected_sketch_present?
      accent = layer ? layer.accent : @state.active_layer.accent

      SketchObject.new(
        shape_type: shape_type,
        points: points,
        num_sides: @state.sketch_polygon_sides,
        stroke_color: style_source ? style_source.stroke_color : accent,
        stroke_width: style_source ? style_source.stroke_width : 2.0,
        stroke_type: style_source ? style_source.stroke_type : "solid",
        dash_length: style_source ? style_source.dash_length : 8.0,
        gap_length: style_source ? style_source.gap_length : 4.0,
        stroke_cap: style_source ? style_source.stroke_cap : "round",
        fill_enabled: style_source ? style_source.fill_enabled : false,
        fill_color: style_source ? style_source.fill_color : accent,
        fill_opacity: style_source ? style_source.fill_opacity : 0.25,
        fill_type: style_source ? style_source.fill_type : "color",
        fill_texture_id: style_source ? style_source.fill_texture_id : "",
        fill_texture_zoom: style_source ? style_source.fill_texture_zoom : 1.0,
        fill_texture_rotation: style_source ? style_source.fill_texture_rotation : 0.0,
        rotation: style_source ? style_source.rotation : 0.0,
        draw_over_grid: style_source ? style_source.draw_over_grid : false,
      )
    end

    private def screen_point(point : Tuple(Float64, Float64)) : Qt6::PointF
      @state.screen_point(Qt6::PointF.new(point[0], point[1]))
    end

    private def handle_hit?(position : Qt6::PointF, target : Qt6::PointF, radius : Float64) : Bool
      dx = position.x - target.x
      dy = position.y - target.y
      dx * dx + dy * dy <= radius * radius
    end

    private def draw_hovered_path_endpoint(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Path"
      return unless endpoint = @hovered_path_endpoint
      return unless object = (@state.selected_path_object if @state.selected_path_present?)

      handle_center = case endpoint
                      when "start"
                        @state.screen_point(@state.hex_center(object.col_a, object.row_a))
                      when "end"
                        @state.screen_point(@state.hex_center(object.col_b, object.row_b))
                      else
                        return
                      end

      painter.save
      painter.pen = Qt6::QPen.new(Qt6::Color.new(255, 248, 220), 3.0)
      painter.brush = Qt6::Color.new(224, 168, 64)
      painter.opacity = 0.95
      painter.draw_ellipse(Qt6::RectF.new(handle_center.x - 7.0, handle_center.y - 7.0, 14.0, 14.0))
      painter.restore
    end

    private def draw_hovered_border_edge(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Border"
      return unless edge = @hovered_border_edge
      shared = @state.shared_edge_points(edge[0], edge[1], edge[2], edge[3])
      return unless shared

      style_source = @state.selected_border_object if @state.selected_border_present?
      start_point = @state.screen_point(shared[0])
      end_point = @state.screen_point(shared[1])
      color = style_source ? style_source.color : @state.active_layer.accent
      width = style_source ? style_source.width : 3.0
      line_type = style_source ? style_source.line_type : "solid"
      pen = Qt6::QPen.new(color, width)
      pen.style = case line_type
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
      painter.opacity = border_object_for_edge(edge) ? 0.85 : 0.6
      painter.draw_line(start_point, end_point)
      painter.restore
    end

    private def draw_hovered_hexside_edge(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Hexside"
      return unless edge = @hovered_hexside_edge
      shared = @state.shared_edge_points(edge[0], edge[1], edge[2], edge[3])
      return unless shared

      style_source = @state.selected_hexside_object if @state.selected_hexside_present?
      start_point = @state.screen_point(shared[0])
      end_point = @state.screen_point(shared[1])
      color = style_source ? style_source.color : @state.active_layer.accent
      width = style_source ? style_source.width : 4.0
      pen = Qt6::QPen.new(color, width)
      pen.cap_style = Qt6::PenCapStyle::RoundCap

      painter.save
      painter.pen = pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = hexside_object_for_edge(edge) ? 0.88 : 0.62
      painter.draw_line(start_point, end_point)
      painter.restore
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
          if @state.neighboring_hexes?(anchor[0], anchor[1], hover[0], hover[1])
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
      end

      painter.restore
    end

    private def draw_pending_freeform_preview(painter : Qt6::QPainter) : Nil
      return unless @state.active_tool == "Freeform"
      return if @freeform_draw_points.size < 2

      style_source = @state.selected_freeform_path_object if @state.selected_freeform_path_present?
      pen = Qt6::QPen.new(style_source ? style_source.color : @state.active_layer.accent, style_source ? style_source.width : 3.0)
      pen.cap_style = Qt6::PenCapStyle::RoundCap
      pen.join_style = Qt6::PenJoinStyle::RoundJoin

      painter.save
      painter.pen = pen
      painter.brush = Qt6::Color.new(0, 0, 0, 0)
      painter.opacity = style_source ? style_source.opacity.clamp(0.0, 1.0) : 0.78
      (@freeform_draw_points.size - 1).times do |index|
        start_point = @state.screen_point(Qt6::PointF.new(@freeform_draw_points[index][0], @freeform_draw_points[index][1]))
        end_point = @state.screen_point(Qt6::PointF.new(@freeform_draw_points[index + 1][0], @freeform_draw_points[index + 1][1]))
        painter.draw_line(start_point, end_point)
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

    private def update_hovered_border_edge(position : Qt6::PointF) : Nil
      @hovered_border_edge = nil
      return unless @state.active_tool == "Border"
      return unless hover = @state.hover_hex

      best = nil
      best_distance = 12.0

      @state.adjacent_hexes(hover[0], hover[1]).each do |neighbor|
        shared = @state.shared_edge_points(hover[0], hover[1], neighbor[0], neighbor[1])
        next unless shared

        start_point = @state.screen_point(shared[0])
        end_point = @state.screen_point(shared[1])
        distance = distance_to_segment(position, start_point, end_point)
        next unless distance <= best_distance

        best_distance = distance
        best = BorderObject.new(hover[0], hover[1], neighbor[0], neighbor[1]).edge_key
      end

      @hovered_border_edge = best
    end

    private def update_hovered_hexside_edge(position : Qt6::PointF) : Nil
      @hovered_hexside_edge = nil
      return unless @state.active_tool == "Hexside"
      return unless hover = @state.hover_hex

      best = nil
      best_distance = 12.0

      @state.adjacent_hexes(hover[0], hover[1]).each do |neighbor|
        shared = @state.shared_edge_points(hover[0], hover[1], neighbor[0], neighbor[1])
        next unless shared

        start_point = @state.screen_point(shared[0])
        end_point = @state.screen_point(shared[1])
        distance = distance_to_segment(position, start_point, end_point)
        next unless distance <= best_distance

        best_distance = distance
        best = HexsideObject.new(hover[0], hover[1], neighbor[0], neighbor[1]).edge_key
      end

      @hovered_hexside_edge = best
    end

    private def border_object_for_edge(edge : Tuple(Int32, Int32, Int32, Int32)) : BorderObject?
      layer = @state.border_layer
      return nil unless layer

      layer.border_at(edge[0], edge[1], edge[2], edge[3])
    end

    private def hexside_object_for_edge(edge : Tuple(Int32, Int32, Int32, Int32)) : HexsideObject?
      layer = @state.hexside_layer
      return nil unless layer

      layer.hexside_at(edge[0], edge[1], edge[2], edge[3])
    end

    private def edge_label(edge : Tuple(Int32, Int32, Int32, Int32)) : String
      "#{@state.hex_label(edge[0], edge[1])}-#{@state.hex_label(edge[2], edge[3])}"
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
end
