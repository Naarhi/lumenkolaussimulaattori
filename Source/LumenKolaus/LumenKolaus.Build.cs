using UnrealBuildTool;

public class LumenKolaus : ModuleRules
{
	public LumenKolaus(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"EnhancedInput",
			"NetCore",
			"ProceduralMeshComponent"
		});
	}
}
