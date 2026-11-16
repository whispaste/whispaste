---
title: "Vom Hotkey zum Text: Diktieren im aktiven Fenster"
description: "So landet Gesprochenes mit Auto-Paste im aktiven Textfeld – mit Hinweisen zur Zwischenablage, zur Textprüfung und zur Einrichtung unter Linux."
date: 2026-10-16
---

Wie bekommst du einen gesprochenen Satz in deine E-Mail, ohne dafür in ein anderes Fenster zu wechseln? Genau dafür ist WhisPaste gedacht: Du startest die Aufnahme dort, wo du schreibst. Mit eingeschaltetem Auto-Paste landet das Transkript anschließend am Cursor.

## Im gewünschten Textfeld anfangen

Setze den Cursor an die Stelle, an der dein Text stehen soll. Das kann eine Antwort in Outlook sein, ein Chat in Slack, ein Browser-Textfeld oder dein Editor. Drücke den Hotkey, sprich und drücke ihn erneut, um die Aufnahme zu beenden.

Für Absätze musst du nicht zur Tastatur greifen: In Deutsch, Englisch, Spanisch, Portugiesisch und Russisch sprichst du „neuer Absatz“ oder „neue Zeile“ als Umbruch. Soll die Aufnahme doch verworfen werden, brichst du sie mit Esc ab.

Probier den Ablauf zunächst mit einem kurzen Text, den du ohnehin schreiben möchtest. So kannst du direkt beurteilen, ob diese Art der Eingabe zu dir passt.

## Auto-Paste einschalten und den Text prüfen

Auto-Paste wird dir bei der Einrichtung angeboten. Ist es eingeschaltet, fügt WhisPaste das Transkript im aktiven Textfeld ein. Andernfalls kopiert es das Ergebnis in die Zwischenablage, und du fügst es selbst ein.

Lies den Text anschließend durch und bearbeite ihn direkt in deiner Anwendung. Die Erkennungsgenauigkeit hängt vom gewählten Modell ab; ein kurzer prüfender Blick gehört deshalb zum Ablauf dazu. Wenn du ein Transkript später wiederfinden möchtest, gibt es außerdem den durchsuchbaren Verlauf. Dort kannst du Einträge bearbeiten und ordnen.

## Unter Linux einmal die Einrichtung prüfen

Unter Linux braucht Auto-Paste eine Berechtigungsregel für `/dev/uinput`. Beim .deb-Paket gibst du sie in der App mit deinem Administratorpasswort frei und kannst sie dort wieder entfernen; bei AppImage oder tar.gz richtest du sie einmal mit sudo ein. Ohne diese Regel bleibt das Ergebnis in der Zwischenablage und lässt sich mit Strg+V einfügen.

Unter Wayland legst du den Hotkey über deine Desktop-Umgebung an. Dafür lässt sich der Befehl `whispaste --toggle` verwenden; beim AppImage nimmst du stattdessen dessen vollständigen Pfad mit `--toggle`.

Entscheidend ist, wie sich der Ablauf beim Schreiben anfühlt: Cursor setzen, sprechen, Text prüfen und weiterarbeiten. Weitere Einsatzmöglichkeiten findest du bei [Spracheingabe für Vielschreiber](/use-cases/vielschreiber/).
