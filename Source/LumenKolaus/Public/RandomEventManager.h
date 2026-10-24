#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "RandomEventManager.generated.h"

class ASnowField;

UENUM(BlueprintType)
enum class ELumiRandomEvent : uint8
{
	AuraAuto,
	Lumimyrsky,
	Hirvi,
	Pertti,
	Kattolumi
};

USTRUCT(BlueprintType)
struct FLumiRandomEventDef
{
	GENERATED_BODY()

	FLumiRandomEventDef() = default;
	FLumiRandomEventDef(ELumiRandomEvent InType, float InWeight, const FText& InAnnouncement)
		: Type(InType), Weight(InWeight), Announcement(InAnnouncement)
	{
	}

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tapahtuma")
	ELumiRandomEvent Type = ELumiRandomEvent::AuraAuto;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tapahtuma", meta = (ClampMin = 0))
	float Weight = 1.f;

	/** {0} korvataan kohteena olevan pelaajan nimellä. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tapahtuma")
	FText Announcement;
};

/**
 * Arpoo OSRS:n "random eventien" tapaisia hulluja tapahtumia. Elää vain palvelimella.
 * Visuaalit (hirvi, moottorikelkka, joulupukki) lisätään Blueprintissä OnRandomEvent-tapahtumaan.
 */
UCLASS()
class LUMENKOLAUS_API ARandomEventManager : public AActor
{
	GENERATED_BODY()

public:
	ARandomEventManager();

	UFUNCTION(BlueprintCallable, Category = "Satunnaistapahtumat")
	void TriggerEvent(ELumiRandomEvent Type);

	UFUNCTION(BlueprintImplementableEvent, Category = "Satunnaistapahtumat")
	void OnRandomEvent(ELumiRandomEvent Type, APawn* TargetPawn);

	UPROPERTY(EditAnywhere, Category = "Satunnaistapahtumat", meta = (ClampMin = 5))
	float MinIntervalSeconds = 90.f;

	UPROPERTY(EditAnywhere, Category = "Satunnaistapahtumat", meta = (ClampMin = 5))
	float MaxIntervalSeconds = 240.f;

	UPROPERTY(EditAnywhere, Category = "Satunnaistapahtumat")
	TArray<FLumiRandomEventDef> Events;

protected:
	virtual void BeginPlay() override;

private:
	void ScheduleNextEvent();
	void FireRandomEvent();
	APawn* PickRandomPawn() const;
	ASnowField* GetSnowField() const;
	void Announce(const FLumiRandomEventDef& Def, const APawn* TargetPawn) const;

	FTimerHandle EventTimer;
};
