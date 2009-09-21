*===========================================================
* BuildProject2.prg
* A project specific hook PRG for the automated build.
* Called right before and after building the EXE. Include it
* in your project source tree if you want to use it.
*
* Parameters:
*	tcErrorMessage	(called by reference) Will be written to
*					the build error log. Setting this
*					parameter to something non-empty means
*					failure, too.
*	toBuild			A reference to the active instance of
*					the PjmFile class of BuildProject.prg.
*	tlBeforeBuild	.T. if called before build.
*					.F. if called after build.
*
* Return Values		.T. (success).
*					.F. (failure).
*===========================================================
LPARAMETERS tcErrorMessage, toBuild, tlBeforeBuild
*--------------------------------------------
* Setup.
*--------------------------------------------
LOCAL lcManifestType, lcExeName, lcPjmFile, lcPjxFile, lcExtra, llReturn
lcManifestType = m.toBuild.ManifestType
lcExeName = m.toBuild.ExeName
lcPjmFile = m.toBuild.PjmFile
lcPjxFile = m.toBuild.PjxFile
lcExtra = m.toBuild.Extra
llReturn = .T.

*--------------------------------------------
* Sample 1:
* You can replace the values of #DEFINEs in
* header or prg files if you want.
*(..)toBuild.Extra carries the 4th parameter
*(..)you submitted to BuildProject.prg in
*(..)ccnet.config. E.g., 
*(..) Vfp_Sample.pjm NULL NULL Customer1
*--------------------------------------------
*IF m.tlBeforeBuild ;
*		AND UPPER(JUSTSTEM( m.lcPjmFile )) == "VFP_SAMPLE" ;
*		AND UPPER(ALLTRIM( m.lcExtra )) == "CUSTOMER1"
*	llReturn = SetDefine( @tcErrorMessage, "Vfp_Sample_Main.prg", "ccCAPTION", ["Vfp Sample for Customer1"] )
*ENDIF

*--------------------------------------------
* Sample 2:
* Switch the icon of Vfp_Sample.exe.
*--------------------------------------------
*IF m.tlBeforeBuild ;
*		AND m.llReturn ;
*		AND UPPER(JUSTSTEM( m.lcPjmFile )) == "VFP_SAMPLE"
*	llReturn = SwitchIcon( @tcErrorMessage, m.lcPjxFile, ;
*		IIF( m.lcExtra == "Customer1", "Icons\Customer1.ico", "Icons\Vfp_Sample.ico" ) )
*ENDIF

*--------------------------------------------
* Write your code here.
*--------------------------------------------
*...

*--------------------------------------------
* Cleanup.
*--------------------------------------------
toBuild = .NULL.
RELEASE toBuild
*
RETURN m.llReturn


