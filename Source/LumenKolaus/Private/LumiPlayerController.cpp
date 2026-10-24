#include "LumiPlayerController.h"

#include "LumenKolaus.h"

void ALumiPlayerController::Liity(const FString& Address)
{
	const FString Target = Address.IsEmpty() ? DefaultServerAddress : Address;
	UE_LOG(LogLumi, Log, TEXT("Yhdistetään palvelimelle %s"), *Target);
	ClientTravel(Target, TRAVEL_Absolute);
}
