#include "SnowField.h"

#include "KismetProceduralMeshLibrary.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Net/UnrealNetwork.h"
#include "ProceduralMeshComponent.h"
#include "UObject/ConstructorHelpers.h"

void FSnowChunk::PostReplicatedAdd(const FSnowChunkArray& InArraySerializer)
{
	if (InArraySerializer.Owner)
	{
		InArraySerializer.Owner->OnChunkReplicated(*this, static_cast<int32>(this - InArraySerializer.Items.GetData()));
	}
}

void FSnowChunk::PostReplicatedChange(const FSnowChunkArray& InArraySerializer)
{
	PostReplicatedAdd(InArraySerializer);
}

ASnowField::ASnowField()
{
	PrimaryActorTick.bCanEverTick = true;
	bReplicates = true;
	bAlwaysRelevant = true;
	SetNetUpdateFrequency(10.f);

	Mesh = CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("SnowMesh"));
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Mesh->bUseAsyncCooking = true;
	RootComponent = Mesh;

	static ConstructorHelpers::FObjectFinder<UMaterialInterface> BasicMaterial(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
	if (BasicMaterial.Succeeded())
	{
		FallbackBaseMaterial = BasicMaterial.Object;
	}
}

void ASnowField::PostInitializeComponents()
{
	Super::PostInitializeComponents();

	Chunks.Owner = this;
	NumChunksX = FMath::DivideAndRoundUp(CellsX, ChunkSize);
	NumChunksY = FMath::DivideAndRoundUp(CellsY, ChunkSize);
	ChunkToItem.Init(INDEX_NONE, NumChunksX * NumChunksY);

	// Winding false: kolmiot osoittavat ylöspäin, kun verteksit ovat X-pääjärjestyksessä.
	UKismetProceduralMeshLibrary::CreateGridMeshTriangles(ChunkSize + 1, ChunkSize + 1, false, GridTriangles);

	ActiveSnowMaterial = SnowMaterial;
	if (!ActiveSnowMaterial && FallbackBaseMaterial && !IsNetMode(NM_DedicatedServer))
	{
		UMaterialInstanceDynamic* Fallback = UMaterialInstanceDynamic::Create(FallbackBaseMaterial, this);
		Fallback->SetVectorParameterValue(TEXT("Color"), FallbackSnowColor);
		ActiveSnowMaterial = Fallback;
	}
}

void ASnowField::BeginPlay()
{
	Super::BeginPlay();

	if (!HasAuthority())
	{
		return;
	}

	const int32 NumChunks = NumChunksX * NumChunksY;
	const uint8 StartDepth = static_cast<uint8>(FMath::Clamp(InitialDepthCm, 0, MaxDepthCm));
	Chunks.Items.SetNum(NumChunks);
	for (int32 Index = 0; Index < NumChunks; ++Index)
	{
		FSnowChunk& Chunk = Chunks.Items[Index];
		Chunk.ChunkIndex = Index;
		Chunk.Heights.Init(StartDepth, ChunkSize * ChunkSize);
		ChunkToItem[Index] = Index;
		Chunks.MarkItemDirty(Chunk);
		QueueMeshRebuild(Index);
	}
}

void ASnowField::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (HasAuthority())
	{
		SnowfallAccumulator += SnowfallCmPerMinute * DeltaSeconds / 60.f;
		if (SnowfallAccumulator >= 1.f)
		{
			const int32 WholeCm = FMath::FloorToInt(SnowfallAccumulator);
			SnowfallAccumulator -= WholeCm;
			AddSnowEverywhere(WholeCm);
		}
		FlushDirtyChunks();
	}

	RebuildQueuedMeshes();
}

void ASnowField::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(ASnowField, Chunks);
}

int32 ASnowField::RemoveSnow(const FVector& WorldLocation, float RadiusCm, int32 MaxAmount, int32 MaxDepthPerCell)
{
	check(HasAuthority());

	int32 Removed = 0;
	ForEachCellInRadius(WorldLocation, RadiusCm, [&](int32 X, int32 Y, float)
	{
		const int32 Want = FMath::Min(MaxDepthPerCell, MaxAmount - Removed);
		if (Want > 0)
		{
			Removed -= ChangeCellHeight(X, Y, -Want);
		}
	});
	return Removed;
}

void ASnowField::AddSnow(const FVector& WorldLocation, float RadiusCm, int32 Amount)
{
	check(HasAuthority());

	// Kasa: keskelle eniten, reunoille vähemmän.
	TArray<TPair<FIntPoint, float>> Cells;
	float TotalWeight = 0.f;
	ForEachCellInRadius(WorldLocation, RadiusCm, [&](int32 X, int32 Y, float Distance)
	{
		const float Weight = 1.1f - Distance / RadiusCm;
		Cells.Emplace(FIntPoint(X, Y), Weight);
		TotalWeight += Weight;
	});

	for (const TPair<FIntPoint, float>& Cell : Cells)
	{
		const int32 Share = FMath::RoundToInt(Amount * Cell.Value / TotalWeight);
		ChangeCellHeight(Cell.Key.X, Cell.Key.Y, Share);
	}
}

