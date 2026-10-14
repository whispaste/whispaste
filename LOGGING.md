# Logging & Observability

Kurzreferenz für das Logging-Konzept der Desktop-App (`lib/`). Betrifft nicht
`website/` (eigenes, sehr schlankes `console.warn`/`console.error`-Regime,
siehe `website/eslint.config.mjs`) und nicht `supabase/` (kein eigenes
App-Logging, nur SQL/RLS — Rate-Limits laufen über gehärtete DB-Trigger, nicht
über Logs).

## Architektur

```
Aufrufstelle
    │  _log.debug/info/warning/error(...)
    ▼
AppLogger (lib/core/logging/app_logger.dart)
    │  package:logging Logger.root.onRecord
    ├─▶ Breadcrumb-Ring (30 Einträge, für Crash-Kontext)
    ├─▶ dart:developer log()          (immer, DevTools-Log-Tab)
    ├─▶ debugPrint()                   (nur Debug-Build, info+, stdout)
    ├─▶ Datei-Sink                     (info+ Release / debug+ Debug)
    ├─▶ Sentry-Breadcrumb              (ab INFO)
    └─▶ CrashReporter.captureError     (ab SEVERE → Sentry-Event)
```

Alles App-Level-Logging läuft über `AppLogger`. Es gibt **keinen** zweiten,
parallelen Logging-Weg — `print()` ist per Lint (`avoid_print`,
`--fatal-infos` in CI) verboten, `dev.log()`/`debugPrint()` außerhalb von
`AppLogger` selbst sind seit diesem Commit per CI-Gate
(`.github/workflows/ci.yml`, Job „Secret scan“ → Step „Logging gate“)
verboten. Ausnahmen (dokumentiert im Gate-Script): `app_logger.dart` /
`app_monitoring.dart` / `crash_reporter.dart` / `crash_reporting_consent.dart`
selbst (vermeiden rekursive
Logger-Aufrufe) sowie die sekundären Flutter-Engine-Entrypoints
(`*_render_entrypoint.dart`, `overlay_render_channel.dart`), die vor dem
regulären App-Bootstrap laufen können.

## Verwendung

```dart
class MyService {
  static final _log = AppLogger('MyService');

  void doThing() {
    _log.debug('verbose detail, nur für Diagnose');
    _log.info('normaler Statuswechsel, z. B. Recording gestartet');
    _log.warning('erwartete Abweichung, z. B. Fallback ausgelöst');
    try {
      ...
    } catch (e, st) {
      _log.error('Operation X fehlgeschlagen', e, st);
    }
  }
}
```

### Level-Kriterien

| Level | Wann |
|---|---|
| `debug` | Nur für Root-Cause-Analyse relevant, im Normalbetrieb Rauschen. Nur in Debug-Builds persistiert. |
| `info` | Fachlich/technisch bemerkenswerte Zustandswechsel (Recording start/stop, Migration erfolgreich, Settings-Reset) — kein High-Frequency-Spam (z. B. nicht pro Audio-Chunk). |
| `warning` | Erwartete, aber abnormale Situation (Fallback, ignorierte Operation, Retry) — kein Nutzerfehler, aber diagnostisch relevant. |
| `error` | Fehlgeschlagene Operation, Exception. Wird ab `SEVERE` automatisch nach Sentry eskaliert (`fingerprint: [appLoggerAutoEscalated]`). Für gezielte Gruppierung: `CrashReporter.instance?.captureError(fingerprint: [...])` direkt mit einer Konstante aus `crash_fingerprints.dart` statt `_log.error`. |

`Logger.root.level` ist `Level.ALL` im Debug-Build, `Level.INFO` im Release —
Debug-/Verbose-Logging ist damit produktionssicher ausgeschaltet, ohne dass
Security-/Fehler-Logging (`warning`/`error`, immer ≥ `INFO`) betroffen ist.

## Speicherort, Rotation, Retention

