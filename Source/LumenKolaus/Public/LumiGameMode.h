#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "LumiGameMode.generated.h"

class ARandomEventManager;
class ASnowField;

/** Pelin säännöt. Luo pihalle lumikentän, jos kartassa ei ole sellaista valmiina, sekä satunnaistapahtumat. */
UCLASS()
class LUMENKOLAUS_API ALumiGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ALumiGameMode();

	/** Konsolikomento testaukseen: "Satunnaistapahtuma 0" (0 = aura-auto ... 4 = kattolumi). */
	UFUNCTION(Exec)
	void Satunnaistapahtuma(int32 EventIndex);

	UPROPERTY(EditDefaultsOnly, Category = "Lumi")
	TSubclassOf<ASnowField> SnowFieldClass;

	UPROPERTY(EditDefaultsOnly, Category = "Satunnaistapahtumat")
	TSubclassOf<ARandomEventManager> RandomEventManagerClass;

protected:
	virtual void BeginPlay() override;

private:
	UPROPERTY(Transient)
	TObjectPtr<ARandomEventManager> RandomEventManager;
};