void ASnowField::AddSnowEverywhere(int32 DepthCm)
{
	check(HasAuthority());

	for (int32 Y = 0; Y < CellsY; ++Y)
	{
		for (int32 X = 0; X < CellsX; ++X)
		{
			ChangeCellHeight(X, Y, DepthCm);
		}
	}
}

void ASnowField::AddSnowLine(const FVector& Start, const FVector& End, float WidthCm, int32 DepthCm)
{
	check(HasAuthority());

	const FVector FlatStart(Start.X, Start.Y, 0.f);
	const FVector FlatEnd(End.X, End.Y, 0.f);
	for (int32 Y = 0; Y < CellsY; ++Y)
	{
		for (int32 X = 0; X < CellsX; ++X)
		{
			const FVector Center = GetCellCenterWorld(X, Y);
			const float Distance = FMath::PointDistToSegment(FVector(Center.X, Center.Y, 0.f), FlatStart, FlatEnd);
			if (Distance <= WidthCm * 0.5f)
			{
				ChangeCellHeight(X, Y, DepthCm);
			}
		}
	}
}

float ASnowField::GetSnowDepthAt(const FVector& WorldLocation) const
{
	int32 X, Y;
	return WorldToCell(WorldLocation, X, Y) ? GetCellHeight(X, Y) : 0.f;
}

FVector ASnowField::GetCellCenterWorld(int32 X, int32 Y) const
{
	return GetActorTransform().TransformPosition(FVector((X + 0.5f) * CellSizeCm, (Y + 0.5f) * CellSizeCm, 0.f));
}

FVector ASnowField::GetRandomPointInField() const
{
	return GetActorTransform().TransformPosition(FVector(FMath::FRand() * CellsX * CellSizeCm, FMath::FRand() * CellsY * CellSizeCm, 0.f));
}

void ASnowField::OnChunkReplicated(const FSnowChunk& Chunk, int32 ItemIndex)
{
	if (ChunkToItem.IsValidIndex(Chunk.ChunkIndex))
	{
		ChunkToItem[Chunk.ChunkIndex] = ItemIndex;
		QueueMeshRebuild(Chunk.ChunkIndex);
	}
}

FSnowChunk* ASnowField::FindChunk(int32 ChunkIndex)
{
	return const_cast<FSnowChunk*>(static_cast<const ASnowField*>(this)->FindChunk(ChunkIndex));
}

const FSnowChunk* ASnowField::FindChunk(int32 ChunkIndex) const
{
	if (!ChunkToItem.IsValidIndex(ChunkIndex))
	{
		return nullptr;
	}
	const int32 ItemIndex = ChunkToItem[ChunkIndex];
	if (!Chunks.Items.IsValidIndex(ItemIndex) || Chunks.Items[ItemIndex].Heights.Num() != ChunkSize * ChunkSize)
	{
		return nullptr;
	}
	return &Chunks.Items[ItemIndex];
}

int32 ASnowField::GetCellHeight(int32 X, int32 Y) const
{
	if (X < 0 || Y < 0 || X >= CellsX || Y >= CellsY)
	{
		return 0;
	}
	const FSnowChunk* Chunk = FindChunk((Y / ChunkSize) * NumChunksX + X / ChunkSize);
	return Chunk ? Chunk->Heights[(Y % ChunkSize) * ChunkSize + X % ChunkSize] : 0;
}

int32 ASnowField::ChangeCellHeight(int32 X, int32 Y, int32 Delta)
{
	if (X < 0 || Y < 0 || X >= CellsX || Y >= CellsY || Delta == 0)
	{
		return 0;
	}

	const int32 ChunkIndex = (Y / ChunkSize) * NumChunksX + X / ChunkSize;
	FSnowChunk* Chunk = FindChunk(ChunkIndex);
	if (!Chunk)
	{
		return 0;
	}

	uint8& Cell = Chunk->Heights[(Y % ChunkSize) * ChunkSize + X % ChunkSize];
	const int32 NewValue = FMath::Clamp<int32>(Cell + Delta, 0, MaxDepthCm);
	const int32 Applied = NewValue - Cell;
	if (Applied != 0)
	{
		Cell = static_cast<uint8>(NewValue);
		PendingDirtyChunks.Add(ChunkIndex);
	}
	return Applied;
}

bool ASnowField::WorldToCell(const FVector& WorldLocation, int32& OutX, int32& OutY) const
{
	const FVector Local = GetActorTransform().InverseTransformPosition(WorldLocation);
	OutX = FMath::FloorToInt(Local.X / CellSizeCm);
	OutY = FMath::FloorToInt(Local.Y / CellSizeCm);
	return OutX >= 0 && OutY >= 0 && OutX < CellsX && OutY < CellsY;
}

