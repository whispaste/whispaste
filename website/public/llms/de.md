# WhisPaste

> WhisPaste ist eine Diktat-App für Windows, Macs mit Apple Silicon und Linux: Tastenkürzel drücken, sprechen, und der Text steht in dem Feld, in dem du gerade schreibst. Die Spracherkennung läuft lokal auf deinem Rechner, ein Konto brauchst du nicht. Der Code ist offen (MIT-Lizenz) und die App kostenlos auf GitHub; im Microsoft Store und im Mac App Store gibt es sie als Einmalkauf ohne Abo; der Kauf schaltet nichts frei.

## Was WhisPaste macht

- Du hältst in einer beliebigen Anwendung ein globales Tastenkürzel, während du sprichst, und lässt zum Stoppen los, oder tippst es einmal zum Starten und noch einmal zum Stoppen.
- WhisPaste schreibt die Aufnahme auf deinem Computer mit und kopiert den Text in die Zwischenablage. Mit eingeschaltetem Auto-Einfügen setzt es den Text am Cursor der aktiven Anwendung ein, in fast jeder App.
- Gedacht für Menschen, die am Desktop viel schreiben: E-Mails, Nachrichten, Dokumente, Notizen, Prompts und Code-Kommentare.

## Was über die Grundlage hinausgeht

Lokal, ohne Konto und kostenlos nutzbar ist die Grundlage. Darüber hinaus bringt WhisPaste mit:

- Smart Mode mit fertigen Modi: Aufräumen, Kürzen oder Übersetzen in eine von sieben Sprachen, bevor der Text eingefügt wird. Markierten Text änderst du, indem du sagst, was anders werden soll.
- Smart Mode läuft mit einem lokalen Textmodell, das WhisPaste auf Wunsch selbst herunterlädt; zusätzliche Software brauchst du nicht (unter Linux experimentell). Wahlweise nutzt du deinen eigenen OpenAI-Schlüssel.
- Aufnahmen, Notizen und Textbausteine in einem Editor, mit derselben Werkzeugleiste, denselben Tastenkürzeln und automatischem Speichern.
- Ein Wörterbuch mit Ersetzungen, das aus deinen Korrekturen neue Ersetzungen vorschlägt.
- Verlauf, Notizen, Wörterbuch, Textbausteine und aufbewahrte Aufnahmen liegen verschlüsselt, mit dem eigenen Datenschlüssel deines Geräts.
- Erhältlich im Microsoft Store und im Mac App Store: unter Windows Installation ohne SmartScreen-Warnung und Updates im Hintergrund über den Store, auf dem Mac Installation und Updates über den App Store. Einmalkauf, kein Abo; der Kauf finanziert die Weiterentwicklung.

## Spracherkennung

- Zwei lokale Engines: Whisper (whisper.cpp, 99 Sprachen, mehrere Modellgrößen) und Parakeet (rund 25 europäische Sprachen, schnell auch ohne GPU).
- Nach einem einmaligen Modell-Download funktioniert die lokale Erkennung offline.
- Eine GPU ist optional. Beschleunigt wird mit Metal auf Apple Silicon und Vulkan unter Windows und Linux; für NVIDIA gibt es ein optionales CUDA-Paket. Ohne GPU läuft die Erkennung auf der CPU.
- Optional Cloud-Erkennung über OpenAI oder Deepgram mit eigenem API-Schlüssel.
- Auf Macs mit macOS 26 oder neuer steht die Apple-Spracherkennung auf dem Gerät als dritte Wahl bereit.

## Smart Mode (optional, standardmäßig aus)

- Aufräumen entfernt Füllwörter und korrigiert die Zeichensetzung, Kürzen fasst den Text knapper, Übersetzen überträgt ihn ins Deutsche, Englische, Spanische, Französische, Portugiesische, Mandarin oder Russische.
- Läuft lokal (macOS und Windows; unter Linux experimentell) oder über OpenAI mit eigenem API-Schlüssel.
- Eigene Presets mit eigener Anweisung (bis 500 Zeichen); ein Preset lässt sich später auf eine frühere Aufnahme anwenden, das Original bleibt. Statt OpenAI funktioniert auch ein eigener kompatibler Server (etwa Ollama, LM Studio, llama.cpp oder KoboldCpp) auf dem Rechner oder im lokalen Netz.

