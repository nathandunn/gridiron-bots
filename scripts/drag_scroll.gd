class_name DragScroll
extends ScrollContainer
## A scroll panel that scrolls the way a phone does: put a finger anywhere on it - on a card, a
## button, a row of stats - and slide. A slide that moves more than a few pixels is a scroll, and
## the button under the finger doesn't fire when it lifts; a quick flick keeps gliding and slows.
## A plain tap is still a tap. Text boxes keep their own dragging (selecting text).

const SLOP := 10.0          # pixels before a touch becomes a scroll
const FRICTION := 4.5       # how fast a fling slows (per second)

var _down := false
var _dragging := false
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _vel := 0.0             # pixels a second, for the fling
var _fling := 0.0
var _last_t := 0
var _pos := 0.0             # where we have scrolled to, in fractions of a pixel (scroll_vertical is whole pixels)


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# a slim bar as a hint of where you are; it isn't needed to scroll
	var bar := get_v_scroll_bar()
	bar.custom_minimum_size.x = 4
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.35, 0.95, 1.0, 0.45)
	grab.set_corner_radius_all(2)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(st, grab)
	bar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())


func _over_text_box(pos: Vector2) -> bool:
	var c := _control_at(pos)
	while c != null and c != self:
		if c is TextEdit or c is LineEdit:
			return true
		c = c.get_parent() as Control
	return false


func _control_at(pos: Vector2) -> Control:
	# the deepest visible control under a point, inside this panel
	var best: Control = null
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Control and (ch as Control).is_visible_in_tree() and (ch as Control).get_global_rect().has_point(pos):
				best = ch
				stack.append(ch)
	return best


func _press(pos: Vector2) -> void:
	if not is_visible_in_tree() or not get_global_rect().has_point(pos) or _over_text_box(pos):
		return
	_down = true
	_dragging = false
	_start = pos
	_last = pos
	_vel = 0.0
	_fling = 0.0
	_pos = float(scroll_vertical)
	_last_t = Time.get_ticks_msec()


func _move(pos: Vector2) -> void:
	if not _down:
		return
	if not _dragging and absf(pos.y - _start.y) > SLOP:
		_dragging = true
		_cancel_press()
	if _dragging:
		var dy := pos.y - _last.y
		_scroll_to(_pos - dy)
		var now := Time.get_ticks_msec()
		var dt := maxf((now - _last_t) / 1000.0, 0.001)
		_vel = lerpf(_vel, -dy / dt, 0.4)
		_last_t = now
		get_viewport().set_input_as_handled()
	_last = pos


## The finger went down on a button and is now scrolling: let go of the button far away from it,
## so it un-presses without firing.
func _cancel_press() -> void:
	var far := Vector2(-10000, -10000)
	var away := InputEventMouseMotion.new()
	away.position = far
	away.global_position = far
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = far
	up.global_position = far
	var vp := get_viewport()
	vp.push_input.call_deferred(away)
	vp.push_input.call_deferred(up)


func _release() -> bool:
	if not _down:
		return false
	_down = false
	if _dragging:
		_dragging = false
		# a flick keeps going; a slide that stopped before lifting doesn't
		if Time.get_ticks_msec() - _last_t < 80:
			_fling = clampf(_vel, -4000.0, 4000.0)
		return true
	return false


func _input(event: InputEvent) -> void:
	# Phones turn each touch into mouse events as well, so the mouse events are all we follow.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.position.x < -9000.0:
			return   # our own let-go, on its way to the button
		if mb.pressed:
			_press(mb.position)
		elif _release():
			# lifted after a scroll: that wasn't a tap on whatever is underneath
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.position.x < -9000.0:
			return   # our own move-away, telling the button the finger left it
		_move(mm.position)
	elif event is InputEventScreenDrag and _dragging:
		get_viewport().set_input_as_handled()   # we are already scrolling; no second scroll


func _process(delta: float) -> void:
	if absf(_fling) > 20.0 and not _down:
		_scroll_to(_pos + _fling * delta)
		_fling *= exp(-FRICTION * delta)
	else:
		_fling = 0.0


## Keep the fraction of a pixel too: small finger moves in either direction add up, instead of
## being rounded away (which made slow swipes one way stick).
func _scroll_to(y: float) -> void:
	var top := maxf(get_v_scroll_bar().max_value - size.y, 0.0)
	_pos = clampf(y, 0.0, top)
	scroll_vertical = int(roundf(_pos))
	if _pos <= 0.0 or _pos >= top:
		_fling = 0.0
