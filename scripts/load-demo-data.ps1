# load-demo-data.ps1 — Populates WhisPaste with realistic mockup data for video recording
# Usage: .\scripts\load-demo-data.ps1
#   -Restore  : Restores the original database from backup
#   -Reset    : Removes demo data and backup

param(
    [switch]$Restore,
    [switch]$Reset
)

$dbDir  = "$env:APPDATA\WhisPaste"
$dbPath = "$dbDir\history.db"
$backup = "$dbDir\history-backup.db"

# --- Restore mode ---
if ($Restore) {
    if (Test-Path $backup) {
        Copy-Item $backup $dbPath -Force
        Write-Host "Original-Datenbank wiederhergestellt aus Backup." -ForegroundColor Green
    } else {
        Write-Host "Kein Backup gefunden unter: $backup" -ForegroundColor Red
    }
    exit 0
}

# --- Reset mode ---
if ($Reset) {
    if (Test-Path $backup) {
        Copy-Item $backup $dbPath -Force
        Remove-Item $backup -Force
        Write-Host "Original wiederhergestellt und Backup entfernt." -ForegroundColor Green
    } else {
        Write-Host "Kein Backup vorhanden — nichts zu tun." -ForegroundColor Yellow
    }
    exit 0
}

# --- Safety check ---
$procs = Get-Process -Name "whispaste" -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host "WhisPaste laeuft noch! Bitte erst beenden (Tray > Quit)." -ForegroundColor Red
    exit 1
}

# --- Backup ---
if (Test-Path $dbPath) {
    Copy-Item $dbPath $backup -Force
    Write-Host "Backup erstellt: $backup" -ForegroundColor Cyan
} else {
    Write-Host "Keine bestehende Datenbank gefunden — erstelle neue." -ForegroundColor Yellow
}

# --- Ensure directory exists ---
if (!(Test-Path $dbDir)) { New-Item -ItemType Directory -Force -Path $dbDir | Out-Null }

# --- Helper functions ---
$now = Get-Date
function ISODate([int]$daysAgo, [int]$hour, [int]$minute) {
    $d = $now.AddDays(-$daysAgo).Date.AddHours($hour).AddMinutes($minute)
    return $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
function DateStr([int]$daysAgo) {
    return $now.AddDays(-$daysAgo).ToString("yyyy-MM-dd")
}
function RandHex { return -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) }) }

# --- Build SQL ---
$sb = [System.Text.StringBuilder]::new(16000)

[void]$sb.AppendLine("-- Demo-Daten fuer WhisPaste Video")
[void]$sb.AppendLine("-- Generiert am: $($now.ToString('yyyy-MM-dd HH:mm'))")
[void]$sb.AppendLine("")