- Datei: `<AppData>/Whispaste/logs/whispaste.log` (Pfad aus
  `whispaste_diagnostics`' `appDataDir()`, plattformabhängig unter
  `%LOCALAPPDATA%`/`~/Library/Application Support`/`~/.local/share`).
- Rotation: bei 2 MB wird `whispaste.log` → `whispaste.log.1` verschoben,
  ältere Backups rutschen eine Nummer weiter (`.1`→`.2` … bis `.5`), das
  älteste (`.6`) wird gelöscht. Bounded auf max. ~12 MB (6 × 2 MB) pro
  Installation — kein unbegrenztes Wachstum.
- Diese Nummerierung ist bewusst identisch zu dem Schema, das
  `packages/whispaste_diagnostics/lib/src/probes/log_reader.dart`
  (`rotatedLogPaths`, `maxRotations: 5`) beim Einlesen für die
  In-App-Diagnostik und die WhisPaste-Diagnose-CLI erwartet — vorher liefen
  Sink (`.old`-Suffix) und Reader (`.1`…`.5`) auseinander, sodass rotierte
  Logs vom Diagnose-Tool nie gefunden wurden. Bei künftigen Änderungen an
  `_maxRotations` in `app_logger.dart` immer mit `maxRotations` in
  `log_reader.dart` synchron halten.
- Keine zeitbasierte Retention nötig, da die Größenbegrenzung das
  Gesamtvolumen bereits hart deckelt; alte Sessions rotieren sich durch die
  Größen-Rotation im Normalbetrieb ohnehin regelmäßig heraus.
- Datei-I/O ist Best-Effort: Schreib-/Rotationsfehler landen nur in
  `debugPrint` und werden nie an aufrufenden Code propagiert — ein
  Logging-Ausfall (volle Disk, Permission-Fehler) bringt die App nicht zum
  Absturz.

## Sensible Daten

Zwei Schutzschichten, dieselbe Regex-Quelle
(`packages/whispaste_diagnostics/lib/src/privacy/sanitizer.dart`):

1. **Schreibzeit** (neu): Jede Zeile wird vor dem Schreiben in die Logdatei
   durch `redactSensitive()` geschickt — erkannte Muster (API-Keys,
   `Bearer …`-Token, `password=`/`token=`-Zuweisungen, OpenAI-/Groq-/
   Anthropic-/Google-Key-Formate) werden durch `<redacted>` ersetzt, statt je
   auf Platte zu landen.
2. **Lesezeit** (bestehend): Der Diagnose-Reader (`log_reader.dart`) verwirft
   beim Export zusätzlich ganze Zeilen, die trotzdem ein sensibles Muster
   enthalten (Defense-in-Depth), und ersetzt Pfad-/Benutzername-Segmente
   durch Platzhalter (`sanitizePaths`).

**Log-Injection-Schutz**: `record.message`/`record.error` werden vor dem
Schreiben single-lined (`\n`/`\r` → literales `\n`, Steuerzeichen entfernt),
sodass aufrufer-kontrollierter Text (z. B. Dateinamen, Clipboard-Ausschnitte
in Fehlermeldungen) keine gefälschten zusätzlichen Log-Zeilen erzeugen kann.
Stacktraces bleiben bewusst mehrzeilig (klar als solche erkennbar, kein
freier Text).

Inhalts-Ebene (Diktat-Text, Audio, Zwischenablage-Inhalt) wird nach dem
Zwei-Schichten-Datenmodell des Projekts (`CONTEXT.md` §6.5) grundsätzlich
**nie** geloggt — weder Debug- noch Release-Build.

## Security-/Audit-relevante Pfade

Diese Bereiche loggen gezielt (nicht nur generische Fehler) und sind bei
Root-Cause-Analysen zuerst zu prüfen:

