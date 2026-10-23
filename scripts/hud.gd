class_name Hud
extends CanvasLayer
## Everything on screen that isn't the field, built in code and sized for a phone: the
## scoreboard, the controls, and the panels - teams and brains, the rule editor, the play log,
## a game's box score and a batch of simulated games.

var main: Node
var _root: Control
var _score := [null, null]
var _clock: Label
var _sit: Label
var _call: Label
var _result: Label
var _pause_btn: Button
var _speed_btns := {}
var _view_btn: Button
var _overlay: Control = null
var _toast: Label
var _board: Control
var _board_tw: Tween
var _toast_t := 0.0
var _progress: Label
var _cap_box: PanelContainer
var _cap: RichTextLabel
var _cap_lines: Array = []    # [text, color], newest last
var _cap_t := 0.0
var _board_on := true
var _sound_btn: Button
var fs := 15                 # base font size

# editor state
var _ed_kind := "ai"
var _ed_name := ""
var _ed_text: CodeEdit
var _ed_status: RichTextLabel
var _ed_words_mode := "conditions"
var _ed_names_box: HFlowContainer
var _ed_words_box: HFlowContainer
var _ed_example: Label

const CYAN := Color(0.35, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.38, 0.8)
const YELLOW := Color(1.0, 0.88, 0.3)
const KIND_LABEL := {"coach": "Coaches", "play": "Plays", "ai": "Position brains"}
const PLAY_HELP := """Assignments, one line per position (OL, WR, DL, LB, CB, S set the whole group):
QB: pass drop 3|5|7 read WR1 WR2 ... · play action drop 7 read ... · handoff · run sneak
RB: run inside left|inside right|middle|outside left|outside right|sweep left|sweep right|draw
    route NAME [depth] · block · block lead
WR/TE: route NAME [depth] · block then route NAME · block
   routes: go fade slant out in dig post corner hitch curl comeback flat seam drag cross wheel screen swing angle stop
OL: block · pull left|right
DL/LB/CB/S: rush · rush contain · blitz · man WR1|WR2|WR3|TE|RB · spy
   zone deep third left|middle|right · deep half left|right · deep middle · flat left|right
        hook left|middle|right · curl left|right · robber
Header: play "Name" · about "..." · side offense|defense · kind pass|run|man|zone|blitz
        formation shotgun|under center|pistol|empty · front even|press|off|goal line"""


func setup(m: Node) -> void:
	main = m
	var vp := get_viewport().get_visible_rect().size
	fs = 15 if vp.x > 700 else 14
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_scoreboard()
	_build_controls()
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.add_theme_font_size_override("font_size", fs + 22)
	_toast.add_theme_color_override("font_color", YELLOW)
	_toast.add_theme_color_override("font_outline_color", MAGENTA)
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)
	_build_caption()


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = fs
	var mk := func(bg: Color, border: Color, glow := 0) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		if glow > 0:
			sb.shadow_color = Color(border, 0.45)
			sb.shadow_size = glow
		return sb
	th.set_stylebox("normal", "Button", mk.call(Color(0.03, 0.05, 0.09, 0.92), Color(0.2, 0.75, 0.9, 0.85)))
	th.set_stylebox("hover", "Button", mk.call(Color(0.05, 0.1, 0.16, 0.95), CYAN, 4))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.85, 0.2, 0.62), MAGENTA, 6))
	th.set_stylebox("hover_pressed", "Button", mk.call(Color(0.95, 0.28, 0.7), MAGENTA, 6))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.04, 0.05, 0.07, 0.8), Color(0.25, 0.28, 0.32)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.85, 0.97, 1.0))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.03, 0.06, 0.96)
	panel.border_color = MAGENTA
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(12)
	panel.shadow_color = Color(1.0, 0.3, 0.75, 0.35)
	panel.shadow_size = 10
	th.set_stylebox("panel", "PanelContainer", panel)
	for cls in ["OptionButton"]:
		th.set_stylebox("normal", cls, mk.call(Color(0.03, 0.05, 0.09, 0.92), Color(0.2, 0.75, 0.9, 0.85)))
		th.set_stylebox("hover", cls, mk.call(Color(0.05, 0.1, 0.16, 0.95), CYAN, 4))
		th.set_stylebox("pressed", cls, mk.call(Color(0.05, 0.1, 0.16, 0.95), MAGENTA, 4))
	return th


func _label(text: String, size := 0, color := Color(0.93, 0.93, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size if size > 0 else fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


## ---- scoreboard ----------------------------------------------------------------------------

func _build_scoreboard() -> void:
	var top := PanelContainer.new()
	_board = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 46
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.02, 0.04, 0.82)
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0.3, 0.9, 1.0, 0.3)
	sb.shadow_size = 8
	top.add_theme_stylebox_override("panel", sb)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	top.add_child(v)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for t in 2:
		var l := _label("", fs + 6, FieldView.NEON[t].lightened(0.25))
		l.add_theme_color_override("font_outline_color", Color(FieldView.NEON[t], 0.5))
		l.add_theme_constant_override("outline_size", 4)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if t == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		_score[t] = l
		if t == 1:
			_clock = _label("", fs + 3, YELLOW)
			_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
			_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(_clock)
		row.add_child(l)
	row.move_child(_score[0], 0)
	_sit = _label("", fs, Color(0.85, 0.97, 1.0))
	_sit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sit)
	_call = _label("", fs - 2, Color(0.8, 0.85, 0.9))
	_call.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_call)
	_result = _label("", fs - 1, Color(1, 1, 1))
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result)
	_progress = _label("", fs - 1, Color(0.7, 1, 0.7))
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.visible = false
	v.add_child(_progress)


