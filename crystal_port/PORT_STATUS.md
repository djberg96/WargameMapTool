# Crystal Port Status

This directory is a practical port spike for WargameMapTool, not a full rewrite.

## What This Slice Proves

- `crystal-qt6` can host a real `QMainWindow` editor shell with menu bar, toolbar, status bar, and dock widgets.
- A custom `EventWidget` canvas can handle paint, mouse drag, wheel zoom, key input, and PNG export from Crystal.
- A layer browser backed by Qt model/view classes is feasible for the editor-side workflow.
- The slice exits cleanly on macOS through both File -> Quit and Command-Q, including the direct `Qt6.application.quit` path after the local binding fix.
- The port can live beside the Python codebase without disturbing the original application.

## What Is Ported Here

- main window shell
- tool-selection toolbar
- layer dock with selection sync
- inspector dock
- importable background image layer with offset/scale-backed rendering
- inspector controls for background offset and scale
- Crystal slice JSON save/load for background image state and transform
- minimal terrain fill workflow with per-hex color overrides, translucent hover preview, left-drag paint, right-drag clear, adjustable fill radius, a global clear-all action, inspector fill color control plus preset swatches, and Crystal slice JSON persistence for both fills and brush radius
- object-backed border layer with edge hover feedback, click-to-place/select interaction, right-click/Delete/Edit-menu removal, inspector-based width/color/line-style editing, and Crystal slice JSON persistence
- object-backed hexside layer with edge hover feedback, click-to-place/select interaction, left-drag placement, right-drag/Delete/Edit-menu removal, inspector-based width/color/opacity editing, and Crystal slice JSON persistence
- object-backed path layer with explicit Path-tool selection, neighboring-hex-constrained two-click path creation, preview feedback, neighboring-hex-constrained endpoint hover/drag reshaping feedback, keyboard delete/cancel support, inspector-based width/color/line-style/opacity editing, duplicate/delete actions, and Crystal slice JSON persistence
- object-backed freeform path layer with world-space drag drawing, click-to-select interaction, visible control-point handles with direct point dragging on the selected stroke, whole-stroke dragging when the selected path body is dragged, right-click/Delete/Edit-menu removal, a live draw preview, inspector-based width/color/opacity editing, and Crystal slice JSON persistence
- object-backed asset layer with image-backed placement, fallback token rendering, and Crystal slice JSON persistence
- explicit asset selection via canvas clicks when the Asset tool is active, with add/duplicate/drag-move/replace-image/reset/delete actions, working snap-to-hex behavior, and inspector-based scale, rotation, opacity, snap, and image-path visibility
- object-backed text layer with renderable text objects instead of hard-coded label tuples
- add-text action plus Crystal slice JSON persistence for text objects
- basic hovered-text edit/delete actions with hover feedback in the inspector
- explicit text selection via canvas clicks when the Text tool is active, with selected-text edit/delete actions
- visible dashed selection highlight around the currently selected text object
- drag-to-move for the selected text object while the Text tool is active
- inspector-based selected-text property editing for content, font size, bold, and italic
- inspector-based selected-text alignment, color, opacity, and rotation editing
- custom map canvas with pan/zoom, hover, labels, route overlay, and counter overlay
- renderable Crystal layer seam with a real layer list feeding the canvas paint loop
- `.hexmap` project import for the Crystal-supported grid settings and layer types, including relative/builtin image path resolution and clean skipping of unsupported layer kinds
- a checked-in Crystal smoke spec for `.hexmap` import coverage plus PNG export

## What Is Still Missing

- project file serialization for `.hexmap`
- the actual command stack and undo/redo command translations
- the remaining real data-backed layer implementations from the Python app beyond background, terrain fills, borders, hexsides, paths, freeform paths, assets, and text
- asset libraries, texture libraries, palette editors, and manager dialogs
- asset-layer editing parity beyond basic create/duplicate/select/move/replace/reset/delete actions, snap-to-hex editing, inspector editing of core object properties, fallback rendering, and slice-state persistence
- background-layer editing parity beyond basic image import, transform, and slice-state persistence
- fill-layer editing parity beyond a single active fill color with preset swatches, adjustable radius, and a clear-all action, per-hex color paint/erase, and broader brush-setting persistence
- border-layer editing parity beyond straight edge placement/selection/removal, simple style editing, and slice-state persistence
- hexside-layer editing parity beyond straight shared-edge click-or-drag placement/selection/removal, simple width/color/opacity editing, and slice-state persistence
- freeform-path editing parity beyond basic world-space drag drawing, control-point reshaping, whole-stroke dragging, selection/removal, simple width/color/opacity editing, and slice-state persistence
- text-layer editing parity beyond basic selection, move, inspector editing of core object properties, add/edit/delete, and slice-state persistence
- the advanced paint, fill, border, hexside, and text tool behaviors
- SVG/PDF export parity with the Python app

## Binding Work Triggered By This Port

The first direct gap uncovered during the port spike was maximized startup. The Python app starts maximized, and the Crystal wrapper did not yet expose that window-state helper. The local `crystal-qt6` checkout was updated to add `Widget#show_maximized`, and this slice now uses it.

The first runtime shutdown issue showed up on macOS. Calling `Qt6.application.quit` directly from the File menu initially caused the app to hang during teardown. The local `crystal-qt6` checkout now queues application shutdown onto the Qt event loop, closes top-level windows first, and then quits the application when no windows remain. With that binding fix in place, both the File menu action and Command-Q have been verified to shut the slice down cleanly while using the direct `Qt6.application.quit` path again.

## Next Pressure Points

These are not all confirmed binding gaps yet, but they are the most likely places where `crystal-qt6` will need deeper work as the port expands:

- heavier `QPainter` parity for the real map layers and cache paths
- richer project/document plumbing around project I/O and dialogs
- broader verification around large model/view flows and editor-side data synchronization
- more downstream examples or specs that exercise a real multi-layer editor instead of isolated widgets
