class_name BroadcastCam
extends Node3D
## Follows the ball. Three views: Behind (from behind the offense - best on a phone held
## upright), Sideline (the TV shot) and Overhead (the coach's film). The camera is not
## steered by mouse or touch: each view frames the play the same way every time.

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
	_cam.fov = 40.0 if view == "Arcade" else 55.0
	match view:
		"Arcade":
			# the cabinet view: always the same picture - sideline to sideline, a fixed stretch
			# of field around the ball - from the same steep angle, on any screen shape. The
			# camera backs off until that whole box fits between the scoreboard and the buttons.
			target = Vector3(0, 0, _focus.z + _dir * ARCADE_AHEAD)
			eye = target + _arcade_offset()
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
	if view == "Arcade":
		_cam.global_position = want   # the fitted distance is exact; the focus itself is smoothed
	else:
		_cam.global_position = _cam.global_position.lerp(want, minf(delta * 4.0, 1.0)) if _cam.global_position != Vector3.ZERO else want
	_cam.look_at(target, Vector3.UP if view != "Overhead" else Vector3(0, 0, _dir))


const STEERABLE := false   # drag to swing, wheel/pinch to zoom: off


func _unhandled_input(event: InputEvent) -> void:
	if input_blocked or not STEERABLE:
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


## The Arcade box: the full width of the field (plus the rails) and BACK yards behind to AHEAD
## yards in front of the ball; the screen space kept clear for the scoreboard and the buttons.
const ARCADE_PITCH := 0.95        # radians below the horizon
const ARCADE_BACK := 12.0
const ARCADE_FRONT := 26.0
const ARCADE_AHEAD := 7.0         # the box is centred this far ahead of the ball
const ARCADE_TOP := 0.2           # fraction of the screen height the scoreboard covers
const ARCADE_BOTTOM := 0.12       # and the buttons


func _arcade_offset() -> Vector3:
	var back := Vector3(0, sin(ARCADE_PITCH), -_dir * cos(ARCADE_PITCH))   # unit vector from target to eye
	var centre := Vector3(0, 0, _focus.z + _dir * ARCADE_AHEAD)
	var hw := FieldView.HALF_W + 1.5
	var z0 := _focus.z - _dir * ARCADE_BACK
	var z1 := _focus.z + _dir * ARCADE_FRONT
	var corners := [Vector3(-hw, 0, z0), Vector3(hw, 0, z0), Vector3(-hw, 0, z1), Vector3(hw, 0, z1),
		Vector3(-hw, 2.5, z0), Vector3(hw, 2.5, z0), Vector3(-hw, 2.5, z1), Vector3(hw, 2.5, z1)]
	var vp := get_viewport().get_visible_rect().size
	var keep := _cam.global_transform
	var lo := 8.0
	var hi := 400.0
	for _i in 18:
		var d := (lo + hi) * 0.5
		var eye := centre + back * d
		_cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(centre, Vector3.UP)
		var fits := true
		for c in corners:
			if _cam.is_position_behind(c):
				fits = false
				break
			var sp := _cam.unproject_position(c)
			if sp.x < 4.0 or sp.x > vp.x - 4.0 or sp.y < vp.y * ARCADE_TOP or sp.y > vp.y * (1.0 - ARCADE_BOTTOM):
				fits = false
				break
		if fits:
			hi = d
		else:
			lo = d
	_cam.global_transform = keep
	return back * hi * zoom


func portrait_view() -> bool:
	var r := get_viewport().get_visible_rect().size
	return r.y > r.x