func show_state(g: Game) -> void:
	for t in 2:
		var ball := " «" if g.poss == t and not g.over else ""
		var cn: String = (g.teams[t]["coach"] as Coach).name
		_score[t].text = ("%s %d%s" % [cn, g.score[t], ball]) if t == 0 else ("%s%s %d" % [ball, cn, g.score[t]])
	var s := maxi(int(g.clock), 0)
	_clock.text = "Final" if g.over else "Q%d %d:%02d" % [g.quarter, s / 60, s % 60]
	_sit.text = "" if g.over else "%s ball · %s" % [g.teams[g.poss]["name"], g.situation()]


## Fade the scoreboard out for the play and back in after the whistle.
func show_board(on: bool) -> void:
	if _board == null:
		return
	_board_on = on
	if _board_tw != null and _board_tw.is_valid():
		_board_tw.kill()
	_board_tw = create_tween()
	_board_tw.tween_property(_board, "modulate:a", 1.0 if on else 0.0, 0.25)


func show_call(text: String) -> void:
	_call.text = text


func show_result(text: String) -> void:
	_result.text = text


func toast(text: String, secs := 1.6) -> void:
	_toast.text = text
	# as big as fits: shrink the type until the longest line fits the screen with a margin
	var avail := get_viewport().get_visible_rect().size.x - 28.0
	var font := _toast.get_theme_font("font")
	var size := fs + 22
	while size > fs:
		var widest := 0.0
		for ln in text.split("\n"):
			widest = maxf(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if widest + 24.0 <= avail:
			break
		size -= 2
	_toast.add_theme_font_size_override("font_size", size)
	_toast.reset_size()
	_toast.visible = true
	_toast.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - _toast.size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.42)
	_toast_t = secs


## ---- play-by-play captions ----------------------------------------------------------------

func _build_caption() -> void:
	_cap_box = PanelContainer.new()
	_cap_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cap_box.offset_left = 8
	_cap_box.offset_right = -8
	_cap_box.offset_top = 46
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.02, 0.05, 0.7)
	sb.border_color = Color(MAGENTA, 0.7)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	_cap_box.add_theme_stylebox_override("panel", sb)
	_cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap = RichTextLabel.new()
	_cap.bbcode_enabled = true
	_cap.fit_content = true
	_cap.scroll_active = false
	_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap.add_theme_font_size_override("normal_font_size", fs)
	_cap.add_theme_font_size_override("bold_font_size", fs + 1)
	_cap_box.add_child(_cap)
	_cap_box.visible = false
	_root.add_child(_cap_box)


## A line from the announcer (or a robot). The last two show; they fade when the play goes quiet.
func caption(text: String, big := false, color := Color(0.9, 0.97, 1.0)) -> void:
	_cap_lines.append([text, YELLOW if big else color, big])
	while _cap_lines.size() > 2:
		_cap_lines.pop_front()
	var out := ""
	for i in _cap_lines.size():
		var ln: Array = _cap_lines[i]
		var c: Color = ln[1]
		if i < _cap_lines.size() - 1:
			c = c.darkened(0.35)
		var t := String(ln[0]).replace("[", "(").replace("]", ")")
		out += ("\n" if out != "" else "") + ("[b][color=#%s]%s[/color][/b]" % [c.to_html(false), t] if ln[2] else "[color=#%s]%s[/color]" % [c.to_html(false), t])
	_cap.text = out
	_cap_box.visible = true
	_cap_box.modulate.a = 1.0
	_cap_t = 3.5


func clear_caption() -> void:
	_cap_lines.clear()
	_cap_box.visible = false


func set_progress(text: String) -> void:
	_progress.text = text
	_progress.visible = text != ""


func _process(delta: float) -> void:
	if _cap_box != null and _cap_box.visible:
		# under the scoreboard when it is up, in its place while the ball is live
		var want := 46.0 + ((_board.size.y + 6.0) if _board_on else 0.0)
		_cap_box.offset_top = lerpf(_cap_box.offset_top, want, minf(delta * 10.0, 1.0))
		_cap_box.offset_bottom = _cap_box.offset_top
		_cap_t -= delta
		if _cap_t < 0.6:
			_cap_box.modulate.a = maxf(_cap_t / 0.6, 0.0)
		if _cap_t <= 0.0:
			_cap_box.visible = false
			_cap_lines.clear()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - _toast.size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.42)
		if _toast_t <= 0.0:
			_toast.visible = false


## ---- controls ------------------------------------------------------------------------------

func _build_controls() -> void:
	var bar := HFlowContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_bottom = -10
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	_root.add_child(bar)
	_pause_btn = _button("Pause", func(): main.toggle_pause())
	bar.add_child(_pause_btn)
	for s in [1.0, 2.0, 4.0, 8.0]:
		var b := _button("%d×" % int(s), func(): main.set_speed(s), true)
		_speed_btns[s] = b
		bar.add_child(b)
	bar.add_child(_button("Skip drive", func(): main.skip_drive()))
	_view_btn = _button("Cam: Behind", func(): _view_btn.text = "Cam: " + main.next_view())
	bar.add_child(_view_btn)
	_sound_btn = _button("Sound: voice", func(): _sound_btn.text = main.next_sound())
	bar.add_child(_sound_btn)
	bar.add_child(_button("Teams", func(): open_teams()))
	bar.add_child(_button("Edit AI", func(): open_editor()))
	bar.add_child(_button("Sim ×10", func(): main.run_batch(10)))
	bar.add_child(_button("Stats", func(): if main.game != null: show_stats(main.game, "live")))
	bar.add_child(_button("Log", func(): open_log()))
	bar.add_child(_button("New game", func(): main.new_game()))
	mark_speed(1.0)


func mark_speed(s: float) -> void:
	for k in _speed_btns:
		_speed_btns[k].button_pressed = is_equal_approx(k, s)


func mark_paused(p: bool) -> void:
	_pause_btn.text = "Play" if p else "Pause"


func mark_view(v: String) -> void:
	_view_btn.text = "Cam: " + v


