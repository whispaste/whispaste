# WhisPaste

> WhisPaste è un’app di dettatura per Windows, Mac con Apple Silicon e Linux: premi una scorciatoia, parli e il testo compare nel campo in cui stai scrivendo. Il riconoscimento vocale avviene localmente sul tuo computer e non serve alcun account. È open source con licenza MIT e gratuita su GitHub; le versioni del Microsoft Store e del Mac App Store sono un acquisto una tantum senza abbonamento; l’acquisto non sblocca nulla.

## Cosa fa WhisPaste

- Tieni premuta una scorciatoia globale in qualsiasi applicazione mentre parli e la rilasci per fermare, oppure la tocchi una volta per iniziare e di nuovo per fermare.
- WhisPaste trascrive la registrazione sul tuo computer e copia il testo negli appunti. Con l’incolla automatico attivo, lo inserisce nel punto del cursore dell’applicazione attiva, in quasi tutte le app.
- Pensato per chi scrive molto al computer: e-mail, messaggi, documenti, note, prompt e commenti nel codice.

## Cosa aggiunge WhisPaste oltre le basi

Locale, senza account e gratuito da usare è il punto di partenza. In più, WhisPaste offre:

- Smart Mode con modalità pronte: pulire, accorciare o tradurre in una di sette lingue prima di incollare il testo. Per cambiare un testo selezionato, di' cosa deve cambiare.
- Smart Mode funziona con un modello di testo locale che WhisPaste scarica per te quando lo chiedi; non serve installare altro software (sperimentale su Linux). In alternativa, usa la tua chiave OpenAI.
- Registrazioni, note e blocchi di testo in un unico editor, con la stessa barra degli strumenti, le stesse scorciatoie e il salvataggio automatico.
- Un dizionario con sostituzioni che propone nuove sostituzioni a partire dalle tue correzioni.
- Cronologia, note, dizionario, blocchi di testo e registrazioni conservate sono salvati cifrati con la chiave dati propria del tuo dispositivo.
- Disponibile nel Microsoft Store e nel Mac App Store: su Windows si installa senza l'avviso di SmartScreen e si aggiorna in background tramite lo store; sul Mac installazione e aggiornamenti passano dall'App Store. Acquisto unico, senza abbonamento; l'acquisto finanzia lo sviluppo.

## Riconoscimento vocale

- Due motori locali: Whisper (whisper.cpp, 99 lingue, varie dimensioni di modello) e Parakeet (circa 25 lingue europee, veloce anche senza GPU).
- Dopo un unico download del modello, il riconoscimento locale funziona offline.
- La GPU è facoltativa. L’accelerazione usa Metal su Apple Silicon e Vulkan su Windows e Linux; per NVIDIA è disponibile un pacchetto CUDA facoltativo. Senza GPU il riconoscimento gira sulla CPU.
- Riconoscimento cloud facoltativo tramite OpenAI o Deepgram con la tua chiave API.
- Sui Mac con macOS 26 o successivo, il riconoscimento vocale di Apple sul dispositivo è una terza opzione.

## Smart Mode (facoltativo, disattivato per impostazione predefinita)

- Pulizia rimuove le parole riempitive e corregge la punteggiatura, Sintesi accorcia il testo, Traduci lo converte in tedesco, inglese, spagnolo, francese, portoghese, cinese mandarino o russo.
- Funziona localmente (macOS e Windows; sperimentale su Linux) oppure tramite OpenAI con la tua chiave API.
- Preset propri con una tua istruzione (fino a 500 caratteri); un preset si può applicare in seguito a una registrazione precedente e l’originale resta. Al posto di OpenAI funziona anche un tuo server compatibile (per esempio Ollama, LM Studio, llama.cpp o KoboldCpp) sul computer o nella rete locale.

## Nell’uso quotidiano

- Area locale Registrazioni con ricerca, filtri, salvataggio automatico e cronologia delle versioni, più note con titoli, immagini, liste di controllo, vista di lettura e modalità concentrazione.
- Snippet: blocchi di testo salvati, inseriti con una scorciatoia o con una parola chiave pronunciata; gli snippet interattivi compilano un modello.
- Importazione di file: trascrivi audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) e video (MP4, MOV, MKV, WebM), fino a 1 GB e 6 ore. I file audio si possono inviare anche dal file manager: con «Apri con» su Mac, su Linux e nella versione Microsoft Store per Windows, oppure con il tasto destro con l’installer per Windows del sito.
- Se vuoi, WhisPaste mette in pausa musica e video su Windows e Linux mentre detti, e l’invio dopo l’incolla preme Invio dopo aver incollato (tieni premuto Alt mentre rilasci la scorciatoia; su Linux solo X11).
- “Even out volume automatically” (attivo per impostazione predefinita) alza la voce bassa prima del riconoscimento senza amplificare silenzio o rumore.
- Fino a cinque lingue di riconoscimento preferite, contrassegnate con la stella, compaiono per prime nei menu della lingua; una scorciatoia passa dall’una all’altra.
- Il vocabolario contiene nomi e termini specialistici; le sostituzioni correggono grafie ricorrenti e WhisPaste ne propone di nuove dalle tue correzioni ripetute.
- I profili stabiliscono lingua, modello vocale, Smart Mode, microfono e uscita per un’app specifica.
- Modifica la selezione (facoltativo, disattivato per impostazione predefinita): seleziona del testo in un’app supportata, premi la sua scorciatoia e di’ cosa cambiare, per esempio “più breve” o “traduci”; Smart Mode riscrive la selezione.
- Se una trascrizione non riesce, l’audio viene conservato per 24 ore per impostazione predefinita, anche dopo un crash, così puoi riprovare.
- Accessibilità: impostazioni, note e strumenti dell’editor funzionano con tastiera e screen reader; con la modalità a tocco non devi mai tenere premuto un tasto.