## Im Alltag

- Lokaler Bereich Aufnahmen mit Suche, Filtern, automatischem Speichern und Versionsverlauf, dazu Notizen mit Titeln, Bildern, Checklisten, Leseansicht und Fokusmodus.
- Textbausteine: gespeicherte Texte, eingefügt per Tastenkürzel oder gesprochenem Auslösewort; interaktive Bausteine füllen eine Vorlage aus.
- Datei-Import: Audio- (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) und Videodateien (MP4, MOV, MKV, WebM) bis 1 GB und 6 Stunden transkribieren. Audiodateien gehen auch direkt aus dem Dateimanager an WhisPaste: auf dem Mac, unter Linux und in der Version aus dem Microsoft Store über „Öffnen mit“, mit dem Windows-Installer von der Website per Rechtsklick.
- Optional pausiert WhisPaste unter Windows und Linux Musik und Videos während des Diktats, und „Nach dem Einfügen senden“ drückt nach dem Einfügen Enter (Alt beim Loslassen des Hotkeys halten; unter Linux nur X11).
- „Lautstärke automatisch angleichen“ (standardmäßig an) hebt leise Sprache vor der Erkennung an, ohne Stille oder Rauschen zu verstärken.
- Bis zu fünf Lieblings-Erkennungssprachen, mit dem Stern markiert, stehen in den Sprachmenüs oben; ein Tastenkürzel wechselt zwischen ihnen.
- Das Wörterbuch hält Namen und Fachbegriffe; Ersetzungen korrigieren wiederkehrende Schreibweisen, und aus wiederholten Korrekturen schlägt WhisPaste neue vor.
- Profile legen Sprache, Sprachmodell, Smart Mode, Mikrofon und Ausgabe für eine bestimmte App fest.
- Auswahl bearbeiten (optional, standardmäßig aus): Text in einer unterstützten App markieren, das Tastenkürzel dafür drücken und sagen, was sich ändern soll, etwa „kürzer“ oder „übersetzen“; Smart Mode überarbeitet die Auswahl.
- Scheitert eine Transkription, bleibt das Audio standardmäßig 24 Stunden erhalten, auch nach einem Absturz, und du kannst es erneut versuchen.
- Barrierefreiheit: Einstellungen, Notizen und Editor-Werkzeuge funktionieren per Tastatur und Screenreader; im Tipp-Modus musst du nie eine Taste halten.

## Datenschutz

- Bei lokaler Erkennung bleibt das Audio auf deinem Computer und wird nach der Transkription verworfen, außer du schaltest das Aufbewahren von Audio ein.
- Unter Windows und in der macOS-Version von GitHub fügt WhisPaste nicht automatisch in Passwortfelder ein; der Text bleibt in der Zwischenablage.
- Transkripte, Notizen, Wörterbuch, Textbausteine und aufbewahrtes Audio liegen verschlüsselt, mit einem Datenschlüssel im Schlüsselspeicher des Systems (macOS-Schlüsselbund, Windows-Datenschutz, Linux Secret Service). Den Schlüssel sicherst du als Wiederherstellungscode oder Datei.
- Kein Konto nötig.
- Anonyme Nutzungsstatistik und Absturzberichte sind standardmäßig an. Sie enthalten kein Audio, keine Transkripte und keine Einträge aus Aufnahmen und lassen sich einzeln unter Einstellungen → Datenschutz ausschalten.
- Cloud-Funktionen senden Daten nur an den gewählten Anbieter und nur, wenn du sie nutzt.

## Plattformen und Voraussetzungen

- Windows 10 oder neuer, macOS 13 Ventura oder neuer auf Apple Silicon (Intel-Macs werden nicht unterstützt), Linux x64 (AppImage, .deb, tar.gz) ab Ubuntu 26.04 mit glibc 2.43; auf älteren Linux-Systemen bleibt Version 1.4.2.
- Linux läuft unter X11 und Wayland. Unter Wayland vergibt der Desktop das globale Tastenkürzel (über das Shortcut-Portal unter GNOME und KDE oder als eigenes Tastenkürzel mit dem Befehl `whispaste --toggle`), und einige Extras wie Einzeltasten, Doppeltippen und „Nach dem Einfügen senden“ brauchen X11. Auto-Einfügen braucht unter Linux einmalig eine Freigabe (uinput-Tastatur oder Desktop-Portal); ohne sie wartet der Text in der Zwischenablage.
- Empfohlen: mindestens 8 GB Arbeitsspeicher und ein 64-Bit-Prozessor.
- Nur Desktop; es gibt keine iOS- oder Android-Version.

