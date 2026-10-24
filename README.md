# Lumenkolaussimulaattori

Moninpelattava lumenkolaussimulaattori suomalaisessa pihapiirissä. Mallia otetaan My Summer Carista (ensimmäinen persoona, arkinen puuha, hulluja sattumuksia), ja äänet ja taitotasot tehdään Old School RuneScapen henkeen. Tehty **Godot 4.6**:lla (GDScript). Vanha Unreal-versio on haarassa `unreal-arkisto`.

## Pelaaminen

1. Lataa [uusin versio](https://github.com/Naarhi/lumenkolaussimulaattori/releases/tag/uusin): `Lumenkolaus-Windows.zip` (tai Linux).
2. Pura ja käynnistä `Lumenkolaus.exe`.
3. Valikossa:
   - **Liity peliin**: yhdistää osoitteeseen `himbe.jnarhi.fi` (UDP 7777). Muun palvelimen voi kirjoittaa muodossa `osoite[:portti]`.
   - **Isännöi peliä**: oma kone toimii palvelimena (avaa UDP 7777, jos kaverit tulevat netin yli).
   - **Yksinpeli**

Ohjaus: WASD liikkuu, Shift juoksee, välilyönti hyppää. Hiiren klikkaus kauhoo lunta lapiolle, ja seuraava klikkaus heittää sen. Esc vapauttaa hiiren.

## Mitä pelissä on

| Osa | Tiedosto | Mitä tekee |
|---|---|---|
| Verkko | `scripts/net.gd` | ENet-palvelin ja -asiakas, komentoriviparametrit ja näppäimet. |
| Lumikenttä | `scripts/snow_field.gd` | 19,2 x 19,2 m pihan lumi 10 cm:n ruudukkona. Palvelin lähettää vain muuttuneet 16 x 16 solun palat. Lunta sataa hiljalleen lisää. |
| Pelilogiikka | `scripts/main.gd` | Valikko, pelaajien luonti, lapio (kauho ja heitä), jalanjäljet ja XP. |
| Pelaaja | `scripts/player.gd` | Ensimmäisen persoonan hahmo. Syvä lumi hidastaa. |
| Taidot | `scripts/skills.gd` | Kolaus-taito OSRS:n XP-käyrällä (taso 2 = 83 XP, taso 99 = 13 034 431 XP). |
| Satunnaistapahtumat | `scripts/random_events.gd` | Aura-auto, lumimyräkkä, hirvi, naapurin Pertti moottorikelkalla ja kattolumi. 1,5–4 minuutin välein. |
| Äänet | `scripts/retro_sfx.gd` | OSRS-henkiset retroäänet syntetisoidaan koodissa, ei äänitiedostoja. |
| Maisema | `scripts/pihapiiri.gd` | Hämärä talvitaivas, punainen talo, sauna, aita, postilaatikko, katulamppu, kuusimetsä ja tie. |
| Käyttöliittymä | `scripts/hud.gd` | Päävalikko, OSRS-tyylinen chat, taitopaneeli ja tasonnousu. |

Kaikki pelin tila (lumi, XP, tapahtumat) on palvelimella. Asiakas lähettää vain lapion käytön, ja liike synkronoidaan muille.

## Kehitys

Avaa kansio Godot 4.6 -editorissa ja paina F5. Komentoriviltä:

```
godot --path . -- --host                 # isännöi
godot --path . -- --connect=127.0.0.1    # liity
godot --headless --path . -- --server    # pelkkä palvelin
tests/multiplayer_test.sh                # palvelin + 2 automaattista asiakasta
```

Muut parametrit: `--port=7777`, `--autotest`, `--screenshot=kuva.png`, `--event=0..4` (laukaisee tapahtuman testissä), `--yaw=astetta`.

GitHub Actions ajaa moninpelitestin jokaisesta muutoksesta ja julkaisee mainista Windows-, Linux- ja palvelinbuildit julkaisuun `uusin`.

## Kotipalvelin

Palvelinbuild `lumenkolaus-server.x86_64` käynnistyy suoraan palvelintilaan:

```
./lumenkolaus-server.x86_64 --headless -- --port=7777
```

Kotipalvelimella (Debian, `himbe.jnarhi.fi`) sitä ajaa systemd-palvelu `lumenkolaus` hakemistosta `/opt/lumenkolaus/server`.
