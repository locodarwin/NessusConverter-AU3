#AutoIt3Wrapper_Change2CUI=y
#cs ---------------------------------------------------------------------------
    nessus_to_csv.au3

    Converts every .nessus file in a directory into one CSV file with three
    columns: ip Address, vulnerability, severity.

    AutoIt port of the Python script in https://github.com/levyjm/NessusConverter

    Usage:
        nessus_to_csv.au3 [input_dir] [output_csv] [/quiet]

        input_dir   Folder holding the .nessus files. Defaults to the folder
                    the script lives in, so dropping the script next to the
                    files and double-clicking it works.
        output_csv  Where to write the CSV. Defaults to nessus_file.csv on
                    the current user's Desktop (the original wrote to
                    /tmp/nessus_file.csv).
        /quiet      Skip the summary message box at the end.

    Requires only a stock AutoIt install; XML parsing uses the MSXML COM
    object that ships with Windows.
#ce ---------------------------------------------------------------------------

#include <FileConstants.au3>
#include <MsgBoxConstants.au3>

Global $g_sInputDir = @ScriptDir
Global $g_sOutputFile = @DesktopDir & "\nessus_file.csv"
Global $g_bQuiet = False
Global $g_iComError = 0

_ParseCommandLine()
Exit _Main()

Func _ParseCommandLine()
    Local $iPositional = 0
    For $i = 1 To $CmdLine[0]
        Local $sArg = $CmdLine[$i]
        If $sArg = "/quiet" Or $sArg = "/q" Then
            $g_bQuiet = True
        Else
            $iPositional += 1
            If $iPositional = 1 Then $g_sInputDir = $sArg
            If $iPositional = 2 Then $g_sOutputFile = $sArg
        EndIf
    Next
    ; Trim a trailing backslash so path joins stay tidy.
    If StringRight($g_sInputDir, 1) = "\" And StringLen($g_sInputDir) > 3 Then
        $g_sInputDir = StringTrimRight($g_sInputDir, 1)
    EndIf
EndFunc

