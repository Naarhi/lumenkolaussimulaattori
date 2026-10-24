#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerState.h"
#include "LumiPlayerState.generated.h"

class USoundBase;

/** Pelaajan taidot Old School RuneScapen tapaan: XP-käyrä on sama kuin OSRS:ssä (taso 99 = 13 034 431 XP). */
UCLASS()
class LUMENKOLAUS_API ALumiPlayerState : public APlayerState
{
	GENERATED_BODY()

public:
	static constexpr int32 MaxLevel = 99;

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	/** Vain palvelimella. */
	void AddKolausXP(int32 Amount);

	UFUNCTION(BlueprintPure, Category = "Taidot")
	int32 GetKolausLevel() const { return LevelForXP(KolausXP); }

	UFUNCTION(BlueprintPure, Category = "Taidot")
	static int32 XPForLevel(int32 Level);

	UFUNCTION(BlueprintPure, Category = "Taidot")
	static int32 LevelForXP(int32 XP);

	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Taidot")
	int32 KolausXP = 0;

	/** Level up -fanfaari. Aseta Blueprint-aliluokassa. */
	UPROPERTY(EditDefaultsOnly, Category = "Audio")
	TObjectPtr<USoundBase> LevelUpSound;

	/** UI:n koukku (esim. OSRS-tyylinen onnittelu-ikkuna). */
	UFUNCTION(BlueprintImplementableEvent, Category = "Taidot")
	void OnKolausLevelUp(int32 NewLevel);

protected:
	UFUNCTION(Client, Reliable)
	void ClientKolausLevelUp(int32 NewLevel);
};
