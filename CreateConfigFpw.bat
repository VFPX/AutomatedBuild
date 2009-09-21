@echo off

rem  Create a Config.fpw file for the calling CCNet project
rem  in the calling CCNet project's ArtifactDirectory.
rem 
rem  We do this to force Visual FoxPro's BUILD EXE command
rem  to use a private directory for temporary files
rem  instead of the Windows TEMP directory.
rem  This way CCNet can build several Visual FoxPro projects
rem  at the same time without conflicts.

del "%CCNetArtifactDirectory%\config.fpw"

echo SCREEN=OFF>"%CCNetArtifactDirectory%\config.fpw"
echo SORTWORK="%CCNetArtifactDirectory%">>"%CCNetArtifactDirectory%\config.fpw"
echo EDITWORK="%CCNetArtifactDirectory%">>"%CCNetArtifactDirectory%\config.fpw"
echo PROGWORK="%CCNetArtifactDirectory%">>"%CCNetArtifactDirectory%\config.fpw"
echo TMPFILES="%CCNetArtifactDirectory%">>"%CCNetArtifactDirectory%\config.fpw"
