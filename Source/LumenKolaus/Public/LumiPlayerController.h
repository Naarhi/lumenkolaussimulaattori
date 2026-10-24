#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "LumiPlayerController.generated.h"

UCLASS(Config = Game)
class LUMENKOLAUS_API ALumiPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	/** Konsolikomento: "Liity" yhdistää oletuspalvelimelle, "Liity osoite:portti" muualle. */
	UFUNCTION(Exec)
	void Liity(const FString& Address = TEXT(""));

	/** Kotipalvelimen DDNS-osoite, asetetaan DefaultGame.ini:ssä. */
	UPROPERTY(Config, EditDefaultsOnly, Category = "Verkko")
	FString DefaultServerAddress = TEXT("himbe.jnarhi.fi:7777");
};
