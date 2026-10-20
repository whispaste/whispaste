---
title: "From hotkey to text: Dictate in the window you’re using"
description: "Get spoken words into the active text field with Auto-Paste, plus notes on the clipboard, checking your text, and Linux setup."
date: 2026-10-16
---

How do you get a spoken sentence into your email without switching to another window? That is what WhisPaste is built for: you start recording where you are already writing. With Auto-Paste enabled, the transcript then appears at your cursor.

## Start in the text field you want to use

Place the cursor where your words should go. That might be an Outlook reply, a Slack message, a browser text field or your editor. Press the hotkey, speak, then press it again to end the recording.

You can speak paragraph breaks too: in English, German, Spanish, Portuguese and Russian, say “new paragraph” or “new line”. If you decide to discard the recording, press Esc.

Try the process with a short piece of text you already need to write. That gives you something useful to work with while you decide whether speaking suits the way you write.

## Enable Auto-Paste and check the result

WhisPaste offers Auto-Paste during setup. When it is enabled, the app inserts the transcript into the active text field. Otherwise, it copies the result to your clipboard for you to paste yourself.

Read through the text and make any edits in your application. Recognition accuracy depends on the model you choose, so a quick check belongs in the routine. If you want to find a transcript again later, WhisPaste also has a searchable history where you can edit and organize entries.

## Check the Linux setup once

On Linux, Auto-Paste needs a permission rule for `/dev/uinput`. With the .deb package, you allow it in the app with your administrator password and can remove it there again; with AppImage or tar.gz, you set it up once using sudo. Without the rule, the result stays in your clipboard, ready to paste with Ctrl+V.

On Wayland, configure the hotkey through your desktop environment. Bind it to `whispaste --toggle`; for an AppImage, use its full path followed by `--toggle` instead.

What matters is how this fits into your writing: place the cursor, speak, check the text and carry on. For more ways to use it, see the guide to [voice input for everyday writing](/en/use-cases/everyday/).
