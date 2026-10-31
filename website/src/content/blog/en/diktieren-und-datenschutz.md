---
title: "Dictation and privacy: What stays on your computer?"
description: "What WhisPaste processes locally, which data may use the network, and what changes when you choose a cloud provider."
date: 2026-10-16
---

What happens to your voice after you dictate a sentence? With WhisPaste, the answer depends on where you choose to run speech recognition. Local processing is the default. To make an informed choice, it also helps to look at stored transcripts and the privacy settings.

## What remains after transcription

Whisper and Parakeet can transcribe a recording directly on your computer. The speech model downloads during setup; local speech recognition needs no internet connection after that. You do not need an account either.

Once transcription finishes, the recording is discarded unless you enable audio retention yourself. The recognized text stays in your local history. That history lives in a SQLite database on your computer and is not synced to a cloud. Dictating locally therefore does not mean that nothing is saved afterwards.

## What can still use the network

Usage statistics and crash reports are enabled by default. Statistics record feature use but exclude audio, transcripts and history. They use no cookies and rely on a pseudonymous weekly value that changes every week. Crash reports also exclude audio and text, and personal data is removed before they are sent.

You can turn both off under Settings → Privacy. The app’s update check can be disabled too. If you care about the connections the app makes as well as where transcription happens, review these settings during setup. Choosing a local engine does not switch off statistics or crash reports.

## What changes when you choose the cloud

You can use OpenAI or Deepgram with your own API key instead. In that case, the recording leaves your computer and goes straight to the selected provider, without passing through a WhisPaste server. That provider’s terms govern the processing.

The choice is yours. WhisPaste does not silently switch to cloud transcription because local processing is taking too long.

To get started, choose local transcription, decide whether to keep recordings, and review your privacy settings. The [speech recognition privacy guide](/en/privacy-speech-recognition/) explains how these choices fit together.
