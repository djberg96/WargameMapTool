require "./spec_helper"

describe WargameMapToolCrystal::MapState do
  it "loads a canonical hexmap fixture for supported layer types" do
    fixture_path = File.expand_path("./fixtures/import_smoke.hexmap", __DIR__)
    state = WargameMapToolCrystal::MapState.new

    message = state.load_hexmap(fixture_path)
    message.should_not be_nil
    message.not_nil!.should contain("Opened import_smoke.hexmap")
    message.not_nil!.should contain("skipped draw, sketch")

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
      layer_types.should eq(["background", "fill", "hexside", "border", "path", "freeform_path", "text", "asset"])

      asset_layer = exported["layers"].as_a.find { |layer| layer["type"].as_s == "asset" }
      asset_layer.should_not be_nil
      asset_layer.not_nil!["objects"].as_a.first["image"].as_s.should eq("builtin:operational/operational_poi_town.png")

      roundtrip = WargameMapToolCrystal::MapState.new
      roundtrip.load_hexmap(export_path).should_not be_nil
      roundtrip.grid_orientation.should eq("flat")
      roundtrip.first_row_offset.should eq("odd")
      roundtrip.asset_layer.not_nil!.asset_count.should eq(1)
      roundtrip.asset_layer.not_nil!.objects.first.has_image?.should be_true
      roundtrip.text_layer.not_nil!.text_count.should eq(1)
      roundtrip.path_layer.not_nil!.path_count.should eq(1)
    ensure
      File.delete(export_path) if File.exists?(export_path)
    end
  end
end
