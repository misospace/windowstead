extends "res://tests/test_case.gd"

# =============================================================================
# Tests for the web unload flush in GameState (issue #403).
#
# On the web build, closing the tab never delivers
# NOTIFICATION_WM_CLOSE_REQUEST to the wasm runtime, so the debounced save
# (PERSIST_INTERVAL_TICKS = 10) can silently lose up to ~10 ticks of
# progress. register_web_unload_flush() wraps a persist callable with
# JavaScriptBridge.create_callback (Godot 4.7: takes one Callable, returns
# a JavaScriptObject reference that must be retained) and assigns the
# reference to window.onbeforeunload through the window interface, so
# closing the tab forces a final persist(true) before the page tears down.
# A single property assignment (rather than addEventListener) is what
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
# is exercised by stubbing _os_has_feature_hook, _js_create_callback_hook,
# and _js_set_onbeforeunload_hook with closures and asserting on what was
# passed through. The main.gd binding is asserted structurally: it must
# bind a JavaScriptBridge-shaped wrapper (one Array argument) that forces
# persist(true), not persist() itself (whose debounce would skip the
# unload write).
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _create_callback_calls: Array = []
var _set_handler_calls: Array = []
var _prior_use_local_storage: bool
var _prior_create_callback_hook: Callable
var _prior_set_handler_hook: Callable
var _prior_os_hook: Callable
var _prior_unload_ref: Variant

func run_tests() -> void:
	setup()
	flow_register_returns_false_when_off_web()
	flow_register_returns_false_when_local_storage_unavailable()
	flow_register_invokes_create_callback_for_persist_callable()
	flow_register_installs_created_reference_on_window()
	flow_register_returns_true_and_retains_reference()
	flow_register_returns_false_when_create_callback_fails()
	flow_register_returns_false_when_installer_fails()
	flow_register_is_noop_off_web_without_calling_hooks()
	flow_main_binds_forced_flush_wrapper()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	# Snapshot so teardown can restore the production hooks and state.
	_prior_use_local_storage = _gs.use_local_storage
	_prior_create_callback_hook = _gs._js_create_callback_hook
	_prior_set_handler_hook = _gs._js_set_onbeforeunload_hook
	_prior_os_hook = _gs._os_has_feature_hook
	_prior_unload_ref = _gs._web_unload_callback_ref
	_create_callback_calls = []
	_set_handler_calls = []

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use_local_storage
		_gs._js_create_callback_hook = _prior_create_callback_hook
		_gs._js_set_onbeforeunload_hook = _prior_set_handler_hook
		_gs._os_has_feature_hook = _prior_os_hook
		_gs._web_unload_callback_ref = _prior_unload_ref
		_gs.queue_free()
	_gs = null
	_create_callback_calls = []
	_set_handler_calls = []

# Helper: arm the three hooks with pass-through stubs on the web branch.
# create_callback returns the fixed literal "__cb_ref__" so downstream
# flows can assert the exact value that gets installed and retained.
func _arm_web_stubs() -> void:
	_create_callback_calls = []
	_set_handler_calls = []
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_create_callback_hook = func(cb: Callable) -> Variant:
		_create_callback_calls.append(cb)
		return "__cb_ref__"
	_gs._js_set_onbeforeunload_hook = func(ref: Variant) -> bool:
		_set_handler_calls.append(ref)
		return true

# 1) register_web_unload_flush returns false when OS.has_feature("web")
#    reports false (desktop, headless). No hooks are called because the
#    function short-circuits before doing any work (issue #403 acceptance).
func flow_register_returns_false_when_off_web() -> void:
	_create_callback_calls = []
	_set_handler_calls = []
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(_feature: String) -> bool:
		return false
	_gs._js_create_callback_hook = func(_cb: Callable) -> Variant:
		_create_callback_calls.append(_cb)
		return "cb"
	_gs._js_set_onbeforeunload_hook = func(_ref: Variant) -> bool:
		_set_handler_calls.append(_ref)
		return true
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false off-web")
	assert_eq(_create_callback_calls.size(), 0, "off-web register does not call create_callback hook")
	assert_eq(_set_handler_calls.size(), 0, "off-web register does not call set handler hook")

