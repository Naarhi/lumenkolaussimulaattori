using UnrealBuildTool;

public class LumenKolausEditorTarget : TargetRules
{
	public LumenKolausEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("LumenKolaus");
	}
}
