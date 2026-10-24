extends Node
## Tarina "Kolaajan tie": Pertti opastaa uuden kolaajan kylän parhaaksi. Palvelin seuraa jokaisen
## pelaajan vaihetta (tallennetaan profiiliin) ja siirtää eteenpäin, kun oikea tapahtuma sattuu.

## Jokainen vaihe: otsikko, tehtävä, mitä Pertti sanoo alussa, tapahtuma joka vie eteenpäin ja palkkio.
const STEPS := [
	{"title": "Uusi kolaaja", "task": "Kolaa jonkun naapurin pihatie tien toisella puolella ja ota palkkio.",
		"intro": "Moro naapuri! Täällä on lunta enemmän kuin kukaan jaksaa kolata. Naapurit maksaa, kun pihatie on puhdas. Mee näyttään mallia!",
		"event": "paid", "reward": 10},
	{"title": "Kunnon kola", "task": "Osta MASI-lumikola rautakaupasta (tien länsipäässä).",
		"intro": "Ei tuolla lapiolla pitkälle pötkitä. Rautakaupassa on MASI, oikea kolaajan työkalu.",
		"event": "bought:masi", "reward": 10},
	{"title": "Mummon pihatie", "task": "Kolaa Mummo Hilkan pihatie ja kasaa lumet siististi lumikasaan.",
		"intro": "Mummo Hilkka on tarkka. Lumet kasaan eikä pitkin pihaa, niin saat koko palkkion.",
		"event": "tidy:0", "reward": 20},
	{"title": "Hirviongelma", "task": "Kun hirvi tulee pihalle, hae naavaa kuusen alta ja syötä se hirvelle.",
		"intro": "Täällä käy välillä hirvi. Se ei lähde ennen kuin saa naavaa, ja potkaisee jos menee liian lähelle tyhjin käsin.",
		"event": "fed_moose", "reward": 25},
	{"title": "Työnantaja", "task": "Palkkaa duunari Työnvälityksestä (kotipihaa vastapäätä).",
		"intro": "Kun hommia on paljon, palkkaa apuria. Muista vain, että palkka juoksee joka minuutti!",
		"event": "hired", "reward": 15},
	{"title": "Konevoimaa", "task": "Osta moottorikelkka koneliikkeestä (tien itäpäässä).",
		"intro": "Nyt alkaa olla rahaa. Koneliikkeessä on moottorikelkka, sillä pääsee kelkkapuistoon talon taakse.",
		"event": "bought:kelkka", "reward": 30},
	{"title": "Kelkkapuiston kuningas", "task": "Tee kelkkapuistossa spinni tai voltti (ilmassa Shift + A/D tai Shift + W/S).",
		"intro": "Mennäänpä kelkkapuistoon! Hyppyristä ilmaan ja Shift pohjaan. Älä vaan laskeudu katolleen.",
		"event": "trick", "reward": 40},
	{"title": "Kylän paras kolaaja", "task": "Nosta Kolaus-taso tasolle 10.",
		"intro": "Sinusta on tullut aikamoinen kolaaja. Vielä pari pihaa, niin koko kylä tietää nimesi.",
		"event": "level:10", "reward": 100},
]
const DONE_TEXT := "Olet kylän paras kolaaja! Pertti tarjoaa Jallu-colat ja naapurit kiittävät."

## Palvelin: {pelaaja: vaiheen indeksi}. STEPS.size() tarkoittaa, että tarina on läpi.
var _step := {}


## Palvelin: pelaaja liittyi, saved on tallennettu vaihe.
func start(peer: int, saved: int) -> void:
	_step[peer] = clampi(saved, 0, STEPS.size())
	_cl_step.rpc_id(peer, _step[peer], true)


func forget(peer: int) -> void:
	_step.erase(peer)


func step_of(peer: int) -> int:
	return _step.get(peer, 0)


## Palvelin: jotain tapahtui. event on esim. "paid", "bought:masi" tai "level:10".
func progress(peer: int, event: String) -> void:
	if not _step.has(peer) or _step[peer] >= STEPS.size():
		return
	var want: String = STEPS[_step[peer]]["event"]
	if not _matches(want, event):
		return
	var main = get_parent()
	var step: Dictionary = STEPS[_step[peer]]
	_step[peer] += 1
	main.add_money(peer, step["reward"])
	main.announce("%s suoritti tehtävän \"%s\"!" % [main.display_name_for(peer)[0], step["title"]])
	main.story_changed(peer)
	_cl_step.rpc_id(peer, _step[peer], false)


## level:N täyttyy myös suuremmalla tasolla.
static func _matches(want: String, event: String) -> bool:
	if want.begins_with("level:") and event.begins_with("level:"):
		return int(event.get_slice(":", 1)) >= int(want.get_slice(":", 1))
	return want == event


@rpc("authority", "call_local", "reliable")
func _cl_step(index: int, joined: bool) -> void:
	var main = get_parent()
	if main.dedicated:
		main.story_step = index
		return
	main.story_step = index
	if index >= STEPS.size():
		main.hud.set_quest("Tarina läpäisty", DONE_TEXT)
		if not joined:
			main.hud.chat("Pertti: \"%s\"" % DONE_TEXT, Color(1.0, 0.85, 0.4))
		return
	var step: Dictionary = STEPS[index]
	main.hud.set_quest("%d/%d %s" % [index + 1, STEPS.size(), step["title"]], step["task"])
	main.hud.chat("Pertti: \"%s\"" % step["intro"], Color(1.0, 0.85, 0.4))
