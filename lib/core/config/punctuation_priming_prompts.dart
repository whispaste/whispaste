/// Default punctuation-priming prompts for [SttSettings.punctuationPriming].
///
/// Whisper's `initial_prompt` mechanism works through **style mimicry**, not
/// instruction-following — passing an unpunctuated prompt (or an explicit
/// instruction like "add punctuation") makes results worse, while a short,
/// punctuated, conversational prompt in the *same* language as the dictation
/// measurably improves punctuation in the output, especially under the
/// greedy decoding WhisPaste uses for latency (see ADR
/// `.scratch/whisper-ffi-engine/issues/23-default-punctuation-priming.md`).
///
/// Source of truth: `ggml-org/whisper.cpp` server docs + community guidance
/// (https://github.com/ggml-org/whisper.cpp/discussions/348). Covers the
/// languages WhisPaste's user base concentrates in; deliberately not all 99
/// Whisper languages — a wrong-language prompt does not reliably transfer
/// the style-mimicry effect, so uncovered languages simply get no prompt
/// (identical to today's behavior, never a regression).
library;

const Map<String, String> punctuationPrimingPrompts = {
  'en': 'Hello, how are you doing today? I hope everything is going well.',
  'de': 'Hallo, wie geht es dir heute? Ich hoffe, es läuft alles gut bei dir.',
  'fr': "Bonjour, comment vas-tu aujourd'hui ? J'espère que tout va bien.",
  'es': '¿Hola, cómo estás hoy? Espero que todo te vaya bien.',
  'it': 'Ciao, come stai oggi? Spero che vada tutto bene.',
  'pt': 'Olá, como você está hoje? Espero que esteja tudo bem.',
  'nl': 'Hallo, hoe gaat het vandaag met je? Ik hoop dat alles goed gaat.',
  'pl': 'Cześć, jak się dzisiaj masz? Mam nadzieję, że wszystko dobrze.',
  'ru': 'Привет, как у тебя дела сегодня? Надеюсь, всё хорошо.',
  'tr': 'Merhaba, bugün nasılsın? Umarım her şey yolundadır.',
  'sv': 'Hej, hur mår du idag? Jag hoppas att allt är bra.',
  'da': 'Hej, hvordan har du det i dag? Jeg håber, alt går godt.',
  'no': 'Hei, hvordan har du det i dag? Jeg håper alt går bra.',
  'fi': 'Hei, mitä sinulle kuuluu tänään? Toivottavasti kaikki on hyvin.',
  'cs': 'Ahoj, jak se dnes máš? Doufám, že je vše v pořádku.',
  'uk': 'Привіт, як у тебе справи сьогодні? Сподіваюся, все добре.',
  'ro': 'Bună, ce mai faci azi? Sper că totul e bine.',
  'hu': 'Szia, hogy vagy ma? Remélem minden rendben megy.',
  'el': 'Γεια σου, πώς είσαι σήμερα; Ελπίζω όλα να πηγαίνουν καλά.',
  'ja': 'こんにちは、今日の調子はどうですか？すべて順調だといいのですが。',
  'zh': '你好，你今天怎么样？希望一切都好。',
  'ko': '안녕하세요, 오늘 어떻게 지내세요? 모든 일이 잘 되길 바랍니다.',
  'ar': 'مرحبًا، كيف حالك اليوم؟ آمل أن يكون كل شيء على ما يرام.',
  'hi': 'नमस्ते, आज आप कैसे हैं? मुझे उम्मीद है कि सब कुछ ठीक चल रहा है।',
  'he': 'שלום, מה שלומך היום? אני מקווה שהכל בסדר.',
  'ca': 'Hola, com estàs avui? Espero que tot vagi bé.',
  'bg': 'Здравей, как си днес? Надявам се всичко да е наред.',
  'hr': 'Bok, kako si danas? Nadam se da je sve u redu.',
  'sk': 'Ahoj, ako sa dnes máš? Dúfam, že je všetko v poriadku.',
};

/// Resolves the default punctuation-priming prompt for [languageCode], or
/// `null` when the language is not in [punctuationPrimingPrompts] (`'auto'`
/// included — auto-detect happens after decoding starts, so there is no
/// language to prime with yet).
String? resolvePunctuationPrimingPrompt(String languageCode) =>
    punctuationPrimingPrompts[languageCode];
