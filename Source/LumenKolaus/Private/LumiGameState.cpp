#include "LumiGameState.h"

#include "Engine/Engine.h"
#include "Kismet/GameplayStatics.h"

void ALumiGameState::MulticastAnnounce_Implementation(const FText& Message)
{
	if (IsNetMode(NM_DedicatedServer))
	{
		return;
	}

	if (AnnouncementSound)
	{
		UGameplayStatics::PlaySound2D(this, AnnouncementSound);
	}
	if (GEngine)
	{
		GEngine->AddOnScreenDebugMessage(-1, 8.f, FColor::Cyan, Message.ToString());
	}
	OnAnnouncement(Message);
}
