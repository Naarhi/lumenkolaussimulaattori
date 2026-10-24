#include "LumiGameMode.h"

#include "EngineUtils.h"
#include "LumiCharacter.h"
#include "LumiGameState.h"
#include "LumiPlayerController.h"
#include "LumiPlayerState.h"
#include "RandomEventManager.h"
#include "SnowField.h"

ALumiGameMode::ALumiGameMode()
{
	DefaultPawnClass = ALumiCharacter::StaticClass();
	PlayerControllerClass = ALumiPlayerController::StaticClass();
	PlayerStateClass = ALumiPlayerState::StaticClass();
	GameStateClass = ALumiGameState::StaticClass();
	SnowFieldClass = ASnowField::StaticClass();
	RandomEventManagerClass = ARandomEventManager::StaticClass();
}

void ALumiGameMode::BeginPlay()
{
	Super::BeginPlay();

	if (!TActorIterator<ASnowField>(GetWorld()) && SnowFieldClass)
	{
		// Keskitetään kenttä maailman origoon.
		const ASnowField* Defaults = SnowFieldClass->GetDefaultObject<ASnowField>();
		const FVector2D Size = Defaults->GetFieldSizeCm();
		GetWorld()->SpawnActor<ASnowField>(SnowFieldClass, FVector(-Size.X * 0.5f, -Size.Y * 0.5f, 0.f), FRotator::ZeroRotator);
	}

	if (RandomEventManagerClass)
	{
		RandomEventManager = GetWorld()->SpawnActor<ARandomEventManager>(RandomEventManagerClass);
	}
}

void ALumiGameMode::Satunnaistapahtuma(int32 EventIndex)
{
	if (RandomEventManager && EventIndex >= 0 && EventIndex <= static_cast<int32>(ELumiRandomEvent::Kattolumi))
	{
		RandomEventManager->TriggerEvent(static_cast<ELumiRandomEvent>(EventIndex));
	}
}