| Bereich | Logger | Datei |
|---|---|---|
| BYOK-API-Key-Speicherung | — (nie geloggt, nur Erfolg/Fehlschlag des Storage-Zugriffs) | `lib/core/config/secure_key_store.dart` |
| Auto-Update (Signaturprüfung, Installation) | `AppLogger` | `lib/services/auto_updater_service.dart`, `lib/services/update/mac_update_installer.dart` |
| Bundle-ID-Migration (macOS App-ID-Wechsel, Datenübernahme) | `AppLogger('BundleIdMigration')` | `lib/services/bundle_id_migration_service.dart` |
| STT-Crash-Klassifikation (Exit-Code → Fingerprint) | `AppLogger` + `CrashReporter` mit `crash_fingerprints.dart`-Konstanten | `lib/services/stt/whisper/gpu_load_crash_guard.dart` |
| Settings-Factory-Reset/-Migration | `AppLogger('SettingsProvider')` | `lib/core/config/settings_provider.dart` |
| DB-Schema-Migrationen | `AppLogger('Database')` | `lib/core/data/database.dart` |
| Crash-Reporting-Consent-Änderung | `AppLogger`/`dev.log` (Consent-Toggle selbst, bewusst nicht persistiert) | `lib/core/logging/crash_reporter.dart` |
| Feedback-Rate-Limiting | serverseitig, kein Client-Log | `supabase/migrations/20260416_feedback_security_hardening.sql` u. Folge-Migrationen |

Zero-Trust-Client-Prinzip (`CONTEXT.md` §6.1): Logs dienen hier ausschließlich
der Diagnose, nie der Durchsetzung von Limits/Berechtigungen — das bleibt
Server-seitig (Supabase RLS + Trigger).

## Konfiguration je Umgebung

- Kein Flavor-System — Unterscheidung über `kDebugMode`/`kReleaseMode`
  (Dart-Compile-Time-Konstanten).
- Sentry-`environment`: `production` (Release) / `development` (Debug).
- Sentry-Sample-Rate: `0.005` (Release) / `0.05` (Debug) plus eigener
  Free-Tier-Throttle (max. 20 Performance-Transaktionen/Stunde,
  `beforeSendTransaction`).
- GDPR-Consent-Gate (`Settings → Verhalten → Fehlerberichte`,
  Default `true`): steuert `CrashReporter.consentGranted`, greift in
  `beforeSend`, `tracesSampler`, `beforeSendTransaction` — ohne Consent
  verlässt **kein** Event/Breadcrumb das Gerät. Das lokale Logfile
  (Diagnose-Zweck) ist davon unabhängig und läuft immer.

## Debugging-Nutzung

- **Lokal**: Logfile direkt öffnen (`<AppData>/Whispaste/logs/whispaste.log`)
  oder `flutter run` → stdout (Debug-Build zeigt info+ live).
- **Von Nutzern gemeldete Probleme**: In-App-Diagnostik bzw.
  WhisPaste-Diagnose-CLI (`packages/whispaste_diagnostics`) — liest
  Primär- + rotierte Logs, sanitisiert, bündelt mit Hardware-/Permissions-/
  STT-Probes zu einem Diagnosebericht.
- **Crashes/Fehler in Produktion**: Sentry (Projekt `whispaste`),
  gruppiert nach Fingerprint (`crash_fingerprints.dart`), mit Breadcrumb-Trail
  aus den letzten `AppLogger`-Aufrufen vor dem Fehler.
- **STT-Engine-Abstürze**: Exit-Code-Klassifikation in
  `gpu_load_crash_guard.dart` → Fingerprint-Mapping in
  `whispaste_diagnostics/lib/src/analysis/fingerprint_mapping.dart`.

## CI-Absicherung

- `analysis_options.yaml`: `avoid_print` (+ `flutter analyze --fatal-infos`
  macht das zum Hard-Fail).
- `.github/workflows/ci.yml`, Job `secret-scan`, Step „Logging gate“: verbietet
  `dev.log()`/`debugPrint()` außerhalb der dokumentierten Ausnahmen.
- `.github/workflows/ci.yml`, Job `secret-scan`, Step „Scan for potential
  secrets“: repo-weiter Regex-Scan gegen eingecheckte Secrets (ergänzt, nicht
  ersetzt, die Laufzeit-Redaction in `AppLogger`).
