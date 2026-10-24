# Lumenkolaussimulaattori

Godot 4.6 -projekti (GDScript). Käyttäjä kirjoittaa suomeksi.

- Kaikki rakennetaan koodissa: kohtaus `scenes/main.tscn` on pelkkä runko, ja pelaajat, maisema ja ajoneuvot luodaan skripteissä. Ei ulkoisia assetteja.
- Palvelin päättää lumesta, XP:stä ja tapahtumista. Asiakas lähettää vain `srv_shovel`-RPC:n. Pelaajan liike on asiakkaan omaa ja synkronoidaan MultiplayerSynchronizerilla.
- Lumi: `scripts/snow_field.gd`, korkeusruudukko 192 x 192 (cm), palat 16 x 16. Godot piirtää myötäpäivään kiertävät kolmiot etupuolina.
- Taidot: `scripts/skills.gd`, XP-käyrä sama kuin Old School RuneScapessa.
- Pelipalvelin: käyttäjän kotin Linux-kone, himbe.jnarhi.fi (DDNS), UDP 7777.
- Testaa pilvikontissa: `godot --headless --path . --import`, sitten `tests/multiplayer_test.sh`. Kuvakaappaus: `xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 -- --host --autotest --screenshot=kuva.png`.
- GDScript: pakatut taulukot (PackedByteArray ym.) välitetään arvona. Käytä tyypittämättömiä muuttujia solmuille, joiden omia funktioita kutsutaan.
- Kommentit ja pelaajalle näkyvät tekstit suomeksi. Koodin tunnisteet englanniksi, paitsi pelikäsitteet (Kolaus, Pertti, Pihapiiri...).
