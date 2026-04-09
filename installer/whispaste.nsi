; WhisPaste NSIS Installer Script (Flutter)
; Requires NSIS 3.x with Modern UI 2
;
; Build:
;   makensis.exe /DPRODUCT_VERSION=1.2.0 /DPRODUCT_VERSION_NUMERIC=1.2.0.0 whispaste.nsi

!include "MUI2.nsh"
!include "FileFunc.nsh"

; --- General ---
!define PRODUCT_NAME "WhisPaste"
!define PRODUCT_PUBLISHER "Silvio Lindstedt"
!define PRODUCT_WEB_SITE "https://whispaste.de"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_AUTORUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

; Version injected via /DPRODUCT_VERSION= at build time
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.0.0"
!endif

; Numeric version for Windows file properties (X.X.X.X format)
!ifndef PRODUCT_VERSION_NUMERIC
  !define PRODUCT_VERSION_NUMERIC "0.0.0.0"
!endif

; Flutter build output directory — override with /DBUILD_DIR= if needed
!ifndef BUILD_DIR
  !define BUILD_DIR "..\build\windows\x64\runner\Release"
!endif

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "WhisPaste-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\${PRODUCT_NAME}"
InstallDirRegKey HKCU "${PRODUCT_UNINST_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Unicode True

; --- Version Information (shown in file properties) ---
VIProductVersion "${PRODUCT_VERSION_NUMERIC}"
VIFileVersion "${PRODUCT_VERSION_NUMERIC}"
VIAddVersionKey /LANG=0 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=0 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=0 "LegalCopyright" "MIT License — ${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=0 "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey /LANG=0 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=0 "ProductVersion" "${PRODUCT_VERSION}"

; --- Interface Settings ---
!define MUI_ABORTWARNING
!define MUI_ICON "..\resources\app.ico"
!define MUI_UNICON "..\resources\app.ico"

; Brand bitmaps — WhisPaste navy/cyan design system
; Welcome/Finish sidebar (164×314): navy gradient + icon + tagline
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "welcome.bmp"
; Header logo (150×57): navy gradient + icon, right-aligned
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!define MUI_HEADERIMAGE_UNBITMAP "header.bmp"

; Branded welcome page text
!define MUI_WELCOMEPAGE_TITLE "$(WELCOME_TITLE)"
!define MUI_WELCOMEPAGE_TEXT "$(WELCOME_TEXT)"

; Branded finish page text
!define MUI_FINISHPAGE_TITLE "$(FINISH_TITLE)"
!define MUI_FINISHPAGE_TEXT "$(FINISH_TEXT)"

; Remember language selection across reinstalls
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "Software\${PRODUCT_NAME}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"

; --- Pages ---
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\whispaste.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(FINISH_RUN)"
!define MUI_FINISHPAGE_LINK "$(FINISH_LINK)"
!define MUI_FINISHPAGE_LINK_LOCATION "${PRODUCT_WEB_SITE}"
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; --- Languages ---
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "German"

; --- Localized Strings ---

; Welcome page
LangString WELCOME_TITLE ${LANG_ENGLISH} "Welcome to WhisPaste ${PRODUCT_VERSION}"
LangString WELCOME_TITLE ${LANG_GERMAN} "Willkommen bei WhisPaste ${PRODUCT_VERSION}"
LangString WELCOME_TEXT ${LANG_ENGLISH} "This will install WhisPaste — AI-powered dictation for your desktop.$\n$\nDictate anywhere, paste everywhere.$\n$\nClick Next to continue."
LangString WELCOME_TEXT ${LANG_GERMAN} "WhisPaste wird jetzt installiert — KI-gest${U+00FC}tzte Diktierfunktion f${U+00FC}r Ihren Desktop.$\n$\n${U+00DC}berall diktieren, ${U+00FC}berall einf${U+00FC}gen.$\n$\nKlicken Sie auf Weiter, um fortzufahren."

; Section names
LangString SEC_CORE_NAME ${LANG_ENGLISH} "WhisPaste (required)"
LangString SEC_CORE_NAME ${LANG_GERMAN} "WhisPaste (erforderlich)"
LangString SEC_DESKTOP_NAME ${LANG_ENGLISH} "Desktop Shortcut"
LangString SEC_DESKTOP_NAME ${LANG_GERMAN} "Desktop-Verkn${U+00FC}pfung"

