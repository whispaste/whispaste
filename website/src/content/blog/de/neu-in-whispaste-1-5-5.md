---
title: "Neu in WhisPaste 1.5.5: alle Modelle an einem Ort, Sprachen per Tastendruck"
description: "Eine eigene Seite für alle Sprach- und Textmodelle mit Suche auf Hugging Face, eine Taste je Sprache, Namen aus deinen Kontakten im Wörterbuch und mehr für Notizen: Das bringt WhisPaste 1.5.5."
date: 2026-11-25
cover:
  src: "/blog/neu-in-whispaste-1-5-5/cover-de.webp"
  alt: "WhisPaste-Hauptfenster mit der Einstellungsseite Modelle: Whisper large-v3-turbo aktiv, Whisper small installiert, Whisper medium und Parakeet mit dem Hinweis „Nicht für Japanisch“, darunter das Textmodell Gemma 4 E2B"
  og: "/blog/neu-in-whispaste-1-5-5/og-de.png"
---

WhisPaste 1.5.5 ist da, mit zwei großen Neuerungen. Alle Sprach- und Textmodelle stehen jetzt auf einer Seite, wo du sie vergleichst, installierst und auch auf Hugging Face suchst. Und wer in mehreren Sprachen diktiert, wechselt die Sprache jetzt mit einem Tastendruck, statt sich auf die automatische Erkennung zu verlassen. Dazu kommen Namen aus deinen Kontakten im Wörterbuch und einiges für Notizen.

## Alle Modelle an einem Ort

Die neue Seite Einstellungen → Modelle zeigt jedes Sprach- und Textmodell mit Größe, Sprachen, Tempo und Genauigkeit in klaren Worten, und ob es auf deinem Rechner oder in der Cloud läuft. Das Modell, das WhisPaste für deinen Rechner empfiehlt, steht oben. Installieren, wechseln und entfernen geht direkt dort; beim Entfernen siehst du, wie viel Platz frei wird.

<figure class="wp-shot"><img src="/blog/neu-in-whispaste-1-5-5/modelle-de.webp" alt="Einstellungsseite Modelle mit Suchfeld, Plus-Taste und Filtern, darunter fünf Modelle mit Größe und Status; bei Parakeet steht „Nicht für Japanisch“" width="1600" height="1633" loading="lazy" /><figcaption>Die Seite Modelle mit Japanisch als Favoriten-Sprache: Parakeet rückt mit „Nicht für Japanisch“ nach unten.</figcaption></figure>

Die Seite kennt auch deine Sprachen: deine Diktiersprache, deine Favoriten und die Sprachen deines Systems. Schreibt ein Modell eine davon nicht, steht dort „Nicht für …“, und es rückt ans Ende der Liste. Die Empfehlung zählt deine Favoriten mit, sodass zum Beispiel ein Japanisch-Favorit kein Parakeet mehr empfohlen bekommt.

Über „+“ durchsuchst du Hugging Face direkt aus der App: ein Suchfeld, Filter für Sprachen und Größe (ab Werk „Passt auf diesen Computer“), und ein Modell installierst du in einem Schritt. Angezeigt werden nur Modelle, die WhisPaste tatsächlich ausführen kann, jeweils mit Lizenz und dem Hinweis, dass wir sie nicht geprüft haben. Unter „Eigene Modelle“ fügst du ein Modell von einer Adresse oder aus einer Datei hinzu, und jedes Textmodell hat „Einstellungen für dieses Modell“, falls du die vom Hersteller empfohlenen Werte nutzen willst.

## Sprachen per Tastendruck

Wer in zwei oder drei Sprachen diktiert, musste bisher entweder umschalten oder auf die automatische Erkennung hoffen, und die landet bei einem kurzen, mehrdeutigen Satz gern in einer Sprache, die du nie sprichst. In 1.5.5 geht beides besser.

