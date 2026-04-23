require "qt6"
require "./map_state"
require "./map_canvas"

module WargameMapToolCrystal
  APP_STYLE = <<-CSS
    QWidget { font-family: "Avenir Next"; font-size: 13px; color: rgb(52, 48, 42); }
    QMainWindow { background: rgb(244, 240, 232); }
    QDockWidget { background: rgb(242, 236, 226); }
    QDockWidget::title {
      background: rgb(228, 220, 208);
      color: rgb(64, 58, 50);
      padding: 8px 10px;
      border-bottom: 1px solid rgb(204, 196, 184);
    }
    QStatusBar {
      background: rgb(232, 225, 214);
      color: rgb(72, 66, 58);
      border-top: 1px solid rgb(206, 198, 188);
    }
    QToolBar {
      background: rgb(236, 229, 218);
      border-bottom: 1px solid rgb(206, 198, 188);
      spacing: 4px;
      padding: 4px 6px;
    }
    QToolBar QToolButton {
      color: rgb(52, 48, 42);
      background: rgb(230, 224, 214);
      border: 1px solid rgb(199, 192, 182);
      padding: 6px 10px;
    }
    QToolBar QToolButton:checked {
      background: rgb(205, 218, 225);
      border-color: rgb(120, 140, 152);
    }
    QMenuBar {
      background: rgb(236, 229, 218);
      color: rgb(54, 50, 44);
    }
    QMenu {
      background: rgb(252, 249, 244);
      color: rgb(44, 42, 37);
      border: 1px solid rgb(206, 198, 188);
    }
    QMenu::item:selected {
      background: rgb(101, 122, 170);
      color: rgb(255, 255, 255);
    }
    QTreeView, QAbstractItemView {
      background: rgb(251, 248, 243);
      alternate-background-color: rgb(244, 239, 232);
      border: 1px solid rgb(208, 201, 191);
      selection-background-color: rgb(97, 118, 166);
      selection-color: rgb(255, 255, 255);
    }
    QHeaderView::section {
      background: rgb(228, 221, 211);
      color: rgb(72, 66, 60);
      border: none;
      border-right: 1px solid rgb(206, 198, 186);
      border-bottom: 1px solid rgb(206, 198, 186);
      padding: 6px 8px;
    }
    QCheckBox, QLabel {
      color: rgb(74, 68, 62);
    }
  CSS

  class MainWindow
    getter widget : Qt6::MainWindow

    @grid_action : Qt6::Action
    @coords_action : Qt6::Action
    @asset_action : Qt6::Action
    @layer_model : Qt6::StandardItemModel
    @layer_tree : Qt6::TreeView
    @layer_selection : Qt6::ItemSelectionModel
    @active_layer_label : Qt6::Label
    @active_tool_label : Qt6::Label
    @project_label : Qt6::Label
    @hover_label : Qt6::Label
    @layer_visible_check : Qt6::CheckBox
    @selection_note : Qt6::Label
    @updating_panel : Bool

    def initialize
      @state = MapState.new
      @widget = Qt6::MainWindow.new
      @widget.window_title = "Wargame Map Tool Crystal"
      @widget.resize(1360, 860)
      @grid_action = Qt6::Action.new("Show Grid", @widget)
      @coords_action = Qt6::Action.new("Show Coordinates", @widget)
      @asset_action = Qt6::Action.new("Show Counters", @widget)
      @layer_model = Qt6::StandardItemModel.new(@widget)
      @layer_tree = Qt6::TreeView.new
      @layer_selection = Qt6::ItemSelectionModel.new(@layer_model, @widget)
      @active_layer_label = Qt6::Label.new
      @active_tool_label = Qt6::Label.new
      @project_label = Qt6::Label.new
      @hover_label = Qt6::Label.new
      @layer_visible_check = Qt6::CheckBox.new("Visible")
      @selection_note = Qt6::Label.new
      @updating_panel = false

      @status_bar = @widget.status_bar
      @status_bar.show_message("Preparing Crystal port slice")

      @canvas = MapCanvas.new(
        @state,
        ->(message : String) { handle_status(message) },
        ->(message : String) { @hover_label.text = message }
      )
      @widget.central_widget = @canvas.widget

      build_file_actions
      build_tool_bar
      build_layer_dock
      build_inspector_dock
      apply_icon
      refresh_layer_model
      refresh_inspector
      @layer_tree.current_index = @layer_model.index(@state.active_layer_index, 0)
      @status_bar.show_message("Crystal port slice ready")
    end

    def show : Nil
      @widget.show_maximized
    end

    private def build_file_actions : Nil
      file_menu = @widget.menu_bar.add_menu("File")
      view_menu = @widget.menu_bar.add_menu("View")
      help_menu = @widget.menu_bar.add_menu("Help")

      open_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Hexmap Files (*.hexmap *.json *.yaml);;All Files (*)")
      open_dialog.window_title = "Select Existing Map Data"
      open_dialog.accept_mode = Qt6::FileDialogAcceptMode::Open
      open_dialog.file_mode = Qt6::FileDialogFileMode::ExistingFile

      export_dialog = Qt6::FileDialog.new(@widget, Dir.current, "PNG Images (*.png);;All Files (*)")
      export_dialog.window_title = "Export Crystal Port Preview"
      export_dialog.accept_mode = Qt6::FileDialogAcceptMode::Save
      export_dialog.file_mode = Qt6::FileDialogFileMode::AnyFile

      new_action = Qt6::Action.new("New Port Slice", @widget)
      new_action.shortcut = "Ctrl+N"
      new_action.on_triggered do
        @state.reset
        refresh_all("Started a new Crystal prototype map")
      end

      open_action = Qt6::Action.new("Open Source Map…", @widget)
      open_action.shortcut = "Ctrl+O"
      open_action.on_triggered do
        if open_dialog.exec == Qt6::DialogCode::Accepted
          selected = open_dialog.selected_file
          @state.project_path = selected.empty? ? nil : selected
          refresh_inspector
          handle_status(selected.empty? ? "Open canceled" : "Selected #{File.basename(selected)} for future import work")
        else
          handle_status("Open canceled")
        end
      end

      export_action = Qt6::Action.new("Export PNG…", @widget)
      export_action.shortcut = "Ctrl+Shift+E"
      export_action.on_triggered do
        suggested = @state.project_path ? File.join(File.dirname(@state.project_path.not_nil!), "wargame-map-tool-crystal-preview.png") : File.join(Dir.current, "wargame-map-tool-crystal-preview.png")
        export_dialog.select_file(suggested)

        if export_dialog.exec == Qt6::DialogCode::Accepted
          output = export_dialog.selected_file
          output = "#{output}.png" unless output.downcase.ends_with?(".png")

          if @canvas.widget.grab.save(output)
            handle_status("Exported #{File.basename(output)}")
          else
            handle_status("PNG export failed")
          end
        else
          handle_status("Export canceled")
        end
      end

      quit_action = Qt6::Action.new("Quit", @widget)
      quit_action.shortcut = "Ctrl+Q"
      quit_action.on_triggered do
        Qt6.application.quit
      end

      reset_view_action = Qt6::Action.new("Reset View", @widget)
      reset_view_action.shortcut = "Ctrl+0"
      reset_view_action.on_triggered do
        @state.reset_view
        @canvas.refresh("View reset")
      end

      @grid_action.checkable = true
      @grid_action.checked = @state.show_grid
      @grid_action.on_toggled do |checked|
        @state.show_grid = checked
        @canvas.refresh(checked ? "Grid shown" : "Grid hidden")
      end

      @coords_action.checkable = true
      @coords_action.checked = @state.show_coordinates
      @coords_action.on_toggled do |checked|
        @state.show_coordinates = checked
        @canvas.refresh(checked ? "Hex labels shown" : "Hex labels hidden")
      end

      @asset_action.checkable = true
      @asset_action.checked = @state.show_assets
      @asset_action.on_toggled do |checked|
        @state.show_assets = checked
        @canvas.refresh(checked ? "Counters shown" : "Counters hidden")
      end

      about_action = Qt6::Action.new("Port Status", @widget)
      about_action.shortcut = "Ctrl+,"
      about_action.on_triggered do
        Qt6::MessageBox.information(
          @widget,
          title: "Crystal Port Status",
          text: "This is a real vertical slice, not a full rewrite of the Python application.",
          informative_text: "It covers the main-window shell, dock widgets, tool actions, a custom pan/zoom canvas, a layer browser, and PNG export. Project I/O, advanced paint tools, and most dialogs remain to be ported."
        )
      end

      file_menu << new_action
      file_menu << open_action
      file_menu << export_action
      file_menu.add_separator
      file_menu << quit_action

      view_menu << reset_view_action
      view_menu << @grid_action
      view_menu << @coords_action
      view_menu << @asset_action

      help_menu << about_action
    end

    private def build_tool_bar : Nil
      toolbar = Qt6::ToolBar.new("Tools", @widget)
      tool_group = Qt6::ActionGroup.new(@widget)
      tool_group.exclusive = true

      MapState::TOOL_NAMES.each do |tool_name|
        action = Qt6::Action.new(tool_name, @widget)
        action.checkable = true
        action.checked = tool_name == @state.active_tool
        action.on_triggered do
          @state.active_tool = tool_name
          refresh_inspector
          @canvas.refresh("#{tool_name} tool active")
        end
        tool_group << action
        toolbar << action
      end

      toolbar << @grid_action
      toolbar << @coords_action
      toolbar << @asset_action
      @widget.add_tool_bar(toolbar)
    end

    private def build_layer_dock : Nil
      @layer_model.set_horizontal_header_label(0, "Layer")
      @layer_model.set_horizontal_header_label(1, "Kind")
      @layer_model.set_horizontal_header_label(2, "State")

      @layer_tree.model = @layer_model
      @layer_tree.selection_model = @layer_selection
      @layer_tree.alternating_row_colors = true
      @layer_tree.root_is_decorated = false
      @layer_tree.uniform_row_heights = true
      @layer_tree.expand_all

      @layer_selection.on_current_index_changed do
        current = @layer_selection.current_index
        next unless current.valid?

        @state.set_active_layer(current.row)
        refresh_inspector
        @canvas.refresh("Active layer #{@state.active_layer.name}")
      end

      panel = Qt6::Widget.new
      panel.vbox do |column|
        column << Qt6::Label.new("Python parity target: layer stack + inspector sync")
        column << @layer_tree
      end

      dock = Qt6::DockWidget.new("Layers", @widget)
      dock.widget = panel
      @widget.add_dock_widget(dock, Qt6::DockArea::Left)
    end

    private def build_inspector_dock : Nil
      @layer_visible_check.on_toggled do |checked|
        next if @updating_panel

        @state.active_layer_visible = checked
        refresh_layer_model
        @canvas.refresh(checked ? "Layer enabled" : "Layer hidden")
      end

      summary = Qt6::Label.new("Scope: shell, toolbar, layers, pan/zoom canvas, and PNG export. Remaining Python dialogs and full project serialization are still ahead.")

      panel = Qt6::Widget.new
      panel.vbox do |column|
        column << Qt6::Label.new("Crystal Port Inspector")
        column << @project_label
        column << @active_tool_label
        column << @active_layer_label
        column << @hover_label
        column << @layer_visible_check
        column << @selection_note
        column << summary
      end

      dock = Qt6::DockWidget.new("Inspector", @widget)
      dock.widget = panel
      @widget.add_dock_widget(dock, Qt6::DockArea::Right)
    end

    private def refresh_all(message : String) : Nil
      refresh_layer_model
      refresh_inspector
      @layer_tree.current_index = @layer_model.index(@state.active_layer_index, 0)
      @canvas.refresh(message)
    end

    private def refresh_layer_model : Nil
      @state.layers.each_with_index do |layer, row|
        layer_item = Qt6::StandardItem.new(layer.name)
        layer_item.set_data(layer.accent, Qt6::ItemDataRole::Foreground)
        kind_item = Qt6::StandardItem.new(layer.kind)
        state_item = Qt6::StandardItem.new(layer.visible ? "Visible" : "Hidden")
        @layer_model.set_item(row, 0, layer_item)
        @layer_model.set_item(row, 1, kind_item)
        @layer_model.set_item(row, 2, state_item)
      end
    end

    private def refresh_inspector : Nil
      @updating_panel = true
      @project_label.text = if path = @state.project_path
                              "Source: #{File.basename(path)}"
                            else
                              "Source: unsaved Crystal prototype"
                            end
      @active_tool_label.text = "Active tool: #{@state.active_tool}"
      @active_layer_label.text = "Active layer: #{@state.active_layer.name}"
      @hover_label.text = if hover = @state.hover_hex
                            "Hover: #{@state.hex_label(hover[0], hover[1])}"
                          else
                            "Hover: outside map"
                          end
      @layer_visible_check.checked = @state.active_layer.visible
      @selection_note.text = "Selected #{@state.active_layer.kind.downcase} layer at #{@state.zoom.round(2)}x. The current slice proves the shell and canvas workflow before porting project I/O and tool-specific commands."
      @updating_panel = false
    end

    private def handle_status(message : String) : Nil
      @status_bar.show_message(message, 1800)
      refresh_inspector
    end

    private def apply_icon : Nil
      icon_path = File.expand_path("../../assets/icon.ico", __DIR__)
      return unless File.exists?(icon_path)

      icon = Qt6::QIcon.from_file(icon_path)
      Qt6.application.window_icon = icon
      @widget.window_icon = icon
    end
  end
end