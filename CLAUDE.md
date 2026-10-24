# Lumenkolaussimulaattori

Unreal Engine 5 C++ -projekti, moduuli `LumenKolaus` (Source/LumenKolaus). Käyttäjä kirjoittaa suomeksi.

- Palvelin päättää kaikesta (authoritative). Asiakas lähettää vain syötteet RPC:llä.
- Lumi: `ASnowField`, korkeusruudukko FFastArraySerializer-paloina (16 x 16 solua).
- Taidot ja XP: `ALumiPlayerState`, XP-käyrä on sama kuin Old School RuneScapessa.
- Satunnaistapahtumat: `ARandomEventManager`, vain palvelimella.
- Pelipalvelin: käyttäjän kotin Linux-kone, himbe.jnarhi.fi (DDNS), UDP 7777. Docker-tiedostot ovat kansiossa Docker/.
- Koodia ei voi kääntää pilvikontissa (ei UE:tä). Käännä ja testaa käyttäjän Windows-koneella.
- Kommentit ja pelaajalle näkyvät tekstit suomeksi. Koodin tunnisteet englanniksi, paitsi pelikäsitteet (Kolaus, Pertti...).
