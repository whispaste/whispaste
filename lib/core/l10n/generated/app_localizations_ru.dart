// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class L10nRu extends L10n {
  L10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'История';

  @override
  String get navNotes => 'Заметки';

  @override
  String get navSettings => 'Настройки';

  @override
  String get navReplacements => 'Замены';

  @override
  String get navSnippets => 'Сниппеты';

  @override
  String get navAnalytics => 'Аналитика';

  @override
  String get navAbout => 'О программе';

  @override
  String get navFeedback => 'Отзыв';

  @override
  String get pageHistoryTitle => 'История';

  @override
  String get pageSettingsTitle => 'Настройки';

  @override
  String get pageReplacementsTitle => 'Замены';

  @override
  String get pageAnalyticsTitle => 'Аналитика';

  @override
  String get pageAboutTitle => 'О программе';

  @override
  String get pageFeedbackTitle => 'Отзыв';

  @override
  String get historyEmpty => 'Пока нет записей';

  @override
  String get historyEmptyHint =>
      'Нажмите кнопку записи или используйте горячую клавишу для начала.';

  @override
  String get historySearch => 'Поиск…';

  @override
  String get historyPinned => 'Избранное';

  @override
  String get historyToday => 'Сегодня';

  @override
  String get historyYesterday => 'Вчера';

  @override
  String get historyThisWeek => 'На этой неделе';

  @override
  String get historyOlder => 'Старые';

  @override
  String get historyAll => 'Все';

  @override
  String get historyTrash => 'Корзина';

  @override
  String get historyArchive => 'Архив';

  @override
  String get historyArchived => 'В архиве';

  @override
  String get historyList => 'Список';

  @override
  String get historyCards => 'Карточки';

  @override
  String get historyCompact => 'Компактно';

  @override
  String historyItemsSelected(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get historyMerge => 'Объединить';

  @override
  String get historyRestore => 'Восстановить';

  @override
  String get historyDeleteForever => 'Удалить навсегда';

  @override
  String get historyDeletePermanently => 'Удалить безвозвратно';

  @override
  String get historyUnarchive => 'Разархивировать';

  @override
  String get historyExport => 'Экспорт';

  @override
  String get historyExportAction => 'Экспорт…';

  @override
  String get historyCopyAsMarkdown => 'Копировать как Markdown';

  @override
  String get historyDetail => 'Детали';

  @override
  String get historyTags => 'Теги';

  @override
  String get historyDuration => 'Длительность';

  @override
  String get historyModel => 'Модель';

  @override
  String get historyWords => 'Слова';

  @override
  String get historyCharacters => 'Символы';

  @override
  String historyWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слов',
      many: '$count слов',
      few: '$count слова',
      one: '1 слово',
    );
    return '$_temp0';
  }

  @override
  String historyReadingTime(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes мин чтения',
      many: '$minutes мин чтения',
      few: '$minutes мин чтения',
      one: '1 мин чтения',
    );
    return '$_temp0';
  }

  @override
  String get historyReadingTimeUnder1 => '< 1 мин чтения';

  @override
  String get historyEditing => 'Редактирование';

  @override
  String get historySearchTranscriptions => 'Поиск транскрипций…';

  @override
  String get historySearchFieldLabel => 'Искать транскрипции';

  @override
  String get historyNewRecording => 'Новая запись';

  @override
  String get historyStopRecording => 'Остановить запись';

  @override
  String get historyNoResults => 'Нет результатов';

  @override
  String historyNoResultsHint(String query) {
    return 'Транскрипций по запросу \"$query\" не найдено.\nПопробуйте другой поисковый запрос.';
  }

  @override
  String get historyTrashEmpty => 'Корзина пуста';

  @override
  String get historyTrashEmptyHint =>
      'Здесь будут удаленные транскрипции.\nЭлементы окончательно удаляются через 30 дней.';

  @override
  String get historyEmptyTrash => 'Очистить корзину';

  @override
  String get historyEmptyTrashConfirm => 'Очистить корзину?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'Это навсегда удалит все элементы в корзине. Это действие нельзя отменить.';

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записей',
      many: '$count записей',
      few: '$count записи',
      one: '1 запись',
    );
    return 'Корзина очищена — удалено $_temp0';
  }

  @override
  String get historyNoArchivedItems => 'Нет элементов в архиве';

  @override
  String get historyNoArchivedItemsHint =>
      'Архивируйте транскрипции, которые хотите сохранить,\nно которые не нужны вам в основном списке.';

  @override
  String get historyNoRecordingsHint =>
      'Нажмите кнопку записи или используйте горячую клавишу для начала.\nВаши транскрипции появятся здесь.';

  @override
  String get historyNoPinned => 'Пока нет избранного';

  @override
  String get historyNoPinnedHint =>
      'Отметьте транскрипцию как избранную, чтобы быстро находить её здесь.';

  @override
  String get historyNoToday => 'Сегодня нет записей';

  @override
  String get historyNoTodayHint => 'Сегодняшние транскрипции появятся здесь.';

  @override
  String get historyNoThisWeek => 'На этой неделе нет записей';

  @override
  String get historyNoThisWeekHint =>
      'Транскрипции за эту неделю появятся здесь.';

  @override
  String get historyCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get historyMovedToTrash => 'Перемещено в корзину';

  @override
  String get historyUndo => 'Отменить';

  @override
  String get historyEntriesMerged => 'Записи объединены';

  @override
  String historyMergeConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записей',
      many: '$count записей',
      few: '$count записи',
      one: '1 запись',
    );
    return 'Объединить $_temp0?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'Выбранные записи будут объединены в одну. Это нельзя отменить.';

  @override
  String get historyExitSelection => 'Выйти из режима выбора';

  @override
  String get historySelectMultiple => 'Выбрать несколько';

  @override
  String get historyProcessed => 'Обработано';

  @override
  String get historyOnDevice => 'На устройстве';

  @override
  String get historyUntitledRecording => 'Запись без названия';

  @override
  String get historyUntitled => 'Без названия';

  @override
  String get historyPinToTop => 'Добавить в избранное';

  @override
  String get historyUnpin => 'Убрать из избранного';

  @override
  String get historyCopyText => 'Копировать текст';

  @override
  String get historyClose => 'Закрыть';

  @override
  String get historyLanguageLabel => 'Язык';

  @override
  String historyResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результатов',
      many: '$count результатов',
      few: '$count результата',
      one: '1 результат',
    );
    return '$_temp0';
  }

  @override
  String get historySelectAll => 'Выбрать все';

  @override
  String get historyDeselectAll => 'Снять выбор';

  @override
  String get settingsInterface => 'Интерфейс';

  @override
  String get settingsInterfaceSubtitle => 'Внешний вид и поведение';

  @override
  String get settingsLaunchAtStartup => 'Запускать при старте';

  @override
  String get settingsStartMinimized => 'Запускать свернутым';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Запускать в фоновом режиме при включении системы';

  @override
  String get settingsAutostartNever => 'Никогда';

  @override
  String get settingsAutostartNormal => 'Обычный';

  @override
  String get settingsAutostartMinimized => 'Свернутый';

  @override
  String get settingsAutostartSyncFailed =>
      'Не удалось зарегистрировать автозапуск. Возможно, проблема с правами доступа или версия ОС не поддерживается.';

  @override
  String get settingsShowNotifications => 'Показывать уведомления';

  @override
  String get settingsShowBackendUtilization =>
      'Индикатор CPU/GPU в строке состояния';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Показывает, где выполняется транскрипция (на CPU или GPU), и уровень нагрузки';

  @override
  String get settingsAudio => 'Аудио';

  @override
  String get settingsAudioSubtitle => 'Микрофон и запись';

  @override
  String get settingsMicrophone => 'Микрофон';

  @override
  String get settingsGain => 'Громкость микрофона';

  @override
  String get settingsClippingBanner =>
      'Последняя запись была с перегрузом. Снизить громкость?';

  @override
  String get settingsClippingDismiss => 'Скрыть';

  @override
  String get settingsHoldToRecord => 'Удерживать для записи';

  @override
  String get pushToTalkUnavailableTooltip => 'Недоступно на этой платформе';

  @override
  String get settingsSpeechRecognition => 'Распознавание речи';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Качество и сервис распознавания речи';

  @override
  String get settingsService => 'Сервис';

  @override
  String get settingsQuality => 'Качество';

  @override
  String get settingsRecordingSafety => 'Безопасность записи';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Автоматические проверки и защиты';

  @override
  String get settingsDeadMicTimeout => 'Детектор тишины микрофона';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Остановить запись, если нет звука в течение этого времени (сек). 0 = отключено.';

  @override
  String get settingsAutoStopSilence => 'Автоостановка при тишине';

  @override
  String get settingsAutoStopSilenceHint =>
      'Автоматически остановить запись после стольки секунд тишины (после речи). 0 = отключено.';

  @override
  String get settingsEnabled => 'Включено';

  @override
  String get settingsStyle => 'Стиль';

  @override
  String get settingsMicSystemDefault => 'Системный по умолчанию';

  @override
  String get settingsMicSystemHint =>
      'Звуковой вход управляется настройками вашей системы';

  @override
  String get settingsServiceOnDevicePrivate => 'Локально на устройстве';

  @override
  String get settingsLanguageAutoDetect => 'Автоопределение';

  @override
  String get settingsLanguageEnglish => 'Английский';

  @override
  String get settingsLanguageGerman => 'Немецкий';

  @override
  String get settingsLanguageFrench => 'Французский';

  @override
  String get settingsLanguageSpanish => 'Испанский';

  @override
  String get settingsLanguageHebrew => 'Иврит';

  @override
  String get settingsSoundFeedback => 'Звук и отклик';

  @override
  String get settingsSoundFeedbackSubtitle =>
      'Звуковые сигналы во время записи';

  @override
  String get settingsSoundsEnabled => 'Звуки';

  @override
  String get settingsRecordStartSound => 'Звук начала записи';

  @override
  String get settingsRecordStopSound => 'Звук остановки записи';

  @override
  String get settingsTranscriptionCompleteSound =>
      'Звук окончания транскрипции';

  @override
  String get settingsDurationWarningSound => 'Сигнал о лимите времени';

  @override
  String get settingsSoundVolume => 'Громкость звука';

  @override
  String get settingsAfterTranscription => 'После транскрипции';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'Что происходит с переведенным текстом';

  @override
  String get settingsAfterTranscriptionActionLabel => 'Действие';

  @override
  String get settingsAfterTranscriptionClipboard =>
      'Скопировать в буфер обмена';

  @override
  String get settingsAfterTranscriptionPaste => 'Автоматическая вставка';

  @override
  String get settingsAfterTranscriptionBoth => 'Копировать и вставить';

  @override
  String get settingsAfterTranscriptionNothing => 'Ничего не делать';

  @override
  String get pasteFailurePermissionMissing =>
      'Вставка заблокирована ОС. WhisPaste требуется разрешение на ввод текста — в macOS это \'Универсальный доступ\'.';

  @override
  String get pasteFailureNoTarget =>
      'Вставка пропущена, нет целевого окна. Сфокусируйтесь на нужном приложении перед записью.';

  @override
  String get pasteFailureElevationBlocked =>
      'Вставка заблокирована: целевое приложение имеет права администратора. Перезапустите WhisPaste от имени администратора.';

  @override
  String get pasteFailureGeneric =>
      'Ошибка автоматической вставки. Текст находится в буфере обмена, вставьте его вручную (Ctrl+V / ⌘V).';

  @override
  String get pasteFailureOpenSettings => 'Открыть настройки';

  @override
  String get pasteCapabilityCheckTitle => 'Минуточку…';

  @override
  String get pasteCapabilityReady => 'Все готово';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Ваша диктовка вставляется прямо туда, где находится курсор.';

  @override
  String get pasteCapabilityPermissionMissing => 'Пока нет разрешения';

  @override
  String get pasteCapabilityUnsupported =>
      'Авто-вставка недоступна на этой платформе';

  @override
  String get pasteCapabilityTestButton => 'Проверить сейчас';

  @override
  String get pasteCapabilityGrantButton => 'Продолжить';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste требуется разрешение на ввод текста — в macOS это \'Универсальный доступ\'.';

  @override
  String get pasteCapabilityTroubleshoot => 'Возникли проблемы?';

  @override
  String get pasteCapabilityRepairHint =>
      'Иногда macOS помнит старую запись и забывает новую. Сбросьте запись, и macOS снова запросит разрешение.';

  @override
  String get pasteCapabilityRepairButton => 'Сбросить запись';

  @override
  String get pasteCapabilityRestartButton => 'Перезапустить WhisPaste';

  @override
  String get pasteCapabilityRestartTitle =>
      'Почти готово — перезапустите WhisPaste';

  @override
  String get pasteCapabilityRestartBody =>
      'Если вы дали разрешение, macOS применяет его только к перезапущенному приложению. В один клик WhisPaste перезапустится.';

  @override
  String get pasteRestartAlertTitle => 'Перезапустить WhisPaste сейчас';

  @override
  String get pasteRestartAlertBody =>
      'Разрешение дано, но macOS применит его только после перезапуска. WhisPaste быстро закроется и снова откроется.';

  @override
  String get pasteRestartAlertConfirm => 'Перезапустить';

  @override
  String get pasteManualGrantAlertTitle => 'Перезапуск не помог';

  @override
  String get pasteManualGrantAlertBody =>
      'WhisPaste перезапустился, но разрешение так и не заработало. Пожалуйста, проверьте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ.';

  @override
  String get pasteManualGrantAlertConfirm => 'Открыть Системные настройки';

  @override
  String get permissionAlertLaterButton => 'Не сейчас';

  @override
  String get micGateAlertTitle => 'Нет доступа к микрофону';

  @override
  String get micGateAlertBody =>
      'WhisPaste не может записывать без доступа к микрофону. Разрешите его в Системных настройках.';

  @override
  String get micGateAlertBodyGeneric =>
      'WhisPaste не может записывать без доступа к микрофону. Пожалуйста, разрешите доступ в настройках конфиденциальности вашей системы.';

  @override
  String get micGateAlertConfirm => 'Открыть настройки';

  @override
  String get micGateRestartAlertTitle => 'Перезапустите WhisPaste';

  @override
  String get micGateRestartAlertBody =>
      'Доступ к микрофону предоставлен, но текущий сеанс WhisPaste не может его получить. Перезапустите приложение.';

  @override
  String get micGateRestartAlertConfirm => 'Перезапустить';

  @override
  String get autoPasteGateAlertTitle => 'Не хватает одного разрешения';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste может вставлять диктовку прямо в текст. Для этого macOS требует разрешение: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ.';

  @override
  String get autoPasteGateAlertConfirm => 'Открыть Системные настройки';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'Перезапуск не применил разрешение';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'Снова откройте разрешение и убедитесь, что WhisPaste включен.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удалено $count старых записей.',
      many: 'Удалено $count старых записей.',
      few: 'Удалено $count старые записи.',
      one: 'Удалена 1 старая запись.',
      zero: 'Старые записи не найдены.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'Старая запись не найдена. Скорее всего, теперь поможет перезапуск.';

  @override
  String get pasteCapabilityRepairFailed =>
      'Не удалось выполнить сброс. Попробуйте удалить WhisPaste из настроек вручную.';

  @override
  String get onboardingPasteTitle =>
      'Чтобы текст появлялся прямо там, где вы печатаете';

  @override
  String get onboardingPasteSubtitle =>
      'Через мгновение macOS спросит разрешения. Скажите «Да».';

  @override
  String get onboardingPasteSubtitleWin =>
      'В Windows разрешения не нужны — просто выберите, должен ли WhisPaste вставлять текст.';

  @override
  String get onboardingPasteChipReady => 'Авто-вставка готова';

  @override
  String get onboardingPasteChipPending => 'Ожидание доступа для авто-вставки';

  @override
  String get onboardingPasteChipAction => 'Авто-вставка: требуется действие';

  @override
  String get onboardingPasteGrantCta => 'Разрешить';

  @override
  String get onboardingPasteSkip => 'Только копировать, без вставки';

  @override
  String get onboardingPasteWhyMac =>
      'Без этого разрешения текст только копируется в буфер. Вставлять придется вручную (⌘V).';

  @override
  String get onboardingPasteWhyWin =>
      'Авто-вставка сама нажимает Ctrl+V после каждой диктовки. Убедились, что это работает? Включите ниже.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'В некоторых защищенных приложениях авто-вставка не работает. Текст останется в буфере обмена.';

  @override
  String get onboardingPasteWinOnTitle => 'Авто-вставка включена';

  @override
  String get onboardingPasteWinOnDetail =>
      'После диктовки WhisPaste нажмет Ctrl+V, и текст появится на месте курсора. Копия также остается в буфере.';

  @override
  String get onboardingPasteWinEnableCta => 'Включить авто-вставку';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'Приложения с правами администратора игнорируют симуляцию клавиш — текст останется в буфере обмена.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Поставьте галочку рядом с WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Открыты системные настройки. Найдите WhisPaste и включите.';

  @override
  String get onboardingPasteTestTitle => 'Проверьте авто-вставку';

  @override
  String get onboardingPasteTestSubtitle =>
      'Нажмите на кнопку. Демо-текст должен появиться в поле ниже.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste печатает за вас.';

  @override
  String get onboardingPasteTestSuccess =>
      'Авто-вставка работает! Нажмите \'Далее\'.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'Поле ввода не обнаружено. Кликните по полю ниже и попробуйте еще раз.';

  @override
  String get onboardingPasteTestFailure =>
      'Тест не пройден. Попробуйте перезапустить приложение.';

  @override
  String get onboardingPasteTestSkip => 'Продолжить без проверки';

  @override
  String get settingsOverlayFloatingButton => 'Оверлей записи';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Управление тем, как отображается статус при записи';

  @override
  String get settingsShowOverlay => 'Отображение статуса';

  @override
  String get settingsShowOverlaySubtitle =>
      'Выберите, где будет отображаться обратная связь при записи';

  @override
  String get settingsOverlayModeFloating => 'Плавающее окно (всегда поверх)';

  @override
  String get settingsOverlayModeOff => 'Выкл.';

  @override
  String get settingsOverlayStartPosition => 'Начальная позиция оверлея';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Где появляется плавающее окно при начале записи';

  @override
  String get settingsOverlayStartTopCenter => 'Сверху по центру';

  @override
  String get settingsOverlayStartBottomCenter => 'Снизу по центру';

  @override
  String get settingsOverlayStartLastPosition => 'Запомнить последнюю позицию';

  @override
  String get settingsShowFloatingButton => 'Плавающая кнопка';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Маленькая кнопка всегда поверх окон для быстрого запуска записи';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsRecognitionLanguage => 'Язык распознавания';

  @override
  String get settingsCustomVocabulary => 'Свой словарь';

  @override
  String get settingsCustomVocabularyHint =>
      'Имена, термины (улучшает точность)';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'напр., WhisPaste, Kubernetes, Иванов';

  @override
  String get settingsPunctuationPriming => 'Стимуляция пунктуации';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Подталкивает Whisper к выводу с пунктуацией, если не задан свой словарь. На скорость не влияет.';

  @override
  String get settingsVadEnabled => 'Обрезать тишину';

  @override
  String get settingsVadEnabledSubtitle =>
      'Удаляет долгую тишину или шум в конце записи до декодирования, чтобы Whisper не додумывал слова.';

  @override
  String get settingsStripPunctuation => 'Удалять пунктуацию';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Удаляет точки, запятые и другие знаки из транскрипции перед сохранением или вставкой.';

  @override
  String get settingsNumericOnlyMode => 'Только цифры';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Преобразует произнесенные числа в цифры, например \'пять\' в \'5\'.';

  @override
  String get settingsAppLanguage => 'Язык приложения';

  @override
  String get settingsSttModels => 'Модели распознавания речи';

  @override
  String get settingsOpenAiApiKey => 'API-ключ OpenAI';

  @override
  String get settingsDeepgramApiKey => 'API-ключ Deepgram';

  @override
  String get settingsToggleApiKeyVisibility => 'Переключить видимость ключа';

  @override
  String get settingsAdvanced => 'Дополнительно';

  @override
  String get settingsAdvancedSubtitle => 'Сброс, отчеты об ошибках, обновления';

  @override
  String get settingsResetToDefaults => 'Сбросить по умолчанию';

  @override
  String get settingsResetTitle => 'Сбросить настройки';

  @override
  String get settingsResetMessage =>
      'Все настройки вернутся к стандартным. API-ключи будут удалены. Это действие нельзя отменить.';

  @override
  String get settingsResetConfirm => 'Сбросить';

  @override
  String get settingsResetSuccess => 'Настройки сброшены по умолчанию';

  @override
  String get settingsFactoryReset => 'Заводские настройки';

  @override
  String get settingsFactoryResetTitle => 'Сброс до заводских настроек';

  @override
  String get settingsFactoryResetMessage =>
      'Это навсегда удалит ВСЕ данные: историю, теги, замены, модели, логи и настройки.\n\nЭто нельзя отменить.';

  @override
  String get settingsFactoryResetConfirm => 'Удалить все';

  @override
  String get settingsFactoryResetSuccess =>
      'Приложение было полностью сброшено';

  @override
  String get settingsFactoryResetProgressTitle => 'Сброс WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Остановка сервиса…';

  @override
  String get settingsFactoryResetPhaseDeletingModels => 'Удаление моделей…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase =>
      'Удаление базы данных…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Очистка учетных данных…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Восстановление настроек…';

  @override
  String get settingsFactoryResetFailedMessage =>
      'Сброс не завершен. Перезапустите приложение.';

  @override
  String get settingsPortabilitySectionTitle =>
      'Резервное копирование и перенос';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'Создайте резервную копию или перенесите настройки на другой ПК';

  @override
  String get settingsPortabilityExportAction => 'Экспорт';

  @override
  String get settingsPortabilityImportAction => 'Импорт';

  @override
  String get settingsPortabilityExportLocationLabel =>
      'Место сохранения экспорта';

  @override
  String get settingsPortabilityImportLocationLabel => 'Источник импорта';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'Мы спросим об этом при первом экспорте';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'Мы спросим об этом при первом импорте';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'Выбрать другое место для экспорта';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'Выбрать другой источник импорта';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'Настройки экспортированы в $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'Ошибка экспорта: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle =>
      'Импортировать настройки?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'Это заменит ваши текущие настройки из $path. API-ключи затронуты не будут.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'Настройки импортированы из $path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'Файл экспорта не найден по пути $path.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'Ошибка импорта: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'Автоматическое резервное копирование';

  @override
  String get settingsAutosaveHint =>
      'Сохраняет резервную копию после каждого изменения';

  @override
  String get settingsAutosaveChooseFolder =>
      'Выбрать другую папку для автоматических резервных копий';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'Последняя копия: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'Резервных копий пока нет';

  @override
  String get settingsAutosaveLastRunFailed => 'Ошибка копирования';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'Последняя попытка неудачна — копия: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'Ошибка копирования: выбранная папка недоступна.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'Ошибка копирования: $reason';
  }

  @override
  String get groqRemovedToast =>
      'STT Groq был удален. Провайдер сброшен на устройство.';

  @override
  String get tccResetAfterUpdateToast =>
      'macOS сбросила ваше разрешение во время обновления.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записей',
      many: '$count записей',
      few: '$count записи',
      one: '1 запись',
    );
    return 'Мигрировано $_temp0';
  }

  @override
  String get settingsOff => 'Выкл.';

  @override
  String get settingsOn => 'Вкл.';

  @override
  String get statusReady => 'Готов';

  @override
  String get statusRecording => 'Запись…';

  @override
  String get statusTranscribing => 'Транскрипция…';

  @override
  String get statusProcessing => 'Обработка…';

  @override
  String get statusTranscriptionDone => 'Транскрипция завершена';

  @override
  String get statusCopied => 'Скопировано!';

  @override
  String get statusLocal => 'Локально';

  @override
  String get statusCloud => 'В облаке';

  @override
  String get statusOnline => 'Онлайн';

  @override
  String get statusOffline => 'Офлайн';

  @override
  String get recordingGuardFailed =>
      'Звук не обнаружен. Пожалуйста, попробуйте еще раз. Иногда микрофону нужно время на запуск.';

  @override
  String get recordingAutoStopped => 'Запись остановлена: обнаружена тишина.';

  @override
  String get actionCopy => 'Копировать';

  @override
  String get actionDuplicate => 'Дублировать';

  @override
  String get actionDelete => 'Удалить';

  @override
  String get actionDismiss => 'Скрыть';

  @override
  String get actionEdit => 'Редактировать';

  @override
  String get actionExport => 'Экспорт';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionConfirm => 'Подтвердить';

  @override
  String get actionSave => 'Сохранить';

  @override
  String get actionRetry => 'Повторить';

  @override
  String get actionClearSearch => 'Очистить поиск';

  @override
  String get tooltipLanguage => 'Язык';

  @override
  String aboutVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get onboardingWelcome => 'Скажите раз. Вставьте где угодно.';

  @override
  String get feedbackTitle => 'Отправить отзыв';

  @override
  String get feedbackHint =>
      'Расскажите, что вы думаете. Мы читаем каждое сообщение.';

  @override
  String get analyticsPreviewBanner =>
      'Предпросмотр: показаны демонстрационные данные. Реальная аналитика появится после начала записей.';

  @override
  String get analyticsEmptyTitle => 'Пока нет записей';

  @override
  String get analyticsEmptySubtitle =>
      'Начните записывать, чтобы увидеть здесь аналитику.';

  @override
  String get analyticsOverview => 'Обзор';

  @override
  String get analyticsOverviewSubtitle =>
      'Статистика записей с первого взгляда';

  @override
  String get analyticsActivity => 'Активность';

  @override
  String get analyticsInsights => 'Сводка';

  @override
  String get analyticsTotalRecordings => 'Всего записей';

  @override
  String get analyticsTotalDuration => 'Общая длительность';

  @override
  String get analyticsWordsDictated => 'Слов транскрибировано';

  @override
  String get analyticsTimeSaved => 'Сэкономлено времени';

  @override
  String get analyticsAvgLatency => 'Ср. скорость';

  @override
  String get analyticsRecordingActivity => 'Активность записей';

  @override
  String get analyticsLast7Days => 'За последние 7 дней';

  @override
  String get analyticsModelUsage => 'Использование моделей';

  @override
  String get analyticsDurationDistribution => 'Распределение по длительности';

  @override
  String get analyticsCostSavings => 'Затраты и экономия';

  @override
  String get analyticsLocalSavings => 'Локальная экономия';

  @override
  String get analyticsCloudCost => 'Затраты на облако';

  @override
  String get analyticsPeriod7d => '7 дней';

  @override
  String get analyticsPeriod30d => '30 дней';

  @override
  String get analyticsPeriod90d => '90 дней';

  @override
  String get analyticsPeriodAll => 'За все время';

  @override
  String get analyticsReset => 'Сбросить';

  @override
  String get analyticsResetTitle => 'Сбросить статистику';

  @override
  String get analyticsResetMessage =>
      'Вы уверены, что хотите удалить все данные аналитики? Это действие нельзя отменить.';

  @override
  String get analyticsDayMon => 'Пн';

  @override
  String get analyticsDayTue => 'Вт';

  @override
  String get analyticsDayWed => 'Ср';

  @override
  String get analyticsDayThu => 'Чт';

  @override
  String get analyticsDayFri => 'Пт';

  @override
  String get analyticsDaySat => 'Сб';

  @override
  String get analyticsDaySun => 'Вс';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta на этой неделе';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta к прошлому месяцу';
  }

  @override
  String analyticsDurationHoursMinutes(int hours, int minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String get analyticsDurationLt15s => '< 15с';

  @override
  String get analyticsDuration15To30s => '15-30с';

  @override
  String get analyticsDuration30To60s => '30-60с';

  @override
  String get analyticsDuration1To3m => '1-3м';

  @override
  String get analyticsDurationGt3m => '> 3м';

  @override
  String analyticsSavedAmount(String amount) {
    return 'сэкономлено $amount';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return 'потрачено $amount';
  }

  @override
  String get replacementsSearch => 'Искать замены…';

  @override
  String get replacementsSearchFieldLabel => 'Поиск замен';

  @override
  String get replacementsAdd => 'Добавить';

  @override
  String get replacementsEmpty => 'Замен пока нет';

  @override
  String get replacementsEmptyHint =>
      'Добавьте замены для автозамены слов при записи.\nНапример: \"кст\" → \"кстати\"';

  @override
  String get replacementsNoMatches => 'Нет совпадений';

  @override
  String get replacementsNoMatchesHint => 'Попробуйте другой запрос.';

  @override
  String get replacementsToggleLabel => 'Включить замены';

  @override
  String get replacementsToggleEnabled => 'Замены активны';

  @override
  String get replacementsToggleDisabled => 'Замены отключены';

  @override
  String get replacementsEnableBannerTitle => 'Замены выключены';

  @override
  String get replacementsEnableBannerHint =>
      'Включите их, чтобы фразы-триггеры заменялись автоматически.';

  @override
  String get replacementsEnableAction => 'Включить';

  @override
  String get replacementsDisableAction => 'Выключить';

  @override
  String get replacementsEditShortcut => 'Изменить замену';

  @override
  String get replacementsNewShortcut => 'Новая замена';

  @override
  String get replacementsDialogHint =>
      'Любая из фраз-триггеров будет автоматически заменена во время записи.';

  @override
  String get replacementsTriggerLabel => 'Фразы-триггеры';

  @override
  String get replacementsTriggerHint => 'напр. кст';

  @override
  String get replacementsAddTrigger => 'Добавить триггер';

  @override
  String get replacementsRemoveTrigger => 'Удалить триггер';

  @override
  String get replacementsReplacementLabel => 'Текст замены';

  @override
  String get replacementsReplacementHint => 'напр. кстати';

  @override
  String get replacementsDeleteTitle => 'Удалить замену';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Удалить замену \"$trigger\"? Это действие нельзя отменить.';
  }

  @override
  String get replacementsImportFromFolder => 'Импорт из папки';

  @override
  String get replacementsImportHint =>
      'Просканировать папку проекта на идентификаторы и добавить их как нечеткие замены — ничто не покидает ваше устройство.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return 'Найдено $found, добавлено $added, пропущено $skipped дубликатов';
  }

  @override
  String get replacementsImportScanning =>
      'Сканирование папки — для крупных проектов это может занять время…';

  @override
  String get replacementsImportError =>
      'Сбой импорта — не удалось отсканировать папку.';

  @override
  String get replacementsImportedBadge => 'Импортировано';

  @override
  String get replacementsImportNothingFound =>
      'В этой папке не найдено новых идентификаторов.';

  @override
  String get replacementsImportReviewTitle => 'Выберите, что импортировать';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return 'Найдено кандидатов: $count — выберите, какие станут заменами. Ничего не добавится до вашего подтверждения.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'Фильтр кандидатов';

  @override
  String get replacementsImportReviewSelectAllFiltered =>
      'Выбрать все показанные';

  @override
  String get replacementsImportReviewDeselectAll => 'Снять выбор';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return 'Выбрано $selected из $total';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'Ни один кандидат не соответствует фильтру.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'Импортировать выбранные ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'Совпадение';

  @override
  String get replacementsMatchModeExact => 'Точное';

  @override
  String get replacementsMatchModeFuzzy => 'Похожее';

  @override
  String get replacementsFuzzyToleranceLabel => 'Допуск';

  @override
  String get replacementsFuzzyToleranceStrict => 'Строгий';

  @override
  String get replacementsFuzzyToleranceStandard => 'Стандартный';

  @override
  String get replacementsFuzzyToleranceTolerant => 'Широкий';

  @override
  String get replacementsFuzzyToleranceHint =>
      'Насколько произнесенная фраза должна быть похожа на триггер. Строгий режим ловит только почти идентичное произношение. Стандартный — сбалансированный выбор. Широкий позволяет ловить заметно отличающиеся слова, но повышает риск случайных замен.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Триггеры короче $minLength символов не могут использовать похожее совпадение — слишком много ложных срабатываний.';
  }

  @override
  String get snippetsSearch => 'Поиск сниппетов…';

  @override
  String get snippetsSearchFieldLabel => 'Искать сниппеты';

  @override
  String get snippetsAdd => 'Добавить';

  @override
  String get snippetsEmpty => 'Пока нет сниппетов';

  @override
  String get snippetsEmptyHint =>
      'Добавьте сниппет, чтобы быстро использовать блок текста — например, подпись или шаблонный ответ.';

  @override
  String get snippetsNoMatches => 'Нет совпадений';

  @override
  String get snippetsNoMatchesHint => 'Попробуйте другой запрос.';

  @override
  String get snippetsEditSnippet => 'Редактировать сниппет';

  @override
  String get snippetsNewSnippet => 'Новый сниппет';

  @override
  String get snippetsDialogHint =>
      'Откройте панель сниппетов во время диктовки, чтобы вставить этот текст.';

  @override
  String get snippetsTitleLabel => 'Название';

  @override
  String get snippetsTitleHint => 'напр. Подпись для Email';

  @override
  String get snippetsBodyLabel => 'Тело сниппета';

  @override
  String get snippetsBodyHint => 'Текст, который вставляет этот сниппет…';

  @override
  String get snippetsKindLabel => 'Тип';

  @override
  String get snippetsKindStatic => 'Статический';

  @override
  String get snippetsKindInteractive => 'Интерактивный';

  @override
  String get snippetsFieldsLabel => 'Поля';

  @override
  String get snippetsFieldsHint =>
      'Вы заполните каждое поле отдельной короткой записью по порядку.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'Название поля $number';
  }

  @override
  String get snippetsFieldMoveUp => 'Переместить поле вверх';

  @override
  String get snippetsFieldMoveDown => 'Переместить поле вниз';

  @override
  String get snippetsFieldRemove => 'Удалить поле';

  @override
  String get snippetsFieldAdd => 'Добавить поле';

  @override
  String get snippetsFieldInsertIntoTemplate => 'Вставить в шаблон';

  @override
  String snippetsFieldsMinWarning(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min именованных полей',
      many: '$min именованных полей',
      few: '$min именованных поля',
      one: '1 именованное поле',
    );
    return 'Интерактивному сниппету требуется как минимум $_temp0.';
  }

  @override
  String get snippetsTemplateLabel => 'Шаблон';

  @override
  String get snippetsTemplateHint =>
      'Напишите текст сниппета, затем используйте кнопки вставки полей, чтобы поместить их куда нужно.';

  @override
  String get snippetsTemplateFieldHint =>
      'Напишите текст здесь и вставьте поля, используя кнопки выше.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'Не все поля добавлены в шаблон — их продиктованный текст не будет использован.';

  @override
  String get snippetsInteractiveBadge => 'Интерактивный';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count полей',
      many: '$count полей',
      few: '$count поля',
      one: '1 поле',
    );
    return '$_temp0 · Enter для начала';
  }

  @override
  String interactiveSnippetBriefingHint(String name) {
    return 'Поле 1: $name · Esc: отмена';
  }

  @override
  String interactiveSnippetAnnounceLabel(int index, int count, String name) {
    return 'Поле $index/$count: $name';
  }

  @override
  String get interactiveSnippetAnnounceHint => 'Приготовьтесь говорить…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'Далее';

  @override
  String get snippetsDeleteTitle => 'Удалить сниппет';

  @override
  String snippetsDeleteMessage(String title) {
    return 'Удалить сниппет \"$title\"? Это действие нельзя отменить.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Слово-триггер для выбора';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Скажите только это слово, чтобы открыть панель сниппетов. Оставьте пустым, чтобы отключить.';

  @override
  String get snippetsPickerTriggerHint => 'напр. сниппет';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'Слово-триггер установлено, но сниппетов пока нет — произнесение слова вставит его как обычный текст, пока вы не добавите первый сниппет.';

  @override
  String get snippetsPickerHotkeyLabel => 'Горячая клавиша панели';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Открывает панель напрямую — второй способ доступа к ней.';

  @override
  String get snippetsPickerHotkeyOff =>
      'Горячая клавиша панели сниппетов отключена.';

  @override
  String get snippetsPickerHotkeyEnable => 'Включить горячую клавишу';

  @override
  String get snippetsPickerUnavailable =>
      'Панель сниппетов пока недоступна на этой платформе.';

  @override
  String get snippetsPickerSemanticsLabel => 'Панель сниппетов';

  @override
  String get snippetsPickerInsertAction => 'Вставить';

  @override
  String get aboutTagline => 'Голос в текст, мгновенно.';

  @override
  String get aboutWhatsNew => 'Что нового';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutReportIssue => 'Сообщить о проблеме';

  @override
  String get aboutSupportTitle => 'Поддержать проект';

  @override
  String get aboutSupportDescription =>
      'WhisPaste — бесплатный проект с открытым исходным кодом по лицензии MIT. Спонсорство покрывает постоянные расходы (Apple Developer Program, Microsoft Partner Center и хостинг/домен), позволяя ему оставаться доступным на любой платформе.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Поставить звезду на GitHub';

  @override
  String get aboutSponsorsTitle => 'Спонсоры';

  @override
  String get supportPromptRecurringTitle => 'Сделать поддержку ежемесячной?';

  @override
  String get supportPromptRecurringDescription =>
      'Спасибо за вашу поддержку WhisPaste! Если хотите, вы можете превратить ее в небольшую ежемесячную подписку, чтобы покрывать постоянные расходы проекта.';

  @override
  String get aboutBuiltWith => 'Создано с помощью';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Кроссплатформенный UI на Flutter. Локальное распознавание через whisper.cpp и Parakeet.';

  @override
  String get aboutWhisper => 'whisper.cpp и OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Локальное и облачное распознавание речи: быстро, точно, многоязычно (99 языков).';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet и sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Локальное распознавание, настроенное на скорость без GPU (~25 языков).';

  @override
  String get aboutPrivacyFirst => 'Конфиденциальность превыше всего';

  @override
  String get aboutPrivacyFirstDesc =>
      'Локальное распознавание по умолчанию: ваш голос не покидает устройство, пока вы сами не выберете облачного провайдера.';

  @override
  String get aboutPrivacy => 'Конфиденциальность и данные';

  @override
  String get aboutPrivacyLocal =>
      'Все транскрипции и история хранятся локально на вашем устройстве, а не на внешних серверах.';

  @override
  String get aboutPrivacyCloud =>
      'Облачные провайдеры (OpenAI, Deepgram) получают аудио, только когда вы их используете. Применяются их политики конфиденциальности.';

  @override
  String get aboutPrivacyNoTracking =>
      'Статистика использования анонимна и соответствует GDPR, её можно отключить в Настройках. Нет учетных записей. Проверка обновлений связывается с GitHub.';

  @override
  String get aboutKeyboardShortcuts => 'Горячие клавиши';

  @override
  String get aboutShortcutRecord => 'Начать / Остановить запись';

  @override
  String get aboutLinks => 'Ссылки';

  @override
  String get aboutWebsite => 'Сайт';

  @override
  String get aboutGitHubRepo => 'Репозиторий GitHub';

  @override
  String get aboutFollowOnX => 'Следить в X';

  @override
  String get aboutMitLicense => 'Лицензия MIT';

  @override
  String get aboutViewOnGitHub => 'Смотреть на GitHub';

  @override
  String get aboutPrivacyPolicy => 'Политика конфиденциальности';

  @override
  String get aboutSystemInfo => 'Информация о системе';

  @override
  String get aboutSystemInfoDesc =>
      'Компактная отладочная информация для отчетов об ошибках.';

  @override
  String get aboutCopyDebugInfo => 'Копировать отладочную информацию';

  @override
  String get aboutCopied => 'Скопировано!';

  @override
  String get aboutMadeWith => 'Сделано с ♥ от WhisPaste';

  @override
  String get aboutOpenSource => 'Открытый исходный код под лицензией MIT';

  @override
  String get feedbackSubtitle =>
      'Помогите нам улучшить WhisPaste. Нам важен каждый голос.';

  @override
  String get feedbackCategoryLabel => 'О чем речь?';

  @override
  String get feedbackCategoryBug => 'Сообщить об ошибке';

  @override
  String get feedbackCategoryFeature => 'Идея новой функции';

  @override
  String get feedbackCategoryGeneral => 'Общее';

  @override
  String get feedbackCategoryAiQuality => 'Качество ИИ';

  @override
  String get feedbackRatingLabel => 'Ваши впечатления от WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Расскажите подробнее';

  @override
  String get feedbackPlaceholderBug =>
      'Опишите, что произошло и что ожидалось…';

  @override
  String get feedbackPlaceholderFeature =>
      'Что бы вы хотели видеть в WhisPaste?';

  @override
  String get feedbackPlaceholderAi => 'Как вам качество транскрипции?';

  @override
  String get feedbackPlaceholderGeneral => 'Поделитесь мыслями…';

  @override
  String get feedbackContactEmailLabel => 'Email (необязательно)';

  @override
  String get feedbackContactEmailExplanation =>
      'Только если ждете ответа. Используется исключительно для ответа по этому сообщению и удаляется через 90 дней.';

  @override
  String get feedbackContactEmailPlaceholder => 'vy@example.com';

  @override
  String get feedbackContactEmailInvalid =>
      'Пожалуйста, введите корректный адрес email или оставьте поле пустым.';

  @override
  String get feedbackContactLanguageLabel => 'Ответить на';

  @override
  String get feedbackContactLanguageHint => 'На каком языке нам отвечать вам?';

  @override
  String get feedbackSubmit => 'Отправить отзыв';

  @override
  String get feedbackPrivacyNote =>
      'По умолчанию анонимно. Мы узнаем вас, только если вы укажете email выше.';

  @override
  String get feedbackThankYou => 'Спасибо!';

  @override
  String get feedbackThankYouMessage =>
      'Ваш отзыв помогает делать WhisPaste лучше для всех.';

  @override
  String get feedbackSendAnother => 'Отправить еще';

  @override
  String get feedbackRatingFrustrated => 'Разочарован';

  @override
  String get feedbackRatingMeh => 'Так себе';

  @override
  String get feedbackRatingOkay => 'Нормально';

  @override
  String get feedbackRatingHappy => 'Доволен';

  @override
  String get feedbackRatingLoveIt => 'В восторге!';

  @override
  String get feedbackSubmitting => 'Отправка…';

  @override
  String get feedbackErrorRateLimited =>
      'Вы уже отправляли отзыв недавно. Попробуйте позже.';

  @override
  String get feedbackErrorNetwork =>
      'Не удалось подключиться к серверу. Проверьте интернет-соединение.';

  @override
  String get feedbackErrorServer => 'Что-то пошло не так. Попробуйте позже.';

  @override
  String get feedbackErrorNotConfigured => 'Отзывы недоступны в этой сборке.';

  @override
  String get statusBarOnDevice => 'На устройстве';

  @override
  String get statusBarOverlayFloating => 'Оверлей: Плавающий';

  @override
  String get statusBarOverlayOff => 'Оверлей: Выкл';

  @override
  String get statusBarAfterCopy => 'После: Копировать';

  @override
  String get statusBarAfterPaste => 'После: Вставить';

  @override
  String get statusBarAfterBoth => 'После: Копировать и Вставить';

  @override
  String get statusBarAfterNothing => 'После: Вручную';

  @override
  String get sttStatusStandby => 'Ожидание';

  @override
  String get sttStatusStarting => 'Запуск…';

  @override
  String get sttStatusReady => 'Готов';

  @override
  String get sttStatusError => 'Ошибка';

  @override
  String get statusBarSttTooltip => 'Голосовой сервис и текущий статус';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Бэкенд транскрипции: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'Реальную загрузку GPU нельзя измерить без повышенных прав; показан процент загрузки CPU процессом.';

  @override
  String get statusBarRecording => 'Запись…';

  @override
  String get statusBarTranscribing => 'Транскрипция…';

  @override
  String get statusBarRefining => 'Улучшение…';

  @override
  String get statusBarDone => 'Готово';

  @override
  String get statusBarHotkeyTooltip =>
      'Глобальная горячая клавиша: кликните для настройки';

  @override
  String get statusBarAutoPasteOffHint =>
      'Авто-вставка выкл, включите в Настройках';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Авто-вставка отключена. Кликните, чтобы открыть настройки.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Скрыть';

  @override
  String get modifierCtrl => 'Ctrl';

  @override
  String get modifierShift => 'Shift';

  @override
  String get modifierAlt => 'Alt';

  @override
  String get modifierWin => 'Win';

  @override
  String get modifierCmd => 'Cmd';

  @override
  String get modifierOption => 'Option';

  @override
  String get modifierAltGr => 'AltGr';

  @override
  String get shortcutKeySpace => 'Пробел';

  @override
  String get shortcutKeyEnter => 'Enter';

  @override
  String get shortcutKeyEscape => 'Esc';

  @override
  String get shortcutKeyBackspace => 'Backspace';

  @override
  String get shortcutKeyTab => 'Tab';

  @override
  String get shortcutKeyDelete => 'Del';

  @override
  String get shortcutKeyInsert => 'Insert';

  @override
  String get shortcutKeyHome => 'Home';

  @override
  String get shortcutKeyEnd => 'End';

  @override
  String get shortcutKeyPageUp => 'Page Up';

  @override
  String get shortcutKeyPageDown => 'Page Down';

  @override
  String get modelServerReady => 'Голосовой сервис готов';

  @override
  String get modelServerMissing => 'Голосовой сервис не установлен';

  @override
  String get modelServerWhisper => 'Локальный голосовой сервис';

  @override
  String get modelReady => 'Готова';

  @override
  String get modelDownloadComplete => 'Модель готова к использованию';

  @override
  String get modelUse => 'Использовать';

  @override
  String get modelDownload => 'Скачать';

  @override
  String get modelDownloading => 'Скачивание…';

  @override
  String get modelDownloadingEngine => 'Подготовка голосового сервиса…';

  @override
  String get modelVerifying => 'Проверка…';

  @override
  String get modelExtracting => 'Извлечение…';

  @override
  String get modelDeleteConfirm => 'Удалить эту модель?';

  @override
  String get modelDeleteConfirmMessage =>
      'Файл модели будет окончательно удален. Вы сможете загрузить его снова в любое время.';

  @override
  String get qualityTierCompactLabel => 'Быстро и компактно';

  @override
  String get qualityTierCompactDesc =>
      'Быстрые результаты, небольшая загрузка. Отлично подходит для коротких заметок.';

  @override
  String get qualityTierBalancedLabel => 'Сбалансированно';

  @override
  String get qualityTierBalancedDesc =>
      'Точно и надежно для повседневной записи. Работает на большинстве устройств.';

  @override
  String get qualityTierPremiumLabel => 'Лучшее качество';

  @override
  String get qualityTierPremiumDesc =>
      'Высочайшая точность для длинных записей. Требует мощного GPU.';

  @override
  String get qualityTierRecommended => 'Рекомендуется для вашего устройства';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size загрузка';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Скачать модель';

  @override
  String get qualityTierChooseDifferent => 'Выбрать другой уровень качества';

  @override
  String get qualityTierActive => 'Активно';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Лучшее качество, обработка занимает примерно в $ratio раз больше времени';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Лучшее качество, примерно в $ratio раз медленнее, чем Быстрое';
  }

  @override
  String get qualityTierInfoModerate => 'Хороший баланс скорости и качества';

  @override
  String get qualityTierBenchmarkReRun => 'Повторить тест производительности';

  @override
  String get qualityTierBenchmarkRun => 'Запустить тест производительности';

  @override
  String get qualityTierInfoBenchmarking => 'Тестирование производительности…';

  @override
  String get qualityTierActionOverride => 'Все равно использовать';

  @override
  String get qualityTierActionOverrideHint =>
      'Использовать этот уровень качества несмотря на предупреждение';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

  @override
  String get settingsQualityBasic => 'Базовое';

  @override
  String get settingsQualityBalanced => 'Сбалансированное';

  @override
  String get settingsQualityHigh => 'Высокое качество';

  @override
  String get settingsQualityBest => 'Лучшее качество';

  @override
  String get settingsQualityMaximum => 'Максимальная точность';

  @override
  String get settingsQualityRecommended => '★ Рекомендуется';

  @override
  String get settingsModelStatusReady => 'Модель готова';

  @override
  String get settingsModelStatusNeeded =>
      'Модель будет скачана при первой записи';

  @override
  String get settingsModelStatusDownloading => 'Скачивание модели…';

  @override
  String get settingsAdvancedModelManagement => 'Расширенные настройки моделей';

  @override
  String get infoEngineDownloading =>
      'Голосовой сервис подготавливается. Пожалуйста, подождите.';

  @override
  String get infoModelMissing => 'Сначала скачайте модель речи в Настройках.';

  @override
  String get infoPipelineBusy => 'WhisPaste все еще занят предыдущей записью.';

  @override
  String get infoSnippetPickerEmpty =>
      'Слово-триггер распознано, но у вас пока нет сниппетов — текст вставлен как обычно.';

  @override
  String get infoSnippetPickerEmptyAction => 'Открыть сниппеты';

  @override
  String get oomRecoveryTitle => 'Сбой записи: нехватка памяти GPU';

  @override
  String get oomRecoveryMessage =>
      'На вашей видеокарте не хватило памяти. Что делать дальше?';

  @override
  String get oomRecoveryTrySmaller => 'Меньшая модель';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Переключиться на $model и повторить попытку';
  }

  @override
  String get oomRecoverySwitchCloud => 'В облако';

  @override
  String get oomRecoverySwitchCloudHint =>
      'Использовать облачное распознавание речи';

  @override
  String get oomRecoveryCancel => 'Отмена';

  @override
  String get oomRecoveryPermanentTitle => 'Локальное распознавание недоступно';

  @override
  String get oomRecoveryPermanentMessage =>
      'Все локальные модели завершились с ошибкой из-за лимита памяти GPU. Пожалуйста, включите облачное распознавание в настройках.';

  @override
  String get oomRecoveryPermanentCloud => 'Открыть Настройки';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Переключение на $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Переключение на облачное распознавание…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Модель $model также завершилась с ошибкой. Пробуем следующий вариант…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'Качество снижено: нехватка видеопамяти. Переключено на более легкую модель.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Нехватка видеопамяти. Переключено в режим CPU для надежности.';

  @override
  String get errorSttServerConnectionLost =>
      'Голосовой сервис неожиданно остановился. Пожалуйста, попробуйте еще раз.';

  @override
  String get errorSttCudaOom =>
      'Нехватка видеопамяти. Качество было снижено, так что следующая попытка должна сработать.';

  @override
  String get errorCloudAuth =>
      'Облачный API-ключ отсутствует или неверен. Проверьте его в Настройках → Распознавание речи.';

  @override
  String get errorCloudQuota =>
      'Достигнут лимит запросов облачного провайдера. Немного подождите и попробуйте еще раз.';

  @override
  String get errorOnboardingNotCompleted =>
      'Пожалуйста, сначала завершите мастер настройки.';

  @override
  String get errorSttModelNotFound =>
      'Модель не найдена. Пожалуйста, скачайте ее в Настройках.';

  @override
  String get errorSttModelUnknown =>
      'Неизвестная модель. Пожалуйста, выберите существующую модель в Настройках.';

  @override
  String get errorRecordingFailed =>
      'Не удалось начать запись, пожалуйста, попробуйте еще раз';

  @override
  String get errorNoAudioRecorded =>
      'Аудио не записано, пожалуйста, попробуйте еще раз';

  @override
  String get errorTranscriptionEmpty =>
      'Транскрипция вернула пустой текст, пожалуйста, попробуйте еще раз';

  @override
  String get errorSttServerFailed => 'Не удалось запустить голосовой сервис';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'Голосовая модель несовместима с установленной средой. Пожалуйста, скачайте модель заново в Настройках.';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'Похоже, модель повреждена. Автоматически скачиваем заново.';

  @override
  String get errorSttDllMissing =>
      'Отсутствует необходимый системный компонент. Повторяем попытку в режиме CPU.';

  @override
  String get errorSttGpuFatal =>
      'Сбой аппаратного ускорения. Повторяем попытку в режиме CPU.';

  @override
  String get errorSttHeapCorruption =>
      'Произошла ошибка памяти. Повторяем попытку в режиме CPU.';

  @override
  String get errorSttCpuFallbackFailed =>
      'Голосовой сервис не сработал ни на GPU, ни на CPU. Перезапустите приложение или скачайте модель заново.';

  @override
  String get errorPipelineTimeout =>
      'Запись длилась слишком долго. Попробуйте записать более короткий фрагмент.';

  @override
  String get errorWavFileNotCreated =>
      'Не удалось сохранить аудиофайл. Пожалуйста, попробуйте еще раз.';

  @override
  String get errorWavFileEmpty =>
      'Звук не был записан. Пожалуйста, проверьте микрофон.';

  @override
  String get errorSttStartTimeout =>
      'Голосовой сервис все еще запускается. Попробуйте чуть позже.';

  @override
  String get errorTranscriptionTimeout =>
      'Транскрипция заняла слишком много времени. Попробуйте записать более короткий фрагмент.';

  @override
  String get errorMicPermissionDenied =>
      'Необходим доступ к микрофону. Разрешите его в системных настройках.';

  @override
  String get errorRecordingStartFailed =>
      'Не удалось начать запись. Пожалуйста, попробуйте еще раз.';

  @override
  String get errorGeneric =>
      'Что-то пошло не так. Пожалуйста, попробуйте еще раз.';

  @override
  String get modelDownloadFailed =>
      'Сбой скачивания. Проверьте ваше подключение к интернету.';

  @override
  String get statusSttLoading => 'Загрузка модели…';

  @override
  String get statusSttReady => 'Модель готова';

  @override
  String get historyDuplicate => 'Дублировать';

  @override
  String get historyDuplicated => 'Запись продублирована';

  @override
  String get historyViewRaw => 'Оригинал';

  @override
  String get historyViewEdited => 'Отредактировано';

  @override
  String get historyApplySmartModePreset => 'Применить пресет Умного режима';

  @override
  String get historySmartModeApplied => 'Умный режим применен';

  @override
  String get historySmartModeFailedModelMissing =>
      'Модель Умного режима не скачана';

  @override
  String get historySmartModeFailedTimeout =>
      'Время ожидания Умного режима истекло';

  @override
  String get historySmartModeFailedGeneric =>
      'Сбой Умного режима — пожалуйста, попробуйте еще раз';

  @override
  String get historySmartModeSelectTargetLanguage => 'Выберите целевой язык';

  @override
  String get historyAddNote => 'Добавить примечание';

  @override
  String get historyEditNote => 'Изменить примечание';

  @override
  String get historyNotes => 'Примечания';

  @override
  String get historyNotePlaceholder => 'Напишите примечание…';

  @override
  String get historyVoiceNoteHint =>
      'Подсказка: скажите «тег: имя» или «исправить: текст» во время записи.';

  @override
  String get historyNoteAdded => 'Примечание добавлено';

  @override
  String get historyNoteDeleted => 'Примечание удалено';

  @override
  String get historyCopiedAsMarkdown => 'Скопировано как Markdown';

  @override
  String get historyAddTag => 'Добавить тег…';

  @override
  String get historySearchTags => 'Поиск или создание…';

  @override
  String get historyNoteEdited => 'изменено';

  @override
  String get historyTagAdded => 'Тег добавлен';

  @override
  String get historyTagRemoved => 'Тег удален';

  @override
  String historyCreateTag(Object tag) {
    return 'Создать \"$tag\"';
  }

  @override
  String get historyManageTags => 'Управление тегами';

  @override
  String get tagManageTitle => 'Управление тегами';

  @override
  String get tagManageEmpty => 'Пока нет созданных тегов.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записей',
      many: '$count записей',
      few: '$count записи',
      one: '1 запись',
      zero: 'не используется',
    );
    return '$_temp0';
  }

  @override
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count тегов',
      many: '$count тегов',
      few: '$count тега',
      one: '1 тег',
    );
    return 'еще $_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => 'Удалить тег?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записях',
      many: '$count записях',
      few: '$count записях',
      one: '1 записи',
    );
    return 'Тег \"$name\" используется в $_temp0. Он будет удален отовсюду.';
  }

  @override
  String tagDeleted(String name) {
    return 'Тег \"$name\" удален';
  }

  @override
  String get tagDeleteUnusedTitle => 'Удалить неиспользуемые теги?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count неиспользуемых тегов',
      many: '$count неиспользуемых тегов',
      few: '$count неиспользуемых тега',
      one: '1 неиспользуемый тег',
    );
    return '$_temp0 будет удален навсегда.';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return 'Удалить $count неиспользуемых';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count неиспользуемых тегов удалено',
      many: '$count неиспользуемых тегов удалено',
      few: '$count неиспользуемых тега удалены',
      one: '1 неиспользуемый тег удален',
    );
    return '$_temp0';
  }

  @override
  String get historyEditTranscript => 'Изменить транскрипцию';

  @override
  String get historyTranscriptSaved => 'Транскрипция сохранена';

  @override
  String get historySaveTranscript => 'Сохранить';

  @override
  String get historyShortcutHelp => 'Горячие клавиши';

  @override
  String get historyShortcutGeneral => 'ОСНОВНЫЕ';

  @override
  String get historyShortcutTags => 'Фокус на ввод тега';

  @override
  String get historyShortcutNotes => 'Добавить примечание';

  @override
  String get historyShortcutPin => 'В избранное / Убрать из избранного';

  @override
  String get historyShortcutClose => 'Сохранить и закрыть';

  @override
  String get historyShortcutEditing => 'РЕДАКТИРОВАНИЕ';

  @override
  String get historyShortcutToggleEdit => 'Режим редактирования';

  @override
  String get historyShortcutSave => 'Сохранить транскрипцию';

  @override
  String get historyShortcutBold => 'Жирный';

  @override
  String get historyShortcutItalic => 'Курсив';

  @override
  String get historyShortcutCopy => 'Скопировать в буфер обмена';

  @override
  String get historyShortcutEditTitle => 'Изменить название';

  @override
  String get historyEditTitle => 'Изменить название';

  @override
  String get historyTitlePlaceholder => 'Введите название…';

  @override
  String get historyTitleSaved => 'Название сохранено';

  @override
  String get historySearchHelpTitle => 'Советы по поиску';

  @override
  String get historySearchHelpTags => 'Введите # для фильтрации по тегам';

  @override
  String get historySearchHelpLang => 'Введите lang: для фильтрации по языку';

  @override
  String get historySearchHelpFreeText => 'Или просто введите любое слово';

  @override
  String get historySearchQuickTags => 'Популярные теги';

  @override
  String get historyRecentSearches => 'Недавние поиски';

  @override
  String get historyRemoveRecentSearch => 'Удалить недавний поиск';

  @override
  String get historyRemoveFilter => 'Удалить фильтр';

  @override
  String get historyQuickActions => 'Быстрые фильтры';

  @override
  String get historyQuickActionAllLangs => 'Все языки';

  @override
  String get historyQuickActionFavorites => 'Только избранное';

  @override
  String get historySortNewest => 'Сначала новые';

  @override
  String get historySortOldest => 'Сначала старые';

  @override
  String get historySortLongest => 'Сначала длинные';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'Фильтр по тегу';

  @override
  String get historySearchSuggestLang => 'Фильтр по языку';

  @override
  String get settingsKeyboardShortcut => 'Горячая клавиша';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Глобальная комбинация клавиш для запуска и остановки записи';

  @override
  String get settingsHotkeyEnabled => 'Включить глобальную клавишу';

  @override
  String get settingsCurrentHotkey => 'Текущая комбинация';

  @override
  String get settingsChangeHotkey => 'Изменить';

  @override
  String get settingsHotkeyRecorderTitle => 'Записать новую горячую клавишу';

  @override
  String get settingsHotkeyRecorderHint =>
      'Нажмите комбинацию клавиш, которую хотите использовать…';

  @override
  String get settingsHotkeyRecorderModifierHint =>
      'Любая комбинация модификаторов работает: например, Alt+Space, Ctrl+Alt+V или Ctrl+Alt+Shift+R';

  @override
  String get settingsHotkeyRecorderCancel => 'Отмена';

  @override
  String get settingsHotkeyRecorderSave => 'Сохранить';

  @override
  String get settingsHotkeyRecorderClear => 'Очистить';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'Эта клавиша не может использоваться как горячая клавиша. Попробуйте букву, цифру, функциональную клавишу (F1-F12) или стрелки.';

  @override
  String get settingsHotkeyActionRecording => 'Начать/остановить запись';

  @override
  String get settingsHotkeyActionQuickNote => 'Быстрая заметка';

  @override
  String get settingsQuickNoteHotkeyEnabled =>
      'Горячая клавиша быстрой заметки';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'Надиктованный текст добавляется к заметке, отмеченной как быстрая. Вы выбираете эту заметку в разделе Заметки.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Комбинация';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша быстрой заметки в данный момент не активна. Выберите другую комбинацию.';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Панель сниппетов';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Горячая клавиша панели сниппетов';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Сразу открывает панель сниппетов — без записи и без произнесения слова-триггера.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Комбинация';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша панели сниппетов в данный момент не активна. Выберите другую комбинацию.';

  @override
  String get settingsMaxRecordDuration => 'Макс. длительность записи';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Автоматическая остановка для безопасности после этого времени';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Без ограничений';

  @override
  String get settingsCloseToTray => 'Сворачивать в трей';

  @override
  String get settingsCloseToTraySubtitle =>
      'Оставлять приложение работать в фоновом режиме при закрытии окна';

  @override
  String get settingsSidePanelEnabled => 'Боковая панель буфера обмена';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'Выезжающая панель при наведении на левый край экрана для транскрипций, сниппетов и истории буфера обмена';

  @override
  String get settingsErrorReporting => 'Отчеты об ошибках';

  @override
  String get settingsErrorReportingSubtitle =>
      'Помогите улучшить WhisPaste, отправляя анонимные отчеты о сбоях';

  @override
  String get settingsAutoPasteDelay => 'Задержка авто-вставки';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Время ожидания перед вставкой в активное окно';

  @override
  String get settingsAutoPasteBlocklist => 'Исключения для авто-вставки';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Идентификаторы приложений через запятую, в которых авто-вставка отключена';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'например: com.apple.Terminal, com.1password';

  @override
  String get settingsCheckUpdates => 'Проверять обновления';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Автоматически проверять наличие новых версий при запуске';

  @override
  String get settingsCheckForUpdatesNow => 'Проверить обновления сейчас';

  @override
  String get settingsUpdates => 'Обновления';

  @override
  String get settingsUpdatesSubtitle => 'Канал обновлений и проверки';

  @override
  String get settingsBetaUpdates => 'Бета-обновления';

  @override
  String get settingsBetaUpdatesSubtitle =>
      'Получать ранние версии, которые меньше протестированы.';

  @override
  String get settingsStableRevertHintMessage =>
      'Автоматическое переключение на стабильную версию невозможно. У вас уже установлена более новая бета-версия.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'Скачать стабильную версию $stableVersion вручную';
  }

  @override
  String get onboardingNext => 'Далее';

  @override
  String get onboardingBack => 'Назад';

  @override
  String get onboardingPrivacyTitle => 'Помогите сделать WhisPaste лучше';

  @override
  String get onboardingPrivacyHint =>
      'Аудио и текст остаются на устройстве. Только анонимная статистика отправляется на наш сервер в ЕС.';

  @override
  String get onboardingPrivacyToggle =>
      'Отправлять анонимную статистику использования';

  @override
  String get onboardingPrivacyToggleHint =>
      'Включено по умолчанию, можно отключить в любой момент';

  @override
  String get onboardingPrivacyCrashToggle =>
      'Отправлять анонимные отчеты о сбоях';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'Помогает исправлять ошибки, включено по умолчанию, можно отключить';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'Внешний вид';

  @override
  String get onboardingAppearancePageSubtitle =>
      'Как запускается приложение, и как выглядит оверлей записи.';

  @override
  String get onboardingBeat1Title => 'Хоткей, голос, готово';

  @override
  String get onboardingBeat1Caption =>
      'Запись начинается мгновенно — слова становятся текстом у курсора.';

  @override
  String get onboardingBeat2Title => 'Локально, на вашем железе';

  @override
  String get onboardingBeat2Caption =>
      'Транскрипция — на вашем устройстве, интернет не нужен.';

  @override
  String get onboardingBeat3Title => 'Везде, где печатаете';

  @override
  String get onboardingBeat3Caption =>
      'Браузер, почта, редактор — WhisPaste работает везде.';

  @override
  String get onboardingMicChipReady => 'Микрофон готов';

  @override
  String get onboardingMicChipPending => 'Ожидание доступа к микрофону';

  @override
  String get onboardingMicChipAction => 'Микрофон: требуется действие';

  @override
  String get onboardingModelTitle => 'Настройка распознавания речи';

  @override
  String get onboardingModelSubtitle =>
      'Скачайте голосовую модель для записи офлайн. Ваш голос не покидает устройство.';

  @override
  String get onboardingModelRecommended => 'Рекомендуется';

  @override
  String get onboardingModelChangeLater =>
      'Вы сможете изменить качество позже в Настройках';

  @override
  String get onboardingModelDownloading => 'Скачивание…';

  @override
  String get onboardingModelReady => 'Модель готова';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Оптимизированное ускорение GPU недоступно, используется CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Быстро и в Европе';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'Самый быстрый способ набрать текст на ~25 европейских языках, включая немецкий. Работает на любой технике, с GPU и без.';

  @override
  String get onboardingModelEngineWhisperLabel => 'Все 99 языков';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'Широчайший охват языков, плюс свой словарь и пунктуация для имен, акронимов и жаргона.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Пока не поддерживает выбранный вами язык';

  @override
  String get onboardingTestRecordingTitle => 'Попробуйте';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Нажмите на кнопку ниже и скажите предложение. Текст появится в поле. Горячая клавиша тоже работает.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Ваша клавиша';

  @override
  String get onboardingTestRecordingStartCta => 'Начать запись';

  @override
  String get onboardingTestRecordingStopCta => 'Остановить запись';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'Сделайте пробную запись, чтобы продолжить.';

  @override
  String get onboardingTestRecordingMicBypassCta => 'Продолжить без микрофона';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'Без рабочего микрофона WhisPaste пока не может начать запись. Вы можете настроить его в любое время в Настройках.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'Ваш сказанный текст появится здесь …';

  @override
  String get onboardingTestRecordingInProgress =>
      'Запись: просто начните говорить. Нажмите еще раз, чтобы остановить.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      'Вот и все! Именно так это работает в любом приложении.';

  @override
  String get onboardingTestRecordingReassurance =>
      'Это просто тест, текст останется в этом поле.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'Это просто тест, текст останется в этом поле — запись автоматически остановится через $seconds сек., настраивается в Настройки → $section.';
  }

  @override
  String get onboardingReadyTitle => 'Всё готово!';

  @override
  String get onboardingReadySubtitle => 'Как пользоваться WhisPaste';

  @override
  String get onboardingReadyStep1 =>
      'Нажмите горячую клавишу для начала записи';

  @override
  String get onboardingReadyStep2 => 'Нажмите еще раз, чтобы остановить';

  @override
  String get onboardingReadyStep3AutoPaste =>
      'Текст льется прямо в активное приложение';

  @override
  String get onboardingReadyStep3CopyOnly =>
      'Текст в буфере обмена, нажмите ⌘V / Ctrl+V для вставки';

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste сохраняет контекст предыдущей записи до десяти минут. Перед сменой темы небольшая пауза поможет результату оставаться точным.';

  @override
  String get onboardingReadyAutostartToggle => 'Запускать WhisPaste при входе';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Отключено по умолчанию, включается в Настройках';

  @override
  String get onboardingTriggerTitle => 'Как вы хотите начать запись?';

  @override
  String get onboardingTriggerSubtitle =>
      'Установите горячую клавишу и выберите режим ее работы.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Текущая комбинация';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Комбинация уже занята';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Ваша горячая клавиша используется другим приложением. Запишите новую комбинацию.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Вернитесь на страницу горячих клавиш и задайте новую комбинацию.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Удерживайте и говорите, отпустите для завершения';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Нажмите для старта, нажмите еще раз для завершения';

  @override
  String get onboardingTriggerSystemWideHint =>
      'Работает во всей системе — не только внутри WhisPaste.';

  @override
  String get onboardingStartUsing => 'Поехали';

  @override
  String get onboardingReviewExit => 'Закрыть введение';

  @override
  String get onboardingReviewDone => 'Готово';

  @override
  String get onboardingReviewEntry => 'Введение';

  @override
  String get onboardingReviewSubtitle =>
      'Вы можете пройти настройку еще раз в любое время — ничего не изменится, пока вы сами не решите.';

  @override
  String get onboardingReviewLabel => 'Посмотреть введение';

  @override
  String get onboardingReviewAction => 'Открыть';

  @override
  String get onboardingRevisionNoticeTitle =>
      'WhisPaste обновлен — ваши настройки не изменились.';

  @override
  String get onboardingRevisionExit => 'Покинуть введение';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Покинуть введение?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Это руководство по обновлению показывается один раз, пропущенные шаги не будут настроены. Вы можете вернуться к ним через Настройки → Введение. Уже настроенные параметры останутся без изменений.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Покинуть';

  @override
  String get overlayRecording => 'Запись';

  @override
  String get overlayTranscribing => 'Транскрипция…';

  @override
  String get overlayRefining => 'Улучшение…';

  @override
  String get overlayDone => 'Скопировано';

  @override
  String get overlayDonePasted => 'Вставлено';

  @override
  String get overlayDoneBoth => 'Скопировано и вставлено';

  @override
  String get overlayDoneReady => 'Готово';

  @override
  String get overlayError => 'Ошибка';

  @override
  String get overlayCancel => 'Отмена';

  @override
  String get overlayPause => 'Пауза';

  @override
  String get overlayResume => 'Продолжить';

  @override
  String get overlayStop => 'Стоп';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'Нажмите $hotkey для остановки';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Enter или $hotkey: следующее поле · Esc: отмена';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Enter: следующее поле · Esc: отмена';

  @override
  String get overlayProcessingLocal => 'Локально';

  @override
  String get overlayProcessingCloud => 'В облаке';

  @override
  String get overlayRecordingQuickNote => 'Запись в заметку';

  @override
  String get overlayTargetQuickNote => 'Заметка';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayDoneQuickNote => 'Добавлено в заметку';

  @override
  String get floatingButtonHide => 'Скрыть';

  @override
  String get floatingButtonQuit => 'Выйти';

  @override
  String get a11yRecordingButton => 'Кнопка записи';

  @override
  String get a11yRecordingOverlay => 'Оверлей записи';

  @override
  String get a11ySidePanel => 'Панель быстрой вставки';

  @override
  String get trayStatusRecording => 'Запись…';

  @override
  String get trayStatusReady => 'Готов';

  @override
  String get trayStartRecording => 'Начать запись';

  @override
  String get trayStopRecording => 'Остановить запись';

  @override
  String get trayOpenApp => 'Открыть WhisPaste';

  @override
  String get traySettings => 'Настройки';

  @override
  String get trayQuit => 'Выход';

  @override
  String get trayMicrophone => 'Микрофон';

  @override
  String get settingsComingSoon => 'Скоро';

  @override
  String get undo => 'Отменить';

  @override
  String get hintDismiss => 'Скрыть подсказку';

  @override
  String get voiceNoteButton => 'Голосовое примечание';

  @override
  String get voiceNoteRecording => 'Запись примечания…';

  @override
  String get voiceNoteTranscribing => 'Транскрипция…';

  @override
  String get voiceNoteAdded => 'Голосовое примечание добавлено';

  @override
  String voiceTagAdded(String tag) {
    return 'Тег \"$tag\" добавлен голосом';
  }

  @override
  String get voiceCorrectionApplied => 'Транскрипция исправлена голосом';

  @override
  String get voiceNoteEmpty => 'Речь не распознана';

  @override
  String get voiceNoteError => 'Сбой голосового примечания';

  @override
  String updateAvailable(String version) {
    return 'Доступно обновление: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Скачивание обновления… $percent%';
  }

  @override
  String get updateReadyToInstall => 'Обновление готово, нажмите для установки';

  @override
  String get updateUpToDate => 'У вас установлена последняя версия';

  @override
  String get updateCheckNow => 'Проверить сейчас';

  @override
  String get updateInstall => 'Установить обновление';

  @override
  String get updateDownload => 'Скачать';

  @override
  String get updateViewRelease => 'Примечания к выпуску';

  @override
  String get updateError => 'Ошибка проверки обновлений';

  @override
  String get updateRateLimited => 'Слишком много запросов, попробуйте позже';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version доступна';
  }

  @override
  String get settingsOverlaySize => 'Размер оверлея';

  @override
  String get settingsOverlaySizeSubtitle =>
      'Выберите между подробным или минималистичным отображением';

  @override
  String get settingsOverlaySizeNormal => 'Обычный';

  @override
  String get settingsOverlaySizeCompact => 'Компактный';

  @override
  String get settingsOverlaySizeMini => 'Мини';

  @override
  String get settingsOverlayStyle => 'Стиль оверлея';

  @override
  String get settingsOverlayStyleSubtitle =>
      'Выберите между стеклянным или сплошным непрозрачным видом';

  @override
  String get settingsOverlayStyleGlass => 'Стекло';

  @override
  String get settingsOverlayStyleSolid => 'Сплошной';

  @override
  String get overlayRetry => 'Повторить';

  @override
  String get overlayDismiss => 'Скрыть';

  @override
  String get overlayContextCancel => 'Отменить запись';

  @override
  String get overlayContextSwitchNormal => 'Обычный вид';

  @override
  String get overlayContextSwitchCompact => 'Компактный вид';

  @override
  String get overlayContextSwitchMini => 'Мини-вид';

  @override
  String get overlayContextHide => 'Скрыть оверлей';

  @override
  String get buttonContextOpen => 'Открыть WhisPaste';

  @override
  String get buttonContextStartRecording => 'Начать запись';

  @override
  String get buttonContextShowHistory => 'Показать историю';

  @override
  String get buttonContextSettings => 'Настройки';

  @override
  String get buttonContextQuit => 'Выйти из WhisPaste';

  @override
  String get settingsHistory => 'История';

  @override
  String get settingsHistorySubtitle => 'Хранение и автоматическая очистка';

  @override
  String get settingsHistoryMaxEntries => 'Максимум записей';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'Без ограничений';

  @override
  String get settingsHistoryAutoTrashDays => 'Автоудаление корзины через';

  @override
  String get settingsHistoryAutoTrashNever => 'Никогда';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней',
      many: '$count дней',
      few: '$count дня',
      one: '1 день',
    );
    return '$_temp0';
  }

  @override
  String get settingsHistoryRetentionPreset => 'Хранение';

  @override
  String get settingsHistoryPresetMinimal => 'Минимальное';

  @override
  String get settingsHistoryPresetStandard => 'Стандартное';

  @override
  String get settingsHistoryPresetUnlimited => 'Без ограничений';

  @override
  String get settingsHistoryPresetCustom => 'Своё';

  @override
  String get settingsFloatingButtonSection => 'Плавающая кнопка';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Всегда видимая поверх окон кнопка для быстрого доступа';

  @override
  String get settingsSttIdleTimeout => 'Время простоя сервиса';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Как долго голосовой сервис остается загруженным после использования';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Не выгружать';

  @override
  String settingsSttIdleTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минут',
      many: '$count минут',
      few: '$count минуты',
      one: '1 минута',
    );
    return '$_temp0';
  }

  @override
  String get reviewPromptTitle => 'Вам нравится WhisPaste?';

  @override
  String get reviewPromptBody =>
      'Ваша оценка помогает другим найти приложение и поддерживает его развитие.';

  @override
  String get reviewPromptYes => 'Очень нравится!';

  @override
  String get reviewPromptNotNow => 'Не сейчас';

  @override
  String get reviewPromptNever => 'Больше не спрашивать';

  @override
  String get reviewPromptStarGitHub => '⭐ Поставить звезду на GitHub';

  @override
  String get reviewPromptRateStore => '★ Оценить в магазине';

  @override
  String get reviewPromptGateBody =>
      'Только небольшой вопрос для нас, это не оценка в магазине.';

  @override
  String get reviewPromptGateYes => 'Да, нравится';

  @override
  String get reviewPromptGateNo => 'Не совсем';

  @override
  String get reviewSupportEntry => 'Оценить и поддержать WhisPaste';

  @override
  String get reviewSupportLabel => 'Ваша оценка';

  @override
  String get reviewSupportSubtitle =>
      'Ваша оценка помогает другим найти WhisPaste и поддерживает проект.';

  @override
  String get reviewSupportAction => 'Оценить';

  @override
  String get insufficientRamTitle => 'Недостаточно памяти';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'Для работы WhisPaste требуется не менее $requiredGb ГБ оперативной памяти. У вас $detectedGbString ГБ.\n\nПри меньшем объеме памяти ИИ может не загрузиться или дать сбой в процессе работы.';
  }

  @override
  String get insufficientRamQuit => 'Выйти из WhisPaste';

  @override
  String get insufficientRamLearnMore => 'Системные требования';

  @override
  String get insufficientRamSystemCheck => 'Проверка системы';

  @override
  String get insufficientRamYourSystem => 'Ваша система';

  @override
  String get insufficientRamRequired => 'Требуется';

  @override
  String get hotkeyRegistrationFailed =>
      'Сбой регистрации горячей клавиши, пожалуйста, переназначьте ее в Настройках.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'Сбой регистрации горячей клавиши, используется резервная Ctrl+Shift+Space. Переназначьте ее в Настройках.';

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Эта комбинация зарезервирована $platform ($note) и может не работать.';
  }

  @override
  String get exportFormatPickerTitle => 'Выберите формат экспорта';

  @override
  String get exportFormatText => 'Текст';

  @override
  String get exportFormatMarkdown => 'Markdown';

  @override
  String get exportFormatCsv => 'CSV';

  @override
  String get exportFormatJson => 'JSON';

  @override
  String get exportFormatWord => 'Word';

  @override
  String get cpuFallbackToast =>
      'Транскрипция сейчас занимает чуть больше времени, чем обычно, процесс идет.';

  @override
  String get recoveryExhaustedToast =>
      'Голосовой сервис не может запуститься. Перезапустите приложение или скачайте модель заново.';

  @override
  String get recoveryExhaustedAction => 'Открыть настройки';

  @override
  String get recoveryVcRuntimeToast =>
      'Голосовой сервис не может запуститься: отсутствует компонент Windows (Microsoft Visual C++). Пожалуйста, установите Visual C++ Redistributable (x64) и перезапустите WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Установить';

  @override
  String get modelAbiInfoToast =>
      'Перезагрузка голосовой модели, пожалуйста, подождите.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste работает без ускорения GPU из-за проблемы при прошлом запуске. Диктовка работает как обычно.';

  @override
  String get serverDownloadFailedToast =>
      'Не удалось скачать голосовой сервис. Проверьте интернет-соединение.';

  @override
  String get serverDownloadFailedAction => 'Повторить';

  @override
  String get serverDownloadStalledToast =>
      'Скачивание зависло: переподключение.';

  @override
  String get historyWriteFailedToast =>
      'Запись не сохранена, проверьте доступное место на диске.';

  @override
  String get historyWriteFailedAction => 'Скопировать диагностику';

  @override
  String get factoryResetFailedToast =>
      'Сброс к заводским настройкам не завершен. Перезапустить приложение?';

  @override
  String get factoryResetFailedAction => 'Выйти';

  @override
  String get errorSttRejectEmpty =>
      'Нет звука для транскрипции, запишите еще раз.';

  @override
  String get errorSttRejectInvalidWav =>
      'Аудиофайл поврежден, запишите еще раз.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'Этот язык не поддерживается локальной моделью, проверьте язык в Настройках.';

  @override
  String get errorSttRejectPromptTooLong =>
      'Свой словарь слишком велик, сократите его в Настройках.';

  @override
  String get settingsGpuAcceleration => 'Аппаратное ускорение';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Управляет тем, использует ли сервис GPU или CPU для локального распознавания';

  @override
  String get settingsGpuAccelerationAuto => 'Автоматически (рекомендуется)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (принудительно)';

  @override
  String get settingsGpuAccelerationDisabled => 'Только CPU';

  @override
  String get settingsSttEngine => 'Движок';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper поддерживает 99 языков и любой GPU; Parakeet работает намного быстрее на CPU, но поддерживает ~25 языков и пока не имеет поддержки GPU';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet =>
      'Parakeet (самый быстрый, ~25 языков)';

  @override
  String get parakeetModelTitle => 'Модель Parakeet TDT';

  @override
  String get parakeetModelSubtitle =>
      'Единоразовая загрузка (~640 МБ), работает полностью офлайн';

  @override
  String get parakeetModelDownload => 'Скачать';

  @override
  String get parakeetModelDownloading => 'Скачивание…';

  @override
  String get parakeetModelInstalled => 'Установлено';

  @override
  String get parakeetModelDelete => 'Удалить';

  @override
  String get parakeetModelCancel => 'Отмена';

  @override
  String get settingsSearchHint => 'Поиск настроек…';

  @override
  String get settingsSearchNoResults => 'Нет результатов';

  @override
  String get settingsSearchNoResultsHint => 'Попробуйте другой запрос.';

  @override
  String get settingsSearchFieldLabel => 'Поиск настроек';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результатов',
      many: '$count результатов',
      few: '$count результата',
      one: '1 результат',
      zero: 'Нет результатов',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'Конфиденциальность';

  @override
  String get settingsPrivacySubtitle => 'Управление передачей данных';

  @override
  String get settingsShareUsageStats =>
      'Отправлять анонимную статистику использования';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Отправляется без куки и идентификаторов, чтобы помочь нам понять, как используется WhisPaste';

  @override
  String get settingsRetainRecentAudio => 'Сохранять недавние аудио';

  @override
  String get settingsRetainRecentAudioSubtitle =>
      'Сохраняет аудио ваших последних 20 диктовок на устройстве для отладки или восстановления транскрипции; старые записи удаляются автоматически';

  @override
  String get storeThankYouTitle => 'Спасибо за поддержку!';

  @override
  String get storeThankYouBody =>
      'Мы очень рады, что вы с нами. Если WhisPaste делает ваш день немного проще, ваш отзыв будет много значить для нас.';

  @override
  String get storeThankYouCtaStore => '★ Оценить в магазине';

  @override
  String get storeThankYouCtaGitHub => '⭐ Поставить звезду на GitHub';

  @override
  String get storeThankYouDismiss => 'Закрыть';

  @override
  String get featureSpotlightHeading => 'Новое в WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Понятно';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Панель сниппетов';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Сохраняйте текстовые блоки и вставляйте их по горячей клавише или слову-триггеру — не нужно печатать одно и то же.';

  @override
  String get featureSpotlightSidePanelTitle => 'Боковая панель буфера';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Наведите на край экрана, чтобы открыть недавнюю историю буфера обмена и перетащить любой элемент прямо в документ.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle =>
      'Интерактивные сниппеты';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'Сниппеты с пропусками: WhisPaste проведет вас по каждому полю — надиктуйте, нажмите Enter для следующего, и готовый текст вставится целиком.';

  @override
  String get featureSpotlightSmartModeTitle => 'Умный режим';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Очищайте, сокращайте или переводите диктовку перед вставкой — полностью на устройстве, со своей горячей клавишей и пресетом.';

  @override
  String get featureSpotlightChangelogLink => 'Полный список изменений';

  @override
  String get featureSpotlightReviewLabel => 'Посмотреть новые функции';

  @override
  String get featureSpotlightReviewAction => 'Показать';

  @override
  String get notesNewNote => 'Новая заметка';

  @override
  String get notesEmptyTitle => 'Пока нет заметок';

  @override
  String get notesEmptyHint =>
      'Создайте заметку, чтобы сохранять туда текст откуда угодно.';

  @override
  String get notesUntitled => 'Заметка без названия';

  @override
  String get notesEditorPlaceholder => 'Начните печатать…';

  @override
  String get notesListSemantics => 'Список заметок';

  @override
  String get notesCopy => 'Копировать заметку';

  @override
  String get notesCopied => 'Заметка скопирована';

  @override
  String get notesFavorite => 'Добавить в избранное';

  @override
  String get notesUnfavorite => 'Убрать из избранного';

  @override
  String get notesQuickNoteSet =>
      'Сделать быстрой заметкой для горячей клавиши';

  @override
  String get notesQuickNoteClear => 'Убрать отметку быстрой заметки';

  @override
  String get notesQuickNoteHotkeyLabel => 'Горячая клавиша';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'Изменить горячую клавишу быстрой заметки — сейчас $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff =>
      'Горячая клавиша быстрой заметки отключена.';

  @override
  String get notesQuickNoteHotkeyEnable => 'Включить горячую клавишу';

  @override
  String get notesMoveToTrash => 'Переместить в корзину';

  @override
  String get notesMovedToTrash => 'Перемещено в корзину';

  @override
  String get notesRestore => 'Восстановить';

  @override
  String get notesDeleteForever => 'Удалить навсегда';

  @override
  String get notesDeleteForeverConfirm => 'Удалить заметку навсегда?';

  @override
  String get notesTrash => 'Корзина';

  @override
  String get notesTrashEmpty => 'Корзина пуста';

  @override
  String get notesTrashEmptyHint =>
      'Удаленные заметки хранятся здесь и не удаляются автоматически.';

  @override
  String get notesUndo => 'Отменить';

  @override
  String get notesAddTag => 'Добавить тег';

  @override
  String get notesTagPlaceholder => 'Название тега…';

  @override
  String get notesSearchPlaceholder => 'Поиск заметок…';

  @override
  String get notesSearchFieldLabel => 'Искать заметки';

  @override
  String get notesNoResults => 'Нет результатов';

  @override
  String notesNoResultsHint(String query) {
    return 'Заметок по запросу \"$query\" не найдено.\nПопробуйте другой запрос.';
  }

  @override
  String notesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результатов',
      many: '$count результатов',
      few: '$count результата',
      one: '1 результат',
    );
    return '$_temp0';
  }

  @override
  String get notesExport => 'Экспорт';

  @override
  String markdownToolbarBold(String shortcut) {
    return 'Жирный ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'Курсив ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'Заголовок';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'Маркированный список ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'Нумерованный список';

  @override
  String get markdownToolbarQuote => 'Цитата';

  @override
  String get markdownToolbarCode => 'Код';

  @override
  String get findReplaceToggle => 'Найти и заменить в тексте';

  @override
  String get findReplaceFindLabel => 'Найти в тексте';

  @override
  String get findReplaceFindHint => 'Найти…';

  @override
  String get findReplaceReplaceLabel => 'Заменить совпадения на';

  @override
  String get findReplaceReplaceHint => 'Заменить на…';

  @override
  String get findReplaceNext => 'Следующее совпадение';

  @override
  String get findReplacePrevious => 'Предыдущее совпадение';

  @override
  String get findReplaceReplaceAction => 'Заменить это';

  @override
  String get findReplaceReplaceAllAction => 'Заменить все';

  @override
  String get findReplaceClose => 'Закрыть поиск и замену';

  @override
  String get findReplaceNoMatches => 'Нет совпадений';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current из $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'Транскрипции';

  @override
  String get sidePanelSnippetsTitle => 'Сниппеты';

  @override
  String get sidePanelClipboardHistoryTitle => 'История буфера';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Пока ничего не скопировано';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Все, что вы копируете при запущенном WhisPaste, появляется здесь — очищается при перезапуске.';

  @override
  String get sidePanelClose => 'Закрыть панель';

  @override
  String get sidePanelSearchHint => 'Поиск';

  @override
  String get sidePanelSearchFieldLabel => 'Поиск по списку';

  @override
  String get sidePanelNoMatches => 'Нет совпадений';

  @override
  String get sidePanelNoMatchesHint => 'Попробуйте другой запрос.';

  @override
  String get settingsSmartMode => 'Умный режим';

  @override
  String get settingsSmartModeSubtitle =>
      'Локальная очистка, сокращение и перевод текста после диктовки';

  @override
  String get smartModeStandardPreset => 'Стандартный пресет';

  @override
  String get smartModePresetOff => 'Выкл';

  @override
  String get smartModePresetOffDescription =>
      'Без постобработки — надиктованный текст используется в исходном виде.';

  @override
  String get smartModePresetCleanup => 'Очистка';

  @override
  String get smartModePresetCleanupDescription =>
      'Удаляет слова-паразиты и исправляет пунктуацию, не меняя смысл или язык.';

  @override
  String get smartModePresetConcise => 'Краткость';

  @override
  String get smartModePresetConciseDescription =>
      'Сокращает текст, удаляя избыточность, сохраняя все факты, на том же языке.';

  @override
  String get smartModePresetTranslate => 'Перевод';

  @override
  String get smartModePresetTranslateDescription =>
      'Переводит надиктованный текст на выбранный ниже язык.';

  @override
  String get smartModeTargetLanguage => 'Целевой язык';

  @override
  String get smartModeTargetLanguageGerman => 'Немецкий';

  @override
  String get smartModeTargetLanguageEnglish => 'Английский';

  @override
  String get smartModeTargetLanguageSpanish => 'Испанский';

  @override
  String get smartModeTargetLanguageFrench => 'Французский';

  @override
  String get smartModeTargetLanguagePortuguese => 'Португальский';

  @override
  String get smartModeTargetLanguageMandarin => 'Китайский';

  @override
  String get smartModeTargetLanguageRussian => 'Русский';

  @override
  String get smartModeDownload => 'Скачать';

  @override
  String get smartModeDownloadComplete => 'Модель Умного режима готова';

  @override
  String get smartModeRamWarningTitle => 'Мало памяти';

  @override
  String get smartModeRamWarningBody =>
      'Для Умного режима лучше иметь 8 ГБ ОЗУ или больше. Он может работать, но медленно или с ошибками. Все равно скачать?';

  @override
  String get smartModeRamWarningContinue => 'Все равно скачать';

  @override
  String get smartModeRamWarningCancel => 'Отмена';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Работает полностью на устройстве. При активности использует около 4–5 ГБ ОЗУ (в дополнение к диску), которые делятся с моделью распознавания.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Пример: обработка типичной диктовки из 50 слов занимает около 1–6 секунд, в зависимости от устройства.';

  @override
  String get settingsHotkeyActionSmartMode => 'Умный режим';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Горячая клавиша Умного режима';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Начинает запись с фиксированным пресетом, независимо от вашего стандартного. Поддерживает режим удержания.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Пресет';

  @override
  String get settingsSmartModeCurrentHotkey => 'Комбинация';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша Умного режима сейчас не активна.';

  @override
  String get smartModeOnboardingHintTitle => 'Попробуйте Умный режим';

  @override
  String get smartModeOnboardingHintBody =>
      'Умный режим может автоматически очищать, сокращать или переводить текст — прямо на устройстве. Скачайте модель сейчас или настройте позже.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Скачать';

  @override
  String get smartModeOnboardingHintSkipCta => 'Пропустить';

  @override
  String get smartModeUsageHintTitle => 'Попробуйте Умный режим';

  @override
  String get smartModeUsageHintBody =>
      'Умный режим может автоматически очищать, сокращать или переводить текст. Вот что вы только что надиктовали:';

  @override
  String get smartModeUsageHintCta => 'Настроить';

  @override
  String get smartModeUsageHintDismiss => 'Не сейчас';
}
