#Requires -Version 5.1
<#
.SYNOPSIS
    WhisPaste Sprachdienst-Diagnose fuer Windows (EXE- und Microsoft-Store-Build).

.DESCRIPTION
    Liest die komplette Laufzeitumgebung des lokalen Sprachdienstes
    (whisper-server.exe) aus und erstellt einen Klartext-Report. Schwerpunkt:
    herausfinden, *welche* DLL beim Start nicht aufgeloest werden kann
    (Windows-Fehler 0xC0000135 / STATUS_DLL_NOT_FOUND) bzw. warum der
    Sprachdienst nicht laeuft.

    Findet beide Installationsvarianten gleichwertig:
      * EXE-Build (NSIS-Installer)      -> Daten unter %APPDATA%\WhisPaste
      * Microsoft-Store-Build (MSIX)    -> Daten im virtualisierten
        Paket-Container
        %LOCALAPPDATA%\Packages\<PaketID>\LocalCache\Roaming\WhisPaste

    Erfasst: installierte WhisPaste-Pakete, alle Daten-Verzeichnisse, die
    whisper-server-Binary samt PE-Import-Analyse (ohne externe Tools),
    Visual-C++-Runtime, Hardware/GPU-Treiber, die App-Logdatei
    (whispaste.log) und einen optionalen Start-Test mit Exit-Code.

    Reines Lesen - veraendert nichts, braucht keine Adminrechte, schreibt
    nur eine Report-Datei.

.PARAMETER ServerPath
    Voller Pfad zu whisper-server.exe. Ohne Angabe wird automatisch in allen
    bekannten Datenverzeichnissen beider Varianten gesucht.

.PARAMETER OutFile
    Zielpfad fuer den Report. Standard: Zeitstempel-Datei auf dem Desktop.

.PARAMETER NoRunTest
    Ueberspringt den Start-Test (Binary wird dann nicht kurz ausgefuehrt).

.PARAMETER LogTail
    Anzahl der Logzeilen, die ans Ende des Reports kopiert werden (Standard 120).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\whispaste-diagnose.ps1

.NOTES
    Weitergabe: Diese .ps1 kann unveraendert an Betroffene geschickt werden.
    Ausfuehren per Rechtsklick > "Mit PowerShell ausfuehren" oder im Terminal:
        powershell -ExecutionPolicy Bypass -File whispaste-diagnose.ps1
    Den erzeugten Report (.txt auf dem Desktop) zuruecksenden.