Func _Main()
    ; Keep a COM failure (bad XML, missing MSXML) from aborting the script.
    Local $oErr = ObjEvent("AutoIt.Error", "_ComErrorHandler")
    #forceref $oErr

    If Not FileExists($g_sInputDir) Then
        _Report("Input folder not found: " & $g_sInputDir)
        Return 1
    EndIf

    Local $hCsv = FileOpen($g_sOutputFile, $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $hCsv = -1 Then
        _Report("Could not open output file for writing: " & $g_sOutputFile)
        Return 1
    EndIf
    FileWriteLine($hCsv, "ip Address,vulnerability,severity")

    Local $iFiles = 0, $iRows = 0
    Local $hSearch = FileFindFirstFile($g_sInputDir & "\*.nessus")
    If $hSearch <> -1 Then
        While True
            Local $sName = FileFindNextFile($hSearch)
            If @error Then ExitLoop
            If @extended Then ContinueLoop ; skip directories
            $iFiles += 1
            ConsoleWrite("Reading " & $sName & @CRLF)
            $iRows += _ConvertFile($g_sInputDir & "\" & $sName, $hCsv)
        WEnd
        FileClose($hSearch)
    EndIf
    FileClose($hCsv)

    Local $sSummary = "Converted " & $iFiles & " .nessus file(s), " & $iRows & " row(s)." & @CRLF & _
            "Output: " & $g_sOutputFile
    If $iFiles = 0 Then $sSummary = "No .nessus files found in " & $g_sInputDir & @CRLF & $sSummary
    _Report($sSummary)
    Return 0
EndFunc

; Appends one CSV row per ReportItem in the file. Returns the number of rows written.
Func _ConvertFile($sPath, $hCsv)
    Local $oXml = ObjCreate("Msxml2.DOMDocument.6.0")
    If Not IsObj($oXml) Then $oXml = ObjCreate("Microsoft.XMLDOM")
    If Not IsObj($oXml) Then
        ConsoleWrite("  MSXML is not available on this machine." & @CRLF)
        Return 0
    EndIf

    $oXml.async = False
    $oXml.validateOnParse = False
    $oXml.resolveExternals = False
    $oXml.setProperty("SelectionLanguage", "XPath")

    $g_iComError = 0
    If Not $oXml.load($sPath) Or $g_iComError Then
        Local $sReason = ""
        If IsObj($oXml.parseError) Then $sReason = $oXml.parseError.reason
        ConsoleWrite("  Skipped, could not parse XML. " & StringStripWS($sReason, 3) & @CRLF)
        Return 0
    EndIf

    Local $iRows = 0
    Local $oHosts = $oXml.selectNodes("//ReportHost")
    If Not IsObj($oHosts) Then Return 0
    Local $bWarned = False
    For $oHost In $oHosts
        ; Prefer the scanned IP; the name attribute may be a hostname.
        Local $sIp = _ChildText($oHost, "HostProperties/tag[@name='host-ip']")
        If $sIp = "" Then $sIp = _NodeValue($oHost, "name")
        Local $oItems = $oHost.selectNodes("ReportItem")
        If Not IsObj($oItems) Then ContinueLoop
        For $oItem In $oItems
            ; Compliance scans file every result under one plugin ("Unix
            ; Compliance Checks" and the like); the useful name is the
            ; individual check, held in a cm:compliance-check-name child.
            Local $sPlugin = _ChildText($oItem, "*[local-name()='compliance-check-name']")
            If $sPlugin = "" Then $sPlugin = _NodeValue($oItem, "pluginName", "plugin_name")
            If $sPlugin = "" And Not $bWarned Then
                $bWarned = True
                ConsoleWrite("  Warning: a ReportItem has no plugin name. Its attributes are: " & _
                        _AttrNames($oItem) & @CRLF)
            EndIf
            FileWriteLine($hCsv, _CsvField($sIp) & "," & _
                    _CsvField($sPlugin) & "," & _
                    _CsvField(_NodeValue($oItem, "severity")))
            $iRows += 1
        Next
    Next
    Return $iRows
EndFunc

; Reads a value from a node: the attribute first, then a child element with
; the same name, then one at the alternate XPath. "" when none is present.
Func _NodeValue($oNode, $sAttr, $sAltPath = "")
    Local $sValue = _Attr($oNode, $sAttr)
    If $sValue = "" Then $sValue = _ChildText($oNode, $sAttr)
    If $sValue = "" And $sAltPath <> "" Then $sValue = _ChildText($oNode, $sAltPath)
    Return $sValue
EndFunc

; Trimmed text of the first node matching an XPath relative to $oNode, or "".
Func _ChildText($oNode, $sPath)
    Local $oChild = $oNode.selectSingleNode($sPath)
    If Not IsObj($oChild) Then Return ""
    Return StringStripWS(String($oChild.text), 3)
EndFunc

; Space-separated list of an element's attribute names, for diagnostics.
Func _AttrNames($oNode)
    Local $sList = ""
    For $oAttr In $oNode.attributes
        $sList &= $oAttr.name & " "
    Next
    If $sList = "" Then Return "(none)"
    Return StringStripWS($sList, 2)
EndFunc

; Reads an attribute as a string, "" when it is absent.
Func _Attr($oNode, $sName)
    Local $vValue = $oNode.getAttribute($sName)
    If IsString($vValue) Or IsNumber($vValue) Then Return String($vValue)
    ; Some MSXML/AutoIt pairings hand back a variant AutoIt cannot type;
    ; go through the attribute collection instead.
    Local $oAttr = $oNode.attributes.getNamedItem($sName)
    If IsObj($oAttr) Then Return String($oAttr.text)
    Return ""
EndFunc

; Quotes a field when it holds a comma, quote or line break, per RFC 4180.
Func _CsvField($sValue)
    If StringRegExp($sValue, '[,"\r\n]') Then
        Return '"' & StringReplace($sValue, '"', '""') & '"'
    EndIf
    Return $sValue
EndFunc

Func _Report($sText)
    ConsoleWrite($sText & @CRLF)
    If Not $g_bQuiet Then MsgBox($MB_ICONINFORMATION, "Nessus to CSV", $sText)
EndFunc

Func _ComErrorHandler($oError)
    $g_iComError = 1
    ConsoleWrite("  COM error 0x" & Hex($oError.number, 8) & " at line " & $oError.scriptline & _
            ": " & StringStripWS($oError.description, 3) & @CRLF)
EndFunc
