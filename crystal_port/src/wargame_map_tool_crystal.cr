require "qt6"
require "./wargame_map_tool_crystal/map_state"
require "./wargame_map_tool_crystal/map_canvas"
require "./wargame_map_tool_crystal/main_window"

app = Qt6.application
app.name = "Wargame Map Tool Crystal"
app.organization_name = "Wargame Map Tool"
app.organization_domain = "local.wargame-map-tool"
app.style_sheet = WargameMapToolCrystal::APP_STYLE

window = WargameMapToolCrystal::MainWindow.new
window.show
app.run