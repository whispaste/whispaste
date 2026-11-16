# WhisPaste

> WhisPaste est une application de saisie vocale gratuite, sous licence MIT, pour Windows, les Mac Apple Silicon et Linux : appuyez sur un raccourci, parlez, et le texte arrive dans le champ de texte actif. La reconnaissance vocale s’exécute localement sur votre ordinateur.

## Ce que fait WhisPaste

- Vous maintenez un raccourci global dans n’importe quelle application pendant que vous parlez et le relâchez pour arrêter, ou vous appuyez une fois pour démarrer et une seconde fois pour arrêter.
- WhisPaste transcrit l’enregistrement sur votre ordinateur et copie le texte dans le presse-papiers. Avec le collage automatique activé, il insère le texte au curseur de l’application active, dans presque toutes les apps.
- Conçu pour celles et ceux qui écrivent beaucoup sur ordinateur : e-mails, messages, documents, notes, prompts et commentaires de code.

## Reconnaissance vocale

- Deux moteurs locaux : Whisper (whisper.cpp, 99 langues, plusieurs tailles de modèle) et Parakeet (environ 25 langues européennes, rapide même sans GPU).
- Après un téléchargement unique du modèle, la reconnaissance locale fonctionne hors ligne.
- Un GPU est facultatif. L’accélération utilise Metal sur Apple Silicon et Vulkan sous Windows et Linux ; un pack CUDA facultatif existe pour NVIDIA. Sans GPU, la reconnaissance s’exécute sur le processeur.
- Reconnaissance dans le cloud facultative via OpenAI ou Deepgram avec votre propre clé API.
- Sur les Mac sous macOS 26 ou plus récent, la reconnaissance vocale d’Apple sur l’appareil est une troisième option.

## Smart Mode (facultatif, désactivé par défaut)

- Nettoyer supprime les mots de remplissage et corrige la ponctuation, Condenser raccourcit le texte, Traduire le convertit en allemand, anglais, espagnol, français, portugais, mandarin ou russe.
- Fonctionne localement (macOS et Windows ; expérimental sous Linux) ou via OpenAI avec votre propre clé API.
- Vos propres préréglages avec votre propre consigne (jusqu’à 500 caractères) ; un préréglage peut s’appliquer plus tard à un enregistrement antérieur, l’original est conservé. À la place d’OpenAI, votre propre serveur compatible (par exemple LM Studio ou Ollama) sur votre ordinateur ou votre réseau local fonctionne aussi.

## Au quotidien

- Section locale Enregistrements avec recherche, filtres, enregistrement automatique et historique des versions, plus des notes avec titres, images, cases à cocher, vue lecture et mode concentration.
- Extraits : blocs de texte enregistrés, insérés par raccourci ou par un mot déclencheur prononcé ; les extraits interactifs remplissent un modèle.
- Import de fichiers : transcrivez de l’audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) et de la vidéo (MP4, MOV, MKV, WebM), jusqu’à 1 Go et 6 heures. Un fichier audio peut aussi partir du gestionnaire de fichiers : « Ouvrir avec » sur Mac, sous Linux et dans la version Microsoft Store pour Windows, clic droit avec l’installateur Windows du site.
- En option, WhisPaste met en pause la musique et les vidéos sous Windows et Linux pendant la dictée, et l’envoi après collage appuie sur Entrée une fois le texte collé (maintenir Alt en relâchant le raccourci ; sous Linux, X11 uniquement).
- « Even out volume automatically » (activé par défaut) remonte la voix faible avant la reconnaissance sans amplifier le silence ni le bruit.
- Jusqu’à cinq langues de reconnaissance favorites, marquées d’une étoile, apparaissent en premier dans les menus de langue ; un raccourci passe de l’une à l’autre.
- Le vocabulaire contient noms propres et termes spécialisés ; les remplacements corrigent les graphies récurrentes, et WhisPaste en propose de nouveaux à partir de vos corrections répétées.
- Les profils définissent langue, modèle vocal, Smart Mode, micro et sortie pour une application donnée.
- Si une transcription échoue, l’audio est conservé 24 heures par défaut, même après un plantage, pour que vous puissiez réessayer.
- Accessibilité : paramètres, notes et outils de l’éditeur fonctionnent au clavier et avec un lecteur d’écran ; avec le mode appui, vous n’avez jamais à maintenir une touche.

## Confidentialité

- Avec la reconnaissance locale, l’audio reste sur votre ordinateur et est supprimé après la transcription, sauf si vous activez sa conservation.
- Sous macOS et Windows, WhisPaste ne colle pas automatiquement dans les champs de mot de passe ; le texte reste dans le presse-papiers.
- Transcriptions, notes, vocabulaire, snippets et audio conservé sont stockés chiffrés avec une clé de données dans le trousseau du système (trousseau macOS, protection des données de Windows, Secret Service de Linux). Vous pouvez sauvegarder la clé sous forme de code de récupération ou de fichier.
- Aucun compte n’est nécessaire.
- Les statistiques d’utilisation et les rapports de plantage ne contiennent ni audio, ni transcriptions, ni historique et se désactivent dans Réglages → Confidentialité.
- Les fonctions cloud n’envoient des données qu’au fournisseur choisi, et seulement lorsque vous les utilisez.

## Plateformes et configuration requise

- Windows 10 ou ultérieur, macOS 12 Monterey ou ultérieur sur Apple Silicon (les Mac Intel ne sont pas pris en charge), Linux x64 (AppImage, .deb, tar.gz).
- Recommandé : au moins 8 Go de RAM et un processeur 64 bits.
- Ordinateur uniquement ; il n’existe pas de version iOS ni Android.

## Prix et licence

- L’application complète est gratuite sur GitHub sous licence MIT.
- Les versions payantes du Microsoft Store et du Mac App Store offrent les mêmes fonctions principales, avec des mises à jour via le store.
- Pas d’abonnement. Les fournisseurs cloud facultatifs peuvent facturer leur utilisation.

## Liens

- [Site web](https://whispaste.de/fr/)
- [Téléchargement](https://whispaste.de/fr/download/)
- [Politique de confidentialité](https://whispaste.de/fr/privacy/)
- [Journal des modifications](https://whispaste.de/fr/changelog/)
- [Code source sur GitHub](https://github.com/whispaste/whispaste)
