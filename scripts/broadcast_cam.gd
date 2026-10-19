class_name BroadcastCam
extends Node3D
## Follows the ball. Three views: Behind (from behind the offense - best on a phone held
## upright), Sideline (the TV shot) and Overhead (the coach's film). Drag to swing round,
## wheel or pinch to zoom; picking a view again puts it back.

const VIEWS := ["Arcade", "Behind", "Sideline", "Overhead"]
var view := "Arcade"
var field: FieldView
var zoom := 1.0
var swing := 0.0
var _cam: Camera3D
var _focus := Vector3.ZERO
var _dir := 1.0
var _touches := {}
var _pinch := 0.0
var _drag := false
var input_blocked := false


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 600.0
	_cam.near = 0.3
	add_child(_cam)


func set_view(v: String) -> void:
	view = v
	zoom = 1.0
	swing = 0.0


func next_view() -> String:
	set_view(VIEWS[(VIEWS.find(view) + 1) % VIEWS.size()])
	return view


func _process(delta: float) -> void:
	if field == null:
		return
	var f := field.focus()
	_dir = lerpf(_dir, field.attack_dir(), minf(delta * 2.0, 1.0))
	_focus = _focus.lerp(f, minf(delta * 3.0, 1.0))
	var target := _focus
	var eye := Vector3.ZERO
	_cam.fov = 44.0 if view == "Arcade" else 55.0
	match view:
		"Arcade":
			# the cabinet view: high and steep from behind the offense, scrolling with the ball
			target += Vector3(0, 0, _dir * (7.0 if portrait_view() else 4.0))
			target.x *= 0.6
			var portrait2 := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
			eye = target + (Vector3(0, 46.0, -_dir * 24.0) if portrait2 else Vector3(0, 21.0, -_dir * 19.0)) * zoom
		"Behind":
			target += Vector3(0, 0, _dir * 10.0)
			var portrait := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
			eye = target + (Vector3(0, 19.0, -_dir * 25.0) if portrait else Vector3(0, 12.0, -_dir * 20.0)) * zoom
		"Sideline":
			target.x = clampf(target.x * 0.4, -8.0, 8.0)
			eye = target + Vector3(-30.0, 15.0, 0) * zoom
		"Overhead":
			eye = target + Vector3(0, 55.0, -_dir * 6.0) * zoom
	# swing round the focus
	var off := eye - target
	off = off.rotated(Vector3.UP, swing)
	var want := target + off
	_cam.global_position = _cam.global_position.lerp(want, minf(delta * 4.0, 1.0)) if _cam.global_position != Vector3.ZERO else want
	_cam.look_at(target, Vector3.UP if view != "Overhead" else Vector3(0, 0, _dir))


func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.35, 2.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.35, 2.5)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag and _touches.size() < 2:
		swing -= (event as InputEventMouseMotion).relative.x * 0.006
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch = 0.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 2:
			var pts := _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch > 0.0:
				zoom = clampf(zoom * _pinch / maxf(d, 1.0), 0.35, 2.5)
			_pinch = d


func portrait_view() -> bool:
	var r := get_viewport().get_visible_rect().size
	return r.y > r.x