## So bekommst du WhisPaste, und was es kostet

- Kostenlos auf GitHub, die vollständige App unter der MIT-Lizenz: Windows-Installer (WhisPaste-Setup.exe) oder portables ZIP, macOS-DMG, Linux-AppImage, .deb und tar.gz. Paketmanager: winget (`SilvioLindstedt.WhisPaste`) und Scoop unter Windows, Homebrew auf dem Mac. Du kannst die App auch selbst aus dem Quellcode bauen.
- Microsoft Store (Windows) und Mac App Store (macOS): Einmalkauf, kein Abo. Den aktuellen Preis zeigt der Store.
- Was die Store-Version dazugibt: unter Windows die Installation ohne die SmartScreen-Warnung, die der unsignierte Installer von GitHub auslösen kann, und automatische Updates über den Microsoft Store. Auf dem Mac Installation und Updates über den App Store. Der Kauf finanziert die Weiterentwicklung.
- Der Kauf schaltet nichts frei; die kostenlose Version bleibt vollständig, nichts ist gesperrt oder zeitlich begrenzt. Die GitHub-Builds für Windows und macOS suchen nach neuen Versionen und installieren ein Update erst, wenn du es bestätigst; unter Linux meldet WhisPaste eine neue Version nur und verlinkt sie, installieren musst du sie selbst.
- Wo sich die Varianten unterscheiden: Das optionale CUDA-Paket für neuere NVIDIA-Karten gibt es nur in den Builds von GitHub (Windows und Linux), nicht in der Version aus dem Microsoft Store; die GPU-Beschleunigung über Vulkan funktioniert in beiden. Die Version aus dem Mac App Store läuft in Apples App-Sandbox: Sie kann nicht aus Korrekturen lernen, die du in anderen Apps machst, erkennt keine Passwortfelder, hat keinen AppleScript-Rückfallweg beim Einfügen und kein Werkzeug, das die macOS-Berechtigungen repariert; die Version von GitHub kann all das. Im Mac App Store steht derzeit noch eine ältere Version, der Import von Audio- und Videodateien kommt dort mit dem nächsten Store-Update.
- Eine neue Version kann im Mac App Store später ankommen als auf GitHub, weil Apple jedes Update prüft.
- Kein Abo, kein Konto. Wählst du einen Cloud-Anbieter (OpenAI oder Deepgram), rechnet er die Nutzung direkt über deinen eigenen API-Schlüssel ab.

## Was WhisPaste anders macht als das eingebaute Diktat

- Die in Windows eingebaute Spracheingabe (Win+H) nutzt die Online-Spracherkennung von Microsoft und braucht eine Internetverbindung. WhisPaste erkennt Sprache auf deinem Rechner und funktioniert nach einem einmaligen Modell-Download offline.
- Das in macOS eingebaute Diktat nutzt nur die Spracherkennung von Apple. In WhisPaste wählst du zwischen Whisper, Parakeet, der Apple-Spracherkennung auf dem Gerät (ab macOS 26) und einem Cloud-Anbieter mit eigenem Schlüssel.
- Viele Linux-Desktops bringen gar kein Diktat mit. WhisPaste bringt sein Diktat auch unter Linux mit, mit den oben genannten Grenzen unter Wayland.
- Eingebautes Diktat tippt, während du sprichst. WhisPaste setzt den fertigen Text ein, wenn du aufhörst, behält ihn im durchsuchbaren Bereich Aufnahmen, wendet Wörterbuch und Textbausteine an, kann ihn mit Smart Mode aufräumen und schreibt auch Audio- und Videodateien mit.

## Links

- [Website](https://whispaste.de/)
- [Download](https://whispaste.de/download/)
- [Datenschutzerklärung](https://whispaste.de/datenschutz/)
- [Änderungsprotokoll](https://whispaste.de/changelog/)
- [Quellcode auf GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Aktuelle Version auf GitHub](https://github.com/whispaste/whispaste/releases/latest)