## ---- overlays ------------------------------------------------------------------------------

func any_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func close_overlay() -> void:
	if any_overlay():
		_overlay.queue_free()
	_overlay = null
	main.overlay_changed(false)


## A panel over the field: returns its content box.
func _open(title: String) -> VBoxContainer:
	close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_overlay = dim
	var vp := get_viewport().get_visible_rect().size
	var w := minf(vp.x - 16.0, 900.0)
	var pc := PanelContainer.new()
	pc.position = Vector2((vp.x - w) * 0.5, 40)
	pc.custom_minimum_size = Vector2(w, vp.y - 60)
	pc.size = Vector2(w, vp.y - 60)
	dim.add_child(pc)
	var outer := VBoxContainer.new()
	pc.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var tl := _label(title, fs + 4, MAGENTA)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(_button("× Close", func(): close_overlay()))
	var sc := DragScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	main.overlay_changed(true)
	return box


func _section(box: Control, text: String) -> void:
	var l := _label(text, fs + 1, CYAN)
	box.add_child(l)


func _chips(box: Control, names: Array, current: String, cb: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for n in names:
		var b := _button(String(n), func(): cb.call(n), true)
		b.button_pressed = n == current
		f.add_child(b)
	box.add_child(f)
	return f


## ---- teams and brains ----------------------------------------------------------------------

var _teams_side := 0


func open_teams() -> void:
	var box := _open("Teams, coaches and brains")
	box.add_child(_label("Each side has a coach (who calls the plays) and a brain at every position (how each player plays them). \"Coach's pick\" uses the brain in the coach's lineup.", fs - 1, Color(0.8, 0.82, 0.85)))
	var sides := HBoxContainer.new()
	box.add_child(sides)
	for t in 2:
		var b := _button("%s side" % Team.NAMES[t], func(): _teams_side = t; open_teams(), true)
		b.button_pressed = _teams_side == t
		b.add_theme_color_override("font_color", FieldView.COLORS[t].lightened(0.4))
		sides.add_child(b)
	var t: int = _teams_side
	_section(box, "Coach")
	var cur: String = main.coaches[t]
	_chips(box, Library.names("coach"), cur, func(n): main.coaches[t] = n; open_teams())
	var c: Coach = Library.coach(cur)
	if c != null:
		box.add_child(_label(c.about, fs - 1, Color(0.8, 0.82, 0.85)))
	_section(box, "Play calling (offense and defense)")
	var cf := HFlowContainer.new()
	cf.add_theme_constant_override("h_separation", 6)
	cf.add_theme_constant_override("v_separation", 6)
	box.add_child(cf)
	for mode in Game.CALLING:
		var b := _button(Game.CALLING_LABEL[mode], func(): main.calling[t] = mode; main.library_changed(); open_teams(), true)
		b.button_pressed = main.calling[t] == mode
		cf.add_child(b)
	var why := {"pick": "You call every play for this side: each down you get a hand of 8 brand-new plays (with diagrams) to choose from. The coach's choice is starred. There is no kicking: fourth down is always a go.",
		"coach": "The coach's rules pick every play.",
		"random": "Any play in the playbook, picked at random every down.",
		"generated": "A brand-new play made up every down: random formation, routes, gaps, coverages and blitzes. Save the good ones from the Log."}
	box.add_child(_label(why[main.calling[t]], fs - 1, Color(0.8, 0.82, 0.85)))
	_section(box, "Brains by position")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for g in Brain.GROUPS:
		var gl := _label(g, fs, Color(0.85, 0.9, 1))
		gl.autowrap_mode = TextServer.AUTOWRAP_OFF
		gl.custom_minimum_size.x = 34
		grid.add_child(gl)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var coach_pick: String = c.lineup.get(g, "") if c != null else ""
		if coach_pick == "":
			var opts0 := Library.brains_for(g)
			coach_pick = opts0[0] if not opts0.is_empty() else "-"
		ob.add_item("Coach's pick (%s)" % coach_pick)
		var opts := Library.brains_for(g)
		var sel := 0
		for i in opts.size():
			ob.add_item(String(opts[i]))
			if main.picks[t].get(g, "") == opts[i]:
				sel = i + 1
		ob.select(sel)
		ob.item_selected.connect(func(idx):
			if idx == 0:
				main.picks[t].erase(g)
			else:
				main.picks[t][g] = opts[idx - 1]
			_brain_about(g, t))
		grid.add_child(ob)
	_section(box, "Game length")
	var q := [["3 min quarters", 180.0], ["5 min", 300.0], ["8 min", 480.0], ["15 min (full)", 900.0]]
	var qf := HFlowContainer.new()
	qf.add_theme_constant_override("h_separation", 6)
	box.add_child(qf)
	for e in q:
		var b := _button(e[0], func(): main.qlen = e[1]; open_teams(), true)
		b.button_pressed = is_equal_approx(main.qlen, e[1])
		qf.add_child(b)
	var go := _button("Start a game with these teams", func(): close_overlay(); main.new_game())
	go.add_theme_font_size_override("font_size", fs + 2)
	box.add_child(go)


func _brain_about(g: String, t: int) -> void:
	var n: String = main.picks[t].get(g, "")
	if n != "":
		var b: Brain = Library.brain(n)
		if b != null:
			toast("%s: %s" % [b.name, b.about], 3.0)


## ---- the rule editor -----------------------------------------------------------------------

func open_editor(kind := "", name := "") -> void:
	if kind != "":
		_ed_kind = kind
	if name != "":
		_ed_name = name
	var box := _open("Edit the AI")
	box.add_child(_label("Every coach, play and position brain is a short rule file. Rules are read top to bottom; the first that holds decides. Tap a word below to insert it; type a space for suggestions.", fs - 1, Color(0.8, 0.82, 0.85)))
	var kinds := HFlowContainer.new()
	kinds.add_theme_constant_override("h_separation", 6)
	box.add_child(kinds)
	for k in ["ai", "coach", "play"]:
		var b := _button(KIND_LABEL[k], func(): _ed_kind = k; _ed_name = ""; open_editor(), true)
		b.button_pressed = _ed_kind == k
		kinds.add_child(b)
	var names := Library.names(_ed_kind)
	if _ed_name == "" or not names.has(_ed_name):
		_ed_name = names[0] if not names.is_empty() else ""
	_ed_names_box = HFlowContainer.new()
	_ed_names_box.add_theme_constant_override("h_separation", 5)
	_ed_names_box.add_theme_constant_override("v_separation", 5)
	box.add_child(_ed_names_box)
	for n in names:
		var label := String(n)
		if _ed_kind == "ai":
			label = "%s · %s" % [(Library.brain(n) as Brain).group, n]
		if Library.is_edited(_ed_kind, n):
			label += " (edited)"
		var b := _button(label, func(): _ed_name = n; open_editor(), true)
		b.button_pressed = n == _ed_name
		b.add_theme_font_size_override("font_size", fs - 2)
		_ed_names_box.add_child(b)
	_ed_text = CodeEdit.new()
	_ed_text.text = Library.source(_ed_kind, _ed_name)
	_ed_text.custom_minimum_size = Vector2(0, maxf(get_viewport().get_visible_rect().size.y * 0.42, 240))
	_ed_text.add_theme_font_size_override("font_size", fs - 1)
	_ed_text.gutters_draw_line_numbers = true
	_ed_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ed_text.code_completion_enabled = true
	_ed_text.code_completion_prefixes = [" "]
	_ed_text.code_completion_requested.connect(_on_completion)
	_ed_text.syntax_highlighter = _highlighter()
	_ed_text.text_changed.connect(func(): _lint_live())
	box.add_child(_ed_text)
	_ed_status = RichTextLabel.new()
	_ed_status.bbcode_enabled = true
	_ed_status.fit_content = true
	_ed_status.add_theme_font_size_override("normal_font_size", fs - 1)
	box.add_child(_ed_status)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(_button("Check", func(): _lint_live(true)))
	row.add_child(_button("Save", func(): _save()))
	row.add_child(_button("Reset to shipped", func(): Library.reset(_ed_kind, _ed_name); open_editor()))
	row.add_child(_button("Copy as new", func(): _copy_as_new()))
	row.add_child(_button("Save & play", func(): if _save(): close_overlay(); main.new_game()))
	# the words
	if _ed_kind == "play":
		_section(box, "Play syntax")
		var ph := _label(PLAY_HELP, fs - 2, Color(0.85, 0.88, 0.9))
		box.add_child(ph)
	else:
		_section(box, "Words (tap to insert)")
		var wm := HBoxContainer.new()
		box.add_child(wm)
		for m in ["conditions", "actions", "dials" if _ed_kind == "ai" else "lineup"]:
			var b := _button(m.capitalize(), func(): _ed_words_mode = m; _fill_words(), true)
			b.button_pressed = _ed_words_mode == m
			wm.add_child(b)
		_ed_example = _label("", fs - 1, Color(0.7, 1, 0.75))
		box.add_child(_ed_example)
		_ed_words_box = HFlowContainer.new()
		_ed_words_box.add_theme_constant_override("h_separation", 5)
		_ed_words_box.add_theme_constant_override("v_separation", 5)
		box.add_child(_ed_words_box)
		_fill_words()
	_lint_live()


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color(0.7, 0.9, 1.0)
	h.symbol_color = Color(0.8, 0.8, 0.8)
	h.function_color = Color(0.9, 0.9, 0.9)
	h.member_variable_color = Color(0.9, 0.9, 0.9)
	for w in ["when", "otherwise", "and", "or", "not", "for"]:
		h.add_keyword_color(w, Color(1.0, 0.6, 0.35))
	for w in ["ai", "about", "position", "dials", "rules", "coach", "offense", "defense", "lineup", "play", "side", "kind", "formation", "front"]:
		h.add_keyword_color(w, Color(0.6, 0.8, 1.0))
	h.add_color_region("#", "", Color(0.5, 0.6, 0.5), true)
	h.add_color_region("\"", "\"", Color(0.95, 0.85, 0.5))
	return h


func _fill_words() -> void:
	for c in _ed_words_box.get_children():
		c.queue_free()
	var tables := Library.tables(_ed_kind)
	var items: Array = []
	match _ed_words_mode:
		"conditions":
			items = RuleHelp.phrases(tables["conditions"])
		"actions":
			items = RuleHelp.phrases(tables["actions"])
		"dials":
			for d in Brain.DIALS:
				items.append({"phrase": "%s 0.5" % d, "help": Brain.DIAL_HELP[d]})
		"lineup":
			for g in Brain.GROUPS:
				var opts := Library.brains_for(g)
				for o in opts:
					items.append({"phrase": "%s \"%s\"" % [g, o]})
	for it in items:
		var phrase: String = it["phrase"]
		var b := _button(phrase, func(): _insert(phrase, it))
		b.add_theme_font_size_override("font_size", fs - 2)
		_ed_words_box.add_child(b)
	var ex := ""
	if _ed_kind == "ai":
		ex = "e.g.  when with the ball and one man to beat -> juke\n      when before the throw and pressure and checkdown open -> check down"
	elif _ed_kind == "coach":
		ex = "e.g.  when third down and to go over 7 -> call \"Smash\" or \"Four Verticals\"\n      when \"Power\" averaging over 5 and chance 50% -> call \"Power\""
	_ed_example.text = ex


func _insert(phrase: String, it: Dictionary) -> void:
	var text := phrase.replace("N%", "40%").replace("Ns", "2s").replace(" N", " 5").replace("WORD", "wr1").replace("\"NAME\"", "\"Smash\"")
	_ed_text.insert_text_at_caret(text + " ")
	_ed_text.grab_focus()
	if it.has("help"):
		_ed_example.text = String(it["help"])
	else:
		var verb := "when %s -> ..." % text if _ed_words_mode == "conditions" else "when ... -> %s" % text
		_ed_example.text = "e.g.  " + verb


## Completion: after a space, offer the phrases that continue what is being typed.
func _on_completion() -> void:
	var tables := Library.tables(_ed_kind)
	if tables.is_empty():
		return
	var line := _ed_text.get_line(_ed_text.get_caret_line()).substr(0, _ed_text.get_caret_column()).to_lower()
	var after_arrow := line.find("->") >= 0
	var cut := 0
	for sep in ["when ", " and ", " or ", "not ", "->", ";", "("]:
		var k := line.rfind(sep)
		if k >= 0:
			cut = maxi(cut, k + sep.length())
	var frag := line.substr(cut).strip_edges(true, false)
	var table: Array = tables["actions"] if after_arrow else tables["conditions"]
	var word_start := frag.rfind(" ") + 1
	for ph in RuleHelp.complete(frag, table, 12):
		var rest := ph.substr(word_start) if ph.begins_with(frag) else ph
		_ed_text.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, ph, rest)
	_ed_text.update_code_completion_options(true)


