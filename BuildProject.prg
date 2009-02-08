#if .F.
	* Testcode:
	CLEAR
	CD C:\AutomatedBuild\Source\Vfp_Sample
	DO BuildProject WITH "Vfp_Sample.pjm"
	PROCEDURE BuildProject
#endif
*=================================================================
* BuildProject.prg.
* Build automation for Vfp8/Vfp9 projects using CruiseControl.NET.
* Markus Winhard (mw@bingo-ev.de).
*=================================================================
#DEFINE CRLF CHR(13)+CHR(10)

LPARAMETERS tcPjmFile, tcExeName
*--------------------------------------------
* Setup.
*--------------------------------------------
LOCAL loBuild, loException
*--------------------------------------------
* This program is to be run by an unattended
* process. So we try to catch any runtime
* errors.
*--------------------------------------------
TRY
	*--------------------------------------------
	* Create the class and tell it to build an
	* EXE for us.
	*--------------------------------------------
	loBuild = CREATEOBJECT( "PjmFile" )
	loBuild.PjmFile = m.tcPjmFile
	loBuild.ExeName = EVL( m.tcExeName, "" )
	m.loBuild.Build( .T. )
CATCH TO loException
	*--------------------------------------------
	* Write build errors to the log. SET
	* TEXTMERGE was set in PjmFile.Init().
	*--------------------------------------------
	TEXT TO loBuild.ErrorLog ADDITIVE TEXTMERGE NOSHOW PRETEXT 1+2
		.
		Error updating project list:
		Error Number: << m.loException.ErrorNo >>
		Line Contents: << m.loException.LineContents >>
		Error Details: << m.loException.Details >>
		User Value: << m.loException.UserValue >>
		Line Number: << m.loException.LineNo >>
		Message: << m.loException.Message >>
		Name: << m.loException.Name >>
		Procedure: << m.loException.Procedure >>
		Stack Level: << m.loException.StackLevel >>
		.
	ENDTEXT
ENDTRY
loException = .NULL.
RELEASE loException
*--------------------------------------------
* Consolidate error logs.
*--------------------------------------------
m.loBuild.ConsolidateErrorLogs()
*--------------------------------------------
* Write the build result to StdOut so
* CruiseControl.NET can catch it.
*--------------------------------------------
m.loBuild.PublishResults()
*--------------------------------------------
* If the ERR file exists wrap its contents in
* XML. The "merge" and "publish" tasks of
* CCNet want XML.
*--------------------------------------------
m.loBuild.WrapErrorsInXml()
*--------------------------------------------
* Special action for failed builds with
* CruiseControl.NET.
*--------------------------------------------
IF NOT m.loBuild.Success
	*--------------------------------------------
	* Cleanup.
	*--------------------------------------------
	loBuild = .NULL.
	RELEASE loBuild
	FLUSH
	CLEAR ALL
	IF _PSCODE == "TESTMODE"
		*--------------------------------------------
		* We are testing this program interactively.
		*--------------------------------------------
		ACTIVATE SCREEN
		? "Program exited with Errorlevel 1"
	ELSE
		*--------------------------------------------
		* Set DOS errorlevel. CCNet interprets
		* errorlevel 0 as success, everything else as
		* failure. So we exit with errorlevel 1.
		*--------------------------------------------
		DECLARE ExitProcess in Win32API INTEGER ExitCode
		ExitProcess( 1 )
	ENDIF
ELSE
	*--------------------------------------------
	* Cleanup.
	*--------------------------------------------
	loBuild = .NULL.
	RELEASE loBuild
	FLUSH
	CLEAR ALL
	IF NOT _PSCODE == "TESTMODE"
		*--------------------------------------------
		* Close VFP when in unattended mode.
		*--------------------------------------------
		QUIT
	ENDIF
ENDIF
*--------------------------------------------
* Done.
*--------------------------------------------
RETURN

