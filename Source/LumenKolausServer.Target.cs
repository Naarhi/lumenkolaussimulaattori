using UnrealBuildTool;

// Dedikoitu palvelin (vaatii lähdekoodista käännetyn Unreal Enginen).
public class LumenKolausServerTarget : TargetRules
{
	public LumenKolausServerTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Server;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("LumenKolaus");
	}
}
