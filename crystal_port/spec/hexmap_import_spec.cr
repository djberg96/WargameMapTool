require "./spec_helper"
require "../src/wargame_map_tool_crystal/map_canvas"

describe WargameMapToolCrystal::MapState do
  it "loads a canonical hexmap fixture for supported layer types" do
    fixture_path = File.expand_path("./fixtures/import_smoke.hexmap", __DIR__)
    state = WargameMapToolCrystal::MapState.new

    message = state.load_hexmap(fixture_path)
    message.should_not be_nil
    message.not_nil!.should contain("Opened import_smoke.hexmap")
    message.not_nil!.should contain("skipped draw")

    state.source_path.should eq(fixture_path)
    state.project_path.should be_nil
    state.cols.should eq(7)
    state.rows.should eq(5)
    state.grid_orientation.should eq("flat")
    state.first_row_offset.should eq("odd")
    state.hex_radius.should eq(42.0)
    state.show_grid.should be_true
    state.show_coordinates.should be_true

    background = state.background_layer.not_nil!
    background.has_image?.should be_true
    background.image_path.should_not be_nil
    background.image_path.not_nil!.ends_with?("classic_orchard.png").should be_true
    background.offset_x.should eq(18.0)
    background.offset_y.should eq(-12.0)
    background.scale.should eq(0.8)

    terrain = state.terrain_layer.not_nil!
    terrain.fill_count.should eq(2)
    terrain.fill_at(2, 2).should_not be_nil
    terrain.fill_at(4, 2).should_not be_nil

    border = state.border_layer.not_nil!
    border.border_count.should eq(1)
    border.objects.first.col_a.should eq(2)
    border.objects.first.row_a.should eq(2)
    border.objects.first.col_b.should eq(2)
    border.objects.first.row_b.should eq(3)
    border.objects.first.line_type.should eq("dashed")

    hexside = state.hexside_layer.not_nil!
    hexside.hexside_count.should eq(1)
    hexside.objects.first.col_a.should eq(1)
    hexside.objects.first.row_a.should eq(1)
    hexside.objects.first.col_b.should eq(2)
    hexside.objects.first.row_b.should eq(2)

    path = state.path_layer.not_nil!
    path.path_count.should eq(1)
    path.objects.first.col_a.should eq(0)
    path.objects.first.row_a.should eq(0)
    path.objects.first.col_b.should eq(1)
    path.objects.first.row_b.should eq(0)
    path.objects.first.line_type.should eq("dotted")

    freeform = state.freeform_path_layer.not_nil!
    freeform.path_count.should eq(1)
    freeform.objects.first.points.size.should eq(3)

    text = state.text_layer.not_nil!
    text.text_count.should eq(1)
    text.objects.first.text.should eq("Depot")
    text.objects.first.alignment.should eq("center")

    sketch = state.sketch_layer.not_nil!
    sketch.sketch_count.should eq(1)
    sketch.objects.first.shape_type.should eq("rect")
    sketch.objects.first.fill_enabled.should be_true
    sketch.objects.first.rotation.should eq(8.0)

    assets = state.asset_layer.not_nil!
    assets.asset_count.should eq(1)
    assets.objects.first.image_path.should_not be_nil
    assets.objects.first.image_path.not_nil!.ends_with?("operational_poi_town.png").should be_true
    assets.objects.first.has_image?.should be_true
    assets.objects.first.snap_to_hex.should be_false
  end

  it "exports supported state as a source-compatible hexmap" do
    fixture_path = File.expand_path("./fixtures/import_smoke.hexmap", __DIR__)
    export_path = "/tmp/wargame-map-tool-crystal-export-#{Process.pid}.hexmap"
    state = WargameMapToolCrystal::MapState.new

    begin
      state.load_hexmap(fixture_path).should_not be_nil
      state.save_hexmap(export_path)

      exported = JSON.parse(File.read(export_path))
      exported["grid"]["orientation"].as_s.should eq("flat")
      exported["grid"]["first_row_offset"].as_s.should eq("odd")

      layer_types = exported["layers"].as_a.map { |layer| layer["type"].as_s }
      layer_types.should eq(["background", "fill", "hexside", "border", "path", "freeform_path", "sketch", "text", "asset"])

      sketch_layer = exported["layers"].as_a.find { |layer| layer["type"].as_s == "sketch" }
      sketch_layer.should_not be_nil
      sketch_layer.not_nil!["objects"].as_a.size.should eq(1)
      sketch_layer.not_nil!["objects"].as_a.first["shape_type"].as_s.should eq("rect")

      asset_layer = exported["layers"].as_a.find { |layer| layer["type"].as_s == "asset" }
      asset_layer.should_not be_nil
      asset_layer.not_nil!["objects"].as_a.first["image"].as_s.should eq("builtin:operational/operational_poi_town.png")

      roundtrip = WargameMapToolCrystal::MapState.new
      roundtrip.load_hexmap(export_path).should_not be_nil
      roundtrip.grid_orientation.should eq("flat")
      roundtrip.first_row_offset.should eq("odd")
      roundtrip.asset_layer.not_nil!.asset_count.should eq(1)
      roundtrip.asset_layer.not_nil!.objects.first.has_image?.should be_true
      roundtrip.sketch_layer.not_nil!.sketch_count.should eq(1)
      roundtrip.text_layer.not_nil!.text_count.should eq(1)
      roundtrip.path_layer.not_nil!.path_count.should eq(1)
    ensure
      File.delete(export_path) if File.exists?(export_path)
    end
  end

  it "relativizes non-builtin image paths on hexmap export" do
    fixture_path = File.expand_path("./fixtures/import_smoke.hexmap", __DIR__)
    temp_root = "/tmp/wargame-map-tool-crystal-relative-#{Process.pid}"
    maps_dir = "#{temp_root}/maps"
    images_dir = "#{temp_root}/images"
    assets_dir = "#{temp_root}/assets"
    export_path = "#{maps_dir}/relative-export.hexmap"
    background_copy = "#{images_dir}/background.png"
    asset_copy = "#{assets_dir}/asset.png"
    source_background = File.expand_path("../../assets/assets/classic_orchard.png", __DIR__)
    source_asset = File.expand_path("../../assets/assets/operational/operational_poi_town.png", __DIR__)
    state = WargameMapToolCrystal::MapState.new

    begin
      Dir.mkdir_p(maps_dir)
      Dir.mkdir_p(images_dir)
      Dir.mkdir_p(assets_dir)
      File.write(background_copy, File.read(source_background))
      File.write(asset_copy, File.read(source_asset))

      state.load_hexmap(fixture_path).should_not be_nil
      state.background_layer.not_nil!.load_image(background_copy).should be_true
      state.asset_layer.not_nil!.objects.first.set_image_path(asset_copy).should be_true
      state.save_hexmap(export_path)

      exported = JSON.parse(File.read(export_path))
      background_layer = exported["layers"].as_a.find { |layer| layer["type"].as_s == "background" }
      asset_layer = exported["layers"].as_a.find { |layer| layer["type"].as_s == "asset" }
      background_layer.should_not be_nil
      asset_layer.should_not be_nil
      background_layer.not_nil!["image_path"].as_s.should eq("../images/background.png")
      asset_layer.not_nil!["objects"].as_a.first["image"].as_s.should eq("../assets/asset.png")

      roundtrip = WargameMapToolCrystal::MapState.new
      roundtrip.load_hexmap(export_path).should_not be_nil
      roundtrip.background_layer.not_nil!.has_image?.should be_true
      roundtrip.asset_layer.not_nil!.objects.first.has_image?.should be_true
    ensure
      [export_path, "#{export_path}.tmp", background_copy, asset_copy].each do |path|
        File.delete(path) if File.exists?(path)
      end
      [maps_dir, images_dir, assets_dir, temp_root].each do |path|
        Dir.delete(path) if Dir.exists?(path)
      end
    end
  end

  it "restores document snapshots without overwriting editor view state" do
    fixture_path = File.expand_path("./fixtures/import_smoke.hexmap", __DIR__)
    state = WargameMapToolCrystal::MapState.new

    state.load_hexmap(fixture_path).should_not be_nil
    state.show_grid = false
    state.show_coordinates = false
    state.show_assets = false
    state.active_tool = "Asset"
    state.fill_radius = 2

    snapshot = state.history_snapshot
    original_asset_scale = state.asset_layer.not_nil!.objects.first.scale

    state.background_layer.not_nil!.offset_x = 144.0
    state.terrain_layer.not_nil!.set_fill(0, 0, Qt6::Color.new(12, 34, 56)).should be_true
    state.text_layer.not_nil!.objects.first.text = "Forward HQ"
    state.asset_layer.not_nil!.objects.first.scale = 1.9
    state.fill_radius = 0

    state.restore_history_snapshot(snapshot).should be_true

    state.background_layer.not_nil!.offset_x.should eq(18.0)
    state.terrain_layer.not_nil!.fill_count.should eq(2)
    state.terrain_layer.not_nil!.fill_at(0, 0).should be_nil
    state.text_layer.not_nil!.objects.first.text.should eq("Depot")
    state.asset_layer.not_nil!.objects.first.scale.should eq(original_asset_scale)
    state.fill_radius.should eq(2)
    state.show_grid.should be_false
    state.show_coordinates.should be_false
    state.show_assets.should be_false
    state.active_tool.should eq("Asset")
  end

  it "creates non-rectangle sketch shapes from the current sketch tool defaults" do
    state = WargameMapToolCrystal::MapState.new

    state.sketch_shape_type = "line"
    line = state.create_sketch_from_drag(Qt6::PointF.new(10.0, 20.0), Qt6::PointF.new(42.0, 20.0))
    line.should_not be_nil
    line.not_nil!.shape_type.should eq("line")
    line.not_nil!.points.size.should eq(2)

    state.sketch_shape_type = "polygon"
    state.sketch_polygon_sides = 5
    polygon = state.create_sketch_from_drag(Qt6::PointF.new(30.0, 30.0), Qt6::PointF.new(54.0, 30.0))
    polygon.should_not be_nil
    polygon.not_nil!.shape_type.should eq("polygon")
    polygon.not_nil!.num_sides.should eq(5)
    polygon.not_nil!.radius.should be > 20.0

    state.sketch_shape_type = "ellipse"
    state.sketch_perfect_circle = true
    ellipse = state.create_sketch_from_drag(Qt6::PointF.new(60.0, 60.0), Qt6::PointF.new(100.0, 90.0))
    ellipse.should_not be_nil
    ellipse.not_nil!.shape_type.should eq("ellipse")
    ellipse.not_nil!.rx.should eq(15.0)
    ellipse.not_nil!.ry.should eq(15.0)

    state.sketch_shape_type = "freehand"
    state.sketch_freehand_closed = true
    freehand = state.create_sketch_freehand([{0.0, 0.0}, {18.0, 0.0}, {18.0, 12.0}])
    freehand.should_not be_nil
    freehand.not_nil!.shape_type.should eq("freehand")
    freehand.not_nil!.closed.should be_true
    freehand.not_nil!.points.size.should eq(3)

    state.sketch_layer.not_nil!.sketch_count.should eq(4)
    state.selected_sketch_object.should eq(freehand)
  end

  it "copies and pastes sketches through the sketch clipboard" do
    state = WargameMapToolCrystal::MapState.new

    state.sketch_shape_type = "ellipse"
    original = state.create_sketch_from_drag(Qt6::PointF.new(20.0, 30.0), Qt6::PointF.new(60.0, 70.0))
    original.should_not be_nil
    original.not_nil!.fill_enabled = true
    original.not_nil!.rotation = 12.0

    copied = state.copy_selected_sketch
    copied.should_not be_nil
    copied.not_nil!.id.should_not eq(original.not_nil!.id)
    copied.not_nil!.shape_type.should eq("ellipse")

    pasted = state.paste_sketch_from_clipboard
    pasted.should_not be_nil
    pasted.not_nil!.id.should_not eq(original.not_nil!.id)
    pasted.not_nil!.shape_type.should eq("ellipse")
    pasted.not_nil!.fill_enabled.should be_true
    pasted.not_nil!.rotation.should eq(12.0)
    pasted.not_nil!.points.first.should eq({original.not_nil!.points.first[0] + 10.0, original.not_nil!.points.first[1] + 10.0})
    pasted.not_nil!.rx.should eq(original.not_nil!.rx)
    pasted.not_nil!.ry.should eq(original.not_nil!.ry)

    state.sketch_layer.not_nil!.sketch_count.should eq(2)
    state.selected_sketch_object.should eq(pasted)
  end

  it "snaps sketch points to nearby hex centers and corners" do
    state = WargameMapToolCrystal::MapState.new

    center = state.hex_center(3, 3)
    snapped_center = state.snap_sketch_world_point(Qt6::PointF.new(center.x + 3.0, center.y - 2.0))
    snapped_center.x.should eq(center.x)
    snapped_center.y.should eq(center.y)

    corner = state.hex_points(3, 3).first
    snapped_corner = state.snap_sketch_world_point(Qt6::PointF.new(corner.x + 2.0, corner.y + 1.0))
    snapped_corner.x.should eq(corner.x)
    snapped_corner.y.should eq(corner.y)
  end
