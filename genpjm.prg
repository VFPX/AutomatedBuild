#DEFINE CR CHR(13)
* Generates a PJM file from a PJX file
* Many tools work backwards to generate the PJX file from the PJM because the PJM is checked into source control
* For those that don't use VSS/TFS for their source control provider, this can be used as a projectHook to generate the PJM file
LPARAMETERS cProjectName
LOCAL cSafety, cPJXFile, nSele
nSele = SELECT()
cSafety = SET("Safety")
cPJXFile = ""
IF EMPTY(cProjectName) 
	IF type("_VFP.ActiveProject")!="U"
		cPJXFile = _vfp.ActiveProject.Name
	ENDIF	
ELSE
	cPJXFile= FORCEEXT(cProjectName,'pjx')
ENDIF
IF EMPTY(cPJXFile) OR NOT FILE(cPJXFile)
	WAIT WINDOW "Could not find project " + cPJXFile timeout 3
	RETURN .f.
ENDIF
IF NOT createCursor(cPJXFile)
	WAIT WINDOW "Could not import cursor" TIMEOUT 3
	RETURN .f.
ENDIF
SELECT crsProjectFile
GO TOP

* Skip the demographic information (for now anyway), as it's not necessary to rebuild PJX
TEXT TO cPJM NOSHOW TEXTMERGE 
Version=  1.20
Author=
Company=
Address=
City=
State=
Zip=
Country=
SaveCode=.T.
Debug=.F.
Encrypt=.F.
NoLogo=.F.
CommentStyle=1
Comments=<<FixString(SUBSTR(devInfo,223,255)))>>
CompanyName=<<FixString(SUBSTR(devInfo,478,255))>>
FileDescription=<<FixString(SUBSTR(devInfo,733,255))>>
LegalCopyright=<<FixString(SUBSTR(devInfo,988,255))>>
LegalTrademarks=<<FixString(SUBSTR(devInfo,1243,255))>>
ProductName=<<FixString(SUBSTR(devInfo,1498,255))>>
Major=<<FixString(SUBSTR(devInfo,1753,5))>>
Minor=<<FixString(SUBSTR(devInfo,1758,5))>>
Revision=<<FixString(SUBSTR(devInfo,1763,5))>>
AutoIncrement=<<IIF(SUBSTR(devInfo,1788,1)==CHR(0),'.F.','.T.')>>
[OLEServers]

ENDTEXT
* List OLE Servers

cPJM = cPJM + ;
	"[OLEServersEnd]"+CR+"[ProjectFiles]"+CR

* List of project files
INDEX ON id TAG id
SCAN FOR NOT EMPTY(id)
	cPJM = cPJM + ;
		TRANSFORM(id)+','+;
		type+','+;
		fixString(name)+','+;
		IIF(exclude,'.T.','.F.')+','+;
		IIF(mainprog,'.T.','.F.')+','+;
		TRANSFORM(cpId)+','+;
		','+;
		','+;	
		fixString(comments)+CR
ENDSCAN
cPjm = cPjm + "[EOF]"

SET SAFETY OFF
cPJMFile = FORCEEXT(cPJXFile,'PJM')
STRTOFILE(cPJM, cPJMFile,0)
SET SAFETY &cSafety 
USE IN crsProjectFile
SELECT( nSele)

RETURN cPJM


FUNCTION createCursor
LPARAMETERS cPJXFile
SELECT 0
create cursor crsProjectFile ;
	(NAME M, ;
	TYPE C(1), ;
	ID N(10,0), ;
	TIMESTAMP N(10,0), ;
	OUTFILE M, ;
	HOMEDIR M, ;
	EXCLUDE L, ;
	MAINPROG L, ;
	SAVECODE L, ;
	DEBUG L, ;
	ENCRYPT L, ;
	NOLOGO L, ;
	CMNTSTYLE N(1,0), ;
	OBJREV N(5,0), ;
	DEVINFO M, ;
	SYMBOLS M, ;
	OBJECT M, ;
	CKVAL N(6,0), ;
	CPID N(5,0), ;
	OSTYPE C(4), ;
	OSCREATOR C(4), ;
	COMMENTS M, ;
	RESERVED1 M, ;
	RESERVED2 M, ;
	SCCDATA M, ;
	LOCAL L, ;
	KEY C(32), ;
	USER M)
APPEND FROM (cPJXFile)

RETURN RECCOUNT() > 0


FUNCTION FixString
LPARAMETERS cString
RETURN ALLTRIM(CHRTRAN(cString,CHR(0),''))
