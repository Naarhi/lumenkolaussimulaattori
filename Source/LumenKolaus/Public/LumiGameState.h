#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameStateBase.h"
#include "LumiGameState.generated.h"

class USoundBase;

UCLASS()
class LUMENKOLAUS_API ALumiGameState : public AGameStateBase
{
	GENERATED_BODY()

public:
	/** Ilmoitus kaikille pelaajille (esim. satunnaistapahtuma). Kutsu palvelimella. */
	UFUNCTION(NetMulticast, Reliable)
	void MulticastAnnounce(const FText& Message);

	UFUNCTION(BlueprintImplementableEvent, Category = "Ilmoitukset")
	void OnAnnouncement(const FText& Message);

	UPROPERTY(EditDefaultsOnly, Category = "Audio")
	TObjectPtr<USoundBase> AnnouncementSound;
};