#>
[CmdletBinding()]
param(
    [string]$ServerPath,
    [string]$OutFile,
    [switch]$NoRunTest,
    [int]$LogTail = 120,
    # Unterdrueckt die Abschluss-Pause am Ende (fuer CI / automatisierte Laeufe).
    # Interaktiv (Doppelklick / .exe) bleibt das Fenster sonst offen, damit der
    # Nutzer die Abschluss-Anweisung lesen kann.
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# MSIX-Paket-Identitaet (aus pubspec.yaml msix_config.identity_name). Der
# Container-Ordner heisst "<IdentityName>_<PublisherHash>"; wir globben ueber
# den stabilen Praefix.
$script:PackageIdentityPrefix = '12342SilvioLindstedt.WhisPaste'

# Report-Zeilen sammeln; am Ende in Datei + Konsole ausgeben (kein Write-Host).
$script:Report = [System.Collections.Generic.List[string]]::new()

function Add-Line {
    param([string]$Text = '')
    $script:Report.Add($Text)
}

function Add-Section {
    param([Parameter(Mandatory)][string]$Title)
    Add-Line ''
    Add-Line ('=' * 72)
    Add-Line ("  $Title")
    Add-Line ('=' * 72)
}

# -------------------------------------------------------------------------
# PE-Parser (reines PowerShell, keine externen Tools)
# -------------------------------------------------------------------------

function Get-UInt16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-UInt32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-AsciiZ {
    param([byte[]]$Bytes, [int]$Offset)
    $sb = [System.Text.StringBuilder]::new()
    $i = $Offset
    while ($i -lt $Bytes.Length -and $Bytes[$i] -ne 0) {
        [void]$sb.Append([char]$Bytes[$i])
        $i++
    }
    return $sb.ToString()
}

function ConvertTo-FileOffset {
    param([Parameter(Mandatory)]$Sections, [Parameter(Mandatory)][uint32]$Rva)
    foreach ($s in $Sections) {
        $span = [Math]::Max($s.VSize, $s.RawSz)
        if ($Rva -ge $s.VAddr -and $Rva -lt ($s.VAddr + $span)) {
            return [int64]($Rva - $s.VAddr + $s.RawPtr)
        }
    }
    return -1
}

# Liest Architektur und importierte Modulnamen (normale + Delay-Imports)
# direkt aus dem PE-Header der Datei.
function Get-PeInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $info = [pscustomobject]@{
        Path         = $Path
        Architecture = 'unbekannt'
        Imports      = [System.Collections.Generic.List[string]]::new()
        Error        = $null
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
    } catch {
        $info.Error = "Lesefehler: $($_.Exception.Message)"
        return $info
    }

    if ($bytes.Length -lt 64) { $info.Error = 'Datei zu klein'; return $info }
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { $info.Error = 'kein MZ/DOS-Header'; return $info }

    $peOff = [int](Get-UInt32 -Bytes $bytes -Offset 0x3C)
    if ($peOff -le 0 -or ($peOff + 24) -ge $bytes.Length) { $info.Error = 'PE-Offset ungueltig'; return $info }
    if ($bytes[$peOff] -ne 0x50 -or $bytes[$peOff + 1] -ne 0x45) { $info.Error = 'keine PE-Signatur'; return $info }

    $machine = Get-UInt16 -Bytes $bytes -Offset ($peOff + 4)
    $info.Architecture = switch ($machine) {
        0x8664 { 'x64' }
        0x014C { 'x86' }
        0xAA64 { 'arm64' }
        default { ('0x{0:X4}' -f $machine) }
    }

    $numSections = Get-UInt16 -Bytes $bytes -Offset ($peOff + 6)
    $optSize     = Get-UInt16 -Bytes $bytes -Offset ($peOff + 20)
    $optStart    = $peOff + 24
    if (($optStart + 2) -ge $bytes.Length) { $info.Error = 'Optional-Header fehlt'; return $info }

    $magic   = Get-UInt16 -Bytes $bytes -Offset $optStart
    $ddStart = if ($magic -eq 0x20B) { $optStart + 112 } else { $optStart + 96 }  # PE32+ vs PE32

    # Section-Tabelle einlesen (fuer RVA->Dateioffset-Umrechnung).
    $secStart = $optStart + $optSize
    $sections = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $numSections; $i++) {
        $s = $secStart + ($i * 40)
        if (($s + 40) -gt $bytes.Length) { break }
        $sections.Add([pscustomobject]@{
            VAddr  = Get-UInt32 -Bytes $bytes -Offset ($s + 12)
            VSize  = Get-UInt32 -Bytes $bytes -Offset ($s + 8)
            RawPtr = Get-UInt32 -Bytes $bytes -Offset ($s + 20)
            RawSz  = Get-UInt32 -Bytes $bytes -Offset ($s + 16)
        })
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # --- Normale Import-Tabelle (Data-Directory-Index 1) ---
    if (($ddStart + 16) -le $bytes.Length) {
        $importRva = Get-UInt32 -Bytes $bytes -Offset ($ddStart + 8)
        if ($importRva -ne 0) {
            $impOff = ConvertTo-FileOffset -Sections $sections -Rva $importRva
            $guard = 0
            while ($impOff -ge 0 -and ($impOff + 20) -le $bytes.Length -and $guard -lt 4096) {
                $origThunk  = Get-UInt32 -Bytes $bytes -Offset ([int]$impOff)
                $nameRva    = Get-UInt32 -Bytes $bytes -Offset ([int]$impOff + 12)
                $firstThunk = Get-UInt32 -Bytes $bytes -Offset ([int]$impOff + 16)
                if ($nameRva -eq 0 -and $origThunk -eq 0 -and $firstThunk -eq 0) { break }
                if ($nameRva -ne 0) {
                    $nameOff = ConvertTo-FileOffset -Sections $sections -Rva $nameRva
                    if ($nameOff -ge 0) {
                        $dll = Read-AsciiZ -Bytes $bytes -Offset ([int]$nameOff)
                        if ($dll -and $seen.Add($dll)) { $info.Imports.Add($dll) }
                    }
                }
                $impOff += 20
                $guard++
            }
        }
    }

    # --- Delay-Import-Tabelle (Data-Directory-Index 13, je 32 Byte) ---
    $delayDd = $ddStart + (8 * 13)
    if (($delayDd + 8) -le $bytes.Length) {
        $delayRva = Get-UInt32 -Bytes $bytes -Offset $delayDd
        if ($delayRva -ne 0) {
            $dOff = ConvertTo-FileOffset -Sections $sections -Rva $delayRva
            $guard = 0
            while ($dOff -ge 0 -and ($dOff + 32) -le $bytes.Length -and $guard -lt 4096) {
                $attrs   = Get-UInt32 -Bytes $bytes -Offset ([int]$dOff)
                $nameRva = Get-UInt32 -Bytes $bytes -Offset ([int]$dOff + 4)
                if ($nameRva -eq 0) { break }
                # Bit 0 gesetzt => RVA-basiert (modernes Format).
                if (($attrs -band 1) -eq 1) {
                    $nameOff = ConvertTo-FileOffset -Sections $sections -Rva $nameRva
                    if ($nameOff -ge 0) {
                        $dll = Read-AsciiZ -Bytes $bytes -Offset ([int]$nameOff)
                        if ($dll -and $seen.Add($dll)) { $info.Imports.Add("$dll (delay)") }
                    }
                }
                $dOff += 32
                $guard++
            }
        }
    }

    return $info
}

# -------------------------------------------------------------------------
# DLL-Aufloesung gegen die Windows-Suchreihenfolge
# -------------------------------------------------------------------------

function Resolve-DllPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$LocalDir,
        [string]$Architecture = 'x64'
    )

    $lower = $Name.ToLowerInvariant()
    if ($lower -like 'api-ms-win-*' -or $lower -like 'ext-ms-*') {
        return [pscustomobject]@{ Name = $Name; Status = 'API-Set'; Path = '(virtuell)' }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add((Join-Path $LocalDir $Name))
    if ($env:WINDIR) {
        $sys = if ($Architecture -eq 'x86') { 'SysWOW64' } else { 'System32' }
        $candidates.Add((Join-Path (Join-Path $env:WINDIR $sys) $Name))
        $candidates.Add((Join-Path $env:WINDIR $Name))
    }
    if ($env:PATH) {
        foreach ($p in $env:PATH.Split([IO.Path]::PathSeparator)) {
            if ($p) { $candidates.Add((Join-Path $p $Name)) }
        }
    }

    foreach ($c in $candidates) {
        try {
            if (Test-Path -LiteralPath $c -PathType Leaf) {
                return [pscustomobject]@{ Name = $Name; Status = 'OK'; Path = $c }
            }
        } catch {
            continue
        }
    }
    return [pscustomobject]@{ Name = $Name; Status = 'FEHLT'; Path = $null }
}

