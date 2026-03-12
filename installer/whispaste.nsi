; WhisPaste NSIS Installer Script
; Requires NSIS 3.x with Modern UI 2

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

; --- General ---
!define PRODUCT_NAME "WhisPaste"
!define PRODUCT_PUBLISHER "Silvio Lindstedt"
!define PRODUCT_WEB_SITE "https://whispaste.com"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_AUTORUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

; Version is injected via /DPRODUCT_VERSION= at build time (may contain prerelease suffix)
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.0.0"
!endif

; Numeric version for Windows file properties (X.X.X.X format, no prerelease suffixes).
; Injected by CI via /DPRODUCT_VERSION_NUMERIC=. Safe default for local dev builds.
!ifndef PRODUCT_VERSION_NUMERIC
  !define PRODUCT_VERSION_NUMERIC "0.0.0.0"
!endif

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "WhisPaste-${PRODUCT_VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
InstallDirRegKey HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
Unicode True

; --- Version Information (shown in file properties) ---
VIProductVersion "${PRODUCT_VERSION_NUMERIC}"
VIFileVersion "${PRODUCT_VERSION_NUMERIC}"
VIAddVersionKey /LANG=0 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=0 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=0 "LegalCopyright" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=0 "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey /LANG=0 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=0 "ProductVersion" "${PRODUCT_VERSION}"

; --- Interface Settings ---
!define MUI_ABORTWARNING
!define MUI_ICON "..\resources\app.ico"
!define MUI_UNICON "..\resources\app.ico"

; Remember language selection across reinstalls
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "Software\${PRODUCT_NAME}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"

; --- Pages ---
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\whispaste.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(FINISH_RUN)"
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; --- Languages ---
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "German"

; --- Localized Strings ---

; Section names
LangString SEC_CORE_NAME ${LANG_ENGLISH} "WhisPaste (required)"
LangString SEC_CORE_NAME ${LANG_GERMAN} "WhisPaste (erforderlich)"
LangString SEC_DESKTOP_NAME ${LANG_ENGLISH} "Desktop Shortcut"
LangString SEC_DESKTOP_NAME ${LANG_GERMAN} "Desktop-Verkn${U+00FC}pfung"
LangString SEC_AUTOSTART_NAME ${LANG_ENGLISH} "Start with Windows"
LangString SEC_AUTOSTART_NAME ${LANG_GERMAN} "Mit Windows starten"

; Section descriptions
LangString SEC_CORE_DESC ${LANG_ENGLISH} "Core application files (required)."
LangString SEC_CORE_DESC ${LANG_GERMAN} "Kerndateien der Anwendung (erforderlich)."
LangString SEC_DESKTOP_DESC ${LANG_ENGLISH} "Create a shortcut on the desktop."
LangString SEC_DESKTOP_DESC ${LANG_GERMAN} "Eine Verkn${U+00FC}pfung auf dem Desktop erstellen."
LangString SEC_AUTOSTART_DESC ${LANG_ENGLISH} "Start WhisPaste automatically when Windows starts."
LangString SEC_AUTOSTART_DESC ${LANG_GERMAN} "WhisPaste beim Systemstart automatisch ausf${U+00FC}hren."

; Finish page
LangString FINISH_RUN ${LANG_ENGLISH} "Start WhisPaste"
LangString FINISH_RUN ${LANG_GERMAN} "WhisPaste starten"
LangString UNINST_REMOVE_DATA ${LANG_ENGLISH} "Also remove all settings, models, and history?$\n(Located in: $APPDATA\${PRODUCT_NAME})"
LangString UNINST_REMOVE_DATA ${LANG_GERMAN} "Auch alle Einstellungen, Modelle und den Verlauf entfernen?$\n(Pfad: $APPDATA\${PRODUCT_NAME})"

; --- Init Function (language selection dialog) ---
Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

; --- Sections ---

Section "$(SEC_CORE_NAME)" SecCore
  SectionIn RO

  ; Close running instance and subprocesses, wait for processes to exit
  nsExec::ExecToLog 'taskkill /F /IM whisper-server.exe'
  nsExec::ExecToLog 'taskkill /F /IM llama-server.exe'
  nsExec::ExecToLog 'taskkill /F /IM whispaste.exe'
  Sleep 1000

  SetOutPath "$INSTDIR"
  File "..\whispaste.exe"
  File "..\LICENSE"

  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\whispaste.exe" "" "$INSTDIR\whispaste.exe" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  ; Write uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Add/Remove Programs registry
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\whispaste.exe"
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoRepair" 1

  ; Compute installed size
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "EstimatedSize" $0
SectionEnd

Section "$(SEC_DESKTOP_NAME)" SecDesktop
  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\whispaste.exe" "" "$INSTDIR\whispaste.exe" 0
SectionEnd

Section "$(SEC_AUTOSTART_NAME)" SecAutostart
  WriteRegStr HKCU "${PRODUCT_AUTORUN_KEY}" "${PRODUCT_NAME}" '"$INSTDIR\whispaste.exe"'
SectionEnd

; --- Section Descriptions ---
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} "$(SEC_CORE_DESC)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "$(SEC_DESKTOP_DESC)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecAutostart} "$(SEC_AUTOSTART_DESC)"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; --- Uninstaller ---

Function un.onInit
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

Section "Uninstall"
  ; Close running instance and subprocesses, wait for processes to exit
  nsExec::ExecToLog 'taskkill /F /IM whisper-server.exe'
  nsExec::ExecToLog 'taskkill /F /IM llama-server.exe'
  nsExec::ExecToLog 'taskkill /F /IM whispaste.exe'
  Sleep 1000

  ; Remove files
  Delete "$INSTDIR\whispaste.exe"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\uninstall.exe"

  ; Remove WebView2 user data (EBWebView directory next to exe)
  RMDir /r "$INSTDIR\EBWebView"

  ; Remove shortcuts
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"

  ; Remove AUMID Start Menu shortcut used for toast notifications
  Delete "$APPDATA\Microsoft\Windows\Start Menu\Programs\${PRODUCT_NAME}.lnk"

  ; Remove registry entries
  DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
  DeleteRegValue HKCU "${PRODUCT_AUTORUN_KEY}" "${PRODUCT_NAME}"
  DeleteRegKey HKCU "Software\${PRODUCT_NAME}"

  ; Ask user whether to remove app data (settings, models, history)
  MessageBox MB_YESNO|MB_ICONQUESTION "$(UNINST_REMOVE_DATA)" IDNO skip_data_removal
    RMDir /r "$APPDATA\${PRODUCT_NAME}"
  skip_data_removal:

  ; Remove install directory (only if empty)
  RMDir "$INSTDIR"
SectionEnd
