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
    @show_layers_action : Qt6::Action
    @show_inspector_action : Qt6::Action
    @layers_dock : Qt6::DockWidget?
    @inspector_dock : Qt6::DockWidget?
    @layer_model : Qt6::StandardItemModel
    @layer_tree : Qt6::TreeView
    @layer_selection : Qt6::ItemSelectionModel
    @active_layer_label : Qt6::Label
    @active_tool_label : Qt6::Label
    @project_label : Qt6::Label
    @source_label : Qt6::Label
    @background_label : Qt6::Label
    @terrain_fill_label : Qt6::Label
    @path_label : Qt6::Label
    @asset_label : Qt6::Label
    @asset_path_label : Qt6::Label
    @hover_label : Qt6::Label
    @layer_visible_check : Qt6::CheckBox
    @selection_note : Qt6::Label
    @path_width_spin : Qt6::DoubleSpinBox
    @path_line_type_combo : Qt6::ComboBox
    @path_color_button : Qt6::PushButton
    @path_opacity_spin : Qt6::DoubleSpinBox
    @asset_snap_check : Qt6::CheckBox
    @asset_scale_spin : Qt6::DoubleSpinBox
    @asset_rotation_spin : Qt6::DoubleSpinBox
    @asset_opacity_spin : Qt6::DoubleSpinBox
    @text_value_edit : Qt6::LineEdit
    @text_font_size_spin : Qt6::SpinBox
    @text_bold_check : Qt6::CheckBox
    @text_italic_check : Qt6::CheckBox
    @text_alignment_combo : Qt6::ComboBox
    @text_color_button : Qt6::PushButton
    @text_opacity_spin : Qt6::DoubleSpinBox
    @text_rotation_spin : Qt6::DoubleSpinBox
    @background_offset_x_spin : Qt6::DoubleSpinBox
    @background_offset_y_spin : Qt6::DoubleSpinBox
    @background_scale_spin : Qt6::DoubleSpinBox
    @terrain_radius_spin : Qt6::SpinBox
    @terrain_color_button : Qt6::PushButton
    @terrain_preset_buttons : Array(Qt6::PushButton)
    @updating_panel : Bool

    def initialize
      @state = MapState.new
      @widget = Qt6::MainWindow.new
      @widget.window_title = "Wargame Map Tool Crystal"
      @widget.resize(1360, 860)
      @grid_action = Qt6::Action.new("Show Grid", @widget)
      @coords_action = Qt6::Action.new("Show Coordinates", @widget)
      @asset_action = Qt6::Action.new("Show Counters", @widget)
      @show_layers_action = Qt6::Action.new("Show Layers", @widget)
      @show_inspector_action = Qt6::Action.new("Show Inspector", @widget)
      @layers_dock = nil
      @inspector_dock = nil
      @layer_model = Qt6::StandardItemModel.new(@widget)
      @layer_tree = Qt6::TreeView.new
      @layer_selection = Qt6::ItemSelectionModel.new(@layer_model, @widget)
      @active_layer_label = Qt6::Label.new
      @active_tool_label = Qt6::Label.new
      @project_label = Qt6::Label.new
      @source_label = Qt6::Label.new
      @background_label = Qt6::Label.new
      @terrain_fill_label = Qt6::Label.new
      @path_label = Qt6::Label.new
      @asset_label = Qt6::Label.new
      @asset_path_label = Qt6::Label.new
      @hover_label = Qt6::Label.new
      @layer_visible_check = Qt6::CheckBox.new("Visible")
      @selection_note = Qt6::Label.new
      @path_width_spin = Qt6::DoubleSpinBox.new
      @path_line_type_combo = Qt6::ComboBox.new
      @path_color_button = Qt6::PushButton.new("Path Color")
      @path_opacity_spin = Qt6::DoubleSpinBox.new
      @asset_snap_check = Qt6::CheckBox.new("Snap To Hex")
      @asset_scale_spin = Qt6::DoubleSpinBox.new
      @asset_rotation_spin = Qt6::DoubleSpinBox.new
      @asset_opacity_spin = Qt6::DoubleSpinBox.new
      @text_value_edit = Qt6::LineEdit.new
      @text_font_size_spin = Qt6::SpinBox.new
      @text_bold_check = Qt6::CheckBox.new("Bold")
      @text_italic_check = Qt6::CheckBox.new("Italic")
      @text_alignment_combo = Qt6::ComboBox.new
      @text_color_button = Qt6::PushButton.new("Text Color")
      @text_opacity_spin = Qt6::DoubleSpinBox.new
      @text_rotation_spin = Qt6::DoubleSpinBox.new
      @background_offset_x_spin = Qt6::DoubleSpinBox.new
      @background_offset_y_spin = Qt6::DoubleSpinBox.new
      @background_scale_spin = Qt6::DoubleSpinBox.new
      @terrain_radius_spin = Qt6::SpinBox.new
      @terrain_color_button = Qt6::PushButton.new("Fill Color")
      @terrain_preset_buttons = build_terrain_preset_buttons
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
      edit_menu = @widget.menu_bar.add_menu("Edit")
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

      slice_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Crystal Slice (*.wmtc.json *.json);;All Files (*)")
      slice_dialog.window_title = "Open Crystal Port Slice"
      slice_dialog.accept_mode = Qt6::FileDialogAcceptMode::Open
      slice_dialog.file_mode = Qt6::FileDialogFileMode::ExistingFile

      save_slice_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Crystal Slice (*.wmtc.json *.json);;All Files (*)")
      save_slice_dialog.window_title = "Save Crystal Port Slice"
      save_slice_dialog.accept_mode = Qt6::FileDialogAcceptMode::Save
      save_slice_dialog.file_mode = Qt6::FileDialogFileMode::AnyFile

      background_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp);;All Files (*)")
      background_dialog.window_title = "Import Background Image"
      background_dialog.accept_mode = Qt6::FileDialogAcceptMode::Open
      background_dialog.file_mode = Qt6::FileDialogFileMode::ExistingFile

      asset_image_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp);;All Files (*)")
      asset_image_dialog.window_title = "Replace Asset Image"
      asset_image_dialog.accept_mode = Qt6::FileDialogAcceptMode::Open
      asset_image_dialog.file_mode = Qt6::FileDialogFileMode::ExistingFile

      add_asset_dialog = Qt6::FileDialog.new(@widget, Dir.current, "Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp);;All Files (*)")
      add_asset_dialog.window_title = "Add Asset Image"
      add_asset_dialog.accept_mode = Qt6::FileDialogAcceptMode::Open
      add_asset_dialog.file_mode = Qt6::FileDialogFileMode::ExistingFile

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
          @state.source_path = selected.empty? ? nil : selected
          refresh_inspector
          handle_status(selected.empty? ? "Open canceled" : "Selected #{File.basename(selected)} for future import work")
        else
          handle_status("Open canceled")
        end
      end

      open_slice_action = Qt6::Action.new("Open Crystal Slice…", @widget)
      open_slice_action.shortcut = "Ctrl+Shift+O"
      open_slice_action.on_triggered do
        if slice_dialog.exec == Qt6::DialogCode::Accepted
          selected = slice_dialog.selected_file

          if !selected.empty? && @state.load_slice(selected)
            refresh_all("Opened #{File.basename(selected)}")
          else
            handle_status(selected.empty? ? "Open canceled" : "Crystal slice open failed")
          end
        else
          handle_status("Open canceled")
        end
      end

      export_action = Qt6::Action.new("Export PNG…", @widget)
      export_action.shortcut = "Ctrl+Shift+E"
      export_action.on_triggered do
        suggested = if @state.project_path
                      File.join(File.dirname(@state.project_path.not_nil!), "wargame-map-tool-crystal-preview.png")
                    elsif @state.source_path
                      File.join(File.dirname(@state.source_path.not_nil!), "wargame-map-tool-crystal-preview.png")
                    else
                      File.join(Dir.current, "wargame-map-tool-crystal-preview.png")
                    end
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

      save_slice_action = Qt6::Action.new("Save Crystal Slice…", @widget)
      save_slice_action.shortcut = "Ctrl+Shift+S"
      save_slice_action.on_triggered do
        suggested = @state.project_path || File.join(Dir.current, "wargame-map-tool-slice.wmtc.json")
        save_slice_dialog.select_file(suggested)

        if save_slice_dialog.exec == Qt6::DialogCode::Accepted
          output = save_slice_dialog.selected_file
          if output.empty?
            handle_status("Save canceled")
          else
            output = "#{output}.wmtc.json" unless output.downcase.ends_with?(".json")
            begin
              @state.save_slice(output)
              refresh_inspector
              handle_status("Saved #{File.basename(output)}")
            rescue
              handle_status("Crystal slice save failed")
            end
          end
        else
          handle_status("Save canceled")
        end
      end

      import_background_action = Qt6::Action.new("Import Background Image…", @widget)
      import_background_action.shortcut = "Ctrl+Shift+B"
      import_background_action.on_triggered do
        if background_dialog.exec == Qt6::DialogCode::Accepted
          selected = background_dialog.selected_file
          layer = @state.background_layer

          if !selected.empty? && layer && layer.load_image(selected)
            refresh_inspector
            @canvas.refresh("Loaded background #{File.basename(selected)}")
          else
            handle_status(selected.empty? ? "Background import canceled" : "Background import failed")
          end
        else
          handle_status("Background import canceled")
        end
      end

      add_text_action = Qt6::Action.new("Add Text Label…", @widget)
      add_text_action.shortcut = "Ctrl+Shift+T"
      add_text_action.on_triggered do
        suggested = if hover = @state.hover_hex
                      @state.hex_label(hover[0], hover[1])
                    else
                      "New label"
                    end
        value = Qt6::InputDialog.get_text(@widget, title: "Add Text Label", label: "Label text:", value: suggested)

        if value && @state.add_text_label(value)
          if index = @state.text_layer_index
            @state.set_active_layer(index)
            @layer_tree.current_index = @layer_model.index(index, 0)
          end
          refresh_all("Added text label")
        else
          handle_status(value.nil? ? "Text add canceled" : "Text add failed")
        end
      end

      add_asset_action = Qt6::Action.new("Add Asset…", @widget)
      add_asset_action.shortcut = "Ctrl+Shift+A"
      add_asset_action.on_triggered do
        if add_asset_dialog.exec == Qt6::DialogCode::Accepted
          selected = add_asset_dialog.selected_file

          if !selected.empty? && @state.add_asset(selected)
            if index = @state.asset_layer_index
              @state.set_active_layer(index)
              @layer_tree.current_index = @layer_model.index(index, 0)
            end
            refresh_all("Added asset #{File.basename(selected)}")
          else
            handle_status(selected.empty? ? "Asset add canceled" : "Asset add failed")
          end
        else
          handle_status("Asset add canceled")
        end
      end

      edit_text_action = Qt6::Action.new("Edit Selected Text…", @widget)
      edit_text_action.on_triggered do
        object = @state.selected_text_object if @state.selected_text_present?
        unless object
          handle_status("Select a text label to edit it")
          next
        end

        value = Qt6::InputDialog.get_text(@widget, title: "Edit Text Label", label: "Label text:", value: object.text)
        if value
          updated = value.strip
          if updated.empty?
            handle_status("Text label cannot be empty")
          else
            object.text = updated
            refresh_all("Updated text label")
          end
        else
          handle_status("Text edit canceled")
        end
      end

      delete_text_action = Qt6::Action.new("Delete Selected Text…", @widget)
      delete_text_action.on_triggered do
        object = @state.selected_text_object if @state.selected_text_present?
        unless object
          handle_status("Select a text label to delete it")
          next
        end

        result = Qt6::MessageBox.question(
          @widget,
          title: "Delete Text Label",
          text: "Delete '#{object.text}'?",
          informative_text: "This removes the selected text label from the Crystal slice.",
          buttons: Qt6::MessageBoxButton::Yes | Qt6::MessageBoxButton::No
        )

        if result == Qt6::MessageBoxButton::Yes && (layer = @state.text_layer) && layer.remove_text(object)
          @state.clear_text_selection
          refresh_all("Deleted text label")
        elsif result == Qt6::MessageBoxButton::No
          handle_status("Delete canceled")
        else
          handle_status("Text delete failed")
        end
      end

      duplicate_path_action = Qt6::Action.new("Duplicate Selected Path", @widget)
      duplicate_path_action.on_triggered do
        unless @state.selected_path_present?
          handle_status("Select a path to duplicate it")
          next
        end

        if object = @state.duplicate_selected_path
          if index = @state.path_layer_index
            @state.set_active_layer(index)
            @layer_tree.current_index = @layer_model.index(index, 0)
          end
          refresh_all("Duplicated path #{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}")
        else
          handle_status("Path duplicate failed")
        end
      end

      delete_path_action = Qt6::Action.new("Delete Selected Path…", @widget)
      delete_path_action.on_triggered do
        object = @state.selected_path_object if @state.selected_path_present?
        unless object
          handle_status("Select a path to delete it")
          next
        end

        label = "#{@state.hex_label(object.col_a, object.row_a)}-#{@state.hex_label(object.col_b, object.row_b)}"
        result = Qt6::MessageBox.question(
          @widget,
          title: "Delete Path",
          text: "Delete path #{label}?",
          informative_text: "This removes the selected path segment from the Crystal slice.",
          buttons: Qt6::MessageBoxButton::Yes | Qt6::MessageBoxButton::No
        )

        if result == Qt6::MessageBoxButton::Yes && (layer = @state.path_layer) && layer.remove_path(object)
          @state.clear_path_selection
          refresh_all("Deleted path #{label}")
        elsif result == Qt6::MessageBoxButton::No
          handle_status("Delete canceled")
        else
          handle_status("Path delete failed")
        end
      end

      replace_asset_image_action = Qt6::Action.new("Replace Selected Asset Image…", @widget)
      replace_asset_image_action.on_triggered do
        object = @state.selected_asset_object if @state.selected_asset_present?
        unless object
          handle_status("Select an asset to replace its image")
          next
        end

        asset_image_dialog.select_file(object.image_path || File.join(Dir.current, "asset.png"))

        if asset_image_dialog.exec == Qt6::DialogCode::Accepted
          selected = asset_image_dialog.selected_file

          if !selected.empty? && object.set_image_path(selected)
            refresh_all("Replaced asset image with #{File.basename(selected)}")
          else
            handle_status(selected.empty? ? "Asset image replace canceled" : "Asset image replace failed")
          end
        else
          handle_status("Asset image replace canceled")
        end
      end

      duplicate_asset_action = Qt6::Action.new("Duplicate Selected Asset", @widget)
      duplicate_asset_action.shortcut = "Ctrl+Shift+D"
      duplicate_asset_action.on_triggered do
        unless @state.selected_asset_present?
          handle_status("Select an asset to duplicate it")
          next
        end

        if object = @state.duplicate_selected_asset
          if index = @state.asset_layer_index
            @state.set_active_layer(index)
            @layer_tree.current_index = @layer_model.index(index, 0)
          end
          refresh_all("Duplicated asset #{object.label}")
        else
          handle_status("Asset duplicate failed")
        end
      end

      reset_asset_transform_action = Qt6::Action.new("Reset Selected Asset Transform", @widget)
      reset_asset_transform_action.on_triggered do
        object = @state.selected_asset_object if @state.selected_asset_present?
        unless object
          handle_status("Select an asset to reset it")
          next
        end

        object.scale = 0.5
        object.rotation = 0.0
        object.opacity = 1.0
        @state.snap_asset_to_hex(object) if object.snap_to_hex
        refresh_all("Reset asset transform")
      end

      delete_asset_action = Qt6::Action.new("Delete Selected Asset…", @widget)
      delete_asset_action.on_triggered do
        object = @state.selected_asset_object if @state.selected_asset_present?
        unless object
          handle_status("Select an asset to delete it")
          next
        end

        result = Qt6::MessageBox.question(
          @widget,
          title: "Delete Asset",
          text: "Delete '#{object.label}'?",
          informative_text: "This removes the selected asset from the Crystal slice.",
          buttons: Qt6::MessageBoxButton::Yes | Qt6::MessageBoxButton::No
        )

        if result == Qt6::MessageBoxButton::Yes && (layer = @state.asset_layer) && layer.remove_asset(object)
          @state.clear_asset_selection
          refresh_all("Deleted asset")
        elsif result == Qt6::MessageBoxButton::No
          handle_status("Delete canceled")
        else
          handle_status("Asset delete failed")
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
      file_menu << open_slice_action
      file_menu << open_action
      file_menu << import_background_action
      file_menu << add_text_action
      file_menu << add_asset_action
      file_menu << save_slice_action
      file_menu << export_action
      file_menu.add_separator
      file_menu << quit_action

      edit_menu << add_text_action
      edit_menu << add_asset_action
      edit_menu << edit_text_action
      edit_menu << delete_text_action
      edit_menu << duplicate_path_action
      edit_menu << delete_path_action
      edit_menu << duplicate_asset_action
      edit_menu << reset_asset_transform_action
      edit_menu << replace_asset_image_action
      edit_menu << delete_asset_action

      view_menu << reset_view_action
      view_menu << @grid_action
      view_menu << @coords_action
      view_menu << @asset_action
      view_menu.add_separator
      @show_layers_action.shortcut = "Ctrl+1"
      @show_layers_action.on_triggered do
        next unless dock = @layers_dock

        dock.visible = true
        dock.raise_to_front
      end
      @show_inspector_action.shortcut = "Ctrl+2"
      @show_inspector_action.on_triggered do
        next unless dock = @inspector_dock

        dock.visible = true
        dock.raise_to_front
      end
      view_menu << @show_layers_action
      view_menu << @show_inspector_action

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
          @state.clear_pending_path_anchor unless tool_name == "Path"
          if tool_name == "Fill"
            if index = @state.terrain_layer_index
              @state.set_active_layer(index)
            end
          end
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
      panel.minimum_width = 250
      panel.vbox do |column|
        column << Qt6::Label.new("Python parity target: layer stack + inspector sync")
        column << @layer_tree
      end

      dock = Qt6::DockWidget.new("Layers", @widget)
      dock.minimum_width = 250
      dock.widget = panel
      @widget.add_dock_widget(dock, Qt6::DockArea::Left)
      @layers_dock = dock
    end

    private def build_inspector_dock : Nil
      @layer_visible_check.on_toggled do |checked|
        next if @updating_panel

        @state.active_layer_visible = checked
        refresh_layer_model
        @canvas.refresh(checked ? "Layer enabled" : "Layer hidden")
      end

      @background_offset_x_spin.set_range(-5000.0, 5000.0)
      @background_offset_x_spin.decimals = 1
      @background_offset_x_spin.single_step = 10.0
      @background_offset_x_spin.suffix = " px"
      @background_offset_x_spin.on_value_changed do |value|
        next if @updating_panel
        next unless layer = @state.background_layer

        layer.offset_x = value
        @canvas.refresh("Background X #{value.round(1)}")
      end

      @background_offset_y_spin.set_range(-5000.0, 5000.0)
      @background_offset_y_spin.decimals = 1
      @background_offset_y_spin.single_step = 10.0
      @background_offset_y_spin.suffix = " px"
      @background_offset_y_spin.on_value_changed do |value|
        next if @updating_panel
        next unless layer = @state.background_layer

        layer.offset_y = value
        @canvas.refresh("Background Y #{value.round(1)}")
      end

      @background_scale_spin.set_range(0.05, 20.0)
      @background_scale_spin.decimals = 2
      @background_scale_spin.single_step = 0.05
      @background_scale_spin.suffix = "x"
      @background_scale_spin.on_value_changed do |value|
        next if @updating_panel
        next unless layer = @state.background_layer

        layer.scale = value
        @canvas.refresh("Background scale #{value.round(2)}x")
      end

      @terrain_color_button.on_clicked do
        next if @updating_panel
        next unless layer = @state.terrain_layer

        color = Qt6::ColorDialog.get_color(@widget, layer.accent, title: "Select Fill Color")
        next unless color

        apply_terrain_fill_color(color, "Updated fill color")
      end

      terrain_fill_presets.each_with_index do |preset, index|
        @terrain_preset_buttons[index].on_clicked do
          next if @updating_panel

          apply_terrain_fill_color(preset[1], "Switched fill color to #{preset[0]}")
        end
      end

      @terrain_radius_spin.set_range(0, 3)
      @terrain_radius_spin.single_step = 1
      @terrain_radius_spin.suffix = " hex"
      @terrain_radius_spin.on_value_changed do |value|
        next if @updating_panel

        @state.fill_radius = value
        @canvas.refresh("Fill radius #{value}")
      end

      @path_width_spin.set_range(1.0, 12.0)
      @path_width_spin.decimals = 1
      @path_width_spin.single_step = 0.5
      @path_width_spin.suffix = " px"
      @path_width_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_path_object if @state.selected_path_present?)

        object.width = value
        @canvas.refresh("Updated path width")
      end

      @path_line_type_combo << "Solid"
      @path_line_type_combo << "Dashed"
      @path_line_type_combo << "Dotted"
      @path_line_type_combo.on_current_index_changed do |index|
        next if @updating_panel
        next unless object = (@state.selected_path_object if @state.selected_path_present?)

        object.line_type = case index
                           when 1
                             "dashed"
                           when 2
                             "dotted"
                           else
                             "solid"
                           end
        @canvas.refresh("Updated path style")
      end

      @path_color_button.on_clicked do
        next if @updating_panel
        next unless object = (@state.selected_path_object if @state.selected_path_present?)

        color = Qt6::ColorDialog.get_color(@widget, object.color, title: "Select Path Color")
        next unless color

        object.color = color
        @path_color_button.text = color_button_text("Path", color)
        @canvas.refresh("Updated path color")
      end

      @path_opacity_spin.set_range(0.0, 1.0)
      @path_opacity_spin.decimals = 2
      @path_opacity_spin.single_step = 0.05
      @path_opacity_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_path_object if @state.selected_path_present?)

        object.opacity = value
        @canvas.refresh("Updated path opacity")
      end

      @asset_scale_spin.set_range(0.1, 4.0)
      @asset_scale_spin.decimals = 2
      @asset_scale_spin.single_step = 0.05
      @asset_scale_spin.suffix = "x"
      @asset_scale_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_asset_object if @state.selected_asset_present?)

        object.scale = value
        @canvas.refresh("Updated asset scale")
      end

      @asset_rotation_spin.set_range(-180.0, 180.0)
      @asset_rotation_spin.decimals = 1
      @asset_rotation_spin.single_step = 5.0
      @asset_rotation_spin.suffix = " deg"
      @asset_rotation_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_asset_object if @state.selected_asset_present?)

        object.rotation = value
        @canvas.refresh("Updated asset rotation")
      end

      @asset_opacity_spin.set_range(0.0, 1.0)
      @asset_opacity_spin.decimals = 2
      @asset_opacity_spin.single_step = 0.05
      @asset_opacity_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_asset_object if @state.selected_asset_present?)

        object.opacity = value
        @canvas.refresh("Updated asset opacity")
      end

      @asset_snap_check.on_toggled do |checked|
        next if @updating_panel
        next unless object = (@state.selected_asset_object if @state.selected_asset_present?)

        object.snap_to_hex = checked
        @state.snap_asset_to_hex(object) if checked
        @canvas.refresh(checked ? "Asset snapping enabled" : "Asset snapping disabled")
      end

      @text_value_edit.placeholder_text = "Select a text label"
      @text_value_edit.on_text_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.text = value
        @canvas.refresh("Updated text content")
      end

      @text_font_size_spin.set_range(6, 96)
      @text_font_size_spin.single_step = 1
      @text_font_size_spin.suffix = " pt"
      @text_font_size_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.font_size = value
        @canvas.refresh("Updated text size")
      end

      @text_bold_check.on_toggled do |checked|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.bold = checked
        @canvas.refresh(checked ? "Bold enabled" : "Bold disabled")
      end

      @text_italic_check.on_toggled do |checked|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.italic = checked
        @canvas.refresh(checked ? "Italic enabled" : "Italic disabled")
      end

      @text_alignment_combo << "Left"
      @text_alignment_combo << "Center"
      @text_alignment_combo << "Right"
      @text_alignment_combo.on_current_index_changed do |index|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.alignment = case index
                           when 1
                             "center"
                           when 2
                             "right"
                           else
                             "left"
                           end
        @canvas.refresh("Updated text alignment")
      end

      @text_color_button.on_clicked do
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        color = Qt6::ColorDialog.get_color(@widget, object.color, title: "Select Text Color")
        next unless color

        object.color = color
        @text_color_button.text = color_button_text("Text", color)
        @canvas.refresh("Updated text color")
      end

      @text_opacity_spin.set_range(0.0, 1.0)
      @text_opacity_spin.decimals = 2
      @text_opacity_spin.single_step = 0.05
      @text_opacity_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.opacity = value
        @canvas.refresh("Updated text opacity")
      end

      @text_rotation_spin.set_range(-180.0, 180.0)
      @text_rotation_spin.decimals = 1
      @text_rotation_spin.single_step = 5.0
      @text_rotation_spin.suffix = " deg"
      @text_rotation_spin.on_value_changed do |value|
        next if @updating_panel
        next unless object = (@state.selected_text_object if @state.selected_text_present?)

        object.rotation = value
        @canvas.refresh("Updated text rotation")
      end

      summary = Qt6::Label.new("Scope: shell, toolbar, layers, pan/zoom canvas, and PNG export. Remaining Python dialogs and full project serialization are still ahead.")
      background_controls = Qt6::Widget.new
      background_controls.vbox do |column|
        column << Qt6::Label.new("Background Transform")
        column << Qt6::Label.new("Offset X")
        column << @background_offset_x_spin
        column << Qt6::Label.new("Offset Y")
        column << @background_offset_y_spin
        column << Qt6::Label.new("Scale")
        column << @background_scale_spin
      end
      terrain_controls = Qt6::Widget.new
      terrain_controls.vbox do |column|
        column << Qt6::Label.new("Fill Tool")
        column << @terrain_fill_label
        column << Qt6::Label.new("Radius")
        column << @terrain_radius_spin
        column << @terrain_color_button
        column << build_terrain_preset_row
      end
      path_controls = Qt6::Widget.new
      path_controls.vbox do |column|
        column << Qt6::Label.new("Selected Path")
        column << @path_label
        column << Qt6::Label.new("Width")
        column << @path_width_spin
        column << Qt6::Label.new("Line Style")
        column << @path_line_type_combo
        column << @path_color_button
        column << Qt6::Label.new("Opacity")
        column << @path_opacity_spin
      end
      asset_controls = Qt6::Widget.new
      asset_controls.vbox do |column|
        column << Qt6::Label.new("Selected Asset")
        column << @asset_label
        column << Qt6::Label.new("Image Path")
        column << @asset_path_label
        column << @asset_snap_check
        column << Qt6::Label.new("Scale")
        column << @asset_scale_spin
        column << Qt6::Label.new("Rotation")
        column << @asset_rotation_spin
        column << Qt6::Label.new("Opacity")
        column << @asset_opacity_spin
      end
      text_controls = Qt6::Widget.new
      text_controls.vbox do |column|
        column << Qt6::Label.new("Selected Text")
        column << Qt6::Label.new("Content")
        column << @text_value_edit
        column << Qt6::Label.new("Font Size")
        column << @text_font_size_spin
        column << Qt6::Label.new("Alignment")
        column << @text_alignment_combo
        column << @text_color_button
        column << Qt6::Label.new("Opacity")
        column << @text_opacity_spin
        column << Qt6::Label.new("Rotation")
        column << @text_rotation_spin
        column << @text_bold_check
        column << @text_italic_check
      end

      panel = Qt6::Widget.new
      panel.minimum_width = 320
      panel.vbox do |column|
        column << Qt6::Label.new("Crystal Port Inspector")
        column << @project_label
        column << @source_label
        column << @background_label
        column << background_controls
        column << terrain_controls
        column << path_controls
        column << asset_controls
        column << text_controls
        column << @active_tool_label
        column << @active_layer_label
        column << @hover_label
        column << @layer_visible_check
        column << @selection_note
        column << summary
      end

      dock = Qt6::DockWidget.new("Inspector", @widget)
      dock.minimum_width = 320
      dock.widget = panel
      @widget.add_dock_widget(dock, Qt6::DockArea::Right)
      @inspector_dock = dock
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
                              "Slice: #{File.basename(path)}"
                            else
                              "Slice: unsaved Crystal prototype"
                            end
      @source_label.text = if path = @state.source_path
                             "Source map: #{File.basename(path)}"
                           else
                             "Source map: none selected"
                           end
      @background_label.text = if layer = @state.background_layer
                                 if path = layer.image_path
                                   "Background: #{File.basename(path)} (#{layer.image_size_text})"
                                 else
                                   "Background: #{layer.image_size_text}"
                                 end
                               else
                                 "Background: unavailable"
                               end
      if layer = @state.terrain_layer
        @terrain_fill_label.text = "Painted hexes: #{layer.fill_count}"
        @terrain_radius_spin.value = @state.fill_radius
        @terrain_color_button.text = color_button_text("Fill", layer.accent)
        @terrain_radius_spin.enabled = true
        @terrain_color_button.enabled = true
        update_terrain_preset_button_styles(layer.accent)
      else
        @terrain_fill_label.text = "Painted hexes: unavailable"
        @terrain_radius_spin.value = 0
        @terrain_color_button.text = "Fill Color"
        @terrain_radius_spin.enabled = false
        @terrain_color_button.enabled = false
        update_terrain_preset_button_styles(nil)
      end
      if layer = @state.background_layer
        @background_offset_x_spin.value = layer.offset_x
        @background_offset_y_spin.value = layer.offset_y
        @background_scale_spin.value = layer.scale
      end
      if object = (@state.selected_path_object if @state.selected_path_present?)
        @path_label.text = "Path: #{@state.hex_label(object.col_a, object.row_a)} -> #{@state.hex_label(object.col_b, object.row_b)}"
        @path_width_spin.value = object.width
        @path_line_type_combo.current_index = case object.line_type
                                              when "dashed"
                                                1
                                              when "dotted"
                                                2
                                              else
                                                0
                                              end
        @path_color_button.text = color_button_text("Path", object.color)
        @path_opacity_spin.value = object.opacity
        @path_width_spin.enabled = true
        @path_line_type_combo.enabled = true
        @path_color_button.enabled = true
        @path_opacity_spin.enabled = true
      else
        @path_label.text = "Path: none selected"
        @path_width_spin.value = 3.0
        @path_line_type_combo.current_index = 0
        @path_color_button.text = "Path Color"
        @path_opacity_spin.value = 1.0
        @path_width_spin.enabled = false
        @path_line_type_combo.enabled = false
        @path_color_button.enabled = false
        @path_opacity_spin.enabled = false
      end
      if object = (@state.selected_asset_object if @state.selected_asset_present?)
        @asset_label.text = if path = object.image_path
                              "Asset: #{File.basename(path)}"
                            else
                              "Asset: #{object.label}"
                            end
        @asset_label.tool_tip = object.image_path || object.label
        @asset_path_label.text = if path = object.image_path
                                   path
                                 else
                                   "Path: none"
                                 end
        @asset_path_label.tool_tip = @asset_path_label.text
        @asset_snap_check.checked = object.snap_to_hex
        @asset_scale_spin.value = object.scale
        @asset_rotation_spin.value = object.rotation
        @asset_opacity_spin.value = object.opacity
        @asset_snap_check.enabled = true
        @asset_scale_spin.enabled = true
        @asset_rotation_spin.enabled = true
        @asset_opacity_spin.enabled = true
      else
        @asset_label.text = "Asset: none selected"
        @asset_label.tool_tip = ""
        @asset_path_label.text = "Path: none selected"
        @asset_path_label.tool_tip = ""
        @asset_snap_check.checked = true
        @asset_scale_spin.value = 1.0
        @asset_rotation_spin.value = 0.0
        @asset_opacity_spin.value = 1.0
        @asset_snap_check.enabled = false
        @asset_scale_spin.enabled = false
        @asset_rotation_spin.enabled = false
        @asset_opacity_spin.enabled = false
      end
      if object = (@state.selected_text_object if @state.selected_text_present?)
        @text_value_edit.text = object.text
        @text_font_size_spin.value = object.font_size
        @text_alignment_combo.current_index = case object.alignment
                                              when "center"
                                                1
                                              when "right"
                                                2
                                              else
                                                0
                                              end
        @text_color_button.text = color_button_text("Text", object.color)
        @text_opacity_spin.value = object.opacity
        @text_rotation_spin.value = object.rotation
        @text_bold_check.checked = object.bold
        @text_italic_check.checked = object.italic
        @text_value_edit.enabled = true
        @text_font_size_spin.enabled = true
        @text_alignment_combo.enabled = true
        @text_color_button.enabled = true
        @text_opacity_spin.enabled = true
        @text_rotation_spin.enabled = true
        @text_bold_check.enabled = true
        @text_italic_check.enabled = true
      else
        @text_value_edit.text = ""
        @text_font_size_spin.value = 12
        @text_alignment_combo.current_index = 0
        @text_color_button.text = "Text Color"
        @text_opacity_spin.value = 1.0
        @text_rotation_spin.value = 0.0
        @text_bold_check.checked = false
        @text_italic_check.checked = false
        @text_value_edit.enabled = false
        @text_font_size_spin.enabled = false
        @text_alignment_combo.enabled = false
        @text_color_button.enabled = false
        @text_opacity_spin.enabled = false
        @text_rotation_spin.enabled = false
        @text_bold_check.enabled = false
        @text_italic_check.enabled = false
      end
      @active_tool_label.text = "Active tool: #{@state.active_tool}"
      @active_layer_label.text = "Active layer: #{@state.active_layer.name}"
      @hover_label.text = if hover = @state.hover_hex
                            "Hover: #{@state.hex_label(hover[0], hover[1])}"
                          else
                            "Hover: outside map"
                          end
      @layer_visible_check.checked = @state.active_layer.visible
      @selection_note.text = if anchor = @state.pending_path_anchor
                               if hover = @state.hover_hex
                                 if anchor == hover
                                   "Pending path start: #{@state.hex_label(anchor[0], anchor[1])}. Click the same hex again or press Escape/Delete to cancel, or click another hex with the Path tool to create a segment."
                                 else
                                   if @state.neighboring_hexes?(anchor[0], anchor[1], hover[0], hover[1])
                                     "Pending path: #{@state.hex_label(anchor[0], anchor[1])} -> #{@state.hex_label(hover[0], hover[1])}. Click to create this neighboring segment, or press Escape/Delete or leave the Path tool to cancel."
                                   else
                                     "Pending path start: #{@state.hex_label(anchor[0], anchor[1])}. Choose a neighboring hex to create a segment, or press Escape/Delete to cancel."
                                   end
                                 end
                               else
                                 "Pending path start: #{@state.hex_label(anchor[0], anchor[1])}. Click a neighboring hex with the Path tool to finish the segment, or press Escape/Delete to cancel."
                               end
                             elsif object = (@state.selected_path_object if @state.selected_path_present?)
                               "Selected path: #{@state.hex_label(object.col_a, object.row_a)} -> #{@state.hex_label(object.col_b, object.row_b)} at #{@state.zoom.round(2)}x. Click with the Path tool to change selection, drag an endpoint handle onto a neighboring hex to reshape it, press Delete to remove it, or edit it in the inspector."
                             elsif object = (@state.selected_asset_object if @state.selected_asset_present?)
                               "Selected asset: '#{object.label}' at #{@state.zoom.round(2)}x. Click with the Asset tool to change selection, drag to move, or edit it in the inspector."
                             elsif object = (@state.selected_text_object if @state.selected_text_present?)
                               "Selected text: '#{object.text}' at #{@state.zoom.round(2)}x. Click with the Text tool to change selection, drag to move, or edit it in the inspector."
                             elsif @state.active_tool == "Fill" && (terrain_layer = @state.terrain_layer)
                               "Fill tool active at #{@state.zoom.round(2)}x. Left-drag paints and right-drag clears within radius #{@state.fill_radius} around the hovered hex, with #{terrain_layer.fill_count} painted so far. The inspector controls the current fill color and radius."
                             else
                               "Selected #{@state.active_layer.kind.downcase} layer at #{@state.zoom.round(2)}x. The current slice proves the shell and canvas workflow before porting project I/O and tool-specific commands."
                             end
      @updating_panel = false
    end

    private def handle_status(message : String) : Nil
      @status_bar.show_message(message, 1800)
      refresh_inspector
    end

    private def color_button_text(prefix : String, color : Qt6::Color) : String
      "#{prefix} Color (#{color.red}, #{color.green}, #{color.blue})"
    end

    private def terrain_fill_presets : Array(Tuple(String, Qt6::Color))
      [
        {"Olive", Qt6::Color.new(136, 160, 92)},
        {"Sand", Qt6::Color.new(194, 171, 118)},
        {"Water", Qt6::Color.new(92, 128, 170)},
        {"Rock", Qt6::Color.new(122, 116, 104)},
      ]
    end

    private def build_terrain_preset_buttons : Array(Qt6::PushButton)
      terrain_fill_presets.map do |preset|
        button = Qt6::PushButton.new(preset[0])
        button.fixed_height = 28
        button.tool_tip = "Set fill color to #{preset[0]}"
        button
      end
    end

    private def build_terrain_preset_row : Qt6::Widget
      row_widget = Qt6::Widget.new
      row = Qt6::HBoxLayout.new(row_widget)
      row.spacing = 6
      row.set_contents_margins(0, 0, 0, 0)
      @terrain_preset_buttons.each do |button|
        row << button
      end
      row_widget
    end

    private def apply_terrain_fill_color(color : Qt6::Color, message : String) : Nil
      return unless layer = @state.terrain_layer

      layer.accent = color
      refresh_layer_model
      refresh_inspector
      @canvas.refresh(message)
    end

    private def update_terrain_preset_button_styles(active_color : Qt6::Color?) : Nil
      terrain_fill_presets.each_with_index do |preset, index|
        color = preset[1]
        selected = active_color && colors_match?(active_color, color)
        @terrain_preset_buttons[index].style_sheet = if selected
                                                       "QPushButton { background: rgb(#{color.red}, #{color.green}, #{color.blue}); border: 2px solid rgb(52, 48, 42); color: rgb(32, 28, 24); font-weight: 600; }"
                                                     else
                                                       "QPushButton { background: rgb(#{color.red}, #{color.green}, #{color.blue}); border: 1px solid rgb(140, 132, 120); color: rgb(32, 28, 24); }"
                                                     end
      end
    end

    private def colors_match?(left : Qt6::Color, right : Qt6::Color) : Bool
      left.red == right.red && left.green == right.green && left.blue == right.blue && left.alpha == right.alpha
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