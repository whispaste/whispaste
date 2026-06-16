# Changelog

## 1.2.40

### Features

- **Die Einstellungen sind jetzt durchsuchbar und vollständig per Tastatur bedienbar.** Ein Suchfeld am oberen Rand filtert die Bereiche live mit, springt zum Treffer und bleibt beim Scrollen sichtbar. Die gesamte Bedienung funktioniert per Tastatur und mit Screenreadern (sinnvolle Fokus-Reihenfolge, Sprungmarken, Vorlese-Beschriftungen).
- **Die Einstellungen wurden aufgeräumt und verdichtet.** Verwandte Schalter sind zusammengefasst: „Ton an/aus" steckt jetzt im Lautstärkeregler, die Autostart-Optionen in einem einzigen Dropdown, die Verlaufs-Aufbewahrung in einer Voreinstellung (Standard/Benutzerdefiniert), und „Overlay anzeigen" samt Position liegen beieinander. Das Sprach-Dropdown zeigt die Erkennungssprachen jetzt in der Sprache der Oberfläche.
- **Live-Vorschau für Overlay und Aufnahme-Button direkt in den Einstellungen.** Beide werden in Originalgröße (1:1) und reaktiv dargestellt, sodass eine Änderung sofort so aussieht, wie sie später erscheint.
- **Die Aufnahme-Anzeige (Overlay und Button) wurde neu gestaltet und ist plattformübergreifend identisch.** Eine gemeinsame Design-Quelle wird nativ auf macOS, Windows und Linux dargestellt — dieselbe Wellenform mit mitlaufender Historie, dasselbe Erscheinungsbild in jedem Farbschema und eine korrekt dimensionierte, sauber positionierte kompakte Variante.
- **Automatische In-App-Aktualisierung auf macOS.** WhisPaste kann sich auf macOS jetzt selbst aktualisieren (atomarer DMG-Austausch, bei Bedarf mit Rechte-Eskalation); eine laufende Aufnahme verschiebt die Installation, bis sie abgeschlossen ist.
- **Durchgängige Screenreader-Unterstützung.** Onboarding, Verlauf, die zentralen Bedienelemente, die „Über"-Seite, der Feedback- und der Cloud-Bereich tragen jetzt Vorlese-Beschriftungen; nicht-interaktive Bilder, Formularfelder und Icon-Schaltflächen sind korrekt ausgezeichnet.

### Bug Fixes

- **Ein ausgeblendetes Overlay fängt keine Mausklicks mehr ab.** Ein unsichtbares Overlay konnte zuvor weiterhin Klicks abfangen. Beim Ausblenden — auch bei der automatischen Ausblendung nach „Fertig" — wird das native Fenster jetzt zuverlässig vom Bildschirm genommen, statt unsichtbar liegen zu bleiben.
- **Diktat geht beim schnellen Stoppen nicht mehr verloren.** Die Stopp-Pfade (manuell, automatisch bei Stille, bei totem Mikrofon) sind konsolidiert: ein totes Mikrofon bricht eine bereits laufende Transkription nicht mehr ab (das war stiller Datenverlust), und gleichzeitige Stopp-Aufrufe laufen sauber zu einem einzigen Durchlauf zusammen.
- **Eine gehaltene Tastenkombination löst genau einmal aus.** Die Auto-Wiederholung des Betriebssystems wird abgefangen, sodass ein gedrückt gehaltener Hotkey nicht mehrfach feuert.
- **Kein doppeltes Einfügen mehr auf macOS.** Ist das Einfügen bereits per CGEvent gelandet, wird der AppleScript-Fallback nicht zusätzlich ausgeführt.
- **Keine Ruckler mehr beim Öffnen durch den Modell-Scan.** Die Prüfung vorhandener Sprachmodelle läuft nicht mehr blockierend auf dem UI-Thread (insbesondere auf virtualisierten Dateisystemen), sodass Wellenform und Zeitanzeige flüssig bleiben.
- **Eine neue Aufnahme lässt sich sofort starten, während die „Fertig"-/Fehler-Anzeige noch nachläuft** — der Auslöser reagiert nicht mehr verzögert, solange das Overlay noch sichtbar ist.
- **Das Overlay behält beim Ausblenden seine eingestellte Größe** und blendet sich nach „Fertig" zuverlässig nach 2 Sekunden aus.
- **Bei einer Neuinstallation zeigt die Verlaufs-Aufbewahrung die Voreinstellung „Standard"** statt fälschlich „Benutzerdefiniert".
- **Linux-Pakete laufen zuverlässiger.** Das Flatpak startet jetzt auf der GNOME-Runtime mit gebündelten nativen Bibliotheken; der Snap-Build entsteht unter verwalteter LXD und bringt vollständige Store-Metadaten mit.

## 1.2.39

### Bug Fixes

- **Alle 99 Whisper-Sprachen funktionieren wieder, und die automatische Spracherkennung läuft jetzt tatsächlich.** Die Store-Review meldete „nur 4 Sprachen funktionieren, Russisch kommt als Englisch heraus". Ursache waren drei gestapelte app-seitige Einschränkungen — die ausgelieferten mehrsprachigen Modelle können alle 99 Sprachen: Bei „Automatisch" wurde die Sprache durch die UI-Sprache ersetzt (die Erkennung lief nie), das Sprachfeld wurde bei der Inferenz weggelassen (Server und Deepgram fielen still auf Englisch zurück), und sowohl die Vorab-Prüfliste als auch das Einstellungs-Dropdown waren auf en/de/fr/es festverdrahtet. Jetzt wird „Automatisch" explizit übertragen, Deepgram bekommt `detect_language=true`, und Dropdown wie Whitelist nutzen den vollständigen Sprachkatalog.
- **Cloud-Transkription (Deepgram/OpenAI) funktioniert jetzt auf macOS.** Der API-Schlüssel wurde in den Einstellungen zwar angenommen, aber jede Aufnahme scheiterte nach ~100 ms mit der generischen Fehlermeldung. Ursache: `flutter_secure_storage` schrieb in den macOS-Data-Protection-Schlüsselbund, der ein Entitlement verlangt, das der nicht-sandboxed Build nicht mitbringt — der Schlüssel landete nie im Schlüsselbund, und die Cloud-Transkriber sahen stets einen leeren Schlüssel. Die Ablage nutzt jetzt den dateibasierten Login-Schlüsselbund; Cloud-Authentifizierungsfehler werden zudem klar gemeldet.
- **Cloud-Anbieter lassen sich ohne lokales Sprachmodell nutzen.** Die Vorab-Prüfung verlangte fälschlich auch bei Deepgram/OpenAI den lokalen `whisper-server` und ein heruntergeladenes Modell, und der lokale Server wurde bedingungslos hochgefahren — reine Cloud-Nutzer konnten so nie eine Aufnahme starten. Die Cloud-Vorab-Prüfung prüft jetzt den konfigurierten API-Schlüssel (scheitert früh statt erst nach dem Diktat) und überspringt das Hochfahren des lokalen Servers.
- **Ein beschädigtes oder zu kleines Sprachmodell lädt sich automatisch still neu.** Beim Start wird eine fehlerhafte Modelldatei jetzt — wie schon bei einer SHA-Abweichung — automatisch erneut heruntergeladen, statt nur gelöscht zu werden und auf die Einstellungen zu verweisen.

### Features

- **Linux-Desktop-Unterstützung: der Sprachserver für Linux x64 wird automatisch beschafft.** Das ausgelieferte Manifest enthält jetzt einen echten `linux/x64/cpu`-Eintrag (statisch gelinkt, läuft auf jeder glibc-Distribution); eine Linux-Installation lädt, entpackt und startet den `whisper-server` über den bestehenden Selbst-Download-Mechanismus — Diktat funktioniert wie unter Windows/macOS. Begleitend stehen Linux-Pakete als Flatpak, Snap, AppImage und `.deb` bereit.
- **Neuer Einstellungsbereich „Grafikbeschleunigung" (Automatisch / Ein / Aus).** Eine bewusste Nutzer-Vorgabe hat jetzt Vorrang vor der automatischen GPU/CPU-Wahl des Sprachdienstes.
- **Problematische ältere Grafikkarten gehen schon vor dem Start auf die CPU.** Bekannt heikle GPUs (Kepler/Fermi, alte AMD-GCN) werden proaktiv auf den CPU-Pfad geleitet, statt erst nach einem Absturz zurückzufallen; unpassende Flash-Attention wird aktiv abgeschaltet.
- **Sanftere Reaktion auf kurze Aussetzer des Sprachdienstes.** Ein vorübergehendes Zucken der Lebendigkeitsprüfung erzwingt keinen vollständigen Neustart mehr (begrenzte Wiederholung mit Karenz); ein echter Hänger löst weiterhin genau einen Neustart aus.
- **Selbst heruntergeladene `whisper-server`-Binärdateien werden per SHA-256 geprüft.** Bei einer Abweichung wird das Artefakt verworfen und ein sauberer Fehler gemeldet, statt eine beschädigte Binärdatei zu starten.
- **Eigene Leer-Zustände für die Verlaufsfilter (Favoriten / Heute / Diese Woche).** Ein leerer Filter zeigt jetzt einen passenden Hinweis, statt den Eindruck zu erwecken, der gesamte Verlauf sei verschwunden.
- **Verwaiste `.tmp`-Fragmente abgebrochener Modell-Downloads werden aufgeräumt.** Beim Start und nach abgeschlossenem Download werden alte Fragmente konservativ entfernt; fortsetzbare Downloads bleiben unangetastet.

## 1.2.38

### Bug Fixes

