extends "res://tests/test_case.gd"

# =============================================================================
# Tests for the web unload flush in GameState (issue #403).
#
# On the web build, closing the tab never delivers
# NOTIFICATION_WM_CLOSE_REQUEST to the wasm runtime, so the debounced save
# (PERSIST_INTERVAL_TICKS = 10) can silently lose up to ~10 ticks of
# progress. register_web_unload_flush() assigns a persist callable to
# `window.onbeforeunload` via JavaScriptBridge.create_callback so closing
# the tab forces a final persist(true) before the page tears down. A
# single property assignment (rather than addEventListener) is what
# guarantees "at most one extra persist per unload" (issue #403
# acceptance).
#
# Acceptance criteria (issue #403):
#   - The callback is registered only when OS.has_feature("web") AND the
#     localStorage check already used for use_local_storage passes, so the
#     desktop NOTIFICATION_WM_CLOSE_REQUEST path keeps working unchanged.
#   - The handler forces at most one extra persist per unload (no
#     double-write regressions).
#
# Headless test runners can't actually run a browser, so the registration
# is exercised by stubbing _os_has_feature_hook, _js_eval_hook, and
# _js_create_callback_hook with closures and asserting on what was passed
# through. The static build statement is asserted against a literal callback
# so a future refactor that breaks the JS shape fails fast.
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _eval_calls: Array = []
var _create_callback_calls: Array = []
var _prior_use_local_storage: bool
var _prior_eval_hook: Callable
var _prior_create_callback_hook: Callable
var _prior_os_hook: Callable

func run_tests() -> void:
	setup()
	flow_static_register_eval_binds_beforeunload()
	flow_static_register_eval_substitutes_callback_literal()
	flow_register_returns_false_when_off_web()
	flow_register_returns_false_when_local_storage_unavailable()
	flow_register_invokes_create_callback_for_persist_callable()
	flow_register_invokes_eval_with_beforeunload_assign_statement()
	flow_register_returns_true_when_eval_succeeds()
	flow_register_returns_false_when_eval_fails()
	flow_register_is_noop_off_web_without_calling_hooks()
	flow_main_calls_register_from_ready()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	# Snapshot so teardown can restore the production hooks and state.
	_prior_use_local_storage = _gs.use_local_storage
	_prior_eval_hook = _gs._js_eval_hook
	_prior_create_callback_hook = _gs._js_create_callback_hook
	_prior_os_hook = _gs._os_has_feature_hook
	_eval_calls = []
	_create_callback_calls = []

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use_local_storage
		_gs._js_eval_hook = _prior_eval_hook
		_gs._js_create_callback_hook = _prior_create_callback_hook
		_gs._os_has_feature_hook = _prior_os_hook
		_gs.queue_free()
	_gs = null
	_eval_calls = []
	_create_callback_calls = []

# 1) build_web_unload_register_eval assigns the callback to
#    `window.onbeforeunload`, matching the documented Godot 4
#    JavaScriptBridge pattern. A single property assignment is what
#    guarantees the "at most one extra persist per unload" acceptance
#    criterion (issue #403).
func flow_static_register_eval_binds_beforeunload() -> void:
	var stmt: String = GameState.build_web_unload_register_eval("cb")
	assert_true(stmt.find("window.onbeforeunload") != -1, "register eval assigns window.onbeforeunload")
	assert_eq(stmt.count("="), 1, "register eval is a single assignment (no addEventListener, no double-write)")

# 2) The callback literal passed to the static helper is interpolated
#    once into the statement. A regression that wraps the literal in
#    extra quoting (which would break the JS function-reference syntax
#    that JavaScriptBridge.create_callback relies on) shows up here.
func flow_static_register_eval_substitutes_callback_literal() -> void:
	var stmt: String = GameState.build_web_unload_register_eval("__mock_fn__")
	assert_eq(stmt.count("__mock_fn__"), 1, "callback literal appears exactly once")
	assert_false(stmt.find("\"__mock_fn__\"") != -1,
		"callback literal is not wrapped in quotes (would break JS function reference)")

# 3) register_web_unload_flush returns false when OS.has_feature("web")
#    reports false (desktop, headless). No hooks are called because the
#    function short-circuits before doing any work (issue #403 acceptance).
func flow_register_returns_false_when_off_web() -> void:
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(_feature: String) -> bool:
		return false
	_gs._js_eval_hook = func(code: String) -> Variant:
		_eval_calls.append(code)
		return true
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		_create_callback_calls.append([_obj, _method])
		return "cb"
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false off-web")
	assert_eq(_eval_calls.size(), 0, "off-web register does not call eval hook")
	assert_eq(_create_callback_calls.size(), 0, "off-web register does not call create_callback hook")

