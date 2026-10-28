#AutoIt3Wrapper_Change2CUI=y
#cs ---------------------------------------------------------------------------
    nessus_to_csv.au3

    Converts every .nessus file in a directory into one CSV file with one row
    per finding (ReportItem). The columns are the host's IP address and name
    followed by every attribute and child element found on any finding in any
    of the files, so nothing in the export is left out.

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

; Column registry: name -> 0-based index, and the names in first-seen order.
Global $g_oColumns = ObjCreate("Scripting.Dictionary")
Global $g_aColumns[0]

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

    If Not IsObj($g_oColumns) Then
        _Report("Scripting.Dictionary is not available on this machine.")
        Return 1
    EndIf
    If Not FileExists($g_sInputDir) Then
        _Report("Input folder not found: " & $g_sInputDir)
        Return 1
    EndIf

    Local $aFiles = _ListNessusFiles($g_sInputDir)
    If UBound($aFiles) = 0 Then
        _Report("No .nessus files found in " & $g_sInputDir)
        Return 1
    EndIf

    ; The two host columns always come first.
    _ColumnIndex("ip Address")
    _ColumnIndex("host")

    ; Pass 1: learn the full column set from every finding in every file.
    For $i = 0 To UBound($aFiles) - 1
        ConsoleWrite("Scanning " & $aFiles[$i] & @CRLF)
        Local $oXml = _LoadXml($g_sInputDir & "\" & $aFiles[$i])
        If Not IsObj($oXml) Then ContinueLoop
        Local $oItems = $oXml.selectNodes("//ReportHost/ReportItem")
        If Not IsObj($oItems) Then ContinueLoop
        For $oItem In $oItems
            _RegisterColumns($oItem)
        Next
    Next

    ; Pass 2: write the header and one row per finding.
    ; UTF-8 with a byte order mark so Excel reads accented text correctly.
    Local $hCsv = FileOpen($g_sOutputFile, $FO_OVERWRITE + $FO_UTF8)
    If $hCsv = -1 Then
        _Report("Could not open output file for writing: " & $g_sOutputFile)
        Return 1
    EndIf
    FileWriteLine($hCsv, _CsvRow($g_aColumns))

    Local $iFiles = 0, $iRows = 0
    For $i = 0 To UBound($aFiles) - 1
        ConsoleWrite("Converting " & $aFiles[$i] & @CRLF)
        Local $oXml = _LoadXml($g_sInputDir & "\" & $aFiles[$i])
        If Not IsObj($oXml) Then ContinueLoop
        $iFiles += 1
        $iRows += _WriteFindings($oXml, $hCsv)
    Next
    FileClose($hCsv)

    _Report("Converted " & $iFiles & " .nessus file(s): " & $iRows & " finding(s), " & _
            UBound($g_aColumns) & " columns." & @CRLF & "Output: " & $g_sOutputFile)
    Return 0
EndFunc

; Names of the .nessus files in a folder, as a zero-based array.
Func _ListNessusFiles($sDir)
    Local $aFiles[0]
    Local $hSearch = FileFindFirstFile($sDir & "\*.nessus")
    If $hSearch = -1 Then Return $aFiles
    While True
        Local $sName = FileFindNextFile($hSearch)
        If @error Then ExitLoop
        If @extended Then ContinueLoop ; skip directories
        ReDim $aFiles[UBound($aFiles) + 1]
        $aFiles[UBound($aFiles) - 1] = $sName
    WEnd
    FileClose($hSearch)
    Return $aFiles
EndFunc

; Parses a file into an MSXML document. Returns the document, or 0 on failure.
Func _LoadXml($sPath)
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
    Return $oXml
EndFunc

; Adds a column for each attribute and child element of a finding.
Func _RegisterColumns($oItem)
    For $oAttr In $oItem.attributes
        _ColumnIndex($oAttr.name)
    Next
    For $oChild In $oItem.childNodes
        If $oChild.nodeType = 1 Then _ColumnIndex($oChild.nodeName)
    Next
EndFunc

; Index of a named column, creating it at the end if it is new.
Func _ColumnIndex($sName)
    If $g_oColumns.Exists($sName) Then Return $g_oColumns.Item($sName)
    Local $iIndex = UBound($g_aColumns)
    ReDim $g_aColumns[$iIndex + 1]
    $g_aColumns[$iIndex] = $sName
    $g_oColumns.Add($sName, $iIndex)
    Return $iIndex
EndFunc

; Writes one CSV row per ReportItem in the document. Returns the row count.
Func _WriteFindings($oXml, $hCsv)
    Local $iRows = 0
    Local $oHosts = $oXml.selectNodes("//ReportHost")
    If Not IsObj($oHosts) Then Return 0
    Local $aRow
    For $oHost In $oHosts
        Local $sHost = _Attr($oHost, "name")
        ; Prefer the scanned IP; the name attribute is often a hostname.
        Local $sIp = _ChildText($oHost, "HostProperties/tag[@name='host-ip']")
        If $sIp = "" Then $sIp = $sHost
        Local $oItems = $oHost.selectNodes("ReportItem")
        If Not IsObj($oItems) Then ContinueLoop
        For $oItem In $oItems
            $aRow = _NewRow()
            $aRow[0] = $sIp
            $aRow[1] = $sHost
            For $oAttr In $oItem.attributes
                _SetCell($aRow, $oAttr.name, $oAttr.value)
            Next
            For $oChild In $oItem.childNodes
                If $oChild.nodeType = 1 Then _SetCell($aRow, $oChild.nodeName, $oChild.text)
            Next
            FileWriteLine($hCsv, _CsvRow($aRow))
            $iRows += 1
        Next
    Next
    Return $iRows
EndFunc

; An empty row with one cell per known column.
Func _NewRow()
    Local $aRow[UBound($g_aColumns)]
    For $i = 0 To UBound($aRow) - 1
        $aRow[$i] = ""
    Next
    Return $aRow
EndFunc

; Stores a value in the named column. Repeated elements such as several
; <cve> entries on one finding are joined with "; " in the one cell.
Func _SetCell(ByRef $aRow, $sName, $vValue)
    Local $sValue = StringStripWS(String($vValue), 3)
    If $sValue = "" Then Return
    Local $iIndex = _ColumnIndex($sName)
    If $iIndex >= UBound($aRow) Then ReDim $aRow[$iIndex + 1]
    If $aRow[$iIndex] = "" Then
        $aRow[$iIndex] = $sValue
    Else
        $aRow[$iIndex] &= "; " & $sValue
    EndIf
EndFunc

; Reads an attribute as a string, "" when it is absent.
Func _Attr($oNode, $sName)
    Local $vValue = $oNode.getAttribute($sName)
    If IsString($vValue) Or IsNumber($vValue) Then Return String($vValue)
    Local $oAttr = $oNode.attributes.getNamedItem($sName)
    If IsObj($oAttr) Then Return String($oAttr.text)
    Return ""
EndFunc

; Trimmed text of the first node matching an XPath relative to $oNode, or "".
Func _ChildText($oNode, $sPath)
    Local $oChild = $oNode.selectSingleNode($sPath)
    If Not IsObj($oChild) Then Return ""
    Return StringStripWS(String($oChild.text), 3)
EndFunc

; Joins an array of cells into one CSV line.
Func _CsvRow(ByRef $aCells)
    Local $sLine = ""
    For $i = 0 To UBound($aCells) - 1
        If $i > 0 Then $sLine &= ","
        $sLine &= _CsvField($aCells[$i])
    Next
    Return $sLine
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
