; NSIS Installer Script for Clinical DBS Annotator
; This script creates a Windows installer with proper installation, shortcuts, and uninstaller
;
; Requirements: NSIS (Nullsoft Scriptable Install System)
; Download from: https://nsis.sourceforge.io/

!define APP_NAME "Clinical DBS Annotator"
!define APP_VERSION "0.1.0"
!define APP_PUBLISHER "BML"
!define APP_EXE "ClinicalDBSAnnot_v0_1.exe"
!define INSTALL_DIR "$PROGRAMFILES\${APP_PUBLISHER}\${APP_NAME}"

; Includes
!include "MUI2.nsh"

; General settings
Name "${APP_NAME}"
OutFile "..\dist\ClinicalDBSAnnot_Installer_v0.1.exe"
InstallDir "${INSTALL_DIR}"
InstallDirRegKey HKCU "Software\${APP_PUBLISHER}\${APP_NAME}" "InstallDir"
RequestExecutionLevel admin

; MUI Settings
!define MUI_ABORTWARNING
!define MUI_ICON "..\icons\logoneutral.ico"
!define MUI_UNICON "..\icons\logoneutral.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "..\icons\logoneutral.png"

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "English"

; Installer Section
Section "Install"
    ; Set output path
    SetOutPath "$INSTDIR"

    ; Copy executable and resources
    File "..\dist\${APP_EXE}"
    File "..\icons\logoneutral.ico"
    File "..\icons\logoneutral.png"
    File "..\style.qss"

    ; Create start menu shortcuts
    CreateDirectory "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}"
    CreateShortcut "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\logoneutral.ico"
    CreateShortcut "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

    ; Create desktop shortcut
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\logoneutral.ico"

    ; Write uninstaller
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Write registry keys for Add/Remove Programs
    WriteRegStr HKCU "Software\${APP_PUBLISHER}\${APP_NAME}" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayIcon" "$INSTDIR\logoneutral.ico"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "${APP_PUBLISHER}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoRepair" 1

SectionEnd

; Uninstaller Section
Section "Uninstall"
    ; Remove files
    Delete "$INSTDIR\${APP_EXE}"
    Delete "$INSTDIR\logoneutral.ico"
    Delete "$INSTDIR\logoneutral.png"
    Delete "$INSTDIR\style.qss"
    Delete "$INSTDIR\Uninstall.exe"

    ; Remove shortcuts
    Delete "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}\Uninstall.lnk"
    RMDir "$SMPROGRAMS\${APP_PUBLISHER}\${APP_NAME}"
    RMDir "$SMPROGRAMS\${APP_PUBLISHER}"
    Delete "$DESKTOP\${APP_NAME}.lnk"

    ; Remove directories
    RMDir "$INSTDIR"

    ; Remove registry keys
    DeleteRegKey HKCU "Software\${APP_PUBLISHER}\${APP_NAME}"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

SectionEnd
