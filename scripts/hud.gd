extends CanvasLayer
## Käyttöliittymä: päävalikko, OSRS-tyylinen chat-laatikko, taitopaneeli ja tasonnousu.

const Skills := preload("res://scripts/skills.gd")
const Tools := preload("res://scripts/tools.gd")
const Village := preload("res://scripts/village.gd")

const OSRS_BROWN := Color(0.24, 0.2, 0.15, 0.92)
const OSRS_BORDER := Color(0.1, 0.08, 0.05)
const OSRS_YELLOW := Color(1.0, 0.9, 0.2)
const CHAT_LINES := 8

var xp := 0

var _menu: Control
var _menu_message: Label
var _address: LineEdit
var _name: LineEdit
var _chat_input: LineEdit
## Tosi, kun pelaaja kirjoittaa chattiin (liike ja lapio pois päältä).
var typing := false
## Tosi, kun Esc-valikko on auki.
var paused := false
var _pause: Control
var _status: Label
var _game: Control
var _chat: VBoxContainer
var _skill_label: Label
var _xp_bar: ProgressBar
var _carry_label: Label
var _popup: Label
var _quest_title: Label
var _quest_task: Label
var _tool_labels: Array[Label] = []
var _hint: Label
var _boost_label: Label
var _money_label: Label
var _health_label: Label
var _naava_label: Label
var _flash: ColorRect
## Oma kunto (palvelin lähettää).
var health := 100
## Kauppaikkuna: auki oleva kauppa tai -1.
var shop := -1
var _shop: Control
var _shop_title: Label
var _shop_rows: VBoxContainer
var _shop_money: Label
var _tool_owned: Array = [true, false, false, false, false]
var _selected_tool := 0


func _ready() -> void:
	_build_game_ui()
	_build_pause_menu()
	_build_shop()
	_build_menu()
	_game.visible = false
	_menu.visible = false


# --- Valikko ---------------------------------------------------------------

## Tosi, kun pelaajan ohjaus on pois päältä (chat tai valikko).
func blocks_input() -> bool:
	return typing or paused or shop >= 0


func show_menu(main, message := "") -> void:
	_menu.set_meta("main", main)
	_close_pause(false)
	close_shop(false)
	_menu.visible = true
	_game.visible = false
	Music.set_playing(true)
	_status.visible = false
	_menu_message.text = message
	_menu_message.visible = message != ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_menu() -> void:
	_menu.visible = false
	Music.set_playing(false)
	_status.visible = false


func show_game() -> void:
	_game.visible = true


func show_status(text: String) -> void:
	_menu.visible = false
	_status.text = text
	_status.visible = true


