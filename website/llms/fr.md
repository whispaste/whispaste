# WhisPaste

> WhisPaste est une application de saisie vocale gratuite, sous licence MIT, pour Windows, les Mac Apple Silicon et Linux : appuyez sur un raccourci, parlez, et le texte arrive dans le champ de texte actif. La reconnaissance vocale s’exécute localement sur votre ordinateur.

## Ce que fait WhisPaste

- Vous appuyez sur un raccourci global dans n’importe quelle application, vous parlez, puis vous appuyez à nouveau (ou vous le maintenez pendant que vous parlez).
- WhisPaste transcrit l’enregistrement sur votre ordinateur et copie le texte dans le presse-papiers. Avec le collage automatique activé, il insère le texte au curseur de l’application active, dans presque toutes les apps.
- Conçu pour celles et ceux qui écrivent beaucoup sur ordinateur : e-mails, messages, documents, notes, prompts et commentaires de code.

## Reconnaissance vocale

- Deux moteurs locaux : Whisper (whisper.cpp, 99 langues, plusieurs tailles de modèle) et Parakeet (environ 25 langues européennes, rapide même sans GPU).
- Après un téléchargement unique du modèle, la reconnaissance locale fonctionne hors ligne.
- Un GPU est facultatif. L’accélération utilise Metal sur Apple Silicon et Vulkan sous Windows et Linux ; un pack CUDA facultatif existe pour NVIDIA. Sans GPU, la reconnaissance s’exécute sur le processeur.
- Reconnaissance dans le cloud facultative via OpenAI ou Deepgram avec votre propre clé API.

## Smart Mode (facultatif, désactivé par défaut)

- Nettoyer supprime les mots de remplissage et corrige la ponctuation, Condenser raccourcit le texte, Traduire le convertit en allemand, anglais, espagnol, français, portugais, mandarin ou russe.
- Fonctionne localement (macOS et Windows ; expérimental sous Linux) ou via OpenAI avec votre propre clé API.

## Au quotidien

- Historique local des transcriptions et notes rapides séparées.
- Extraits : blocs de texte enregistrés, insérés par raccourci ou par un mot déclencheur prononcé ; les extraits interactifs remplissent un modèle.
- Import de fichiers : transcrivez des fichiers audio existants.

## Confidentialité

- Avec la reconnaissance locale, l’audio reste sur votre ordinateur et est supprimé après la transcription, sauf si vous activez sa conservation.
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