# 2) register_web_unload_flush returns false when localStorage is
#    unavailable, even on a web build. Without localStorage there is no
#    place to persist to, so a forced write would just fail; the listener
#    must not register (issue #403 acceptance).
func flow_register_returns_false_when_local_storage_unavailable() -> void:
	_create_callback_calls = []
	_set_handler_calls = []
	_gs.use_local_storage = false
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_create_callback_hook = func(_cb: Callable) -> Variant:
		_create_callback_calls.append(_cb)
		return "cb"
	_gs._js_set_onbeforeunload_hook = func(_ref: Variant) -> bool:
		_set_handler_calls.append(_ref)
		return true
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false when localStorage is unavailable")
	assert_eq(_create_callback_calls.size(), 0, "no-localStorage register does not call create_callback hook")
	assert_eq(_set_handler_calls.size(), 0, "no-localStorage register does not call set handler hook")

# 3) On the web branch, register_web_unload_flush wraps the persist
#    callable itself (not an object/method pair — Godot 4.7's
#    create_callback takes one Callable) exactly once (issue #403
#    acceptance: persist is invoked from JS).
func flow_register_invokes_create_callback_for_persist_callable() -> void:
	_arm_web_stubs()
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_true(registered, "register returns true on the web branch with localStorage")
	assert_eq(_create_callback_calls.size(), 1, "create_callback invoked exactly once")
	var passed: Callable = _create_callback_calls[0]
	assert_eq(passed.get_object(), self, "create_callback invoked with the persist callable's bound object")
	assert_eq(String(passed.get_method()), "_persist_target", "create_callback invoked with the persist callable's method name")

# 4) The reference returned by create_callback is the exact value handed
#    to the window.onbeforeunload installer, once. A single property
#    assignment is what bounds the browser to one callback per unload
#    (issue #403 acceptance: no save duplication).
func flow_register_installs_created_reference_on_window() -> void:
	_arm_web_stubs()
	_gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_eq(_set_handler_calls.size(), 1, "installer called exactly once (single assignment, no addEventListener)")
	assert_eq(_set_handler_calls[0], "__cb_ref__", "installer receives the created callback reference")

# 5) On success the reference is retained on the node. Godot's
#    JavaScriptBridge docs require the reference to be kept until the
#    callback happens, or it won't be called at all — losing the reference
#    would silently break the unload flush on web.
func flow_register_returns_true_and_retains_reference() -> void:
	_arm_web_stubs()
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_true(registered, "register returns true when create_callback and installer succeed")
	assert_eq(_gs._web_unload_callback_ref, "__cb_ref__", "created reference is retained on the node")

# 6) When create_callback fails (returns null — e.g. the web runtime
#    refused to create the reference), register returns false and the
#    installer is never reached; the listener must not be considered
#    installed without a live reference.
func flow_register_returns_false_when_create_callback_fails() -> void:
	# Earlier flows may have retained a reference on this node; start from
	# a clean field so the "retains no reference" assertion is meaningful.
	_create_callback_calls = []
	_set_handler_calls = []
	_gs._web_unload_callback_ref = null
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_create_callback_hook = func(_cb: Callable) -> Variant:
		_create_callback_calls.append(_cb)
		return null
	_gs._js_set_onbeforeunload_hook = func(ref: Variant) -> bool:
		_set_handler_calls.append(ref)
		return true
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false when create_callback fails")
	assert_eq(_set_handler_calls.size(), 0, "installer is not called when create_callback fails")
	assert_eq(_gs._web_unload_callback_ref, null, "failed registration retains no reference")

