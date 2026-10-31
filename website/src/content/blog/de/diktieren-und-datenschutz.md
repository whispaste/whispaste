---
title: "Diktieren und Datenschutz: Was bleibt auf deinem Rechner?"
description: "Was WhisPaste lokal verarbeitet, welche Daten ins Netz gehen können und was sich ändert, wenn du einen Cloud-Anbieter auswählst."
date: 2026-10-16
---

Was passiert mit deiner Stimme, nachdem du einen Satz diktiert hast? Bei WhisPaste hängt die Antwort davon ab, wo du die Spracherkennung ausführen lässt. Lokal ist der Standard. Für eine bewusste Entscheidung lohnt sich außerdem ein Blick auf gespeicherte Texte und die Datenschutzeinstellungen.

## Was nach dem Diktieren gespeichert bleibt

Whisper und Parakeet können die Aufnahme direkt auf deinem Rechner transkribieren. Das Sprachmodell wird bei der Einrichtung heruntergeladen; danach braucht die lokale Spracherkennung keine Internetverbindung. Ein Konto brauchst du dafür ebenfalls nicht.

Nach der Transkription wird die Aufnahme verworfen, außer du aktivierst selbst das Speichern von Audio. Der erkannte Text bleibt dagegen im lokalen Verlauf erhalten. Dieser liegt in einer SQLite-Datenbank auf deinem Rechner und wird nicht mit einer Cloud synchronisiert. Lokal diktieren bedeutet also nicht, dass hinterher überhaupt nichts gespeichert ist.

## Welche Verbindungen trotzdem möglich sind

Nutzungsstatistik und Absturzberichte sind standardmäßig eingeschaltet. Die Statistik erfasst Funktionsnutzung, enthält aber weder Audio noch Transkripte oder Verlauf. Sie kommt ohne Cookies aus und verwendet eine zufällige Kennung, die jede Woche wechselt. Absturzberichte enthalten ebenfalls weder Audio noch Text und werden vor dem Versand von personenbezogenen Daten bereinigt.

Beides kannst du unter Einstellungen → Datenschutz ausschalten. Auch die App-Prüfung auf Updates lässt sich abschalten. Wenn dir neben der lokalen Verarbeitung wichtig ist, welche Verbindungen die App aufbaut, prüfe diese Einstellungen bei der Einrichtung mit. Die Wahl einer lokalen Engine allein schaltet Statistik und Absturzberichte nicht aus.

## Was eine Cloud-Auswahl verändert

Du kannst stattdessen OpenAI oder Deepgram mit deinem eigenen API-Schlüssel verwenden. Dann verlässt die Aufnahme deinen Rechner: Sie geht direkt zum gewählten Anbieter, ohne Umweg über einen WhisPaste-Server. Für die Verarbeitung dort gelten dessen Bedingungen.

Diese Entscheidung triffst du selbst. WhisPaste wechselt nicht still zur Cloud, weil die lokale Transkription zu langsam wäre.

Für deinen Einstieg heißt das: lokal transkribieren, über die Audio-Speicherung entscheiden und die Datenschutzeinstellungen prüfen. Die Zusammenhänge findest du ausführlicher auf der Seite [Privatsphäre bei der Spracherkennung](/privatsphaere-spracherkennung/).
