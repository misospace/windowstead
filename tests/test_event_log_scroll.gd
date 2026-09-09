extends "res://tests/test_case.gd"

# ── Event-log RichTextLabel scroll preservation (issue #380) ──────────────────
# _render_event_log() used to wipe the sidebar RichTextLabel with
# event_log.clear() and rebuild it via append_text() on every event_rev bump.
# clear() resets the internal scroll state, so a new event (a build finishing,
# a worker break, an ambient event, a recruit click — anywhere push_event runs)
# snapped an already-scrolling log back to the top. The fix captures the
# v-scroll value before clear() and writes it back after the append.
#
# This suite drives the real _render_event_log() against a scene-free main.gd
# instance with a real RichTextLabel and asserts that the player's scroll
# position survives an event_rev bump.
#
# Run: godot --headless --path . --script res://tests/test_event_log_scroll.gd

## Build a scene-free main.gd with a real RichTextLabel wired in, so
## _render_event_log() runs its full path without a scene tree. main.gd is
## loaded (not preloaded) because it references the GameState autoload, which
## is only registered once the engine has booted.
##
## scroll_following is enabled because that is the mode in which the clear() +
## append_text() rebuild actually resets the player's scroll position: with
## scroll-following on, the next layout pass snaps the bar back to the newest
## line, discarding wherever the player had scrolled. That is the regression
## this suite guards against.
func _make_main() -> Control:
	var main_script = load("res://scripts/main.gd")
	var main = main_script.new()
	var log := RichTextLabel.new()
	log.scroll_active = true
	log.bbcode_enabled = false
	log.scroll_following = true
	# Give the log a bounded height so a long event list becomes scrollable.
	log.custom_minimum_size = Vector2(200, 120)
	root.add_child(log)
	main.event_log = log
	main.state = {"events": []}
	return main


## Seed enough events that the log content exceeds the viewport, so the
## v-scroll bar has a non-zero max and a scroll position is meaningful.
func _seed_scrollable(main: Control) -> void:
	for i in 30:
		main.push_event("Event %d" % i)
	main._render_event_log()


func run_tests() -> void:
	await test_scroll_survives_event_rev_bump()
	await test_scroll_preserved_across_multiple_bumps()
	await test_idle_render_does_not_touch_scroll()


func test_scroll_survives_event_rev_bump() -> void:
	print("\n--- scroll position survives a single event_rev bump ---")
	var main := _make_main()
	await process_frame
	_seed_scrollable(main)
	await process_frame

	var scroll_bar: VScrollBar = main.event_log.get_v_scroll_bar()
	assert_true(scroll_bar != null, "scroll: v-scroll bar exists")
	assert_true(scroll_bar.max_value > 0.0, "scroll: log is scrollable (max > 0)")

	# The player scrolls down to read older events (away from the newest line).
	var target := 50.0
	scroll_bar.value = target
	assert_eq(scroll_bar.value, target, "scroll: player scrolled to target")

	# A new event arrives -> event_rev bumps -> _render_event_log rebuilds.
	main.push_event("New event arrives")
	main._render_event_log()
	# The scroll reset happens in the next layout pass, so let a frame elapse
	# before asserting the position held.
	await process_frame

	# The rebuild must not have snapped the log back to the top.
	assert_eq(scroll_bar.value, target, "scroll: position preserved after event_rev bump")

	# The new event is still rendered (the rebuild actually happened). The list
	# is bounded at MAX_EVENT_LOG, so the size stays capped while the newest
	# entry moves to the front.
	var events: Array = main.state.get("events", [])
	assert_eq(events.size(), 20, "scroll: event list stays bounded at MAX_EVENT_LOG")
	assert_eq(String(events[0].get("text", "")), "New event arrives", "scroll: newest event is first")
	main.free()


func test_scroll_preserved_across_multiple_bumps() -> void:
	print("\n--- scroll position survives repeated event_rev bumps ---")
	var main := _make_main()
	await process_frame
	_seed_scrollable(main)
	await process_frame

	var scroll_bar: VScrollBar = main.event_log.get_v_scroll_bar()
	var target := 80.0
	scroll_bar.value = target

	# Several events arrive in a row; each one bumps event_rev and rebuilds.
	for i in 5:
		main.push_event("Burst event %d" % i)
		main._render_event_log()
		await process_frame

	assert_eq(scroll_bar.value, target, "scroll: position preserved across 5 bumps")
	main.free()


func test_idle_render_does_not_touch_scroll() -> void:
	print("\n--- idle render (no event_rev bump) leaves scroll untouched ---")
	var main := _make_main()
	await process_frame
	_seed_scrollable(main)
	await process_frame

	var scroll_bar: VScrollBar = main.event_log.get_v_scroll_bar()
	var target := 60.0
	scroll_bar.value = target

	# No push_event: event_rev is unchanged, so _render_event_log early-returns.
	main._render_event_log()
	main._render_event_log()

	assert_eq(scroll_bar.value, target, "scroll: idle render leaves position untouched")
	main.free()
