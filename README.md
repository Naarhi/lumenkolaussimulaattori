# Lumenkolaussimulaattori

Moninpelattava lumenkolaussimulaattori suomalaisessa pihapiirissä. Mallia otetaan My Summer Carista (ensimmäinen persoona, arkinen puuha, hulluja sattumuksia), ja äänet ja taitotasot tehdään Old School RuneScapen henkeen. Tehty Unreal Engine 5:llä.

## Mitä pohjassa on

| Osa | Tiedosto | Mitä tekee |
|---|---|---|
| Lumikenttä | `SnowField` | Pihan lumi 10 cm:n ruudukkona. Palvelin replikoi vain muuttuneet 16 x 16 solun palat. Lumi muotoutuu, kertyy hiljalleen lisää ja katoaa, kun sen heittää pihan ulkopuolelle. |
| Pelaaja | `LumiCharacter` | Ensimmäisen persoonan hahmo: WASD, hiiri, välilyönti. Vasen hiiren nappi kauhoo lunta lapiolle, ja seuraava painallus heittää sen eteenpäin. |
| Taidot | `LumiPlayerState` | Kolaus-taito ja XP. XP-käyrä on sama kuin OSRS:ssä (taso 2 = 83 XP, taso 99 = 13 034 431 XP). Level up -ääni ja -ilmoitus. |
| Satunnaistapahtumat | `RandomEventManager` | Aura-auto, lumimyräkkä, hirvi, naapurin Pertti ja kattolumi. Palvelin arpoo tapahtuman 1,5–4 minuutin välein. |
| Säännöt | `LumiGameMode` | Luo lumikentän, jos kartassa ei ole sellaista, ja käynnistää satunnaistapahtumat. |
| Yhdistäminen | `LumiPlayerController` | Konsolikomento `Liity` yhdistää kotipalvelimelle `himbe.jnarhi.fi:7777`. |

Kaikki pelin tila on palvelimella. Asiakas lähettää vain painallukset, joten kaikki näkevät saman pihan ja huijaaminen on vaikeaa.

## Aloitus (Windows-kehityskone)

1. Asenna **Unreal Engine 5.7** Epic Games Launcherista ja **Visual Studio 2022** (työkuorma "Game development with C++").
2. Asenna [Git LFS](https://git-lfs.com) ja kloonaa repo:
   ```
   git lfs install
   git clone https://github.com/Naarhi/lumenkolaussimulaattori.git
   ```
3. Avaa `LumenKolaus.uproject` ja vastaa "Yes", kun editori kysyy moduulin kääntämisestä. Jos käytät eri UE-versiota, klikkaa `.uproject`-tiedostoa oikealla ja valitse "Switch Unreal Engine version".
4. Tee ensimmäinen kartta: **File → New Level → Basic** ja tallenna se nimellä `Content/Maps/Piha`.
5. Paina **Play**. Lumikenttä (19 x 19 m) syntyy maailman keskelle automaattisesti.

### Lumen materiaali

Ilman omaa materiaalia lumi käyttää moottorin perusmateriaalia sinertävän valkoisena (*Fallback Snow Color*). Tee materiaali `M_Lumi` (esim. Base Color lähes valkoinen, Roughness 0.5–0.7, Subsurface-väri vaalean sininen) tai käytä Fabin Megascans-lumimateriaalia. Raahaa sitten **SnowField**-actor karttaan ja aseta materiaali kohtaan *Snow Material*. Karttaan sijoitettu kenttä korvaa automaattisen. Ruudukko alkaa actorin sijainnista ja jatkuu +X- ja +Y-suuntiin.

### Äänet (OSRS-henki)

Pelissä on valmiina koodissa syntetisoidut 8-bittiset äänet (kauhaisu, heitto, level up -fanfaari ja ilmoitus). Omat äänet korvaavat ne, kun ne asetetaan Blueprintissä.

Tee Blueprint-aliluokat `BP_LumiCharacter`, `BP_LumiPlayerState` ja `BP_LumiGameState`. Aseta niihin äänet (*Scoop Sound*, *Throw Sound*, *Level Up Sound*, *Announcement Sound*) ja aliluokat `BP_LumiGameMode`-luokkaan. Lyhyet, tömäkät retroäänet saa esimerkiksi [jsfxr](https://sfxr.me):llä. RuneScapen omia ääniä ei saa käyttää.

## Moninpelin testaus editorissa

**Play**-napin valikko → *Number of Players* = 2 ja *Net Mode* = **Play As Listen Server**. Molemmat ikkunat näkevät saman lumen.

Konsolikomennot (avaa konsoli §- tai `-näppäimellä):

| Komento | Mitä tekee |
|---|---|
| `Satunnaistapahtuma 0` | Aura-auto (1 = lumimyräkkä, 2 = hirvi, 3 = Pertti, 4 = kattolumi) |
| `Liity` | Yhdistää kotipalvelimelle `himbe.jnarhi.fi:7777` |
| `Liity 192.168.1.10:7777` | Yhdistää annettuun osoitteeseen |

## Dedikoitu palvelin kotipalvelimelle

Dedikoitu palvelin vaatii **lähdekoodista käännetyn Unreal Enginen**:

1. Yhdistä Epic Games -tili GitHubiin ([ohje](https://www.unrealengine.com/ue-on-github)), kloonaa `EpicGames/UnrealEngine` (sama versio kuin projektissa), aja `Setup.bat` ja `GenerateProjectFiles.bat` ja käännä Visual Studiossa.
2. Asenna Linux cross-compile -työkalut, joiden versio vastaa UE-versiota ([Epicin ohje](https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-requirements-for-unreal-engine)).
3. Paketoi palvelin:
   ```
   set UE_ROOT=C:\UnrealEngine
   Scripts\BuildLinuxServer.bat
   ```
   Tulos tulee kansioon `Out/LinuxServer/`.
4. Kopioi repo ja `Out/LinuxServer` kotipalvelimelle ja käynnistä:
   ```
   docker compose -f Docker/docker-compose.yml up -d --build
   ```
5. Reitittimessä on oltava ohjaus **UDP 7777** palvelimelle, ja DDNS:n on osoitettava `himbe.jnarhi.fi`-osoitteeseen.

Lokit: `docker compose -f Docker/docker-compose.yml logs -f`.

## Seuraavat askeleet

- Suomalainen omakotitalon piha: talo, puuaita, postilaatikko, pihavalot (Megascans / Fab)
- Lumipyry ja hengityshöyry Niagaralla, päivä- ja yökierto
- Lumen törmäys, jotta syvässä lumessa kävely hidastuu
- Hirvi-, Pertti- ja aura-autovisuaalit satunnaistapahtumiin
- Steam-yhdistäminen (Steam Datagram Relay) ja palvelinlista
