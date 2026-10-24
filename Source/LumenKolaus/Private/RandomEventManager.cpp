#include "RandomEventManager.h"

#include "EngineUtils.h"
#include "GameFramework/PlayerState.h"
#include "LumenKolaus.h"
#include "LumiGameState.h"
#include "SnowField.h"
#include "TimerManager.h"

#define LOCTEXT_NAMESPACE "LumiRandomEvents"

ARandomEventManager::ARandomEventManager()
{
	PrimaryActorTick.bCanEverTick = false;
	bReplicates = false;

	Events = {
		{ ELumiRandomEvent::AuraAuto, 3.f, LOCTEXT("AuraAuto", "Kunnan aura-auto jyrisi ohi ja puski penkan pihatielle!") },
		{ ELumiRandomEvent::Lumimyrsky, 2.f, LOCTEXT("Lumimyrsky", "Lumimyräkkä yllätti! Pihalle sataa lunta silmissä.") },
		{ ELumiRandomEvent::Hirvi, 1.f, LOCTEXT("Hirvi", "Hirvi käveli pihalle eikä aio lähteä mihinkään.") },
		{ ELumiRandomEvent::Pertti, 2.f, LOCTEXT("Pertti", "Naapurin Pertti tuli moottorikelkalla \"auttamaan\". Pihalla on nyt lumikasoja.") },
		{ ELumiRandomEvent::Kattolumi, 2.f, LOCTEXT("Kattolumi", "Katolta romahti lumikuorma pelaajan {0} niskaan!") },
	};
}

void ARandomEventManager::BeginPlay()
{
	Super::BeginPlay();

	if (HasAuthority())
	{
		ScheduleNextEvent();
	}
}

void ARandomEventManager::ScheduleNextEvent()
{
	const float Delay = FMath::FRandRange(MinIntervalSeconds, FMath::Max(MinIntervalSeconds, MaxIntervalSeconds));
	GetWorldTimerManager().SetTimer(EventTimer, this, &ARandomEventManager::FireRandomEvent, Delay, false);
}

void ARandomEventManager::FireRandomEvent()
{
	float TotalWeight = 0.f;
	for (const FLumiRandomEventDef& Def : Events)
	{
		TotalWeight += Def.Weight;
	}

	float Roll = FMath::FRand() * TotalWeight;
	for (const FLumiRandomEventDef& Def : Events)
	{
		Roll -= Def.Weight;
		if (Roll <= 0.f && Def.Weight > 0.f)
		{
			TriggerEvent(Def.Type);
			break;
		}
	}

	ScheduleNextEvent();
}

void ARandomEventManager::TriggerEvent(ELumiRandomEvent Type)
{
	if (!HasAuthority())
	{
		return;
	}

	const FLumiRandomEventDef* Def = Events.FindByPredicate([Type](const FLumiRandomEventDef& Candidate) { return Candidate.Type == Type; });
	ASnowField* Field = GetSnowField();
	APawn* TargetPawn = PickRandomPawn();
	if (!Def || !Field)
	{
		return;
	}

	switch (Type)
	{
	case ELumiRandomEvent::AuraAuto:
		// Penkka pihan tienpuoleiseen reunaan.
		Field->AddSnowLine(Field->GetCellCenterWorld(0, 3), Field->GetCellCenterWorld(Field->CellsX - 1, 3), 90.f, 45);
		break;

	case ELumiRandomEvent::Lumimyrsky:
		Field->AddSnowEverywhere(8);
		break;

	case ELumiRandomEvent::Pertti:
		for (int32 Pile = 0; Pile < 4; ++Pile)
		{
			Field->AddSnow(Field->GetRandomPointInField(), 80.f, 2500);
		}
		break;

	case ELumiRandomEvent::Kattolumi:
		if (!TargetPawn)
		{
			return;
		}
		Field->AddSnow(TargetPawn->GetActorLocation(), 70.f, 3000);
		break;

	case ELumiRandomEvent::Hirvi:
		// Pelkkä Blueprint-visuaali (OnRandomEvent).
		break;
	}

	UE_LOG(LogLumi, Log, TEXT("Satunnaistapahtuma: %s"), *UEnum::GetValueAsString(Type));
	Announce(*Def, TargetPawn);
	OnRandomEvent(Type, TargetPawn);
}

APawn* ARandomEventManager::PickRandomPawn() const
{
	TArray<APawn*> Pawns;
	for (TActorIterator<APawn> It(GetWorld()); It; ++It)
	{
		if (It->GetPlayerState())
		{
			Pawns.Add(*It);
		}
	}
	return Pawns.Num() > 0 ? Pawns[FMath::RandRange(0, Pawns.Num() - 1)] : nullptr;
}

ASnowField* ARandomEventManager::GetSnowField() const
{
	TActorIterator<ASnowField> It(GetWorld());
	return It ? *It : nullptr;
}

void ARandomEventManager::Announce(const FLumiRandomEventDef& Def, const APawn* TargetPawn) const
{
	if (ALumiGameState* GameState = GetWorld()->GetGameState<ALumiGameState>())
	{
		const FText PlayerName = TargetPawn ? FText::FromString(TargetPawn->GetPlayerState()->GetPlayerName()) : LOCTEXT("Someone", "joku");
		GameState->MulticastAnnounce(FText::Format(Def.Announcement, PlayerName));
	}
}

#undef LOCTEXT_NAMESPACE
