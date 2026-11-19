# WhisPaste

> WhisPaste est une application de dictée pour Windows, les Mac Apple Silicon et Linux : appuyez sur un raccourci, parlez, et le texte arrive dans le champ où vous écrivez. La reconnaissance vocale s’exécute localement sur votre ordinateur, sans compte. Le code est ouvert sous licence MIT et l’application est gratuite sur GitHub ; les versions du Microsoft Store et du Mac App Store sont un achat unique sans abonnement ; l’achat ne débloque rien.

## Ce que fait WhisPaste

- Vous maintenez un raccourci global dans n’importe quelle application pendant que vous parlez et le relâchez pour arrêter, ou vous appuyez une fois pour démarrer et une seconde fois pour arrêter.
- WhisPaste transcrit l’enregistrement sur votre ordinateur et copie le texte dans le presse-papiers. Avec le collage automatique activé, il insère le texte au curseur de l’application active, dans presque toutes les apps.
- Conçu pour celles et ceux qui écrivent beaucoup sur ordinateur : e-mails, messages, documents, notes, prompts et commentaires de code.

## Ce que WhisPaste apporte au-delà de l’essentiel

Local, sans compte et gratuit à l’usage : c’est le point de départ. En plus, WhisPaste apporte :

- Smart Mode avec des modes prêts à l’emploi : nettoyer, raccourcir ou traduire dans l’une de sept langues avant de coller le texte. Pour modifier un texte sélectionné, dites ce qui doit changer.
- Smart Mode fonctionne avec un modèle de texte local que WhisPaste télécharge pour vous quand vous le demandez ; aucun logiciel supplémentaire à installer (expérimental sous Linux). Vous pouvez aussi utiliser votre propre clé OpenAI.
- Enregistrements, notes et blocs de texte dans un seul éditeur, avec la même barre d’outils, les mêmes raccourcis et l’enregistrement automatique.
- Un dictionnaire avec remplacements qui propose de nouveaux remplacements à partir de vos corrections.
- L’historique, les notes, le dictionnaire, les blocs de texte et les enregistrements conservés sont chiffrés avec la clé de données propre à votre appareil.
- Disponible dans le Microsoft Store et le Mac App Store : sous Windows, installation sans l’avertissement SmartScreen et mises à jour en arrière-plan via le store ; sur Mac, installation et mises à jour via l’App Store. Achat unique, sans abonnement ; l’achat finance le développement.

## Reconnaissance vocale

- Deux moteurs locaux : Whisper (whisper.cpp, 99 langues, plusieurs tailles de modèle) et Parakeet (environ 25 langues européennes, rapide même sans GPU).
- Après un téléchargement unique du modèle, la reconnaissance locale fonctionne hors ligne.
- Un GPU est facultatif. L’accélération utilise Metal sur Apple Silicon et Vulkan sous Windows et Linux ; un pack CUDA facultatif existe pour NVIDIA. Sans GPU, la reconnaissance s’exécute sur le processeur.
- Reconnaissance dans le cloud facultative via OpenAI ou Deepgram avec votre propre clé API.
- Sur les Mac sous macOS 26 ou plus récent, la reconnaissance vocale d’Apple sur l’appareil est une troisième option.

## Smart Mode (facultatif, désactivé par défaut)

- Nettoyer supprime les mots de remplissage et corrige la ponctuation, Condenser raccourcit le texte, Traduire le convertit en allemand, anglais, espagnol, français, portugais, mandarin ou russe.
- Fonctionne localement (macOS et Windows ; expérimental sous Linux) ou via OpenAI avec votre propre clé API.
- Vos propres préréglages avec votre propre consigne (jusqu’à 500 caractères) ; un préréglage peut s’appliquer plus tard à un enregistrement antérieur, l’original est conservé. À la place d’OpenAI, votre propre serveur compatible (par exemple Ollama, LM Studio, llama.cpp ou KoboldCpp) sur votre ordinateur ou votre réseau local fonctionne aussi.

## Au quotidien