Unter Einstellungen → Tastenkürzel → „Taste je Favoriten-Sprache“ bekommt jede Favoriten-Sprache mit „Taste festlegen“ ihre eigene Tastenkombination. Ein Druck schaltet direkt auf diese Sprache um, und die Aufnahmeleiste zeigt kurz, welche jetzt gilt. Willst du dir das Umschalten ganz sparen, legst du unter „Weitere Diktiertasten“ bis zu drei zusätzliche Diktiertasten an. Jede diktiert fest in ihrer eigenen Sprache, auf Wunsch mit eigenem Smart Mode, und funktioniert sonst wie die Haupttaste. Bei kurzen Sätzen ist das zuverlässiger als jede Erkennung.

<figure class="wp-shot"><img src="/blog/neu-in-whispaste-1-5-5/tastenkuerzel-de.webp" alt="Einstellungen Tastenkürzel: eine weitere Diktiertaste für Französisch, darunter „Taste je Favoriten-Sprache“ mit eigenen Tasten für Deutsch, Englisch und Spanisch" width="1600" height="1981" loading="lazy" /><figcaption>Eine weitere Diktiertaste für Französisch und je eine Taste für drei Favoriten-Sprachen.</figcaption></figure>

Nutzt du trotzdem „Automatisch erkennen“, wählt WhisPaste ab zwei Favoriten-Sprachen jetzt nur noch unter diesen Favoriten. Der Vorschlag kam auf unserem [Ideenboard](https://app.votepit.com/silvio-und-maik/whispaste) und von [H-Masoumi](https://github.com/H-Masoumi) auf GitHub. Und Parakeet bleibt bei deinen Sprachen: Bisher konnte es ein polnisches Diktat in kyrillischer Schrift ausgeben. Schreibt Parakeet jetzt in einer Schrift, die keine deiner Sprachen nutzt, transkribiert Whisper dieselbe Aufnahme noch einmal, sofern ein Whisper-Modell installiert ist.

Eine Einschränkung gibt es unter Linux mit Wayland: Dort bindet das System nur die Haupt-Diktiertaste, die weiteren Tasten reagieren in anderen Apps unter Umständen nicht. Die Einstellungen weisen darauf hin.

## Namen aus deinen Kontakten

Spracherkennung kennt „Müller“, aber nicht unbedingt „Mühlhäuser“ oder den Namen der Firma, für die du arbeitest. Im Wörterbuch gibt es dafür jetzt „Namen aus Kontakten übernehmen…“. WhisPaste zeigt dir die vollständigen Namen und Firmen aus deinem Adressbuch, du wählst aus, welche du übernehmen willst, und ab dann schreibt die Erkennung sie richtig. Adressen, Telefonnummern und E-Mail-Adressen liest WhisPaste dabei nicht.

Die Namen kommen aus den Kontakten von macOS, aus den Windows-Kontakten oder Outlook, aus GNOME-Kontakte oder dem KDE-Adressbuch, und auf jedem System aus einem vCard- oder CSV-Export. Sie bleiben auf deinem Gerät: Die lokale Erkennung nutzt sie, Cloud-Dienste bekommen sie nie. Die Flatpak- und Snap-Version kommt nicht an die Linux-Adressbücher heran, dort nimmst du den vCard-Export.

## Notizen verknüpfen und ablegen

Tippe in einer Aufnahme, Notiz oder einem Textbaustein `[[`, und WhisPaste öffnet „Verknüpfen mit …“. Du wählst einen Eintrag, und ein Link mit seinem Namen steht im Text. Der Link hängt am Eintrag, nicht am Namen, Umbenennen macht ihn also nicht kaputt. Über dem Text siehst du, wohin eine Notiz verweist und welche Einträge auf sie zeigen.

Notizen lassen sich jetzt in Ordner sortieren, mit einer Ebene Unterordnern. Solange du keinen Ordner anlegst, ändert sich nichts. Dazu kommen ein Archiv für Notizen, gespeicherte Ansichten, Suchen und Ersetzen, eine Gliederung zum Springen zwischen Überschriften und eine Rechtschreibprüfung, die die Wörterbücher deines Betriebssystems nutzt (unter Linux braucht sie Enchant mit einem Hunspell-Wörterbuch).

Behält eine Aufnahme ihr Audio, zeigt „Audio nach Sätzen“ jeden Satz mit seiner Stelle in der Aufnahme. Ein Klick spielt ihn ab. So hörst du schnell nach, ob da wirklich „Dienstag“ gesagt wurde.

## Smart Mode für einen Absatz

In Aufnahmen und Notizen arbeitet Smart Mode jetzt auch auf einem Teil des Textes. Du markierst eine Stelle und wählst im Kontextmenü „Bereinigen“, „Kürzen“, „Übersetzen …“ oder „Eigener Auftrag …“, oder du drückst Strg+J (auf dem Mac ⌘J). Ohne Auswahl nimmt sich Smart Mode den Absatz am Cursor vor, nie den ganzen Text. Ein einziges Rückgängig bringt den alten Wortlaut zurück, und ändert das Modell Zahlen oder Namen, ersetzt WhisPaste nichts.

## Ruhe beim Diktieren

Unter Einstellungen → Aufnahme & Audio → „Medien beim Diktat“ wählst du „Pausieren“ oder „Leiser stellen“. Läuft Musik oder ein Video, wird es während des Diktats angehalten oder leiser und danach wieder so laut wie vorher, auch wenn du das Diktat abbrichst. Auch diese Idee kam vom Ideenboard. Auf dem Mac lassen sich Musik und Spotify pausieren; anderes, etwa ein Video im Browser, wird ab macOS 14.2 leiser gestellt.

## Und noch einiges mehr

- Die App gibt es jetzt auch auf Französisch, Italienisch und vereinfachtem Chinesisch. Diese Übersetzungen haben noch keine Muttersprachler gelesen. Korrekturen nehmen wir gern an.
- Mit OpenAI oder Deepgram gehen Aufnahmen ab 30 Sekunden als komprimiertes Opus-Audio raus. Ein Abschnitt von zehn Minuten schrumpft von etwa 19 MB auf etwa 2,4 MB.
- Das Leerzeichen, das die Erkennung oft an den Zeilenanfang setzt, entfernt WhisPaste vor dem Einfügen.
- Erfundene Zeilen am Ende eines Diktats wie „Untertitel von …“ verschwinden, aber nur, wenn an der Stelle wirklich Stille war.
- Videos importierst du jetzt auch als MPEG, VOB und MPEG-TS, etwa von Camcorder, DVD oder TV-Aufnahme.
- „Mit WhisPaste transkribieren“ steht unter Windows jetzt auch in der Store-Version im Kontextmenü des Explorers, für Audio und Video.
- Über die Kommandozeile startest, stoppst und brichst du Diktate ab oder transkribierst eine Datei, praktisch für eigene Tastenkürzel unter Wayland.

## Danke

[artepdoos](https://github.com/artepdoos) hat auf GitHub gemeldet, dass gespeicherte API-Schlüssel von OpenAI und Deepgram nach einem Neustart nicht mehr geladen wurden. Das betraf 1.5.0 bis 1.5.2 und ist behoben; der Schlüssel selbst blieb die ganze Zeit gespeichert. [H-Masoumi](https://github.com/H-Masoumi) hat die Arbeit an den Sprachen angestoßen. Danke euch, und allen, die auf dem Ideenboard abgestimmt haben.

## Auf 1.5.5 aktualisieren

Lade WhisPaste 1.5.5 über den [Download](/download/) herunter. Nutzt du die Version aus dem Microsoft Store oder dem Mac App Store, kommt das Update dort an, sobald der Store es freigegeben hat. Nach dem Start zeigt die Übersicht eine Karte mit den wichtigsten Neuerungen. Wenn du mehrsprachig diktierst, lohnt sich als Erstes ein Blick auf deine Favoriten-Sprachen.