func _build_menu() -> void:
	_menu = ColorRect.new()
	(_menu as ColorRect).color = Color(0.05, 0.07, 0.12, 0.55)
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _osrs_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(440, 0)
	_menu.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := _label("LUMENKOLAUSSIMULAATTORI", 30, OSRS_YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label("Piha ei kolaa itseään.", 16, Color(0.9, 0.85, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	_menu_message = _label("", 15, Color(1.0, 0.45, 0.35))
	_menu_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_menu_message)

	_name = LineEdit.new()
	_name.text = Net.cli.get("name", "Kolaaja%d" % randi_range(100, 999))
	_name.placeholder_text = "nimesi"
	_name.max_length = 16
	box.add_child(_name)

	_address = LineEdit.new()
	_address.text = Net.DEFAULT_ADDRESS
	_address.placeholder_text = "palvelimen osoite[:portti]"
	box.add_child(_address)

	box.add_child(_button("Liity peliin", func(): _main().join_game(_address.text.strip_edges())))
	box.add_child(_button("Isännöi peliä (portti %d)" % Net.port(), func(): _main().start_host()))
	box.add_child(_button("Yksinpeli", func(): _main().start_singleplayer()))
	box.add_child(_button("Lopeta", func(): get_tree().quit()))

	var help := _label("WASD liiku · Shift juokse · Välilyönti hyppää · Enter chat\n1–5 tai rulla vaihtaa työkalua · Hiiri: käytä · E juo / kauppa · F kelkka · Z X C V tanssit · Esc valikko\nNaapurit maksavat pihateidensä kolaamisesta. Kelkkapuisto on talon pohjoispuolella: ilmassa Shift + A/D pyörii, Shift + W/S volttaa.", 13, Color(0.8, 0.78, 0.7))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)

	_status = _label("", 22, Color.WHITE)
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.visible = false
	add_child(_status)


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Kolaaja"


func _main():
	return _menu.get_meta("main")


# --- Pelinäkymä -------------------------------------------------------------

func _build_game_ui() -> void:
	_game = Control.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game)

	var crosshair := _label("+", 22, Color(1, 1, 1, 0.8))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game.add_child(crosshair)

	# Chat vasempaan alakulmaan kuten OSRS:ssä.
	var chat_panel := PanelContainer.new()
	chat_panel.add_theme_stylebox_override("panel", _osrs_box())
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_panel.position = Vector2(12, -12)
	chat_panel.custom_minimum_size = Vector2(520, 0)
	chat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(chat_panel)
	_chat = VBoxContainer.new()
	_chat.alignment = BoxContainer.ALIGNMENT_END
	_chat.add_theme_constant_override("separation", 1)
	var chat_box := VBoxContainer.new()
	chat_panel.add_child(chat_box)
	chat_box.add_child(_chat)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Kirjoita viesti ja paina Enter"
	_chat_input.max_length = 120
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	chat_box.add_child(_chat_input)
	chat("Tervetuloa kylään! Naapurit maksavat kolauksesta, ja Pertti neuvoo alkuun (tehtävä vasemmalla ylhäällä).", Color.WHITE)

	# Taitopaneeli oikeaan yläkulmaan.
	var skill_panel := PanelContainer.new()
	skill_panel.add_theme_stylebox_override("panel", _osrs_box())
	skill_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skill_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skill_panel.position = Vector2(-12, 12)
	skill_panel.custom_minimum_size = Vector2(240, 0)
	skill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(skill_panel)
	var skill_box := VBoxContainer.new()
	skill_panel.add_child(skill_box)
	_skill_label = _label("", 18, OSRS_YELLOW)
	skill_box.add_child(_skill_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.75, 0.2)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.45, 0.1, 0.08)
	_xp_bar.add_theme_stylebox_override("background", bg)
	skill_box.add_child(_xp_bar)
	_carry_label = _label("", 14, Color(0.85, 0.9, 1.0))
	skill_box.add_child(_carry_label)
	_boost_label = _label("", 15, Color(1.0, 0.75, 0.3))
	skill_box.add_child(_boost_label)
	_money_label = _label("Rahaa: 0 €", 17, Color(0.55, 1.0, 0.45))
	skill_box.add_child(_money_label)
	_health_label = _label("", 16, Color(1.0, 0.45, 0.4))
	_health_label.visible = false
	skill_box.add_child(_health_label)
	_naava_label = _label("Naavaa mukana: vie hirvelle", 15, Color(0.7, 0.85, 0.6))
	_naava_label.visible = false
	skill_box.add_child(_naava_label)
	# Tarinan tehtävä vasemmassa yläkulmassa.
	var quest_panel := PanelContainer.new()
	quest_panel.add_theme_stylebox_override("panel", _osrs_box())
	quest_panel.position = Vector2(12, 12)
	quest_panel.custom_minimum_size = Vector2(300, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(quest_panel)
	var quest_box := VBoxContainer.new()
	quest_panel.add_child(quest_box)
	_quest_title = _label("Tehtävä", 17, OSRS_YELLOW)
	quest_box.add_child(_quest_title)
	_quest_task = _label("", 14, Color(0.9, 0.88, 0.8))
	_quest_task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_task.custom_minimum_size.x = 300
	quest_box.add_child(_quest_task)
	quest_panel.visible = false
	_quest_title.set_meta("panel", quest_panel)
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(_flash)
	set_xp(0)
	set_carrying(0)
	set_boost(0.0)

	_hint = _label("", 20, Color.WHITE)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y = 140
	_game.add_child(_hint)

	# Työkalupalkki alas keskelle
	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", _osrs_box())
	bar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_panel.position.y = -12
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	bar_panel.add_child(bar)
	for i in Tools.COUNT:
		var l := _label("%d %s" % [i + 1, Tools.NAMES[i]], 15, Color.WHITE)
		bar.add_child(l)
		_tool_labels.append(l)
	set_inventory(0, [], 0.0)

	_popup = _label("", 36, OSRS_YELLOW)
	_popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.position.y = 140
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.add_theme_color_override("font_outline_color", Color.BLACK)
	_popup.add_theme_constant_override("outline_size", 6)
	_popup.modulate.a = 0.0
	_game.add_child(_popup)


func set_xp(value: int) -> void:
	xp = value
	var level := Skills.level_for_xp(xp)
	_skill_label.text = "Kolaus  %d / 99   (%s XP)" % [level, _thousands(xp)]
	if level >= Skills.MAX_LEVEL:
		_xp_bar.value = 100.0
	else:
		var low := Skills.xp_for_level(level)
		var high := Skills.xp_for_level(level + 1)
		_xp_bar.value = 100.0 * float(xp - low) / float(high - low)
	_skill_label.tooltip_text = "Seuraavaan tasoon %d XP" % (Skills.xp_for_level(level + 1) - xp)


func set_tool(index: int) -> void:
	_selected_tool = index
	for i in _tool_labels.size():
		var color := OSRS_YELLOW if i == index else Color(0.75, 0.72, 0.65)
		if not _tool_owned[i]:
			color = Color(0.45, 0.42, 0.38)
		_tool_labels[i].add_theme_color_override("font_color", color)


## Rahat ja ostetut tavarat palvelimelta. Ostamattomat työkalut näkyvät harmaina hintoineen.
func set_inventory(money: int, owned: Array, salt: float) -> void:
	_money_label.text = "Rahaa: %s €" % _thousands(money)
	for i in Tools.COUNT:
		var item := Village.item_for_tool(i)
		if i == Tools.SUOLA:
			_tool_owned[i] = salt > 0.0
			_tool_labels[i].text = "%d Suola %.1f kg" % [i + 1, salt] if salt > 0.0 else "%d Suola (8 €)" % (i + 1)
		else:
			_tool_owned[i] = item == "" or item in owned
			var price := "" if _tool_owned[i] else " (%d €)" % Village.ITEMS[item]["price"]
			_tool_labels[i].text = "%d %s%s" % [i + 1, Tools.NAMES[i], price]
	set_tool(_selected_tool)
	if shop >= 0:
		_fill_shop()


func set_health(value: int, hit: bool) -> void:
	health = value
	_health_label.text = "Kunto %d / 100" % value
	_health_label.visible = value < 100
	if hit:
		_flash.color.a = 0.45
		create_tween().tween_property(_flash, "color:a", 0.0, 0.6)


func set_naava(carrying: bool) -> void:
	_naava_label.visible = carrying


func tool_locked(tool: int) -> void:
	var item := "suola" if tool == Tools.SUOLA else Village.item_for_tool(tool)
	var where: Dictionary = Village.SHOPS[Village.ITEMS[item]["shop"]]
	chat("%s: osta ensin %s (%s)." % [Tools.NAMES[tool], where["from"], where["where"]], Color(1.0, 0.75, 0.4))


func set_hint(text: String) -> void:
	if _hint.text != text:
		_hint.text = text


func set_boost(seconds: float) -> void:
	var text := "Jallu-boosti %d s" % ceili(seconds) if seconds > 0.0 else ""
	_boost_label.visible = text != ""
	if _boost_label.text != text:
		_boost_label.text = text


func set_carrying(amount: int) -> void:
	_carry_label.text = "Lapiossa lunta: %d" % amount if amount > 0 else "Lapio tyhjä"


func chat(text: String, color := Color.WHITE) -> void:
	var line := _label(text, 15, color)
	line.add_theme_color_override("font_shadow_color", Color.BLACK)
	line.add_theme_constant_override("shadow_offset_x", 1)
	line.add_theme_constant_override("shadow_offset_y", 1)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 500
	_chat.add_child(line)
	while _chat.get_child_count() > CHAT_LINES:
		var old := _chat.get_child(0)
		_chat.remove_child(old)
		old.queue_free()


func _input(event: InputEvent) -> void:
	if not _game.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not typing and not paused and shop < 0 and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_T]:
		typing = true
		_chat_input.visible = true
		_chat_input.text = ""
		_chat_input.grab_focus.call_deferred()
		get_viewport().set_input_as_handled()
	elif shop >= 0 and event.physical_keycode in [KEY_ESCAPE, KEY_E]:
		close_shop(true)
		get_viewport().set_input_as_handled()
	elif typing and event.physical_keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE:
		if paused:
			_close_pause(true)
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