# Schema (CREATE IF NOT EXISTS for safety)
[void]$sb.AppendLine(@'
CREATE TABLE IF NOT EXISTS history_entries (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    timestamp TEXT NOT NULL,
    duration_sec REAL NOT NULL DEFAULT 0,
    processing_duration_sec REAL NOT NULL DEFAULT 0,
    language TEXT NOT NULL DEFAULT '',
    tags TEXT NOT NULL DEFAULT '[]',
    pinned INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'dictation',
    model TEXT NOT NULL DEFAULT '',
    is_local INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    project_id TEXT NOT NULL DEFAULT '',
    archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS daily_stats (
    date TEXT NOT NULL,
    model TEXT NOT NULL,
    is_local INTEGER NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    total_duration_sec REAL NOT NULL DEFAULT 0,
    total_processing_sec REAL NOT NULL DEFAULT 0,
    total_words INTEGER NOT NULL DEFAULT 0,
    total_cost_usd REAL NOT NULL DEFAULT 0,
    dur_under_15s INTEGER NOT NULL DEFAULT 0,
    dur_15_30s INTEGER NOT NULL DEFAULT 0,
    dur_30_60s INTEGER NOT NULL DEFAULT 0,
    dur_1_3m INTEGER NOT NULL DEFAULT 0,
    dur_over_3m INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (date, model, is_local)
);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER);
INSERT OR REPLACE INTO schema_version (version) VALUES (5);

DELETE FROM history_entries;
DELETE FROM projects;
DELETE FROM daily_stats;
'@)

# --- Projects ---
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Projekte")
[void]$sb.AppendLine("INSERT INTO projects (id, name, created_at) VALUES ('proj_alpha',  'Kundenprojekt Alpha',  '$(ISODate 45 9 0)');")
[void]$sb.AppendLine("INSERT INTO projects (id, name, created_at) VALUES ('proj_blog',   'Blog Content',         '$(ISODate 30 14 0)');")
[void]$sb.AppendLine("INSERT INTO projects (id, name, created_at) VALUES ('proj_intern', 'Team Intern',          '$(ISODate 60 10 0)');")

# --- History entries ---
$entries = @(
    # Today
    @{ text="Sehr geehrte Frau Mueller, vielen Dank fuer Ihre Nachricht. Ich kann den Termin am Donnerstag um 14 Uhr bestaetigen. Bitte bringen Sie die Unterlagen zum Projektplan mit. Mit freundlichen Gruessen"; title="E-Mail Terminbestaetigung"; days=0; h=10; m=15; dur=12.5; proc=1.8; lang="de"; tags='["Meeting","Wichtig"]'; pin=1; src="smart"; model="whisper-small"; local=1; cost=0; proj="proj_alpha" },
    @{ text="Idee fuer den naechsten Blog-Post: Top 5 Produktivitaets-Tools fuer Freiberufler. Fokus auf kostenlose Open-Source-Alternativen. Zielgruppe: Selbststaendige und Freelancer."; title="Blog-Idee: Produktivitaets-Tools"; days=0; h=11; m=30; dur=8.3; proc=0.9; lang="de"; tags='["Idee","Draft"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_blog" },
    @{ text="Notiz an mich selbst: Die Praesentation fuer Freitag muss noch ueberarbeitet werden. Slide 3 und 7 brauchen aktuelle Zahlen aus dem Q4-Report."; title="Praesentation ueberarbeiten"; days=0; h=14; m=45; dur=6.1; proc=0; lang="de"; tags='["Follow-up"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="" },
    @{ text="Quick reminder: Call with the design team at 3 PM to discuss the new landing page mockups. Need to bring the brand guidelines document."; title="Design Team Call Reminder"; days=0; h=9; m=0; dur=7.2; proc=0; lang="en"; tags='["Meeting"]'; pin=1; src="dictation"; model="whisper-1"; local=0; cost=0.0043; proj="proj_alpha" },

    # Yesterday
    @{ text="Meeting-Protokoll vom 9. Maerz: 1. Projektstatus Alpha: Im Zeitplan, naechster Meilenstein am 20. Maerz. 2. Budget: 12.000 Euro verbraucht von 20.000 Euro. 3. Offene Punkte: Design-Review bis Freitag, API-Dokumentation aktualisieren. 4. Naechstes Meeting: Montag 10 Uhr"; title="Meeting-Protokoll Projektstatus"; days=1; h=10; m=0; dur=45.2; proc=3.1; lang="de"; tags='["Meeting","Wichtig"]'; pin=1; src="smart"; model="whisper-1"; local=0; cost=0.027; proj="proj_alpha" },
    @{ text="Die neue Funktion fuer automatisches Tagging funktioniert jetzt. Habe sie mit 50 Testeintraegen geprueft. Genauigkeit liegt bei etwa 85 Prozent."; title="Auto-Tagging Testergebnis"; days=1; h=15; m=20; dur=10.8; proc=0; lang="de"; tags='["Erledigt"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },
    @{ text="Hey Lisa, koenntest du bitte die Social-Media-Posts fuer naechste Woche vorbereiten? Wir brauchen je einen Post fuer LinkedIn, Twitter und Instagram. Thema: Unser neues Feature-Update."; title="Social Media Posts beauftragen"; days=1; h=11; m=45; dur=9.4; proc=1.2; lang="de"; tags='["Follow-up"]'; pin=0; src="smart"; model="whisper-small"; local=1; cost=0; proj="proj_blog" },

    # 2 days ago
    @{ text="Zusammenfassung Kundenfeedback Q1: 89% Zufriedenheit insgesamt. Haeufigste Wuensche: Offline-Modus, mehr Sprachen, Mobile App. NPS Score: 72 (sehr gut)"; title="Kundenfeedback Q1 Zusammenfassung"; days=2; h=9; m=30; dur=22.1; proc=2.5; lang="de"; tags='["Wichtig","Meeting"]'; pin=0; src="smart"; model="whisper-1"; local=0; cost=0.013; proj="proj_alpha" },
    @{ text="Draft for the blog post introduction: Voice-to-text technology has come a long way. What used to require expensive hardware and proprietary software is now available as a free desktop app."; title="Blog Draft: Voice-to-Text Intro"; days=2; h=14; m=0; dur=15.3; proc=0; lang="en"; tags='["Draft"]'; pin=0; src="dictation"; model="whisper-1"; local=0; cost=0.0092; proj="proj_blog" },

    # This week
    @{ text="Einkaufsliste fuer das Team-Event am Freitag: 20 Getraenke, Snacks fuer 15 Personen, Servietten, Pappteller, Bluetooth-Lautsprecher organisieren. Budget: maximal 150 Euro."; title="Team-Event Einkaufsliste"; days=3; h=12; m=0; dur=8.7; proc=0; lang="de"; tags='["Follow-up"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },
    @{ text="The API integration for the customer portal is 80% complete. Remaining tasks: error handling, rate limiting, and integration tests. Estimated completion: end of this week."; title="API Integration Status Update"; days=3; h=16; m=30; dur=11.2; proc=0; lang="en"; tags='["Wichtig"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_alpha" },
    @{ text="Telefonat mit Herr Schmidt zusammengefasst: Er ist grundsaetzlich zufrieden mit dem Projektfortschritt. Moechte aber mehr Transparenz bei den woechentlichen Updates."; title="Telefonat Herr Schmidt"; days=4; h=11; m=0; dur=14.6; proc=1.9; lang="de"; tags='["Meeting","Follow-up"]'; pin=0; src="smart"; model="whisper-1"; local=0; cost=0.0088; proj="proj_alpha" },
    @{ text="Notiz: Python-Skript fuer die automatische Datenmigration ist fertig. Laeuft in unter 3 Minuten fuer 10.000 Datensaetze."; title="Datenmigration fertig"; days=4; h=17; m=0; dur=7.8; proc=0; lang="de"; tags='["Erledigt"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },
    @{ text="Brainstorming fuer die Roadmap Q2: Multi-Sprachen-Support erweitern, Team-Collaboration, Browser-Extension, Mobile Companion App. Prioritaet nach Kundenfeedback festlegen."; title="Roadmap Q2 Brainstorming"; days=5; h=10; m=0; dur=18.9; proc=2.3; lang="de"; tags='["Idee","Wichtig"]'; pin=0; src="smart"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },

    # Last week
    @{ text="Lieber Max, hier die Zusammenfassung unseres Gespraeches: Design bis zum 15. fertig, technische Umsetzung startet am 18. Du Mockups, ich Backend-Architektur. Bei Fragen jederzeit melden!"; title="Zusammenfassung Gespraech Max"; days=8; h=14; m=30; dur=16.4; proc=2.0; lang="de"; tags='["Meeting"]'; pin=0; src="smart"; model="whisper-1"; local=0; cost=0.0098; proj="proj_alpha" },
    @{ text="Feedback zum neuen Onboarding-Flow: Der Wizard ist intuitiv, aber Schritt 3 koennte besser erklaert werden. Vielleicht ein kurzes Erklaervideo einbetten? Ausserdem fehlt ein Skip-Button."; title="Onboarding Feedback"; days=9; h=11; m=15; dur=12.1; proc=0; lang="de"; tags='["Idee"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },
    @{ text="Weekly standup notes: Sarah finished the export module, starting on analytics. Tom did bug fixes for the overlay, 3 issues closed. Lisa has the content calendar ready. Action items: Code review by Wednesday."; title="Weekly Standup Notes"; days=10; h=9; m=30; dur=25.7; proc=2.8; lang="en"; tags='["Meeting","Follow-up"]'; pin=0; src="smart"; model="whisper-1"; local=0; cost=0.015; proj="proj_intern" },
    @{ text="Recherche-Ergebnis: Die drei besten Hosting-Alternativen sind Hetzner, Contabo und Netcup. Hetzner hat das beste Preis-Leistungs-Verhaeltnis. Empfehlung: Migration auf Hetzner Cloud."; title="Hosting Recherche"; days=11; h=15; m=0; dur=11.3; proc=1.5; lang="de"; tags='["Idee"]'; pin=0; src="smart"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },

    # Older
    @{ text="Konzept fuer die Preisgestaltung: Freemium-Modell mit kostenloser Basisversion und Premium fuer 9.99 Euro pro Monat. Premium: unbegrenzte Cloud-Transkriptionen, Priority-Support, erweiterte Analytics."; title="Preismodell Konzept"; days=15; h=10; m=0; dur=20.5; proc=2.7; lang="de"; tags='["Wichtig","Idee"]'; pin=0; src="smart"; model="whisper-1"; local=0; cost=0.012; proj="proj_intern" },
    @{ text="User Story: Als Freiberufler moechte ich meine Rechnungstexte diktieren koennen, damit ich weniger Zeit mit Tippen verbringe und mich auf meine eigentliche Arbeit konzentrieren kann."; title="User Story: Rechnungstexte"; days=18; h=13; m=0; dur=14.2; proc=0; lang="de"; tags='["Draft"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_alpha" },
    @{ text="Tutorial-Skript Kapitel 1: Willkommen bei WhisPaste. In diesem Tutorial zeigen wir dir, wie du in weniger als einer Minute loslegen kannst. Los gehts!"; title="Tutorial Skript Kapitel 1"; days=20; h=11; m=0; dur=9.8; proc=0; lang="de"; tags='["Draft"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_blog" },
    @{ text="Performance-Test Ergebnisse: Lokales Whisper-Small in 4.2 Sekunden auf Ryzen 5 5600X. Cloud whisper-1 in 1.8 Sekunden inkl. Netzwerk-Latenz. Beide gut genug fuer Echtzeit-Nutzung."; title="Performance Test Ergebnisse"; days=22; h=16; m=0; dur=17.6; proc=0; lang="de"; tags='["Erledigt","Wichtig"]'; pin=0; src="dictation"; model="whisper-1"; local=0; cost=0.011; proj="proj_intern" }
)

# Archived entries (separate to set archived=1)
$archivedEntries = @(
    @{ text="Alte Notiz: Server-Migration am 15. Januar erfolgreich abgeschlossen. Alle Dienste laufen stabil. Dokumentation aktualisiert."; title="Server Migration abgeschlossen"; days=45; h=9; m=0; dur=6.5; proc=0; lang="de"; tags='["Erledigt"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="proj_intern" },
    @{ text="Deprecated: Alter Workflow fuer die manuelle Datensicherung. Wurde durch automatisches Backup ersetzt. Kann geloescht werden."; title="Alter Backup Workflow"; days=50; h=14; m=0; dur=5.2; proc=0; lang="de"; tags='["Erledigt"]'; pin=0; src="dictation"; model="whisper-small"; local=1; cost=0; proj="" }
)

[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Verlaufseintraege (25 Stueck)")
foreach ($e in $entries) {
    $id = RandHex
    $ts = ISODate $e.days $e.h $e.m
    $t = $e.text -replace "'", "''"
    $ti = $e.title -replace "'", "''"
    [void]$sb.AppendLine("INSERT INTO history_entries (id, text, title, timestamp, duration_sec, processing_duration_sec, language, tags, pinned, source, model, is_local, cost_usd, project_id, archived) VALUES ('$id', '$t', '$ti', '$ts', $($e.dur), $($e.proc), '$($e.lang)', '$($e.tags)', $($e.pin), '$($e.src)', '$($e.model)', $($e.local), $($e.cost), '$($e.proj)', 0);")
}
foreach ($e in $archivedEntries) {
    $id = RandHex
    $ts = ISODate $e.days $e.h $e.m
    $t = $e.text -replace "'", "''"
    $ti = $e.title -replace "'", "''"
    [void]$sb.AppendLine("INSERT INTO history_entries (id, text, title, timestamp, duration_sec, processing_duration_sec, language, tags, pinned, source, model, is_local, cost_usd, project_id, archived) VALUES ('$id', '$t', '$ti', '$ts', $($e.dur), $($e.proc), '$($e.lang)', '$($e.tags)', $($e.pin), '$($e.src)', '$($e.model)', $($e.local), $($e.cost), '$($e.proj)', 1);")
}

# --- Daily stats (30 days) ---
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Analytics (30 Tage)")
for ($i = 0; $i -lt 30; $i++) {
    $date = DateStr $i
    $lc = Get-Random -Minimum 2 -Maximum 7
    $cc = Get-Random -Minimum 0 -Maximum 3
    $ld = [math]::Round((Get-Random -Minimum 20 -Maximum 120), 1)
    $cd = [math]::Round((Get-Random -Minimum 10 -Maximum 60), 1)
    $lw = Get-Random -Minimum 30 -Maximum 200
    $cw = Get-Random -Minimum 15 -Maximum 100
    $ccost = [math]::Round($cd / 60 * 0.006, 4)
    $u15 = Get-Random -Minimum 1 -Maximum 4
    $u30 = Get-Random -Minimum 0 -Maximum 3
    $u60 = Get-Random -Minimum 0 -Maximum 2
    [void]$sb.AppendLine("INSERT INTO daily_stats VALUES ('$date', 'whisper-small', 1, $lc, $ld, $([math]::Round($ld * 0.12, 1)), $lw, 0, $u15, $u30, $u60, 0, 0);")
    if ($cc -gt 0) {
        [void]$sb.AppendLine("INSERT INTO daily_stats VALUES ('$date', 'whisper-1', 0, $cc, $cd, $([math]::Round($cd * 0.06, 1)), $cw, $ccost, $([math]::Max(1, $cc - 1)), $([math]::Min(1, $cc)), 0, 0, 0);")
    }
}

# --- FTS rebuild ---
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- FTS Neuaufbau")
[void]$sb.AppendLine("DELETE FROM history_fts;")
[void]$sb.AppendLine("INSERT INTO history_fts(rowid, title, text, tags) SELECT rowid, title, text, tags FROM history_entries;")

$sql = $sb.ToString()

# --- Write and execute SQL ---
$sqlFile = "$env:TEMP\whispaste-demo-data.sql"
[System.IO.File]::WriteAllText($sqlFile, $sql, [System.Text.Encoding]::UTF8)

$sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
if ($sqlite3) {
    Write-Host "Lade Demo-Daten mit sqlite3..." -ForegroundColor Cyan
    & sqlite3 $dbPath ".read $sqlFile" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Demo-Daten erfolgreich geladen!" -ForegroundColor Green
    } else {
        Write-Host "Fehler beim Laden der Demo-Daten." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "sqlite3 nicht gefunden." -ForegroundColor Yellow
    Write-Host "Installiere mit: winget install sqlite.sqlite" -ForegroundColor White
    Write-Host "Dann fuehre dieses Skript erneut aus." -ForegroundColor White
    Write-Host ""
    Write-Host "Alternativ: SQL-Datei manuell ausfuehren:" -ForegroundColor White
    Write-Host "  sqlite3 `"$dbPath`" `".read $sqlFile`"" -ForegroundColor White
    exit 1
}

# --- Cleanup ---
Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Demo-Daten Uebersicht:" -ForegroundColor Cyan
Write-Host "   25 Verlaufseintraege (3 gepinnt, 2 archiviert)"
Write-Host "    3 Projekte (Kundenprojekt Alpha, Blog Content, Team Intern)"
Write-Host "    6 verschiedene Tags"
Write-Host "   30 Tage Analytics-Daten"
Write-Host ""
Write-Host "Starte jetzt WhisPaste und oeffne das Dashboard!" -ForegroundColor Green
Write-Host ""
Write-Host "Nach dem Video: .\scripts\load-demo-data.ps1 -Restore" -ForegroundColor Yellow
