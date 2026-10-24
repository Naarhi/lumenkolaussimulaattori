extends SceneTree
## Lumikentän yksikkötesti: pitkä lumisade ei hautaa pihaa.
## Ajo: godot --headless --path . -s tests/snow_test.gd

const SnowField := preload("res://scripts/snow_field.gd")


func _initialize() -> void:
	var snow := SnowField.new()
	snow.heights.resize(SnowField.CELLS_X * SnowField.CELLS_Z)
	snow.heights.fill(SnowField.INITIAL_DEPTH_CM)
	# Vuorokauden lumisade ja kymmenen myräkkää.
	for i in 24 * 60:
		snow.add_snow_everywhere(1, SnowField.SNOWFALL_MAX_DEPTH_CM)
	var after_snowfall: int = snow.heights[0]
	for i in 10:
		snow.add_snow_everywhere(8, SnowField.STORM_MAX_DEPTH_CM)
	var after_storms: int = snow.heights[0]
	var ok := after_snowfall == SnowField.SNOWFALL_MAX_DEPTH_CM and after_storms == SnowField.STORM_MAX_DEPTH_CM
	print("LUMITESTI sateen jälkeen %d cm, myräkkien jälkeen %d cm: %s" % [after_snowfall, after_storms, "OK" if ok else "FAIL"])
	snow.free()
	quit(0 if ok else 1)