# -------------------------------------------------------------------------
# Daten-Verzeichnisse + Installationen finden (EXE + Store gleichwertig)
# -------------------------------------------------------------------------

# Liefert eine Liste der WhisPaste-Daten-Wurzeln beider Varianten, jeweils mit
# Label, Wurzelpfad und abgeleitetem stt-Verzeichnis.
function Get-WhisPasteDataRootList {
    $roots = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-Root([string]$label, [string]$root) {
        if (-not $root) { return }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
        if (-not $seen.Add($root)) { return }
        $roots.Add([pscustomobject]@{
            Label  = $label
            Root   = $root
            SttDir = Join-Path $root 'models\stt'
        })
    }

    # EXE-Build: klassisches Roaming-AppData.
    if ($env:APPDATA) { Add-Root 'EXE (%APPDATA%)' (Join-Path $env:APPDATA 'WhisPaste') }
    # Sicherheitshalber auch lokales AppData.
    if ($env:LOCALAPPDATA) { Add-Root 'EXE (%LOCALAPPDATA%)' (Join-Path $env:LOCALAPPDATA 'WhisPaste') }

    # Store-Build (MSIX): virtualisierter Paket-Container. APPDATA-Schreibzugriffe
    # werden nach LocalCache\Roaming umgeleitet.
    if ($env:LOCALAPPDATA) {
        $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
        if (Test-Path -LiteralPath $pkgRoot -PathType Container) {
            try {
                $pkgDirs = Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter "$($script:PackageIdentityPrefix)_*" -ErrorAction SilentlyContinue
                foreach ($pkg in $pkgDirs) {
                    Add-Root "Store/MSIX LocalCache\Roaming ($($pkg.Name))" (Join-Path $pkg.FullName 'LocalCache\Roaming\WhisPaste')
                    Add-Root "Store/MSIX LocalCache\Local ($($pkg.Name))"   (Join-Path $pkg.FullName 'LocalCache\Local\WhisPaste')
                    Add-Root "Store/MSIX LocalState ($($pkg.Name))"          (Join-Path $pkg.FullName 'LocalState\WhisPaste')
                    Add-Root "Store/MSIX LocalCache\Local (direkt, $($pkg.Name))" (Join-Path $pkg.FullName 'LocalCache\Local')
                }
            } catch {
                Write-Verbose "Store-Paketsuche fehlgeschlagen: $($_.Exception.Message)"
            }
        }
    }

    # Komma-Operator: verhindert, dass PowerShell die (evtl. leere) Liste
    # beim Return zu $null/Skalar entrollt - sonst bricht spaeter `.Count`.
    return , $roots
}

# Beschreibt installierte WhisPaste-Varianten (Store via Appx, EXE via Registry).
function Get-WhisPasteInstallInfo {
    $lines = [System.Collections.Generic.List[string]]::new()

    # Store/MSIX
    try {
        $appx = Get-AppxPackage -Name "*WhisPaste*" -ErrorAction SilentlyContinue
        if ($appx) {
            foreach ($a in $appx) {
                $lines.Add("Store/MSIX: $($a.Name) v$($a.Version)")
                $lines.Add("   PackageFamilyName: $($a.PackageFamilyName)")
                $lines.Add("   InstallLocation  : $($a.InstallLocation)")
            }
        }
    } catch {
        $lines.Add("Store/MSIX: Abfrage nicht moeglich ($($_.Exception.Message))")
    }

    # EXE/NSIS via Registry-Uninstall.
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $uninstallRoots) {
        try {
            $hits = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*WhisPaste*' }
            foreach ($h in $hits) {
                $lines.Add("EXE/Installer: $($h.DisplayName) v$($h.DisplayVersion)")
                if ($h.PSObject.Properties.Name -contains 'InstallLocation' -and $h.InstallLocation) {
                    $lines.Add("   InstallLocation: $($h.InstallLocation)")
                }
            }
        } catch { continue }
    }

    if ($lines.Count -eq 0) { $lines.Add('(keine WhisPaste-Installation erkannt)') }
    return , $lines
}

# Sucht die whisper-server.exe: zuerst in den Standard-stt-Verzeichnissen,
# danach rekursiv unterhalb jeder Daten-Wurzel.
function Find-ServerBinary {
    param([Parameter(Mandatory)]$Roots)
    foreach ($r in $Roots) {
        $candidate = Join-Path $r.SttDir 'whisper-server.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    foreach ($r in $Roots) {
        try {
            $hit = Get-ChildItem -LiteralPath $r.Root -Recurse -File -Filter 'whisper-server.exe' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch { continue }
    }
    return $null
}

# =========================================================================
# Bericht erstellen
# =========================================================================

$now = Get-Date
Add-Line 'WHISPASTE - SPRACHDIENST-DIAGNOSE'
Add-Line ("Erstellt: {0:yyyy-MM-dd HH:mm:ss} ({1})" -f $now, ([System.TimeZoneInfo]::Local.Id))
Add-Line 'Skript-Version: 2.0'

$onWindows = $true
try { if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) { $onWindows = [bool]$IsWindows } } catch { $onWindows = $true }
if (-not $onWindows) {
    Add-Line ''
    Add-Line '!! Hinweis: Dieses Skript ist fuer Windows gedacht. Es laeuft hier'
    Add-Line '   auf einem Nicht-Windows-System; Hardware-/Registry-/Appx-'
    Add-Line '   Abschnitte bleiben leer. Die PE-Analyse funktioniert dennoch.'
}

