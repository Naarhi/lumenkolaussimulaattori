#include "LumiCharacter.h"

#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "Engine/StaticMesh.h"
#include "EngineUtils.h"
#include "InputAction.h"
#include "InputActionValue.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Kismet/GameplayStatics.h"
#include "LumiPlayerState.h"
#include "LumiRetroSounds.h"
#include "Net/UnrealNetwork.h"
#include "SnowField.h"
#include "UObject/ConstructorHelpers.h"

ALumiCharacter::ALumiCharacter()
{
	GetCapsuleComponent()->InitCapsuleSize(34.f, 88.f);

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(GetCapsuleComponent());
	Camera->SetRelativeLocation(FVector(0.f, 0.f, 64.f));
	Camera->bUsePawnControlRotation = true;

	PlaceholderBody = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderBody"));
	PlaceholderBody->SetupAttachment(GetCapsuleComponent());
	PlaceholderBody->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	PlaceholderBody->SetOwnerNoSee(true);
	PlaceholderBody->SetRelativeScale3D(FVector(0.68f, 0.68f, 1.76f));

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	if (CylinderMesh.Succeeded())
	{
		PlaceholderBody->SetStaticMesh(CylinderMesh.Object);
	}
}

void ALumiCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(ALumiCharacter, CarriedSnow);
}

void ALumiCharacter::EnsureInputObjects()
{
	if (MappingContext)
	{
		return;
	}

	// Ohjaimet luodaan koodissa, jotta projekti toimii heti ilman input-assetteja.
	MappingContext = NewObject<UInputMappingContext>(this, TEXT("IMC_Lumi"));

	MoveAction = NewObject<UInputAction>(this, TEXT("IA_Move"));
	MoveAction->ValueType = EInputActionValueType::Axis2D;
	LookAction = NewObject<UInputAction>(this, TEXT("IA_Look"));
	LookAction->ValueType = EInputActionValueType::Axis2D;
	JumpAction = NewObject<UInputAction>(this, TEXT("IA_Jump"));
	ShovelAction = NewObject<UInputAction>(this, TEXT("IA_Shovel"));

	auto MapMoveKey = [this](const FKey& Key, bool bSwizzle, bool bNegate)
	{
		FEnhancedActionKeyMapping& Mapping = MappingContext->MapKey(MoveAction, Key);
		if (bSwizzle)
		{
			Mapping.Modifiers.Add(NewObject<UInputModifierSwizzleAxis>(MappingContext));
		}
		if (bNegate)
		{
			Mapping.Modifiers.Add(NewObject<UInputModifierNegate>(MappingContext));
		}
	};
	MapMoveKey(EKeys::W, true, false);
	MapMoveKey(EKeys::S, true, true);
	MapMoveKey(EKeys::D, false, false);
	MapMoveKey(EKeys::A, false, true);

	MappingContext->MapKey(LookAction, EKeys::Mouse2D);
	MappingContext->MapKey(JumpAction, EKeys::SpaceBar);
	MappingContext->MapKey(ShovelAction, EKeys::LeftMouseButton);
}

void ALumiCharacter::PawnClientRestart()
{
	Super::PawnClientRestart();

	EnsureInputObjects();
	if (const APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			Subsystem->ClearAllMappings();
			Subsystem->AddMappingContext(MappingContext, 0);
		}
	}
}

void ALumiCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	EnsureInputObjects();
	if (UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(PlayerInputComponent))
	{
		Input->BindAction(MoveAction, ETriggerEvent::Triggered, this, &ALumiCharacter::Move);
		Input->BindAction(LookAction, ETriggerEvent::Triggered, this, &ALumiCharacter::Look);
		Input->BindAction(JumpAction, ETriggerEvent::Started, static_cast<ACharacter*>(this), &ACharacter::Jump);
		Input->BindAction(JumpAction, ETriggerEvent::Completed, static_cast<ACharacter*>(this), &ACharacter::StopJumping);
		Input->BindAction(ShovelAction, ETriggerEvent::Started, this, &ALumiCharacter::ShovelPressed);
	}
}

void ALumiCharacter::Move(const FInputActionValue& Value)
{
	const FVector2D Axis = Value.Get<FVector2D>();
	const FRotator YawRotation(0.f, GetControlRotation().Yaw, 0.f);
	const FRotationMatrix YawMatrix(YawRotation);
	AddMovementInput(YawMatrix.GetUnitAxis(EAxis::X), Axis.Y);
	AddMovementInput(YawMatrix.GetUnitAxis(EAxis::Y), Axis.X);
}

void ALumiCharacter::Look(const FInputActionValue& Value)
{
	const FVector2D Axis = Value.Get<FVector2D>() * LookSensitivity;
	AddControllerYawInput(Axis.X);
	AddControllerPitchInput(Axis.Y);
}

void ALumiCharacter::ShovelPressed()
{
	ServerShovel();
}

ASnowField* ALumiCharacter::GetSnowField()
{
	if (!CachedSnowField.IsValid())
	{
		TActorIterator<ASnowField> It(GetWorld());
		CachedSnowField = It ? *It : nullptr;
	}
	return CachedSnowField.Get();
}

void ALumiCharacter::ServerShovel_Implementation()
{
	const double Now = GetWorld()->GetTimeSeconds();
	if (Now - LastShovelTime < ShovelCooldownSeconds)
	{
		return;
	}
	LastShovelTime = Now;

	ASnowField* Field = GetSnowField();
	if (!Field)
	{
		return;
	}

	const FVector Forward = FRotator(0.f, GetControlRotation().Yaw, 0.f).Vector();
	const FVector Feet = GetActorLocation() - FVector(0.f, 0.f, GetCapsuleComponent()->GetScaledCapsuleHalfHeight());

	if (CarriedSnow == 0)
	{
		const FVector Target = Feet + Forward * ShovelReachCm;
		const int32 Removed = Field->RemoveSnow(Target, ShovelRadiusCm, ShovelCapacity, ShovelBiteCm);
		if (Removed > 0)
		{
			CarriedSnow = Removed;
			MulticastShovelFx(Target, true);
		}
	}
	else
	{
		const FVector Target = Feet + Forward * ThrowDistanceCm;
		Field->AddSnow(Target, ShovelRadiusCm * 1.6f, CarriedSnow);
		if (ALumiPlayerState* LumiPlayerState = GetPlayerState<ALumiPlayerState>())
		{
			LumiPlayerState->AddKolausXP(FMath::Max(1, CarriedSnow / 20));
		}
		CarriedSnow = 0;
		MulticastShovelFx(Target, false);
	}
}

void ALumiCharacter::MulticastShovelFx_Implementation(FVector_NetQuantize Location, bool bScoop)
{
	if (IsNetMode(NM_DedicatedServer))
	{
		return;
	}

	USoundBase* Sound = bScoop ? ScoopSound.Get() : ThrowSound.Get();
	if (!Sound)
	{
		Sound = LumiRetroSounds::Create(this, bScoop ? ELumiRetroSound::Scoop : ELumiRetroSound::Throw);
	}
	UGameplayStatics::PlaySoundAtLocation(this, Sound, Location);
}
