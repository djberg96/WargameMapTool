# Crystal Port Status

This directory is a practical port spike for WargameMapTool, not a full rewrite.

## What This Slice Proves

- `crystal-qt6` can host a real `QMainWindow` editor shell with menu bar, toolbar, status bar, and dock widgets.
- A custom `EventWidget` canvas can handle paint, mouse drag, wheel zoom, key input, and PNG export from Crystal.
- A layer browser backed by Qt model/view classes is feasible for the editor-side workflow.
- The slice exits cleanly on macOS through both File -> Quit and Command-Q when shutdown follows the window close path.
- The port can live beside the Python codebase without disturbing the original application.

## What Is Ported Here

- main window shell
- tool-selection toolbar
- layer dock with selection sync
- inspector dock
- custom map canvas with pan/zoom, hover, labels, route overlay, and counter overlay
- source-map selection stub and PNG export

## What Is Still Missing

- project file parsing and serialization for `.hexmap`
- the actual command stack and undo/redo command translations
- the real layer implementations from the Python app
- asset libraries, texture libraries, palette editors, and manager dialogs
- the advanced paint, fill, path, border, hexside, and text editing tool behaviors
- SVG/PDF export parity with the Python app

## Binding Work Triggered By This Port

The first direct gap uncovered during the port spike was maximized startup. The Python app starts maximized, and the Crystal wrapper did not yet expose that window-state helper. The local `crystal-qt6` checkout was updated to add `Widget#show_maximized`, and this slice now uses it.

The first runtime shutdown issue showed up on macOS. Calling `Qt6.application.quit` directly from the File menu caused the app to hang during teardown, while routing quit through `@widget.close` exits cleanly. The port now uses the close path, and both the File menu action and Command-Q have been verified to shut the slice down cleanly. If `crystal-qt6` wants a reliable direct application-level quit on macOS, that path still needs follow-up in the binding layer.

## Next Pressure Points

These are not all confirmed binding gaps yet, but they are the most likely places where `crystal-qt6` will need deeper work as the port expands:

- heavier `QPainter` parity for the real map layers and cache paths
- richer project/document plumbing around project I/O and dialogs
- broader verification around large model/view flows and editor-side data synchronization
- application-level shutdown semantics on macOS if the binding should support direct `Application#quit` from menu actions
- more downstream examples or specs that exercise a real multi-layer editor instead of isolated widgets