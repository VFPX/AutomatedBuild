@echo off

rem *********************************************************************
rem Get current year.
set Year=%date:~-4%

rem Get current month.
if %date:~-7,1% == 0 set Month=%date:~-6,1%
if not %date:~-7,1% == 0 set Month=%date:~-7,2%

rem Get current day.
if %date:~-10,1% == 0 set Day=%date:~-9,1%
if not %date:~-10,1% == 0 set Day=%date:~-10,2%

rem Create a version numer in format YYYY.MM.DD.
set Version=%Year%.%Month%.%Day%

rem *********************************************************************
rem Make sure the target directories exist.
if not exist C:\AutomatedBuild\Distrib\%2 md "C:\AutomatedBuild\Distrib\%2"
if not exist C:\AutomatedBuild\Distrib\%2\%Version% md "C:\AutomatedBuild\Distrib\%2\%Version%"

rem *********************************************************************
rem Copy source file(s) to target directories.
rem Existing files are overwritten.
copy /y "%CCNetWorkingDirectory%\%1" "C:\AutomatedBuild\Distrib\%2\%Version%"
copy /y "%CCNetWorkingDirectory%\%1" "C:\AutomatedBuild\Distrib\%2"
