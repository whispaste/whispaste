---
title: "Which model size do you need for local dictation?"
description: "Quick & Compact, Balanced or Best Quality: how much graphics memory the three WhisPaste models need and which one to start with."
date: 2026-10-16
---

Dictating locally means the speech recognition model runs on your computer and the recording never leaves it. For that, the model has to fit your hardware. WhisPaste offers exactly three sizes. All of them run fully offline and cover 99 languages.

## The three sizes

- **Quick & Compact** (whisper-small) needs about 900 MB of graphics memory. It keeps a modest machine responsive and is the right entry point with integrated graphics, an older card, or no GPU at all.
- **Balanced** (whisper-medium) wants about 1.5 GB of graphics memory. It is usually more accurate than the compact tier on accents and technical vocabulary, without the memory appetite of the top tier.
- **Best Quality** is recommended from about 3.6 GB of graphics memory on NVIDIA, from 4 GB on Apple Silicon and from 12 GB on AMD or Intel.

All memory figures are our own estimates.

## What to start with

On NVIDIA or Apple Silicon, start with Balanced from about 2 GB of graphics memory (Apple: unified memory); on AMD or Intel, from about 4 GB. Below that, or without a GPU, take Quick & Compact. Switching later costs one download, since the app fetches a single file.

## Parakeet as an alternative

Besides Whisper, WhisPaste ships the Parakeet engine. It trades language breadth for speed: it supports 25 European languages and was several times faster than the compact Whisper model on the processor in our benchmark. With a GPU it is faster still.

More in the [Whisper model size guide](/en/whisper-model-size/) and on the [offline speech-to-text](/en/offline-speech-to-text/) page.
