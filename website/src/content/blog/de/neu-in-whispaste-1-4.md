---
title: "Neu in WhisPaste 1.4: Sprechen, säubern, per Stimme umformulieren"
description: "Mails mit echten Absätzen sprechen, „äh“ automatisch streichen und markierte Sätze per Stimme kürzen: Das bringt WhisPaste 1.4 für dein Schreiben."
date: 2026-10-17
cover:
  src: "/blog/neu-in-whispaste-1-4/cover.webp"
  alt: "Abstrakte Illustration: ein Textfeld mit Textzeilen, eine lange Zeile cyanfarben markiert, darunter eine kürzere bernsteinfarbene Zeile mit Textcursor"
  og: "/blog/neu-in-whispaste-1-4/og.png"
---

Mit WhisPaste 1.4 kannst du eine Mail mit Absätzen sprechen, Füllwörter herausnehmen und einen langen Satz per Stimme kürzen. Stell dir einen Donnerstagmorgen vor: Eine Kundin wartet auf den Projektstatus. Du weißt, was du sagen möchtest, und willst es direkt ins Mailfenster sprechen.

WhisPaste bringt Gesprochenes unter macOS, Windows und Linux per Auto-Paste ins aktive Textfeld. Die Spracherkennung läuft standardmäßig lokal mit Whisper; dafür brauchst du keine Cloud. In 1.4 kommen neue Handgriffe hinzu, die dich vom ersten Entwurf bis zum Überarbeiten begleiten.

## Absätze gleich mitsprechen

Setze den Cursor ins Mailfenster, drücke deinen Hotkey und sprich: „Guten Morgen, die Entwürfe sind zur Abstimmung bereit. Neuer Absatz. Als Nächstes besprechen wir die offenen Fragen.“ Drücke den Hotkey erneut, um die Aufnahme zu beenden. Mit aktiviertem Auto-Paste steht der Text anschließend in der Mail, samt echtem Absatz.

Neu sind die gesprochenen Zeilenumbrüche: „neuer Absatz“ und „neue Zeile“ werden zu Umbrüchen statt zu Wörtern im Text. **Gesprochene Zeilenumbrüche** ist standardmäßig eingeschaltet. Du findest den Schalter unter Einstellungen → Spracherkennung, falls du die Funktion ausschalten möchtest.

Die Befehle gibt es in allen sechs Oberflächensprachen, auf Spanisch etwa „nuevo párrafo“; sie folgen der Sprache, in der du sprichst. Den grundlegenden Ablauf mit Auto-Paste beschreibt [Vom Hotkey zum Text](/blog/vom-hotkey-zum-text-im-aktiven-fenster/).

## Das „äh“ aus dem Entwurf streichen

Beim Sprechen überlegst du vielleicht noch, wie du den nächsten Schritt formulierst. Ein „äh“ oder „ähm“ soll deshalb nicht in der Statusmail stehen. Aktiviere dafür unter Einstellungen → Spracherkennung den neuen Schalter **Füllwörter entfernen**. Er ist zunächst ausgeschaltet.

<figure><img src="/blog/neu-in-whispaste-1-4/einstellungen-de.webp" alt="Dunkle WhisPaste-Einstellungen mit den Zeilen „Füllwörter entfernen“ und „Gesprochene Zeilenumbrüche“, beide Schalter eingeschaltet" width="1750" height="325" loading="lazy" /><figcaption>Unter Einstellungen → Spracherkennung kannst du beide Funktionen einstellen. Hier sind beide Schalter eingeschaltet; „Füllwörter entfernen“ ist ab Werk aus.</figcaption></figure>

WhisPaste entfernt eindeutige Verlegenheitslaute wie „äh“, „ähm“ und „öhm“ vor dem Speichern oder Einfügen des bereinigten Textes. Wörter mit Bedeutung bleiben erhalten: Das deutsche „um“ („um 8 Uhr“) bleibt zum Beispiel stehen; das englische Füllwort „um“ wird nur bei englischer Erkennungssprache entfernt. Im Verlauf bleibt das Originaltranskript erhalten. Lies die eingefügte Mail anschließend kurz durch, bevor du sie abschickst.

