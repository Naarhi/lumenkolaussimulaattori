#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Net/Serialization/FastArraySerializer.h"
#include "SnowField.generated.h"

class ASnowField;
class UMaterialInterface;
class UProceduralMeshComponent;
struct FSnowChunkArray;

/** Yksi 16 x 16 solun pala lumiruudukkoa. Replikoidaan kokonaisena, kun yksikin solu muuttuu. */
USTRUCT()
struct FSnowChunk : public FFastArraySerializerItem
{
	GENERATED_BODY()

	UPROPERTY()
	int32 ChunkIndex = INDEX_NONE;

	/** Lumen syvyys soluittain senttimetreinä. */
	UPROPERTY()
	TArray<uint8> Heights;

	void PostReplicatedAdd(const FSnowChunkArray& InArraySerializer);
	void PostReplicatedChange(const FSnowChunkArray& InArraySerializer);
};

USTRUCT()
struct FSnowChunkArray : public FFastArraySerializer
{
	GENERATED_BODY()

	UPROPERTY()
	TArray<FSnowChunk> Items;

	/** Asetetaan PostInitializeComponentsissa, jotta asiakas tietää mitä päivittää. */
	ASnowField* Owner = nullptr;

	bool NetDeltaSerialize(FNetDeltaSerializeInfo& DeltaParms)
	{
		return FFastArraySerializer::FastArrayDeltaSerialize<FSnowChunk, FSnowChunkArray>(Items, DeltaParms, *this);
	}
};

template<>
struct TStructOpsTypeTraits<FSnowChunkArray> : public TStructOpsTypeTraitsBase2<FSnowChunkArray>
{
	enum { WithNetDeltaSerializer = true };
};

/**
 * Pihan lumi korkeusruudukkona. Palvelin päättää lumen määrästä ja replikoi vain
 * muuttuneet palat. Asiakas rakentaa niistä muotoutuvan lumipinnan.
 * Ruudukko alkaa actorin sijainnista ja jatkuu +X- ja +Y-suuntiin.
 */
UCLASS()
class LUMENKOLAUS_API ASnowField : public AActor
{
	GENERATED_BODY()

public:
	ASnowField();

	/** Poistaa lunta ympyrän alueelta, enintään MaxDepthPerCell senttiä solusta. Palauttaa poistetun määrän. Vain palvelimella. */
	int32 RemoveSnow(const FVector& WorldLocation, float RadiusCm, int32 MaxAmount, int32 MaxDepthPerCell);

	/** Kasaa lunta ympyrän alueelle, eniten keskelle. Ruudukon ulkopuolelle heitetty lumi katoaa. Vain palvelimella. */
	void AddSnow(const FVector& WorldLocation, float RadiusCm, int32 Amount);

	/** Lisää jokaiseen soluun saman verran lunta (lumisade). Vain palvelimella. */
	void AddSnowEverywhere(int32 DepthCm);

	/** Lisää lunta janan suuntaiselle kaistalle (esim. aura-auton penkka). Vain palvelimella. */
	void AddSnowLine(const FVector& Start, const FVector& End, float WidthCm, int32 DepthCm);

	UFUNCTION(BlueprintPure, Category = "Lumi")
	float GetSnowDepthAt(const FVector& WorldLocation) const;

	UFUNCTION(BlueprintPure, Category = "Lumi")
	FVector GetCellCenterWorld(int32 X, int32 Y) const;

	UFUNCTION(BlueprintPure, Category = "Lumi")
	FVector GetRandomPointInField() const;

	FVector2D GetFieldSizeCm() const { return FVector2D(CellsX * CellSizeCm, CellsY * CellSizeCm); }

	/** FSnowChunkin replikointikutsu asiakkaalla. */
	void OnChunkReplicated(const FSnowChunk& Chunk, int32 ItemIndex);

	UPROPERTY(EditAnywhere, Category = "Lumi", meta = (ClampMin = 16))
	int32 CellsX = 192;

	UPROPERTY(EditAnywhere, Category = "Lumi", meta = (ClampMin = 16))
	int32 CellsY = 192;

	UPROPERTY(EditAnywhere, Category = "Lumi", meta = (ClampMin = 1))
	float CellSizeCm = 10.f;

	UPROPERTY(EditAnywhere, Category = "Lumi", meta = (ClampMin = 0, ClampMax = 250))
	int32 InitialDepthCm = 30;

	UPROPERTY(EditAnywhere, Category = "Lumi", meta = (ClampMin = 0))
	float SnowfallCmPerMinute = 0.5f;

	/** Oma lumimateriaali. Jos tyhjä, käytetään moottorin perusmateriaalia lumen värisenä. */
	UPROPERTY(EditAnywhere, Category = "Lumi")
	TObjectPtr<UMaterialInterface> SnowMaterial;

	UPROPERTY(EditAnywhere, Category = "Lumi")
	FLinearColor FallbackSnowColor = FLinearColor(0.82f, 0.86f, 0.92f);

protected:
	virtual void PostInitializeComponents() override;
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

private:
	static constexpr int32 ChunkSize = 16;
	static constexpr int32 MaxDepthCm = 250;
	static constexpr int32 MaxMeshRebuildsPerFrame = 24;

	UPROPERTY(VisibleAnywhere, Category = "Lumi")
	TObjectPtr<UProceduralMeshComponent> Mesh;

	UPROPERTY(Replicated)
	FSnowChunkArray Chunks;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInterface> FallbackBaseMaterial;

	/** Materiaali, jota palat oikeasti käyttävät (SnowMaterial tai sen korvike). */
	UPROPERTY(Transient)
	TObjectPtr<UMaterialInterface> ActiveSnowMaterial;

	int32 NumChunksX = 0;
	int32 NumChunksY = 0;

	/** Palan indeksi -> sijainti Chunks.Items-taulukossa (asiakkaalla järjestys voi poiketa). */
	TArray<int32> ChunkToItem;

	TSet<int32> PendingDirtyChunks;
	TSet<int32> MeshRebuildQueue;
	TArray<int32> GridTriangles;
	float SnowfallAccumulator = 0.f;

	FSnowChunk* FindChunk(int32 ChunkIndex);
	const FSnowChunk* FindChunk(int32 ChunkIndex) const;
	int32 GetCellHeight(int32 X, int32 Y) const;
	int32 ChangeCellHeight(int32 X, int32 Y, int32 Delta);
	bool WorldToCell(const FVector& WorldLocation, int32& OutX, int32& OutY) const;
	void ForEachCellInRadius(const FVector& WorldLocation, float RadiusCm, TFunctionRef<void(int32 X, int32 Y, float Distance)> Func) const;

	void FlushDirtyChunks();
	void QueueMeshRebuild(int32 ChunkIndex);
	void RebuildQueuedMeshes();
	void RebuildChunkMesh(int32 ChunkIndex);
	float GetVertexHeight(int32 VX, int32 VY) const;
};