# --- Abschnitt: System / Hardware ---------------------------------------
Add-Section 'SYSTEM & HARDWARE'
try {
    Add-Line ("Computername : {0}" -f $env:COMPUTERNAME)
    Add-Line ("Benutzer     : {0}" -f $env:USERNAME)
    Add-Line ("Prozessor-Arch (Prozess): {0}" -f $env:PROCESSOR_ARCHITECTURE)
    Add-Line ("PowerShell   : {0}" -f $PSVersionTable.PSVersion)
} catch { Add-Line "  (Umgebungsvariablen nicht lesbar: $($_.Exception.Message))" }

if ($onWindows) {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Add-Line ("Betriebssystem: {0}" -f $os.Caption)
        Add-Line ("Version/Build : {0} (Build {1})" -f $os.Version, $os.BuildNumber)
        Add-Line ("Architektur   : {0}" -f $os.OSArchitecture)
    } catch { Add-Line "  OS-Info nicht lesbar: $($_.Exception.Message)" }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        Add-Line ("CPU           : {0} ({1} Kerne / {2} Threads)" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    } catch { Add-Line "  CPU-Info nicht lesbar: $($_.Exception.Message)" }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ramGb = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        Add-Line ("Arbeitsspeicher: {0} GB" -f $ramGb)
    } catch { Add-Line "  RAM-Info nicht lesbar: $($_.Exception.Message)" }

    Add-Line ''
    Add-Line 'Grafikkarten:'
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
        foreach ($g in $gpus) {
            Add-Line ("  - {0}" -f $g.Name)
            Add-Line ("      Treiber-Version: {0}" -f $g.DriverVersion)
            $dd = $g.DriverDate
            if ($dd) { Add-Line ("      Treiber-Datum  : {0:yyyy-MM-dd}" -f $dd) }
            if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) {
                Add-Line ("      Adapter-RAM    : {0} MB (gemeldet)" -f [Math]::Round($g.AdapterRAM / 1MB))
            }
            Add-Line ("      PNP-ID         : {0}" -f $g.PNPDeviceID)
        }
    } catch { Add-Line "  GPU-Info nicht lesbar: $($_.Exception.Message)" }
}

# --- Abschnitt: Installationen ------------------------------------------
Add-Section 'INSTALLIERTE WHISPASTE-VARIANTEN'
if ($onWindows) {
    foreach ($l in (Get-WhisPasteInstallInfo)) { Add-Line $l }
} else {
    Add-Line '(Windows erforderlich - uebersprungen.)'
}

# --- Daten-Verzeichnisse beider Varianten -------------------------------
$dataRoots = Get-WhisPasteDataRootList
Add-Section 'DATEN-VERZEICHNISSE (EXE + Store)'
if ($dataRoots.Count -eq 0) {
    Add-Line 'Keine WhisPaste-Daten-Verzeichnisse gefunden.'
    Add-Line 'Gesuchte Orte:'
    Add-Line '  EXE   : %APPDATA%\WhisPaste'
    Add-Line ("  Store : %LOCALAPPDATA%\Packages\{0}_*\LocalCache\Roaming\WhisPaste" -f $script:PackageIdentityPrefix)
} else {
    foreach ($r in $dataRoots) {
        Add-Line ''
        Add-Line ("[{0}]" -f $r.Label)
        Add-Line ("  Root  : {0}" -f $r.Root)
        Add-Line ("  stt   : {0}" -f $r.SttDir)
        if (Test-Path -LiteralPath $r.SttDir -PathType Container) {
            $infoJson = Join-Path $r.SttDir '.server-info.json'
            if (Test-Path -LiteralPath $infoJson -PathType Leaf) {
                try {
                    $meta = Get-Content -LiteralPath $infoJson -Raw | ConvertFrom-Json
                    $parts = foreach ($prop in $meta.PSObject.Properties) { "$($prop.Name)=$($prop.Value)" }
                    Add-Line ("  .server-info.json: {0}" -f ($parts -join '  '))
                } catch { Add-Line "  .server-info.json nicht lesbar: $($_.Exception.Message)" }
            } else {
                Add-Line '  .server-info.json: nicht vorhanden'
            }
            Add-Line '  Dateien im stt-Verzeichnis:'
            try {
                $files = Get-ChildItem -LiteralPath $r.SttDir -File -ErrorAction Stop | Sort-Object Name
                if ($files) {
                    foreach ($f in $files) { Add-Line ("    {0,12:N0}  {1}" -f $f.Length, $f.Name) }
                } else {
                    Add-Line '    (leer)'
                }
            } catch { Add-Line "    nicht lesbar: $($_.Exception.Message)" }
        } else {
            Add-Line '  stt-Verzeichnis existiert nicht (Modell noch nicht geladen?).'
        }
    }
}

# --- Abschnitt: Server-Binary -------------------------------------------
Add-Section 'SPRACHDIENST-BINARY (whisper-server.exe)'

if (-not $ServerPath) { $ServerPath = Find-ServerBinary -Roots $dataRoots }

