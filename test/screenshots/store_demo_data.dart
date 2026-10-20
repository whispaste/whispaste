// Demo history entries and replacements the store screenshots are seeded
// with (see store_screenshots_test.dart). Kept out of that file so the plain
// fixture checks in store_demo_data_test.dart can read them in every run.
library;

const demoEntriesEn = <DemoEntry>[
  DemoEntry(
    id: 'demo-1',
    title: 'Weekly standup notes',
    content:
        'The backend team shipped the new auth flow. Frontend is on track for '
        'the design review on Thursday. Mobile team needs one more day for the '
        'push notification integration. No blockers reported.',
    durationSec: 42.3,
    minutesAgo: 15,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    pinned: true,
    colorSlot: 5,
  ),
  DemoEntry(
    id: 'demo-2',
    title: 'Email to client — project update',
    content:
        'Hi Sarah, quick update on the project. We are ahead of schedule on '
        'the dashboard redesign and the new analytics view should be ready '
        'for testing by next Monday. I will send the staging link right away.',
    durationSec: 28.7,
    minutesAgo: 45,
    tags: ['Work', 'Email'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 6,
  ),
  DemoEntry(
    id: 'demo-3',
    title: 'Product idea — voice shortcuts',
    content:
        'Voice shortcuts could expand into full phrases. Saying "sign off" '
        'would insert the email signature automatically and save time on '
        'repetitive writing throughout the day.',
    durationSec: 18.5,
    minutesAgo: 120,
    tags: ['Idea'],
    model: 'Whisper Medium',
    pinned: true,
    colorSlot: 0,
  ),
  DemoEntry(
    id: 'demo-4',
    title: 'Grocery list for the weekend',
    content:
        'Avocados, sourdough bread, cherry tomatoes, mozzarella, fresh basil, '
        'olive oil, pasta, chicken breast, garlic, onions, and dark chocolate.',
    durationSec: 12.1,
    minutesAgo: 180,
    tags: ['Personal'],
    model: 'Whisper Medium',
    colorSlot: 1,
  ),
  DemoEntry(
    id: 'demo-5',
    title: 'Meeting recap — Q2 planning',
    content:
        'Key takeaways: revenue target is fifteen percent growth, three new '
        'engineering hires approved, and the September launch date is locked. '
        'Follow up with design on the brand refresh.',
    durationSec: 55.8,
    minutesAgo: 360,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 3,
  ),
  DemoEntry(
    id: 'demo-6',
    title: 'Quick reminder — dentist appointment',
    content:
        'Dentist appointment moved to Friday at nine. Ask reception whether '
        'the parking garage validation still works for early visits.',
    durationSec: 8.2,
    minutesAgo: 25,
    tags: ['Personal'],
    model: 'Whisper Medium',
    colorSlot: 7,
  ),
  DemoEntry(
    id: 'demo-7',
    title: 'Interview debrief — backend candidate',
    content:
        'Strong on distributed systems, thinner on frontend collaboration. '
        'Leaning yes, but loop in the frontend lead before the offer call.',
    durationSec: 61.4,
    minutesAgo: 300,
    tags: ['Work', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 2,
  ),
  DemoEntry(
    id: 'demo-8',
    title: 'Travel note — conference next month',
    content:
        'Book the flight before prices climb, and check whether the hotel '
        'block for the conference is still open for early registration.',
    durationSec: 15.0,
    minutesAgo: 500,
    tags: ['Idea'],
    model: 'Whisper Medium',
    colorSlot: 4,
  ),
];

const demoEntriesDe = <DemoEntry>[
  DemoEntry(
    id: 'demo-1',
    title: 'Wöchentliche Standup-Notizen',
    content:
        'Das Backend-Team hat den neuen Login-Ablauf ausgeliefert. Das '
        'Frontend liegt für das Design-Review am Donnerstag im Plan. Mobile '
        'braucht noch einen Tag für die Push-Integration. Keine Blocker.',
    durationSec: 42.3,
    minutesAgo: 15,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    pinned: true,
    colorSlot: 5,
  ),
  DemoEntry(
    id: 'demo-2',
    title: 'E-Mail an Kundin — Projektupdate',
    content:
        'Hi Sarah, hier ein kurzes Update zum Projekt. Beim Dashboard-Redesign '
        'liegen wir vor dem Plan und die neue Statistikansicht sollte bis '
        'Montag testbar sein. Den Staging-Link schicke ich dir direkt danach.',
    durationSec: 28.7,
    minutesAgo: 45,
    tags: ['Arbeit', 'E-Mail'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 6,
  ),
  DemoEntry(
    id: 'demo-3',
    title: 'Produktidee — Sprachkürzel',
    content:
        'Sprachkürzel könnten ganze Phrasen einfügen. Wenn ich '
        '"Grußformel" sage, wird automatisch meine Abschlussformel '
        'eingesetzt. Das spart täglich Tipparbeit.',
    durationSec: 18.5,
    minutesAgo: 120,
    tags: ['Idee'],
    model: 'Whisper Medium',
    pinned: true,
    colorSlot: 0,
  ),
  DemoEntry(
    id: 'demo-4',
    title: 'Einkaufsliste für das Wochenende',
    content:
        'Avocados, Sauerteigbrot, Cherrytomaten, Mozzarella, frisches Basilikum, '
        'Olivenöl, Pasta, Hähnchen, Knoblauch, Zwiebeln und dunkle Schokolade.',
    durationSec: 12.1,
    minutesAgo: 180,
    tags: ['Privat'],
    model: 'Whisper Medium',
    colorSlot: 1,
  ),
  DemoEntry(
    id: 'demo-5',
    title: 'Meeting-Zusammenfassung — Q2-Planung',
    content:
        'Wichtigste Punkte: fünfzehn Prozent Wachstumsziel, drei neue Stellen '
        'im Engineering und der September-Launch bleibt gesetzt. Bitte mit dem '
        'Design-Team das Marken-Refresh nachziehen.',
    durationSec: 55.8,
    minutesAgo: 360,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 3,
  ),
  DemoEntry(
    id: 'demo-6',
    title: 'Kurze Erinnerung — Zahnarzttermin',
    content:
        'Zahnarzttermin auf Freitag neun Uhr verschoben. An der Rezeption '
        'fragen, ob die Parkhaus-Validierung auch für frühe Termine gilt.',
    durationSec: 8.2,
    minutesAgo: 25,
    tags: ['Privat'],
    model: 'Whisper Medium',
    colorSlot: 7,
  ),
  DemoEntry(
    id: 'demo-7',
    title: 'Interview-Nachbesprechung — Backend-Kandidat',
    content:
        'Stark bei verteilten Systemen, dünner bei Frontend-Zusammenarbeit. '
        'Tendenz ja, aber vor dem Angebot noch die Frontend-Leitung einbeziehen.',
    durationSec: 61.4,
    minutesAgo: 300,
    tags: ['Arbeit', 'Meeting'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 2,
  ),
  DemoEntry(
    id: 'demo-8',
    title: 'Reisenotiz — Konferenz nächsten Monat',
    content:
        'Flug buchen, bevor die Preise steigen, und prüfen, ob das '
        'Hotelkontingent für die Konferenz noch für Frühbucher offen ist.',
    durationSec: 15.0,
    minutesAgo: 500,
    tags: ['Idee'],
    model: 'Whisper Medium',
    colorSlot: 4,
  ),
];

const replacementsEn = <(String, String)>[
  ('sign off', 'Best regards,\nAlex'),
  ('my email', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('brb', 'Be right back, give me just a moment.'),
];

const replacementsDe = <(String, String)>[
  ('grußformel', 'Viele Grüße,\nAlex'),
  ('meine mail', 'alex@whispaste.dev'),
  ('meeting link', 'https://meet.example.com/team-sync'),
  ('bin gleich zurück', 'Bin gleich wieder da, gib mir bitte einen Moment.'),
];

const demoEntriesRu = <DemoEntry>[
  DemoEntry(
    id: 'demo-1',
    title: 'Еженедельные заметки по стендапу',
    content:
        'Бэкенд-команда выпустила новый процесс входа. Фронтенд успевает к '
        'дизайн-ревью в четверг. Мобильной команде нужен ещё один день на '
        'интеграцию push-уведомлений. Блокеров нет.',
    durationSec: 42.3,
    minutesAgo: 15,
    tags: ['Работа', 'Встреча'],
    model: 'Whisper Large v3 Turbo',
    pinned: true,
    colorSlot: 5,
  ),
  DemoEntry(
    id: 'demo-2',
    title: 'Письмо клиенту — обновление по проекту',
    content:
        'Привет, Sarah! Короткое обновление по проекту. Редизайн дашборда идёт '
        'раньше графика, новый раздел аналитики будет готов к тестированию '
        'в понедельник. Ссылку на стейджинг отправлю сразу после этого.',
    durationSec: 28.7,
    minutesAgo: 45,
    tags: ['Работа', 'Почта'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 6,
  ),
  DemoEntry(
    id: 'demo-3',
    title: 'Идея для продукта — голосовые ярлыки',
    content:
        'Голосовые ярлыки могут раскрываться во целые фразы. Если я скажу '
        '«подпись», автоматически вставится мой завершающий текст. Это '
        'экономит время на однотипном наборе.',
    durationSec: 18.5,
    minutesAgo: 120,
    tags: ['Идея'],
    model: 'Whisper Medium',
    pinned: true,
    colorSlot: 0,
  ),
  DemoEntry(
    id: 'demo-4',
    title: 'Список покупок на выходные',
    content:
        'Авокадо, закваска, черри-томаты, моцарелла, свежий базилик, '
        'оливковое масло, паста, куриная грудка, чеснок, лук и тёмный шоколад.',
    durationSec: 12.1,
    minutesAgo: 180,
    tags: ['Личное'],
    model: 'Whisper Medium',
    colorSlot: 1,
  ),
  DemoEntry(
    id: 'demo-5',
    title: 'Итоги встречи — планирование Q2',
    content:
        'Главное: цель по выручке — рост на пятнадцать процентов, утверждены '
        'три новых инженера, дата запуска в сентябре зафиксирована. Нужно '
        'обсудить с дизайном обновление бренда.',
    durationSec: 55.8,
    minutesAgo: 360,
    tags: ['Работа', 'Встреча'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 3,
  ),
  DemoEntry(
    id: 'demo-6',
    title: 'Короткое напоминание — визит к стоматологу',
    content:
        'Визит к стоматологу перенесли на пятницу, на девять утра. Уточнить '
        'на ресепшене, работает ли парковка с валидацией для ранних записей.',
    durationSec: 8.2,
    minutesAgo: 25,
    tags: ['Личное'],
    model: 'Whisper Medium',
    colorSlot: 7,
  ),
  DemoEntry(
    id: 'demo-7',
    title: 'Итоги интервью — кандидат на бэкенд',
    content:
        'Силён в распределённых системах, слабее в работе с фронтендом. '
        'Склоняюсь к найму, но перед звонком с предложением подключите '
        'руководителя фронтенда.',
    durationSec: 61.4,
    minutesAgo: 300,
    tags: ['Работа', 'Встреча'],
    model: 'Whisper Large v3 Turbo',
    colorSlot: 2,
  ),
  DemoEntry(
    id: 'demo-8',
    title: 'Заметка о поездке — конференция в следующем месяце',
    content:
        'Забронировать перелёт, пока цены не выросли, и проверить, открыт ли '
        'ещё блок номеров в отеле для ранней регистрации.',
    durationSec: 15.0,
    minutesAgo: 500,
    tags: ['Идея'],
    model: 'Whisper Medium',
    colorSlot: 4,
  ),
];

const replacementsRu = <(String, String)>[
  ('подпись', 'С уважением,\nAlex'),
  ('моя почта', 'alex@whispaste.dev'),
  ('ссылка на встречу', 'https://meet.example.com/team-sync'),
  ('сейчас вернусь', 'Сейчас вернусь, дай мне минутку.'),
];

class DemoEntry {
  const DemoEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.durationSec,
    required this.minutesAgo,
    required this.tags,
    required this.model,
    required this.colorSlot,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String content;
  final double durationSec;
  final int minutesAgo;
  final List<String> tags;
  final String model;
  final int colorSlot;
  final bool pinned;
}
