# WhisPaste

> WhisPaste ist eine kostenlose, MIT-lizenzierte Spracheingabe-App für Windows, Macs mit Apple Silicon und Linux: Tastenkürzel drücken, sprechen, und der Text landet im aktiven Textfeld. Die Spracherkennung läuft lokal auf deinem Computer.

## Was WhisPaste macht

- Du hältst in einer beliebigen Anwendung ein globales Tastenkürzel, während du sprichst, und lässt zum Stoppen los, oder tippst es einmal zum Starten und noch einmal zum Stoppen.
- WhisPaste schreibt die Aufnahme auf deinem Computer mit und kopiert den Text in die Zwischenablage. Mit eingeschaltetem Auto-Einfügen setzt es den Text am Cursor der aktiven Anwendung ein, in fast jeder App.
- Gedacht für Menschen, die am Desktop viel schreiben: E-Mails, Nachrichten, Dokumente, Notizen, Prompts und Code-Kommentare.

## Spracherkennung

- Zwei lokale Engines: Whisper (whisper.cpp, 99 Sprachen, mehrere Modellgrößen) und Parakeet (rund 25 europäische Sprachen, schnell auch ohne GPU).
- Nach einem einmaligen Modell-Download funktioniert die lokale Erkennung offline.
- Eine GPU ist optional. Beschleunigt wird mit Metal auf Apple Silicon und Vulkan unter Windows und Linux; für NVIDIA gibt es ein optionales CUDA-Paket. Ohne GPU läuft die Erkennung auf der CPU.
- Optional Cloud-Erkennung über OpenAI oder Deepgram mit eigenem API-Schlüssel.
- Auf Macs mit macOS 26 oder neuer steht die Apple-Spracherkennung auf dem Gerät als dritte Wahl bereit.

## Smart Mode (optional, standardmäßig aus)

- Aufräumen entfernt Füllwörter und korrigiert die Zeichensetzung, Kürzen fasst den Text knapper, Übersetzen überträgt ihn ins Deutsche, Englische, Spanische, Französische, Portugiesische, Mandarin oder Russische.
- Läuft lokal (macOS und Windows; unter Linux experimentell) oder über OpenAI mit eigenem API-Schlüssel.
- Eigene Presets mit eigener Anweisung (bis 500 Zeichen); ein Preset lässt sich später auf eine frühere Aufnahme anwenden, das Original bleibt. Statt OpenAI funktioniert auch ein eigener kompatibler Server (etwa LM Studio oder Ollama) auf dem Rechner oder im lokalen Netz.

## Im Alltag

- Lokaler Bereich Aufnahmen mit Suche, Filtern, automatischem Speichern und Versionsverlauf, dazu Notizen mit Titeln, Bildern, Checklisten, Leseansicht und Fokusmodus.
- Textbausteine: gespeicherte Texte, eingefügt per Tastenkürzel oder gesprochenem Auslösewort; interaktive Bausteine füllen eine Vorlage aus.
- Datei-Import: Audio- (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) und Videodateien (MP4, MOV, MKV, WebM) bis 1 GB und 6 Stunden transkribieren. Audiodateien gehen auch direkt aus dem Dateimanager an WhisPaste: auf dem Mac, unter Linux und in der Version aus dem Microsoft Store über „Öffnen mit“, mit dem Windows-Installer von der Website per Rechtsklick.
- Optional pausiert WhisPaste unter Windows und Linux Musik und Videos während des Diktats, und „Nach dem Einfügen senden“ drückt nach dem Einfügen Enter (Alt beim Loslassen des Hotkeys halten; unter Linux nur X11).
- „Lautstärke automatisch angleichen“ (standardmäßig an) hebt leise Sprache vor der Erkennung an, ohne Stille oder Rauschen zu verstärken.
- Bis zu fünf Lieblings-Erkennungssprachen, mit dem Stern markiert, stehen in den Sprachmenüs oben; ein Tastenkürzel wechselt zwischen ihnen.
- Das Wörterbuch hält Namen und Fachbegriffe; Ersetzungen korrigieren wiederkehrende Schreibweisen, und aus wiederholten Korrekturen schlägt WhisPaste neue vor.
- Profile legen Sprache, Sprachmodell, Smart Mode, Mikrofon und Ausgabe für eine bestimmte App fest.
- Scheitert eine Transkription, bleibt das Audio standardmäßig 24 Stunden erhalten, auch nach einem Absturz, und du kannst es erneut versuchen.
- Barrierefreiheit: Einstellungen, Notizen und Editor-Werkzeuge funktionieren per Tastatur und Screenreader; im Tipp-Modus musst du nie eine Taste halten.

## Datenschutz

- Bei lokaler Erkennung bleibt das Audio auf deinem Computer und wird nach der Transkription verworfen, außer du schaltest das Aufbewahren von Audio ein.
- Unter macOS und Windows fügt WhisPaste nicht automatisch in Passwortfelder ein; der Text bleibt in der Zwischenablage.
- Transkripte, Notizen, Wörterbuch, Textbausteine und aufbewahrtes Audio liegen verschlüsselt, mit einem Datenschlüssel im Schlüsselspeicher des Systems (macOS-Schlüsselbund, Windows-Datenschutz, Linux Secret Service). Den Schlüssel sicherst du als Wiederherstellungscode oder Datei.
- Kein Konto nötig.
- Nutzungsstatistik und Absturzberichte enthalten kein Audio, keine Transkripte und keine Einträge aus Aufnahmen und lassen sich unter Einstellungen → Datenschutz ausschalten.
- Cloud-Funktionen senden Daten nur an den gewählten Anbieter und nur, wenn du sie nutzt.

## Plattformen und Voraussetzungen

- Windows 10 oder neuer, macOS 13 Ventura oder neuer auf Apple Silicon (Intel-Macs werden nicht unterstützt), Linux x64 (AppImage, .deb, tar.gz) ab Ubuntu 26.04 mit glibc 2.43; auf älteren Linux-Systemen bleibt Version 1.4.2.
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
