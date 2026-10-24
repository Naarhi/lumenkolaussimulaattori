#include "LumiPlayerState.h"

#include "Engine/Engine.h"
#include "Kismet/GameplayStatics.h"
#include "LumiRetroSounds.h"
#include "Net/UnrealNetwork.h"

namespace
{
	/** Table[L - 1] = tasoon L vaadittava XP. */
	const TArray<int32>& GetXPTable()
	{
		static const TArray<int32> Table = []
		{
			TArray<int32> Result;
			Result.Add(0);
			double Points = 0.0;
			for (int32 Level = 1; Level < ALumiPlayerState::MaxLevel; ++Level)
			{
				Points += FMath::FloorToDouble(Level + 300.0 * FMath::Pow(2.0, Level / 7.0));
				Result.Add(static_cast<int32>(FMath::FloorToDouble(Points / 4.0)));
			}
			return Result;
		}();
		return Table;
	}
}

void ALumiPlayerState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(ALumiPlayerState, KolausXP);
}

int32 ALumiPlayerState::XPForLevel(int32 Level)
{
	const TArray<int32>& Table = GetXPTable();
	return Table[FMath::Clamp(Level, 1, MaxLevel) - 1];
}

int32 ALumiPlayerState::LevelForXP(int32 XP)
{
	const TArray<int32>& Table = GetXPTable();
	int32 Level = 1;
	while (Level < MaxLevel && XP >= Table[Level])
	{
		++Level;
	}
	return Level;
}

void ALumiPlayerState::AddKolausXP(int32 Amount)
{
	check(HasAuthority());

	const int32 OldLevel = GetKolausLevel();
	KolausXP = FMath::Min(KolausXP + Amount, 200000000);
	const int32 NewLevel = GetKolausLevel();
	if (NewLevel > OldLevel)
	{
		ClientKolausLevelUp(NewLevel);
	}
}

void ALumiPlayerState::ClientKolausLevelUp_Implementation(int32 NewLevel)
{
	UGameplayStatics::PlaySound2D(this, LevelUpSound ? LevelUpSound.Get() : LumiRetroSounds::Create(this, ELumiRetroSound::LevelUp));
	if (GEngine)
	{
		GEngine->AddOnScreenDebugMessage(-1, 6.f, FColor::Yellow,
			FString::Printf(TEXT("Onneksi olkoon! Kolaustasosi on nyt %d."), NewLevel));
	}
	OnKolausLevelUp(NewLevel);
}