end

describe WargameMapToolCrystal::MapCanvas do
  it "snaps selected sketch moves to the grid in select mode" do
    application = app
    state = WargameMapToolCrystal::MapState.new
    status_messages = [] of String
    hover_messages = [] of String
    canvas = WargameMapToolCrystal::MapCanvas.new(
      state,
      ->(message : String) { status_messages << message },
      ->(message : String) { hover_messages << message }
    )
    canvas.widget.resize(860, 620)
    canvas.widget.show
    application.process_events

    state.active_tool = "Sketch"
    state.sketch_snap_to_grid = true
    object = state.create_sketch_rectangle(
      Qt6::PointF.new(40.0, 40.0),
      Qt6::PointF.new(80.0, 80.0)
    )
    object.should_not be_nil
    target_center = state.hex_center(5, 5)

    start_center = object.not_nil!.center
    start_screen = state.screen_point(Qt6::PointF.new(start_center[0], start_center[1]))
    drag_screen = state.screen_point(Qt6::PointF.new(target_center.x + 3.0, target_center.y - 2.0))

    canvas.widget.simulate_mouse_press(start_screen)
    canvas.widget.simulate_mouse_move(drag_screen, buttons: 1)
    canvas.widget.simulate_mouse_release(drag_screen)
    5.times { application.process_events }

    moved_center = object.not_nil!.center
    moved_center[0].should eq(target_center.x)
    moved_center[1].should eq(target_center.y)
    status_messages.last?.should eq("Moved sketch rect")
    application.should_not be_nil
  end
