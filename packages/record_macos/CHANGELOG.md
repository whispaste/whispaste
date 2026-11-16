## 2.1.1+whispaste.1
* fix: Stop the audio engine before switching voice processing off, and only switch it when the take turned it on. Switching it on a running engine crashed the CoreAudio IO thread.

