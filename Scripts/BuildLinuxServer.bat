@echo off
rem Paketoi dedikoidun Linux-palvelimen Windowsilla.
rem Vaatii: lahdekoodista kaannetyn UE5:n (UE_ROOT) ja Linux cross-compile -tyokalut (LINUX_MULTIARCH_ROOT).
setlocal
if "%UE_ROOT%"=="" (
  echo Aseta UE_ROOT osoittamaan lahdekoodista kaannettyyn Unreal Engineen, esim. set UE_ROOT=C:\UnrealEngine
  exit /b 1
)
set PROJECT=%~dp0..\LumenKolaus.uproject
set OUT=%~dp0..\Out

call "%UE_ROOT%\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun ^
  -project="%PROJECT%" -noP4 -utf8output ^
  -platform=Linux -server -serverplatform=Linux -noclient ^
  -serverconfig=Development ^
  -build -cook -stage -pak -archive -archivedirectory="%OUT%"
