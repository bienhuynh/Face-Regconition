Attribute VB_Name = "Module1"
Option Base 0
Option Explicit


Sub Main()
    If (FSDKVB_ActivateLibrary("fhPKopJVjHpnsV6/aumzjOvApHU7gnFduuovOu1DRngQEEevUnlpLfSAhNIhLVjzPYYbhmrz36x9Xnn1AZ/8HOcgXtIaZxOxZzNXNwS3ezLiwFwZGhY9w3S+beKvuIC8DhosdzRYCSGx4H9hC1A+jAHqTPjBTr42nKiOZ+y3H70=") <> FSDKE_OK) Then
        MsgBox "Please run the License Key Wizard (Start - Luxand - FaceSDK - License Key Wizard)", vbOKOnly, "Error activating FaceSDK"
        Exit Sub
    End If
    
    FSDKVB_Initialize ""
 
    Dim frmMain As New Form1
    frmMain.Show
  
  
End Sub