*===========================================================
* Helper functions.
*===========================================================
*--------------------------------------------
* Change a #DEFINE.
*(..)Works with text files only.
*(..)No vcx, scx, etc..
*--------------------------------------------
FUNCTION SetDefine
	LPARAMETERS tcErrorMessage, tcFile, tcDefine, tcNewValue
	*--------------------------------------------
	* Setup.
	*--------------------------------------------
	LOCAL lcText, lcNewText, laDir[1], llFound, lcComment, ;
		laLines[1], i, lnAt, lnAt2
	*--------------------------------------------
	* Check parameters.
	*--------------------------------------------
	IF NOT "|" + UPPER(JUSTEXT( m.tcFile )) + "|" $ "|H|PRG|SPR|QPR|"
		tcErrorMessage = PROGRAM() + ": Invalid file type [" + m.tcFile + "]"
		RETURN .F.
	ENDIF
	IF NOT ADIR( laDir, m.tcFile ) == 1
		*--------------------------------------------
		* Look for the file along the vfp's
		* set("path").
		*--------------------------------------------
		IF FILE( m.tcFile )
			*--------------------------------------------
			* Get absolute path.
			*--------------------------------------------
			tcFile = FULLPATH( m.tcFile )
			ADIR( laDir, m.tcFile )
		ELSE
			tcErrorMessage = PROGRAM() + ": File not found: " + m.tcFile
			RETURN .F.
		ENDIF
	ENDIF
	*--------------------------------------------
	* Read file.
	*--------------------------------------------
	lcText = FILETOSTR( m.tcFile )
	*--------------------------------------------
	* Look for the #DEFINE line by line.
	*--------------------------------------------
	lcNewText = ""
	FOR i = 1 TO ALINES( laLines, m.lcText )
		IF LEFT( LTRIM( laLines[ i ] ), LEN( "#DEFINE" ) ) == "#DEFINE"
			*--------------------------------------------
			* Start of the constant.
			*--------------------------------------------
			lnAt = ATC( m.tcDefine, laLines[ i ] )
			*--------------------------------------------
			* Start of the firsts word after "#DEFINE".
			*--------------------------------------------
			lnAt2 = ATC( "#DEFINE", laLines[ i ] ) + LEN( "#DEFINE" )
			DO WHILE SUBSTR( laLines[ i ], m.lnAt2, 1 ) $ SPACE(1)+CHR(9)
				lnAt2 = m.lnAt2 + 1
			ENDDO
			*--------------------------------------------
			* Is the item we're lokking for after the
			* word #DEFINE and is it surrounded by space
			* or TAB?
			*--------------------------------------------
			IF m.lnAt > LEN( "#DEFINE" ) + 1 ;
					AND m.lnAt == m.lnAt2 ;
					AND SUBSTR( laLines[ i ], m.lnAt - 1, 1 ) $ SPACE(1)+CHR(9) ;
					AND SUBSTR( laLines[ i ], m.lnAt + LEN( m.tcDefine ), 1 ) $ SPACE(1)+CHR(9)
				*--------------------------------------------
				* Look for the start of the old value.
				*--------------------------------------------
				lnAt = m.lnAt + LEN( m.tcDefine )
				DO WHILE SUBSTR( laLines[ i ], m.lnAt + 1, 1 ) $ SPACE(1)+CHR(9)
					lnAt = m.lnAt + 1
				ENDDO
				*--------------------------------------------
				* Is there a comment after the code?
				*--------------------------------------------
				IF "&"+"&" $ laLines[ i ]
					*--------------------------------------------
					* Keep the distance of value and comment.
					*--------------------------------------------
					lnAt2 = AT( "&"+"&", laLines[ i ] )
					DO WHILE SUBSTR( laLines[ i ], m.lnAt2 - 1, 1 ) $ SPACE(1)+CHR(9)
						lnAt2 = m.lnAt2 - 1
					ENDDO
					lcComment = SUBSTR( laLines[ i ], m.lnAt2 )
				ELSE
					lcComment = ""
				ENDIF
				*--------------------------------------------
				* Build the modified line.
				*--------------------------------------------
				lcNewText = m.lcNewText + ;
					LEFT( laLines[ i ], m.lnAt ) + TRANSFORM( m.tcNewValue ) + ;
					m.lcComment + CHR(13)+CHR(10)
				llFound = .T.
				LOOP
			ENDIF
		ENDIF
		*--------------------------------------------
		* Nothing changed in this line.
		*--------------------------------------------
		lcNewText = m.lcNewText + ;
			laLines[ i ] + CHR(13)+CHR(10)
	ENDFOR
	*
	DO CASE
		CASE NOT m.llFound
			tcErrorMessage = PROGRAM() + ": #DEFINE " + m.tcDefine + ;
				" not found in " + m.tcFile
			RETURN .F.
		CASE m.lcText == m.lcNewText
			* Nothing to do.
		OTHERWISE
			IF "R" $ laDir[ 1, 5 ]
				tcErrorMessage = PROGRAM() + ": File " + m.tcFile + " is ReadOnly"
				RETURN .F.
			ENDIF
			IF "H" $ laDir[ 1, 5 ]
				tcErrorMessage = PROGRAM() + ": File " + m.tcFile + " is Hidden"
				RETURN .F.
			ENDIF
			IF "S" $ laDir[ 1, 5 ]
				tcErrorMessage = PROGRAM() + ": File " + m.tcFile + " is System"
				RETURN .F.
			ENDIF
			*--------------------------------------------
			* Write back the changed file.
			*--------------------------------------------
			ERASE (m.tcFile)
			STRTOFILE( m.lcNewText, m.tcFile )
	ENDCASE
	*
	RETURN .T.
ENDFUNC

*--------------------------------------------
* Switch exe icon.
*--------------------------------------------
FUNCTION SwitchIcon
	LPARAMETERS tcErrorMessage, tcPjxFile, tcIconFile
	*--------------------------------------------
	* Check parameters.
	*--------------------------------------------
	IF NOT FILE( m.tcIconFile )
		tcErrorMessage = PROGRAM() + ": File " + ;
			m.tcPjxFile + " not found"
		RETURN .F.
	ENDIF
	*--------------------------------------------
	* Setup.
	*--------------------------------------------
	LOCAL lnSelect, llReturn
	lnSelect = SELECT(0)
	llReturn = .T.
	*--------------------------------------------
	* Open project as a table.
	*--------------------------------------------
	SELECT 0
	USE (m.tcPjxFile) SHARED AGAIN
	*--------------------------------------------
	* Switch exe icon.
	*--------------------------------------------
	LOCATE FOR type == "i"
	IF FOUND()
		REPLACE name WITH LOWER( m.tcIconFile ) + CHR(0)
	ELSE
		tcErrorMessage = PROGRAM() + ": No exe icon set: " + m.tcPjxFile
		llReturn = .F.
	ENDIF
	*--------------------------------------------
	* Cleanup.
	*--------------------------------------------
	USE
	SELECT (m.lnSelect)
	*
	RETURN m.llReturn
ENDFUNC
