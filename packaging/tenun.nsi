Unicode true
Name "Tenun"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Tenun"
RequestExecutionLevel user

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File /oname=tenun.exe "${EXE}"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; tambahkan INSTDIR ke PATH pengguna (HKCU, tanpa admin)
  ReadRegStr $0 HKCU "Environment" "Path"
  StrCmp $0 "" 0 +3
    WriteRegExpandStr HKCU "Environment" "Path" "$INSTDIR"
    Goto pathdone
  WriteRegExpandStr HKCU "Environment" "Path" "$0;$INSTDIR"
  pathdone:
  SendMessage 0xFFFF 0x1A 0 "STR:Environment" /TIMEOUT=5000

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun" "DisplayName" "Tenun"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun" "UninstallString" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\tenun.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun"
SectionEnd