*--------------------------------------------
* A class to build the project and create
* the EXE.
*--------------------------------------------
DEFINE CLASS PjmFile AS SESSION

	*--------------------------------------------
	* Core properties.
	*--------------------------------------------
	ErrorLog = ""
	PjxFile = ""
	PjmFile = ""
	PjmFileName = ""
	PjmPath = ""
	ErrFile = ""
	ExeName = ""
	PrgErrLog = ""
	SearchPath = ""
	Success = .F.
	TestMode = .F.
	CurrentDefault = SYS(5) + SYS(2003)
	DIMENSION ProjectFiles[1]

	*--------------------------------------------
	* Pjx Properties.
	*--------------------------------------------
	Version = 1.20
	Author = ""
	Company = ""
	Address = ""
	City = ""
	State = ""
	Zip = ""
	Country = ""
	SaveCode = .T.
	Debug = .T.
	Encrypt=.F.
	NoLogo = .F.
	CommentStyle = 1
	Comments = "Project created by " + PROPER(PROGRAM())
	CompanyName = ""
	FileDescription = ""
	LegalCopyright = "© 1999-" + ;
		STR( YEAR(DATE()), 4 ) + " FooBar Inc."
	LegalTrademarks = "® FooBar is a registered" + ;
		" trademark of FooBar Inc."
	ProductName = "FooBar"
	Major = 0
	Minor = 0
	Revision = 0
	AutoIncrement = .F.

	*--------------------------------------------
	* Reload the project object when assigned a
	* new PJM.
	*--------------------------------------------
	PROCEDURE PjmFile_Assign
		LPARAMETERS tcPjmFile
		DO CASE
			CASE VARTYPE( m.tcPjmFile ) == "L" ;
					AND m.tcPjmFile == .F.
				*--------------------------------------------
				* This program was called without parameters.
				*--------------------------------------------
				ERROR "PJM file name not passed. Probably this program was called without parameters."
			CASE NOT VARTYPE( m.tcPjmFile ) == "C"
				*--------------------------------------------
				* Wrong parameter type.
				*--------------------------------------------
				ERROR "PJM file name passed (" + TRANSFORM( m.tcPjmFile ) +") "+ ;
					"is of type '" + VARTYPE( m.tcPjmFile ) + "'. Type 'C' (character) is required."
			CASE NOT m.This.IsFile(FULLPATH(FORCEEXT( m.tcPjmFile, "pjm" )))
				*--------------------------------------------
				* The given PJM file does not exist.
				*--------------------------------------------
				ERROR "File not found: " + FULLPATH(FORCEEXT( m.tcPjmFile, "pjm" ))
			OTHERWISE
				*--------------------------------------------
				* Set file name properties.
				*--------------------------------------------
				This.PjmFile = FULLPATH(FORCEEXT( m.tcPjmFile, "pjm" ))
				This.PjmFileName = JUSTFNAME( m.This.PjmFile )
				This.PjmPath = JUSTPATH( m.This.PjmFile )
				*--------------------------------------------
				* Set the corresponding ERR file name.
				*--------------------------------------------
				This.ErrFile = ADDBS( m.This.PjmPath ) + ;
					FORCEEXT( m.This.PjmFileName, "err" )
				m.This.EraseFile( m.This.ErrFile )
				*--------------------------------------------
				* Parse PJM file.
				*--------------------------------------------
				m.This.ParsePjm()
		ENDCASE
	ENDPROC
	
	*--------------------------------------------
	* Check if a build was successful.
	*--------------------------------------------
	PROCEDURE Success_Access
		RETURN m.This.IsFile( m.This.ExeName ) ;
			AND NOT m.This.IsFile( m.This.ErrFile ) ;
			AND EMPTY( m.This.ErrorLog )
	ENDPROC

	*--------------------------------------------
	* Set environment.
	*--------------------------------------------
	PROCEDURE Init
		This.ProjectFiles[ 1 ] = .NULL.
		SET FULLPATH ON
		SET MEMOWIDTH TO 8192
		*--------------------------------------------
		* SetFileAttributes() is used in EraseFile().
		*--------------------------------------------
		DECLARE INTEGER SetFileAttributes IN Win32API STRING, INTEGER
		*--------------------------------------------
		* Start the error log.
		*--------------------------------------------
		SET TEXTMERGE TO
		SET TEXTMERGE TO MEMVAR ;
			This.ErrorLog NOSHOW ADDITIVE
		SET TEXTMERGE ON
		*--------------------------------------------
		* Initial errors are written to
		* BuildProject.err.
		*--------------------------------------------
		This.ErrFile = "BuildProject.err"
		m.This.EraseFile( m.This.ErrFile )
		*--------------------------------------------
		* Check if we are testing this program
		* interactively. In unattended mode SCREEN is
		* set OFF in config.fpw. We have to store
		* this information in a place that survives a
		* CLEAR ALL. VFP's system variables meet this
		* requirement. We chose _PSCODE because it's
		* no longer used in VFP.
		*--------------------------------------------
		IF _Screen.Visible
			_PSCODE = "TESTMODE"
			This.TestMode = .T.
		ENDIF
	ENDPROC

	*--------------------------------------------
	* Restore environment.
	*--------------------------------------------
	PROCEDURE Destroy
		LOCAL i
		FOR i = ALEN( This.ProjectFiles ) TO 1 STEP -1
			This.ProjectFiles[ i ] = .NULL.
		ENDFOR
		SET DEFAULT TO (m.This.CurrentDefault)
		SET TEXTMERGE TO
		SET TEXTMERGE OFF
	ENDPROC

	*--------------------------------------------
	* Build the EXE.
	*--------------------------------------------
	PROCEDURE Build
		LPARAMETERS tlRecompile
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcExe, loException, lcRecompile
		IF EMPTY( m.This.ExeName )
			This.ExeName = ADDBS( m.This.PjmPath ) + ;
				FORCEEXT( m.This.PjmFileName, "exe" )
		ELSE
			This.ExeName = FORCEEXT( m.This.ExeName, "exe")
		ENDIF
		lcExe = m.This.ExeName
		SET DEFAULT TO (m.This.PjmPath)
		*--------------------------------------------
		* Create project and add files from the PJM.
		*--------------------------------------------
		m.This.SetPath()
		m.This.CreatePjx()
		m.This.TweakPjx()
		m.This.CompilePrgs( .T. )
		*--------------------------------------------
		* Stop text merging.
		*--------------------------------------------
		SET TEXTMERGE TO
		*--------------------------------------------
		* Only try to build the EXE if everything
		* was successful.
		*--------------------------------------------
		IF EMPTY( m.This.ErrorLog )
			lcRecompile = IIF( m.tlRecompile, "RECOMPILE", "" )
			TRY
				BUILD EXE (m.lcExe) FROM (m.This.PjxFile) &lcRecompile.
			CATCH TO loException
				This.ErrorLog = m.loException.Message
			ENDTRY
		ENDIF
		*--------------------------------------------
		* Delete files that are not part of the
		* project. We do this after building the EXE
		* to prevent errors when a developer added a
		* new file to the project but forgot to
		* update the PJM. Usually VFP will add the
		* missing file.
		*--------------------------------------------
		m.This.CleanupDisk( "" )
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		loException = .NULL.
		RELEASE loException
	ENDPROC
	
	*--------------------------------------------
	* Hydrate the object from the PJM.
	*--------------------------------------------
	PROCEDURE ParsePjm
		*--------------------------------------------
		* Check environment.
		*--------------------------------------------
		IF EMPTY( m.This.PjmFile ) ;
				OR NOT m.This.IsFile( m.This.PjmFile )
			RETURN
		ENDIF
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcPjm, laLines[1], lcState, lcLine, lcPropertyName, lcProperty, lcValue
		*--------------------------------------------
		* Get PJM file contents.
		*--------------------------------------------
		lcPjm = FILETOSTR( m.This.PjmFile )
		IF EMPTY( m.lcPjm )
			RETURN
		ENDIF
		ALINES( laLines, m.lcPjm, .T. )
		*--------------------------------------------
		* First section of PJM file. As this section
		* has no section header we set one ourselves.
		*--------------------------------------------
		lcState = "[Properties]"
		FOR EACH lcLine IN laLines
			*--------------------------------------------
			* Filter out section markers.
			*--------------------------------------------
			IF INLIST( m.lcLine, ;
					"[OLEServers]", ;
					"[OLEServersEnd]", ;
					"[ProjectFiles]", ;
					"[EOF]" )
				lcState = m.lcLine
				LOOP
			ENDIF
			*
			DO CASE
				CASE m.lcState = "[Properties]"
					*--------------------------------------------
					* This is for the project's header record.
					*--------------------------------------------
					lcPropertyName = ALLTRIM(GETWORDNUM( m.lcLine, 1, "=" ))
					lcProperty = "This." + m.lcPropertyName
					lcValue = GETWORDNUM( m.lcLine, 2, "=" )
					IF NOT EMPTY( m.lcValue )
						DO CASE
							CASE INLIST( m.lcPropertyName, ;
									[SaveCode], ;
									[Debug], ;
									[Encrypt], ;
									[NoLogo], ;
									[AutoIncrement] )
								*--------------------------------------------
								* Logical properties.
								*--------------------------------------------
								STORE EVALUATE( m.lcValue ) TO (m.lcProperty)
							CASE INLIST( m.lcPropertyName, ;
									[CommentStyle], ;
									[Major], ;
									[Minor], ;
									[Revision] )
								*--------------------------------------------
								* Numeric properties.
								*--------------------------------------------
								STORE VAL( m.lcValue ) to (m.lcProperty)
							OTHERWISE
								*--------------------------------------------
								* Character properties.
								*--------------------------------------------
								STORE m.lcValue TO (m.lcProperty)
						ENDCASE
					ENDIF
				CASE m.lcState = "[OLEServers]"
					* ToDo: Add support for COM Servers.
					LOOP
				CASE m.lcState = "[OLEServersEnd]"
					* ToDo: Add support for COM Servers.
					LOOP
				CASE m.lcState = "[ProjectFiles]"
					*--------------------------------------------
					* Add this file to our .ProjectFiles[] array.
					*--------------------------------------------
					m.This.AddFile( m.lcLine )
				CASE m.lcState = "[EOF]"
					LOOP
			ENDCASE
		ENDFOR
	ENDPROC

	*--------------------------------------------
	* Add a file to our .ProjectFiles[] array.
	*--------------------------------------------
	PROCEDURE AddFile
		LPARAMETERS tcLine
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL loFile, lnFiles
		*--------------------------------------------
		* Create a new placeholder object for a
		* record in the PJX file we're going to
		* create.
		*--------------------------------------------
		loFile = CREATEOBJECT( "ProjectFile" )
		*--------------------------------------------
		* Set the placeholder object's properties
		* from the current PJM file line.
		*--------------------------------------------
		m.loFile.ParseFile( m.tcLine )
		*--------------------------------------------
		* Add one more row to our .ProjectFiles[]
		* array.
		*--------------------------------------------
		lnFiles = ALEN( m.This.ProjectFiles )
		IF NOT ISNULL( m.This.ProjectFiles[ m.lnFiles ] )
			lnFiles = m.lnFiles + 1
			DIMENSION This.ProjectFiles[ m.lnFiles ]
		ENDIF
		*--------------------------------------------
		* Add the placeholder object to our
		* .ProjectFiles[] array.
		*--------------------------------------------
		This.ProjectFiles[ m.lnFiles ] = m.loFile
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		loFile = .NULL.
		RELEASE loFile
	ENDPROC

	*--------------------------------------------
	* Set path to all sub dirs of the project.
	* This helps avoid 'include file not found'
	* errors.
	*--------------------------------------------
	PROCEDURE SetPath
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcPath
		*--------------------------------------------
		* Get all sub dirs separated by semicolon.
		*--------------------------------------------
		lcPath = m.This.GetPathTree( "" )
		*--------------------------------------------
		* SET PATH accepts no more than 4095
		* characters.
		*--------------------------------------------
		lcPath = LEFT( m.This.SearchPath, 4095 )
		IF NOT RIGHT( m.lcPath, 1 ) == ";"
			*--------------------------------------------
			* Last folder name is truncated. Remove it.
			*--------------------------------------------
			lcPath = LEFT( m.lcPath, RAT( ";", m.lcPath ) )
		ENDIF
		*--------------------------------------------
		* Set search path.
		*--------------------------------------------
		SET PATH TO (m.lcPath)
	ENDPROC
	
	*--------------------------------------------
	* Traverse all sub dirs recursively.
	*--------------------------------------------
	FUNCTION GetPathTree
		LPARAMETERS tcBaseDir
		*--------------------------------------------
		* Check parameters.
		*--------------------------------------------
		IF EMPTY( m.tcBaseDir )
			This.SearchPath = ""
		ELSE
			tcBaseDir = ADDBS( m.tcBaseDir )
		ENDIF
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcPath, i, laDir[1]
		*--------------------------------------------
		* Look for sub dirs.
		*--------------------------------------------
		FOR i = 1 TO ADIR( laDir, m.tcBaseDir + "*.*", "HSD" )
			IF "D" $ laDir[ i, 5 ] ;
					AND NOT INLIST( laDir[ i, 1 ], ".", ".." )
				*--------------------------------------------
				* Add this directory to the search path.
				*--------------------------------------------
				lcPath = m.tcBaseDir + laDir[ i, 1 ]
				This.SearchPath = m.This.SearchPath + ;
					ADDBS( m.lcPath ) + ";"
				*--------------------------------------------
				* Call this method recursively.
				*--------------------------------------------
				m.This.GetPathTree( m.lcPath )
			ENDIF
		ENDFOR
		*
		RETURN m.This.SearchPath
	ENDFUNC

	*--------------------------------------------
	* Create the project and verify that files in
	* the project exist.
	*--------------------------------------------
	PROCEDURE CreatePjx
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcFile, lcPjx, lcPjt, lcFileName, loFile, lcDummyFile
		lcDummyFile = LOWER( ".\dummy" + SYS(2015) + ".txt" )
		*--------------------------------------------
		* Preserve the existing project if testing.
		* Normally during an automated build there is
		* only the PJM.
		*--------------------------------------------
		lcFile = IIF( m.This.IsFile(FORCEEXT( m.This.PjmFile, "pjx" )), "_", "" ) + ;
			m.This.PjmFileName
		lcPjx = FORCEEXT( m.lcFile, "pjx" )
		lcPjt = FORCEEXT( m.lcFile, "pjt" )
		This.PjxFile = ADDBS( m.This.PjmPath ) + m.lcPjx
		*--------------------------------------------
		* Delete the project files.
		*--------------------------------------------
		m.This.EraseFile( m.lcPjx )
		m.This.EraseFile( m.lcPjt )
		*--------------------------------------------
		* Create a new project from a dummy file.
		*--------------------------------------------
		IF NOT m.This.IsFile( m.lcDummyFile )
			STRTOFILE( ".", m.lcDummyFile )
		ENDIF
		BUILD PROJECT (m.lcPjx) FROM (m.lcDummyFile)
		*--------------------------------------------
		* Remove the dummy file from the project.
		*--------------------------------------------
		USE (m.lcPjx) EXCLUSIVE
		DELETE FOR name = JUSTFNAME( m.lcDummyFile ) + CHR(0)
		PACK
		USE
		*--------------------------------------------
		* Delete the dummy file.
		*--------------------------------------------
		m.This.EraseFile( m.lcDummyFile )
		*--------------------------------------------
		* Verify that files in the project exist.
		*--------------------------------------------
		FOR EACH loFile IN m.This.ProjectFiles
			lcFileName = m.loFile.FileName
			IF NOT m.loFile.FileType == "W" ;		&& Ignore the ProjectHook.
					AND NOT m.This.IsFile( m.lcFileName )
		         \Project file not found: << m.lcFileName >>
			ENDIF
		ENDFOR
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		loFile = .NULL.
		RELEASE loFile
	ENDPROC

	*--------------------------------------------
	* Update the project with data from the PJM.
	*--------------------------------------------
	PROCEDURE TweakPjx
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL loFile, lcDevInfo
		*--------------------------------------------
		* Open the PJX file as a table.
		*--------------------------------------------
		USE (m.This.PjxFile) ALIAS PJX
		*--------------------------------------------
		* Update project properties.
		*--------------------------------------------
		LOCATE FOR type = "H"
		REPLACE savecode WITH m.This.SaveCode, ;
			debug WITH m.This.Debug, ;
			encrypt WITH m.This.Encrypt, ;
			nologo WITH m.This.NoLogo, ;
			cmntstyle WITH m.This.CommentStyle
		*--------------------------------------------
		* Update project version information.
		*--------------------------------------------
		lcDevInfo = m.This.SetVersionInfo( devinfo , ;
			m.This.Comments, m.This.CompanyName, m.This.FileDescription, ;
			m.This.LegalCopyright, m.This.LegalTrademarks, m.This.ProductName, ;
			m.This.Major, m.This.Minor, m.This.Revision, m.This.AutoIncrement )
		IF NOT devinfo == m.lcDevInfo
			REPLACE devinfo WITH m.lcDevInfo
		ENDIF
		*--------------------------------------------
		* Update project files.
		*--------------------------------------------
		FOR EACH loFile IN m.This.ProjectFiles
			IF m.loFile.FileType == "W"
				*--------------------------------------------
				* Ignore the ProjectHook.
				*--------------------------------------------
				LOOP
			ENDIF
			APPEND BLANK
			REPLACE name WITH m.loFile.FileName + CHR(0), ;
				type WITH m.loFile.FileType, ;
				id WITH m.loFile.ID, ;
				exclude WITH m.loFile.Exclude, ;
				mainprog WITH m.loFile.MainProgram, ;
				cpid WITH m.loFile.CodePage, ;
				comments WITH m.loFile.FileDescription
		ENDFOR
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		USE IN PJX
		loFile = .NULL.
		RELEASE loFile
	ENDPROC

	*--------------------------------------------
	* Update the contents of the project header
	* record's DevInfo field.
	*--------------------------------------------
	PROCEDURE SetVersionInfo
		LPARAMETERS tcDevInfo, ;
			tcComments, tcCompanyname, tcDescription, ;
			tcCopyright, tcTrademarks, tcProductname, ;
			tnMajor, tnMinor, tnRevision, tlAutoIncrement
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcDevInfo, lcMajor, lcMinor, lcRevision
		lcMajor = LTRIM(STR( m.tnMajor ))
		lcMinor = LTRIM(STR( m.tnMinor ))
		lcRevision = LTRIM(STR( m.tnRevision ))
		*--------------------------------------------
		* Create a new DevInfo structure from the
		* passed data.
		*--------------------------------------------
		lcDevInfo = REPLICATE( CHR(0), LEN( m.tcDevInfo ) )
		lcDevInfo = STUFF( m.lcDevInfo, 223, LEN( m.tcComments ), m.tcComments )
		lcDevInfo = STUFF( m.lcDevInfo, 478, LEN( m.tcCompanyname ), m.tcCompanyname )
		lcDevInfo = STUFF( m.lcDevInfo, 733, LEN( m.tcDescription ), m.tcDescription )
		lcDevInfo = STUFF( m.lcDevInfo, 988, LEN( m.tcCopyright ), m.tcCopyright )
		lcDevInfo = STUFF( m.lcDevInfo, 1243, LEN( m.tcTrademarks ), m.tcTrademarks )
		lcDevInfo = STUFF( m.lcDevInfo, 1498, LEN( m.tcProductname ), m.tcProductname )
		lcDevInfo = STUFF( m.lcDevInfo, 1753, LEN( m.lcMajor ), m.lcMajor )
		lcDevInfo = STUFF( m.lcDevInfo, 1758, LEN( m.lcMinor ), m.lcMinor )
		lcDevInfo = STUFF( m.lcDevInfo, 1763, LEN( m.lcRevision ), m.lcRevision )
		lcDevInfo = STUFF( m.lcDevInfo, 1788, 1, IIF( m.tlAutoIncrement, CHR(1), CHR(0) ) )
		*
		RETURN m.lcDevInfo
	ENDPROC

	*--------------------------------------------
	* Compile PRG files.
	*--------------------------------------------
	PROCEDURE CompilePrgs
		LPARAMETERS tlExcludedOnly
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcFileName, loException, lcErrLog, lcErrFile, loFile
		*--------------------------------------------
		* Compile all PRGs of this project. If
		* parameter tlExcludedOnly is .T. compile
		* just the excluded ones.
		*--------------------------------------------
		lcErrLog = ""
		FOR EACH loFile IN This.ProjectFiles
			lcFileName = m.loFile.FileName
			IF m.This.IsFile( m.lcFileName ) ;
					AND LOWER(JUSTEXT( m.lcFileName )) == "prg" ;
					AND ( NOT m.tlExcludedOnly OR m.loFile.Exclude )
				*--------------------------------------------
				* Delete the old FXP file.
				*--------------------------------------------
				m.This.EraseFile(FORCEEXT( m.lcFileName, "fxp" ))
				TRY
					*--------------------------------------------
					* Compile the PRG file.
					*--------------------------------------------
					COMPILE (m.lcFileName)
					lcErrFile = FORCEEXT( m.lcFileName, "err")
					IF m.This.IsFile( m.lcErrFile )
						*--------------------------------------------
						* Collect compile errors.
						*--------------------------------------------
						lcErrLog = m.lcErrLog + ;
							"File Name: " + m.lcFileName +CRLF+ ;
							FILETOSTR( m.lcErrFile ) + CRLF
					ENDIF
				CATCH TO loException
					*--------------------------------------------
					* Rethrow the exception.
					*--------------------------------------------
					loException.Details = m.loException.Details + ", Program File: " + m.lcFileName
					THROW loException
				ENDTRY
			ENDIF
		ENDFOR
		*--------------------------------------------
		* Store the compile errors.
		*--------------------------------------------
		IF NOT EMPTY( m.lcErrLog )
			This.PrgErrLog = m.lcErrLog
		ENDIF
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		loFile = .NULL.
		loException = .NULL.
		RELEASE loFile, loException
	ENDPROC

	*--------------------------------------------
	* Delete files from disk that are not part of
	* the project.
	*--------------------------------------------
	PROCEDURE CleanupDisk
		LPARAMETERS tcBaseDir
		*--------------------------------------------
		* Check parameters.
		*--------------------------------------------
		IF NOT EMPTY( m.tcBaseDir )
			tcBaseDir = ADDBS( m.tcBaseDir )
		ENDIF
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL i, laDir[1]
		*--------------------------------------------
		* Open the PJX file as a table.
		*--------------------------------------------
		IF m.tcBaseDir == ""
			USE (m.This.PjxFile) ALIAS PJX
		ENDIF
		*--------------------------------------------
		* Look for files and sub dirs.
		*--------------------------------------------
		FOR i = 1 TO ADIR( laDir, m.tcBaseDir + "*.*", "HSD" )
			DO CASE
				CASE NOT "D" $ laDir[ i, 5 ]
					*--------------------------------------------
					* Delete this file if it's not part of the
					* project.
					*--------------------------------------------
					IF NOT m.This.IsProjectFile( m.tcBaseDir + laDir[ i, 1 ] )
						m.This.EraseFile( m.tcBaseDir + laDir[ i, 1 ] )
					ENDIF
				CASE NOT INLIST( laDir[ i, 1 ], ".", ".." )
					*--------------------------------------------
					* Call this method recursively for each sub
					* dir.
					*--------------------------------------------
					m.This.CleanupDisk( m.tcBaseDir + laDir[ i, 1 ] )
			ENDCASE
		ENDFOR
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		IF m.tcBaseDir == ""
			USE IN PJX
		ENDIF
	ENDPROC
	
	*--------------------------------------------
	* Check if a file is part of the project.
	*--------------------------------------------
	FUNCTION IsProjectFile
		LPARAMETERS tcFile
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL llFound, lcExtension, lcName
		lcName = LOWER( m.tcFile )
		*--------------------------------------------
		* Table based file types consist of several
		* files but only the main file name is in the
		* project.
		*--------------------------------------------
		lcExtension = "/" + JUSTEXT( m.lcName ) + "/"
		DO CASE
			CASE m.lcExtension $ "/pjt/pjm/exe/err/"
				lcExtension = "pjx"
			CASE m.lcExtension $ "/fpt/cdx/dba/"
				lcExtension = "dbf"
			CASE m.lcExtension $ "/dct/dcx/dca/"
				lcExtension = "dbc"
			CASE m.lcExtension $ "/sct/sca/"
				lcExtension = "scx"
			CASE m.lcExtension $ "/frt/fra/"
				lcExtension = "frx"
			CASE m.lcExtension $ "/lbt/lba/"
				lcExtension = "lbx"
			CASE m.lcExtension $ "/vct/vca/"
				lcExtension = "vcx"
			CASE m.lcExtension $ "/mnt/mna/"
				lcExtension = "mnx"
			OTHERWISE
				lcExtension = JUSTEXT( m.lcName )
		ENDCASE
		lcName = FORCEEXT( m.lcName, m.lcExtension ) + CHR(0)
		*--------------------------------------------
		* Is it the project file itself or the EXE?
		*--------------------------------------------
		DO CASE
			CASE m.lcName == FORCEEXT( LOWER(JUSTFNAME( m.This.PjmFile )), "pjx" ) + CHR(0)
				RETURN .T.
			CASE m.lcName == "_" + FORCEEXT( LOWER(JUSTFNAME( m.This.PjmFile )), "pjx" ) + CHR(0)
				RETURN .T.
		ENDCASE
		*--------------------------------------------
		* Locate the file in the project.
		*--------------------------------------------
		SELECT PJX
		LOCATE FOR name == m.lcName
		IF NOT FOUND() ;
				AND m.lcExtension == "fxp"
			*--------------------------------------------
			* Keep the FXP file if its PRG file is in the
			* project but excluded.
			*--------------------------------------------
			lcName = FORCEEXT( m.lcName, "prg" ) + CHR(0)
			LOCATE FOR name == m.lcName AND exclude
		ENDIF
		llFound = FOUND()
		*
		RETURN m.llFound
	ENDFUNC
	
	*--------------------------------------------
	* Consolidate error logs.
	*--------------------------------------------
	PROCEDURE ConsolidateErrorLogs
		IF NOT EMPTY( m.This.ErrorLog ) ;
				OR NOT EMPTY( m.This.PrgErrLog )
			*--------------------------------------------
			* Add the contents of the ERR file to the
			* global error log.
			*--------------------------------------------
			IF m.This.IsFile( m.This.ErrFile )
				This.ErrorLog = m.This.ErrorLog +CRLF+ ;
					"." +CRLF+ ;
					FILETOSTR( m.This.ErrFile )
			ENDIF
			*--------------------------------------------
			* Add the contents of the initial ERR file to
			* the global error log.
			*--------------------------------------------
			IF NOT m.This.ErrFile == "BuildProject.err" ;
					AND m.This.IsFile( "BuildProject.err" )
				This.ErrorLog = m.This.ErrorLog +CRLF+ ;
					"." +CRLF+ ;
					FILETOSTR( "BuildProject.err" )
			ENDIF
			*--------------------------------------------
			* Add the contents of the PRG error log to
			* the global error log.
			*--------------------------------------------
			IF NOT EMPTY( m.This.PrgErrLog )
				This.ErrorLog = m.This.ErrorLog +CRLF+ ;
					m.This.PrgErrLog
			ENDIF
			*--------------------------------------------
			* Write everything to the ERR file.
			*--------------------------------------------
			m.This.EraseFile( m.This.ErrFile )
			STRTOFILE( m.This.ErrorLog, m.This.ErrFile )
		ENDIF
	ENDPROC

 	*--------------------------------------------
	* Wrap build errors in XML. The "merge" and
	* "publish" tasks of CCNet want XML.
	*--------------------------------------------
	PROCEDURE WrapErrorsInXml
		*--------------------------------------------
		* Does the error file exist?
		*--------------------------------------------
		IF NOT m.This.IsFile( m.This.ErrFile )
			RETURN
		ENDIF
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcErrors
		lcErrors = FILETOSTR( m.This.ErrFile )
		*--------------------------------------------
		* Wrap the error file contents in XML.
		*--------------------------------------------
		m.This.EraseFile( m.This.ErrFile )
		STRTOFILE( ;
			"<VfpErrors>" +CRLF+ ;
			m.lcErrors +CRLF+ ;
			"</VfpErrors>" + CRLF, ;
			m.This.ErrFile )
	ENDPROC
	
	*--------------------------------------------
	* Communicate the build results to CCNet.
	*--------------------------------------------
	PROCEDURE PublishResults
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		LOCAL lcMessage, llSuccess
		llSuccess = m.This.Success
		*--------------------------------------------
		* Was the build successful?
		*--------------------------------------------
		IF m.llSuccess
			lcMessage = "Build successful"
		ELSE
			lcMessage = FILETOSTR( m.This.ErrFile )
		ENDIF
		IF m.This.TestMode
			*--------------------------------------------
			* We are testing this program interactively.
			*--------------------------------------------
			ACTIVATE SCREEN
			? m.lcMessage
		ELSE
			*--------------------------------------------
			* Unattended mode. Write the build result to
			* StdErr so build servers like
			* CruiseControl.NET can catch it.
			*--------------------------------------------
			IF NOT m.This.WriteToStdOut( m.lcMessage )
				IF NOT m.llSuccess
					*--------------------------------------------
					* Add this error to the ERR file.
					*--------------------------------------------
					lcMessage = CRLF + ;
						PROGRAM( PROGRAM( -1 ) - 1 ) + ": Error writing to StdOut."
					STRTOFILE( m.lcMessage, m.This.ErrFile, .T. )
				ENDIF
			ENDIF
		ENDIF
	ENDPROC
	
	*--------------------------------------------
	* Output the given string to "stdout".
	*--------------------------------------------
	FUNCTION WriteToStdOut
		LPARAMETERS tcMessage
		*--------------------------------------------
		* Setup.
		*--------------------------------------------
		#DEFINE  STD_INPUT_HANDLE -10
		#DEFINE STD_OUTPUT_HANDLE -11
		#DEFINE  STD_ERROR_HANDLE -12
		LOCAL lnHandle, lnWritten, lnSuccess, llSuccess, lnLen
		lnLen = LEN( m.tcMessage )
		*--------------------------------------------
		* Declare Windows API functions.
		*--------------------------------------------
		DECLARE INTEGER AllocConsole IN Win32API
		DECLARE INTEGER GetStdHandle IN Win32API ;
			INTEGER nStdHandle
		DECLARE INTEGER WriteFile IN Win32API ;
			INTEGER filehandle, STRING buffer, ;
			INTEGER BytesToWrite, INTEGER @BytesWritten
		DECLARE INTEGER FreeConsole IN Win32API
		*--------------------------------------------
		* A Windows application has no console window
		* by default. So we have to create one first.
		*--------------------------------------------
		AllocConsole()
		lnHandle = GetStdHandle( STD_OUTPUT_HANDLE )
		*--------------------------------------------
		* Output to "stdout".
		*--------------------------------------------
		lnWritten = 0
		lnSuccess = WriteFile( m.lnHandle, m.tcMessage, m.lnLen, @lnWritten )
		IF NOT m.lnWritten == m.lnLen ;
				OR m.lnSuccess == 0
			llSuccess = .F.
		ELSE
			llSuccess = .T.
		ENDIF
		*--------------------------------------------
		* Cleanup.
		*--------------------------------------------
		FreeConsole()
		*
		RETURN m.llSuccess
	ENDFUNC
	
	*--------------------------------------------
	* A better replacement for FILE().
	*--------------------------------------------
	FUNCTION IsFile
		LPARAMETERS tcFile
		LOCAL laDir[1], llFileFound
		llFileFound = ADIR( laDir, m.tcFile, "HS" ) == 1
		RETURN m.llFileFound
	ENDFUNC
	
	*--------------------------------------------
	* Helper method to avoid errors while
	* deleting a file.
	*--------------------------------------------
	PROCEDURE EraseFile
		LPARAMETERS tcFile
		IF m.This.IsFile( m.tcFile )
			SetFileAttributes( m.tcFile, 0 )
			ERASE (m.tcFile)
		ENDIF
	ENDPROC