$serverDir = $null
$serverArch = 'x64'
if ($ServerPath -and (Test-Path -LiteralPath $ServerPath -PathType Leaf)) {
    $serverDir = Split-Path -Parent $ServerPath
    $fi = Get-Item -LiteralPath $ServerPath
    Add-Line ("Pfad        : {0}" -f $ServerPath)
    Add-Line ("Groesse     : {0:N0} Bytes" -f $fi.Length)
    Add-Line ("Geaendert   : {0:yyyy-MM-dd HH:mm:ss}" -f $fi.LastWriteTime)
    $pe = Get-PeInfo -Path $ServerPath
    if ($pe.Error) {
        Add-Line ("PE-Analyse  : FEHLER - {0}" -f $pe.Error)
    } else {
        $serverArch = $pe.Architecture
        Add-Line ("Architektur : {0}" -f $pe.Architecture)
    }
} else {
    Add-Line 'whisper-server.exe NICHT gefunden (in keiner Variante).'
    Add-Line 'Moegliche Gruende:'
    Add-Line '  - Sprachmodell wurde noch nie vollstaendig heruntergeladen, ODER'
    Add-Line '  - die Selbstheilung hat die Binary nach einem Fehlstart geloescht'
    Add-Line '    und der erneute Download schlug fehl (Logs unten pruefen).'
}

# --- Abschnitt: DLL-Abhaengigkeitsanalyse -------------------------------
Add-Section 'DLL-ABHAENGIGKEITS-ANALYSE (Kern der Diagnose)'

if ($serverDir) {
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($ServerPath)
    [void]$visited.Add((Split-Path -Leaf $ServerPath))

    $deps = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $parseErrors = [System.Collections.Generic.List[string]]::new()

    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        $pe = Get-PeInfo -Path $file
        $importerName = Split-Path -Leaf $file
        if ($pe.Error) {
            $parseErrors.Add(("{0}: {1}" -f $importerName, $pe.Error))
            continue
        }
        foreach ($rawDep in $pe.Imports) {
            $isDelay = $rawDep.EndsWith(' (delay)')
            $depName = if ($isDelay) { $rawDep.Substring(0, $rawDep.Length - 8) } else { $rawDep }

            if (-not $deps.ContainsKey($depName)) {
                $res = Resolve-DllPath -Name $depName -LocalDir $serverDir -Architecture $serverArch
                $arch = ''
                $isBundled = $false
                if ($res.Status -eq 'OK' -and $res.Path) {
                    $isBundled = ($res.Path.ToLowerInvariant().StartsWith($serverDir.ToLowerInvariant()))
                    $depPe = Get-PeInfo -Path $res.Path
                    if (-not $depPe.Error) { $arch = $depPe.Architecture }
                }
                $deps[$depName] = [pscustomobject]@{
                    Name      = $depName
                    Status    = $res.Status
                    Path      = $res.Path
                    Arch      = $arch
                    Delay     = $isDelay
                    Bundled   = $isBundled
                    Importers = [System.Collections.Generic.List[string]]::new()
                }
                if ($isBundled -and $res.Path -and $visited.Add($depName)) {
                    $queue.Enqueue($res.Path)
                }
            }
            if (-not $deps[$depName].Importers.Contains($importerName)) {
                $deps[$depName].Importers.Add($importerName)
            }
        }
    }

    $missing = @($deps.Values | Where-Object { $_.Status -eq 'FEHLT' } | Sort-Object Name)
    $mismatch = @($deps.Values | Where-Object { $_.Status -eq 'OK' -and $_.Arch -and $_.Arch -ne $serverArch -and $_.Arch -notlike '0x*' } | Sort-Object Name)

    Add-Line ("Server-Architektur: {0}" -f $serverArch)
    Add-Line ("Untersuchte Module: {0}   Fehlend: {1}   Arch-Konflikt: {2}" -f $deps.Count, $missing.Count, $mismatch.Count)
    Add-Line ''

    if ($missing.Count -gt 0) {
        Add-Line '>>> FEHLENDE DLLs (sehr wahrscheinlich die Startursache) <<<'
        foreach ($m in $missing) {
            $imp = ($m.Importers -join ', ')
            $tag = if ($m.Delay) { ' [delay-load]' } else { '' }
            Add-Line ("  [FEHLT] {0}{1}" -f $m.Name, $tag)
            Add-Line ("          benoetigt von: {0}" -f $imp)
        }
        Add-Line ''
    } else {
        Add-Line 'Keine fehlenden DLLs in der statischen Import-Analyse gefunden.'
        Add-Line '(Ursache kann dann eine verzoegert/zur Laufzeit per LoadLibrary'
        Add-Line ' geladene DLL sein - siehe Start-Test + Logs.)'
        Add-Line ''
    }

    if ($mismatch.Count -gt 0) {
        Add-Line '>>> ARCHITEKTUR-KONFLIKTE (DLL passt nicht zur exe) <<<'
        foreach ($m in $mismatch) {
            Add-Line ("  [{0} statt {1}] {2}  ->  {3}" -f $m.Arch, $serverArch, $m.Name, $m.Path)
        }
        Add-Line ''
    }

    Add-Line 'Vollstaendige Abhaengigkeitsliste:'
    foreach ($d in ($deps.Values | Sort-Object @{ Expression = 'Status'; Descending = $true }, Name)) {
        $loc = switch ($d.Status) {
            'OK'      { if ($d.Bundled) { 'mitgeliefert' } else { $d.Path } }
            'API-Set' { '(virtuell)' }
            default   { '---' }
        }
        $archStr = if ($d.Arch) { $d.Arch } else { '?' }
        $delayStr = if ($d.Delay) { ' (delay)' } else { '' }
        Add-Line ("  [{0,-7}] {1,-30} {2,-5} {3}{4}" -f $d.Status, $d.Name, $archStr, $loc, $delayStr)
    }

    if ($parseErrors.Count -gt 0) {
        Add-Line ''
        Add-Line 'Parse-Hinweise:'
        foreach ($e in $parseErrors) { Add-Line ("  $e") }
    }
} else {
    Add-Line 'Uebersprungen - keine whisper-server.exe gefunden.'
}

