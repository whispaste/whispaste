# WhisPaste

> WhisPaste è un’app di input vocale gratuita e con licenza MIT per Windows, Mac con Apple Silicon e Linux: premi una scorciatoia, parli e il testo compare nel campo di testo attivo. Il riconoscimento vocale avviene localmente sul tuo computer.

## Cosa fa WhisPaste

- Tieni premuta una scorciatoia globale in qualsiasi applicazione mentre parli e la rilasci per fermare, oppure la tocchi una volta per iniziare e di nuovo per fermare.
- WhisPaste trascrive la registrazione sul tuo computer e copia il testo negli appunti. Con l’incolla automatico attivo, lo inserisce nel punto del cursore dell’applicazione attiva, in quasi tutte le app.
- Pensato per chi scrive molto al computer: e-mail, messaggi, documenti, note, prompt e commenti nel codice.

## Riconoscimento vocale

- Due motori locali: Whisper (whisper.cpp, 99 lingue, varie dimensioni di modello) e Parakeet (circa 25 lingue europee, veloce anche senza GPU).
- Dopo un unico download del modello, il riconoscimento locale funziona offline.
- La GPU è facoltativa. L’accelerazione usa Metal su Apple Silicon e Vulkan su Windows e Linux; per NVIDIA è disponibile un pacchetto CUDA facoltativo. Senza GPU il riconoscimento gira sulla CPU.
- Riconoscimento cloud facoltativo tramite OpenAI o Deepgram con la tua chiave API.
- Sui Mac con macOS 26 o successivo, il riconoscimento vocale di Apple sul dispositivo è una terza opzione.

## Smart Mode (facoltativo, disattivato per impostazione predefinita)

- Pulizia rimuove le parole riempitive e corregge la punteggiatura, Sintesi accorcia il testo, Traduci lo converte in tedesco, inglese, spagnolo, francese, portoghese, cinese mandarino o russo.
- Funziona localmente (macOS e Windows; sperimentale su Linux) oppure tramite OpenAI con la tua chiave API.
- Preset propri con una tua istruzione (fino a 500 caratteri); un preset si può applicare in seguito a una registrazione precedente e l’originale resta. Al posto di OpenAI funziona anche un tuo server compatibile (per esempio LM Studio o Ollama) sul computer o nella rete locale.

## Nell’uso quotidiano

- Area locale Registrazioni con ricerca, filtri, salvataggio automatico e cronologia delle versioni, più note con titoli, immagini, liste di controllo, vista di lettura e modalità concentrazione.
- Snippet: blocchi di testo salvati, inseriti con una scorciatoia o con una parola chiave pronunciata; gli snippet interattivi compilano un modello.
- Importazione di file: trascrivi audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) e video (MP4, MOV, MKV, WebM), fino a 1 GB e 6 ore. I file audio si possono inviare anche dal file manager: con «Apri con» su Mac, su Linux e nella versione Microsoft Store per Windows, oppure con il tasto destro con l’installer per Windows del sito.
- Se vuoi, WhisPaste mette in pausa musica e video su Windows e Linux mentre detti, e l’invio dopo l’incolla preme Invio dopo aver incollato (tieni premuto Alt mentre rilasci la scorciatoia; su Linux solo X11).
- “Even out volume automatically” (attivo per impostazione predefinita) alza la voce bassa prima del riconoscimento senza amplificare silenzio o rumore.
- Fino a cinque lingue di riconoscimento preferite, contrassegnate con la stella, compaiono per prime nei menu della lingua; una scorciatoia passa dall’una all’altra.
- Il vocabolario contiene nomi e termini specialistici; le sostituzioni correggono grafie ricorrenti e WhisPaste ne propone di nuove dalle tue correzioni ripetute.
- I profili stabiliscono lingua, modello vocale, Smart Mode, microfono e uscita per un’app specifica.
- Se una trascrizione non riesce, l’audio viene conservato per 24 ore per impostazione predefinita, anche dopo un crash, così puoi riprovare.
- Accessibilità: impostazioni, note e strumenti dell’editor funzionano con tastiera e screen reader; con la modalità a tocco non devi mai tenere premuto un tasto.

## Privacy

- Con il riconoscimento locale l’audio resta sul tuo computer e viene eliminato dopo la trascrizione, a meno che tu non attivi la conservazione dell’audio.
- Su macOS e Windows WhisPaste non incolla automaticamente nei campi password; il testo resta negli appunti.
- Trascrizioni, note, vocabolario, snippet e audio conservato sono salvati in forma cifrata con una chiave dati nell’archivio delle chiavi del sistema (portachiavi di macOS, protezione dati di Windows, Secret Service di Linux). Puoi fare un backup della chiave come codice di recupero o file.
- Non serve alcun account.
- Le statistiche d’uso e i rapporti sugli arresti anomali non contengono audio, trascrizioni né cronologia e si possono disattivare in Impostazioni → Privacy.
- Le funzioni cloud inviano dati solo al fornitore scelto e solo quando le usi.

## Piattaforme e requisiti

- Windows 10 o successivo, macOS 13 Ventura o successivo su Apple Silicon (i Mac Intel non sono supportati), Linux x64 (AppImage, .deb, tar.gz) su Ubuntu 26.04 o successivo con glibc 2.43; sui sistemi Linux più vecchi resta la versione 1.4.2.
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