## Einen langen Satz per Stimme kürzen

Beim Lesen fällt dir ein Satz auf, der zu viele Gedanken enthält. Mit dem neuen Hotkey „Auswahl bearbeiten“ kannst du ihn direkt in deiner Mail überarbeiten. Schalte dafür zunächst unter Einstellungen → Smart Mode die Option **Hotkey „Auswahl bearbeiten“** ein. Sie ist standardmäßig aus.

<figure><img src="/blog/neu-in-whispaste-1-4/bearbeiten-de.webp" alt="Dunkle WhisPaste-Einstellungen mit ausgeschaltetem Hotkey „Auswahl bearbeiten“, Beschreibungstext und der Kombination Umschalt + Befehl + &gt; neben „Ändern“" width="1750" height="325" loading="lazy" /><figcaption>Einstellungen → Smart Mode: Aktiviere den Hotkey „Auswahl bearbeiten“. Unter „Kombination“ lässt sich die angezeigte Tastenkombination über „Ändern“ anpassen.</figcaption></figure>

Markiere den Satz, drücke die Tastenkombination, die unter „Kombination“ angezeigt wird, und sage „kürzer“. Das Ergebnis ersetzt die Auswahl. Passt es nicht, holt „Rückgängig“ in deiner Mail-App das Original zurück. Die Zwischenablage wird wiederhergestellt; diese Bearbeitung landet nicht im Verlauf.

Neben „kürzer“ gibt es die Schnellbefehle „verbessern“ und „übersetzen“, jeweils in allen sechs Oberflächensprachen. Andere Sätze gelten als freie Anweisung, etwa „Formuliere das als freundliche Bitte“. Die Bearbeitung nutzt Smart Mode, wahlweise lokal oder über die Cloud. Für die lokale Nutzung muss das passende Smart-Mode-Modell heruntergeladen sein.

## Auch längere Gedanken am Stück festhalten

Nach der Mail möchtest du vielleicht noch deine Überlegungen zum Projekt sammeln. Die „Maximale Aufnahmedauer“ (Einstellungen → Aufnahme-Schutz) reicht jetzt bis 60 Minuten; ganz rechts steht „Unbegrenzt“. Eine Desktop-Verknüpfung mit `whispaste --toggle` startet oder stoppt die Aufnahme in der laufenden App, etwa unter Wayland, über einen Launcher oder ein Stream Deck.

Neu sind außerdem Spanisch und brasilianisches Portugiesisch für die Oberfläche. Zusammen mit Deutsch, Englisch, Russisch und Hebräisch sind es jetzt sechs Sprachen. Die neuen Übersetzungen wurden noch nicht von Muttersprachlern geprüft.

Auf älteren Prozessoren und mit älteren NVIDIA-Karten stürzt WhisPaste nicht mehr ab. Für NVIDIA RTX und GTX 16 gibt es unter Windows und Linux optional ein separates CUDA-Paket unter Einstellungen → Spracherkennung → Grafikbeschleunigung, außerhalb der Microsoft-Store-Version. Ohne passenden CUDA-Treiber bleibt es bei Vulkan. Smart Mode behält sein Modell geladen, sodass es bei wiederholten Umschreibungen nicht jedes Mal neu laden muss.

## Mit einer kurzen Mail anfangen

Weitere Anregungen findest du bei [Spracheingabe für Vielschreiber](/use-cases/vielschreiber/). Für den Einstieg reicht die nächste Mail: Absätze mitsprechen, Fülllaute bei Bedarf entfernen lassen und einen Satz zum Kürzen auswählen.

Wenn du noch 1.3 nutzt, aktualisiere über den [Download](/download/) auf die veröffentlichte Version 1.4.2. Sie enthält die Neuerungen aus 1.4.0 sowie die Fehlerkorrekturen aus 1.4.1 und 1.4.2. Bist du neu dabei, lade WhisPaste herunter und probiere es mit einer kurzen Mail aus.