func _lint_live(loud := false) -> void:
	var errs := Library.lint(_ed_kind, _ed_text.text)
	if errs.is_empty():
		_ed_status.text = "[color=#8f8]Reads cleanly.[/color]" + ("" if not loud else " Save to use it.")
	else:
		var s := "[color=#f99]"
		for e in errs.slice(0, 6):
			s += "- " + e.replace("[", "(").replace("]", ")") + "\n"
		_ed_status.text = s + "[/color]"


func _save() -> bool:
	var r := Library.save(_ed_kind, _ed_text.text)
	if not (r[0] as Array).is_empty():
		_lint_live(true)
		toast("Not saved - fix the problems first", 2.0)
		return false
	_ed_name = r[1]
	toast("Saved \"%s\" - used from the next snap" % _ed_name, 2.0)
	main.library_changed()
	open_editor()
	return true


func _copy_as_new() -> void:
	var text := _ed_text.text
	var head: String = {"ai": "ai ", "coach": "coach ", "play": "play "}[_ed_kind]
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].strip_edges().to_lower().begins_with(head):
			var n := Dsl.quoted(lines[i].strip_edges().substr(head.length()))
			lines[i] = "%s\"%s (mine)\"" % [head, n]
			break
	_ed_text.text = "\n".join(lines)
	_lint_live()
	toast("Renamed - Save to keep it as a new one", 2.0)


