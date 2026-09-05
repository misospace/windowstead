extends "res://tests/test_case.gd"

# ── Event-drawer expanded-log cache (issue #361) ──────────────────────────────
# render_event_drawer() used to rebuild a fresh Array, run six format calls,
# and join() on every event_rev bump. The fix caches the joined text and only
# recomputes it when the last 6 events actually change. This suite drives the
# real render_event_drawer() against a scene-free main.gd instance and asserts:
#   - the cached text updates exactly once per real event change
#   - an idle tick (no push_event) causes no recomputation
#   - the drawer text is byte-for-byte identical to the pre-cache behaviour
#
# Run: godot --headless --path . --script res://tests/test_event_drawer_cache.gd

## Build a scene-free main.gd with a real label + log wired in, so
## render_event_drawer() runs its full path without a scene tree.
## main.gd is loaded (not preloaded) because it references the GameState
## autoload, which is only registered once the engine has booted.
func _make_main() -> Control:
	var main_script = load("res://scripts/main.gd")
	var main = main_script.new()
	var label := Label.new()
	var log := Label.new()
	main.event_drawer_label = label
	main.event_drawer_log = log
	main.state = {"events": []}
	return main


## The pre-cache reference implementation: fresh array + six format calls +
## join(). The cached path must produce a byte-for-byte identical string.
func _reference_drawer_text(events: Array) -> String:
	var lines := []
	for i in range(mini(events.size(), 6)):
		var entry = events[i]
		lines.append("t%02d  %s" % [int(entry.tick), String(entry.get("text", ""))])
	return "\n".join(lines) if not lines.is_empty() else "No events yet."


func run_tests() -> void:
	test_idle_causes_no_recomputation()
	test_push_updates_cached_text_once()
	test_text_matches_reference_byte_for_byte()
	test_recompute_when_events_change()


func test_idle_causes_no_recomputation() -> void:
	print("\n--- idle tick causes no recomputation ---")
	var main := _make_main()
	# Seed one event so the log has content.
	main.push_event("Colony wakes up.")
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, 1, "idle: first render recomputes once")
	var after_first: int = main._drawer_log_recomputes

	# Idle: no push_event, so event_rev does not bump. render_event_drawer()
	# must early-return on the event_rev gate and recompute nothing.
	main.render_event_drawer()
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, after_first, "idle: no recomputation when event_rev unchanged")
	assert_eq(main.event_drawer_log.text, "t00  Colony wakes up.", "idle: log text preserved")
	main.free()


func test_push_updates_cached_text_once() -> void:
	print("\n--- push_event updates the cached text exactly once ---")
	var main := _make_main()
	main.push_event("First event.")
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, 1, "push: first event recomputes once")
	assert_eq(main.event_drawer_log.text, "t00  First event.", "push: log shows first event")

	# A second push changes the event list → exactly one more recompute.
	main.push_event("Second event.")
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, 2, "push: second event recomputes once more")
	assert_eq(main.event_drawer_log.text, "t00  Second event.\nt00  First event.", "push: log shows both events newest-first")

	# Idle renders after the push must not recompute again.
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, 2, "push: idle render after push does not recompute")
	main.free()


func test_text_matches_reference_byte_for_byte() -> void:
	print("\n--- drawer text is byte-for-byte identical to the reference ---")
	var main := _make_main()
	var texts := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta"]
	for i in texts.size():
		main.push_event(texts[i])
	main.render_event_drawer()

	var events: Array = main.state.get("events", [])
	assert_eq(main.event_drawer_log.text, _reference_drawer_text(events), "byte-for-byte: cached text equals reference join")
	assert_eq(main._drawer_log_text, _reference_drawer_text(events), "byte-for-byte: cached field equals reference join")

	# Empty log edge case.
	var empty_main := _make_main()
	empty_main.render_event_drawer()
	assert_eq(empty_main.event_drawer_log.text, "No events yet.", "byte-for-byte: empty log text")
	assert_eq(empty_main._drawer_log_text, "No events yet.", "byte-for-byte: empty log cached field")
	main.free()
	empty_main.free()


func test_recompute_when_events_change() -> void:
	print("\n--- recompute fires when the last 6 events change ---")
	var main := _make_main()
	main.push_event("One.")
	main.render_event_drawer()
	var count_after_one: int = main._drawer_log_recomputes
	assert_eq(count_after_one, 1, "change: first event recomputes")

	# Same event list again (no push) → no recompute.
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, count_after_one, "change: unchanged list does not recompute")

	# A new event shifts the window → recompute.
	main.push_event("Two.")
	main.render_event_drawer()
	assert_eq(main._drawer_log_recomputes, count_after_one + 1, "change: new event recomputes")
	main.free()