# --- Esc-valikko --------------------------------------------------------------------

func _build_pause_menu() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.45)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _osrs_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(380, 0)
	_pause.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label("Tauko", 26, OSRS_YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_button("Jatka kolaamista", func(): _close_pause(true)))
	box.add_child(_volume_slider("Efektit", Sfx.BUS))
	box.add_child(_volume_slider("Musiikki", Music.BUS))
	box.add_child(_button("Poistu päävalikkoon", func(): _main().leave_game()))
	box.add_child(_button("Lopeta peli", func(): get_tree().quit()))


func _volume_slider(title: String, bus_name: String) -> Control:
	var row := HBoxContainer.new()
	var l := _label(title, 17, Color(0.95, 0.9, 0.75))
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.get_volume(bus_name)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float):
		Sfx.set_volume(bus_name, v)
		if bus_name == Sfx.BUS:
			Sfx.play_2d(Sfx.SCOOP))
	row.add_child(slider)
	return row


func _open_pause() -> void:
	paused = true
	_pause.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause(recapture: bool) -> void:
	paused = false
	_pause.visible = false
	if recapture and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Kauppa ------------------------------------------------------------------------

func _build_shop() -> void:
	_shop = ColorRect.new()
	(_shop as ColorRect).color = Color(0, 0, 0, 0.35)
	_shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.visible = false
	add_child(_shop)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _osrs_box())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(460, 0)
	_shop.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_shop_title = _label("", 26, OSRS_YELLOW)
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_shop_title)
	_shop_money = _label("", 17, Color(0.55, 1.0, 0.45))
	_shop_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_shop_money)
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 6)
	box.add_child(_shop_rows)
	box.add_child(_button("Sulje (Esc)", func(): close_shop(true)))


