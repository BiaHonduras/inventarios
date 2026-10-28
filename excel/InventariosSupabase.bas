Attribute VB_Name = "InventariosSupabase"
Option Explicit
Private Enviando As Boolean
Private Const WEB As String = "https://biahonduras.github.io/inventarios/importar-excel.html"
Private Const ENDPOINT As String = "https://czxzghhwgfciyrgmgtai.supabase.co/rest/v1/rpc/excel_inventory_receive"
' Public project key. Not an administrator key; the one-use pass authorizes staging only.
Private Const PUBLIC_KEY As String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHpnaGh3Z2ZjaXlyZ21ndGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzYxMTgsImV4cCI6MjA4ODc1MjExOH0.LdODWE1RDggRq11NkfgFTUVv6g1E5iQxTfOtZnV0gF0"

Public Sub ActualizarYEnviarInventarios()
    Dim ws As Worksheet, tabla As ListObject, qt As QueryTable
    Dim nombres As Variant, campos As Variant, filas As Variant
    Dim i As Long, j As Long, col As Long, cuerpo As String, codigo As String
    Dim http As Object, respuesta As String, valor As Variant, exito As Boolean
    Dim rowJson() As String, cellJson() As String
    If Enviando Then Exit Sub
    Enviando = True
    On Error GoTo Fallo
    Set ws = ThisWorkbook.Worksheets("DATA")
    ' FACTS62 is the table name in the supplied book. INVENTARIOS is the SQL connection.
    On Error Resume Next
    Set tabla = ws.ListObjects("FACTS62")
    If tabla Is Nothing Then Set tabla = ws.ListObjects("INVENTARIOS")
    On Error GoTo Fallo
    If tabla Is Nothing Then Err.Raise vbObjectError + 1, , "No se encontro la tabla FACTS62 o INVENTARIOS en DATA."
    nombres = Split("Bodega|CodArticulo|CodDescrip|ClaseArticulo|CafeRep|CostoActual|Cantidades|Fecha|Masterpack|Marca|Proveedor|ExistenciaCajasFardos|VentasCajasFardos|LbReales|ProductoVenta|Categoria|Familia|Libras|Sociedad", "|")
    ReDim campos(0 To UBound(nombres))
    For j = 0 To UBound(nombres)
        campos(j) = tabla.ListColumns(CStr(nombres(j))).Index
    Next j
    Set qt = tabla.QueryTable
    If qt Is Nothing Then Err.Raise vbObjectError + 2, , "La tabla no tiene conexion SQL. No se enviaron datos."
    Application.StatusBar = "Actualizando la consulta SQL. Mantente conectado a la red BIA..."
    ' Foreground refresh: failure stops the upload, without using cached data.
    exito = qt.Refresh(BackgroundQuery:=False)
    If Not exito Then Err.Raise vbObjectError + 3, , "Se cancelo la actualizacion SQL. No se enviaron datos."
    If qt.Refreshing Then Err.Raise vbObjectError + 4, , "La consulta sigue actualizandose. Espera a que termine."
    If tabla.DataBodyRange Is Nothing Then Err.Raise vbObjectError + 5, , "La consulta no devolvio registros."
    If tabla.ListRows.Count > 20000 Then Err.Raise vbObjectError + 6, , "La carga supera 20,000 registros."
    filas = tabla.DataBodyRange.Value2
    ReDim rowJson(1 To UBound(filas, 1))
    ReDim cellJson(0 To UBound(nombres))
    For i = 1 To UBound(filas, 1)
        For j = 0 To UBound(nombres)
            valor = filas(i, campos(j))
            If IsError(valor) Then Err.Raise vbObjectError + 7, , "Fila " & i & ": hay un error de Excel en " & nombres(j)
            Select Case CStr(nombres(j))
                Case "Bodega"
                    If Not IsNumeric(valor) Then Err.Raise vbObjectError + 8, , "Fila " & i & ": Bodega no valida."
                    If CDbl(valor) <> Fix(CDbl(valor)) Or CDbl(valor) < 0 Or CDbl(valor) > 999 Then Err.Raise vbObjectError + 8, , "Fila " & i & ": Bodega no valida."
                    cellJson(j) = JString(CStr(nombres(j))) & ":" & JString(Format$(CLng(valor), "000"))
                Case "Fecha"
                    cellJson(j) = JString(CStr(nombres(j))) & ":" & JString(FechaISO(valor))
                Case "CostoActual", "Cantidades", "Masterpack", "ExistenciaCajasFardos", "VentasCajasFardos", "LbReales", "Libras"
                    If Len(Trim$(CStr(valor))) = 0 Then
                        cellJson(j) = JString(CStr(nombres(j))) & ":null"
                    Else
                        If Not IsNumeric(valor) Then Err.Raise vbObjectError + 9, , "Fila " & i & ": valor numerico no valido en " & nombres(j)
                        cellJson(j) = JString(CStr(nombres(j))) & ":" & Replace(CStr(CDec(valor)), Application.International(xlDecimalSeparator), ".")
                    End If
                Case Else
                    cellJson(j) = JString(CStr(nombres(j))) & ":" & JString(CStr(valor))
            End Select
        Next j
        rowJson(i) = "{" & Join(cellJson, ",") & "}"
    Next i
    Application.StatusBar = False
    ThisWorkbook.FollowHyperlink Address:=WEB
    codigo = LCase$(Trim$(InputBox("La consulta termino. En la pagina web genera un codigo temporal y pegalo aqui. No ingreses tu contrasena.", "Enviar a Inventarios")))
    If Len(codigo) = 0 Then GoTo Salir
    If Len(codigo) <> 64 Or codigo Like "*[!0-9a-f]*" Then Err.Raise vbObjectError + 10, , "Codigo temporal no valido."
    cuerpo = "{""p_codigo"":" & JString(codigo) & ",""p_registros"":[" & Join(rowJson, ",") & "]}"
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.SetTimeouts 15000, 15000, 30000, 120000
    http.Open "POST", ENDPOINT, False
    http.SetRequestHeader "Content-Type", "application/json; charset=utf-8"
    http.SetRequestHeader "apikey", PUBLIC_KEY
    http.SetRequestHeader "Authorization", "Bearer " & PUBLIC_KEY
    Application.StatusBar = "Enviando carga pendiente a Supabase..."
    http.Send UTF8(cuerpo)
    respuesta = http.ResponseText
    codigo = "": cuerpo = ""
    If http.Status < 200 Or http.Status >= 300 Then Err.Raise vbObjectError + 11, , "Supabase rechazo el envio (HTTP " & http.Status & "). " & Left$(respuesta, 800)
    MsgBox "Carga recibida. Vuelve a la web, pulsa Actualizar cargas, valida el resumen y confirma la importacion. Todavia no se han reemplazado existencias.", vbInformation, "Inventarios BIA"