# 7) When the installer reports failure (window interface unavailable),
#    register returns false so callers can observe the broken
#    registration.
func flow_register_returns_false_when_installer_fails() -> void:
	# Same clean-field rationale as the create_callback-failure flow.
	_create_callback_calls = []
	_set_handler_calls = []
	_gs._web_unload_callback_ref = null
	_gs.use_local_storage = true
	_gs._os_has_feature_hook = func(feature: String) -> bool:
		return feature == "web"
	_gs._js_create_callback_hook = func(_cb: Callable) -> Variant:
		return "__cb_ref__"
	_gs._js_set_onbeforeunload_hook = func(_ref: Variant) -> bool:
		_set_handler_calls.append(_ref)
		return false
	var registered: bool = _gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_false(registered, "register returns false when the installer fails")
	assert_eq(_gs._web_unload_callback_ref, null, "failed install retains no reference")

# 8) Off-web, the registration is a strict no-op — neither hook fires and
#    no reference is retained. This is what guarantees the desktop
#    NOTIFICATION_WM_CLOSE_REQUEST path stays unchanged (issue #403
#    acceptance).
func flow_register_is_noop_off_web_without_calling_hooks() -> void:
	# Reset the cross-flow logs so a stray call from this flow is the only
	# entry being asserted on (the earlier flows leave their own entries
	# behind, and we want a true delta, not a global count).
	_create_callback_calls = []
	_set_handler_calls = []
	_gs._web_unload_callback_ref = null
	_gs.use_local_storage = false
	_gs._os_has_feature_hook = func(_feature: String) -> bool:
		return false
	_gs._js_create_callback_hook = func(_cb: Callable) -> Variant:
		_create_callback_calls.append("UNEXPECTED")
		return "cb"
	_gs._js_set_onbeforeunload_hook = func(_ref: Variant) -> bool:
		_set_handler_calls.append("UNEXPECTED")
		return true
	_gs.register_web_unload_flush(Callable(self, "_persist_target"))
	assert_eq(_create_callback_calls.size(), 0, "off-web register is a strict no-op (no create_callback)")
	assert_eq(_set_handler_calls.size(), 0, "off-web register is a strict no-op (no installer)")
	assert_eq(_gs._web_unload_callback_ref, null, "off-web register retains no reference")

# 9) main.gd must install the listener from _ready() and bind it to a
#     JavaScriptBridge-shaped wrapper that FORCES the write: a bare
#     Callable(self, "persist") would receive the unload event as its
#     force flag and could still be skipped by the PERSIST_INTERVAL_TICKS
#     debounce — the exact loss issue #403 is about. We check the source
#     rather than booting main.gd because the main scene expects a
#     populated scene tree; the structural assertion is what prevents an
#     accidental revert of the binding in a refactor.
func flow_main_binds_forced_flush_wrapper() -> void:
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	assert_true(main_src.find("GameState.register_web_unload_flush") != -1,
		"main.gd calls GameState.register_web_unload_flush")
	assert_true(main_src.find("Callable(self, \"_flush_save_on_unload\")") != -1,
		"main.gd binds the unload listener to _flush_save_on_unload")
	assert_true(main_src.find("func _flush_save_on_unload(_args: Array)") != -1,
		"_flush_save_on_unload matches the JavaScriptBridge one-Array-argument contract")
	# The wrapper must force the write, not rely on the debounce window.
	var wrapper_start := main_src.find("func _flush_save_on_unload")
	assert_true(wrapper_start != -1, "main.gd defines _flush_save_on_unload")
	var wrapper_body := main_src.substr(wrapper_start, 240)
	assert_true(wrapper_body.find("persist(true)") != -1,
		"_flush_save_on_unload calls persist(true) so the debounced save is forced")

# ── Test target method ───────────────────────────────────────────────────────
# Stand-in for the real persist callable so the create_callback hook can
# capture the bound (object, method) pair and verify it points at the right
# method on the right node.
func _persist_target() -> void:
	pass
