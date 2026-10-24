#include "LumiGameState.h"

#include "Engine/Engine.h"
#include "Kismet/GameplayStatics.h"
#include "LumiRetroSounds.h"

void ALumiGameState::MulticastAnnounce_Implementation(const FText& Message)
{
	if (IsNetMode(NM_DedicatedServer))
	{
		return;
	}

	UGameplayStatics::PlaySound2D(this, AnnouncementSound ? AnnouncementSound.Get() : LumiRetroSounds::Create(this, ELumiRetroSound::Announcement));
	if (GEngine)
	{
		GEngine->AddOnScreenDebugMessage(-1, 8.f, FColor::Cyan, Message.ToString());
	}
	OnAnnouncement(Message);
}