# --- Abschnitt: Visual C++ Runtime --------------------------------------
Add-Section 'VISUAL C++ RUNTIME'

$vcDlls = @(
    'VCRUNTIME140.dll', 'VCRUNTIME140_1.dll',
    'MSVCP140.dll', 'MSVCP140_1.dll', 'MSVCP140_2.dll',
    'VCOMP140.dll', 'CONCRT140.dll'
)
if ($onWindows -and $env:WINDIR) {
    $sys32 = Join-Path $env:WINDIR 'System32'
    Add-Line ("System32-Pruefung ({0}):" -f $sys32)
    foreach ($dll in $vcDlls) {
        $path = Join-Path $sys32 $dll
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $ver = (Get-Item -LiteralPath $path).VersionInfo.FileVersion
            Add-Line ("  [OK]    {0,-22} v{1}" -f $dll, $ver)
        } else {
            Add-Line ("  [FEHLT] {0}" -f $dll)
        }
    }

    Add-Line ''
    Add-Line 'Installierte VC++-Redistributables (Registry):'
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $vcEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $uninstallRoots) {
        try {
            $hits = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*Visual C++*Redistributable*' }
            foreach ($h in $hits) { $vcEntries.Add($h) }
        } catch { continue }
    }
    if ($vcEntries.Count -gt 0) {
        foreach ($e in $vcEntries) {
            Add-Line ("  - {0}  (v{1})" -f $e.DisplayName, $e.DisplayVersion)
        }
    } else {
        Add-Line '  (keine VC++-Redistributable-Eintraege gefunden)'
    }

    Add-Line ''
    Add-Line 'Runtime-Schluessel (HKLM\...\VC\Runtimes):'
    foreach ($edition in @('X64', 'X86')) {
        $key = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$edition"
        $keyWow = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$edition"
        foreach ($k in @($key, $keyWow)) {
            try {
                if (Test-Path -LiteralPath $k) {
                    $p = Get-ItemProperty -LiteralPath $k -ErrorAction Stop
                    $inst = if ($p.PSObject.Properties.Name -contains 'Installed') { $p.Installed } else { '?' }
                    $ver = if ($p.PSObject.Properties.Name -contains 'Version') { $p.Version } else { '?' }
                    Add-Line ("  {0,-4}: Installed={1}  Version={2}" -f $edition, $inst, $ver)
                }
            } catch { continue }
        }
    }
} else {
    Add-Line '(Windows erforderlich - uebersprungen.)'
}

# --- Abschnitt: App-Logs ------------------------------------------------
Add-Section ("WHISPASTE-LOG (letzte {0} Zeilen je Variante)" -f $LogTail)

$logFound = $false
foreach ($r in $dataRoots) {
    $logFile = Join-Path $r.Root 'logs\whispaste.log'
    if (Test-Path -LiteralPath $logFile -PathType Leaf) {
        $logFound = $true
        $lf = Get-Item -LiteralPath $logFile
        Add-Line ''
        Add-Line ("[{0}] {1}" -f $r.Label, $logFile)
        Add-Line ("  Groesse: {0:N0} Bytes   Geaendert: {1:yyyy-MM-dd HH:mm:ss}" -f $lf.Length, $lf.LastWriteTime)
        Add-Line '  --- Tail ---'
        try {
            $tail = Get-Content -LiteralPath $logFile -Tail $LogTail -ErrorAction Stop
            foreach ($line in $tail) { Add-Line ("  | {0}" -f $line) }
        } catch {
            Add-Line ("  (Log nicht lesbar: {0})" -f $_.Exception.Message)
        }
    }
}
if (-not $logFound) {
    Add-Line 'Keine whispaste.log gefunden (App ggf. nie gestartet oder Logging aus).'
}

# --- Abschnitt: Start-Test ----------------------------------------------
Add-Section 'START-TEST (Exit-Code der Binary)'