## ---- the log and results ------------------------------------------------------------------

func open_log() -> void:
	var box := _open("Play by play")
	var g: Game = main.game
	if g == null:
		return
	var entries: Array = g.log.slice(maxi(0, g.log.size() - 120))
	entries.reverse()
	for e in entries:
		var s := maxi(int(e["clock"]), 0)
		var who := ""
		if e.has("team"):
			who = Team.NAMES[int(e["team"])] + " · " + ["", "1st", "2nd", "3rd", "4th"][clampi(int(e["down"]), 1, 4)] + " & " + str(maxi(int(round(float(e["to_go"]))), 1)) + " · "
		var l := _label("Q%d %d:%02d  %d-%d   %s%s" % [e["q"], s / 60, s % 60, e["score"][0], e["score"][1], who, e["text"]], fs - 2)
		box.add_child(l)
		if e.has("off_text") or e.has("def_text"):
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			box.add_child(row)
			for k in ["off_text", "def_text"]:
				if e.has(k):
					var txt: String = e[k]
					var b := _button("+ Save %s play" % ("offense" if k == "off_text" else "defense"), func(): _save_generated(txt))
					b.add_theme_font_size_override("font_size", fs - 3)
					row.add_child(b)


## Keep a play made up during the game: it goes into the playbook under its own name.
func _save_generated(text: String) -> void:
	var p := Play.parse(text)
	var base := p.name.replace("Gen ", "My ")
	var n := base
	var k := 2
	while Library.play(n) != null:
		n = "%s #%d" % [base, k]
		k += 1
	var r := Library.save("play", text.replace("\"%s\"" % p.name, "\"%s\"" % n).replace("Made up for this down.", "Saved from a game."))
	if (r[0] as Array).is_empty():
		toast("Saved \"%s\" to the playbook" % n, 2.5)
		main.library_changed()
	else:
		toast("Couldn't save: %s" % r[0][0], 3.0)


## ---- calling your own plays ---------------------------------------------------------------

