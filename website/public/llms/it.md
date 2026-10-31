# WhisPaste

> WhisPaste è un’app di input vocale gratuita e con licenza MIT per Windows, Mac con Apple Silicon e Linux: premi una scorciatoia, parli e il testo compare nel campo di testo attivo. Il riconoscimento vocale avviene localmente sul tuo computer.

## Cosa fa WhisPaste

- Premi una scorciatoia globale in qualsiasi applicazione, parli e la premi di nuovo (oppure la tieni premuta mentre parli).
- WhisPaste trascrive la registrazione sul tuo computer e copia il testo negli appunti. Con l’incolla automatico attivo, lo inserisce nel punto del cursore dell’applicazione attiva, in quasi tutte le app.
- Pensato per chi scrive molto al computer: e-mail, messaggi, documenti, note, prompt e commenti nel codice.

## Riconoscimento vocale

- Due motori locali: Whisper (whisper.cpp, 99 lingue, varie dimensioni di modello) e Parakeet (circa 25 lingue europee, veloce anche senza GPU).
- Dopo un unico download del modello, il riconoscimento locale funziona offline.
- La GPU è facoltativa. L’accelerazione usa Metal su Apple Silicon e Vulkan su Windows e Linux; per NVIDIA è disponibile un pacchetto CUDA facoltativo. Senza GPU il riconoscimento gira sulla CPU.
- Riconoscimento cloud facoltativo tramite OpenAI o Deepgram con la tua chiave API.

## Smart Mode (facoltativo, disattivato per impostazione predefinita)

- Pulizia rimuove le parole riempitive e corregge la punteggiatura, Sintesi accorcia il testo, Traduci lo converte in tedesco, inglese, spagnolo, francese, portoghese, cinese mandarino o russo.
- Funziona localmente (macOS e Windows; sperimentale su Linux) oppure tramite OpenAI con la tua chiave API.

## Nell’uso quotidiano

- Cronologia locale delle trascrizioni e note rapide separate.
- Snippet: blocchi di testo salvati, inseriti con una scorciatoia o con una parola chiave pronunciata; gli snippet interattivi compilano un modello.
- Importazione di file: trascrivi file audio esistenti.

## Privacy

- Con il riconoscimento locale l’audio resta sul tuo computer e viene eliminato dopo la trascrizione, a meno che tu non attivi la conservazione dell’audio.
- Non serve alcun account.
- Le statistiche d’uso e i rapporti sugli arresti anomali non contengono audio, trascrizioni né cronologia e si possono disattivare in Impostazioni → Privacy.
- Le funzioni cloud inviano dati solo al fornitore scelto e solo quando le usi.

## Piattaforme e requisiti

- Windows 10 o successivo, macOS 12 Monterey o successivo su Apple Silicon (i Mac Intel non sono supportati), Linux x64 (AppImage, .deb, tar.gz).
- Consigliati: almeno 8 GB di RAM e un processore a 64 bit.
- Solo desktop; non esiste una versione per iOS o Android.

## Prezzo e licenza

- L’app completa è gratuita su GitHub con licenza MIT.
- Le versioni a pagamento nel Microsoft Store e nel Mac App Store offrono le stesse funzioni principali, con aggiornamenti tramite lo store.
- Nessun abbonamento. I fornitori cloud facoltativi possono addebitare il proprio utilizzo.

## Link

- [Sito web](https://whispaste.de/it/)
- [Download](https://whispaste.de/it/download/)
- [Informativa sulla privacy](https://whispaste.de/it/privacy/)
- [Registro delle modifiche](https://whispaste.de/it/changelog/)
- [Codice sorgente su GitHub](https://github.com/whispaste/whispaste)
