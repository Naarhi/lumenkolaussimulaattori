extends SceneTree
## Lumikentän yksikkötesti: pitkä lumisade ei hautaa pihaa.
## Ajo: godot --headless --path . -s tests/snow_test.gd

const SnowField := preload("res://scripts/snow_field.gd")


func _initialize() -> void:
	var snow := SnowField.new()
	root.add_child(snow)
	_run.call_deferred(snow)


func _run(snow) -> void:
	snow.heights.resize(SnowField.CELLS_X * SnowField.CELLS_Z)
	snow.heights.fill(SnowField.INITIAL_DEPTH_CM)
	# Vuorokauden lumisade ja kymmenen myräkkää.
	for i in 24 * 60:
		snow.add_snow_everywhere(1, SnowField.SNOWFALL_MAX_DEPTH_CM)
	var after_snowfall: int = snow.heights[0]
	for i in 10:
		snow.add_snow_everywhere(8, SnowField.STORM_MAX_DEPTH_CM)
	var after_storms: int = snow.heights[0]
	# Suolattu kohta sulaa ja pysyy sulana lumisateessa.
	snow.salt_area(snow.cell_center(10, 10), 0.3, 600.0)
	for i in 60 * 30:
		snow.melt_salted(1.0 / 30.0)
		if i % 30 == 0:
			snow.add_snow_everywhere(1, SnowField.SNOWFALL_MAX_DEPTH_CM)
	var salted_depth: int = snow.heights[10 * SnowField.CELLS_X + 10]
	print("LUMITESTI suolattu kohta minuutin jälkeen %d cm" % salted_depth)
	var ok := salted_depth == 0 and after_snowfall == SnowField.SNOWFALL_MAX_DEPTH_CM and after_storms == SnowField.STORM_MAX_DEPTH_CM
	print("LUMITESTI sateen jälkeen %d cm, myräkkien jälkeen %d cm: %s" % [after_snowfall, after_storms, "OK" if ok else "FAIL"])
	snow.free()
	quit(0 if ok else 1)