ENDDEFINE

*--------------------------------------------
* A helper class to read the lines in the
* [ProjectFiles] section of the PJM file into
* properties.
*--------------------------------------------
DEFINE CLASS ProjectFile AS SESSION

	*--------------------------------------------
	* Properties.
	*--------------------------------------------
	ID = ""
	FileType = ""
	FileName = ""
	Exclude = .F.
	MainProgram = .F.
	CodePage = 1252
	User1 = ""
	User2 = ""
	FileDescription = ""

	*--------------------------------------------
	* Parse the given PJM file line into
	* properties of this class.
	*--------------------------------------------
	PROCEDURE ParseFile
		LPARAMETERS tcLine
		*
		This.ID = VAL(GETWORDNUM( m.tcLine, 1, "," ))
		This.FileType = GETWORDNUM( m.tcLine, 2, "," )
		This.FileName = GETWORDNUM( m.tcLine, 3, "," )
		This.Exclude = EVALUATE(GETWORDNUM( m.tcLine, 4, "," ))
		This.MainProgram = EVALUATE(GETWORDNUM( m.tcLine, 5, "," ))
		This.CodePage = VAL(GETWORDNUM( m.tcLine, 6, "," ))
		This.User1 = GETWORDNUM( m.tcLine, 7, "," )
		This.User2 = GETWORDNUM( m.tcLine, 8, "," )
		This.FileDescription = GETWORDNUM( m.tcLine, 9, "," )
	ENDPROC

ENDDEFINE
