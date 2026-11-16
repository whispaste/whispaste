/**
 * Intent file of the contact widget's FAQ matcher (#351).
 *
 * One intent per FAQ entry: its source is the FAQ key (`faq.<key>.q/a` in
 * `src/i18n/*.ts`, deep link `#faq-<key>`), plus question variants and
 * synonyms per site language that users type but the FAQ text does not say.
 * The FAQ text itself is indexed too, so variants only add what is missing.
 *
 * Maintenance: when users ask something the matcher misses, add the wording
 * here (all 8 languages), add the question to `faq-match-questions.ts`, then
 * run the calibration test (see internal-notes).
 * Never write an answer here; answers live only in the FAQ.
 */

import type { Locale } from '../scripts/locales.ts';

export interface FaqIntent {
  /** FAQ key; must exist in FAQ_GROUPS. */
  readonly key: string;
  /** Question variants and synonyms, per locale. */
  readonly variants: Readonly<Record<Locale, readonly string[]>>;
}

export const FAQ_INTENTS: readonly FaqIntent[] = [
  {
    key: 'free',
    variants: {
      de: ['Ist WhisPaste kostenlos?', 'Preis Kosten gratis umsonst Lizenz Abo Kaufen bezahlen', 'Warum kostet die Store-Version Geld?'],
      en: ['Is WhisPaste free?', 'price cost pricing license subscription buy pay paid', 'Why does the Store version cost money?'],
      es: ['¿WhisPaste es gratis?', 'precio coste gratuito licencia suscripción comprar pagar', '¿Hay que pagar? ¿Es de pago?'],
      pt: ['O WhisPaste é grátis?', 'preço custo gratuito licença assinatura comprar pagar'],
      it: ['WhisPaste è gratis?', 'prezzo costo gratuito licenza abbonamento comprare pagare', 'Si paga? È a pagamento?'],
      ru: ['WhisPaste бесплатный?', 'цена стоимость бесплатно лицензия подписка купить платить', 'Это платно? Надо ли платить?'],
      zh: ['WhisPaste 免费吗？', '价格 费用 免费 许可 订阅 购买 付费 多少钱'],
      fr: ['WhisPaste est-il gratuit ?', 'prix coût gratuit licence abonnement acheter payer payant'],
    },
  },
  {
    key: 'offline',
    variants: {
      de: ['Geht das ohne Internetverbindung?', 'offline lokal ohne Netz Flugmodus Verbindung'],
      en: ['Does it work without an internet connection?', 'offline local no network airplane mode connection'],
      es: ['¿Funciona sin conexión a internet?', 'sin conexión local sin red modo avión'],
      pt: ['Funciona sem conexão com a internet?', 'offline local sem rede modo avião conexão'],
      it: ['Funziona senza connessione internet?', 'offline locale senza rete modalità aereo connessione'],
      ru: ['Работает без подключения к интернету?', 'офлайн оффлайн локально без сети авиарежим'],
      zh: ['没有网络能用吗？', '离线 断网 本地 无网络 飞行模式 联网'],
      fr: ['Est-ce que ça marche sans connexion Internet ?', 'hors ligne local sans réseau mode avion connexion'],
    },
  },
  {
    key: 'accuracy',
    variants: {
      de: ['Welches Modell ist das beste?', 'Erkennung ungenau schlecht Genauigkeit Modellgröße Balanced Quick Compact'],
      en: ['Which model is best?', 'recognition inaccurate bad accuracy model size Balanced Quick Compact'],
      es: ['¿Qué modelo es el mejor?', 'reconocimiento impreciso precisión tamaño del modelo'],
      pt: ['Qual modelo é o melhor?', 'reconhecimento impreciso precisão tamanho do modelo'],
      it: ['Qual è il modello migliore?', 'riconoscimento impreciso precisione dimensione del modello'],
      ru: ['Какая модель лучше?', 'распознавание неточное точность размер модели'],
      zh: ['哪个模型最好？', '识别 不准 准确率 模型大小 选择模型'],
      fr: ['Quel modèle est le meilleur ?', 'reconnaissance imprécise précision taille du modèle'],
    },
  },
  {
    key: 'sysreq',
    variants: {
      de: ['Systemanforderungen', 'Voraussetzungen RAM Arbeitsspeicher Grafikkarte GPU Prozessor Speicherplatz Hardware'],
      en: ['System requirements', 'requirements RAM memory graphics card GPU processor CPU disk space hardware'],
      es: ['Requisitos del sistema', 'requisitos memoria RAM tarjeta gráfica GPU procesador espacio en disco'],
      pt: ['Requisitos do sistema', 'requisitos memória RAM placa de vídeo GPU processador espaço em disco'],
      it: ['Requisiti di sistema', 'requisiti memoria RAM scheda grafica GPU processore spazio su disco', 'Quanta memoria serve?'],
      ru: ['Системные требования', 'требования оперативная память видеокарта GPU процессор место на диске'],
      zh: ['系统要求', '配置 要求 内存 显卡 GPU 处理器 硬盘空间 硬件'],
      fr: ['Configuration requise', 'prérequis mémoire RAM carte graphique GPU processeur espace disque'],
    },
  },
  {
    key: 'languages',
    variants: {
      de: ['Versteht WhisPaste Deutsch?', 'Sprache Sprachen Dialekt Spracherkennung Mehrsprachig', 'Deutsch Englisch Spanisch Französisch Italienisch Russisch Chinesisch diktieren'],
      en: ['Does WhisPaste understand my language?', 'language languages dialect multilingual speak', 'German English Spanish French Italian Russian Chinese dictate'],
      es: ['¿Entiende WhisPaste español?', 'idioma idiomas dialecto multilingüe hablar', 'alemán inglés español francés italiano ruso chino dictar'],
      pt: ['O WhisPaste entende português?', 'idioma idiomas língua dialeto multilíngue falar', 'alemão inglês espanhol francês italiano russo chinês ditar'],
      it: ['WhisPaste capisce l’italiano?', 'lingua lingue dialetto multilingue parlare', 'tedesco inglese spagnolo francese italiano russo cinese dettare'],
      ru: ['Понимает ли WhisPaste русский?', 'язык языки диалект многоязычный говорить', 'немецкий английский испанский французский итальянский русский китайский диктовать'],
      zh: ['WhisPaste 支持中文吗？', '语言 支持 中文 方言 多语言 说话', '德语 英语 西班牙语 法语 意大利语 俄语 普通话 听写'],
      fr: ['WhisPaste comprend-il le français ?', 'langue langues dialecte multilingue parler', 'allemand anglais espagnol français italien russe chinois dicter'],
    },
  },
  {
    key: 'engines',
    variants: {
      de: ['Unterschied zwischen Whisper und Parakeet', 'Engine Spracherkennung schneller Vergleich'],
      en: ['Difference between Whisper and Parakeet', 'engine speech recognition faster compare'],
      es: ['Diferencia entre Whisper y Parakeet', 'motor reconocimiento de voz más rápido comparar'],
      pt: ['Diferença entre Whisper e Parakeet', 'motor reconhecimento de voz mais rápido comparar'],
      it: ['Differenza tra Whisper e Parakeet', 'motore riconoscimento vocale più veloce confronto'],
      ru: ['Разница между Whisper и Parakeet', 'движок распознавание речи быстрее сравнение'],
      zh: ['Whisper 和 Parakeet 有什么区别？', '引擎 语音识别 更快 比较 区别'],
      fr: ['Différence entre Whisper et Parakeet', 'moteur reconnaissance vocale plus rapide comparer'],
    },
  },
  {
    key: 'snippets',
    variants: {
      de: ['Textbausteine Vorlagen Snippet einfügen', 'Wie lege ich eine Vorlage an?'],
      en: ['text snippets templates insert boilerplate', 'How do I create a template?'],
      es: ['fragmentos de texto plantillas insertar', '¿Cómo creo una plantilla?'],
      pt: ['trechos de texto modelos inserir', 'Como crio um modelo?'],
      it: ['frammenti di testo modelli inserire', 'Come creo un modello?'],
      ru: ['фрагменты текста шаблоны сниппеты вставить', 'Как создать шаблон?'],
      zh: ['文本片段 模板 插入 常用语', '怎样创建模板？'],
      fr: ['extraits de texte modèles insérer', 'Comment créer un modèle ?'],
    },
  },
  {
    key: 'smartmode',
    variants: {
      de: ['Smart Mode KI Text verbessern übersetzen kürzen Füllwörter Zeichensetzung', 'Kann WhisPaste übersetzen?'],
      en: ['Smart Mode AI improve text translate shorten filler words punctuation', 'Can WhisPaste translate?'],
      es: ['Smart Mode IA mejorar texto traducir acortar muletillas puntuación', '¿WhisPaste puede traducir?'],
      pt: ['Smart Mode IA melhorar texto traduzir encurtar vícios de linguagem pontuação', 'O WhisPaste traduz?'],
      it: ['Smart Mode IA migliorare testo tradurre accorciare intercalari punteggiatura', 'WhisPaste può tradurre?'],
      ru: ['Умный режим ИИ улучшить текст перевести сократить слова-паразиты пунктуация', 'Может ли WhisPaste переводить?'],
      zh: ['智能模式 AI 改进文字 翻译 缩短 语气词 标点', 'WhisPaste 能翻译吗？'],
      fr: ['Smart Mode IA améliorer texte traduire raccourcir mots parasites ponctuation', 'WhisPaste peut-il traduire ?'],
    },
  },
  {
    key: 'privacy',
    variants: {
      de: ['Datenschutz', 'Daten Privatsphäre Aufnahmen Cloud OpenAI Deepgram Telemetrie Statistik DSGVO sicher', 'Werden meine Aufnahmen hochgeladen?'],
      en: ['Privacy', 'data privacy recordings cloud OpenAI Deepgram telemetry statistics GDPR secure', 'Are my recordings uploaded?'],
      es: ['Privacidad', 'datos privacidad grabaciones nube OpenAI Deepgram telemetría estadísticas RGPD', '¿Se suben mis grabaciones?'],
      pt: ['Privacidade', 'dados privacidade gravações nuvem OpenAI Deepgram telemetria estatísticas LGPD', 'Minhas gravações são enviadas?'],
      it: ['Privacy', 'dati privacy registrazioni cloud OpenAI Deepgram telemetria statistiche GDPR', 'Le mie registrazioni vengono caricate?'],
      ru: ['Конфиденциальность', 'данные приватность записи облако OpenAI Deepgram телеметрия статистика', 'Мои записи загружаются в сеть?'],
      zh: ['隐私', '数据 隐私 录音 云端 OpenAI Deepgram 遥测 统计 安全', '我的录音会上传吗？'],
      fr: ['Confidentialité', 'données vie privée enregistrements cloud OpenAI Deepgram télémétrie statistiques RGPD', 'Mes enregistrements sont-ils envoyés ?'],
    },
  },
  {
    key: 'windows',
    variants: {
      de: ['Gibt es WhisPaste für Mac, Linux, iPhone oder Android?', 'Betriebssystem Plattform Download Intel-Mac Ubuntu Handy App'],
      en: ['Is there a version for Mac, Linux, iPhone or Android?', 'operating system platform download Intel Mac Ubuntu phone mobile app'],
      es: ['¿Hay versión para Mac, Linux, iPhone o Android?', 'sistema operativo plataforma descarga Mac Intel Ubuntu móvil'],
      pt: ['Tem versão para Mac, Linux, iPhone ou Android?', 'sistema operacional plataforma download Mac Intel Ubuntu celular'],
      it: ['C’è una versione per Mac, Linux, iPhone o Android?', 'sistema operativo piattaforma download Mac Intel Ubuntu cellulare'],
      ru: ['Есть ли версия для Mac, Linux, iPhone или Android?', 'операционная система платформа скачать Mac Intel Ubuntu телефон'],
      zh: ['有 Mac、Linux、iPhone 或安卓版吗？', '操作系统 平台 下载 英特尔 Mac Ubuntu 手机 安卓'],
      fr: ['Existe-t-il une version pour Mac, Linux, iPhone ou Android ?', 'système d’exploitation plateforme téléchargement Mac Intel Ubuntu mobile'],
    },
  },
  {
    key: 'smartscreen',
    variants: {
      de: ['Windows blockiert die Installation', 'SmartScreen Virus Warnung Defender unsicher Installer startet nicht signiert'],
      en: ['Windows blocks the installer', 'SmartScreen virus warning Defender unsafe installer will not run signed'],
      es: ['Windows bloquea el instalador', 'SmartScreen virus aviso Defender inseguro instalador firmado'],
      pt: ['O Windows bloqueia o instalador', 'SmartScreen vírus aviso Defender inseguro instalador assinado'],
      it: ['Windows blocca l’installazione', 'SmartScreen virus avviso Defender non sicuro installer firmato'],
      ru: ['Windows блокирует установщик', 'SmartScreen вирус предупреждение Defender небезопасно установщик подписан'],
      zh: ['Windows 阻止安装', 'SmartScreen 病毒 警告 Defender 不安全 安装程序 签名'],
      fr: ['Windows bloque l’installation', 'SmartScreen virus alerte Defender dangereux installateur signé'],
    },
  },
  {
    key: 'gatekeeper',
    variants: {
      de: ['macOS lässt die App nicht öffnen', 'Gatekeeper beschädigt Entwickler nicht verifiziert notarisiert DMG Mac App Store'],
      en: ['macOS will not open the app', 'Gatekeeper damaged unidentified developer notarized DMG Mac App Store'],
      es: ['macOS no deja abrir la app', 'Gatekeeper dañada desarrollador no identificado notarizada DMG Mac App Store'],
      pt: ['O macOS não deixa abrir o app', 'Gatekeeper danificado desenvolvedor não identificado notarizado DMG Mac App Store'],
      it: ['macOS non apre l’app', 'Gatekeeper danneggiata sviluppatore non identificato notarizzata DMG Mac App Store'],
      ru: ['macOS не открывает приложение', 'Gatekeeper повреждено неустановленный разработчик нотариально DMG Mac App Store'],
      zh: ['macOS 无法打开应用', 'Gatekeeper 已损坏 无法验证开发者 公证 DMG Mac App Store'],
      fr: ['macOS refuse d’ouvrir l’app', 'Gatekeeper endommagée développeur non identifié notarisée DMG Mac App Store'],
    },
  },
  {
    key: 'hotkey',
    variants: {
      de: ['Tastenkürzel ändern', 'Hotkey Tastenkombination Kürzel Shortcut Taste ändern umstellen belegen Aufnahme starten', 'Welches Tastenkürzel ist Standard?'],
      en: ['Change the hotkey', 'hotkey shortcut key combination keyboard change rebind remap start recording', 'What is the default hotkey?'],
      es: ['Cambiar el atajo', 'atajo tecla combinación de teclas hotkey cambiar modificar iniciar grabación', '¿Cuál es el atajo por defecto?'],
      pt: ['Alterar o atalho', 'atalho tecla combinação de teclas hotkey alterar mudar iniciar gravação', 'Qual é o atalho padrão?'],
      it: ['Cambiare la scorciatoia', 'scorciatoia tasto combinazione di tasti hotkey cambiare modificare avviare registrazione', 'Qual è la scorciatoia predefinita?'],
      ru: ['Изменить горячую клавишу', 'горячая клавиша сочетание клавиш комбинация изменить поменять начать запись', 'Какое сочетание клавиш по умолчанию?'],
      zh: ['修改快捷键', '快捷键 热键 组合键 按键 修改 更改 开始录音', '默认快捷键是什么？'],
      fr: ['Changer le raccourci', 'raccourci touche combinaison de touches hotkey changer modifier démarrer enregistrement', 'Quel est le raccourci par défaut ?'],
    },
  },
  {
    key: 'encryption',
    variants: {
      de: ['Sind meine Daten verschlüsselt?', 'Verschlüsselung verschlüsselt Datenschlüssel Schlüsselbund Wiederherstellungscode Datenbank sicher gespeichert neuer Rechner'],
      en: ['Is my data encrypted?', 'encryption encrypted data key keychain recovery code database stored securely new computer'],
      es: ['¿Mis datos están cifrados?', 'cifrado cifrados encriptado clave de datos llavero código de recuperación base de datos ordenador nuevo'],
      pt: ['Meus dados são criptografados?', 'criptografia criptografados chave de dados keychain código de recuperação banco de dados computador novo'],
      it: ['I miei dati sono cifrati?', 'crittografia cifrati chiave dati portachiavi codice di recupero database nuovo computer'],
      ru: ['Мои данные зашифрованы?', 'шифрование зашифрованы ключ данных связка ключей код восстановления база данных новый компьютер'],
      zh: ['我的数据加密了吗？', '加密 数据密钥 钥匙串 恢复码 数据库 新电脑'],
      fr: ['Mes données sont-elles chiffrées ?', 'chiffrement chiffrées clé de données trousseau code de récupération base de données nouvel ordinateur'],
    },
  },
  {
    key: 'accessibility',
    variants: {
      de: ['Geht WhisPaste ohne Maus?', 'Barrierefreiheit barrierefrei Screenreader Bildschirmleser Tastatur ohne Maus blind sehbehindert Taste halten schwer Zittern große Schrift'],
      en: ['Can I use it without a mouse?', 'accessibility accessible screen reader VoiceOver NVDA keyboard only no mouse blind low vision hard to hold a key tremor large text'],
      es: ['¿Se puede usar sin ratón?', 'accesibilidad accesible lector de pantalla teclado sin ratón ciego baja visión mantener tecla temblor texto grande'],
      pt: ['Dá para usar sem mouse?', 'acessibilidade acessível leitor de tela teclado sem mouse cego baixa visão segurar tecla tremor texto grande'],
      it: ['Si può usare senza mouse?', 'accessibilità accessibile screen reader lettore di schermo tastiera senza mouse cieco ipovedente tenere premuto tremore testo grande'],
      ru: ['Можно ли без мыши?', 'доступность специальные возможности экранный диктор программа чтения с экрана клавиатура без мыши незрячий слабовидящий удерживать клавишу тремор крупный шрифт'],
      zh: ['可以不用鼠标吗？', '无障碍 辅助功能 屏幕阅读器 读屏 键盘 不用鼠标 盲人 视障 长按困难 手抖 大字号'],
      fr: ['WhisPaste fonctionne-t-il sans souris ?', 'accessibilité accessible lecteur d’écran clavier sans souris aveugle malvoyant maintenir touche tremblement texte agrandi'],
    },
  },
];
