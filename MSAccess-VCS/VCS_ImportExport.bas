Attribute VB_Name = "VCS_ImportExport"
Option Compare Database

Option Explicit

' List of lookup tables that are part of the program rather than the
' data, to be exported with source code
' Set to "*" to export the contents of all tables
'Only used in ExportAllSource
Private Const INCLUDE_TABLES As String = "tbl Settings,tbl ReceiptJournalType"
' This is used in ImportAllSource
Private Const DebugOutput As Boolean = False
'this is used in ExportAllSource
'Causes the VCS_ code to be exported
Private Const ArchiveMyself As Boolean = False
Private StatusLine As String
Private StatusProgress As Integer


'returns true if named module is NOT part of the VCS code
Private Function IsNotVCS(ByVal Name As String) As Boolean
    If Name <> "VCS_ImportExport" And _
      Name <> "VCS_IE_Functions" And _
      Name <> "VCS_File" And _
      Name <> "VCS_Dir" And _
      Name <> "VCS_String" And _
      Name <> "VCS_Loader" And _
      Name <> "VCS_Table" And _
      Name <> "VCS_Reference" And _
      Name <> "VCS_DataMacro" And _
      Name <> "VCS_Report" And _
      Name <> "VCS_Relation" Then
        IsNotVCS = True
    Else
        IsNotVCS = False
    End If

End Function
Public Sub VCS_ProcessOn(isOn As Boolean)
    DoCmd.Hourglass isOn
    StatusLine = " "
End Sub
Public Sub VCS_StatusMessage(msg As String, Optional newline As Boolean = True)
    StatusLine = StatusLine & msg
    
    SysCmd acSysCmdSetStatus, StatusLine
    
    If (newline) Then
        Debug.Print msg
        StatusLine = ""
    Else
        Debug.Print msg;
    End If
End Sub