end

describe WargameMapToolCrystal::SketchObject do
  it "computes selection handles in world space" do
    object = WargameMapToolCrystal::SketchObject.new(
      shape_type: "rect",
      points: [{10.0, 20.0}, {30.0, 40.0}],
      stroke_width: 2.0,
    )

    corners = object.selection_corners
    corners.should eq([
      {9.0, 19.0},
      {31.0, 19.0},
      {31.0, 41.0},
      {9.0, 41.0},
    ])

    rotation_handle = object.rotation_handle(26.0)
    rotation_handle[0].should be_close(20.0, 0.001)
    rotation_handle[1].should be_close(-7.0, 0.001)
    object.rotation_angle_for({20.0, 4.0}).should be_close(0.0, 0.001)
  end

  it "resizes freehand sketches from an anchored bounding corner" do
    object = WargameMapToolCrystal::SketchObject.new(
      shape_type: "freehand",
      points: [{10.0, 10.0}, {30.0, 10.0}, {30.0, 30.0}, {10.0, 30.0}],
      stroke_width: 2.0,
      closed: true,
    )

    corners = object.selection_corners
    original_points = object.points.map { |point| {point[0], point[1]} }
    object.resize_from_anchor(corners[0], {51.0, 71.0}, original_points, object.radius, object.rx, object.ry)

    x_values = object.points.map(&.[0])
    y_values = object.points.map(&.[1])
    (x_values.max - x_values.min).should be_close(42.0, 0.001)
    (y_values.max - y_values.min).should be_close(62.0, 0.001)
    object.points.size.should eq(4)
    object.closed.should be_true
  end
end