- Section locale Enregistrements avec recherche, filtres, enregistrement automatique et historique des versions, plus des notes avec titres, images, cases à cocher, vue lecture et mode concentration.
- Extraits : blocs de texte enregistrés, insérés par raccourci ou par un mot déclencheur prononcé ; les extraits interactifs remplissent un modèle.
- Import de fichiers : transcrivez de l’audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) et de la vidéo (MP4, MOV, MKV, WebM), jusqu’à 1 Go et 6 heures. Un fichier audio peut aussi partir du gestionnaire de fichiers : « Ouvrir avec » sur Mac, sous Linux et dans la version Microsoft Store pour Windows, clic droit avec l’installateur Windows du site.
- En option, WhisPaste met en pause la musique et les vidéos sous Windows et Linux pendant la dictée, et l’envoi après collage appuie sur Entrée une fois le texte collé (maintenir Alt en relâchant le raccourci ; sous Linux, X11 uniquement).
- « Even out volume automatically » (activé par défaut) remonte la voix faible avant la reconnaissance sans amplifier le silence ni le bruit.
- Jusqu’à cinq langues de reconnaissance favorites, marquées d’une étoile, apparaissent en premier dans les menus de langue ; un raccourci passe de l’une à l’autre.
- Le vocabulaire contient noms propres et termes spécialisés ; les remplacements corrigent les graphies récurrentes, et WhisPaste en propose de nouveaux à partir de vos corrections répétées.
- Les profils définissent langue, modèle vocal, Smart Mode, micro et sortie pour une application donnée.
- Modifier une sélection (facultatif, désactivé par défaut) : sélectionnez du texte dans une app prise en charge, appuyez sur son raccourci et dites ce qui doit changer, par exemple « plus court » ou « traduire » ; Smart Mode réécrit la sélection.
- Si une transcription échoue, l’audio est conservé 24 heures par défaut, même après un plantage, pour que vous puissiez réessayer.
- Accessibilité : paramètres, notes et outils de l’éditeur fonctionnent au clavier et avec un lecteur d’écran ; avec le mode appui, vous n’avez jamais à maintenir une touche.

## Confidentialité

- Avec la reconnaissance locale, l’audio reste sur votre ordinateur et est supprimé après la transcription, sauf si vous activez sa conservation.
- Sous Windows et dans la version macOS de GitHub, WhisPaste ne colle pas automatiquement dans les champs de mot de passe ; le texte reste dans le presse-papiers.
- Transcriptions, notes, vocabulaire, snippets et audio conservé sont stockés chiffrés avec une clé de données dans le trousseau du système (trousseau macOS, protection des données de Windows, Secret Service de Linux). Vous pouvez sauvegarder la clé sous forme de code de récupération ou de fichier.
- Aucun compte n’est nécessaire.
- Les statistiques d’utilisation anonymes et les rapports de plantage sont activés par défaut. Ils ne contiennent ni audio, ni transcriptions, ni historique, et chacun se désactive dans Réglages → Confidentialité.
- Les fonctions cloud n’envoient des données qu’au fournisseur choisi, et seulement lorsque vous les utilisez.

## Plateformes et configuration requise

- Windows 10 ou ultérieur, macOS 13 Ventura ou ultérieur sur Apple Silicon (les Mac Intel ne sont pas pris en charge), Linux x64 (AppImage, .deb, tar.gz) sous Ubuntu 26.04 ou ultérieur avec glibc 2.43 ; les systèmes Linux plus anciens restent sur la version 1.4.2.
- Sous Linux, WhisPaste fonctionne avec X11 et Wayland. Sous Wayland, c’est le bureau qui attribue le raccourci global (via le portail de raccourcis sous GNOME et KDE, ou un raccourci personnalisé qui lance `whispaste --toggle`), et quelques extras comme les touches seules, le double appui et l’envoi après collage nécessitent X11. Le collage automatique sous Linux demande une autorisation unique (clavier uinput ou portail du bureau) ; sans elle, le texte reste dans le presse-papiers.
- Recommandé : au moins 8 Go de RAM et un processeur 64 bits.
- Ordinateur uniquement ; il n’existe pas de version iOS ni Android.