void ASnowField::ForEachCellInRadius(const FVector& WorldLocation, float RadiusCm, TFunctionRef<void(int32 X, int32 Y, float Distance)> Func) const
{
	const FVector Local = GetActorTransform().InverseTransformPosition(WorldLocation);
	const int32 MinX = FMath::Max(0, FMath::FloorToInt((Local.X - RadiusCm) / CellSizeCm));
	const int32 MaxX = FMath::Min(CellsX - 1, FMath::FloorToInt((Local.X + RadiusCm) / CellSizeCm));
	const int32 MinY = FMath::Max(0, FMath::FloorToInt((Local.Y - RadiusCm) / CellSizeCm));
	const int32 MaxY = FMath::Min(CellsY - 1, FMath::FloorToInt((Local.Y + RadiusCm) / CellSizeCm));

	for (int32 Y = MinY; Y <= MaxY; ++Y)
	{
		for (int32 X = MinX; X <= MaxX; ++X)
		{
			const float Distance = FVector2D::Distance(FVector2D(Local.X, Local.Y), FVector2D((X + 0.5f) * CellSizeCm, (Y + 0.5f) * CellSizeCm));
			if (Distance <= RadiusCm)
			{
				Func(X, Y, Distance);
			}
		}
	}
}

void ASnowField::FlushDirtyChunks()
{
	for (const int32 ChunkIndex : PendingDirtyChunks)
	{
		if (FSnowChunk* Chunk = FindChunk(ChunkIndex))
		{
			Chunks.MarkItemDirty(*Chunk);
			QueueMeshRebuild(ChunkIndex);
		}
	}
	PendingDirtyChunks.Reset();
}

void ASnowField::QueueMeshRebuild(int32 ChunkIndex)
{
	if (IsNetMode(NM_DedicatedServer))
	{
		return;
	}

	// Palojen reunaverteksit lukevat naapurisoluja, joten päivitetään myös naapurit.
	const int32 CX = ChunkIndex % NumChunksX;
	const int32 CY = ChunkIndex / NumChunksX;
	for (int32 DY = -1; DY <= 1; ++DY)
	{
		for (int32 DX = -1; DX <= 1; ++DX)
		{
			const int32 NX = CX + DX;
			const int32 NY = CY + DY;
			if (NX >= 0 && NY >= 0 && NX < NumChunksX && NY < NumChunksY)
			{
				MeshRebuildQueue.Add(NY * NumChunksX + NX);
			}
		}
	}
}

void ASnowField::RebuildQueuedMeshes()
{
	int32 Budget = MaxMeshRebuildsPerFrame;
	for (auto It = MeshRebuildQueue.CreateIterator(); It && Budget > 0; ++It, --Budget)
	{
		RebuildChunkMesh(*It);
		It.RemoveCurrent();
	}
}

float ASnowField::GetVertexHeight(int32 VX, int32 VY) const
{
	// Verteksi on neljän solun kulmassa: korkeus on niiden keskiarvo.
	const int32 Sum = GetCellHeight(VX - 1, VY - 1) + GetCellHeight(VX, VY - 1) + GetCellHeight(VX - 1, VY) + GetCellHeight(VX, VY);
	const float Average = Sum * 0.25f;
	// Paljas maa painetaan hieman maanpinnan alle, ettei lumi välky maan kanssa.
	return Average > 0.5f ? Average : -2.f;
}

void ASnowField::RebuildChunkMesh(int32 ChunkIndex)
{
	const int32 CX = ChunkIndex % NumChunksX;
	const int32 CY = ChunkIndex / NumChunksX;
	const int32 VertsPerSide = ChunkSize + 1;

	TArray<FVector> Vertices;
	TArray<FVector> Normals;
	TArray<FVector2D> UVs;
	Vertices.Reserve(VertsPerSide * VertsPerSide);
	Normals.Reserve(VertsPerSide * VertsPerSide);
	UVs.Reserve(VertsPerSide * VertsPerSide);

	// X-pääjärjestys, kuten CreateGridMeshTriangles olettaa.
	for (int32 I = 0; I < VertsPerSide; ++I)
	{
		for (int32 J = 0; J < VertsPerSide; ++J)
		{
			const int32 VX = CX * ChunkSize + I;
			const int32 VY = CY * ChunkSize + J;
			Vertices.Add(FVector(VX * CellSizeCm, VY * CellSizeCm, GetVertexHeight(VX, VY)));

			const float DX = GetVertexHeight(VX + 1, VY) - GetVertexHeight(VX - 1, VY);
			const float DY = GetVertexHeight(VX, VY + 1) - GetVertexHeight(VX, VY - 1);
			Normals.Add(FVector(-DX, -DY, 2.f * CellSizeCm).GetSafeNormal());

			UVs.Add(FVector2D(VX * CellSizeCm / 100.f, VY * CellSizeCm / 100.f));
		}
	}

	const FProcMeshSection* Existing = Mesh->GetProcMeshSection(ChunkIndex);
	if (Existing && Existing->ProcVertexBuffer.Num() == Vertices.Num())
	{
		Mesh->UpdateMeshSection(ChunkIndex, Vertices, Normals, UVs, TArray<FColor>(), TArray<FProcMeshTangent>());
	}
	else
	{
		Mesh->CreateMeshSection(ChunkIndex, Vertices, GridTriangles, Normals, UVs, TArray<FColor>(), TArray<FProcMeshTangent>(), false);
		if (ActiveSnowMaterial)
		{
			Mesh->SetMaterial(ChunkIndex, ActiveSnowMaterial);
		}
	}
}
