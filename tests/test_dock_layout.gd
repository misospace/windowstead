extends "res://tests/test_case.gd"

# ── Dock anchor layout orchestration tests (#279 item 11) ─────────────────────
# apply_anchor_layout() reparents the header labels, status column, and HUD
# row between the bottom-strip and side-dock families — the largest UX
# surface in the dock, previously untested. main.gd is instantiated WITHOUT
# entering the tree (so _ready never runs and no autoloads are needed); the
# node references it @onready-resolves in production are assigned manually.

func run_tests() -> void:
	var main = load("res://scripts/main.gd").new()
	var refs := _build_layout_harness(main)

	# ── Bottom family ──
	main.apply_anchor_geometry("bottom")
	main.apply_anchor_layout("bottom")
	assert_eq(main.anchor_family, "bottom", "bottom: anchor family applied")
	assert_true(main.bottom_header_row != null, "bottom: header row created")
	assert_eq(main.bottom_header_row.get_parent(), refs.left_column, "bottom: header row lives in left column")
	assert_eq(refs.resource_label.get_parent(), main.bottom_header_row, "bottom: resource label in bottom header")
	assert_eq(refs.status_label.get_parent(), main.bottom_status_column, "bottom: status label in bottom status column")
	assert_eq(refs.hud_row.get_parent(), main.bottom_button_row, "bottom: HUD row in bottom button row")
	assert_true(main.bottom_header_row.visible, "bottom: bottom header visible")
	assert_eq(refs.status_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "bottom: status right-aligned")
	assert_eq(refs.world_grid.columns, main.grid_w, "bottom: grid columns match bottom dims")

	# ── Switch to side family ──
	main.apply_anchor_geometry("left")
	main.apply_anchor_layout("left")
	assert_eq(main.anchor_family, "vertical", "side: anchor family applied")
	assert_true(main.side_header_row != null, "side: header row created")
	assert_eq(main.side_header_row.get_parent(), refs.left_column, "side: header row lives in left column")
	assert_eq(refs.resource_label.get_parent(), main.side_header_row, "side: resource label in side header")
	assert_eq(refs.status_label.get_parent(), main.side_status_column, "side: status label in side status column")
	assert_eq(refs.hud_row.get_parent(), main.side_button_row, "side: HUD row in side button row")
	assert_false(main.bottom_header_row.visible, "side: bottom header hidden")
	assert_true(main.side_header_row.visible, "side: side header visible")
	assert_eq(refs.status_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT, "side: status left-aligned")
	assert_eq(refs.world_grid.columns, main.grid_w, "side: grid columns match side dims")

	# ── And back — parentage must be fully restored ──
	main.apply_anchor_geometry("bottom")
	main.apply_anchor_layout("bottom")
	assert_eq(refs.resource_label.get_parent(), main.bottom_header_row, "return: resource label back in bottom header")
	assert_eq(refs.status_label.get_parent(), main.bottom_status_column, "return: status label back in bottom column")
	assert_eq(refs.hud_row.get_parent(), main.bottom_button_row, "return: HUD row back in bottom button row")
	assert_true(main.bottom_header_row.visible, "return: bottom header visible again")
	assert_false(main.side_header_row.visible, "return: side header hidden again")
	# HUD row internal ordering is normalized by the shared tail.
	assert_eq(refs.hud_row.get_child(0), refs.menu_button, "return: menu button first in HUD row")
	assert_eq(refs.hud_row.get_child(2), refs.menu_hint, "return: menu hint last in HUD row")

	main.free()


## Wire up the minimal node graph apply_anchor_layout touches, returning the
## nodes the assertions need. Mirrors the scene structure without loading it.
func _build_layout_harness(main: Control) -> Dictionary:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	main.add_child(backdrop)

	var root_box := BoxContainer.new()
	backdrop.add_child(root_box)
	var left_column := VBoxContainer.new()
	root_box.add_child(left_column)
	var world_panel := PanelContainer.new()
	left_column.add_child(world_panel)
	var world_grid := GridContainer.new()
	world_panel.add_child(world_grid)
	var sidebar_scroll := ScrollContainer.new()
	root_box.add_child(sidebar_scroll)

	var resource_label := Label.new()
	left_column.add_child(resource_label)
	var status_label := Label.new()
	left_column.add_child(status_label)

	var hud_row := HBoxContainer.new()
	left_column.add_child(hud_row)
	var menu_button := Button.new()
	hud_row.add_child(menu_button)
	var build_mode_button := Button.new()
	hud_row.add_child(build_mode_button)
	var menu_hint := Label.new()
	hud_row.add_child(menu_hint)

	main.root_box = root_box
	main.left_column = left_column
	main.world_panel = world_panel
	main.world_grid = world_grid
	main.sidebar_scroll = sidebar_scroll
	main.resource_label = resource_label
	main.status_label = status_label
	main.menu_button = menu_button
	main.build_mode_button = build_mode_button
	main.menu_hint = menu_hint

	return {
		"left_column": left_column,
		"world_grid": world_grid,
		"resource_label": resource_label,
		"status_label": status_label,
		"hud_row": hud_row,
		"menu_button": menu_button,
		"menu_hint": menu_hint,
	}