## Privacy

- Con il riconoscimento locale l’audio resta sul tuo computer e viene eliminato dopo la trascrizione, a meno che tu non attivi la conservazione dell’audio.
- Su Windows e nella versione per macOS da GitHub WhisPaste non incolla automaticamente nei campi password; il testo resta negli appunti.
- Trascrizioni, note, vocabolario, snippet e audio conservato sono salvati in forma cifrata con una chiave dati nell’archivio delle chiavi del sistema (portachiavi di macOS, protezione dati di Windows, Secret Service di Linux). Puoi fare un backup della chiave come codice di recupero o file.
- Non serve alcun account.
- Le statistiche d’uso anonime e i rapporti sugli arresti anomali sono attivi per impostazione predefinita. Non contengono audio, trascrizioni né cronologia e si possono disattivare singolarmente in Impostazioni → Privacy.
- Le funzioni cloud inviano dati solo al fornitore scelto e solo quando le usi.

## Piattaforme e requisiti

- Windows 10 o successivo, macOS 13 Ventura o successivo su Apple Silicon (i Mac Intel non sono supportati), Linux x64 (AppImage, .deb, tar.gz) su Ubuntu 26.04 o successivo con glibc 2.43; sui sistemi Linux più vecchi resta la versione 1.4.2.
- Su Linux funziona con X11 e Wayland. Con Wayland è il desktop ad assegnare la scorciatoia globale (tramite il portale delle scorciatoie su GNOME e KDE, oppure con una scorciatoia personalizzata che esegue `whispaste --toggle`), e alcune funzioni extra come i tasti singoli, il doppio tocco e l’invio dopo l’incolla richiedono X11. L’incolla automatico su Linux richiede un’autorizzazione una tantum (tastiera uinput o portale del desktop); senza di essa il testo resta negli appunti.
- Consigliati: almeno 8 GB di RAM e un processore a 64 bit.
- Solo desktop; non esiste una versione per iOS o Android.

## Come ottenere WhisPaste e quanto costa

- Gratis su GitHub, l’app completa con licenza MIT: installer per Windows (WhisPaste-Setup.exe) o ZIP portatile, DMG per macOS, AppImage, .deb e tar.gz per Linux. Gestori di pacchetti: winget (`SilvioLindstedt.WhisPaste`) e Scoop su Windows, Homebrew su macOS. Puoi anche compilarla da solo dal codice sorgente.
- Microsoft Store (Windows) e Mac App Store (macOS): acquisto una tantum, nessun abbonamento. Il prezzo attuale è indicato nello store.
- Cosa aggiunge la versione dello store: su Windows l’installazione senza l’avviso di SmartScreen che l’installer non firmato di GitHub può mostrare, e aggiornamenti automatici tramite il Microsoft Store. Su macOS installazione e aggiornamenti tramite l’App Store. L’acquisto finanzia lo sviluppo.
- L’acquisto non sblocca nulla; la versione gratuita resta completa, senza nulla di bloccato o limitato nel tempo. Le versioni GitHub per Windows e macOS cercano nuove versioni e installano un aggiornamento solo dopo la tua conferma; su Linux WhisPaste segnala soltanto la nuova versione e ne mostra il link, e la installi tu a mano.
- In cosa differiscono le versioni: il pacchetto CUDA facoltativo per le schede NVIDIA recenti è disponibile solo nelle versioni GitHub (Windows e Linux), non nella versione del Microsoft Store; l’accelerazione GPU tramite Vulkan funziona in entrambe. La versione del Mac App Store gira nella sandbox delle app di Apple: non può imparare dalle correzioni che fai in altre app, non riconosce i campi password, non ha il ripiego AppleScript per incollare né lo strumento che ripara i permessi di macOS; la versione da GitHub ha tutto questo. Sul Mac App Store c’è per ora una versione precedente, quindi l’importazione di file audio e video vi arriverà con il prossimo aggiornamento dello store.
- Una nuova versione può arrivare sul Mac App Store dopo che su GitHub, perché Apple esamina ogni aggiornamento.
- Nessun abbonamento e nessun account. Se scegli un fornitore cloud (OpenAI o Deepgram), ti addebita l’utilizzo direttamente tramite la tua chiave API.

## In cosa WhisPaste si distingue dalla dettatura integrata

- La digitazione vocale integrata in Windows (Win+H) usa il riconoscimento vocale online di Microsoft e richiede una connessione a internet. WhisPaste riconosce la voce sul tuo computer e funziona offline dopo un unico download del modello.
- La dettatura integrata in macOS usa solo il riconoscimento vocale di Apple. In WhisPaste scegli tra Whisper, Parakeet, il riconoscimento di Apple sul dispositivo (macOS 26 o successivo) o un fornitore cloud con la tua chiave.
- Molti desktop Linux non includono alcuna dettatura. WhisPaste porta la sua dettatura anche su Linux, con i limiti di Wayland indicati sopra.
- La dettatura integrata scrive mentre parli. WhisPaste inserisce il testo finito quando smetti, lo conserva nell’area Registrazioni con ricerca, applica il tuo vocabolario e i tuoi snippet, può ripulirlo con Smart Mode e trascrive anche file audio e video.

## Link

- [Sito web](https://whispaste.de/it/)
- [Download](https://whispaste.de/it/download/)
- [Informativa sulla privacy](https://whispaste.de/it/privacy/)
- [Registro delle modifiche](https://whispaste.de/it/changelog/)
- [Codice sorgente su GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Ultima versione su GitHub](https://github.com/whispaste/whispaste/releases/latest)
