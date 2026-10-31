---
title: "Lokal diktieren: Brauche ich eine NVIDIA-Grafikkarte?"
description: "WhisPaste nutzt Vulkan, Metal oder den Prozessor. Welche Hardware vorausgesetzt wird und wann das optionale CUDA-Paket infrage kommt."
date: 2026-10-16
---

Brauchst du eine NVIDIA-Grafikkarte, um auf deinem Rechner lokal zu diktieren? Für WhisPaste lautet die Antwort: nein. Die App unterstützt auch AMD- und Intel-Grafik und kann ohne nutzbare GPU auf dem Prozessor transkribieren. Bevor du über neue Hardware nachdenkst, lohnt sich deshalb ein Blick auf deinen vorhandenen Rechner.

## Die Voraussetzungen zuerst

Du brauchst einen 64-Bit-Prozessor, mindestens 8 GB RAM und freien Speicherplatz für die App und ihre Sprachmodelle. Unterstützt werden Windows 10 oder neuer, Linux sowie macOS 12 Monterey oder neuer auf Apple Silicon.

Beim Mac gilt eine Einschränkung: WhisPaste gibt es dort als Build für Apple Silicon. Auch ältere Prozessoren ohne AVX2 funktionieren, sofern sie die übrigen Systemanforderungen erfüllen.

## AMD, Intel und Apple haben ihren eigenen Zugang

Unter Windows und Linux nutzt WhisPaste Vulkan für die GPU-Beschleunigung. Darüber werden NVIDIA, AMD und Intel mit demselben Build angesprochen. Voraussetzung ist ein funktionierender Vulkan-Treiber.

Auch Intels integrierte Grafik kann mitrechnen, wenn ihr Treiber Vulkan bereitstellt. Eine separate Grafikkarte ist dafür nicht nötig. Auf Apple Silicon läuft die Beschleunigung über Metal; Prozessor und Grafik teilen sich dort den gemeinsamen Speicher.

## CUDA bleibt eine zusätzliche Option

Für die GPU-Nutzung über Vulkan musst du kein CUDA-Toolkit installieren. Wer eine NVIDIA-Karte der RTX- oder GTX-16-Serie besitzt, kann in den GitHub-Builds für Windows und Linux über die Einstellungen ein zusätzliches CUDA-Paket herunterladen.

Das ist eine Option für passende NVIDIA-Hardware. Für AMD, Intel oder den Einstieg mit dem Prozessor brauchst du diesen Download nicht.

## Wenn die GPU nicht mitmacht

Findet WhisPaste keine kompatible GPU, verwendet es den Prozessor. Du kannst diesen Weg auch mit der Einstellung „Nur CPU“ erzwingen.

Hängt das Laden eines Modells auf der GPU, wiederholt WhisPaste den Versuch einmal auf einer reinen CPU-Engine. Nach zwei aufeinanderfolgenden Ladeabstürzen wird die Beschleunigung abgeschaltet, bis du sie in den Einstellungen wieder aktivierst.

Prüfe also zunächst Betriebssystem, Arbeitsspeicher und Treiber deines Rechners. Der [GPU-Kompatibilitätscheck](/gpu-kompatibilitaet/) hilft dir bei der Einordnung und läuft vollständig im Browser, ohne deine Auswahl zu übertragen.
