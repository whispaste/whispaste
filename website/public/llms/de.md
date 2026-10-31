# WhisPaste

> WhisPaste ist eine kostenlose, MIT-lizenzierte Spracheingabe-App für Windows, Macs mit Apple Silicon und Linux: Tastenkürzel drücken, sprechen, und der Text landet im aktiven Textfeld. Die Spracherkennung läuft lokal auf deinem Computer.

## Was WhisPaste macht

- Du drückst in einer beliebigen Anwendung ein globales Tastenkürzel, sprichst und drückst es erneut (oder hältst es beim Sprechen gedrückt).
- WhisPaste schreibt die Aufnahme auf deinem Computer mit und kopiert den Text in die Zwischenablage. Mit eingeschaltetem Auto-Einfügen setzt es den Text am Cursor der aktiven Anwendung ein, in fast jeder App.
- Gedacht für Menschen, die am Desktop viel schreiben: E-Mails, Nachrichten, Dokumente, Notizen, Prompts und Code-Kommentare.

## Spracherkennung

- Zwei lokale Engines: Whisper (whisper.cpp, 99 Sprachen, mehrere Modellgrößen) und Parakeet (rund 25 europäische Sprachen, schnell auch ohne GPU).
- Nach einem einmaligen Modell-Download funktioniert die lokale Erkennung offline.
- Eine GPU ist optional. Beschleunigt wird mit Metal auf Apple Silicon und Vulkan unter Windows und Linux; für NVIDIA gibt es ein optionales CUDA-Paket. Ohne GPU läuft die Erkennung auf der CPU.
- Optional Cloud-Erkennung über OpenAI oder Deepgram mit eigenem API-Schlüssel.

## Smart Mode (optional, standardmäßig aus)

- Aufräumen entfernt Füllwörter und korrigiert die Zeichensetzung, Kürzen fasst den Text knapper, Übersetzen überträgt ihn ins Deutsche, Englische, Spanische, Französische, Portugiesische, Mandarin oder Russische.
- Läuft lokal (macOS und Windows; unter Linux experimentell) oder über OpenAI mit eigenem API-Schlüssel.

## Im Alltag

- Lokaler Verlauf der Transkripte und getrennte Schnellnotizen.
- Textbausteine: gespeicherte Texte, eingefügt per Tastenkürzel oder gesprochenem Auslösewort; interaktive Bausteine füllen eine Vorlage aus.
- Datei-Import: vorhandene Audiodateien transkribieren.

## Datenschutz

- Bei lokaler Erkennung bleibt das Audio auf deinem Computer und wird nach der Transkription verworfen, außer du schaltest das Aufbewahren von Audio ein.
- Kein Konto nötig.
- Nutzungsstatistik und Absturzberichte enthalten kein Audio, keine Transkripte und keinen Verlauf und lassen sich unter Einstellungen → Datenschutz ausschalten.
- Cloud-Funktionen senden Daten nur an den gewählten Anbieter und nur, wenn du sie nutzt.

## Plattformen und Voraussetzungen

- Windows 10 oder neuer, macOS 12 Monterey oder neuer auf Apple Silicon (Intel-Macs werden nicht unterstützt), Linux x64 (AppImage, .deb, tar.gz).
- Empfohlen: mindestens 8 GB Arbeitsspeicher und ein 64-Bit-Prozessor.
- Nur Desktop; es gibt keine iOS- oder Android-Version.

## Preis und Lizenz

- Die vollständige App ist kostenlos auf GitHub unter der MIT-Lizenz.
- Kostenpflichtige Versionen im Microsoft Store und im Mac App Store bieten dieselben Kernfunktionen mit Updates über den Store.
- Kein Abo. Optionale Cloud-Anbieter können ihre Nutzung berechnen.

## Links

- [Website](https://whispaste.de/)
- [Download](https://whispaste.de/download/)
- [Datenschutzerklärung](https://whispaste.de/datenschutz/)
- [Änderungsprotokoll](https://whispaste.de/changelog/)
- [Quellcode auf GitHub](https://github.com/whispaste/whispaste)