func open_shop(index: int) -> void:
	shop = index
	_shop.visible = true
	_shop_title.text = Village.SHOPS[index]["name"]
	_fill_shop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop(recapture: bool) -> void:
	shop = -1
	_shop.visible = false
	if recapture and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _fill_shop() -> void:
	var main = get_tree().current_scene
	_shop_money.text = "Rahaa: %s €" % _thousands(main.money)
	for child in _shop_rows.get_children():
		child.queue_free()
	if shop == Village.TYONVALITYS:
		var note := _label("Duunarit kolaavat tilattuja pihateitä ja kasaavat lumet. Palkka veloitetaan minuutin välein, ja jos rahat loppuvat, duunari lähtee kotiin.", 15, Color(0.8, 0.85, 0.9))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 420
		_shop_rows.add_child(note)
	for id in Village.ITEM_ORDER:
		var info: Dictionary = Village.ITEMS[id]
		if info["shop"] != shop:
			continue
		var row := HBoxContainer.new()
		var text := "%s  %d €" % [info["name"], info["price"]]
		if info.has("worker"):
			text = "%s  %d € + %d €/min" % [info["name"], info["price"], info["wage"]]
		var name_label := _label(text, 18, Color(0.95, 0.9, 0.75))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var b: Button
		if info.has("worker"):
			var working: bool = id in main.hired
			b = _button("Irtisano" if working else "Palkkaa", func(): main.buy(id))
			b.disabled = not working and main.money < info["price"]
		else:
			var have: bool = not info.has("salt") and id in main.owned
			b = _button("Omistat" if have else "Osta", func(): main.buy(id))
			b.disabled = have or main.money < info["price"]
		b.custom_minimum_size.x = 110
		row.add_child(b)
		_shop_rows.add_child(row)


func _on_chat_submitted(text: String) -> void:
	_close_chat()
	if text.strip_edges() != "":
		_main().send_chat(text)


func _close_chat() -> void:
	typing = false
	_chat_input.release_focus()
	_chat_input.visible = false


func set_quest(title: String, task: String) -> void:
	_quest_title.text = "Tehtävä: " + title
	_quest_task.text = task
	_quest_title.get_meta("panel").visible = true


func stunt_popup(text: String) -> void:
	_popup.text = text
	_popup.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_popup, "modulate:a", 0.0, 0.8)


func level_up_popup(level: int) -> void:
	_popup.text = "Kolaus-taso %d!" % level
	_popup.modulate.a = 1.0
	_popup.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_popup, "modulate:a", 0.0, 1.0)


# --- Apufunktiot --------------------------------------------------------------

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", OSRS_YELLOW)
	var normal := _osrs_box()
	normal.bg_color = Color(0.32, 0.27, 0.2)
	b.add_theme_stylebox_override("normal", normal)
	var hover := _osrs_box()
	hover.bg_color = Color(0.42, 0.36, 0.26)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		Sfx.play_2d(Sfx.FOOTSTEP)
		action.call())
	return b


func _osrs_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = OSRS_BROWN
	s.border_color = OSRS_BORDER
	s.set_border_width_all(3)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(12)
	return s


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