Salir:
    Application.StatusBar = False
    codigo = "": cuerpo = ""
    Enviando = False
    Exit Sub
Fallo:
    MsgBox "No se completo el envio: " & Err.Description & vbCrLf & "Si hubo un corte de conexion, revisa Actualizar cargas en la web antes de volver a enviar.", vbExclamation, "Inventarios BIA"
    Resume Salir
End Sub

Private Function FechaISO(ByVal v As Variant) As String
    Dim s As String, d As Date
    If IsNumeric(v) And VarType(v) <> vbString Then
        If ThisWorkbook.Date1904 Then
            d = DateSerial(1904, 1, 1) + CDbl(v)
        Else
            d = DateSerial(1899, 12, 30) + CDbl(v)
        End If
        FechaISO = Format$(d, "yyyy-mm-dd")
    Else
        s = Trim$(CStr(v))
        If Len(s) <> 10 Or Not s Like "####-##-##" Then Err.Raise vbObjectError + 12, , "Fecha debe estar en formato AAAA-MM-DD o ser una fecha de Excel."
        d = DateSerial(CInt(Left$(s, 4)), CInt(Mid$(s, 6, 2)), CInt(Right$(s, 2)))
        If Format$(d, "yyyy-mm-dd") <> s Then Err.Raise vbObjectError + 13, , "Fecha no valida."
        FechaISO = s
    End If
End Function

Private Function JString(ByVal s As String) As String
    Dim i As Long, u As Long, c As String, salida As String
    For i = 1 To Len(s)
        c = Mid$(s, i, 1): u = AscW(c)
        Select Case u
            Case 34: salida = salida & "\"""
            Case 92: salida = salida & "\\"
            Case 0 To 31: salida = salida & "\u" & Right$("0000" & Hex$(u), 4)
            Case Else: salida = salida & c
        End Select
    Next i
    JString = """" & salida & """"
End Function

Private Function UTF8(ByVal s As String) As Variant
    Dim stream As Object
    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 2: stream.Charset = "utf-8": stream.Open
    stream.WriteText s
    stream.Position = 0: stream.Type = 1: stream.Position = 3
    UTF8 = stream.Read
    stream.Close
End Function