if ($NoRunTest) {
    Add-Line 'Uebersprungen (-NoRunTest gesetzt).'
} elseif (-not ($ServerPath -and (Test-Path -LiteralPath $ServerPath -PathType Leaf))) {
    Add-Line 'Uebersprungen - keine Binary vorhanden.'
} elseif (-not $onWindows) {
    Add-Line 'Uebersprungen - Start-Test nur unter Windows sinnvoll.'
} else {
    Add-Line 'Starte whisper-server.exe kurz, um den Lade-Exit-Code zu pruefen...'
    $errFile = [System.IO.Path]::GetTempFileName()
    $outFileTmp = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $ServerPath -ArgumentList '--help' -PassThru `
            -RedirectStandardError $errFile -RedirectStandardOutput $outFileTmp -WindowStyle Hidden
        $exited = $proc.WaitForExit(8000)
        if (-not $exited) {
            Add-Line '  Prozess laeuft noch nach 8 s -> DLLs konnten geladen werden'
            Add-Line '  (kein 0xC0000135-Ladefehler). Wird beendet.'
            try { $proc.Kill() } catch { Add-Line "  (Beenden fehlgeschlagen: $($_.Exception.Message))" }
        } else {
            $code = $proc.ExitCode
            $hex = ('0x{0:X8}' -f ([uint32]($code -band 0xFFFFFFFF)))
            $meaning = switch ($code) {
                -1073741515 { 'STATUS_DLL_NOT_FOUND - eine benoetigte DLL fehlt (0xC0000135)' }
                -1073741511 { 'STATUS_ENTRYPOINT_NOT_FOUND - DLL vorhanden, aber falsche Version (0xC0000139)' }
                -1073741701 { 'STATUS_INVALID_IMAGE_FORMAT - Architektur-/Format-Konflikt (0xC000007B)' }
                -1073740791 { 'STATUS_STACK_BUFFER_OVERRUN / Abbruch (0xC0000409)' }
                0           { 'OK (sauberer Start/Beenden)' }
                default     { '(siehe Exit-Code / stderr)' }
            }
            Add-Line ("  Exit-Code: {0} ({1})" -f $code, $hex)
            Add-Line ("  Bedeutung: {0}" -f $meaning)
        }
        $errText = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
        if ($errText -and $errText.Trim()) {
            Add-Line '  --- stderr (gekuerzt) ---'
            foreach ($line in ($errText -split "`n" | Select-Object -First 20)) {
                if ($line.Trim()) { Add-Line ("    {0}" -f $line.TrimEnd()) }
            }
        }
    } catch {
        Add-Line ("  Start fehlgeschlagen: {0}" -f $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $errFile, $outFileTmp -ErrorAction SilentlyContinue
    }

    # --- Echter Modell-Lade-Test ------------------------------------------
    # Der --help-Test oben laedt NUR den Hilfetext: er initialisiert weder das
    # Modell noch die ggml-Compute-Backends (ggml-cpu/ggml-blas/libopenblas).
    # Genau deshalb meldete er im Feld "Exit 0", obwohl die App den Server mit
    # 0xC0000135 (STATUS_DLL_NOT_FOUND) abstuerzen sah -- der Fehler tritt erst
    # beim echten Laden auf (FLUTTER_WHISPASTE-A0, GTX 650 Kepler). Dieser
    # zweite Test startet den Server so, wie die App es tut: mit echtem Modell
    # und --no-gpu, gegen einen freien Port, und faengt den realen Exit-Code.
    Add-Line ''
    Add-Line 'Echter Modell-Lade-Test (wie die App startet, --no-gpu)...'
    $serverDirForTest = Split-Path -Parent $ServerPath
    $modelFile = Get-ChildItem -LiteralPath $serverDirForTest -Filter 'ggml-*.bin' -File -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending | Select-Object -First 1
    if (-not $modelFile) {
        Add-Line '  Uebersprungen - kein Modell (ggml-*.bin) neben der Binary gefunden.'
    } else {
        $errFile2 = [System.IO.Path]::GetTempFileName()
        $outFile2 = [System.IO.Path]::GetTempFileName()
        # Freien lokalen Port suchen, damit der Test keinen echten Server stoert.
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $testPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        $listener.Stop()
        try {
            Add-Line ("  Modell: {0} ({1:N0} Bytes)" -f $modelFile.Name, $modelFile.Length)
            $args2 = @(
                '--model', $modelFile.FullName,
                '--host', '127.0.0.1', '--port', "$testPort",
                '--threads', '4', '--no-timestamps', '--no-gpu'
            )
            $proc2 = Start-Process -FilePath $ServerPath -ArgumentList $args2 -PassThru `
                -RedirectStandardError $errFile2 -RedirectStandardOutput $outFile2 -WindowStyle Hidden
            $exited2 = $proc2.WaitForExit(20000)
            if (-not $exited2) {
                Add-Line '  ERGEBNIS: Server laeuft nach 20 s stabil -> Modell + Backends'
                Add-Line '  wurden erfolgreich geladen. KEIN Ladefehler. Wird beendet.'
                try { $proc2.Kill() } catch { $null = $_ }
            } else {
                $code2 = $proc2.ExitCode
                $hex2 = ('0x{0:X8}' -f ([uint32]($code2 -band 0xFFFFFFFF)))
                $meaning2 = switch ($code2) {
                    -1073741515 { 'STATUS_DLL_NOT_FOUND - Backend-/Laufzeit-DLL fehlt im Suchpfad (0xC0000135)' }
                    -1073741511 { 'STATUS_ENTRYPOINT_NOT_FOUND - DLL da, aber falsche Version (0xC0000139)' }
                    -1073740791 { 'STATUS_STACK_BUFFER_OVERRUN / Abbruch (0xC0000409)' }
                    -1073741819 { 'STATUS_ACCESS_VIOLATION (0xC0000005)' }
                    3           { 'Modell konnte nicht geladen/geoeffnet werden (whisper exit 3)' }
                    0           { 'OK (sauberer Start/Beenden)' }
                    default     { '(siehe Exit-Code / stderr unten)' }
                }
                Add-Line ("  ERGEBNIS: Exit-Code {0} ({1})" -f $code2, $hex2)
                Add-Line ("  Bedeutung: {0}" -f $meaning2)
                if ($code2 -ne 0) {
                    Add-Line '  >> DAS ist der reale Startfehler, den die App sieht (nicht der'
                    Add-Line '  >> --help-Test darueber). Exit-Code + stderr hier sind massgeblich.'
                }
            }
            $errText2 = (Get-Content -LiteralPath $errFile2 -Raw -ErrorAction SilentlyContinue)
            if ($errText2 -and $errText2.Trim()) {
                Add-Line '  --- stderr (gekuerzt) ---'
                foreach ($line in ($errText2 -split "`n" | Select-Object -First 25)) {
                    if ($line.Trim()) { Add-Line ("    {0}" -f $line.TrimEnd()) }
                }
            }
        } catch {
            Add-Line ("  Start fehlgeschlagen: {0}" -f $_.Exception.Message)
        } finally {
            Remove-Item -LiteralPath $errFile2, $outFile2 -ErrorAction SilentlyContinue
        }
    }
}