## Comment obtenir WhisPaste et ce qu’il coûte

- Gratuit sur GitHub, l’application complète sous licence MIT : installeur Windows (WhisPaste-Setup.exe) ou ZIP portable, DMG pour macOS, AppImage, .deb et tar.gz pour Linux. Gestionnaires de paquets : winget (`SilvioLindstedt.WhisPaste`) et Scoop sous Windows, Homebrew sous macOS. Vous pouvez aussi la compiler vous-même à partir du code source.
- Microsoft Store (Windows) et Mac App Store (macOS) : achat unique, sans abonnement. Le store affiche le prix actuel.
- Ce qu’apporte la version du store : sous Windows, l’installation sans l’avertissement SmartScreen que peut déclencher l’installeur non signé de GitHub, et des mises à jour automatiques via le Microsoft Store. Sous macOS, l’installation et les mises à jour via l’App Store. L’achat finance le développement.
- L’achat ne débloque rien ; la version gratuite reste complète, sans rien de verrouillé ni de limité dans le temps. Les versions GitHub pour Windows et macOS recherchent les nouvelles versions et n’installent une mise à jour qu’après votre confirmation ; sous Linux, WhisPaste signale seulement la nouvelle version et renvoie vers elle, et vous l’installez vous-même.
- Ce qui diffère entre les versions : le pack CUDA facultatif pour les cartes NVIDIA récentes n’est disponible que dans les versions GitHub (Windows et Linux), pas dans la version du Microsoft Store ; l’accélération GPU via Vulkan fonctionne dans les deux. La version du Mac App Store s’exécute dans le bac à sable des apps d’Apple : elle ne peut pas apprendre des corrections que vous faites dans d’autres apps, ne détecte pas les champs de mot de passe, n’a pas de solution de repli AppleScript pour coller ni d’outil de réparation des autorisations macOS ; la version GitHub a tout cela. Le Mac App Store propose pour l’instant une version plus ancienne : l’import de fichiers audio et vidéo y arrivera avec la prochaine mise à jour du store.
- Une nouvelle version peut arriver sur le Mac App Store plus tard que sur GitHub, car Apple examine chaque mise à jour.
- Ni abonnement ni compte. Si vous choisissez un fournisseur cloud (OpenAI ou Deepgram), il vous facture directement son utilisation via votre propre clé d’API.

## Ce qui distingue WhisPaste de la dictée intégrée

- La saisie vocale intégrée à Windows (Win+H) utilise la reconnaissance vocale en ligne de Microsoft et nécessite une connexion internet. WhisPaste reconnaît la parole sur votre ordinateur et fonctionne hors ligne après un téléchargement unique du modèle.
- La dictée intégrée à macOS n’utilise que la reconnaissance vocale d’Apple. Dans WhisPaste, vous choisissez entre Whisper, Parakeet, la reconnaissance d’Apple sur l’appareil (macOS 26 ou ultérieur) ou un fournisseur cloud avec votre propre clé.
- Beaucoup de bureaux Linux n’intègrent aucune dictée. WhisPaste apporte aussi sa dictée sous Linux, avec les limites de Wayland indiquées plus haut.
- La dictée intégrée tape pendant que vous parlez. WhisPaste insère le texte terminé quand vous vous arrêtez, le conserve dans l’espace Enregistrements avec recherche, applique votre vocabulaire et vos snippets, peut le nettoyer avec Smart Mode et transcrit aussi des fichiers audio et vidéo.

## Liens

- [Site web](https://whispaste.de/fr/)
- [Téléchargement](https://whispaste.de/fr/download/)
- [Politique de confidentialité](https://whispaste.de/fr/privacy/)
- [Journal des modifications](https://whispaste.de/fr/changelog/)
- [Code source sur GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Dernière version sur GitHub](https://github.com/whispaste/whispaste/releases/latest)
