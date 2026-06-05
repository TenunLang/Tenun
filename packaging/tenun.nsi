Unicode true
!include "StrFunc.nsh"
!include "LogicLib.nsh"
${StrStr}
${UnStrRep}

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

  ; Tambahkan INSTDIR ke PATH pengguna (HKCU, tanpa admin) bila belum ada.
  ReadRegStr $0 HKCU "Environment" "Path"
  ${StrStr} $1 "$0" "$INSTDIR"
  ${If} $1 == ""
    ${If} $0 == ""
      WriteRegExpandStr HKCU "Environment" "Path" "$INSTDIR"
    ${Else}
      WriteRegExpandStr HKCU "Environment" "Path" "$0;$INSTDIR"
    ${EndIf}
    ; Beritahu sistem agar PATH baru langsung dipakai proses baru.
    SendMessage 0xFFFF 0x1A 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun" "DisplayName" "Tenun"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun" "DisplayIcon" "$INSTDIR\tenun.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun" "UninstallString" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\tenun.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  ; Hapus INSTDIR dari PATH pengguna.
  ReadRegStr $0 HKCU "Environment" "Path"
  ${UnStrRep} $0 "$0" ";$INSTDIR" ""
  ${UnStrRep} $0 "$0" "$INSTDIR;" ""
  ${UnStrRep} $0 "$0" "$INSTDIR" ""
  WriteRegExpandStr HKCU "Environment" "Path" "$0"
  SendMessage 0xFFFF 0x1A 0 "STR:Environment" /TIMEOUT=5000

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Tenun"
SectionEnd