func open_picker(g: Game, team: int, side: String, hand: Array, coach: Dictionary = {}) -> void:
	var title := "%s %s · %s" % [Team.NAMES[team], side, g.situation()]
	var box := _open(title)
	box.add_child(_label("%s %d - %d %s   ·   Q%d %d:%02d.  Pick a play - all made up just now." % [
		(g.teams[0]["coach"] as Coach).name, g.score[0], g.score[1], (g.teams[1]["coach"] as Coach).name,
		mini(g.quarter, 4), maxi(int(g.clock), 0) / 60, maxi(int(g.clock), 0) % 60], fs - 2, Color(0.8, 0.82, 0.85)))
	var vp := get_viewport().get_visible_rect().size
	var inner := minf(vp.x - 16.0, 900.0) - 40.0
	var cols := 2 if inner < 560.0 else 4
	var cw := floorf((inner - 8.0 * (cols - 1)) / cols)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var coach_i := int(coach.get("index", -1))
	var coach_name: String = ((g.teams[team]["coach"]) as Coach).name
	if coach_i >= 0:
		var cl := _label("COACH'S PICK: %s would call %s - the marked card is the closest in this hand." % [coach_name, String(coach.get("call", ""))], fs - 1, MAGENTA)
		box.add_child(cl)
		box.move_child(cl, grid.get_index())
	for ci in hand.size():
		var g2: Dictionary = hand[ci]
		var p: Play = g2["play"]
		var card := Button.new()
		if ci == coach_i:
			for st in ["normal", "hover", "pressed"]:
				var sb := (card.get_theme_stylebox(st) as StyleBoxFlat)
				if sb != null:
					sb = sb.duplicate()
					sb.border_color = MAGENTA
					sb.set_border_width_all(3)
					sb.shadow_color = Color(MAGENTA, 0.45)
					sb.shadow_size = 8
					card.add_theme_stylebox_override(st, sb)
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.custom_minimum_size = Vector2(cw, cw * 0.62 + fs * 2.6 + 10.0)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 4
		v.offset_right = -4
		v.offset_top = 4
		v.offset_bottom = -4
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var d := PlayDiagram.new()
		d.custom_minimum_size = Vector2(cw - 8.0, cw * 0.62)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		d.setup(p)
		if ci == coach_i:
			var badge := _label("COACH'S PICK", fs - 2, Color(0.05, 0.02, 0.08))
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = MAGENTA
			bsb.set_corner_radius_all(3)
			bsb.set_content_margin_all(2)
			badge.add_theme_stylebox_override("normal", bsb)
			# over the top of the diagram, so the card keeps its size
			badge.autowrap_mode = TextServer.AUTOWRAP_OFF
			badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
			badge.size = Vector2.ZERO
			badge.position = Vector2(6, 6)
			badge.z_index = 1
			card.add_child.call_deferred(badge)
		var nl := _label((("%s · %s" % [p.name, "run" if p.kind == "run" else "pass"]) if side == "offense" else p.name), fs - 2, MAGENTA if ci == coach_i else YELLOW)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(nl)
		var sl := _label(_play_subline(p), fs - 3, Color(0.78, 0.82, 0.86))
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.clip_text = true
		v.add_child(sl)
		card.pressed.connect(func(): main.pick_made("off" if side == "offense" else "def", g2))
		grid.add_child(card)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	row.add_child(_button("Deal new plays", func(): main.redeal(side)))
	box.add_child(_label("Yellow is the run, the blue line is the line of scrimmage. Defense: shaded zones, dashed lines for man coverage, pink arrows for blitzers.", fs - 3, Color(0.7, 0.74, 0.78)))


func _play_subline(p: Play) -> String:
	if p.about != "" and not p.about.begins_with("Made up"):
		return p.about
	if p.side == "offense":
		var qb: Dictionary = p.assigns.get("QB", {})
		if p.kind == "run":
			return "%s · run" % p.formation.capitalize()
		return "%s · %s%d-step drop" % [p.formation.capitalize(), "play action, " if qb.get("fake", false) else "", int(qb.get("drop", 5))]
	var blitz := 0
	for s in p.assigns:
		if String(p.assigns[s].get("kind", "")) == "blitz":
			blitz += 1
	return "%s · %s%s" % [p.front.capitalize(), p.kind, (" · %d blitz" % blitz) if blitz > 0 else ""]


## ---- box scores: at each quarter break, at the end and any time from Stats ---------------

var _stats_tab := "team"


## mode: "quarter" (a break - Continue goes on), "final", or "live" (just a look).
func show_stats(g: Game, mode: String, snap: Dictionary = {}) -> void:
	var names := [(g.teams[0]["coach"] as Coach).name, (g.teams[1]["coach"] as Coach).name]
	var score: Array = snap.get("score", g.score)
	var line: Array = snap.get("line", g.line)
	var stats: Array = snap.get("stats", g.stats)
	var pstats: Array = snap.get("pstats", g.pstats)
	var title := "Box score"
	match mode:
		"quarter":
			var q := int(snap.get("q", 1))
			title = ["", "End of the 1st quarter", "Halftime", "End of the 3rd quarter", "End of regulation"][clampi(q, 1, 4)]
		"final":
			title = "Final"
		"live":
			title = "Box score · Q%d" % mini(g.quarter, 4)
	var box := _open(title)
	if mode == "final":
		var w := g.winner()
		box.add_child(_label("Tie game" if w < 0 else "%s win" % names[w], fs + 3, MAGENTA))
	_line_score(box, names, line, score)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	box.add_child(tabs)
	for tab in [["team", "Team"], ["p0", "%s players" % Team.NAMES[0]], ["p1", "%s players" % Team.NAMES[1]]]:
		var b := _button(tab[1], func(): _stats_tab = tab[0]; show_stats(g, mode, snap), true)
		b.button_pressed = _stats_tab == tab[0]
		tabs.add_child(b)
	match _stats_tab:
		"team":
			_box_score(box, stats, [1, 1], names)
		"p0", "p1":
			var t := int(_stats_tab.substr(1))
			_player_tables(box, pstats[t], 1, g.teams[t])
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	if mode == "quarter":
		var go := _button("Continue", func(): close_overlay(); main.resume_after_break())
		go.add_theme_font_size_override("font_size", fs + 2)
		row.add_child(go)
		var stop := _button("Stop at quarter breaks", func(): main.stop_at_quarters = not main.stop_at_quarters, true)
		stop.button_pressed = main.stop_at_quarters
		row.add_child(stop)
	if mode == "final":
		row.add_child(_button("Play again", func(): close_overlay(); main.new_game()))
		row.add_child(_button("Sim ×10 these teams", func(): close_overlay(); main.run_batch(10)))
		_final_extras(box, g)