; Section descriptions
LangString SEC_CORE_DESC ${LANG_ENGLISH} "Core application files (required)."
LangString SEC_CORE_DESC ${LANG_GERMAN} "Kerndateien der Anwendung (erforderlich)."
LangString SEC_DESKTOP_DESC ${LANG_ENGLISH} "Create a shortcut on the desktop."
LangString SEC_DESKTOP_DESC ${LANG_GERMAN} "Eine Verkn${U+00FC}pfung auf dem Desktop erstellen."

; Finish page
LangString FINISH_TITLE ${LANG_ENGLISH} "Installation Complete"
LangString FINISH_TITLE ${LANG_GERMAN} "Installation abgeschlossen"
LangString FINISH_TEXT ${LANG_ENGLISH} "WhisPaste has been installed on your computer.$\n$\nClick Finish to close this wizard."
LangString FINISH_TEXT ${LANG_GERMAN} "WhisPaste wurde auf Ihrem Computer installiert.$\n$\nKlicken Sie auf Fertig stellen, um den Assistenten zu schlie${U+00DF}en."
LangString FINISH_RUN ${LANG_ENGLISH} "Start WhisPaste"
LangString FINISH_RUN ${LANG_GERMAN} "WhisPaste starten"
LangString FINISH_LINK ${LANG_ENGLISH} "Visit whispaste.de"
LangString FINISH_LINK ${LANG_GERMAN} "whispaste.de besuchen"

; Uninstaller
LangString UNINST_REMOVE_DATA ${LANG_ENGLISH} "Also remove downloaded models and history?$\n(Located in: $APPDATA\${PRODUCT_NAME})$\n$\nNote: API keys stored in Windows Credential Manager are not removed."
LangString UNINST_REMOVE_DATA ${LANG_GERMAN} "Auch heruntergeladene Modelle und den Verlauf entfernen?$\n(Pfad: $APPDATA\${PRODUCT_NAME})$\n$\nHinweis: API-Schl${U+00FC}ssel in der Windows-Anmeldeinformationsverwaltung werden nicht entfernt."

; --- Init Function (language selection dialog) ---
Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

; --- Sections ---

Section "$(SEC_CORE_NAME)" SecCore
  SectionIn RO

  ; Close running app instance (required to replace files)
  nsExec::ExecToLog 'taskkill /F /IM whispaste.exe'
  Sleep 2000

  ; Install entire Flutter build output (exe, DLLs, data/, resources/)
  SetOutPath "$INSTDIR"
  File /r "${BUILD_DIR}\*"

  ; Bundle license
  File "..\LICENSE"

  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\whispaste.exe" "" "$INSTDIR\whispaste.exe" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  ; Write uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Add/Remove Programs registry (per-user)
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\whispaste.exe"
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "NoRepair" 1

  ; Write install source marker (used by app to detect deploy channel)
  WriteRegStr HKCU "Software\${PRODUCT_NAME}" "InstallSource" "installer"

  ; Compute and store installed size
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${PRODUCT_UNINST_KEY}" "EstimatedSize" $0
SectionEnd

Section "$(SEC_DESKTOP_NAME)" SecDesktop
  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\whispaste.exe" "" "$INSTDIR\whispaste.exe" 0
SectionEnd

; --- Section Descriptions ---
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} "$(SEC_CORE_DESC)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "$(SEC_DESKTOP_DESC)"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; --- Uninstaller ---

Function un.onInit
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

Section "Uninstall"
  ; Close running app instance
  nsExec::ExecToLog 'taskkill /F /IM whispaste.exe'
  Sleep 2000

  ; Remove Flutter runtime directories
  RMDir /r "$INSTDIR\data"
  RMDir /r "$INSTDIR\resources"

  ; Remove top-level files (DLLs, exe, json, license)
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.exe"
  Delete "$INSTDIR\*.json"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\uninstall.exe"

  ; Remove shortcuts
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"

  ; Remove registry entries
  DeleteRegKey HKCU "${PRODUCT_UNINST_KEY}"
  DeleteRegValue HKCU "${PRODUCT_AUTORUN_KEY}" "${PRODUCT_NAME}"
  DeleteRegKey HKCU "Software\${PRODUCT_NAME}"

  ; Ask user whether to remove app data (models, history)
  ; Also kill AI subprocesses if running from app data directory
  MessageBox MB_YESNO|MB_ICONQUESTION "$(UNINST_REMOVE_DATA)" IDNO skip_data_removal
    nsExec::ExecToLog 'taskkill /F /IM whisper-server.exe'
    nsExec::ExecToLog 'taskkill /F /IM llama-server.exe'
    Sleep 2000
    RMDir /r "$APPDATA\${PRODUCT_NAME}"
  skip_data_removal:

  ; Remove install directory (only if empty after cleanup)
  RMDir "$INSTDIR"
SectionEnd
