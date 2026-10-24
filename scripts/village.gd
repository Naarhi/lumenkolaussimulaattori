extends RefCounted
## Kylän kartta ja kauppojen valikoima: naapurien pihatiet, rautakauppa ja koneliike.
## Palvelin ja asiakkaat käyttävät samoja tietoja, joten maisema ja pelilogiikka pysyvät samoilla paikoilla.

const Tools := preload("res://scripts/tools.gd")

## Tie kulkee X-akselin suuntaisesti kotipihan eteläpuolella.
const ROAD_Z := 12.8
const ROAD_HALF_WIDTH := 1.6
const ROAD_FAR := ROAD_Z + ROAD_HALF_WIDTH

## Naapurien pihatiet tien eteläpuolella. x on pihatien keskikohta, w ja d leveys ja pituus metreinä.
## pay on palkkio, jonka naapuri maksaa, kun pihatie on kolattu.
const NEIGHBOURS := [
	{"name": "Mummo Hilkka", "x": -17.0, "w": 4.8, "d": 8.0, "pay": 25, "color": Color(0.85, 0.72, 0.25)},
	{"name": "Tapani", "x": 6.0, "w": 3.2, "d": 9.6, "pay": 20, "color": Color(0.3, 0.45, 0.6)},
	{"name": "Kauppisen perhe", "x": 26.0, "w": 6.4, "d": 9.6, "pay": 40, "color": Color(0.85, 0.85, 0.8)},
]
## Pihatie on kolattu, kun näin suuri osa siitä on enintään CLEARED_CM syvä.
const CLEARED_FRACTION := 0.88
const CLEARED_CM := 4
const NEIGHBOUR_START_CM := 20

## Naavaa kasvaa näin monen pihaa lähimmän matalan kuusen alla. Hirvi lähtee vain naavalla.
const NAAVA_TREES := 8
const NAAVA_RANGE := 1.8
const NAAVA_REGROW := 120.0

enum { RAUTAKAUPPA, KONELIIKE }

## Kaupat tien eteläpuolella. counter on tiskin paikka (seiso tässä ja paina E).
const SHOPS := [
	{"name": "Rautakauppa", "from": "rautakaupasta", "where": "tien länsipäässä", "x": -42.0, "color": Color(0.15, 0.35, 0.65)},
	{"name": "Koneliike", "from": "koneliikkeestä", "where": "tien itäpäässä", "x": 46.0, "color": Color(0.8, 0.45, 0.05)},
]
const SHOP_RANGE := 3.0
## Kaupan oven etäisyys tien reunasta.
const SHOP_SETBACK := 3.5

## Myytävät tavarat. tool kertoo, minkä työkalun ostos avaa. salt on suolakiloja.
const ITEMS := {
	"masi": {"name": "MASI-lumikola", "price": 35, "shop": RAUTAKAUPPA, "tool": Tools.MASI},
	"suola": {"name": "Suolasäkki 10 kg", "price": 8, "shop": RAUTAKAUPPA, "salt": 10.0},
	"linko": {"name": "Lumilinko", "price": 220, "shop": KONELIIKE, "tool": Tools.LINKO},
	"kelkka": {"name": "Moottorikelkka", "price": 350, "shop": KONELIIKE},
	"liekki": {"name": "Liekinheitin", "price": 600, "shop": KONELIIKE, "tool": Tools.LIEKKI},
}
const ITEM_ORDER := ["masi", "suola", "linko", "kelkka", "liekki"]


static func counter_position(shop: int) -> Vector3:
	return Vector3(SHOPS[shop]["x"], 0.0, ROAD_FAR + SHOP_SETBACK)


## Kauppa, jonka tiskillä pelaaja seisoo, tai -1.
static func shop_near(pos: Vector3) -> int:
	for i in SHOPS.size():
		var c := counter_position(i)
		if Vector2(pos.x - c.x, pos.z - c.z).length() < SHOP_RANGE:
			return i
	return -1


## Ostos, joka avaa työkalun, tai "" (lapio on aina mukana, suola vaatii säkin).
static func item_for_tool(tool: int) -> String:
	for id in ITEMS:
		if ITEMS[id].get("tool", -1) == tool:
			return id
	return ""


static func neighbour_origin(index: int) -> Vector3:
	var n: Dictionary = NEIGHBOURS[index]
	return Vector3(n["x"] - n["w"] * 0.5, 0.0, ROAD_FAR)