func _line_score(box: Control, names: Array, line: Array, score: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for h in ["", "1", "2", "3", "4", "T"]:
		var l := _label(h, fs - 1, CYAN)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for t in 2:
		var nl := _label(names[t], fs, FieldView.COLORS[t].lightened(0.4))
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(nl)
		for q in 4:
			var l := _label(str(line[t][q]), fs)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		var tl := _label(str(score[t]), fs + 1, Color.WHITE)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(tl)


## Passing, rushing, receiving and defense for one side. `per` divides (games in a batch).
func _player_tables(box: Control, ps: Dictionary, per: int, team: Dictionary) -> void:
	var v := func(slot: String, k: String) -> float: return float(ps[slot][k]) / float(per)
	var fmt := func(x: float) -> String: return str(int(round(x))) if per == 1 else "%.1f" % x
	var who := func(slot: String) -> String:
		var b: Brain = (team.get("brains", {}) as Dictionary).get(slot, null)
		return slot if b == null else "%s %s" % [slot, b.name.split(" ")[0]]
	if per > 1:
		box.add_child(_label("Per game, over %d games. LNG is the longest." % per, fs - 2, Color(0.8, 0.82, 0.85)))
	var tables := [
		["Passing", ["C/ATT", "YDS", "TD", "INT", "SK"], func(s): return v.call(s, "att") > 0 or v.call(s, "sk") > 0,
			func(s): return ["%s/%s" % [fmt.call(v.call(s, "cmp")), fmt.call(v.call(s, "att"))], fmt.call(v.call(s, "pyd")), fmt.call(v.call(s, "ptd")), fmt.call(v.call(s, "int")), fmt.call(v.call(s, "sk"))], "pyd"],
		["Rushing", ["CAR", "YDS", "AVG", "TD", "LNG"], func(s): return v.call(s, "car") > 0,
			func(s): return [fmt.call(v.call(s, "car")), fmt.call(v.call(s, "ryd")), "%.1f" % (float(ps[s]["ryd"]) / maxf(float(ps[s]["car"]), 1.0)), fmt.call(v.call(s, "rtd")), str(int(round(float(ps[s]["rlong"]))))], "ryd"],
		["Receiving", ["REC/TGT", "YDS", "AVG", "TD", "LNG"], func(s): return v.call(s, "tgt") > 0,
			func(s): return ["%s/%s" % [fmt.call(v.call(s, "rec")), fmt.call(v.call(s, "tgt"))], fmt.call(v.call(s, "recyd")), "%.1f" % (float(ps[s]["recyd"]) / maxf(float(ps[s]["rec"]), 1.0)), fmt.call(v.call(s, "rectd")), str(int(round(float(ps[s]["reclong"]))))], "recyd"],
		["Defense", ["TKL", "SK", "INT", "PBU", "FF"], func(s): return Play.DEFENSE_SLOTS.has(s) and (v.call(s, "tkl") + v.call(s, "sack") + v.call(s, "dint") + v.call(s, "pbu") + v.call(s, "ff")) > 0,
			func(s): return [fmt.call(v.call(s, "tkl")), fmt.call(v.call(s, "sack")), fmt.call(v.call(s, "dint")), fmt.call(v.call(s, "pbu")), fmt.call(v.call(s, "ff"))], "tkl"],
	]
	for tb in tables:
		var slots: Array = ps.keys().filter(tb[2])
		if slots.is_empty():
			continue
		var key: String = tb[4]
		slots.sort_custom(func(a, b): return float(ps[a][key]) > float(ps[b][key]))
		_section(box, tb[0])
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 2)
		box.add_child(grid)
		var hl := _label("", fs - 2)
		grid.add_child(hl)
		for h in tb[1]:
			var l := _label(h, fs - 2, CYAN)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		for sl in slots:
			var nl := _label(who.call(sl), fs - 2, Color(0.85, 0.9, 1))
			nl.autowrap_mode = TextServer.AUTOWRAP_OFF
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(nl)
			for cell in tb[3].call(sl):
				var l := _label(String(cell), fs - 2)
				l.autowrap_mode = TextServer.AUTOWRAP_OFF
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				grid.add_child(l)


func show_game_over(g: Game) -> void:
	show_stats(g, "final")


func _final_extras(box: Control, g: Game) -> void:
	_section(box, "Play calls (calls · yards a call)")
	for t in 2:
		box.add_child(_label(_calls_line(g.calls[t], Team.NAMES[t]), fs - 2))
	_section(box, "Drives")
	var ds := []
	for d in g.drives:
		ds.append("%s: %d plays, %d yds, %s" % [Team.NAMES[int(d["team"])], int(d["plays"]), int(round(float(d["yards"]))), d["result"]])
	box.add_child(_label("\n".join(ds), fs - 2))
	var bt: Array = g.get_meta("brain_tally", [{}, {}])
	_rules_section(box, bt, g.coach_tally, [g.teams[0]["coach"], g.teams[1]["coach"]])


func _calls_line(calls: Dictionary, who: String) -> String:
	var parts := []
	var names := calls.keys()
	names.sort_custom(func(a, b): return calls[a][0] > calls[b][0])
	for n in names:
		parts.append("%s %d · %.1f" % [n, calls[n][0], float(calls[n][1]) / maxf(float(calls[n][0]), 1.0)])
	return "%s: %s" % [who, ",  ".join(parts)]


