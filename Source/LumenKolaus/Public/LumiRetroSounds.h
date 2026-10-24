#pragma once

#include "CoreMinimal.h"

class USoundBase;

enum class ELumiRetroSound : uint8
{
	Scoop,
	Throw,
	LevelUp,
	Announcement
};

/**
 * Old School RuneScapen henkiset 8-bittiset ääniefektit, jotka syntetisoidaan koodissa.
 * Käytetään silloin, kun Blueprintissä ei ole asetettu omaa ääntä.
 */
namespace LumiRetroSounds
{
	/** Luo uuden kertasoittoon tarkoitetun äänen. Jokainen soitto tarvitsee oman instanssin. */
	LUMENKOLAUS_API USoundBase* Create(UObject* Outer, ELumiRetroSound Sound);
}