- **Diktat geht nicht mehr verloren, wenn eine Aufnahme schnell wieder gestoppt wird.** Beim Stoppen konnte ein noch laufender, nicht abgewarteter Schreibvorgang den WAV-Header mit Null-Größen zurücklassen; der Sprachdienst lehnte eine solche Datei mit `HTTP 400 „Invalid request"` ab und die Transkription ging verloren (`FLUTTER_WHISPASTE-7X`). Die Aufnahme-Pipeline serialisiert die Schreibvorgänge jetzt und repariert vor der Inferenz fehlerhafte RIFF/data-Größenfelder.
- **GPU-Sprachserver landet nicht mehr in einer cuda↔vulkan-Endlosschleife, sondern fällt zuverlässig auf die CPU zurück (alte NVIDIA-Karten).** Ein per Recovery installierter Vulkan-Build wurde auf einer cuda-optimalen Karte fälschlich als inkompatibel gelöscht und der abstürzende cuda-Build erneut geladen — die Recovery erschöpfte sich, ohne je den CPU-Build zu versuchen (`FLUTTER_WHISPASTE-A0`). Kompatibilität heißt jetzt „auf dieser Maschine lauffähig", nicht „optimal"; gewollte Downgrades bleiben bestehen.
- **Der ausgelieferte CPU/BLAS-Fallback wird auf Vulkan-optimalen Maschinen nicht mehr bei jedem Start gelöscht.** Eine DLL-Heuristik stufte einen CPU-Floor-Build ohne `.server-info.json` (unter MSIX beobachtet) als inkompatibel ein und löste denselben Lösch-→-Neudownload-→-Crash-Kreis aus. Die Heuristik unterscheidet jetzt CPU-Floor- von GPU-Builds.
- **Stille und Hintergrundgeräusche fügen keine Platzhalter mehr in den Text ein.** Tags wie `[Musik]`, `[BLANK_AUDIO]` oder `[Applause]` werden vor dem Einfügen/Speichern entfernt; ein reiner Marker-Text wird korrekt als leere Transkription behandelt. In Klammern diktierter Text bleibt unangetastet.
- **Hinweise bei fehlendem Sprachmodell oder Sprachdienst sind jetzt anklickbar.** Die zuvor passiven Hinweis-Toasts („in den Einstellungen herunterladen") tragen jetzt eine „Einstellungen öffnen"-Aktion, die direkt zum richtigen Bereich springt.
- **Einheitliche Bezeichnung „Sprachdienst" in der gesamten Oberfläche.** Die zuvor vermischten Begriffe „Sprach-Engine", „Sprachmodul" und „Sprachdienst" sind vereinheitlicht (EN: „speech service"); der Modell-Schritt im Onboarding spricht korrekt vom „Sprachmodell".
- **Doppelte Überschrift im Bereich „Nach der Transkription" entfernt.** Die Aktions-Auswahl wiederholte den Sektionstitel wörtlich; sie trägt jetzt ein eigenes „Aktion"-Label.
- **Toter Apple-Store-Bewertungslink entfernt.** Bewerten-Pfad ist jetzt plattformgerecht (Windows-Store-Link bzw. GitHub-Stern), ohne strukturell ungültige `apps.apple.com`-URL.

### Features

- **Neue Installationswege: Scoop, winget und Homebrew.** Zusätzlich zum Installer und der Microsoft-Store-Variante stehen jetzt Paketmanager-Manifeste für Scoop, winget (Windows) und Homebrew-Cask (macOS) bereit; die Download-Seite dokumentiert die Scoop-Installation.
- **Das eigenständige Diagnose-Werkzeug listet jetzt alle Installations-Datenpfade nebeneinander.** Koexistieren eine EXE-Installation und eine oder mehrere MSIX-`LocalCache`-Installationen, zeigt der Report jeden gefundenen Datenpfad mit Variantenbezeichnung, statt stillschweigend einen auszuwählen.
- **Einmalige, idempotente Datenmigration für den Bundle-ID-Wechsel.** API-Schlüssel und Einstellungen werden beim ersten Start einmalig übernommen, ohne vorhandene Daten zu überschreiben.
- **Onboarding passt sich der Auto-Einfügen-Unterstützung an.** Auf Builds ohne automatisches Einfügen entfallen die nicht zutreffenden Auto-Einfügen-/Bedienungshilfen-Schritte.

## 1.2.37

### Bug Fixes

- **Der Sprachdienst startet jetzt auch in der Microsoft-Store-Variante (MSIX) zuverlässig — das Sprachmodell wird gefunden, statt mit „kann nicht geöffnet werden" zu scheitern (alte NVIDIA-Karten, z. B. GeForce GTX 650).** In der gepackten Store-Variante schreibt WhisPaste Modell und `whisper-server` nach `%APPDATA%\WhisPaste\models\stt`; die MSIX-Laufzeit leitet diese Schreibzugriffe transparent in den paket-eigenen `LocalCache` um. Der **als Kindprozess gestartete `whisper-server` erbt diese Umleitung jedoch nicht** — er löst denselben Pfad gegen das **un-virtualisierte, leere** echte Roaming-Verzeichnis auf und bricht mit Exit-Code 3 ab (`ggml_backend_load_best: search path … does not exist` / `failed to open`), obwohl die App die Datei als vorhanden und SHA-256-geprüft sieht (`FLUTTER_WHISPASTE-A0`). Neu: Die an den Kindprozess übergebenen Pfade (Modell-Argument, Start-Pfad und Arbeitsverzeichnis) werden vor dem Start auf den **physischen** Paketpfad `%LOCALAPPDATA%\Packages\<Paketname>\LocalCache\Roaming\WhisPaste` umgeschrieben, sodass Eltern- und Kindprozess dieselbe Datei auflösen. Die Ablage bleibt unverändert (kein erneuter Download), die Umschreibung ist außerhalb von Windows/MSIX wirkungslos. Damit war die GTX-650-Odyssee aus v1.2.32–v1.2.36 zuletzt nicht GPU- oder DLL-bedingt, sondern reine MSIX-Pfad-Virtualisierung.

### Features

- **Neues plattformübergreifendes Diagnose-Werkzeug (Dart-nativ) löst das alte Skript-basierte Tool ab.** Der eigenständige Sprachdienst-Report wird jetzt aus einer geteilten Pure-Dart-Kernbibliothek erzeugt — unter Windows als `dart compile exe`-Binary, unter macOS als `.app`/DMG — statt aus dem bisherigen Windows-only PowerShell-Skript. Der Report deckt zusätzlich Hardware-, Berechtigungs-, AV-/Quarantäne- und Einstellungs-Proben, eine DLL-Abhängigkeitsanalyse mit Fingerprint-Zuordnung sowie eine automatische Bewertung ab und durchläuft einen durchgängigen Privacy-Sanitizer (Pfade/Benutzernamen). Auslieferung ohne Backend: Der Report wird im Dateimanager angezeigt und eine vorbefüllte Mail geöffnet.

## 1.2.36

### Bug Fixes

- **GPU-Sprachserver fällt jetzt schon *vor* dem Start auf die CPU zurück, wenn die nötige System-Bibliothek fehlt (alte NVIDIA-Karten, z. B. GeForce GTX 650).** Die GPU-Builds von `whisper-server` linken die GGML-Backends zwar statisch, importieren aber zur *Ladezeit* einen System-Loader, den der Grafiktreiber mitbringt — der Vulkan-Build `vulkan-1.dll`, der CUDA-Build die CUDA-Runtime. Diese liegt nicht im ZIP. Auf einer Maschine, deren Treiber den Loader nie installiert hat und die der Varianten-Router auf Vulkan leitet (Kepler-GTX-6xx), bricht der Prozess deshalb mit `STATUS_DLL_NOT_FOUND` (`0xC0000135`) **ab, bevor `main()` läuft** — `--no-gpu` kann das nicht verhindern, weil der OS-Loader den Import auflöst, bevor das Flag gelesen wird (`FLUTTER_WHISPASTE-A0`). Neu: Ein Pre-Launch-Gate prüft unter Windows die Loader-DLLs der installierten Variante (Binary-Ordner + `System32`, analog zur VC++-Runtime-Prüfung) und übergibt einen fehlenden Loader an `ServerBinaryRecovery`, das **vor** dem Crash auf den abhängigkeitsfreien CPU-Build wechselt — statt erst post-mortem über den Exit-Klassifikator zu recovern. Ein Windows-Smoke-Test hat bestätigt, dass das Arbeitsverzeichnis nie der Blocker war (das Modell lädt auch mit `cwd=System32`).

### Features

- **In-App-Diagnose („Debug-Infos kopieren") liefert jetzt einen vollständigen Sprachdienst-Dump inklusive echtem Modell-Lade-Test.** Der Dump erfasst den STT-Failure-State und probt den Modell-Load real, statt nur Metadaten zu sammeln — die wichtigste Information, um einen Startfehler aus der Ferne zu diagnostizieren.
- **Eigenständige Sprachdienst-Diagnose-Tools für Windows und macOS, an jedes Release angehängt.** Nutzer ohne lauffähige App können einen Debug-Report erzeugen: unter Windows als Standalone-`.exe` (plus AV-sicheres Skript-Bundle), unter macOS als doppelklickbares `.command` im DMG.
- **Diagnose-Anleitung auf der Download-Seite** führt Schritt für Schritt durch das Erstellen und Teilen eines Sprachdienst-Reports.

## 1.2.35

### Bug Fixes

- **Hängende GPU-Sprachserver fallen jetzt auf die CPU zurück, statt in einer Sackgasse zu enden (alte NVIDIA-/AMD-Karten, z. B. GeForce GTX 650).** Die v1.2.32–v1.2.34-Fixes haben den CPU-Fallback an *Prozess-Exit-Codes* gehängt (`gpuFatal`/`heapCorruption`/abnormaler Exit). Auf einer Kepler-Karte stürzt der Vulkan-Build aber nicht zwingend ab — er **initialisiert vollständig (Modell geladen, alle Compute-Buffer allokiert) und macht dann keinen Fortschritt mehr**. Ein Hang erzeugt keinen Exit-Code, deshalb griff keiner der Exit-Code-Arme, und der `SttServerStateNotifier` lief über den Heartbeat-Timeout (`stt_heartbeat_timeout`) bzw. die Startup-Deadline (`stt_startup_deadline`) direkt in den `error`-State — der funktionierende CPU-Build wurde nie versucht (`FLUTTER_WHISPASTE-9W`). Neu: Beide Stall-Pfade lösen jetzt — wie die Exit-Code-Arme — den einmaligen CPU-Fallback aus und starten den Sprachserver sofort im CPU-Modus neu, abgesichert durch `gpu.hasGpu` (auf reinen CPU-Maschinen bleibt es korrekt beim Fehler, ohne sinnlosen Neustart) und durch `_gpuFallbackActive` gegen Schleifen. Damit erreicht der GTX-650-Fix endlich auch den Hang-Fall, den die bisherigen Exit-Code-Fixes offenließen.
- **Erwartete Netzwerkfehler bei Update-Check und Server-/Modell-Download erzeugen keine Sentry-Events mehr.** Der Update-Check, der Manifest-Loader und der Download-Client laufen best-effort gegen Drittanbieter-Endpunkte, deren Fehler erwartet und bereits sauber behandelt sind (Fehler-State, Failover-Kette bzw. eigene fingerprinted Captures). Der `addSentry()`-Interceptor hat trotzdem jeden 5xx automatisch als Sentry-Event erfasst (Default-Range 500–599) — nutzloses Rauschen, das Free-Tier-Quota verbrennt und Download-Fehler doppelt meldete, entgegen der dokumentierten Absicht (`FLUTTER_WHISPASTE-72`). `captureFailedRequests` ist auf diesen Clients jetzt deaktiviert; Tracing-Spans und Breadcrumbs bleiben erhalten.

## 1.2.34

### Bug Fixes

- **Auf alten NVIDIA-Karten (z. B. GeForce GTX 650) sagt die App jetzt klar, was fehlt, statt in einer Sackgasse zu enden.** Der v1.2.33-Fix hat den „Incompatible whisper-server"-Löschloop beendet — die Recovery bleibt nun dauerhaft auf dem CPU-Build. Damit wurde aber ein Folgefall sichtbar: Der ausgelieferte CPU-Build ist das Upstream-Asset `whisper-blas-bin-x64`, dessen Binaries dynamisch gegen die Microsoft-Visual-C++-Runtime linken — `whisper-server.exe` braucht `MSVCP140`/`VCRUNTIME140`/`VCRUNTIME140_1`, und `ggml-cpu.dll` zusätzlich die OpenMP-Runtime `VCOMP140.DLL`. Keine davon liegt im ZIP; sie stammen aus dem Visual C++ Redistributable, das auf vielen älteren/frischen Windows-Installationen fehlt (gerade die OpenMP-DLL). Folge: Der CPU-Server bricht mit `STATUS_DLL_NOT_FOUND` (`0xC0000135`) ab, die Recovery ist erschöpft, der Nutzer hängt fest (`FLUTTER_WHISPASTE-A0`). Neu: `ServerBinaryRecovery` erkennt einen `dllMissing`-Abbruch des CPU-Floors als fehlende VC++-Runtime und zeigt einen **actionable Toast** mit „Installieren"-Button, der den Download des **Visual C++ Redistributable (x64)** öffnet — statt der nutzlosen „App neu starten"-Meldung. Das Sentry-Event trägt jetzt ein `vc_runtime_missing`-Flag für eindeutige Triage.
- **Der CPU-Fallback wird künftig self-contained ausgeliefert (Vorbereitung).** Ein neuer CI-Job `build-cpu-windows` packt das Upstream-BLAS-Asset zu `whisper-server-cpu-x64.zip` um und bündelt die vier benötigten Runtime-DLLs (`vcomp140`, `vcruntime140`, `vcruntime140_1`, `msvcp140`) app-local mit; das Manifest zeigt den `cpu`-Eintrag dann auf dieses eigene Artefakt statt auf das bare Upstream-ZIP. Wirksam nach dem nächsten `build-whisper-server`-Lauf, der das Manifest neu generiert — danach heilt sich der CPU-Floor auf jeder Maschine ohne separate Redist-Installation.

## 1.2.33

### Bug Fixes

- **Sprachserver bleibt jetzt dauerhaft auf der CPU-Variante, wenn die GPU-Builds nicht starten (alte NVIDIA-Karten, z. B. GeForce GTX 650).** Der v1.2.32-Fix hat das Backend-Routing korrigiert, aber ein Restfall blieb: Auf einer Kepler-Karte bricht selbst der Vulkan-Build beim Model-Load ab (Exit-Code `3`), woraufhin `ServerBinaryRecovery` korrekt auf den **CPU-Build** zurückfällt und `backend=cpu` in die `.server-info.json` schreibt. Beim nächsten Start meldete der proaktive Kompatibilitäts-Check jedoch „installiert=`cpu`, GPU braucht aber `vulkan`", **löschte genau das eine lauffähige Binary** und warf „Incompatible whisper-server for your GPU" — eine Endlos-Schleife aus Recovery → CPU → Löschen → Re-Download → Crash, die auch durch Neuinstallation + komplettes Onboarding nicht zu beseitigen war (`FLUTTER_WHISPASTE-80`). Ursache war ein Konflikt zweier Subsysteme: Die Recovery wählt CPU bewusst als universellen Fallback, der proaktive Check wertete „CPU auf einer GPU-fähigen Maschine" aber als Fehlkonfiguration. Neu: `isServerBinaryCompatible` behandelt einen CPU-Build als **universell kompatibel** — er läuft auf jeder Hardware und ist der absichtliche Recovery-Endzustand, wird also nicht mehr gelöscht. Damit bricht die Schleife endgültig; betroffene Geräte transkribieren auf der CPU (langsamer, aber funktionsfähig). Wer GPU-Beschleunigung erneut versuchen will, kann den Sprachserver in den Einstellungen neu herunterladen.
- **Echter Hardware-/Treiber-Wechsel führt jetzt zum stillen Self-Heal statt zur Sackgasse.** Findet der proaktive Check ein wirklich unpassendes GPU-Binary (z. B. der STT-Ordner wurde auf eine Maschine mit anderem GPU-Hersteller verschoben), lädt er die korrekte Variante jetzt im Hintergrund nach (`invalidateServerBinary`), statt mit „re-download in Settings" abzubrechen und ein Sentry-Event zu erzeugen. Scheitert der nachgeladene GPU-Build erneut, greift die nun dauerhafte CPU-Recovery.

## 1.2.32

### Bug Fixes

- **Sprachserver startet wieder auf älteren NVIDIA-Karten (Kepler, z. B. GeForce GTX 650).** Die Backend-Auswahl behandelte bisher jede NVIDIA-Karte mit vorhandenem `nvcuda.dll` als CUDA-optimal und lud den `cuda12`-Build. CUDA 12 hat aber Fermi- (sm_2x) und Kepler-Support (sm_3x) komplett fallengelassen — auf einer GTX 6xx/7xx bricht `whisper-server` deshalb beim CUDA-Init ab: in der Praxis sofort mit Exit-Code `-1` und leerem stderr (`FLUTTER_WHISPASTE-6X`/`-39`) oder als Model-Load-Fehler mit Exit `3` (`-6V`/`-6W`). Schlimmer: selbst wenn die Recovery auf den Vulkan-Build zurückfiel, hat der proaktive Kompatibilitäts-Check beim nächsten Start gemeldet, der Vulkan-Build sei ≠ `optimalBackend` (`cuda`), ihn gelöscht und erneut `cuda12` erzwungen — eine Endlos-Schleife, die als „Incompatible whisper-server for your GPU" (`FLUTTER_WHISPASTE-80`) sichtbar wurde. Neu: eine `GpuInfo.supportsCuda12`-Heuristik (analog zu `supportsFlashAttn`) erkennt Kepler/Fermi-Karten an der Modellbezeichnung und routet sie auf den Vulkan-Build. `optimalBackend`, der `serverAssetPatterns`-Fallback und der Manifest-`WhisperBinarySelector` respektieren das jetzt durchgängig, womit die Schleife bricht und der Self-Heal-Download sofort die lauffähige Variante zieht.
- **Abnormaler Server-Crash fällt jetzt automatisch auf CPU zurück.** Ein unklassifizierter Abbruch mit negativem Exit-Code (Windows-Roh-DWORD wie `-1` oder POSIX-Signal-Kill) bei einem GPU-Start war bisher ein Sackgassen-`error`, weil die `SttGpuFallbackPolicy` nur die bekannten NTSTATUS-GPU-Fatals abdeckte. Genau diese Form trifft alte GPUs, deren GPU-Runtime gar nicht erst initialisiert (`FLUTTER_WHISPASTE-6X`/`-39`). Der `other`-Pfad im `SttServerStateNotifier` aktiviert jetzt — einmalig, abgesichert durch `_gpuFallbackActive` gegen Schleifen, und nur bei negativem Exit-Code — den CPU-Fallback (spiegelt die `gpuFatal`/`heapCorruption`-Arme). Ein sauberer positiver Exit (z. B. `99`) bleibt ein bewusster Server-Exit und surfacet weiterhin als Fehler.

## 1.2.31

### Features

- **Mikrofon-Schritt im Onboarding zeigt jetzt live, ob das gewählte Gerät dich hört.** Statt nur die TCC-Berechtigung abzufragen, lässt der neue Schritt eine kurze Probe-Aufnahme laufen, misst den realen Eingangspegel und klassifiziert das Gerät als „funktioniert / zu leise / nichts zu hören". Die Dropdown-Auswahl reicht denselben Geräte-Pool wie der eigentliche Recorder durch — was im Onboarding ausgewählt wird, ist auch das Gerät, das später aufnimmt. Greift Hand in Hand mit dem zweiten Teil: `AVAudioEngine.inputNode.auAudioUnit.setDeviceID()` wird unter macOS 15/26 stillschweigend ignoriert, sodass die User-Auswahl bisher nie beim Recorder ankam und jede Aufnahme auf den System-Default (oft ein Bluetooth-Headset) zurückfiel. Ein direkter Wechsel zu `AVCaptureSession` hätte die HAL exklusiv blockiert und die SoLoud-Aufnahme-Chimes erstickt. Die Lösung folgt dem Logic/Audacity/OBS-Pfad: ein neuer `AudioRoutingHost`-Swift-Bridge flippt unmittelbar vor jeder Aufnahme das CoreAudio-Default-Input-Gerät auf die User-Wahl und stellt beim Stoppen den Originalwert wieder her. Eine Settle-Poll auf der Default-UID-Property garantiert, dass AVAudioEngine an ein live-bereites Device bindet statt an eines, das noch aus dem Power-Save hochfährt.
- **Auto-Paste-Onboarding-Schritt komplett umgebaut auf One-CTA-pro-Phase.** Der macOS-Schritt rendert bisher bis zu vier Karten gleichzeitig (Status, Polling-Hinweis, TCC-Mismatch-Banner, Repair-Panel) in tech-lastiger Sprache („Bedienungshilfen-Berechtigung erteilen", „TCC-Cache stale", „Reparieren"). Der In-App-Selbsttest mit `TextField` war zusätzlich unzuverlässig, weil Flutter den synthetisierten ⌘V aus dem eigenen Prozess nicht stabil empfing — der „Beweis es funktioniert"-Schritt feuerte manchmal Success, während das Demofeld leer blieb. Die neue Phase-State-Machine (`checking / granted / intro / waiting / troubleshoot`) wird aus dem bestehenden `PasteCapabilityState` abgeleitet und rendert je Phase genau eine primäre Action. Das TCC-Mismatch-Banner bekommt eine eingebettete „WhisPaste neu starten"-CTA, die über einen neuen `restart`-Hook auf dem App-Lifecycle-MethodChannel einen Detached-Shell-Helper anwirft — der wartet den Exit des aktuellen Prozesses ab und öffnet das Bundle neu, sodass macOS den Accessibility-Trust gegen eine frische PID statt gegen den toten Eltern-Prozess auswertet. Die DE/EN/HE-Strings sind auf den Schreibfluss-Audience-Tonfall umgeschrieben („Jetzt freigeben / Eintrag zurücksetzen / WhisPaste hat das Häkchen nicht erkannt"), und das `diagnosticPaste` darf jetzt gegen die echte aktive App testen — der Self-Paste-Guard ist raus, das Pasteboard-Restore-Fenster auf 300 ms verbreitert.

### Bug Fixes

- **Sprachserver-Download im Onboarding läuft wieder durch.** Bis v1.2.30 hat der `WhisperServerDownloader` die GitHub-Releases-API mit `per_page=20` befragt und den `whisper-server-*`-Tag per Substring-Match in der Asset-Liste gesucht. Sobald genug eigene `v1.2.x`-App-Releases akkumuliert waren, fiel der whisper-server-Tag aus Seite 1 raus, das Lookup lieferte `null`, und der User sah im Onboarding nur das nichtssagende „Could not download whisper-server.". Der neue Pfad ist Manifest-getrieben: `assets/whisper-server-manifest.json` ist die alleinige Wahrheitsquelle (schema_version, whisper_server_tag, whisper_cpp_release, plus ein Eintrag je platform/arch/backend-Binary). Ein `WhisperServerManifestLoader` läuft eine dreistufige Failover-Kette durch (raw.githubusercontent.com → release-asset-URL aus dem gebündelten Tag → mitgeliefertes Asset), sodass Onboarding offline benutzbar bleibt. Ein deterministischer `WhisperBinarySelector` macht den Platform+Arch+Vendor-Lookup; Lücken (z. B. macOS x64, Linux) werden mit konkretem Grund gemeldet statt generisch zu crashen. `build-whisper-server.yml` regeneriert das Manifest aus den frisch hochgeladenen Release-Assets, hängt es ans Release und committet es nach `main`, damit die Raw-URL stabil aktuell bleibt.

### Stability (internal)

- **Windows-CI-Flake im Recovery-Toast endgültig zugedreht.** Der `stt_exit_classifier_test`-Lauf war auf Windows intermittierend rot mit „failed after test completion": die Test-Bodies erreichten grün, aber ~2 s später feuerte ein Async-Leak in den bereits disposed Riverpod-Container. Ursache war `_attemptRecovery` in `SttServerStateNotifier`, das nach mehreren `await`s `ref.read(recoveryToastNotifierProvider.notifier)` aufrief, ohne den `ref.mounted`-Status zu prüfen — der parallel sitzende `ref.invalidate`-Call in `_restartAfterRecovery` hatte den Guard längst, der Toast-Push war die letzte ungeschützte Stelle. Der Push ist jetzt durch das gleiche `if (ref.mounted)` umschlossen. Produktionsverhalten unverändert (disposed Container = UI ist eh weg = Toast unterdrücken ist korrekt), aber der Post-Completion-Callback berührt keinen toten Scope mehr.
- **Widget-Tests gegen ARB-Reworking immunisiert.** Die 23 Auto-Paste-Failures, die v1.2.30 in CI brockten, lagen daran, dass die Tests UI-Labels als Literal-Strings (`'Allow now'`, `'Reset entry'`, `'Skip — disable Auto-Paste'`, …) hartcodiert hatten — jede ARB-Umformulierung brachte die Suite still zum Bruch. Sechzehn Test-Dateien sind jetzt auf `find.text(l10n.<key>)`-Lookups via geladenen `L10n`-Snapshot umgestellt und pinnen ihre Locale explizit auf `en` (bzw. `de`/`en`-Paare für die multi-locale-Toast-Tests), sodass weder der CI-Runner-Default-Locale noch ARB-Rewordings die Tests stillschweigend brechen können. Ein Key-Rename in der ARB schlägt jetzt als Compile-Fehler durch; ein Value-Rewording bleibt unsichtbar. Test-Daten (Sample-Entry-Titel, Device-Namen, Harness-Strings wie `'Open picker'`) bleiben absichtlich Literal-Strings, weil sie nie durch Lokalisierung laufen.

## 1.2.30

### Stability (internal)

- **Windows-CI-Flake im STT-Notifier nachhaltig behoben.** Zwei Stellen in `SttServerStateNotifier` (`_start` und `_handleModelLoadFailure`) riefen `hw.detectGpu()` direkt auf und liefen damit am Riverpod-Override für `gpuInfoProvider` vorbei, den alle betroffenen Tests bereits gesetzt hatten. Auf dem Windows-Runner führte das pro Testlauf die echten WMI/PowerShell-GPU-Probes aus — mit zwei Folgen: erstens leakte ein verspätetes `gpuDetectionFailed`-Sentry-Event in die Capture-Count-Assertions von `stt_inference_capture_test`, weil der Detector aus dem „windows-vendor-unclassified"-Pfad noch nach dem `_capturedEvents.clear()` feuerte; zweitens lief der Recovery-Test gegen die 200-ms-Timing-Fenster, weil `clearGpuCache()` + Re-Detect den zweiten `runner.start()`-Spawn nicht mehr rechtzeitig zuließ. Beide Call-Sites gehen jetzt durch `await ref.read(hw.gpuInfoProvider.future)` (gleiches Pattern wie der Benchmark-Pfad in Zeile 767), und `_restartAfterRecovery` invalidiert den Provider parallel zum modul-internen Cache. Produktionsverhalten unverändert — gleiches Caching, gleiche Re-Detection nach Recovery — aber die Tests sehen auf dem Windows-Runner jetzt deterministisch ihr Fake-`GpuInfo` statt der echten Hardware-Probes.

## 1.2.29

### Stability (internal)

- **Hardware-spezifische Crashes sind jetzt im Sentry diagnostizierbar.** Vier Pfade, die bisher entweder gar nicht oder im `appLoggerAutoEscalated`-Catch-all gelandet sind und damit pro Crash unbrauchbare Generika produziert haben, haben jetzt eigene Fingerprints und reichen den vollständigen Hardware-Kontext mit: `sttCudaOom` (CUDA-OOM im whisper-server — mit GPU-Name, VRAM, Modell + Soll-VRAM, stderr-Tail), `sttInferenceConnectionLost` (SocketException/ClientException während Inference — Modell, Port, WAV-Größe, GPU-Modus), `sttStartupDeadline` (absolute Wall-Clock-Deadline im Startup-Loop, fängt die Long-Load-Form ab, die das Heartbeat-Fenster allein nicht beenden kann), und `gpuDetectionFailed` (GPU-Probes liefern beide nichts — typisch corporate AV / gesperrte WMI). Der GPU-Detection-Capture hat einen Once-per-Session-Guard plus Re-Arm via `clearGpuCache`, damit Sentry bei einem Recovery-Restart die Wiederholungsblindheit sieht statt von der Erstdetektion erstickt zu werden.
- **Architektur-Tag in Sentry zeigt jetzt die echte CPU-Architektur.** Das alte `_currentArch()` war eine Compile-Time-Konstante (`0x7FFFFFFFFFFFFFFF > 0`), die auf jeder Plattform `'x64'` zurückgab — auch auf Apple Silicon. Der neue `currentArchTag()` aus `dart:ffi`-`Abi.current()` liefert `arm64` / `x64` / `x86` / `arm` / `riscv64` / `riscv32` korrekt, was Hardware-Cluster-Filter in Sentry endlich brauchbar macht. Wirkt sowohl auf das `dist`-Feld als auch auf das `arch`-Scope-Tag.
- **Dedup-Migration der heißen STT-Pfade.** Acht `_log.error`-Stellen in `SttServerStateNotifier` (GPU-Fatal-Capture, Heap-Korruption-Capture, Other-Exit-Capture, Recovery-Exhausted, ABI-Mismatch-Pfad, Modell-Korruption, sub-optimaler Binary-Detect-Check) lagen jeweils unmittelbar vor oder nach einem expliziten `captureError` — die zusätzliche Auto-Eskalation hat denselben Vorfall doppelt nach Sentry geschickt, einmal mit dem richtigen Fingerprint und einmal im Catch-all. Die Stellen sind jetzt auf `_log.warning` heruntergestuft; die Modell-Korruption (zuvor nur via `_log.error`) bekommt ihren eigenen `sttModelCorrupted`-Capture mit Datei-Größe und Modell-ID. Im Schnitt halbiert sich damit das Sentry-Event-Volumen je harter Sprachdienst-Störung, ohne Diagnose-Information zu verlieren.
- **`SttStartupHeartbeatConfig` als Value-Object statt Record-Type.** Provider-Typ ist jetzt eine Klasse mit Defaults (`window: 60 s`, `maxMissedWindows: 3`, `overallDeadline: 180 s`), damit der hinzugefügte Wall-Clock-Cap nicht jeden Test bricht. Alle 28 Test-Stellen, die das frühere `({Duration window, int maxMissedWindows})`-Record-Literal benutzten, sind 1:1 auf den Konstruktor migriert.

## 1.2.28

### Bug Fixes

- **Feedback-Funktion läuft wieder durch — Schema-Drift im Supabase-Backend behoben.** Zwischen dem 21. April und 27. Mai schlug jede Feedback-Übermittlung serverseitig fehl: die `locale`-Spalte fehlte im produktiven Schema, und der `enforce_feedback_defaults`-Trigger griff auf ein nie existierendes `user_agent`-Feld zu, sodass PostgREST jeden INSERT mit HTTP 400 abwies, bevor die RLS-Prüfung überhaupt griff. Die ausstehenden Migrations (`20260418_add_feedback_locale`, `20260421_fix_security_advisor_findings`, `20260512_cleanup_edge_function_artifacts`, `20260513_cleanup_legacy_artifacts`) sind jetzt deployed — Feedback aus bereits installierten Clients der Versionen 1.2.0+ kommt sofort wieder durch, ohne dass Nutzer ein App-Update brauchen. End-to-End mit echtem Client-Payload verifiziert: HTTP 201, alle server-seitig erzwungenen Felder (id, received_at, status, ip_hash aus x-forwarded-for) korrekt befüllt, RLS-Constraints + Device-/IP-Rate-Limits unverändert wirksam.

### Stability (internal)

- **Server-Fehler im Feedback-Pfad eskalieren jetzt aktiv nach Sentry.** Bisher hat der `FeedbackSubmissionService` ein Backend-Problem nur als Breadcrumb mit `result: server_error` gemeldet — Breadcrumbs verschwinden mit der Session, wenn der Lauf nicht zusätzlich crasht. So konnte die fünfwöchige Schema-Drift unbemerkt durchlaufen, obwohl jeder Submit ein HTTP 400 produzierte. `FeedbackServerError` löst jetzt zusätzlich `Sentry.captureMessage('feedback_server_error', warning)` mit Status-Code und auf 500 Zeichen gekürztem Response-Body als strukturiertem `feedback_response`-Context aus. Rate-Limit-, Netzwerk- und Not-Configured-Pfade bleiben absichtlich nicht-eskaliert, damit nutzergetriebenes Verhalten den Sentry-Posteingang nicht zumüllt. Die deprecated `scope.setExtra`-API wurde gleich auf `scope.setContexts` migriert (sentry_flutter 9.x).
- **Supabase-Migrations-History an das tatsächlich angewendete Remote-Schema angeglichen.** Zwei manuelle SQL-Editor-Sessions am 03. Mai hatten `schema_migrations`-Einträge mit voller Sekunden-Timestamp-Präzision (`20260503093151`, `20260503102718`) hinterlassen, während die Repo-Dateien nur den Tagespräfix (`20260503_…`) trugen — `supabase migration list` markierte die Remote-Zeilen als Waisen und `db push` brach mit „Remote migration versions not found in local migrations directory" ab. Die Dateien sind jetzt auf die vollen Timestamps umbenannt; History reconciled ohne destruktiven `migration repair --status reverted`.

## 1.2.27

### Features

- **Konkrete Toasts statt „Etwas ist schiefgelaufen" bei untauglichen Aufnahmen**. Offensichtlich nicht-transkribierbare Anfragen (leeres WAV, kaputter Header, nicht-unterstützte Sprache, zu langes Eigenvokabular) werden jetzt vor dem POST an den Sprachserver erkannt und mit dem passenden Klartext-Hinweis abgewiesen — der Nutzer sieht z. B. „Aufnahme leer" oder „Sprache nicht unterstützt", statt die Antwortzeit eines Sprachserver-Rundlaufs samt generischer Fehlermeldung abzuwarten. Sentry erfasst diese Fälle nur noch als Breadcrumb, nicht mehr als Crash-Event.

### Bug Fixes

- **Doppelte Crash-Reports bei fehlgeschlagener Sprachserver-Antwort beseitigt**. Fehlerhafte Inference-Antworten (4xx/5xx vom lokalen whisper-server) wurden bisher sowohl über den expliziten `captureError`-Pfad als auch über die `_log.error`-Auto-Eskalation an Sentry geschickt — pro Inference-Fehler landeten also zwei Events in zwei verschiedenen Issue-Gruppen. Der Orchestrator loggt diesen Pfad jetzt als Warning, und der zentrale Capture (mit stabilem Fingerprint pro Statuscode + PII-bereinigtem Body) sitzt direkt im STT-Notifier. 5xx-Antworten ziehen außerdem nicht mehr die ServerBinary-Recovery in den Pfad — die war für Crash-Exit-Codes gedacht, nicht für HTTP-Fehlerantworten. Im Ergebnis kollabiert die bisherige Sentry-Issue-Streuung pro Inference-Fehler auf genau eine Gruppe je HTTP-Statuscode.

### Stability (internal)

- **Pre-Flight-Validator + HTTP-Klassifikator für die Inference-Pipeline**. Neuer `InferenceRequestValidator` prüft jede Aufnahme deterministisch (leere Bytes → invalider WAV-Header → nicht-unterstützte Sprache → zu langes Prompt) gegen eine versiegelte Result-Klasse; neuer `InferenceErrorClassifier` mappt whisper-server-HTTP-Antworten auf die zentrale Fingerprint-Tabelle (400 / 413 / 415 / 5xx / unknown) mit PII-bereinigtem Body (Unix-, Windows-, UNC-Pfade → `<path>`) und sechs Request-Kontext-Extras. Beide sind reine, abhängigkeitsfreie Value-Klassen, werfen keine Exceptions und sind zusammen mit der Notifier-Integration durch 1 229 neue Test-Zeilen abgedeckt.

### Dependencies

- **App-Stack-Patches**: `record` 6.2.0 → 6.2.1 plus die fünf Plattform-Companions (`record_android`, `record_ios`, `record_linux`, `record_macos`, `record_platform_interface`); `flutter_secure_storage` 10.2.0 → 10.3.0 (+ darwin/linux-Begleiter); `lucide_icons_flutter` 3.1.14+1 → 3.1.14+2; sechs transitive Dart-Pakete (`built_value`, `url_launcher_android`/`_web`, `vector_graphics`(`_compiler`), `vm_service`). Alle Bumps reine Patch-/Build-Updates, keine API-Änderungen — volle Test-Suite (1 775) grün, macOS-Debug-Build grün.
- **Website-Stack-Patches**: `astro` 6.3.3 → 6.3.8, `@astrojs/sitemap` 3.7.2 → 3.7.3, `@sentry/astro` 10.53.1 → 10.54.0 (entfernt 42 OTel-Auto-Instrumentation-Pakete aus dem Build — Free-Tier-positiv, da statische Marketing-Site), `dompurify` 3.4.5 → 3.4.6, `vitest` 4.1.6 → 4.1.7 (+ sieben `@vitest/*`-Companions), `@typescript-eslint/eslint-plugin` und `parser` 8.59.3 → 8.60.0, `@playwright/test` 1.58.2 → 1.60.0. Website-Gate (tsc, eslint, vitest, build, Playwright) grün.

## 1.2.26

### Bug Fixes

- **CI-Build wird wieder grün — `sqlite3`-Version explizit gepinnt**. Der v1.2.25-Build lief lokal sauber durch, aber der CI-Runner auflöste `sqlite3` auf eine ältere Major-Version (2.9.4 statt 3.3.1), weil `sentry_drift 9.20.0` einen veralteten `sqlite3: ^2.1.0`-Constraint mitschleppt, der mit dem `sqlite3: ^3.1.5`-Bedarf von `drift 2.33.0` kollidiert. Lokal blieb das durch das eingecheckte Lock-File auf 3.3.1 stabil, auf CI griff der Resolver am Lock vorbei und kippte auf 2.9.4 — dessen `SqliteException` einen anderen Konstruktor hat und damit die Coordinator-Tests beim `flutter analyze` zerlegt. `dependency_overrides: { sqlite3: ^3.3.0 }` zwingt jetzt beide Seiten auf die gleiche Major-Version. Reine Build-Hygiene — keine Verhaltensänderung an der App selbst gegenüber 1.2.25.

## 1.2.25

### Features

- **Sprachdienst erholt sich jetzt selbst nach Crashes**. Wenn der whisper-server mit einem DLL-, ABI- oder GPU-Fehler abstürzt, fällt die App jetzt automatisch eine Stufe zurück (CUDA 12 → Vulkan → CPU auf Windows, Metal → CPU auf macOS), lädt die passende Variante nach, validiert sie und fährt den Dienst neu hoch. Pro Aufnahme-Session ist ein Versuch je Variante zulässig, damit Endlosschleifen ausgeschlossen sind. Nur wenn alle Stufen scheitern, sieht der Nutzer einen Toast — sonst läuft die nächste Aufnahme einfach weiter. Auf der Fehler-Endstufe gibt es jetzt einen aktionablen Toast „Einstellungen öffnen", der direkt in den Reset-Bereich navigiert.

- **HTTP-Downloads hängen nicht mehr unbemerkt**. Ein 30-Sekunden-Stall-Detektor überwacht den Byte-Fluss bei Modell- und Server-Binary-Downloads. Wenn der Stream einfriert (kein Fortschritt, aber auch kein Abbruch — der typische schlechte WLAN-Fall), bricht die App den Versuch sauber ab und probiert die nächste Quelle. Bisher konnte der Onboarding-Download im schlimmsten Fall stundenlang stehenbleiben, ohne dass die UI das merkte. Zusätzlich sind die rohen Dio-Fehler jetzt in lesbare deutsche Texte übersetzt („Verbindung zum Server nicht möglich", „Download wurde unterbrochen") statt Stacktrace-Fragmente.

- **Fehler-Toasts haben jetzt eine sinnvolle Aktion**. Sechs typische Fehlerstellen zeigen statt des generischen „Etwas ist schiefgelaufen"-Toasts einen Knopf zur direkten Lösung: „Einstellungen öffnen" bei erschöpfter Sprachdienst-Recovery, „Erneut versuchen" bei fehlgeschlagenem Server-Download, „Diagnose kopieren" bei History-Schreibfehlern, „App schließen" bei Factory-Reset-Fehler, „Accessibility-Berechtigung öffnen" beim macOS-Auto-Paste-Pfad. Wo bisher nur ein lakonischer Hinweis stand, gibt es jetzt einen Klick zur Behebung.

- **Factory-Reset hängt nicht mehr und friert die UI nicht ein**. Der Reset-Flow wartet jetzt auf das tatsächliche Beenden des Sprachdienstes (PID-File-Polling, 10-Sekunden-Timeout, harter Kill als Fallback) statt auf einen blinden 800-ms-Sleep, und das Löschen mehrerer GB Modelle läuft in einem separaten Isolate, damit die UI flüssig bleibt. Eine modale Fortschrittsanzeige zeigt die einzelnen Phasen („Beende Sprachdienst…", „Lösche Modelle…") an, sodass der Nutzer sieht, dass etwas passiert. Bei Fehler wird die Phase benannt und einmalig in Sentry gemeldet — keine Doppelreports mehr.

### Bug Fixes

- **GPU-Erkennung hängt das Onboarding nicht mehr fest**. Die parallelen `wmic` / PowerShell-Probes auf Windows haben jetzt ein 8-Sekunden-Timeout pro Probe und laufen im Wettrennen statt seriell. Schlägt die Erkennung komplett fehl (z. B. blockierte WMI-Schnittstelle, fehlende DLL), fällt die App nun explizit auf CPU-Modus zurück und zeigt einen freundlichen Hinweis „Optimierte GPU-Beschleunigung nicht verfügbar — App nutzt CPU" — statt das System fälschlich als inkompatibel zu markieren und das Onboarding zu blockieren.

- **Doppelte Crash-Reports bei fehlgeschlagenem Server-Download beseitigt**. Der finale Fehlerlog des Modell-Downloaders wurde sowohl über die Auto-Eskalation als auch über den expliziten `captureError`-Aufruf an Sentry geschickt — pro fehlgeschlagenem Download landeten also zwei Events in zwei verschiedenen Issue-Gruppen. Die redundante Log-Eskalation ist jetzt eine Warning, sodass nur noch der explizite, korrekt fingerprintete Capture-Aufruf den Vorgang meldet.

### Stability (internal)

- **Schreibzugriffe auf die History sind jetzt serialisiert**. Alle zwölf Schreib-Methoden der lokalen SQLite-Datenbank laufen durch einen einzelnen Lock und versuchen es bei `SQLITE_BUSY` mit `[50, 100, 200]` ms Backoff erneut, bevor sie aufgeben. Damit verschwindet die Mehrheit der bisherigen „Etwas ist schiefgelaufen"-Toasts bei parallelen Schreibvorgängen (z. B. Aufnahme abschließt, während Nutzer im History-Tab löscht), und der Sentry-Cluster aus WP-7B…7M kollabiert auf ein einzelnes Signal.

- **Zentrales Crash-Fingerprint-Inventar**. Alle Sentry-Captures benutzen jetzt verpflichtend Fingerprints aus einer zentralen Inventarliste, sodass thematisch zusammengehörige Fehler sauber in eine Issue-Gruppe fallen und das Free-Tier-Kontingent nicht durch generische `Etwas ist schiefgelaufen`-Events verbrannt wird. Update-Check-Netzwerkfehler eskalieren nicht mehr nach Sentry, sondern bleiben als Breadcrumb erhalten.

## 1.2.24

### Features

- **Microphone-volume slider is back — and it actually works this time**. The slider that was removed in v1.2.23 (because it had been dead code) returns as a real control. Behind the scenes the recording path was rebuilt: audio now flows through a PCM stream pipeline that splits in-process into the WAV writer and the level meter, with an optional gain multiplier inserted whenever the slider sits anywhere other than 100 %. At 100 % nothing changes (library autoGain still acts as before, default recordings sound the same as in v1.2.23); above 100 % the user gain takes over completely and library autoGain steps aside, so the slider's effect is predictable and audible. Range is 0–300 % in 5 % steps; 0 % records silence, 200 % is roughly twice as loud, and mid-recording slider movement is deliberately ignored — the gain captured at recording start governs the whole take.

- **Clipping warning surfaces in the settings**. When the gain is pushed high enough that PCM samples hit the 16-bit ceiling, the new pipeline counts those clipped samples per recording. A subtle banner below the gain slider lights up after a recording with clipping ("Last recording had clipping — reduce gain?") so the cause of a bad transcription is visible instead of mysterious. Dismissing the banner clears the warning until the next clipping event; a clean recording also clears it automatically. No modal, no sound, no OS notification — the banner sits passively in the place you would go to react to it.

## 1.2.23

### Bug Fixes

- **Maximum recording duration setting is now respected**. The recording safety guard counted amplitude samples to enforce `maxRecordDuration`, `deadMicTimeout` and `autoStopSilence`, but used the wrong sample rate — it expected 10 Hz while the audio service emits at 25 Hz (one sample every 40 ms). All three guards therefore fired 2.5× too early: a user setting "2:30" got cut off at ~60 s, dead-mic kicked in at 1.2 s instead of 3 s, and the 90 % duration-warning sound played at ~36 % of the configured limit. The orchestrator now passes the real rate to the guard, and the guard's `samplesPerSecond` knob has been promoted to a required parameter so the mismatch cannot silently re-appear. The orchestrator behavior-snapshot tests, which had calibrated against the buggy rate and locked the bug in as spec, have been re-calibrated.

- **Microphone-volume slider removed**. The slider in Audio Input was non-functional — the value was persisted but no code path in the recording pipeline applied it. The `record` plugin has no gain parameter and no PCM multiplication ran on the stream, so changing the slider had zero effect on the captured audio. Rather than ship a fix-by-implementation that would have widened this release's scope, the dead slider has been removed; if true input-gain control is wanted later it returns as its own feature.

- **"Show notifications" preference is now honoured**. The Interface toggle was persisted but never consulted — paste-blocked and paste-failed alerts fired through `SystemAttentionService` regardless of the setting. The native notification path now checks the preference and stays silent when the user has opted out. The dock-bounce / taskbar-flash fallback stays active either way; that is the layer that surfaces problems when the main window is hidden.

## 1.2.22

### Bug Fixes

- **Auto-Paste onboarding step removed on Windows**. First-run testing revealed that the diagnostic Test-Paste sub-step was reading as "press a hotkey" — users tried to trigger their dictation shortcut instead of clicking the in-step button, then got stuck because Next stayed gated. Since Windows needs no extra permission for `SendInput`-style paste in the 99 % case, the step delivered no real value and the UIPI/UAC edge stays surfaced through the Settings paste capability indicator. Windows now follows Linux's lead and skips the step entirely, taking the onboarding from five screens to four. macOS keeps the full flow because the TCC grant + verify is the actual user task there.

- **STT spawn and exit failures are now visible in Sentry**. The whisper-server lifecycle had several failure modes that only ended up in local logs (`_fail()` into the in-process state machine) while Sentry got either nothing or a one-line message. That made FLUTTER_WHISPASTE-4P-class incidents ("exited before becoming ready") undiagnosable without direct access to a user's machine. The notifier now ships a structured `captureError` for: spawn `ProcessException` (binary path, args, errno), heartbeat timeout (stderr tail + args + binary), early process exit on the unclassified path, and the generic `SttExitKind.other` exit code now carries the stderr tail, args, model id and GPU mode in extras (the message-only capture was the shape behind FLUTTER_WHISPASTE-6X). A new `stt.stderr` breadcrumb category mirrors stderr lines that look like errors so any later event in the same session inherits the signal, not just the dedicated STT captures.

## 1.2.21

### Features

- **Onboarding gains a dedicated Auto-Paste step**. New users now hit a guided `AutoPasteStep` before reaching the Ready screen. On macOS it triggers the Accessibility prompt, polls TCC state via a `PollingPhase` controller, surfaces a "Waiting for permission…" hint card while the System Settings sheet is open, exposes a lazy "Repair permissions" button (`tccutil reset Accessibility + AppleEvents`) that only appears once the user has had a chance to grant manually, and shows a sharper TCC-mismatch banner with a restart hint when the bundle ID granted in TCC no longer matches the running app. On Windows the same step runs a verify branch that detects the UIPI edge case (elevated foreground window blocks `SendInput`) and skips cleanly with a Windows-specific explanation. The step counter at the top of the wizard is now dynamic, so users on `clipboardOnly` mode (where the Auto-Paste step is skipped) no longer see misleading "Step 3 of 4" labels. A new diagnostic-paste endpoint backs a **Test-Paste sub-step** that lets the user verify the paste path end-to-end without recording first.

- **Hotkey conflict detection in `ReadyStep`**. The Ready screen now checks whether the configured global hotkey is already claimed by another running app or by the OS before the user hits Start. If a conflict is detected, the step blocks the Start CTA and points the user back to the Hotkey step instead of letting them finish onboarding into a broken state.

- **Dynamic language selector in `WelcomeStep`**. The welcome screen picks up the user's OS locale on first paint and proposes it as the default transcription language. The old static pill-row selector has been replaced by a shared `LanguageSelector` dropdown that scales to the full Whisper language catalog without overflowing.

- **`ReadyStep` reacts to `afterTranscriptionAction`**. The "What happens after recording?" preview on step 3 now updates live when the user changes the after-transcription mode (`copy` / `paste` / `clipboardAndPaste`) elsewhere in onboarding, so the preview text always matches the active mode.

- **Status-bar Auto-Paste-Off hint**. Users who skip the Auto-Paste onboarding step now see a one-time hint in the status bar explaining that Auto-Paste is off and how to enable it later, so the skipped path is recoverable without the user having to remember the setting exists.

- **Soft release-out on the floating overlay when recording ends**. The waveform now animates out gracefully when the overlay transitions from `recording` to `transcribing`, instead of snapping flat. The new `WaveformPipeline` drives a ring-buffer of bar heights with configurable attack/release smoothing, so the visualisation tracks speech energy faithfully on rises and decays smoothly on silence.

- **Perceptual `SpeechLevelMapper`**. The raw RMS level from the audio engine is now mapped through a perceptual dB → visual curve before reaching the overlay. Quiet speech registers visibly, loud speech doesn't clip the bars, and the silence floor sits where the user expects it.

### Refactor

- **`PasteCapabilityNotifier` extracted from the indicator widget**. The Auto-Paste capability state (the `ready` / `permissionMissing` / `unsupported` machine shipped in 1.2.19) now lives in a dedicated Riverpod notifier instead of being tangled into the Settings indicator widget. The new onboarding `AutoPasteStep` and the existing Settings indicator both observe the same source of truth, so a permission grant in onboarding immediately reflects in Settings and vice versa.

- **History UI adopts split-view + search-filter-bar naming**. The history pane's internal widgets and providers have been renamed to match the `CONTEXT.md` glossary (`SplitView`, `SearchFilterBar`). No behaviour change — pure terminology alignment so future references match the canonical vocabulary.

- **Shared `LanguageSelector` widget**. Onboarding and Settings now both consume the same dropdown widget for transcription-language selection, eliminating the duplicated pill-row in onboarding and the bespoke dropdown in Settings.

- **`AudioService` routes level through `SpeechLevelMapper`**. The internal audio level path no longer exposes raw RMS to consumers. The new `setWaveformBars` channel is the supported way to drive visualisations, and the legacy `setAudioLevel` hook has been removed.

### Bug Fixes

- **Sentry no longer ingests user-config noise**. Settings-page navigation, preference toggles, and the routine config-load breadcrumbs that contributed nothing diagnostic but inflated event payloads have been filtered out at the breadcrumb level. Crash reports stay focused on the path that led to the failure instead of being buried under setting reads.

- **Disposal guard on `AutoPasteStep`**. The onboarding step now cancels its TCC poll and Sentry breadcrumb timer when disposed, so navigating away mid-grant no longer leaks a timer or fires a breadcrumb against a dead context.

## 1.2.20

### Bug Fixes

- **Release pipeline no longer fails when an action's Post-step exits non-zero**. In v1.2.19 every functional Windows build step (compile, Sentry symbol upload, NSIS installer, MSIX, both artifact uploads) succeeded, but the `subosito/flutter-action` Post-step (cache save on a cache hit) returned a non-zero exit code. That flipped `needs.build-windows.result` to `failure` and the conditional gates on `create-release` and `submit-ms-store` (`result == 'success'`) skipped both jobs, leaving the binaries stranded in the artifact storage with no GitHub Release and no Microsoft Store submission. The workflow now exposes an explicit `build-succeeded` output set by a `Mark build succeeded` step that runs after every real build/upload step. Downstream jobs gate on that output (combined with `!cancelled()`) instead of the job result, so cache-save quirks or other Post-step failures can no longer block a release.

## 1.2.19

### Bug Fixes

- **Auto-Paste now works on ad-hoc-signed macOS builds**. The old code aborted with `Paste failed` whenever `AXIsProcessTrusted()` returned `false`, but on macOS Sequoia that API lies for ad-hoc-signed apps: every rebuild produces a new content hash, TCC binds permissions to that hash, and the visible "Accessibility ON" toggle in System Settings keeps referring to a previous build. The Swift host no longer treats the AX check as a hard gate. Instead it posts the keystroke through **two independent permission channels** (`CGEvent` + AppleScript via `System Events.keystroke`), reports honest success only when at least one channel can be proven to have landed, and includes a structured detail string (`ax=… cg=… as=… target=…`) in the result so silent-drop scenarios are diagnosable from `whispaste.log`.

- **Paste failures are no longer silent when the main window is hidden**. The previous in-app toast was invisible in the normal use case where the user is focused on Terminal / VS Code / Warp and WhisPaste lives in the tray. Three additional surfaces fire on every paste failure: a **native OS notification** via `local_notifier` (Toast on Windows, Notification Center on macOS), a **Dock-icon bounce** (`NSApp.requestUserAttention(.criticalRequest)`) on macOS / **taskbar flash** (`FlashWindowEx(FLASHW_TRAY|FLASHW_TIMERNOFG)`) on Windows, and a **persistent tray-menu badge** ("⚠ Auto-Einfügen blockiert — Berechtigung erteilen") that survives until the next successful paste auto-clears it. Attention requests are throttled to one per minute per failure kind to avoid spamming during a recording session.

### Features

- **Auto-Paste capability indicator in Settings**. The "After Transcription" section now hosts a live status card that probes both permission channels without actually pasting, shown as soon as the user enables `paste` or `clipboardAndPaste` mode. The card surfaces three actionable states (`ready` / `permissionMissing` / `unsupported`) with platform-specific repair actions: **"Test now"** runs a fresh `AXIsProcessTrusted` + AppleScript probe; **"Grant permission"** triggers `AXIsProcessTrustedWithOptions(prompt: true)` and opens System Settings → Privacy → Accessibility; and a new **"Repair permissions"** button that spawns `tccutil reset Accessibility com.whispaste.whispaste && tccutil reset AppleEvents com.whispaste.whispaste`, the documented Apple workaround for stale TCC entries on ad-hoc-signed apps. The repair button is hidden on Windows where TCC doesn't apply.

- **Structured paste-outcome reporting end-to-end**. The native bridges now return `{status, detail}` maps (`success` / `no_target` / `no_accessibility` / `post_failed` on macOS; `success` / `no_target` / `foreground_blocked` / `send_input_failed` on Windows) which Dart maps to a typed `PasteOutcome` enum (`success` / `blocked` / `platformUnavailable` / `noTarget` / `permissionMissing` / `failed`). Toast messages, native notifications, and tray badges are tailored to the specific failure mode so the user gets actionable guidance instead of a generic "Paste failed".

- **Visible native logging via `os_log`** in the macOS Swift host (`subsystem=com.whispaste.paste`) replaces the prior `NSLog` calls, which Apple's unified logging filters from non-Apple processes. Combined with the Dart-side `DesktopPaster.info` line logging the full native detail string, every paste attempt now leaves a triage-ready record in `~/Library/Application Support/WhisPaste/logs/whispaste.log`.

## 1.2.17

### Features

- **Streamlined model selection**: The STT model catalog now exposes exactly one model per quality tier — `whisper-small` (Compact), `whisper-medium` (Balanced), and `whisper-large-v3-turbo` (Premium). The previous catalog mixed redundant variants (`whisper-tiny`, `whisper-base`, non-turbo `whisper-large-v3`) that made tier-based defaults ambiguous and shipped large files for marginal quality wins. Existing installations are migrated automatically on settings load: any removed model ID is rewritten to its tier representative, so users keep a valid selection without manual intervention.

### Cleanup

- **CI/release pipeline consolidation**: The release workflow now triggers only on tag push (a stray merge to `main` no longer burns ~15 min on Win + macOS + MSIX builds whose artifacts are never published). The Windows and MSIX builds were merged into a single job that reuses one `flutter build windows --release` for both the NSIS installer and the MSIX store package, cutting roughly a duplicate Windows build off every release. Redundant `flutter analyze` + `flutter test` steps were dropped from the release job because CI on `dev` already gates them. The flaky Linux secure-storage job was removed (Linux is not a release target and the same path is covered on Win + macOS), the secret scan was deduplicated into a single Ubuntu job, and the changelog-refresh cron dropped from daily to weekly.

## 1.2.16

### Bug Fixes

- **Sentry consent gating**: Transactions are now suppressed alongside events when the user revokes monitoring consent. Previously the kill switch only stopped event capture, so performance spans and Drift query traces could still leak after opt-out. The consent check now runs in the transaction sampler, so revoking consent silences the SDK end-to-end with no restart needed.

### Observability

- **Sentry SDK 9.20 upgrade**: `sentry_flutter` moves from 8.14 to 9.20, with the matching `sentry_dio` and `sentry_drift` integrations enabled. HTTP requests through the update service's Dio client and every Drift database query now produce performance spans, so a slow update check or a regressed query shows up in the Sentry transaction list instead of staying invisible. Trace propagation is explicitly scoped to an empty allow-list so no `sentry-trace` headers leak to third-party APIs.

- **Native crash symbolication**: Release builds upload PDB/DLL symbols on Windows and `.dSYM` bundles on macOS to Sentry via `sentry_dart_plugin` during the release workflow. Native crash frames in the Rust audio engine, the whisper.cpp bridge, and platform plugins now resolve to source lines instead of raw addresses. Symbol upload uses a separate Sentry billing bucket and does not consume the event/span quota.

- **Route breadcrumbs**: A `SentryNavigatorObserver` is wired into both top-level `MaterialApp`s so dialog opens, settings panels, and the review prompt land as navigation breadcrumbs on the next error event — the path that led to a crash is now reconstructable.

### Distribution

- **Microsoft Store submission automated**: The release workflow now pushes a successful MSIX build to the Microsoft Store via the Partner Center Submission API. The "What's new" field is populated from the same AI-enhanced release notes that the GitHub Release uses, in both English and German. The job self-skips when the `MS_STORE_APP_ID` secret is unset, so forks and dispatch-only runs stay clean. Listing copy (description, features) lives in `store/` per locale.

### Cleanup

- **Dependency wave**: `flutter_secure_storage` 9 → 10 (consolidated iOS+macOS pod, Linux drops the `libjsoncpp1` system dep), `drift` family + `analyzer` + `sqlite3` upgraded, Dart utilities (`flutter_soloud`, `flutter_svg`, `lucide_icons_flutter`, `in_app_review`, `mocktail`) on current minor, website npm dependencies refreshed (Tailwind held at 4.2 until an upstream Vite/rolldown compatibility issue is resolved), CI action major pins bumped (checkout v6, setup-node v6, upload-artifact v7, download-artifact v8, withastro/action v6, deploy-pages v5, softprops/action-gh-release v3).

## 1.2.15

### Bug Fixes

- **Auto-Paste reports the real outcome (macOS)**: The macOS paste host now waits for the synthesised ⌘V to complete before reporting success back to Flutter, hard-stops with a clear error when the Accessibility permission is missing, clears stale target-app state when WhisPaste itself is frontmost, and uses the modern `activate(options:)` API on macOS 14+. The Auto-Paste toast no longer claims success when nothing was actually pasted.

### New Features

- **Multi-format export activation**: The history detail panel can now export the selected entry to TXT, MD, CSV, JSON, and DOCX. The action is wired up from the detail panel overflow menu and uses the platform file save dialog — no third-party services involved.

### Removals

- **`Projects` table and `project_id` column removed**: The unused `Projects` table and the `HistoryEntries.project_id` column have been deleted. A one-time destructive Drift v9 → v10 migration drops both on first launch. **Migration note**: Existing user databases auto-migrate from schema v9 to v10 on first launch. The migration is idempotent and requires no user action; transcripts, notes, tags, and timestamps are preserved.

- **Command Palette removed**: The entry-scoped Ctrl+K popup has been removed. All actions it exposed (export, copy, delete, etc.) remain available through the history detail panel's overflow menu, so no functionality is lost.

- **`useVAD` and `vadSensitivity` settings removed**: The Recording stack never read these two settings, so the corresponding UI controls and persisted columns have been dropped. Old persisted `use_vad` / `vad_sensitivity` keys in existing databases are silently ignored — no migration required.

### Cleanup

- **README and website Features alignment**: The README and the website Features section have been trimmed to match the actually-shipping feature set after the removals above. Outdated mentions of Projects, the Command Palette, and the VAD toggle have been removed from public-facing documentation.

## 1.2.13

### Bug Fixes

- **Model-failure classification with re-download prompt**: WhisPaste now classifies whisper-server exit codes more precisely. A code-3 failure (failed to load model) triggers an actionable "Please re-download the model" prompt and clears the cached model path, so a single corrupt or incompatible file no longer locks the user into an unrecoverable state. Subsequent recordings resume normally after re-download.

- **Heartbeat startup timeout**: The STT server heartbeat now enforces a hard deadline during startup. If the server does not become ready within the configured timeout, the pipeline fails fast with a clear error instead of hanging indefinitely while the process idles in the background.

- **Recording idempotency**: Rapid hotkey presses and overlapping trigger signals no longer start a second recording while one is already in flight. The orchestrator gates on the current `RecordingPhase` so only one session is active at a time, preventing corrupted WAV files and duplicate history entries.

- **Hotkey `TypeError` fallback**: On platforms where the hotkey manager returns a non-string key token, WhisPaste now catches the `TypeError` and degrades gracefully instead of crashing. The hotkey is marked as unregistered and the user sees an actionable settings nudge.

### Observability

- **Sentry fingerprint extension**: Error events are now grouped by a richer fingerprint that includes the recording phase and STT status at the time of failure. This collapses noisy duplicate issues in the Sentry dashboard and makes regression tracking more reliable.

- **Info-level guard fires**: Sentry now captures info-level breadcrumbs when safety guards (OOM guard, CPU fallback gate, idempotency gate) activate. These breadcrumbs are attached to the next error event, giving support the full decision trail without PII.

### Removals

- **Smart-Mode dead code removed**: All `SmartMode`-prefixed fields, providers, and UI fragments have been deleted. The feature was never shipped publicly; removing the dead code reduces bundle size and eliminates confusion in the settings diff. No user-visible behaviour changes.

- **Groq STT removed**: The Groq cloud STT backend has been removed from WhisPaste. **Migration note**: Existing users who had Groq selected as their STT provider will automatically fall back to On-Device STT (whisper.cpp) on first launch after the update. No data is lost; the API key stored in secure storage is left intact but is no longer read.

### New Features

- **Deepgram STT — production-ready**: The Deepgram Nova-2 cloud STT backend is now fully functional and supported as a first-class provider alongside OpenAI and On-Device. Real-time streaming transcription, automatic language detection, and speaker diarisation are all supported. Configure your Deepgram API key in Settings → Cloud STT.

- **Free-tier onboarding hints**: Settings now shows inline signup links for Deepgram (free tier: 45 hours/month) and OpenAI (pay-as-you-go) directly beneath the API key fields. New users no longer need to leave the app to find sign-up links.

### Cleanup

- **README and website consistency**: Removed Post-Processing, LLM auto-tagging, and Groq from the README feature list and the website landing page. The public-facing documentation now accurately reflects the shipped feature set.

### Internal Refactors

- **`AppSettings` section-based architecture**: `AppSettings` is now split into focused section classes (`RecordingSettings`, `SttSettings`, `UiSettings`, etc.) instead of a flat record. Each section owns its own `fromDb`/`toDb` logic, making future column additions additive rather than requiring edits across the entire settings surface.

- **STT subsystem modularisation**: The monolithic `SttService` has been split into deep, independently testable modules — `SttProcessManager`, `SttHealthMonitor`, `SttTranscriber`, and `SttProviderRouter`. Each module has its own unit tests and a clearly defined interface boundary.

- **Recording orchestrator decomposition**: `RecordingOrchestrator` has been refactored into three collaborating components — `SafetyGuard` (pre-flight checks and idempotency), `OomRecoveryHandler` (RAM monitoring and retry logic), and `RecordingStateMachine` (phase transitions and event emission). This separation makes the flow easier to test and audit.

- **Floating UI platform host**: The floating button, floating overlay, and recording pill now share a single `FloatingPlatformHost` that manages the native window lifecycle. Duplicated window-positioning and always-on-top logic has been consolidated into one place.

## 1.2.10

### New Features

- **Minimum system requirements enforced**: WhisPaste now checks available RAM at startup and shows a clear, localized error screen when the system does not meet the 8 GB minimum. Users on underpowered hardware receive a friendly explanation with a link to the FAQ instead of encountering confusing failures mid-session.

### Improvements

- **System requirements updated on website**: The FAQ now lists accurate hardware requirements — 8 GB RAM minimum (enforced), 16 GB recommended, and a detailed GPU VRAM table for each model tier (compact ~300 MB, balanced ~900 MB, premium ~2.6 GB). Apple Silicon unified-memory users are also noted.

## 1.2.9

### Bug Fixes

- **Model load failure loop prevented**: When whisper-server exits with code 3 (failed to load model — typically a corrupted or incompatible model file), WhisPaste now fails fast on all subsequent recording attempts with an actionable "Please re-download" message instead of silently retrying indefinitely. The failed-model flag resets when the user re-downloads the model or changes model/GPU settings.

- **Duplicate error toast eliminated**: The generic "Something went wrong" toast no longer appears alongside the specific "model file corrupted" error message after a code-3 model load failure. The exit handler's specific message now takes priority.

- **Misleading "Could not save audio file" toast fixed**: When a recording pipeline abort is caused by STT startup failure (not by an audio capture issue), WhisPaste now shows the STT error message instead of the confusing "Could not save the audio file" toast.

## 1.2.8

### Bug Fixes

- **GPU → CPU automatic fallback**: When the speech engine crashes with a fatal GPU error (e.g. on older NVIDIA cards like GTX 650 with insufficient VRAM or unsupported compute features), WhisPaste now silently activates CPU mode instead of showing an error dialog. Subsequent recordings automatically use the CPU backend. The fallback resets when the user changes the GPU setting or active model.

- **Flash-attention compatibility**: GTX 650 and other pre-Turing GPUs (pre-sm_75) no longer receive the `--flash-attn` flag, preventing the STATUS_STACK_BUFFER_OVERRUN crash that occurred on these cards at runtime.

- **Waveform animation**: The audio visualiser in the macOS recording overlay is no longer static at high amplitude levels. The per-frame dual-oscillator now applies correct normalisation so the waveform remains visibly dynamic across the full input range.

### New Features

- **Review prompts**: After a configurable number of successful recordings, the app now gently invites users to rate WhisPaste in the App Store / Microsoft Store or star the project on GitHub. The prompt is non-intrusive and only shown once per milestone.

- **Download support modal**: The landing page now shows a friendly post-download modal with low-pressure information about how visitors can support the project (review, star, share).

### Infrastructure

- Supabase security advisor warnings resolved: RLS policies tightened, analytics functions hardened against injection, unused indexes dropped.

## 1.2.7

### Bug Fixes

- **Crash on quit**: Fixed a SIGABRT crash when quitting via the floating button context menu or tray icon. The Drift/SQLite database is now explicitly closed before the window is destroyed, preventing an assertion failure in SQLite's mutex cleanup.

### Screenshots & Store Assets

- Mac App Store screenshots now use the correct **1440×900** resolution (16:10) with authentic macOS window chrome (traffic-light close/minimise/maximise dots). Previously, both stores incorrectly used 1920×1080 Windows-style chrome.
- OG images no longer carry a double window frame — the fake CSS title bar overlay has been removed and border-radius corrected to match real macOS window corners.
- Screenshot pipeline is now fully cross-platform (macOS + Windows): golden tests generate separate `windowsStoreScreenshots/` and `macStoreScreenshots/` sets; the Node compositor renders each store panorama at its native resolution with injected CSS variables.

## 1.2.6

### Improvements

- MSIX package for Microsoft Store now included in release artifacts with correct Partner Center publisher identity.
- MSIX build failure now properly blocks the release workflow instead of being silently ignored.

## 1.2.3

### Bug Fixes

- **History detail editor**: Enter, Backspace, and Delete keys are no longer intercepted by list-level keyboard shortcuts when a text field has focus. All standard editing operations (line breaks, character deletion, cursor movement) now work correctly in the transcript editor, notes field, and tag input.

## 1.2.2

### macOS

- macOS app ships as a native ARM64 DMG with every release — direct download and Gatekeeper instructions included.
- Floating button context menu expanded: open WhisPaste, start recording, view history, open settings, or quit — all accessible via right-click on the floating button.
- macOS menu bar icon now displays correctly and resolves paths reliably across all bundle layouts.

## 1.2.1

Re-release of 1.2.0 with consistent version metadata and release pipeline
stabilization. No user-visible app changes.

## 1.2.0

Complete rewrite: WhisPaste is now a native **Flutter** application replacing the previous Go+WebView2 architecture.

### What's New

- **Native Flutter UI** — truly cross-platform (Windows, macOS, Linux, iOS, Android) with a single Dart codebase
- **SQLite via Drift** — all data stored locally in a type-safe database; no shared config files
- **Riverpod state management** — reactive, testable, maintainable architecture
- **Unified design system** — WpToast notifications, WpDialog modals, consistent theme tokens
- **Recording pill overlay** — slim, elegant status bar during dictation with progress ring
- **Floating button** — always-on-top recording trigger with context menu and multi-monitor support
- **Premium UI** — warm gradients, frosted glass effects, micro-animations, WCAG AA contrast
- **469+ automated tests** — widget, unit, and integration tests with >90% feature coverage

### Architecture

- All Go backend code removed — zero Go dependencies
- CI/CD updated for Flutter-only builds (Windows debug + release)
- Security scanning migrated from golangci-lint/gosec to flutter analyze + gitleaks
- Version centralized in `pubspec.yaml` with `app_info.dart` constant

### Breaking Changes

- Settings are stored in SQLite, not the legacy Go `config.json`
- No Go FFI bridge — all inference via whisper-server subprocess

---

## 1.1.3.0

A polished UI update that makes WhisPaste feel faster, clearer, and more intuitive to use.

### Highlights

- Redesigned dashboard, Smart Mode, and Voice Snippets screens with cleaner cards and better spacing.
- Smart Mode and Voice Snippets now have separate AI provider settings — choose local or cloud independently.
- Silence removal is now a single, unified setting combining voice detection and trim in one step.
- Page transitions are now smooth and animated for a more premium feel.
- Auto-generated tags now use Title Case and block system tags from leaking into your entries.

### UI and copy improvements

- Settings reorganized into clearer sections with more descriptive labels.
- Replaced jargon like "Transcription" and "Diktat" with everyday language throughout.
- All German translations reviewed and aligned with the current English copy.
- Contextual tips explain features where you need them, not just in onboarding.

### Reliability

- Fixed a race condition when switching pages quickly during transitions.
- Version metadata in Windows resources now stays in sync with the release version.
- Silence detection margins tuned to industry best practices (250 ms pre-speech, 350 ms post-speech).

## 1.1.2.0

This release focuses on safer crash reporting, clearer setup flows, and more consistent communication across the app and website.

### Highlights

- Crash reporting now uses a Supabase relay instead of shipping a direct Discord webhook in the app.
- Release builds now require the public crash-relay URL, so packaged builds keep crash delivery working reliably.
- The onboarding try-dictation flow no longer marks onboarding complete too early while transcription is still finishing.

### Privacy and security

- Public builds ship only the relay URL. Private secrets stay server-side in Supabase.
- Crash-message sanitization is stricter for API keys, bearer tokens, and similar secrets.
- Setup docs now clearly explain which Supabase values are public and which must never be committed.

### Product and copy updates

- Website copy now reflects the real product setup more accurately: local transcription or the cloud provider you choose.
- Privacy messaging now explains optional crash reporting more transparently.
- Download and release messaging no longer implies an OpenAI-only setup.

### Reliability

- Release workflow validation now fails early if the crash-relay configuration is missing or malformed.
- Build metadata stays aligned with the release version more consistently.