# --- Abschnitt: Bewertung -----------------------------------------------
Add-Section 'AUTOMATISCHE BEWERTUNG'

$verdict = [System.Collections.Generic.List[string]]::new()
if (-not $serverDir) {
    $verdict.Add('- Keine whisper-server.exe auf der Platte. Entweder nie vollstaendig')
    $verdict.Add('  geladen, oder die Selbstheilung hat sie nach einem Fehlstart')
    $verdict.Add('  geloescht und der Re-Download schlug fehl. Logs oben pruefen:')
    $verdict.Add('  nach "recovery", "exited", "dllMissing", "download" suchen.')
} else {
    if ($null -ne (Get-Variable -Name missing -ErrorAction SilentlyContinue) -and $missing.Count -gt 0) {
        $verdict.Add('- Es fehlen konkrete DLLs (siehe Liste oben). Genau diese')
        $verdict.Add('  Datei(en) sind die Startursache, NICHT die GPU.')
        $vcMiss = @($missing | Where-Object { $vcDlls -contains $_.Name })
        if ($vcMiss.Count -gt 0) {
            $verdict.Add('- Darunter VC++-Runtime-DLLs -> Visual C++ Redistributable')
            $verdict.Add('  x64 installieren: https://aka.ms/vs/17/release/vc_redist.x64.exe')
        } else {
            $verdict.Add('- Keine VC++-Runtime-DLL betroffen - die fehlende DLL gehoert')
            $verdict.Add('  zu einer anderen Komponente (gebuendelte ggml-/CUDA-/Vulkan-')
            $verdict.Add('  oder Treiber-DLL). Pfad/Importer oben pruefen.')
        }
    } else {
        $verdict.Add('- Statische Analyse: keine fehlende DLL. Falls die App dennoch')
        $verdict.Add('  scheitert, ist der Start-Test-Exit-Code + die Logs massgeblich.')
    }
}
foreach ($v in $verdict) { Add-Line $v }

Add-Line ''
Add-Line ('=' * 72)
Add-Line 'Ende des Reports. Bitte diese Datei zuruecksenden.'

# =========================================================================
# Ausgabe: Datei + Konsole
# =========================================================================

if (-not $OutFile) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { $desktop = (Get-Location).Path }
    $OutFile = Join-Path $desktop ("WhisPaste-Diagnose_{0:yyyyMMdd_HHmmss}.txt" -f $now)
}

try {
    $script:Report -join [Environment]::NewLine | Set-Content -LiteralPath $OutFile -Encoding UTF8
} catch {
    Add-Line ("WARNUNG: Report-Datei konnte nicht geschrieben werden: {0}" -f $_.Exception.Message)
}

$script:Report | ForEach-Object { Write-Output $_ }
Write-Output ''
Write-Output ("Report gespeichert unter: {0}" -f $OutFile)

# =========================================================================
# Abschluss-Anweisung fuer den Nutzer + Pause
#
# Wichtig: Als kompilierte .exe (ps2exe) oder per Doppelklick schliesst sich
# das Konsolenfenster sonst sofort -- der Nutzer sieht nie, dass ueberhaupt
# ein Report erzeugt wurde, und weiss nicht, was als Naechstes zu tun ist.
# Darum hier eine klare, freundliche Schluss-Meldung und eine Pause. In CI /
# automatisierten Laeufen wird die Pause per -NoPause uebersprungen.
# =========================================================================
Write-Output ''
Write-Output ('=' * 72)
Write-Output '  FERTIG - was du jetzt tun solltest:'
Write-Output ('=' * 72)
Write-Output ''
Write-Output '  1. Es wurde eine Diagnose-Datei erstellt:'
Write-Output ("       {0}" -f $OutFile)
Write-Output '     (liegt normalerweise auf deinem Desktop).'
Write-Output ''
Write-Output '  2. Bitte sende diese Datei an den Support / per Mail zurueck.'
Write-Output '     Sie enthaelt keine persoenlichen Inhalte - nur technische'
Write-Output '     Infos zu Hardware, Treibern und dem Sprachdienst-Start.'
Write-Output ''
Write-Output '  3. Danach kannst du dieses Fenster schliessen.'
Write-Output ''

# Pause nur, wenn interaktiv und nicht ausdruecklich unterdrueckt. Ohne diese
# Guards wuerde ein CI-Lauf (ps2exe-Build/Smoke-Test) ewig haengen.
$interactive = $false
try { $interactive = [Environment]::UserInteractive } catch { $interactive = $false }
if (-not $NoPause -and $interactive) {
    try {
        Read-Host -Prompt 'Zum Schliessen die Eingabetaste druecken'
    } catch {
        # Read-Host kann in nicht-interaktiven Hosts werfen -> still ignorieren.
        $null = $_
    }
}