func _box_score(box: Control, stats: Array, per: Array, names: Array) -> void:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	box.add_child(g)
	var rows := [["", names[0], names[1]]]
	var f := func(t: int, k: String) -> float: return float(stats[t].get(k, 0.0)) / float(per[t])
	rows.append(["Points" if per[0] == 1 else "Points a game", "", ""])
	rows.append(["Plays", "%.1f" % f.call(0, "plays"), "%.1f" % f.call(1, "plays")])
	rows.append(["Yards", "%.0f" % f.call(0, "yards"), "%.0f" % f.call(1, "yards")])
	rows.append(["Pass C/A, yds (avg)", _pass_line(stats[0], per[0]), _pass_line(stats[1], per[1])])
	rows.append(["Rush car-yds (avg)", _rush_line(stats[0], per[0]), _rush_line(stats[1], per[1])])
	rows.append(["Sacks taken", "%.1f" % f.call(0, "sacks"), "%.1f" % f.call(1, "sacks")])
	rows.append(["Turnovers", "%.1f" % f.call(0, "turnovers"), "%.1f" % f.call(1, "turnovers")])
	rows.append(["3rd down", _rate(stats[0], "third_conv", "third_att"), _rate(stats[1], "third_conv", "third_att")])
	rows.append(["Big plays (20+)", "%.1f" % f.call(0, "explosive"), "%.1f" % f.call(1, "explosive")])
	rows.remove_at(1)
	for r in rows:
		for i in 3:
			var l := _label(String(r[i]), fs - 1, CYAN if i == 0 or r == rows[0] else Color(0.93, 0.93, 0.9))
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			g.add_child(l)


func _pass_line(s: Dictionary, n: int) -> String:
	var att := float(s.get("pass_att", 0))
	return "%.0f/%.0f, %.0f (%.1f)" % [float(s.get("comp", 0)) / n, att / n, float(s.get("pass_yds", 0)) / n, float(s.get("pass_yds", 0)) / maxf(att, 1.0)]


func _rush_line(s: Dictionary, n: int) -> String:
	var att := float(s.get("rush_att", 0))
	return "%.0f-%.0f (%.1f)" % [att / n, float(s.get("rush_yds", 0)) / n, float(s.get("rush_yds", 0)) / maxf(att, 1.0)]


func _rate(s: Dictionary, a: String, b: String) -> String:
	var d := float(s.get(b, 0))
	return "-" if d == 0 else "%.0f%%" % (100.0 * float(s.get(a, 0)) / d)


## The rules that did the work, per side: the coach's and the busiest brain rules.
func _rules_section(box: Control, brain_tally: Array, coach_tally: Array, coaches: Array) -> void:
	_section(box, "Rules that decided (most used)")
	for t in 2:
		var c: Coach = coaches[t]
		var lines := []
		var ct: Dictionary = coach_tally[t]
		var cl := ct.keys()
		cl.sort_custom(func(a, b): return ct[a] > ct[b])
		for ln in cl.slice(0, 4):
			lines.append("  %d× %s" % [ct[ln], _coach_rule(c, int(ln))])
		var bt: Dictionary = brain_tally[t]
		var flat := []
		for bn in bt:
			for ln in bt[bn]:
				flat.append([int(bt[bn][ln]), bn, int(ln)])
		flat.sort_custom(func(a, b): return a[0] > b[0])
		for f in flat.slice(0, 8):
			var b: Brain = Library.brain(f[1])
			lines.append("  %d× %s: %s" % [f[0], f[1], b.rule_text(f[2]) if b != null else str(f[2])])
		var l := _label("%s (%s)\n%s" % [Team.NAMES[t], c.name, "\n".join(lines)], fs - 2)
		box.add_child(l)


func _coach_rule(c: Coach, ln: int) -> String:
	for r in c.offense_rules + c.defense_rules:
		if int(r["line"]) == ln:
			return String(r["text"])
	return "line %d" % ln


func show_batch(agg: Dictionary, names: Array) -> void:
	var box := _open("Sim ×%d" % int(agg["n"]))
	var n := int(agg["n"])
	box.add_child(_label("%s won %d, %s won %d, %d tied.   Points a game %.1f - %.1f" % [names[0], agg["wins"][0], names[1], agg["wins"][1], agg["ties"], float(agg["points"][0]) / n, float(agg["points"][1]) / n], fs + 2))
	var sc := []
	for s in agg["scores"]:
		sc.append("%d-%d" % [s[0], s[1]])
	box.add_child(_label("Scores: " + ", ".join(sc), fs - 2, Color(0.8, 0.82, 0.85)))
	var avg_line := [[], []]
	for t in 2:
		for q in 4:
			avg_line[t].append(snappedf(float(agg["line"][t][q]) / n, 0.1))
	box.add_child(_label("Points a quarter", fs - 1, CYAN))
	_line_score(box, names, avg_line, [snappedf(float(agg["points"][0]) / n, 0.1), snappedf(float(agg["points"][1]) / n, 0.1)])
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	box.add_child(tabs)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	var teams_now := [Team.build(0, main.coaches[0], main.picks[0]), Team.build(1, main.coaches[1], main.picks[1])]
	var fill := func(tab: String) -> void:
		for ch in holder.get_children():
			ch.queue_free()
		if tab == "team":
			_box_score(holder, agg["stats"], [n, n], names)
		else:
			var t := int(tab.substr(1))
			_player_tables(holder, agg["pstats"][t], n, teams_now[t])
		for b in tabs.get_children():
			b.button_pressed = b.get_meta("tab") == tab
	for tab in [["team", "Team"], ["p0", "%s players" % Team.NAMES[0]], ["p1", "%s players" % Team.NAMES[1]]]:
		var b := _button(tab[1], func(): fill.call(tab[0]), true)
		b.set_meta("tab", tab[0])
		tabs.add_child(b)
	box.add_child(holder)
	fill.call("team")
	_section(box, "Play calls (calls · yards a call)")
	for t in 2:
		box.add_child(_label(_calls_line(agg["calls"][t], Team.NAMES[t]), fs - 2))
	_rules_section(box, agg["brain_tally"], agg["coach_tally"], [main.game.teams[0]["coach"], main.game.teams[1]["coach"]] if main.game != null else [Library.coach(main.coaches[0]), Library.coach(main.coaches[1])])
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(_button("Sim ×10 again", func(): close_overlay(); main.run_batch(10)))
	row.add_child(_button("Sim ×50", func(): close_overlay(); main.run_batch(50)))
	row.add_child(_button("Teams", func(): open_teams()))