' Main entry point for EXPORT. Export all forms, reports, queries,
' macros, modules, and lookup tables to `source` folder under the
' database's folder.
Public Sub ExportAllSource()
    Dim Db As Object ' DAO.Database
    Dim source_path As String
    Dim obj_path As String
    Dim qry As Object ' DAO.QueryDef
    Dim doc As Object ' DAO.Document
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_name As String
    Dim obj_type_num As Integer
    Dim obj_count As Integer
    Dim obj_data_count As Integer
    Dim ucs2 As Boolean

    Set Db = CurrentDb

    VCS_ProcessOn True
    CloseFormsReports
    'InitVCS_UsingUcs2

    source_path = VCS_Dir.VCS_ProjectPath() & "source\"
    VCS_Dir.VCS_MkDirIfNotExist source_path

    Debug.Print

    obj_path = source_path & "queries\"
    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "bas"
    VCS_StatusMessage VCS_String.VCS_PadRight("Exporting queries...", 24), False
    obj_count = 0
    For Each qry In Db.QueryDefs
        DoEvents
        If Left$(qry.Name, 1) <> "~" Then
            VCS_IE_Functions.VCS_ExportObject acQuery, qry.Name, obj_path & qry.Name & ".bas", VCS_File.VCS_UsingUcs2
            obj_count = obj_count + 1
        End If
    Next
    VCS_StatusMessage VCS_String.VCS_PadRight("Sanitizing...", 15), False
    VCS_IE_Functions.VCS_SanitizeTextFiles obj_path, "bas"
    VCS_StatusMessage "[" & obj_count & "]"

    
    For Each obj_type In Split( _
        "forms|Forms|" & acForm & "," & _
        "reports|Reports|" & acReport & "," & _
        "macros|Scripts|" & acMacro & "," & _
        "modules|Modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_name = obj_type_split(1)
        obj_type_num = Val(obj_type_split(2))
        obj_path = source_path & obj_type_label & "\"
        obj_count = 0
        VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "bas"
        VCS_StatusMessage VCS_String.VCS_PadRight("Exporting " & obj_type_label & "...", 24), False
        For Each doc In Db.Containers(obj_type_name).Documents
            DoEvents
            If (Left$(doc.Name, 1) <> "~") And _
               (IsNotVCS(doc.Name) Or ArchiveMyself) Then
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = VCS_File.VCS_UsingUcs2
                End If
                VCS_IE_Functions.VCS_ExportObject obj_type_num, doc.Name, obj_path & doc.Name & ".bas", ucs2
                
                If obj_type_label = "reports" Then
                    VCS_Report.VCS_ExportPrintVars doc.Name, obj_path & doc.Name & ".pv"
                End If
                
                obj_count = obj_count + 1
            End If
        Next

        VCS_StatusMessage VCS_String.VCS_PadRight("Sanitizing...", 15), False
        If obj_type_label <> "modules" Then
            VCS_IE_Functions.VCS_SanitizeTextFiles obj_path, "bas"
        End If
        VCS_StatusMessage "[" & obj_count & "]"
    Next
    
    VCS_Reference.VCS_ExportReferences source_path

'-------------------------table export------------------------
    obj_path = source_path & "tables\"
    VCS_Dir.VCS_MkDirIfNotExist Left$(obj_path, InStrRev(obj_path, "\"))
    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "txt"
    
    Dim td As DAO.TableDef
    Dim tds As DAO.TableDefs
    Set tds = Db.TableDefs

    obj_type_label = "tbldef"
    obj_type_name = "Table_Def"
    obj_type_num = acTable
    obj_path = source_path & obj_type_label & "\"
    obj_count = 0
    obj_data_count = 0
    VCS_Dir.VCS_MkDirIfNotExist Left$(obj_path, InStrRev(obj_path, "\"))
    
    'move these into Table and DataMacro modules?
    ' - We don't want to determin file extentions here - or obj_path either!
    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "sql"
    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "xml"
    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "LNKD"
    
    Dim IncludeTablesCol As Collection
    Set IncludeTablesCol = StrSetToCol(INCLUDE_TABLES, ",")
    
    VCS_StatusMessage VCS_String.VCS_PadRight("Exporting " & obj_type_label & "...", 24), False
    
    For Each td In tds
        ' This is not a system table
        ' this is not a temporary table
        If Left$(td.Name, 4) <> "MSys" And _
        Left$(td.Name, 1) <> "~" Then
            If Len(td.connect) = 0 Then ' this is not an external table
                VCS_Table.VCS_ExportTableDef td.Name, obj_path
                If INCLUDE_TABLES = "*" Then
                    DoEvents
                    VCS_Table.VCS_ExportTableData CStr(td.Name), source_path & "tables\"
                    If Len(Dir$(source_path & "tables\" & td.Name & ".txt")) > 0 Then
                        obj_data_count = obj_data_count + 1
                    End If
                ElseIf (Len(Replace(INCLUDE_TABLES, " ", vbNullString)) > 0) And INCLUDE_TABLES <> "*" Then
                    DoEvents
                    On Error GoTo Err_TableNotFound
                    If InCollection(IncludeTablesCol, td.Name) Then
                        VCS_Table.VCS_ExportTableData CStr(td.Name), source_path & "tables\"
                        obj_data_count = obj_data_count + 1
                    End If
Err_TableNotFound:
                    
                'else don't export table data
                End If
            Else
                VCS_Table.VCS_ExportLinkedTable td.Name, obj_path
            End If
            
            obj_count = obj_count + 1
            
        End If
    Next
    Debug.Print "[" & obj_count & "]"
    If obj_data_count > 0 Then
      VCS_StatusMessage VCS_String.VCS_PadRight("Exported data...", 24) & "[" & obj_data_count & "]"
    End If
    
    
    VCS_StatusMessage VCS_String.VCS_PadRight("Exporting Relations...", 24), False
    obj_count = 0
    obj_path = source_path & "relations\"
    VCS_Dir.VCS_MkDirIfNotExist Left$(obj_path, InStrRev(obj_path, "\"))

    VCS_Dir.VCS_ClearTextFilesFromDir obj_path, "txt"

    Dim aRelation As DAO.Relation
    
    For Each aRelation In CurrentDb.Relations
        ' Exclude relations from system tables and inherited (linked) relations
        ' Skip if dbRelationDontEnforce property is not set. The relationship is already in the table xml file. - sean
        If Not (aRelation.Name = "MSysNavPaneGroupsMSysNavPaneGroupToObjects" _
                Or aRelation.Name = "MSysNavPaneGroupCategoriesMSysNavPaneGroups" _
                Or (aRelation.Attributes And DAO.RelationAttributeEnum.dbRelationInherited) = _
                DAO.RelationAttributeEnum.dbRelationInherited) _
                And (aRelation.Attributes = DAO.RelationAttributeEnum.dbRelationDontEnforce) Then
            VCS_Relation.VCS_ExportRelation aRelation, obj_path & aRelation.Name & ".txt"
            obj_count = obj_count + 1
        End If
    Next
    VCS_StatusMessage "[" & obj_count & "]"
    
    VCS_StatusMessage "Done."
    VCS_ProcessOn False
End Sub


' Main entry point for IMPORT. Import all forms, reports, queries,
' macros, modules, and lookup tables from `source` folder under the
' database's folder.
Public Sub ImportAllSource()
    Dim FSO As Object
    Dim source_path As String
    Dim obj_path As String
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_num As Integer
    Dim obj_count As Integer
    Dim fileName As String
    Dim obj_name As String
    Dim ucs2 As Boolean

    Set FSO = CreateObject("Scripting.FileSystemObject")

    VCS_ProcessOn True
    CloseFormsReports
    'InitVCS_UsingUcs2

    source_path = VCS_Dir.VCS_ProjectPath() & "source\"
    If Not FSO.FolderExists(source_path) Then
        MsgBox "No source found at:" & vbCrLf & source_path, vbExclamation, "Import failed"
        Exit Sub
    End If

    Debug.Print
    
    If Not VCS_Reference.VCS_ImportReferences(source_path) Then
        VCS_StatusMessage "Info: no references file in " & source_path
        Debug.Print
    End If

    obj_path = source_path & "queries\"
    fileName = Dir$(obj_path & "*.bas")
    
    Dim tempFilePath As String
    tempFilePath = VCS_File.VCS_TempFile()
    
    If Len(fileName) > 0 Then
        VCS_StatusMessage VCS_String.VCS_PadRight("Importing queries...", 24), False
        obj_count = 0
        Do Until Len(fileName) = 0
            DoEvents
            obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
            VCS_IE_Functions.VCS_ImportObject acQuery, obj_name, obj_path & fileName, VCS_File.VCS_UsingUcs2
            VCS_IE_Functions.VCS_ExportObject acQuery, obj_name, tempFilePath, VCS_File.VCS_UsingUcs2
            VCS_IE_Functions.VCS_ImportObject acQuery, obj_name, tempFilePath, VCS_File.VCS_UsingUcs2
            obj_count = obj_count + 1
            fileName = Dir$()
        Loop
        VCS_StatusMessage "[" & obj_count & "]"
    End If
    
    VCS_Dir.VCS_DelIfExist tempFilePath

    ' restore table definitions
    obj_path = source_path & "tbldef\"
    fileName = Dir$(obj_path & "*.xml")
    If Len(fileName) > 0 Then
        Debug.Print VCS_String.VCS_PadRight("Importing tabledefs...", 24);
        obj_count = 0
        Do Until Len(fileName) = 0
            obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
            If DebugOutput Then
                If obj_count = 0 Then
                    Debug.Print
                End If
                VCS_StatusMessage "  [debug] table " & obj_name, False
                Debug.Print
            End If
            VCS_Table.VCS_ImportTableDef CStr(obj_name), obj_path
            obj_count = obj_count + 1
            fileName = Dir$()
        Loop
        VCS_StatusMessage "[" & obj_count & "]"
    End If
    
    
    ' restore linked tables - we must have access to the remote store to import these!
    fileName = Dir$(obj_path & "*.LNKD")
    If Len(fileName) > 0 Then
        VCS_StatusMessage VCS_String.VCS_PadRight("Importing Linked tabledefs...", 24), False
        obj_count = 0
        Do Until Len(fileName) = 0
            obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
            If DebugOutput Then
                If obj_count = 0 Then
                    Debug.Print
                End If
                Debug.Print "  [debug] table " & obj_name;
                Debug.Print
            End If
            VCS_Table.VCS_ImportLinkedTable CStr(obj_name), obj_path
            obj_count = obj_count + 1
            fileName = Dir$()
        Loop
        VCS_StatusMessage "[" & obj_count & "]"
    End If
    
    
    
    ' NOW we may load data
    obj_path = source_path & "tables\"
    fileName = Dir$(obj_path & "*.txt")
    If Len(fileName) > 0 Then
        VCS_StatusMessage VCS_String.VCS_PadRight("Importing tables...", 24), False
        obj_count = 0
        Do Until Len(fileName) = 0
            DoEvents
            obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
            VCS_Table.VCS_ImportTableData CStr(obj_name), obj_path
            obj_count = obj_count + 1
            fileName = Dir$()
        Loop
        VCS_StatusMessage "[" & obj_count & "]"
    End If
    
    'load Data Macros - not DRY!
    obj_path = source_path & "tbldef\"
    fileName = Dir$(obj_path & "*.dm")
    If Len(fileName) > 0 Then
        VCS_StatusMessage VCS_String.VCS_PadRight("Importing Data Macros...", 24), False
        obj_count = 0
        Do Until Len(fileName) = 0
            DoEvents
            obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
            'VCS_Table.VCS_ImportTableData CStr(obj_name), obj_path
            VCS_DataMacro.VCS_ImportDataMacros obj_name, obj_path
            obj_count = obj_count + 1
            fileName = Dir$()
        Loop
        VCS_StatusMessage "[" & obj_count & "]"
    End If
    

        'import Data Macros
    

    For Each obj_type In Split( _
        "forms|" & acForm & "," & _
        "reports|" & acReport & "," & _
        "macros|" & acMacro & "," & _
        "modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_num = Val(obj_type_split(1))
        obj_path = source_path & obj_type_label & "\"
         
            
        fileName = Dir$(obj_path & "*.bas")
        If Len(fileName) > 0 Then
            VCS_StatusMessage VCS_String.VCS_PadRight("Importing " & obj_type_label & "...", 24), False
            obj_count = 0
            Do Until Len(fileName) = 0
                ' DoEvents no good idea!
                obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = VCS_File.VCS_UsingUcs2
                End If
                If IsNotVCS(obj_name) Then
                    VCS_IE_Functions.VCS_ImportObject obj_type_num, obj_name, obj_path & fileName, ucs2
                    obj_count = obj_count + 1
                Else
                    If ArchiveMyself Then
                            MsgBox "Module " & obj_name & " could not be updated while running. Ensure latest version is included!", vbExclamation, "Warning"
                    End If
                End If
                fileName = Dir$()
            Loop
            VCS_StatusMessage "[" & obj_count & "]"
        
        End If
    Next
    
    'import Print Variables
    VCS_StatusMessage VCS_String.VCS_PadRight("Importing Print Vars...", 24), False
    obj_count = 0
    
    obj_path = source_path & "reports\"
    fileName = Dir$(obj_path & "*.pv")
    Do Until Len(fileName) = 0
        DoEvents
        obj_name = Mid$(fileName, 1, InStrRev(fileName, ".") - 1)
        VCS_Report.VCS_ImportPrintVars obj_name, obj_path & fileName
        obj_count = obj_count + 1
        fileName = Dir$()
    Loop
    VCS_StatusMessage "[" & obj_count & "]"
    
    'import relations
    VCS_StatusMessage VCS_String.VCS_PadRight("Importing Relations...", 24), False
    obj_count = 0
    obj_path = source_path & "relations\"
    fileName = Dir$(obj_path & "*.txt")
    Do Until Len(fileName) = 0
        DoEvents
        VCS_Relation.VCS_ImportRelation obj_path & fileName
        obj_count = obj_count + 1
        fileName = Dir$()
    Loop
    VCS_StatusMessage "[" & obj_count & "]"
    DoEvents
    
    VCS_StatusMessage "Done."
    VCS_ProcessOn False
End Sub

' Main entry point for ImportProject.
' Drop all forms, reports, queries, macros, modules.
' execute ImportAllSource.
Public Sub ImportProject()
On Error GoTo ErrorHandler

    If MsgBox("This action will delete all existing: " & vbCrLf & _
              vbCrLf & _
              Chr$(149) & " Tables" & vbCrLf & _
              Chr$(149) & " Forms" & vbCrLf & _
              Chr$(149) & " Macros" & vbCrLf & _
              Chr$(149) & " Modules" & vbCrLf & _
              Chr$(149) & " Queries" & vbCrLf & _
              Chr$(149) & " Reports" & vbCrLf & _
              vbCrLf & _
              "Are you sure you want to proceed?", vbCritical + vbYesNo, _
              "Import Project") <> vbYes Then
        Exit Sub
    End If

    Dim Db As DAO.Database
    Set Db = CurrentDb
    CloseFormsReports

    Debug.Print
    Debug.Print "Deleting Existing Objects"
    Debug.Print
    
    Dim rel As DAO.Relation
    For Each rel In CurrentDb.Relations
        If Not (rel.Name = "MSysNavPaneGroupsMSysNavPaneGroupToObjects" Or _
                rel.Name = "MSysNavPaneGroupCategoriesMSysNavPaneGroups") Then
            CurrentDb.Relations.Delete (rel.Name)
        End If
    Next

    Dim dbObject As Object
    For Each dbObject In Db.QueryDefs
        DoEvents
        If Left$(dbObject.Name, 1) <> "~" Then
'            Debug.Print dbObject.Name
            Db.QueryDefs.Delete dbObject.Name
        End If
    Next
    
    Dim td As DAO.TableDef
    For Each td In CurrentDb.TableDefs
        If Left$(td.Name, 4) <> "MSys" And _
            Left$(td.Name, 1) <> "~" Then
            CurrentDb.TableDefs.Delete (td.Name)
        End If
    Next

    Dim objType As Variant
    Dim objTypeArray() As String
    Dim doc As Object
    '
    '  Object Type Constants
    Const OTNAME As Byte = 0
    Const OTID As Byte = 1

    For Each objType In Split( _
            "Forms|" & acForm & "," & _
            "Reports|" & acReport & "," & _
            "Scripts|" & acMacro & "," & _
            "Modules|" & acModule _
            , "," _
        )
        objTypeArray = Split(objType, "|")
        DoEvents
        For Each doc In Db.Containers(objTypeArray(OTNAME)).Documents
            DoEvents
            If (Left$(doc.Name, 1) <> "~") And _
               (IsNotVCS(doc.Name)) Then
'                Debug.Print doc.Name
                DoCmd.DeleteObject objTypeArray(OTID), doc.Name
            End If
        Next
    Next
    
    Debug.Print "================="
    Debug.Print "Importing Project"
    ImportAllSource
    
    Exit Sub

ErrorHandler:
    Debug.Print "VCS_ImportExport.ImportProject: Error #" & Err.Number & vbCrLf & _
                Err.Description
End Sub


'===================================================================================================================================
'-----------------------------------------------------------'
' Helper Functions - these should be put in their own files '
'-----------------------------------------------------------'

' Close all open forms.
Private Sub CloseFormsReports()
    On Error GoTo ErrorHandler
    Do While Forms.Count > 0
        DoCmd.Close acForm, Forms(0).Name
        DoEvents
    Loop
    Do While Reports.Count > 0
        DoCmd.Close acReport, Reports(0).Name
        DoEvents
    Loop
    Exit Sub

ErrorHandler:
    Debug.Print "VCS_ImportExport.CloseFormsReports: Error #" & Err.Number & vbCrLf & _
                Err.Description
End Sub


'errno 457 - duplicate key (& item)
Private Function StrSetToCol(ByVal strSet As String, ByVal delimiter As String) As Collection 'throws errors
    Dim strSetArray() As String
    Dim col As Collection
    
    Set col = New Collection
    strSetArray = Split(strSet, delimiter)
    
    Dim item As Variant
    For Each item In strSetArray
        col.Add item, item
    Next
    
    Set StrSetToCol = col
End Function


' Check if an item or key is in a collection
Private Function InCollection(col As Collection, Optional vItem, Optional vKey) As Boolean
    On Error Resume Next

    Dim vColItem As Variant

    InCollection = False

    If Not IsMissing(vKey) Then
        col.item vKey

        '5 if not in collection, it is 91 if no collection exists
        If Err.Number <> 5 And Err.Number <> 91 Then
            InCollection = True
        End If
    ElseIf Not IsMissing(vItem) Then
        For Each vColItem In col
            If vColItem = vItem Then
                InCollection = True
                GoTo Exit_Proc
            End If
        Next vColItem
    End If

Exit_Proc:
    Exit Function
Err_Handle:
    Resume Exit_Proc
End Function


