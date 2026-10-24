#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "LumiCharacter.generated.h"

class ASnowField;
class UCameraComponent;
class UInputAction;
class UInputMappingContext;
class USoundBase;
class UStaticMeshComponent;
struct FInputActionValue;

/**
 * Ensimmäisen persoonan pelaaja, jolla on lumilapio.
 * Vasen hiiren nappi: kauho lunta, ja kun lapio on täynnä, heitä se eteenpäin.
 * Palvelin tekee kaikki lumimuutokset; asiakas lähettää vain painalluksen.
 */
UCLASS()
class LUMENKOLAUS_API ALumiCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	ALumiCharacter();

	virtual void Tick(float DeltaSeconds) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
	virtual void PawnClientRestart() override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	/** Lapiolla oleva lumi (cm x solu). 0 = lapio tyhjä. */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Lapio")
	int32 CarriedSnow = 0;

	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	float ShovelReachCm = 110.f;

	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	float ShovelRadiusCm = 25.f;

	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	float ThrowDistanceCm = 260.f;

	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	int32 ShovelCapacity = 400;

	/** Kuinka syvältä yksi kauhaisu ottaa lunta solusta. */
	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	int32 ShovelBiteCm = 15;

	UPROPERTY(EditDefaultsOnly, Category = "Lapio")
	float ShovelCooldownSeconds = 0.45f;

	UPROPERTY(EditDefaultsOnly, Category = "Lumi")
	float BaseWalkSpeed = 450.f;

	/** Kävelynopeus, kun lunta on DeepSnowDepthCm tai enemmän. */
	UPROPERTY(EditDefaultsOnly, Category = "Lumi")
	float DeepSnowWalkSpeed = 170.f;

	UPROPERTY(EditDefaultsOnly, Category = "Lumi")
	float DeepSnowDepthCm = 60.f;

	/** Kuinka monta senttiä lunta yksi askel painaa kasaan (jalanjäljet). */
	UPROPERTY(EditDefaultsOnly, Category = "Lumi")
	int32 FootprintDepthCm = 3;

	UPROPERTY(EditDefaultsOnly, Category = "Audio")
	TObjectPtr<USoundBase> ScoopSound;

	UPROPERTY(EditDefaultsOnly, Category = "Audio")
	TObjectPtr<USoundBase> ThrowSound;

	UPROPERTY(EditAnywhere, Category = "Ohjaus")
	float LookSensitivity = 0.4f;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Kamera")
	TObjectPtr<UCameraComponent> Camera;

	/** Väliaikainen vartalo, jonka muut pelaajat näkevät, kunnes oikea hahmomalli on tehty. */
	UPROPERTY(VisibleAnywhere, Category = "Ulkonako")
	TObjectPtr<UStaticMeshComponent> PlaceholderBody;

private:
	void EnsureInputObjects();
	void Move(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
	void ShovelPressed();
	ASnowField* GetSnowField();

	UFUNCTION(Server, Reliable)
	void ServerShovel();

	UFUNCTION(NetMulticast, Unreliable)
	void MulticastShovelFx(FVector_NetQuantize Location, bool bScoop);

	UPROPERTY(Transient)
	TObjectPtr<UInputMappingContext> MappingContext;

	UPROPERTY(Transient)
	TObjectPtr<UInputAction> MoveAction;

	UPROPERTY(Transient)
	TObjectPtr<UInputAction> LookAction;

	UPROPERTY(Transient)
	TObjectPtr<UInputAction> JumpAction;

	UPROPERTY(Transient)
	TObjectPtr<UInputAction> ShovelAction;

	TWeakObjectPtr<ASnowField> CachedSnowField;
	double LastShovelTime = -100.0;
	float FootprintTimer = 0.f;
};