# 4) register_web_unload_flush returns false when localStorage is
#    unavailable, even on a web build. Without localStorage there is no
#    place to persist to, so a forced write would just fail; the listener
#    must not register (issue #403 acceptance).
func flow_register_returns_false_when_local_storage_unavailable() -> void:
	_gs.use_local_storage = false
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_eval_hook = func(code: String) -> Variant:
		_eval_calls.append(code)
		return true
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		_create_callback_calls.append([_obj, _method])
		return "cb"
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false when localStorage is unavailable")
	assert_eq(_eval_calls.size(), 0, "no-localStorage register does not call eval hook")
	assert_eq(_create_callback_calls.size(), 0, "no-localStorage register does not call create_callback hook")

# 5) On the web branch, register_web_unload_flush wraps the persist callable
#    via JavaScriptBridge.create_callback so the browser can invoke it.
#    The hook is invoked exactly once with the persist callable's bound
#    object and method (issue #403 acceptance: persist is invoked from JS).
func flow_register_invokes_create_callback_for_persist_callable() -> void:
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_eval_hook = func(_code: String) -> Variant:
		return true
	_gs._js_create_callback_hook = func(obj: Object, method: StringName) -> Variant:
		_create_callback_calls.append([obj, method])
		return "__cb__"
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_true(registered, "register returns true on the web branch with localStorage")
	assert_eq(_create_callback_calls.size(), 1, "create_callback invoked exactly once")
	assert_eq(_create_callback_calls[0][0], self, "create_callback invoked with persist callable's bound object")
	assert_eq(String(_create_callback_calls[0][1]), "_persist_target", "create_callback invoked with persist callable's method name")

# 6) The eval hook receives the window.onbeforeunload assignment
#    statement built from the static helper, with the callback's string
#    representation interpolated in. This is the only statement the
#    registration issues, so a regression that adds extra side-effects
#    shows up here.
func flow_register_invokes_eval_with_beforeunload_assign_statement() -> void:
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_eval_hook = func(code: String) -> Variant:
		_eval_calls.append(code)
		return true
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		return "__cb_literal__"
	_gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_eq(_eval_calls.size(), 1, "register issues exactly one eval statement")
	assert_eq(_eval_calls[0], GameState.build_web_unload_register_eval("__cb_literal__"),
		"eval statement is the static-helper output with the callback literal")

# 7) When the eval hook reports success (returns non-null), register
#    returns true so callers can log / observe the registration.
func flow_register_returns_true_when_eval_succeeds() -> void:
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_eval_hook = func(_code: String) -> Variant:
		return true
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		return "cb"
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_true(registered, "register returns true when the eval hook succeeds")

# 8) When the eval hook reports failure (returns null — JavaScriptBridge
#    converts thrown errors and undefined returns to null), register
#    returns false. The listener must not be considered installed if the
#    addEventListener call did not actually run.
func flow_register_returns_false_when_eval_fails() -> void:
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_eval_hook = func(_code: String) -> Variant:
		return null
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		return "cb"
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false when the eval hook fails")

# 9) Off-web, the registration is a strict no-op — neither hook fires. This
#    is what guarantees the desktop NOTIFICATION_WM_CLOSE_REQUEST path
#    stays unchanged (issue #403 acceptance).
func flow_register_is_noop_off_web_without_calling_hooks() -> void:
	# Reset the cross-flow logs so a stray call from this flow is the only
	# entry being asserted on (the earlier flows leave their own entries
	# behind, and we want a true delta, not a global count).
	_eval_calls = []
	_create_callback_calls = []
	_gs.use_local_storage = false
	_gs._os_has_feature_hook = func(_feature: String) -> bool:
		return false
	_gs._js_eval_hook = func(_code: String) -> Variant:
		_eval_calls.append("UNEXPECTED")
		return true
	_gs._js_create_callback_hook = func(_obj: Object, _method: StringName) -> Variant:
		_create_callback_calls.append("UNEXPECTED")
		return "cb"
	_gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_eq(_eval_calls.size(), 0, "off-web register is a strict no-op (no eval)")
	assert_eq(_create_callback_calls.size(), 0, "off-web register is a strict no-op (no create_callback)")

# 10) main.gd's _ready() must call GameState.register_web_unload_flush so
#     the listener is installed on every fresh web build. We check the
#     source for the call rather than booting main.gd because the main
#     scene expects a populated scene tree; the structural assertion is
#     what prevents an accidental drop of the registration in a refactor.
func flow_main_calls_register_from_ready() -> void:
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	assert_true(main_src.find("GameState.register_web_unload_flush") != -1,
		"main.gd calls GameState.register_web_unload_flush")
	# The argument must be a Callable bound to self.persist so the listener
	# forces a debounced-save flush and not some other action.
	assert_true(main_src.find("Callable(self, \"persist\")") != -1,
		"main.gd binds register_web_unload_flush to its own persist method")

# ── Test target method ───────────────────────────────────────────────────────
# Stand-in for the real persist callable so the create_callback hook can
# capture the bound (object, method) pair and verify it points at the right
# method on the right node.
func _persist_target() -> void:
	pass