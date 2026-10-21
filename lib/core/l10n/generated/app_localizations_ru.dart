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
  String get navHistory => 'Записи';

  @override
  String get navNotes => 'Заметки';

  @override
  String get navSettings => 'Настройки';

  @override
  String get navReplacements => 'Словарь';

  @override
  String get navSnippets => 'Сниппеты';

  @override
  String get navAnalytics => 'Статистика';

  @override
  String get navHelp => 'Справка';

  @override
  String get actionOpen => 'Открыть';

  @override
  String actionOpenNamed(String name) {
    return 'Открыть: $name';
  }

  @override
  String get helpTabManual => 'Руководство';

  @override
  String get helpTabIntro => 'Введение';

  @override
  String get helpTabSupport => 'Поддержка';

  @override
  String get helpTabDiagnostics => 'Диагностика';

  @override
  String get manualSearchHint => 'Поиск по руководству';

  @override
  String get manualSearchEmpty => 'Ни одна глава не подходит к запросу.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Найдено $count главы',
      many: 'Найдено $count глав',
      few: 'Найдено $count главы',
      one: 'Найдена 1 глава',
      zero: 'Глав не найдено',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'Отзыв';

  @override
  String get pageHistoryTitle => 'Записи';

  @override
  String get pageSettingsTitle => 'Настройки';

  @override
  String get pageReplacementsTitle => 'Словарь';

  @override
  String get pageAnalyticsTitle => 'Аналитика';

  @override
  String get pageAboutTitle => 'О WhisPaste';

  @override
  String get pageFeedbackTitle => 'Отзыв';

  @override
  String get historyEmpty => 'Записей пока нет';

  @override
  String get historyEmptyHint =>
      'Нажмите кнопку записи или используйте горячую клавишу для начала.';

  @override
  String get historyPrivacyGateTitle => 'Записи скрыты';

  @override
  String get historyPrivacyGateHint =>
      'Транскрипции и аудио только скрыты, а не удалены, пока вы не решите их показать.';

  @override
  String get historyPrivacyGateShow => 'Показать записи';

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
  String historyExportDone(String path) {
    return 'Экспортировано в $path';
  }

  @override
  String get historyExportFailed =>
      'Не удалось экспортировать. Проверьте, доступна ли папка для записи, и повторите попытку.';

  @override
  String get historyCopyAsMarkdown => 'Копировать как Markdown';

  @override
  String get historyDetail => 'Детали';

  @override
  String get historyTags => 'Теги';

  @override
  String get historyDuration => 'Длительность';

  @override
  String get historyModel => 'Модель распознавания речи';

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
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'около $count слов',
      many: 'около $count слов',
      few: 'около $count слова',
      one: 'около $count слово',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'Вид и выбор';

  @override
  String get historyEditing => 'Редактирование';

  @override
  String get historySearchTranscriptions => 'Поиск по записям…';

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
    return 'Записей по запросу \"$query\" не найдено.\nПопробуйте другой поисковый запрос.';
  }

  @override
  String get historyTrashEmpty => 'Корзина пуста';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Элементы окончательно удаляются через $days дня.',
      many: 'Элементы окончательно удаляются через $days дней.',
      few: 'Элементы окончательно удаляются через $days дня.',
      one: 'Элементы окончательно удаляются через $days день.',
      zero: 'Элементы хранятся, пока вы не удалите их окончательно.',
    );
    return 'Здесь будут удаленные транскрипции.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'Очистить корзину';

  @override
  String get historyEmptyTrashConfirm => 'Очистить корзину?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Будут окончательно удалены $count транскрипции. Сохранённые аудиофайлы удаляются не позднее чем через 30 дней после записи. Это действие нельзя отменить.',
      many:
          'Будут окончательно удалены $count транскрипций. Сохранённые аудиофайлы удаляются не позднее чем через 30 дней после записи. Это действие нельзя отменить.',
      few:
          'Будут окончательно удалены $count транскрипции. Сохранённые аудиофайлы удаляются не позднее чем через 30 дней после записи. Это действие нельзя отменить.',
      one:
          'Будет окончательно удалена $count транскрипция. Сохранённый аудиофайл удаляется не позднее чем через 30 дней после записи. Это действие нельзя отменить.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => 'Удалить безвозвратно?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Будут безвозвратно удалены $count транскрипций вместе с сохранёнными аудиофайлами. Это действие нельзя отменить.',
      many:
          'Будут безвозвратно удалены $count транскрипций вместе с сохранёнными аудиофайлами. Это действие нельзя отменить.',
      few:
          'Будут безвозвратно удалены $count транскрипции вместе с сохранёнными аудиофайлами. Это действие нельзя отменить.',
      one:
          'Будет безвозвратно удалена $count транскрипция вместе с сохранённым аудиофайлом. Это действие нельзя отменить.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count транскрипций',
      many: '$count транскрипций',
      few: '$count транскрипции',
      one: '1 транскрипция',
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
  String get historyRestored => 'Восстановлено';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Архивировано расшифровок: $count',
      one: '1 расшифровка архивирована',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'В корзину перемещено расшифровок: $count',
      one: '1 расшифровка перемещена в корзину',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Восстановлено расшифровок: $count',
      one: '1 расшифровка восстановлена',
    );
    return '$_temp0';
  }

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
  String get historyShowAll => 'Показать все';

  @override
  String get historyMoreActions => 'Другие действия';

  @override
  String get historyMdTags => 'Теги';

  @override
  String get historyMdDate => 'Дата';

  @override
  String get historyMdModel => 'Модель';

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
  String get settingsReviewPromptRestore =>
      'Снова показывать напоминание об оценке';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'Вы выбрали «Больше не спрашивать». Если включить, напоминание снова сможет появляться; обычные паузы остаются.';

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
      'Индикатор вычислений в строке состояния';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Показывает, работает ли сейчас процессор или видеокарта.';

  @override
  String get settingsAudio => 'Аудио';

  @override
  String get settingsAudioSubtitle => 'Микрофон и запись';

  @override
  String get settingsMicrophone => 'Микрофон';

  @override
  String get settingsGain => 'Чувствительность микрофона';

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
  String get pushToTalkUnavailableLinuxTooltip =>
      'Ваш рабочий стол здесь не сообщает об отпускании клавиш. Вместо этого назначьте «whispaste --toggle» сочетанию клавиш в настройках системы.';

  @override
  String get settingsExperimentalBadge => 'Экспериментально';

  @override
  String get settingsHoldOrTap => 'Нажатие или удержание';

  @override
  String get settingsHoldOrTapHint =>
      'Короткое нажатие запускает и останавливает запись, удержание записывает до отпускания.';

  @override
  String get settingsSpeechRecognition => 'Распознавание речи';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Качество и сервис распознавания речи';

  @override
  String get settingsService => 'Распознавание выполняется на';

  @override
  String get settingsQuality => 'Скорость и точность';

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
  String get settingsAfterTranscriptionActionLabel => 'После записи';

  @override
  String get settingsAfterTranscriptionClipboard =>
      'Скопировать в буфер обмена';

  @override
  String get settingsAfterTranscriptionPaste => 'Автовставка у курсора';

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
  String pasteFailureGeneric(String paste) {
    return 'Ошибка автоматической вставки. Текст находится в буфере обмена, вставьте его вручную ($paste).';
  }

  @override
  String get pasteFailureOpenSettings => 'Открыть настройки';

  @override
  String get pendingAudioSaveLater =>
      'Запись не удалось сохранить в записях. Аудио сохраняется и будет сохранено снова при следующем запуске WhisPaste.';

  @override
  String get pendingAudioRecovered =>
      'Запись, которую раньше не удалось сохранить, теперь в записях.';

  @override
  String get pasteNotificationNoTargetTitle =>
      'WhisPaste: автовставка пропущена';

  @override
  String get pasteNotificationNoTargetBody =>
      'Целевое приложение не найдено. Сначала переключитесь в нужное приложение, затем начните запись. Текст находится в буфере обмена.';

  @override
  String get pasteNotificationNoTargetTray =>
      'Автовставка: нет целевого приложения';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: нет сигнала с микрофона';

  @override
  String get silentMicrophoneNotificationBody =>
      'Микрофон не передаёт звук. Проверьте выбранный микрофон и не выключен ли он. Запись продолжается.';

  @override
  String get pasteNotificationRestartNeededTitle =>
      'WhisPaste: требуется перезапуск';

  @override
  String get pasteNotificationRestartNeededBody =>
      'Разрешение предоставлено, но WhisPaste всё ещё работает со старым состоянием. Нажмите здесь, чтобы перезапустить WhisPaste.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'Автовставка заблокирована — требуется перезапуск';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: автовставка заблокирована';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'WhisPaste требуется разрешение на вставку текста в другие приложения — в macOS оно называется «Универсальный доступ». Нажмите здесь: WhisPaste удалит возможно устаревшую запись, и macOS запросит разрешение заново.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'WhisPaste требуется разрешение на вставку текста в другие приложения — в macOS оно называется «Универсальный доступ». Нажмите здесь или на значок в трее, чтобы открыть Системные настройки.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'Автовставка заблокирована — откройте Системные настройки';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: автовставка заблокирована';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'Целевое приложение запущено с правами администратора. Чтобы вставлять в него текст, перезапустите WhisPaste тоже от имени администратора.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'Автовставка заблокирована — нужны права администратора';

  @override
  String get pasteNotificationFailedTitle => 'WhisPaste: ошибка автовставки';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'Система заблокировала вставку. Текст находится в буфере обмена. Вставьте его сами сочетанием $paste.';
  }

  @override
  String get pasteNotificationFailedTray => 'Ошибка автовставки';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'WhisPaste пока не может использовать виртуальную клавиатуру /dev/uinput. Текст находится в буфере обмена, вставьте его сочетанием $paste. Нажмите здесь, чтобы настроить.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'Автовставка заблокирована — нужна настройка';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'Автовставка недоступна: в этой системе нет виртуальной клавиатуры, которая для неё нужна. Текст находится в буфере обмена, вставьте его сочетанием $paste. Нажмите здесь, чтобы открыть настройки автовставки.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray => 'Автовставка недоступна';

  @override
  String get pasteCapabilityCheckTitle => 'Минуточку…';

  @override
  String get pasteCapabilityReady => 'Все готово';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Ваш текст появится прямо у курсора.';

  @override
  String get pasteCapabilityPermissionMissing => 'Пока нет разрешения';

  @override
  String get pasteCapabilityUnsupported =>
      'Автовставка недоступна на этой платформе';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'Автовставка сейчас здесь невозможна';

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
  String get pasteStaleEntryGuideTitle => 'Удалите старую запись WhisPaste';

  @override
  String get pasteStaleEntryGuideBody =>
      'macOS всё ещё хранит разрешение на автовставку от предыдущей версии WhisPaste. Эту запись нельзя включить — её нужно один раз удалить:\n\n1. Выберите «WhisPaste» в списке.\n2. Нажмите «−» под списком.\n3. Вернитесь в WhisPaste.\n\nПосле перезапуска macOS спросит снова — просто разрешите.';

  @override
  String get pasteStaleEntryGuideConfirm => 'Открыть Системные настройки';

  @override
  String get pasteStaleEntryRestartTitle => 'Перезапустить WhisPaste';

  @override
  String get pasteStaleEntryRestartBody =>
      'Когда старая запись удалена, перезапустите WhisPaste. macOS снова запросит разрешение — подтвердите его и включите WhisPaste.';

  @override
  String get pasteStaleEntryRestartConfirm => 'Перезапустить WhisPaste';

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
      'WhisPaste вставляет ваш текст прямо в позицию курсора. Для этого macOS требуется один переключатель, который можете включить только вы: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ. Подтвердите, чтобы открыть именно эту страницу. WhisPaste сам заметит ваше разрешение и при необходимости перезапустится.';

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
  String get onboardingPasteSubtitleLinux =>
      'В Linux системный запрос разрешения не появляется. Ниже указано, нужно ли что-то настроить для этого.';

  @override
  String get onboardingPasteChipReady => 'Автовставка готова';

  @override
  String get onboardingPasteChipPending => 'Ожидание доступа для автовставки';

  @override
  String get onboardingPasteChipAction => 'Автовставка: требуется действие';

  @override
  String get onboardingPasteGrantCta => 'Разрешить';

  @override
  String get onboardingPasteSkip => 'Только копировать, без вставки';

  @override
  String get onboardingPasteWhyMac =>
      'Без этого разрешения текст только копируется в буфер. Вставлять придется вручную (⌘V).';

  @override
  String get onboardingPasteWhyWin =>
      'Автовставка сама нажимает Ctrl+V после каждой записи, и текст появляется там, где вы печатаете. Проверено на этом устройстве — включите ниже.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'В программах, запущенных от имени администратора, Автовставка не работает. Текст останется в буфере обмена, и вы вставите его сами сочетанием Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'Автовставка включена';

  @override
  String get onboardingPasteWinOnDetail =>
      'После записи WhisPaste нажмет Ctrl+V, и текст появится на месте курсора. Копия также остается в буфере обмена.';

  @override
  String get onboardingPasteLinuxNative =>
      'Автовставке нужно ваше разрешение на виртуальную клавиатуру (/dev/uinput). С пакетом .deb нажмите «Разрешить (пароль администратора)» и введите пароль администратора, иначе скопируйте команду и выполните её один раз в терминале. Разрешение можно убрать в настройках.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'В версии Flatpak --device=all делает /dev/input/* и /dev/uinput видимыми внутри песочницы. Сам WhisPaste не читает устройства ввода. Если у вашего пользователя есть права на чтение в системе (например, как у члена группы input), приложение могло бы читать нажатия клавиш в других программах. Автовставке также нужен доступ на запись к /dev/uinput в системе: скопируйте команду и выполните её один раз в терминале. Она устанавливает правило udev 71-whispaste-uinput.rules, которое даёт доступ только активному сеансу. Команде нужны права администратора (sudo), и она изменяет систему. Если вы этого не хотите, оставьте автовставку выключенной и вставляйте текст вручную.';

  @override
  String get onboardingPasteLinuxSnap =>
      'В версии Snap выполните это один раз в терминале: sudo snap connect whispaste:uinput. До этого автовставка только копирует текст.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'AppImage нужен доступ к /dev/uinput (виртуальной клавиатуре). Скопируйте команду и выполните её один раз в терминале. Она устанавливает правило udev 71-whispaste-uinput.rules в /etc/udev/rules.d/ и выполняет sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. Правило даёт доступ на запись только активному сеансу. Команде нужны права администратора (sudo), и она изменяет систему. До тех пор автовставка только копирует текст.';

  @override
  String get onboardingPasteWinEnableCta => 'Включить автовставку';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'В программах, запущенных от имени администратора, Автовставка не работает. Текст останется в буфере обмена, и вы вставите его сами сочетанием Ctrl+V.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'Автовставка включена. Пока доступ не настроен, WhisPaste помещает текст в буфер обмена, и вы вставляете его сами сочетанием Ctrl+V.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'Текст попадает в буфер обмена. Вставьте его сочетанием $shortcut.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Поставьте галочку рядом с WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Открыты системные настройки. Найдите WhisPaste и включите.';

  @override
  String get onboardingPasteTestTitle => 'Проверьте автовставку';

  @override
  String get onboardingPasteTestSubtitle =>
      'Нажмите на кнопку. Демо-текст должен появиться в поле ниже.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste печатает за вас.';

  @override
  String get onboardingPasteTestSuccess =>
      'Автовставка работает! Нажмите «Далее».';

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
  String get settingsOverlayModeFloating => 'Плавающий (всегда поверх)';

  @override
  String get settingsOverlayModeOff => 'Выкл.';

  @override
  String get settingsOverlayStartPosition => 'Начальная позиция оверлея';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Где появляется оверлей записи при начале записи';

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
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return 'занято ~$count из $budget';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Если список занимает больше $budget, остальное автоматически не учитывается.';
  }

  @override
  String get settingsPunctuationPriming => 'Стимуляция пунктуации';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Распознавание чаще ставит знаки препинания, если свой словарь не задан. Скорость не меняется.';

  @override
  String get settingsVadEnabled => 'Обрезать тишину';

  @override
  String get settingsVadEnabledSubtitle =>
      'Обрезает долгую тишину и шум в конце записи, чтобы распознавание не придумывало финальную фразу (например, «Спасибо за просмотр»).';

  @override
  String get settingsStripPunctuation => 'Удалять пунктуацию';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Удаляет точки, запятые и другие знаки препинания из каждой транскрипции перед сохранением или вставкой. Числа вроде 3,5 не меняются. Работает одинаково для всех способов распознавания.';

  @override
  String get settingsNumericOnlyMode => 'Только цифры';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Преобразует произнесенные числа в цифры, например \'пять\' в \'5\'.';

  @override
  String get settingsRemoveFillerWords => 'Удалять слова-паразиты';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'Удаляет звуки-заминки вроде «uh», «um» и «äh» перед сохранением или вставкой транскрипции. Только однозначные английские и немецкие паразиты; слова со смыслом не затрагиваются.';

  @override
  String get settingsVoiceLineBreaks => 'Голосовые переносы строк';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'Превращает голосовые команды вроде «новый абзац» и «новая строка» в настоящие переносы строк. Действует для языка транскрипции, а при автоопределении — для всех поддерживаемых языков.';

  @override
  String get settingsSpokenPunctuation => 'Голосовая пунктуация';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'Если вы произносите «запятая» или «точка» как слово внутри фразы, проверьте текст после этого.';

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
  String get settingsFactoryReset => 'Сбросить всё';

  @override
  String get settingsFactoryResetTitle => 'Сброс до заводских настроек';

  @override
  String get settingsFactoryResetMessage =>
      'Немедленно удаляются: транскрипции с их тегами и заметками, сохранённые аудиофайлы, Словарь, Сниппеты, Статистика, ключи API, загруженные модели, журналы и настройки. Приложение вернётся в исходное состояние.\n\nПриложение не может восстановить ничего из этого. Файлы удаляются обычным способом, без перезаписи, поэтому специальные инструменты могут восстановить их части.';

  @override
  String get settingsFactoryResetConfirm => 'Удалить все';

  @override
  String get settingsFactoryResetSuccess =>
      'Приложение было полностью сброшено';

  @override
  String get settingsFactoryResetProgressTitle => 'Сброс WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Остановка модели распознавания речи…';

  @override
  String get settingsFactoryResetPhaseDeletingModels => 'Удаление моделей…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio => 'Удаление записей…';

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
  String settingsFactoryResetFailedMessage(String areas) {
    return 'Сброс не завершён. Затронуто: $areas. Можно повторить попытку.';
  }

  @override
  String get factoryResetAreaDb =>
      'Транскрипции, Заметки, Словарь, Сниппеты и Статистика';

  @override
  String get factoryResetAreaAudio => 'Аудиофайлы';

  @override
  String get factoryResetAreaModels => 'Модели и журналы';

  @override
  String get factoryResetAreaSecure => 'Ключи API';

  @override
  String get factoryResetAreaSettings => 'Настройки';

  @override
  String get factoryResetAreaProcess => 'Фоновый процесс';

  @override
  String get factoryResetRetryAction => 'Повторить';

  @override
  String get factoryResetKeyringHint =>
      'Не удалось удалить ключи API из связки ключей. При необходимости удалите записи, начинающиеся с «wp_», вручную в менеджере паролей системы.';

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
      'Облачный провайдер, который вы использовали, удалён. Распознавание речи теперь работает на этом устройстве.';

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
  String get statusSelectionEdited => 'Выделение отредактировано';

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
  String get unsavedInputTitle => 'Отменить изменения?';

  @override
  String get unsavedInputMessage => 'Введённый текст ещё не сохранён.';

  @override
  String get unsavedInputDiscard => 'Отменить';

  @override
  String get trayUnavailableMinimizedHint =>
      'Значок в трее недоступен. WhisPaste свёрнут и продолжает работу.';

  @override
  String get settingsSaveFailedToast =>
      'Не удалось сохранить настройку. Сохранено прежнее значение.';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionClose => 'Закрыть';

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
  String get analyticsNoRecordingsInPeriod => 'В этом периоде записей нет';

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
  String get analyticsTimeSaved => 'Сэкономлено времени (оценка)';

  @override
  String get analyticsAvgLatency => 'Ср. время до текста';

  @override
  String get analyticsRecordingActivity => 'Активность записей';

  @override
  String get analyticsLast7Days => 'За последние 7 дней';

  @override
  String get analyticsWeekEmpty => 'За последние 7 дней записей не было';

  @override
  String get analyticsModelUsage => 'Использование моделей распознавания речи';

  @override
  String get analyticsNoModelData => 'За этот период данных о моделях пока нет';

  @override
  String get analyticsLoading => 'Загрузка статистики';

  @override
  String get analyticsDurationDistribution => 'Распределение по длительности';

  @override
  String get analyticsCostSavings => 'Затраты и экономия';

  @override
  String get analyticsLocalSavings => 'Локальная экономия';

  @override
  String get analyticsCloudCost => 'Затраты на облако';

  @override
  String get analyticsEstimateNote => 'Оценка по тарифам за каждую расшифровку';

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
  String get analyticsResetDone => 'Статистика сброшена.';

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
  String get replacementsMissingTrigger =>
      'Добавьте хотя бы одну фразу-триггер.';

  @override
  String get replacementsRemoveTrigger => 'Удалить триггер';

  @override
  String get replacementsReplacementLabel => 'Текст замены';

  @override
  String get replacementsMissingReplacement => 'Введите текст замены.';

  @override
  String get replacementsReplacementHint => 'напр. кстати';

  @override
  String get replacementsReplacementHelper =>
      'Используйте \\n для переноса строки и \\n\\n для пустой строки. Чтобы оставить обратный слеш и n как текст, напишите \\\\n.';

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
  String get replacementsLearnedBadge => 'Изучено';

  @override
  String get correctionLearningToggleLabel => 'Учиться на исправлениях';

  @override
  String get correctionLearningToggleEnabled =>
      'Повторяющиеся голосовые исправления проверяются на предложения';

  @override
  String get correctionLearningToggleDisabled =>
      'Голосовые исправления не проверяются на предложения';

  @override
  String get correctionLearningHowTo =>
      'При записи заметки в Записях скажите «correct: …» (или «korrektur: …»), а затем исправленный текст, чтобы перезаписать её. Исправьте одно и то же дважды, и WhisPaste предложит здесь автоматическую замену.';

  @override
  String get correctionCandidatesCardTitle =>
      'Предложено на основе ваших исправлений';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count предложение(я) на основе повторяющихся голосовых исправлений — проверьте перед добавлением.';
  }

  @override
  String get correctionCandidatesReviewButton => 'Проверить';

  @override
  String get correctionCandidatesReviewTitle =>
      'Проверить выученные исправления';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count повторённых исправления',
      many: '$count повторённых исправлений',
      few: '$count повторённых исправления',
      one: '$count повторённое исправление',
    );
    return '$_temp0 — примите те, которые WhisPaste должен впредь применять автоматически. Ничего не изменится, пока вы не подтвердите.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return 'Добавлено $added изученных замен';
  }

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
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'Триггер «$trigger» уже есть (замена: «$replacement»).';
  }

  @override
  String get snippetsSearch => 'Поиск сниппетов…';

  @override
  String get snippetsSearchFieldLabel => 'Искать сниппеты';

  @override
  String get snippetsAdd => 'Добавить';

  @override
  String get snippetCopySuffix => '(копия)';

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
      'Откройте панель сниппетов во время записи, чтобы вставить этот текст.';

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
      'Не все поля добавлены в шаблон — их текст не будет использован.';

  @override
  String get snippetsSaveMissingTitle => 'Не указан заголовок';

  @override
  String get snippetsSaveMissingBody => 'Не указан текст';

  @override
  String get snippetsFieldsDuplicateWarning =>
      'Имена полей должны различаться.';

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
  String get snippetsPickerSettingsLink =>
      'Слово-триггер и горячая клавиша в настройках';

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
      'Локальное распознавание речи: ускорение на GPU, где доступно (Metal, Vulkan, CUDA), иначе на CPU (~25 языков).';

  @override
  String get aboutParakeetModelCredit =>
      'Модель: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'GGUF-конвертация: ggml-org, MIT';

  @override
  String get aboutLinks => 'Ссылки';

  @override
  String get helpLegalTitle => 'Правовая информация';

  @override
  String get helpDiagnosticsPublicNote =>
      'Задачи на GitHub публичны. Проверьте отчёт перед вставкой.';

  @override
  String get helpDiagnosticsBuilding => 'Формируем отчёт …';

  @override
  String get tabsScrollBack => 'Показать предыдущие вкладки';

  @override
  String get tabsScrollForward => 'Показать следующие вкладки';

  @override
  String get aboutWebsite => 'Сайт';

  @override
  String get aboutGitHubRepo => 'Репозиторий GitHub';

  @override
  String get aboutFollowOnX => 'Следить в X';

  @override
  String get aboutMitLicense => 'Лицензия MIT';

  @override
  String get aboutThirdPartyLicenses => 'Сторонние лицензии';

  @override
  String get aboutThirdPartyLicensesDetail => 'Шрифты и модели';

  @override
  String get aboutPrivacyPolicy => 'Политика конфиденциальности';

  @override
  String get aboutImprint => 'Импрессум';

  @override
  String get aboutSystemInfo => 'Информация о системе';

  @override
  String get aboutSystemInfoDesc =>
      'Компактная отладочная информация для отчетов об ошибках.';

  @override
  String get aboutDiagnosticsContentsTitle => 'Что входит в отчёт';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'Версия приложения, операционная система, путь к программе без имени пользователя, модель распознавания речи (вариант, модель, состояние, последняя ошибка), GPU, файлы моделей и последние 40 строк журнала. Ключи и токены в строках журнала скрыты.';

  @override
  String get aboutDiagnosticsPreviewShow => 'Показать';

  @override
  String get aboutDiagnosticsPreviewHide => 'Скрыть';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'Диагностика неполная: $error';
  }

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
  String get feedbackRatingLabel => 'Ваши впечатления от WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Расскажите подробнее';

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
  String feedbackSubmitMissing(String what) {
    return 'Чтобы отправить, $what.';
  }

  @override
  String get feedbackMissingCategory => 'выберите, о чём сообщение';

  @override
  String get feedbackMissingRating => 'оцените, как вам WhisPaste';

  @override
  String get feedbackMissingComment => 'напишите сообщение';

  @override
  String get feedbackMissingEmail =>
      'исправьте адрес почты или оставьте поле пустым';

  @override
  String get feedbackRequiredMarker => 'Обязательно';

  @override
  String get feedbackPublishConsentLabel =>
      'Я разрешаю показать мой отзыв на сайте анонимно, как цитату.';

  @override
  String get feedbackPublishConsentExplanation =>
      'По умолчанию выключено. Показываются только ваш текст и оценка, но не имя и не e-mail. Согласие можно отозвать в любой момент одним нажатием на странице «Отзыв» в приложении.';

  @override
  String get feedbackPublishReviewHint =>
      'Цитаты пишутся как оценка: что понравилось и что ещё можно улучшить. Сообщения об ошибках и пожелания относятся к разделам «Проблема» или «Идея» и никогда не публикуются.';

  @override
  String get feedbackWithdrawConsentLabel => 'Отозвать согласие';

  @override
  String get feedbackWithdrawConsentHelp =>
      'Относится к отзывам, отправленным с согласием с этого устройства. Цитата исчезнет с сайта примерно через 24 часа.';

  @override
  String get feedbackWithdrawConsentPending =>
      'Отзыв сохранён и будет отправлен, когда WhisPaste запустится с подключением к интернету (в течение 30 дней); иначе отзовите по e-mail.';

  @override
  String get feedbackWithdrawNoCode =>
      'На этом устройстве нет кода отзыва – отзовите по e-mail';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'Отзыв от $date отправляется…';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'Отзыв от $date не доставлен – отзовите по e-mail';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'Не удалось доставить отзыв – отзовите по e-mail.';

  @override
  String get feedbackWithdrawEmailLabel => 'Отозвать по e-mail';

  @override
  String get feedbackWithdrawEmailSubject =>
      'Отзыв согласия на цитирование моего отзыва';

  @override
  String get feedbackWithdrawEmailBody =>
      'Пожалуйста, отзовите моё согласие на цитирование моего отзыва.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'Дата отзыва:';

  @override
  String get feedbackWithdrawEmailReferenceLabel => 'Код отзыва:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'Письмо отправлено';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'Почтовая программа не найдена. Отправьте подготовленное сообщение на этот адрес:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'Скопировать адрес и сообщение';

  @override
  String get feedbackWithdrawEmailCopied => 'Адрес и сообщение скопированы.';

  @override
  String get feedbackWithdrawLocked =>
      'Хранилище учётных данных системы сейчас недоступно для чтения. WhisPaste не может отправить сохранённые там согласия и отзывы. Отзовите по e-mail: подготовленное письмо содержит нужные коды.';

  @override
  String get feedbackWithdrawConsentDone =>
      'Отзыв отправлен. Цитата исчезнет с сайта примерно через 24 часа, при следующем ежедневном обновлении.';

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
  String get dockOutputCopy => 'Копировать';

  @override
  String get dockOutputPaste => 'Вставить';

  @override
  String get dockOutputBoth => 'Копировать и вставить';

  @override
  String get dockOutputNothing => 'Вручную';

  @override
  String get sttStatusStarting => 'Запуск…';

  @override
  String get sttStatusReady => 'Готов';

  @override
  String get sttStatusError => 'Ошибка';

  @override
  String get statusBarSttTooltip => 'Статус модели распознавания речи';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Распознавание выполняется на: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'Реальную загрузку GPU нельзя измерить без повышенных прав; показан процент загрузки CPU процессом.';

  @override
  String get statusBarRecording => 'Запись…';

  @override
  String get statusBarTranscribing => 'Обработка…';

  @override
  String get statusBarRefining => 'Обработка…';

  @override
  String get statusBarHotkeyTooltip =>
      'Глобальная горячая клавиша: кликните для настройки';

  @override
  String get statusBarAutoPasteOffHint => 'Включить автовставку…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Автовставка отключена. Кликните, чтобы открыть настройки.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Скрыть';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'Автоматизация: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'Автоматизация: ошибка';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'API автоматизации активен на порту $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'API автоматизации активен на порту $port (порт $requestedPort был занят)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'API автоматизации: не найден свободный порт';

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
  String get modelServerReady => 'Модель распознавания речи готова';

  @override
  String get modelServerMissing => 'Модель распознавания речи не установлена';

  @override
  String get modelServerWhisper => 'Локальная модель распознавания речи';

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
  String get modelDownloadingEngine => 'Подготовка модели распознавания речи…';

  @override
  String get modelVerifying => 'Проверка…';

  @override
  String get modelExtracting => 'Извлечение…';

  @override
  String get modelDeleteConfirm => 'Удалить эту модель распознавания речи?';

  @override
  String get modelDeleteConfirmMessage =>
      'Файл модели распознавания речи удаляется с этого устройства. Вы сможете загрузить его снова в любое время.';

  @override
  String get modelTierDeleteConfirm => 'Удалить эти модели?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count моделей ($size) будут удалены с этого устройства. Их можно загрузить снова в любой момент.',
      many:
          '$count моделей ($size) будут удалены с этого устройства. Их можно загрузить снова в любой момент.',
      few:
          '$count модели ($size) будут удалены с этого устройства. Их можно загрузить снова в любой момент.',
      one:
          'Модель ($size) будет удалена с этого устройства. Её можно загрузить снова в любой момент.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'Быстрый';

  @override
  String get qualityTierCompactDesc =>
      'Быстрые результаты, небольшая загрузка. Отлично подходит для коротких заметок.';

  @override
  String get qualityTierBalancedLabel => 'Сбалансированный';

  @override
  String get qualityTierBalancedDesc =>
      'Точно и надежно для повседневной записи. Работает на большинстве устройств.';

  @override
  String get qualityTierPremiumLabel => 'Точный';

  @override
  String get qualityTierPremiumDesc =>
      'Высочайшая точность для длинных записей. Требует мощного GPU.';

  @override
  String get qualityTierRecommended => 'Рекомендуется для вашего устройства';

  @override
  String get qualityTierRecommendedMeasured => 'Измерено для вашего устройства';

  @override
  String qualityTierDownloadSize(String size) {
    return '$size загрузка';
  }

  @override
  String get qualityTierDownloadAndContinue =>
      'Скачать модель распознавания речи';

  @override
  String get qualityTierChooseDifferent => 'Выбрать другой уровень';

  @override
  String get qualityTierActive => 'Активно';

  @override
  String get qualityTierInfoSlow =>
      'Точный, на этом компьютере обработка заметно дольше';

  @override
  String get qualityTierInfoSlowEstimate =>
      'Точный, вероятно, на этом компьютере заметно дольше (оценка)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Точный, примерно в $ratio раз медленнее, чем Быстрый';
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
  String get benchmarkRowSubtitle =>
      'Измеряет скорость каждого установленного уровня на этом компьютере. Результаты задают подсказки о скорости и рекомендацию.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'Выполняется… шаг $step из $total: $tier';
  }

  @override
  String get benchmarkCancel => 'Отменить тест';

  @override
  String get benchmarkCancelled =>
      'Тест отменён. Уже измеренные уровни сохранены.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'измерено $count уровня',
      many: 'измерено $count уровней',
      few: 'измерено $count уровня',
      one: 'измерен $count уровень',
    );
    return 'Измерение завершено: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'Последнее измерение: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'Способ вычислений: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'Процессор (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'Видеокарта ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds с обработки на каждую секунду аудио';
  }

  @override
  String get benchmarkNoResult =>
      'Измерений пока нет. Запустите тест, чтобы получить подсказки о скорости для этого компьютера.';

  @override
  String get benchmarkStaleNotice =>
      'Результаты получены на другом компьютере или в более ранней версии. Они будут измерены заново в фоновом режиме.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'Замер относится к моделям Whisper. Parakeet не измеряется.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'Рекомендовано после измерения: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'Перейти на $tier';
  }

  @override
  String get benchmarkErrorBusy =>
      'Тест нельзя запустить во время записи. Запустите его позже.';

  @override
  String get benchmarkErrorNoModel =>
      'Ни один уровень не установлен. Сначала скачайте модель распознавания речи.';

  @override
  String get benchmarkErrorFailed => 'Не удалось завершить тест.';

  @override
  String get benchmarkRetry => 'Повторить';

  @override
  String get qualityTierActionOverride => 'Все равно использовать';

  @override
  String get qualityTierActionOverrideHint =>
      'Использовать этот уровень несмотря на предупреждение';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'Базовое';

  @override
  String get settingsQualityBalanced => 'Сбалансированное';

  @override
  String get settingsQualityHigh => 'Высокое качество';

  @override
  String get settingsQualityBest => 'Точный';

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
  String get settingsAdvancedModelManagement =>
      'Расширенные настройки моделей распознавания речи';

  @override
  String get infoEngineDownloading =>
      'Модель распознавания речи подготавливается. Пожалуйста, подождите.';

  @override
  String get infoModelMissing => 'Сначала скачайте модель речи в Настройках.';

  @override
  String infoModelMissingSelected(String size) {
    return 'Выбранная модель речи ($size) ещё не скачана.';
  }

  @override
  String get infoModelMissingDownload => 'Скачать сейчас';

  @override
  String get statusBarModelMissing => 'Модель распознавания речи не скачана';

  @override
  String statusBarModelDownloading(int percent) {
    return 'Загрузка модели распознавания речи… $percent %';
  }

  @override
  String get modelDownloadAction => 'Скачать';

  @override
  String get modelMissingDownloadAction => 'Нет — скачать';

  @override
  String get infoPipelineBusy => 'WhisPaste все еще занят предыдущей записью.';

  @override
  String get infoSnippetPickerEmpty =>
      'Сниппетов пока нет. Создайте один, и откроется выбор.';

  @override
  String get infoSnippetPickerEmptyAction => 'Открыть сниппеты';

  @override
  String get oomRecoveryTitle =>
      'Запись прервана: видеокарте не хватает памяти';

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
      'Использовать облачную модель распознавания речи';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'Тогда записи будут отправляться в $provider.';
  }

  @override
  String get oomRecoveryCancel => 'Отмена';

  @override
  String get oomRecoveryPermanentTitle =>
      'Локальная модель распознавания речи недоступна';

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
      'Переключение на облачную модель распознавания речи…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'Модель $model также завершилась с ошибкой. Пробуем следующий вариант…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'Меньшая модель недоступна. Выберите другую модель в настройках или используйте облачное распознавание речи.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'Качество снижено: нехватка видеопамяти. Переключено на более легкую модель.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Нехватка видеопамяти. Переключено в режим CPU для надежности.';

  @override
  String get errorSttServerConnectionLost =>
      'Модель распознавания речи неожиданно остановилась. Пожалуйста, попробуйте еще раз.';

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
  String get errorCloudTimeoutLocal =>
      'Облачный сервис слишком долго не отвечал. Проверьте подключение или диктуйте без сети локальной моделью.';

  @override
  String get errorCloudTimeout =>
      'Облачный сервис слишком долго не отвечал. Проверьте подключение и попробуйте снова.';

  @override
  String get errorCloudNetworkLocal =>
      'Не удалось подключиться к облачному сервису. Проверьте подключение к интернету или диктуйте без сети локальной моделью.';

  @override
  String get errorCloudNetwork =>
      'Не удалось подключиться к облачному сервису. Проверьте подключение к интернету и попробуйте снова.';

  @override
  String get errorQuickNoteAppendFailed =>
      'Не удалось сохранить быструю заметку, поэтому текст в неё не добавлен. Скопируйте текст и вставьте его в заметку.';

  @override
  String get errorOnboardingNotCompleted =>
      'Пожалуйста, сначала завершите мастер настройки.';

  @override
  String get errorSttModelNotFound =>
      'Модель не найдена. Пожалуйста, скачайте ее в Настройках.';

  @override
  String get errorSttModelLoadFailed =>
      'Не удалось загрузить голосовую модель. Перезапустите WhisPaste. Если ошибка повторяется, скачайте голосовую модель заново в Настройках.';

  @override
  String get errorSttModelFileMissing =>
      'Файл голосовой модели не найден. Скачайте голосовую модель в Настройках.';

  @override
  String get errorSttModelCorrupted =>
      'Файл голосовой модели повреждён. Скачайте голосовую модель заново в Настройках.';

  @override
  String get errorSttEngineRestartNeeded =>
      'Голосовой движок ещё занят предыдущей диктовкой. Перезапустите WhisPaste, чтобы использовать его снова.';

  @override
  String get pendingRetryFailed =>
      'Повторная расшифровка не удалась. Запись сохранена для следующей попытки.';

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
  String get errorSttServerFailed =>
      'Не удалось запустить модель распознавания речи';

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
      'Модель распознавания речи не сработала ни на GPU, ни на CPU. Перезапустите приложение или скачайте модель заново.';

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
      'Модель распознавания речи все еще запускается. Попробуйте чуть позже.';

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
  String get errorNoMicrophone =>
      'Микрофон не найден. Подключите микрофон и попробуйте еще раз.';

  @override
  String get errorGeneric =>
      'Что-то пошло не так. Пожалуйста, попробуйте еще раз.';

  @override
  String get modelDownloadFailed =>
      'Сбой скачивания. Проверьте ваше подключение к интернету.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'Недостаточно места на диске для загрузки: нужно $needed, свободно $free. Загрузка не начата.';
  }

  @override
  String get modelDeleteInUse =>
      'Файл модели распознавания речи используется другой программой и не может быть удален. Закройте ее и попробуйте еще раз.';

  @override
  String get statusSttLoading => 'Загрузка модели распознавания речи…';

  @override
  String get statusSttReady => 'Модель распознавания речи готова';

  @override
  String get modelDownloadFailedChecksum =>
      'Скачанный файл повреждён и был удалён. Скачайте его ещё раз.';

  @override
  String get modelDownloadFailedStorage =>
      'Не удалось сохранить файл. Проверьте, достаточно ли свободного места на диске.';

  @override
  String get modelDownloadFailedUnknown =>
      'Сбой скачивания. Попробуйте ещё раз.';

  @override
  String get onboardingModelDownloadCancel => 'Отменить скачивание';

  @override
  String get onboardingModelDiskSpaceTitle => 'Мало места на диске';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'Модели нужно $needed, а свободно только $free. Скорее всего, скачивание не удастся.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'Всё равно скачать';

  @override
  String get historyDuplicate => 'Дублировать';

  @override
  String get historyDuplicated => 'Запись продублирована';

  @override
  String get historyTakeAsNote => 'Сохранить как заметку';

  @override
  String get historyTakenAsNote => 'Сохранено как заметка';

  @override
  String get historyOpenNote => 'Открыть';

  @override
  String get historyViewRaw => 'Оригинал';

  @override
  String get historyViewEdited => 'Отредактировано';

  @override
  String get historyApplySmartModePreset => 'Применить пресет Smart Mode';

  @override
  String get historySmartModeApplied => 'Smart Mode применен';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode применён';

  @override
  String get smartModeUndoAction => 'Отменить';

  @override
  String get smartModeBusy => 'Smart Mode ещё работает';

  @override
  String get smartModeBusyRetry =>
      'Smart Mode ещё работает – попробуйте снова через секунду';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count имени изменено',
      many: '$count имён изменено',
      few: '$count имени изменено',
      one: '$count имя изменено',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'Оригинал скопирован в буфер обмена – вставьте его: $shortcut. Предыдущее содержимое буфера обмена заменено.';
  }

  @override
  String get selectionUndoUnavailable => 'Отмена сейчас невозможна.';

  @override
  String get smartModeCheckTimedOut =>
      'Проверка заняла слишком много времени – ваш текст не изменился.';

  @override
  String get historySmartModeUndo => 'Отменить Smart Mode';

  @override
  String get historySmartModeRestore => 'Вернуть Smart Mode';

  @override
  String get historySmartModeFailedModelMissing =>
      'Текстовая модель не скачана';

  @override
  String get historySmartModeFailedTimeout =>
      'Время ожидания Smart Mode истекло';

  @override
  String get historySmartModeFailedGeneric =>
      'Сбой Smart Mode — попробуйте еще раз.';

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
      'Подсказка: скажите «tag: имя» или «correct: текст» во время записи.';

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
  String get tagManageEmpty =>
      'Тегов пока нет. Чтобы создать тег, добавьте его к записи.';

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
  String tagRemoveSemanticsLabel(String tag) {
    return 'Удалить тег \"$tag\"';
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
  String get historyShortcutListGroup => 'СПИСОК ЗАПИСЕЙ';

  @override
  String get historyShortcutMoveFocus => 'Выбор записи';

  @override
  String get historyShortcutOpenEntry => 'Открыть запись';

  @override
  String get historyShortcutCopyEntry => 'Копировать запись';

  @override
  String get historyShortcutDeleteEntry => 'Удалить запись';

  @override
  String get historyShortcutSelectAll => 'Выбрать все';

  @override
  String get historyShortcutClearSelection => 'Снять выделение';

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
  String get historyShortcutDiscardEdit => 'Отменить правку';

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
  String get shortcutsGroupDictate => 'Диктовка';

  @override
  String get shortcutsGroupNotes => 'Заметки и сниппеты';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode и редактирование выделения';

  @override
  String get shortcutsAreaIntro =>
      'Эти горячие клавиши работают во всей системе: в любом приложении, даже когда WhisPaste работает в фоне. Каждая комбинация относится только к одной клавише.';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Клавиша для запуска и остановки записи';

  @override
  String get settingsHotkeyEnabled => 'Начать/остановить запись';

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
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'Любая комбинация модификаторов работает: например, $first, $second или $third';
  }

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
  String get settingsQuickNoteHotkeyEnabled => 'Запись быстрой заметки';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'Распознанный текст добавляется к заметке, отмеченной как быстрая. Вы выбираете эту заметку в разделе «Заметки».';

  @override
  String get settingsQuickNoteOpenInMainWindow =>
      'Открывать заметки в главном окне';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'Выкл.: быстрая заметка сохраняется в фоне, а уведомление предлагает «Открыть заметку». Вкл.: главное окно выходит вперёд и показывает заметку.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Текущая комбинация';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша быстрой заметки в данный момент не активна. Выберите другую комбинацию.';

  @override
  String get quickNoteToastSaved => 'Быстрая заметка сохранена';

  @override
  String get quickNoteToastOpenNote => 'Открыть заметку';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Панель сниппетов';

  @override
  String get settingsSnippetPickerHotkeyEnabled => 'Открыть панель сниппетов';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Сразу открывает панель сниппетов — без записи и без произнесения слова-триггера.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Текущая комбинация';

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
      'Выезжающая панель при наведении на выбранный край экрана для транскрипций, сниппетов и истории буфера обмена';

  @override
  String get settingsSidePanelEdge => 'Положение панели';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'К какому краю экрана крепится панель и откуда она выезжает';

  @override
  String get settingsSidePanelEdgeLeft => 'Левый край';

  @override
  String get settingsSidePanelEdgeRight => 'Правый край';

  @override
  String get settingsAppearance => 'Оформление';

  @override
  String get settingsAppearanceSubtitle =>
      'Цвета окон приложения. Панель записи и оверлей остаются тёмными.';

  @override
  String get settingsAppearanceSystem => 'Как в системе';

  @override
  String get settingsAppearanceLight => 'Светлое';

  @override
  String get settingsAppearanceDark => 'Тёмное';

  @override
  String get settingsAppearanceNavy => 'Морской';

  @override
  String get settingsAppearanceCardNavy => 'Морской';

  @override
  String get settingsLanguageDialogSubtitle =>
      'Выберите язык, который WhisPaste ожидает при записи. Если автоопределение включено, он распознаёт язык сам.';

  @override
  String get settingsLanguageSearchHint => 'Поиск языков';

  @override
  String get settingsLanguageSelectedTitle => 'Выбрано';

  @override
  String get settingsLanguageSaveAndClose => 'Сохранить и закрыть';

  @override
  String get settingsLanguageSavePickOne =>
      'Выберите хотя бы один язык, чтобы сохранить.';

  @override
  String get settingsLanguageNoResults => 'Языки не найдены';

  @override
  String get settingsLanguageChange => 'Изменить';

  @override
  String get settingsLanguageCancel => 'Отмена';

  @override
  String get settingsErrorReporting => 'Отчеты об ошибках';

  @override
  String get settingsErrorReportingSubtitle =>
      'Отправляет отчёты о сбоях и ошибках с анонимным ID устройства. Аудио и текст никогда не отправляются.';

  @override
  String get settingsErrorReportingRestartHint =>
      'Вступит в силу после перезапуска WhisPaste.';

  @override
  String get settingsAutoPasteBlocklist => 'Исключения для автовставки';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Приложения, в которых текст только копируется (без автовставки). Если переключатель ниже включён, текст попадает в буфер обмена, иначе только в Записи. Пока список задан, неизвестное приложение считается заблокированным.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'Копировать в буфер обмена при заблокированных приложениях';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'Выкл.: текст сохраняется только в Записях.';

  @override
  String get settingsAutoPasteBlocklistPlaceholderMac =>
      'com.1password.1password, com.apple.Terminal';

  @override
  String get settingsAutoPasteBlocklistPlaceholderWindows =>
      '1password, windowsterminal';

  @override
  String get settingsAutoPasteBlocklistPlaceholderLinux =>
      '1password, gnome-terminal-server';

  @override
  String get settingsAutoPasteBlocklistShortPrefixWarning =>
      'На Mac указывайте идентификаторы пакетов, например com.apple.Terminal. Без точки запись совпадает только с идентичным ID.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'В GNOME (Wayland) WhisPaste определяет целевое приложение только с расширением WhisPaste для GNOME; без него при активном списке текст только копируется';

  @override
  String get settingsLinuxAlwaysShiftPaste =>
      'Всегда вставлять через Ctrl+Shift+V';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'Сочетание из терминалов — и во всех остальных приложениях. Некоторые приложения используют эти клавиши иначе: LibreOffice, например, открывает «Специальная вставка»';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'Здесь WhisPaste определяет целевое приложение и сам вставляет в терминалы через Ctrl+Shift+V';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'В GNOME (Wayland) WhisPaste распознаёт терминалы только с расширением WhisPaste для GNOME. До тех пор включите, если диктуете в основном в терминалы';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'На этом рабочем столе WhisPaste не распознаёт терминалы. Включите, если диктуете в основном в терминалы';

  @override
  String get settingsLinuxPortalInputTitle =>
      'Вставка через разрешение рабочего стола';

  @override
  String get settingsLinuxPortalInputBody =>
      'Без настройки: рабочий стол один раз спросит, может ли WhisPaste отправлять сочетания клавиш. WhisPaste отправляет так только Ctrl+V и Ctrl+C';

  @override
  String get settingsLinuxPortalInputConnect => 'Запросить разрешение';

  @override
  String get settingsLinuxPortalInputRevoke => 'Отозвать разрешение';

  @override
  String get settingsLinuxPortalInputConnected =>
      'Разрешение получено. Теперь WhisPaste может вставлять так';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'Разрешение не дано. Его можно запросить снова в любой момент';

  @override
  String get settingsLinuxPortalInputFailed =>
      'Не удалось запросить разрешение. Попробуйте позже';

  @override
  String get settingsLinuxGnomeExtensionTitle =>
      'Расширение WhisPaste для GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'В GNOME WhisPaste узнаёт активное приложение только с этим расширением — например, для терминалов и списка блокировки. Оно читает только имя приложения, никогда заголовки окон или содержимое';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'Включить расширение';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'Выключить расширение';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'Расширение здесь не установлено. Как его установить, описано в справке';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'Включено. Если WhisPaste ещё не распознаёт приложение, один раз выйдите из сеанса и войдите снова';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'Не удалось включить. В терминале: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'В Wayland WhisPaste не видит активное приложение. Пока есть заблокированные приложения, текст только копируется, а не вставляется.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'Под Wayland WhisPaste не может проверить, переключали ли вы окно во время обработки: текст попадёт в окно, активное в момент вставки';

  @override
  String get settingsPasteBlocklistAdd => 'Добавить приложение';

  @override
  String get settingsPasteBlocklistEmpty =>
      'Ни одно приложение не заблокировано — автовставка работает везде.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'Удалить из списка блокировки: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle =>
      'Добавить приложение в список блокировки';

  @override
  String get settingsPasteBlocklistRecentHeading => 'Недавно диктовали в';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'Пока нет диктовок с распознанным приложением. Введите идентификатор приложения ниже.';

  @override
  String get settingsPasteBlocklistManualHeading =>
      'Ввести идентификатор вручную';

  @override
  String get settingsPasteBlocklistManualAdd => 'Добавить';

  @override
  String get historyAutoPasteOffForApp =>
      'Выключить автовставку в этом приложении';

  @override
  String get settingsPasteClipboardAfter => 'Буфер обмена после вставки';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'Вернуть ли прежнее содержимое буфера обмена после вставки. Если вставку не удалось подтвердить вовремя, транскрипция всегда остаётся в буфере обмена.';

  @override
  String get settingsPasteClipboardAfterKeep => 'Оставить транскрипцию';

  @override
  String get settingsPasteClipboardAfterRestore =>
      'Вернуть скопированное раньше';

  @override
  String get pasteClipboardUnsavedHint =>
      'Не удалось сохранить прежнее содержимое буфера обмена: macOS запретила доступ. Разрешите в Системных настройках → Конфиденциальность и безопасность.';

  @override
  String get pasteClipboardUnsavedAction => 'Открыть Системные настройки';

  @override
  String get settingsCheckUpdates => 'Проверять обновления';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Проверять наличие новых версий при запуске и каждые 24 часа';

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
      'Аудио и текст остаются на устройстве. Анонимная статистика отправляется на собственный сервер в ЕС, отчеты о сбоях — в сервис в ЕС (Sentry). Соответствует GDPR.';

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
  String get onboardingModelTitle => 'Настройка модели распознавания речи';

  @override
  String get onboardingModelSubtitle =>
      'Скачайте голосовую модель для записи офлайн. При локальном распознавании ваш голос остаётся на устройстве.';

  @override
  String get onboardingModelRecommended => 'Рекомендуется';

  @override
  String get onboardingModelChangeLater =>
      'Вы сможете изменить качество позже в Настройках';

  @override
  String get onboardingModelNextBlocked =>
      'Скачайте модель распознавания речи или используйте облачного провайдера с сохранённым API-ключом, чтобы продолжить.';

  @override
  String get onboardingModelDownloading => 'Скачивание…';

  @override
  String get onboardingModelReady => 'Модель распознавания речи готова';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Оптимизированное ускорение GPU недоступно, используется CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'Самый быстрый способ набрать текст на ~25 европейских языках, включая немецкий. Работает на любой технике, с GPU и без.';

  @override
  String get onboardingModelDetectingHardware =>
      'Проверяем ваше оборудование, чтобы подобрать рекомендацию…';

  @override
  String onboardingModelUseCloud(String provider) {
    return 'Использовать $provider';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'Для $provider уже сохранён API-ключ. Его можно использовать вместо локальной модели распознавания речи.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'Для распознавания речи используется $provider. Локальная модель распознавания речи для этого не нужна.';
  }

  @override
  String get onboardingModelUseLocal =>
      'Использовать локальную модель распознавания речи';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

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
  String get onboardingTestRecordingMicBypassConsequence =>
      'Тогда горячая клавиша останется непроверенной, пока вы не воспользуетесь ею в первый раз.';

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
  String get onboardingReadyNoModelTitle =>
      'Пока не хватает модели распознавания речи';

  @override
  String get onboardingReadyNoModelBody =>
      'Без модели распознавания речи или API-ключа WhisPaste ничего не расшифрует. Скачайте модель или сохраните ключ, и всё будет готово.';

  @override
  String get onboardingReadyBackToModel => 'Назад к модели';

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
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'Текст в буфере обмена, нажмите $paste для вставки';
  }

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste сохраняет контекст предыдущей записи до десяти минут. Перед сменой темы небольшая пауза поможет результату оставаться точным.';

  @override
  String get onboardingReadyAutostartToggle => 'Запускать WhisPaste при входе';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Запускается свёрнутым в фоне, готов к сочетанию клавиш';

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
  String get onboardingRevisionNoticeExpand => 'Показать все изменения';

  @override
  String get onboardingRevisionNoticeCollapse => 'Показать меньше';

  @override
  String get onboardingRevisionExit => 'Покинуть введение';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Покинуть введение?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Это руководство по обновлению показывается один раз, пропущенные шаги не будут настроены. Вы можете вернуться к ним на странице «Справка», в разделе «Посмотреть введение». Уже настроенные параметры останутся без изменений.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Покинуть';

  @override
  String get overlayRecording => 'Запись';

  @override
  String get overlayTranscribing => 'Обработка…';

  @override
  String get overlayRefining => 'Улучшение…';

  @override
  String get overlayStarting => 'Запуск…';

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
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey — остановить · $cancelKey — отмена';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return 'Отменить запись? Нажмите $cancelKey ещё раз';
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
  String get overlayMicSignalLost => 'Нет сигнала с микрофона';

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
  String get trayTranscribeFile => 'Транскрибировать файл…';

  @override
  String get trayOpenSidePanel => 'Открыть панель быстрой вставки';

  @override
  String get traySettings => 'Настройки';

  @override
  String get trayQuit => 'Выход';

  @override
  String get trayRecentRecordings => 'Последние записи';

  @override
  String get trayUnlockRecordings => 'Разблокировать записи…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слова',
      many: '$count слов',
      few: '$count слова',
      one: '$count слово',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'Отправить отзыв…';

  @override
  String get quitDuringDictationTitle => 'Запись ещё идёт';

  @override
  String get quitDuringDictationMessage =>
      'Если выйти сейчас, текущая запись или расшифровка будет прервана, и её текст пропадёт.';

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
  String get voiceCorrectionUndone => 'Исправление отменено';

  @override
  String get voiceNoteEmpty => 'Речь не распознана';

  @override
  String get voiceNoteError => 'Сбой голосового примечания';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'Голосовое примечание — скажите «tag: …», чтобы добавить тег, или «correct: …», чтобы заменить эту транскрипцию';

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
  String get updateInstallAfterRecording =>
      'Обновление будет установлено после записи';

  @override
  String get updateInstallerMissing =>
      'Файл установки отсутствует. Проверьте обновления ещё раз.';

  @override
  String get updateInstallFailed =>
      'Не удалось запустить установку. Попробуйте установить обновление ещё раз.';

  @override
  String get updateInstallRetry => 'Установить снова';

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
  String get settingsOverlayColors => 'Цвета оверлея';

  @override
  String get settingsOverlayBackground => 'Фон оверлея и кнопки';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'Относится к оверлею записи и плавающей кнопке.';

  @override
  String get settingsOverlayBackgroundMarine => 'Морской';

  @override
  String get settingsOverlayBackgroundGraphit => 'Графит';

  @override
  String get settingsOverlayBackgroundGletscher => 'Ледник';

  @override
  String get settingsOverlayBackgroundAmber => 'Янтарный';

  @override
  String get settingsOverlayWave => 'Цвет волны для оверлея и кнопки';

  @override
  String get settingsOverlayWaveSubtitle =>
      'Относится к оверлею записи и плавающей кнопке: волна и кольцо записи.';

  @override
  String get settingsOverlayWaveCyan => 'Голубой';

  @override
  String get settingsOverlayWaveViolett => 'Фиолетовый';

  @override
  String get settingsOverlayWaveNeutral => 'Нейтральный';

  @override
  String get settingsOverlayWaveAmber => 'Янтарный';

  @override
  String get settingsOverlayWaveInk => 'Чернильный';

  @override
  String get settingsOverlayWaveCoral => 'Коралловый';

  @override
  String get settingsOverlayWaveMint => 'Мятный';

  @override
  String get settingsOverlayWaveUnavailable => 'На этом фоне плохо видно';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '«$from» на этом фоне плохо видно. Волна переключена на «$to».';
  }

  @override
  String get settingsOverlayLiveTranscript => 'Живая расшифровка';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'Показывать распознанный текст по мере расшифровки вместо только формы волны';

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
  String get buttonContextShowHistory => 'Показать записи';

  @override
  String get buttonContextSettings => 'Настройки';

  @override
  String get buttonContextQuit => 'Выйти из WhisPaste';

  @override
  String get settingsHistory => 'Записи';

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
  String get settingsHistoryHideOnOpen => 'Скрывать записи при открытии';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Показывает кнопку «Показать записи» вместо ваших транскрипций при каждом запуске WhisPaste или повторном открытии окна. Ничего не удаляется.';

  @override
  String get historyPinGateTitle => 'Записи заблокированы';

  @override
  String get historyPinGateHint =>
      'Введите PIN-код, чтобы показать ваши расшифровки.';

  @override
  String get historyImportUnlockHint =>
      'Разблокируйте раздел «Записи», чтобы транскрибировать файл.';

  @override
  String get historyPinUnlock => 'Разблокировать';

  @override
  String get historyPinDialogTitle => 'Введите PIN-код';

  @override
  String get historyPinDialogSubtitle => 'Ваши записи защищены PIN-кодом.';

  @override
  String get historyPinFieldHint => 'PIN-код';

  @override
  String get historyPinRepeatHint => 'Повторите PIN-код';

  @override
  String get historyPinWrong => 'Неверный PIN-код.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'Слишком много попыток. Повторите через $seconds с.';
  }

  @override
  String get historyPinForgot => 'Забыли PIN-код?';

  @override
  String get historyPinForgotHint =>
      'Сброс сразу удаляет все записи, сохранённые аудиофайлы, заметки с версиями и изображения заметок. Если файл не удалось удалить, WhisPaste покажет уведомление.';

  @override
  String get historyPinForgotConfirmTitle =>
      'Удалить записи и заметки и снять PIN-код?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Забытый PIN-код восстановить нельзя. Для сброса сразу и безвозвратно удаляются все записи и сохранённые аудиофайлы (включая архив и корзину), все заметки с версиями (включая корзину) и все изображения заметок. Настройки, текстовые блоки и замены сохраняются. Если файл не удалось удалить, WhisPaste покажет уведомление.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'Некоторые записи, импорты или изображения заметок не удалось удалить. WhisPaste удалит их при следующем запуске.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'Некоторые записи или импорты не удалось удалить, и WhisPaste не может повторить попытку позже. Удалите их вручную. Расположение: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'Не удалось удалить копию старой базы данных ($path). Удалите её вручную.';
  }

  @override
  String get historyPinForgotConfirmAction => 'Удалить';

  @override
  String get historyPinSetTitle => 'Задать PIN-код';

  @override
  String get historyPinSetSubtitle =>
      '4–8 цифр. Не даёт другим просто так просматривать ваши транскрипции на этом компьютере, но не шифрует их.';

  @override
  String get historyPinInvalid => 'Используйте от 4 до 8 цифр.';

  @override
  String get historyPinMismatch => 'PIN-коды не совпадают.';

  @override
  String get settingsHistoryPin => 'Защита PIN-кодом';

  @override
  String get settingsHistoryPinSubtitle =>
      'Требовать PIN-код для показа записей и заметок, включая боковую панель, меню плавающей кнопки и API автоматизации.';

  @override
  String get settingsHistoryPinChange => 'Изменить';

  @override
  String get settingsHistoryPinRemove => 'Удалить';

  @override
  String get settingsHistoryAutoLock => 'Блокировать автоматически';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Снова скрывать записи после такого периода бездействия.';

  @override
  String get settingsHistoryAutoLockNever => 'Никогда';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Через $minutes мин';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'Включите плавающую кнопку, чтобы изменить это.';

  @override
  String get settingsFloatingButtonSection => 'Плавающая кнопка';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Всегда видимая поверх окон кнопка для быстрого доступа';

  @override
  String get settingsFloatingButtonWaylandTitle => 'Ограничения Wayland';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'В Wayland рабочий стол сам решает, где появится кнопка и останется ли она поверх окон. WhisPaste может гарантировать это только в ограниченной степени. Запись по нажатию работает как обычно, а кнопка не забирает фокус клавиатуры.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'Недоступно на этом рабочем столе Linux: кнопке нужен X11 или XWayland. Выключить её всё равно можно.';

  @override
  String get settingsSttIdleTimeout =>
      'Время простоя модели распознавания речи';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Как долго модель распознавания речи остается загруженной после использования';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Не выгружать';

  @override
  String get settingsSttKeepLoaded => 'Держать модель загруженной';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'Загруженная модель начинает диктовку без ожидания загрузки. Пока она загружена, она занимает память.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'В загруженном состоянии модель занимает около $size памяти.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'Памяти видеокарты ($vramMb МБ) недостаточно для этой модели ($requiredMb МБ). Модель работает на процессоре.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'Всегда';

  @override
  String get settingsSttKeepLoadedAutomatic => 'Автоматически';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'После простоя';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'Выгружать через';

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
  String get reviewPromptStarGitHub => 'Поставить звезду на GitHub';

  @override
  String get reviewPromptRateStore => 'Оценить в магазине';

  @override
  String get reviewSupportEntry => 'Оценить и поддержать WhisPaste';

  @override
  String get reviewSupportLabel => 'Оценить приложение';

  @override
  String get reviewSupportAction => 'Оценить';

  @override
  String get reviewSupportGitHubLabel =>
      'Поддержите WhisPaste звездой на GitHub';

  @override
  String get reviewSupportGitHubAction => 'Открыть на GitHub';

  @override
  String get githubInviteTitle => 'WhisPaste — открытое ПО';

  @override
  String get githubInviteBody => 'Звезда на GitHub помогает другим его найти.';

  @override
  String get githubInviteOpen => 'Открыть на GitHub';

  @override
  String get githubInviteLater => 'Позже';

  @override
  String get githubInviteNever => 'Больше не спрашивать';

  @override
  String get ideasBoardLabel => 'Идеи и пожелания';

  @override
  String get ideasBoardAction => 'Открыть доску';

  @override
  String get feedbackIdeasLink => 'Предложить идею и проголосовать';

  @override
  String get feedbackTypeProblem => 'Проблема';

  @override
  String get feedbackTypeIdea => 'Идея';

  @override
  String get feedbackTypePraise => 'Похвала';

  @override
  String get feedbackTypeQuestion => 'Вопрос';

  @override
  String get feedbackPromptProblem =>
      'Что пошло не так? Расскажите, что вы сделали и что произошло.';

  @override
  String get feedbackPromptIdea => 'Что сделало бы WhisPaste лучше для вас?';

  @override
  String get feedbackPromptPraise => 'Что у вас хорошо работает?';

  @override
  String get feedbackPromptQuestion => 'Что вы хотели бы узнать?';

  @override
  String get feedbackDiagnosticsLabel => 'Прикрепить диагностику';

  @override
  String get feedbackDiagnosticsExplanation =>
      'Добавляет версию приложения, операционную систему, движок распознавания речи и бэкенд. Диктовки и тексты никогда не прикрепляются.';

  @override
  String get feedbackDiagnosticsPreview => 'Показать предпросмотр';

  @override
  String get feedbackDiagnosticsPreviewHide => 'Скрыть предпросмотр';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'Этот точный текст будет добавлен к вашему сообщению:';

  @override
  String get feedbackIdeaBoardHint =>
      'Идею можно также разместить на публичной доске идей и голосовать за идеи других.';

  @override
  String get feedbackTextTooLong =>
      'Текст слишком длинный для диагностики. Немного сократите его.';

  @override
  String get hotkeyRegistrationFailed =>
      'Сбой регистрации горячей клавиши, пожалуйста, переназначьте ее в Настройках.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken уже занято другим приложением. Пока вы не выберете другое сочетание, запись запускает $active.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'Горячая клавиша для «$action» занята другим приложением. Она будет отключена, пока вы не выберете свободную комбинацию в настройках.';
  }

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
      'Модель распознавания речи не может запуститься. Перезапустите приложение или скачайте модель заново.';

  @override
  String get recoveryExhaustedAction => 'Открыть настройки';

  @override
  String get recoveryVcRuntimeToast =>
      'Модель распознавания речи не может запуститься: отсутствует компонент Windows (Microsoft Visual C++). Пожалуйста, установите Visual C++ Redistributable (x64) и перезапустите WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Установить';

  @override
  String get modelAbiInfoToast =>
      'Перезагрузка голосовой модели, пожалуйста, подождите.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste работает без ускорения GPU из-за проблемы при прошлом запуске. Запись работает как обычно.';

  @override
  String get serverDownloadFailedToast =>
      'Не удалось скачать модель распознавания речи. Проверьте интернет-соединение.';

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
      'Автоматический режим использует видеокарту, если она доступна. «Только CPU» медленнее, но работает на любом устройстве. Принудительный GPU — только если автоматический режим не работает.';

  @override
  String get settingsGpuAccelerationAuto => 'Автоматически (рекомендуется)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (принудительно)';

  @override
  String get settingsGpuAccelerationDisabled => 'Только CPU';

  @override
  String get settingsSttEngine => 'Модель распознавания речи';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 языков. Parakeet: быстрее, около 25 языков.';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet';

  @override
  String get settingsSttEngineRecommended => 'Рекомендуется';

  @override
  String get parakeetModelTitle => 'Модель Parakeet';

  @override
  String parakeetModelSubtitle(String size) {
    return 'Единоразовая загрузка ($size), работает полностью офлайн';
  }

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
      'Анонимные счётчики использования, без cookie и без привязки к вам. Помогают понять, какими функциями пользуются. Ваш текст и аудио никогда не передаются.';

  @override
  String get settingsRetainRecentAudio => 'Сохранять аудио недавних записей';

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'Сохраняет аудио ваших последних $count записей на устройстве для отладки или восстановления транскрипции; записи и импортированные файлы удаляются автоматически не позже чем через $days дн.';
  }

  @override
  String get pendingAudioRetentionNote =>
      'Запись, расшифровка которой не удалась, хранит аудио до 24 часов, чтобы можно было повторить попытку, даже если эта опция выключена.';

  @override
  String get pendingAudioSectionTitle => 'Записи, ожидающие повторной попытки';

  @override
  String get pendingAudioSectionBody =>
      'Эти записи не удалось расшифровать, например из-за обрыва соединения. Аудио удаляется не позднее чем через 24 часа или когда вы его отбрасываете.';

  @override
  String get pendingAudioEmpty => 'Нет записей, ожидающих повтора.';

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
      'Сниппеты с пропусками: WhisPaste проведёт вас по каждому полю. Произнесите текст, нажмите Enter, чтобы перейти к следующему, и готовый текст вставится целиком.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Очищайте, сокращайте или переводите текст перед вставкой — полностью на устройстве, с собственными горячей клавишей, пресетом и целевым языком.';

  @override
  String get featureSpotlightHistoryPinTitle => 'PIN-код для записей';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'Защитите свои транскрипции PIN-кодом — в том числе в боковой панели и меню плавающей кнопки, — с автоблокировкой после бездействия. Настройки → Записи.';

  @override
  String get featureSpotlightEditSelectionTitle =>
      'Редактирование выделенного текста голосом';

  @override
  String get featureSpotlightEditSelectionDescription =>
      'Выделите текст в любом приложении, нажмите горячую клавишу редактирования выделения и скажите, что изменить, — или просто «короче», «улучши» или «переведи». Использует текстовую модель Smart Mode. По умолчанию выключено: включите в Настройки → Smart Mode.';

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
  String get sidePanelClipboardLockedTitle => 'Заблокировано PIN-кодом';

  @override
  String get sidePanelClipboardLockedHint =>
      'Скопированный текст скрыт, пока записи заблокированы. Разблокируйте их PIN-кодом, чтобы снова его увидеть.';

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
  String get sidePanelLoadFailedHint =>
      'Закройте панель и откройте её снова, чтобы повторить попытку.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Локальная очистка, сокращение и перевод текста после записи';

  @override
  String get smartModeStandardPreset => 'Стандартный пресет';

  @override
  String get smartModePresetOff => 'Выкл';

  @override
  String get smartModePresetOffDescription =>
      'Без постобработки — распознанный текст используется в исходном виде.';

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
      'Переводит распознанный текст на выбранный ниже язык.';

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
  String get smartModeDownloadComplete => 'Текстовая модель готова';

  @override
  String get smartModeRamWarningTitle => 'Мало памяти';

  @override
  String get smartModeRamWarningBody =>
      'Локальная текстовая модель Smart Mode лучше работает с 8 ГБ ОЗУ или больше. Она может работать, но медленно или с ошибками. Все равно скачать?';

  @override
  String get smartModeRamWarningContinue => 'Все равно скачать';

  @override
  String get smartModeRamWarningCancel => 'Отмена';

  @override
  String get smartModeModelDeleteConfirm => 'Удалить эту текстовую модель?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'Файл текстовой модели удаляется с этого устройства. Вы сможете загрузить его снова в любое время.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Работает полностью на устройстве. При активности текстовая модель использует около 4–5 ГБ ОЗУ (в дополнение к диску), которые делятся с моделью распознавания речи, поэтому общий расход памяти зависит и от того, какая модель распознавания речи загружена.';

  @override
  String get smartModeFactGuardHint =>
      'Страж фактов проверяет числа, даты, ссылки, адреса электронной почты и IBAN. Имена из словаря сохраняются. Свободные инструкции могут изменить имена, которых нет в словаре; добавьте их в словарь, если они должны сохраниться.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Пример: обработка типичной записи из 50 слов занимает около 1–6 секунд, в зависимости от устройства.';

  @override
  String get smartModeLocalUnavailable =>
      'Локальный Smart Mode не входит в эту сборку. Переключитесь на OpenAI или установите официальный релиз WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Запись с Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Начинает запись с фиксированным пресетом, независимо от стандартного пресета в Smart Mode. «Удерживать для записи» действует и здесь.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Пресет';

  @override
  String get settingsSmartModeCurrentHotkey => 'Текущая комбинация';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Эта комбинация уже используется для \"$action\". Выберите другую.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша Smart Mode сейчас не активна. Выберите другое сочетание клавиш.';

  @override
  String get smartModeOnboardingHintTitle => 'Попробуйте Smart Mode';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'Smart Mode может автоматически очищать, сокращать или переводить текст — прямо на устройстве. Локальная текстовая модель занимает $size на диске. Загрузите её сейчас или настройте позже в настройках.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Сырой текст';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'так э встречу с клиентом перенесли на четверг на три часа дня и ну нам всё ещё нужны обновлённые слайды от маркетинга';

  @override
  String get smartModeOnboardingHintExampleAfterLabel => 'Результат Smart Mode';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'Итак, встречу с клиентом перенесли на четверг на три часа дня, и нам всё ещё нужны обновлённые слайды от маркетинга.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Скачать';

  @override
  String get smartModeOnboardingHintSkipCta => 'Позже';

  @override
  String get smartModeUsageHintTitle =>
      'Попробуйте Smart Mode в следующей записи';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode может автоматически очищать, сокращать или переводить такой текст прямо на вашем устройстве. Вот что вы только что сказали:';

  @override
  String get smartModeUsageHintCta => 'Настроить';

  @override
  String get smartModeUsageHintDismiss => 'Не сейчас';

  @override
  String get settingsAutomationApi => 'Локальный API автоматизации';

  @override
  String get settingsAutomationApiSubtitle =>
      'Другие программы и скрипты на этом компьютере могут управлять WhisPaste, например запускать запись. Устройства в вашей сети до него не достучатся.';

  @override
  String get settingsAutomationApiEnable =>
      'Включить локальный API автоматизации';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'Слушает только 127.0.0.1/::1 — из сети никогда не доступен';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'Работает на порту $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'Работает на порту $port (порт $requestedPort был занят)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'Не запущен';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'Не найден свободный порт в диапазоне $start–$end';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'Свой порт';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'Оставьте пустым для автоматического выбора — если порт занят, будет выбран другой';

  @override
  String get settingsAutomationApiCustomPortHint => 'Автоматически';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'Введите порт от 1024 до 65535';

  @override
  String get settingsAutomationApiToken => 'Bearer-токен';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'Передавайте его как \"Authorization: Bearer <token>\" — любой запрос без него отклоняется';

  @override
  String get settingsAutomationApiRegenerate => 'Сгенерировать заново';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle =>
      'Сгенерировать новый токен?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'Текущий токен сразу перестанет работать. Всем скриптам, которые его используют, понадобится новый.';

  @override
  String get settingsAutomationApiCopyToken => 'Копировать токен';

  @override
  String get settingsAutomationApiTokenCopied =>
      'Токен скопирован в буфер обмена';

  @override
  String get settingsAutomationApiDocumentation => 'Документация';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'Справочник по эндпоинтам и примеры curl';

  @override
  String get settingsAutomationApiDocumentationAction => 'Открыть';

  @override
  String historyCharacterCount(int count) {
    return '$count символов';
  }

  @override
  String historyPastedInto(String app) {
    return 'Вставлено в $app';
  }

  @override
  String get historyShowOriginalTranscript => 'Показать оригинальный текст';

  @override
  String get historyHideOriginalTranscript => 'Скрыть оригинальный текст';

  @override
  String get historyOriginalTranscriptLabel => 'Оригинальный текст';

  @override
  String get settingsHotkeyActionSelectionEdit => 'Редактирование выделения';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'Редактирование выделения';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Выделите текст в любом приложении, нажмите эту горячую клавишу и скажите, что изменить, — или просто «короче», «улучши» или «переведи». Результат заменит выделение; отмена в приложении вернёт оригинал. Использует текстовую модель, настроенную в Smart Mode.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'Эту комбинацию не удалось зарегистрировать — горячая клавиша редактирования выделения сейчас не активна.';

  @override
  String get overlayTargetSelectionEdit => 'Выделение';

  @override
  String get overlayRecordingSelectionEdit => 'Скажите, что изменить';

  @override
  String get overlaySelectionEditHint =>
      'Скажите, что изменить, — или: короче · улучши · переведи';

  @override
  String get overlayEditingSelection => 'Редактирую выделение…';

  @override
  String get overlayDoneSelectionEdit => 'Выделение заменено';

  @override
  String get errorSelectionEditNoSelection =>
      'Текст не выделен — сначала выделите текст, затем нажмите горячую клавишу';

  @override
  String get errorSelectionEditNoEngine =>
      'Чтобы редактировать выделение, сначала настройте Smart Mode (загрузите локальную текстовую модель или добавьте ключ OpenAI)';

  @override
  String get errorSelectionEditUnsupported =>
      'Для редактирования выделения нужна автовставка, которая недоступна в этой сборке';

  @override
  String get errorSelectionEditCopyFailed =>
      'Не удалось прочитать выделение — проверьте разрешение на автовставку';

  @override
  String get errorSelectionEditFailed =>
      'Не удалось отредактировать — ваш текст не изменён';

  @override
  String get errorSelectionEditFactsChanged =>
      'Правка изменила бы факты, которых нет в вашей инструкции — ваш текст не изменён';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'Правка изменила бы «$value», которое ваша инструкция не называет. Укажите старое и новое значение, например «замени 3 на 5»; ваш текст не изменён';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'Не удалось заменить выделение — ваш текст не изменён';

  @override
  String get settingsCudaPackTitle => 'Ускорение NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Более быстрое распознавание на видеокартах GeForce RTX и GTX 16. Однократная загрузка, $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Установлено. Если драйвер видеокарты слишком старый, WhisPaste продолжит использовать Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'Требуется согласие';

  @override
  String get settingsCudaPackConsentReview => 'Посмотреть лицензию';

  @override
  String get settingsCudaPackDownload => 'Загрузить';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'Загрузка: $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'Установка …';

  @override
  String get settingsCudaPackCancel => 'Отменить загрузку';

  @override
  String get settingsCudaPackRemove => 'Удалить пакет CUDA';

  @override
  String get settingsCudaPackRemoveConfirm => 'Удалить пакет CUDA?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'Пакет CUDA будет удалён с этого устройства. Его можно загрузить снова в любой момент.';

  @override
  String get settingsCudaPackToggle => 'Использовать CUDA';

  @override
  String get settingsCudaPackErrorNetwork =>
      'Не удалось загрузить. Проверьте подключение и попробуйте снова.';

  @override
  String get settingsCudaPackErrorVerification =>
      'Загруженный файл повреждён. Попробуйте ещё раз.';

  @override
  String get settingsCudaPackErrorStorage =>
      'Не удалось сохранить пакет. Проверьте свободное место на диске.';

  @override
  String get cudaEulaDialogTitle => 'Лицензия NVIDIA CUDA';

  @override
  String cudaEulaDialogBody(String version) {
    return 'Пакет CUDA содержит компоненты NVIDIA по Лицензионному соглашению конечного пользователя NVIDIA CUDA ($version). Вы соглашаетесь с полным текстом этой версии, его можно открыть через «Полный текст». Другая версия на сайте NVIDIA может отличаться. Для загрузки его нужно принять.';
  }

  @override
  String get cudaEulaDialogLink => 'Другая версия на сайте NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'Полный текст';

  @override
  String get cudaEulaFullTextClose => 'Закрыть';

  @override
  String get cudaEulaDialogCancel => 'Отмена';

  @override
  String get cudaEulaDialogAccept => 'Принять и загрузить';

  @override
  String get recoveryCudaDisabledToast =>
      'Ускорение CUDA отключено из-за проблемы при последнем запуске. WhisPaste теперь использует Vulkan, запись работает как обычно.';

  @override
  String get recoveryGpuProbeFailedToast =>
      'Ускорение на видеокарте в этом сеансе не используется: проверка видеокарты не завершилась. WhisPaste распознаёт речь на процессоре. Запись работает как обычно.';

  @override
  String get settingsGpuProbeTitle => 'Проверка GPU';

  @override
  String get settingsGpuProbeNotChecked =>
      'Ещё не проверялась. Проверка выполнится при первой загрузке модели.';

  @override
  String get settingsGpuProbeUsable => 'Проверена: используется видеокарта.';

  @override
  String get settingsGpuProbeUnusable =>
      'Не работает: WhisPaste использует процессор. Проверьте снова после обновления драйвера или приложения.';

  @override
  String get settingsGpuProbeRetry => 'Проверить снова';

  @override
  String get supportPromptSnooze => 'Не спрашивать 90 дней';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'Спасибо, что купили WhisPaste в магазине. Любая дополнительная поддержка добровольна.';

  @override
  String get supportShareText =>
      'Я использую WhisPaste, чтобы вводить текст голосом прямо в приложения. Работает локально на компьютере и с открытым кодом:';

  @override
  String get supportPageTitle => 'Поддержать WhisPaste';

  @override
  String get supportIntroDirect =>
      'WhisPaste бесплатный и с открытым исходным кодом. Вклад или рекомендация помогают проекту.';

  @override
  String get supportCostsNote =>
      'Взносы помогают покрывать разработку и текущие расходы на публикацию, хостинг и домен.';

  @override
  String get supportSectionOnce => 'Разовая поддержка';

  @override
  String get supportSectionOthers => 'Другие способы поддержки';

  @override
  String get supportSectionReach => 'Рекомендовать WhisPaste';

  @override
  String get supportStoreTitleWindows => 'WhisPaste в Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste в Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'Установку и обновления выполняет магазин.';

  @override
  String get supportStoreFactPurchase =>
      'Ваша разовая покупка поддерживает WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'Те же функции. Прямая версия остаётся бесплатной.';

  @override
  String get supportStoreCtaWindows => 'Открыть в Microsoft Store';

  @override
  String get supportStoreCtaMac => 'Открыть в Mac App Store';

  @override
  String get supportStorePriceNote => 'Цена в магазине';

  @override
  String get supportStoreCoffeeNote =>
      'Разовая покупка примерно за цену чашки кофе. Актуальную цену показывает магазин.';

  @override
  String get supportStoreDismiss => 'Скрыть вариант с магазином';

  @override
  String get supportStoreShowAgain => 'Показать вариант с магазином';

  @override
  String get supportSponsorsCta => 'Открыть GitHub Sponsors';

  @override
  String get supportSponsorsNote =>
      'Ежемесячно или на сумму по вашему выбору. Сумму и периодичность выбираете там.';

  @override
  String get supportKofiCta => 'Открыть Ko-fi';

  @override
  String get supportPayPalCta => 'Поддержать через PayPal';

  @override
  String get supportNativeTitle => 'Разовая поддержка в магазине';

  @override
  String get supportNativeDescription =>
      'Разовая сумма, которую списывает магазин. Те же функции, без подписки.';

  @override
  String get supportNativeCta => 'Поддержать один раз';

  @override
  String get supportSheetChoose => 'Выберите сумму';

  @override
  String get supportSheetLoading => 'Загружаем суммы …';

  @override
  String supportSheetBuy(String price) {
    return 'Поддержать за $price';
  }

  @override
  String get supportSheetPurchasing => 'Магазин подтверждает покупку …';

  @override
  String get supportSheetThanks => 'Спасибо за поддержку!';

  @override
  String get supportSheetThanksDetail =>
      'Значок поддержки уже активен. Все функции остаются доступны всем.';

  @override
  String get supportSheetPending => 'Покупка ожидает подтверждения.';

  @override
  String get supportSheetPurchaseError =>
      'Не удалось завершить покупку. Попробуйте позже.';

  @override
  String get supportSheetPricesError =>
      'Не удалось загрузить суммы. Попробуйте позже.';

  @override
  String get supportSheetUnavailable => 'Сейчас в магазине нет доступных сумм.';

  @override
  String get supportSheetRetry => 'Повторить';

  @override
  String get supportSheetClose => 'Закрыть';

  @override
  String get supportSelfDeclareCta => 'Я уже поддерживаю WhisPaste';

  @override
  String get supportSelfDeclareNote =>
      'Просто отметка на этом устройстве, ничего не проверяется. Кнопка поддержки в строке состояния скрывается.';

  @override
  String get supportSelfDeclareHint =>
      'Ничего не проверяется. Используйте, если вы уже вносили вклад.';

  @override
  String get supportSupporterLine => 'Вы поддерживаете WhisPaste. Спасибо!';

  @override
  String get supportSupporterBadge => 'Сторонник';

  @override
  String get supportRateCta => 'Оценить в магазине';

  @override
  String get supportShareCopy => 'Копировать ссылку';

  @override
  String get supportShareCopied => 'Ссылка скопирована';

  @override
  String get externalLinkOpenFailed => 'Не удалось открыть ссылку';

  @override
  String get externalLinkCopyAddress => 'Копировать адрес';

  @override
  String get supportShareEmail => 'Эл. почта';

  @override
  String get supportChipLabel => 'Спонсор';

  @override
  String get supportChipTooltip => 'Поддержать WhisPaste';

  @override
  String get supportChipThanksLabel => 'Спасибо';

  @override
  String get supportChipThanksTooltip => 'Спасибо за поддержку';

  @override
  String get settingsSponsorChip => 'Кнопка поддержки в строке состояния';

  @override
  String get settingsSponsorChipSubtitle =>
      'Показывает путь к странице поддержки. Его можно скрыть в любой момент и снова показать здесь.';

  @override
  String get automationPreviewTitle => 'Вставить многострочный текст?';

  @override
  String get automationPreviewBody =>
      'Автоматизация хочет вставить текст с переносами строк. Проверьте его, прежде чем он попадёт в активное приложение.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count строки',
      many: '$count строк',
      few: '$count строки',
      one: '1 строка',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'Вставить';

  @override
  String get automationPreviewCancel => 'Отмена';

  @override
  String get automationIntegrationsHeading => 'Интеграции';

  @override
  String get automationIntegrationsHooksTitle =>
      'Отправка событий в другие приложения';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'Отправляет готовые расшифровки и изменённые заметки приложению на этом компьютере. Хуки срабатывают, даже если сервер API выключен.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хука',
      many: '$count хуков',
      few: '$count хука',
      one: '1 хук',
      zero: 'Нет хуков',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'Настроить';

  @override
  String get automationIntegrationsCliTitle => 'Командная строка и MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'Только из исходного кода. Запустите $path с заданным $token; команда $command запускает сервер MCP.';
  }

  @override
  String get automationHooksIntro =>
      'Готовые тексты и изменённые заметки отправляются в приложение на этом компьютере. Адрес должен быть на этом устройстве.';

  @override
  String get automationHooksEmpty => 'Подключение пока не настроено.';

  @override
  String get automationHooksUrlLabel =>
      'Адрес назначения (только этот компьютер)';

  @override
  String get automationHooksEventsLabel => 'События';

  @override
  String get automationHooksEventTranscript => 'Расшифровка готова';

  @override
  String get automationHooksEventNote => 'Заметка изменена';

  @override
  String get automationHooksAdd => 'Добавить хук';

  @override
  String get automationHooksRemove => 'Удалить хук';

  @override
  String get automationHooksRemoveConfirm => 'Удалить этот хук?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'Хук будет удалён из списка. Его можно добавить снова позже.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'Используйте $ipv4, $ipv6 или $localhost с портом, например $example.';
  }

  @override
  String get automationHooksNoEvents => 'Выберите хотя бы одно событие.';

  @override
  String automationHooksTooMany(int max) {
    return 'Можно добавить не более $max хуков.';
  }

  @override
  String get automationHooksDone => 'Готово';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'Диктовка';

  @override
  String get dockOverflow => 'Ещё';

  @override
  String get dockMenuGroupStatus => 'Статус';

  @override
  String get dockMenuGroupNotices => 'Уведомления';

  @override
  String get dockMenuHotkeyChange => 'Изменить сочетание клавиш…';

  @override
  String get dockMenuSmartModeSettings => 'Настройки Smart Mode…';

  @override
  String get dockMenuSttModels => 'Управление моделями распознавания речи…';

  @override
  String get dockMenuGroupCloud => 'Облако';

  @override
  String get dockMenuModelDownload => 'Загрузить';

  @override
  String get dockMenuModelLoading => 'загружается';

  @override
  String get dockMenuSttLockedReason => 'Нельзя изменить во время записи';

  @override
  String get dockMenuSearchHint => 'Поиск…';

  @override
  String get dockMenuSearchNoMatches => 'Ничего не найдено';

  @override
  String get dockMenuAppliesNextRecording => 'Применяется с следующей записи';

  @override
  String get dockStopDictation => 'Остановить запись';

  @override
  String get historyImportAddFiles => 'Добавить файлы';

  @override
  String historyImportDescription(String formats) {
    return 'Расшифровка аудиофайлов ($formats) на этом устройстве. Перетащите файлы на эту страницу или добавьте их.';
  }

  @override
  String get historyImportQueueTitle => 'Очередь импорта';

  @override
  String get historyImportStatusQueued => 'Ожидает';

  @override
  String get historyImportStatusCopying => 'Копирование';

  @override
  String get historyImportStatusDecoding => 'Декодирование';

  @override
  String get historyImportStatusTranscribing => 'Расшифровка';

  @override
  String get historyImportStatusDone => 'Готово';

  @override
  String get historyImportStatusFailed => 'Ошибка';

  @override
  String get historyImportStatusCancelled => 'Отменено';

  @override
  String get historyImportFailureCopy =>
      'Не удалось скопировать файл. Проверьте, что он существует и доступен для чтения, и попробуйте снова.';

  @override
  String get historyImportFailureUnsupported =>
      'Этот формат не поддерживается на этой платформе. Преобразуйте файл в WAV и импортируйте его снова.';

  @override
  String get historyImportFailureDecode =>
      'Не удалось декодировать файл. Вероятно, он повреждён или неполный. Импортируйте другую копию или сохраните файл в WAV.';

  @override
  String get historyImportFailureInputLimit =>
      'Файл слишком большой или длиннее 6 часов. Разделите его на более короткие части.';

  @override
  String get historyImportFailureTranscription =>
      'Расшифровка не удалась. Проверьте распознавание речи в настройках и попробуйте снова.';

  @override
  String get historyImportFailureSave =>
      'Не удалось сохранить расшифровку. Проверьте свободное место на диске и попробуйте снова.';

  @override
  String get historyImportRejectedFolder =>
      'Папки нельзя импортировать. Выберите аудиофайлы внутри них.';

  @override
  String get historyImportRejectedNotFound => 'Файл не найден.';

  @override
  String historyImportRejectedType(String formats) {
    return 'Этот тип файла нельзя импортировать. Поддерживаются: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'Не удалось открыть окно выбора файлов. Попробуйте ещё раз или перетащите файлы на эту страницу.';

  @override
  String get historyImportDropHere =>
      'Перетащите аудиофайлы сюда, чтобы расшифровать их';

  @override
  String get historyImportCancel => 'Отменить импорт';

  @override
  String get historyImportRetry => 'Повторить импорт';

  @override
  String get recoveryOffer =>
      'Найдена прерванная запись. Восстановить аудио и расшифровать его?';

  @override
  String get recoveryNoAudioKept =>
      'Найдена прерванная запись, но аудио не сохранено, так как хранение аудио выключено.';

  @override
  String get recoveryNoAudioCaptured =>
      'Найдена прерванная запись, но в ней нет аудио.';

  @override
  String get recoveryRestore => 'Восстановить';

  @override
  String get recoveryDiscard => 'Удалить';

  @override
  String get recoveryDiscardConfirm => 'Отбросить эту запись?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'Эта прерванная запись будет удалена с этого устройства вместе с сохранённым аудио, если оно есть.';

  @override
  String get recoveryFailed =>
      'Восстановить не удалось. Аудио сохранено, можно повторить.';

  @override
  String recoverySkippedCorrupt(int count) {
    return 'Пропущено повреждённых записей восстановления: $count. Они сохранены на диске.';
  }

  @override
  String get settingsGroupApp => 'Приложение';

  @override
  String get settingsGroupDictation => 'Голосовой ввод';

  @override
  String get settingsGroupSystem => 'Система';

  @override
  String get settingsAreaGeneral => 'Общие';

  @override
  String get settingsAreaAppearance => 'Оформление';

  @override
  String get settingsAreaShortcuts => 'Горячие клавиши';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'Горячая клавиша: $combo';
  }

  @override
  String get settingsAreaRecording => 'Запись и звук';

  @override
  String get settingsAreaSpeech => 'Распознавание речи';

  @override
  String get settingsAreaTextInsert => 'Текст и вставка';

  @override
  String get settingsAreaPrivacy => 'Конфиденциальность и данные';

  @override
  String get settingsAreaAdvanced => 'Дополнительно';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'Актуальная версия';

  @override
  String get settingsNavUpdateAvailable => 'Доступно обновление';

  @override
  String get settingsNavStoreUpdates => 'Обновления через магазин';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'Обновления для этой сборки поставляет магазин. Проверка обновлений в приложении здесь недоступна.';

  @override
  String get settingsStoreBetaUnavailable =>
      'Предварительные сборки в версии для магазина не предлагаются.';

  @override
  String get settingsStoreCudaUnavailable =>
      'Недоступно в версии для магазина: загрузка драйверов из-за пределов магазина там не разрешена.';

  @override
  String get settingsOverlayPreview => 'Предпросмотр оверлея';

  @override
  String get settingsPreviewTitle => 'Предпросмотр';

  @override
  String get settingsPreviewHint =>
      'Так выглядят оверлей и кнопка во время записи. Изменения применяются сразу.';

  @override
  String get settingsPreviewOverlayCaption => 'Оверлей';

  @override
  String get settingsOverlayOptionsGroup => 'Оверлей';

  @override
  String get settingsOverlayForm => 'Форма';

  @override
  String get settingsOverlayFormSubtitle =>
      'Капсула или прямоугольник со скруглёнными углами.';

  @override
  String get settingsOverlayFormPill => 'Капсула';

  @override
  String get settingsOverlayFormRoundedRect => 'Скруглённый';

  @override
  String get settingsOverlayWaveStyle => 'Стиль волны';

  @override
  String get settingsOverlayWaveStyleSubtitle =>
      'Как голос отображается в оверлее.';

  @override
  String get settingsOverlayWaveBars => 'Полосы';

  @override
  String get settingsOverlayWaveLine => 'Линия';

  @override
  String get settingsOverlayWaveDots => 'Точки';

  @override
  String get settingsOverlayWaveFluid => 'Плавный контур';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'Край реагирует на голос. Выключен при «Уменьшить движение».';

  @override
  String get settingsOverlayShowTimer => 'Показывать время';

  @override
  String get settingsOverlayShowTimerSubtitle =>
      'Показывает прошедшее время записи.';

  @override
  String get settingsOverlayShowCancel => 'Значок отмены';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'Кнопка «Стоп» всегда видна. Esc по-прежнему отменяет.';

  @override
  String get settingsOverlayOpacity => 'Непрозрачность';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'Повышается автоматически, если волна иначе станет слишком бледной.';

  @override
  String get settingsOverlayOpacityFull => '100 %';

  @override
  String get settingsOverlayOpacityReduced => '80 %';

  @override
  String get settingsOverlayOpacitySubtle => '60 %';

  @override
  String get settingsFloatingButtonSize => 'Размер';

  @override
  String get settingsFloatingButtonSizeSubtitle => 'Диаметр плавающей кнопки';

  @override
  String get settingsFloatingButtonSizeSmall => 'Маленький';

  @override
  String get settingsFloatingButtonSizeMedium => 'Средний';

  @override
  String get settingsFloatingButtonSizeLarge => 'Большой';

  @override
  String get settingsFloatingButtonShape => 'Форма';

  @override
  String get settingsFloatingButtonShapeSubtitle =>
      'Круглая или скруглённый квадрат';

  @override
  String get settingsFloatingButtonShapeRound => 'Круглая';

  @override
  String get settingsFloatingButtonShapeSquare => 'Квадрат';

  @override
  String get settingsFloatingButtonRing => 'Кольцо записи';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'Цветное кольцо вокруг кнопки во время записи';

  @override
  String get settingsFloatingButtonIdleOpacity => 'Непрозрачность в покое';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'Насколько заметна кнопка без записи';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'Общие (цвета)';

  @override
  String get settingsAreaSmartMode => 'Умный режим';

  @override
  String get settingsAreaDictionary => 'Словарь';

  @override
  String get settingsSearchEmptyHelp => 'Искать в справке';

  @override
  String get dictionaryTabTerms => 'Термины';

  @override
  String get dictionaryTabReplacements => 'Замены';

  @override
  String get dictionaryTabSuggestions => 'Предложения';

  @override
  String get dictionaryTermsEffectPrompt =>
      'Передаётся распознаванию речи как подсказка. Оно может чаще выбирать эти написания, но само текст не меняет.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'Текущее распознавание речи подсказки не принимает. Текст меняют только замены. Ваши термины сохраняются.';

  @override
  String get dictionaryTermsHelp =>
      'Имена, термины и аббревиатуры, которые распознавание часто пишет неверно. Разделяйте запятыми или переносами строк.';

  @override
  String get dictionaryReplacementsHelp =>
      'Добавляйте только слова, которые распознавание действительно пишет неверно. Правильно распознанные слова не меняются.';

  @override
  String get dictionaryTestTitle => 'Проверить';

  @override
  String get dictionaryTestInputLabel => 'Пример предложения';

  @override
  String get dictionaryTestInputHint =>
      'Введите предложение, чтобы увидеть, какие замены сработают.';

  @override
  String get dictionaryTestResultLabel => 'Результат';

  @override
  String get dictionaryTestNoChange => 'Ни одна замена не сработала.';

  @override
  String get dictionaryCsvTitle => 'Импорт и экспорт (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'Одна строка на запись: триггеры через $pipe, текст замены, режим (exact или fuzzy), порог.';
  }

  @override
  String get dictionaryCsvImport => 'Импорт CSV';

  @override
  String get dictionaryCsvExport => 'Экспорт CSV';

  @override
  String get dictionaryCsvExportEmpty => 'Пока нет замен для экспорта.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'Файл больше 1 МБ. Разделите его на несколько файлов.';

  @override
  String get dictionaryCsvImportReadError => 'Не удалось прочитать файл.';

  @override
  String get dictionaryCsvImportNothing => 'Подходящих записей не найдено.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count строки пропущены: они неполные или неверные.',
      many: '$count строк пропущены: они неполные или неверные.',
      few: '$count строки пропущены: они неполные или неверные.',
      one: '$count строка пропущена: она неполная или неверная.',
    );
    return '$_temp0';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Прочитаны только $count записи.',
      many: 'Прочитаны только $count записей.',
      few: 'Прочитаны только $count записи.',
      one: 'Прочитана только $count запись.',
    );
    return '$_temp0';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return 'Добавлено записей: $added.';
  }

  @override
  String get dictionaryCsvExportFailed => 'Не удалось сохранить CSV-файл.';

  @override
  String dictionaryCsvExportDone(int count) {
    return 'Экспортировано записей: $count.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'Строка $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'Слишком мало столбцов.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'Нет триггера.';

  @override
  String get dictionaryCsvReasonTriggerTooLong => 'Триггер слишком длинный.';

  @override
  String get dictionaryCsvReasonEmptyReplacement => 'Нет текста замены.';

  @override
  String get dictionaryCsvReasonReplacementTooLong =>
      'Текст замены слишком длинный.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'Режим должен быть exact или fuzzy.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'Порог: strict, standard, tolerant или число от 0,5 до 1.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'Строка содержит управляющий или скрытый символ форматирования либо разрыв строки.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'Слишком много триггеров в одной строке (не больше $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'Проверьте записи';

  @override
  String get dictionaryDuplicateBadge => 'Дубль';

  @override
  String get dictionaryDuplicateHint =>
      'Другая запись использует тот же триггер. Действует запись, которая стоит выше в списке.';

  @override
  String dictionaryUsageCount(int count) {
    return 'Применено $count×';
  }

  @override
  String get dictionaryFavouriteLabel => 'Избранное';

  @override
  String dictionarySuggestionsHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count раза',
      many: '$count раз',
      few: '$count раза',
      one: '$count раз',
    );
    return 'Предложение появляется, когда одна и та же правка повторяется $_temp0. Без вашего подтверждения ничего не добавляется.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'Пока нет предложений';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'Если вы дважды исправите одно и то же слово, WhisPaste предложит здесь замену.';

  @override
  String get dictionarySuggestionAccept => 'Принять';

  @override
  String get dictionarySuggestionReject => 'Отклонить';

  @override
  String get dictionarySuggestionAccepted => 'Замена добавлена.';

  @override
  String get dictionarySuggestionRejected =>
      'Предложение отклонено. Оно больше не появится.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'Записи с пометкой «будет добавлено» попадут в ваш список. Существующие записи не меняются.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return 'Добавить записей: $count';
  }

  @override
  String get dictionaryCsvImportEncodingError =>
      'Файл не является текстом в кодировке UTF-8.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'Этот файл в формате пакета, который это приложение не может прочитать.';

  @override
  String get dictionaryCsvRefusedType =>
      'Этот файл не является пакетом словаря замен.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'Пакет: $name (создан $date)';
  }

  @override
  String get dictionaryCsvPackageNone =>
      'Нет данных о пакете (старый или чужой файл)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'Новых: $added · Дубликатов: $duplicates · Конфликтов: $conflicts · Циклических ссылок: $circular · С ошибками: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel => 'Если триггер уже есть';

  @override
  String get dictionaryCsvStrategySkip => 'Пропустить';

  @override
  String get dictionaryCsvStrategyOverwrite => 'Заменить';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'Оставить оба';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'Строка не импортируется. Существующие записи не меняются.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'Общий триггер удаляется из старой записи, строка добавляется. Изменится или будет удалено записей: $changed.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'Строка тоже добавляется. Для того же триггера по-прежнему работает существующая запись, которая стоит в списке раньше.';

  @override
  String get dictionaryCsvStatusAdded => 'будет добавлено';

  @override
  String get dictionaryCsvStatusDuplicate => 'уже есть';

  @override
  String get dictionaryCsvStatusConflictSkipped => 'конфликт, пропускается';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'конфликт, заменяет существующий триггер';

  @override
  String get dictionaryCsvStatusConflictKept =>
      'конфликт, добавляется дополнительно';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'заменена более поздней строкой этого файла';

  @override
  String get dictionaryCsvStatusCircular =>
      'циклическая ссылка, не импортируется';

  @override
  String get dictionaryCsvRowWillAdd => 'Будет добавлено';

  @override
  String get dictionaryCsvRowSkipped => 'Дубликат, пропускается';

  @override
  String get dictionaryCsvExportSelectTitle => 'Выберите записи для экспорта';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return 'Записей для выбора: $count';
  }

  @override
  String get dictionaryCsvAllPresent =>
      'Все записи уже есть. Ничего не будет записано.';

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'Экспортировать ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'Слишком много записей для одного файла: $count. Выберите меньше (не более 5000 записей, 1 МиБ).';
  }

  @override
  String get settingsBetaGroupHeading => 'Предварительные версии';

  @override
  String get analyticsWordingTitle => 'Формулировка';

  @override
  String get analyticsWordingPanelTitle => 'Слова: сырые и переработанные';

  @override
  String get analyticsRawWords => 'Сырые слова';

  @override
  String get analyticsRevisedWords => 'Переработанные слова';

  @override
  String get analyticsTransformActions => 'Записи, переработанные действиями';

  @override
  String get analyticsCorrectionsTitle => 'Частые исправления';

  @override
  String get analyticsNoCorrections => 'Исправления пока не записаны.';

  @override
  String get errorNoticeNoModelCause =>
      'Модель распознавания речи не установлена.';

  @override
  String get errorNoticeNoModelNext =>
      'Скачайте модель в настройках и попробуйте снова.';

  @override
  String get errorNoticeMicCause => 'У WhisPaste нет доступа к микрофону.';

  @override
  String get errorNoticeMicNext =>
      'Разрешите доступ в системных настройках и попробуйте снова.';

  @override
  String get errorNoticeTranscribeCause => 'Расшифровка не удалась.';

  @override
  String get errorNoticeTranscribeNext =>
      'Попробуйте снова. Если ошибка повторяется, перезапустите WhisPaste или выберите другую модель в настройках.';

  @override
  String get errorNoticeCpuCause =>
      'Видеокарту для этой расшифровки использовать не удалось.';

  @override
  String get errorNoticeCpuNext =>
      'Расшифровка шла на процессоре, это медленнее. Проверьте ускорение GPU в настройках.';

  @override
  String get languageMismatchHint =>
      'Распознанный язык не совпадает с настройкой.';

  @override
  String get languageMismatchSwitch => 'Сменить язык';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'Parakeet не может распознать $language. Перейти на Whisper?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'Перейти на Whisper';

  @override
  String get titleBarMinimizeLabel => 'Свернуть окно';

  @override
  String get titleBarCloseLabel => 'Закрыть окно';

  @override
  String get titleBarMaximizeLabel => 'Развернуть окно';

  @override
  String get titleBarRestoreLabel => 'Восстановить окно';

  @override
  String get notificationSmartModeSkippedTitle =>
      'WhisPaste: Smart Mode пропущен';

  @override
  String get notificationHotkeyFallbackTitle =>
      'WhisPaste: сочетание клавиш занято';

  @override
  String get notificationSmartModeSkippedBody =>
      'Не удалось применить постобработку.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'Текстовая модель не загружена, поэтому постобработка пропущена.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'Постобработка заняла слишком много времени.';

  @override
  String get notificationSmartModeOutcomePasted =>
      'Неизменённый текст вставлен.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'Не удалось подтвердить, вставлен ли неизменённый текст.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'Неизменённый текст в буфере обмена, но он не вставлен.';

  @override
  String get notificationSmartModeOutcomeNone =>
      'Неизменённый текст не вставлен.';

  @override
  String get smartModeNoTextModelHint =>
      'Текстовая модель не настроена — пока можно выбрать только «Выкл».';

  @override
  String get smartModeLoadTextModelAction => 'Нет текстовой модели – загрузить';

  @override
  String get smartModeAddOpenAiKeyAction => 'Добавить ключ OpenAI';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'Файл не является корректным экспортом WhisPaste.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'Не удалось обработать файл или настройки.';

  @override
  String get historyImportAudioLabel => 'Аудио';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'Переключение приложений';

  @override
  String get hotkeyConflictNoteQuitApp => 'Выход из приложения';

  @override
  String get hotkeyConflictNoteCloseWindow => 'Закрыть окно';

  @override
  String get hotkeyConflictNoteHideApp => 'Скрыть приложение';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'Свернуть окно';

  @override
  String get hotkeyConflictNoteCycleWindows => 'Переключение окон';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen =>
      'Снимок экрана (весь экран)';

  @override
  String get hotkeyConflictNoteScreenshotSelection =>
      'Снимок экрана (выделенная область)';

  @override
  String get hotkeyConflictNoteScreenshotRecording => 'Снимок/запись экрана';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'Выбор эмодзи и символов';

  @override
  String get hotkeyConflictNoteForceQuit => 'Окно «Принудительное завершение»';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'Блокировка компьютера';

  @override
  String get hotkeyConflictNoteShowDesktop => 'Показ/скрытие рабочего стола';

  @override
  String get hotkeyConflictNoteFileExplorer => 'Проводник';

  @override
  String get hotkeyConflictNoteRunDialog => 'Окно «Выполнить»';

  @override
  String get hotkeyConflictNoteSettings => 'Параметры';

  @override
  String get hotkeyConflictNoteSearch => 'Поиск';

  @override
  String get hotkeyConflictNoteTaskView => 'Представление задач';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch =>
      'Переключение языка ввода';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'Развернуть окно';

  @override
  String get hotkeyConflictNoteSnapLeft => 'Прикрепить окно слева';

  @override
  String get hotkeyConflictNoteSnapRight => 'Прикрепить окно справа';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'Параметры безопасности / Диспетчер задач';

  @override
  String get hotkeyConflictNoteTaskManager => 'Диспетчер задач';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde =>
      'Блокировка экрана (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'Окно «Выполнить» (KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'Диалог выхода/выключения системы';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'Открыть терминал (по умолчанию в GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'Блокировка экрана (GNOME)';

  @override
  String get hotkeyConflictNoteActivityOverviewKde => 'Обзор действий (KDE)';

  @override
  String get settingsTextProcessingHeading => 'Обработка текста';

  @override
  String get settingsShowNotificationsSubtitle =>
      'Сообщает о проблемах, например о заблокированной автовставке или отсутствующем сигнале микрофона.';

  @override
  String get settingsGainSubtitle =>
      'Усиливает сигнал микрофона перед записью. Слишком высокие значения могут исказить запись.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'Что происходит с распознанным текстом. Автовставка вставляет его прямо в курсор.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'Язык, который ожидает распознавание. Автоопределение обычно работает хорошо. Фиксированный язык часто точнее для коротких записей.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'Ваш собственный ключ OpenAI. Нужен, только если вы используете OpenAI для распознавания или Smart Mode. Аудио и текст тогда напрямую отправляются в OpenAI и оплачиваются по тарифам OpenAI.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'Ваш собственный ключ Deepgram. Нужен, только если вы используете Deepgram для распознавания. Аудио тогда напрямую отправляется в Deepgram и оплачивается по тарифам Deepgram.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'Сбрасывает все настройки, ключи API и статистику. Записи, заметки и модели сохраняются.';

  @override
  String get settingsFactoryResetSubtitle =>
      'Сразу удаляет все транскрипции, заметки, аудиофайлы, Словарь, Сниппеты, модели, журналы и настройки на этом устройстве. Отменить нельзя.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'Горячая клавиша запускает запись из любого приложения. Когда она выключена, WhisPaste её игнорирует.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'Сразу проверяет, есть ли новая версия. Установка начнётся только после вашего подтверждения.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'Сколько транскрипций хранится, прежде чем старые переместятся в корзину. В корзине транскрипции удаляются окончательно по истечении выбранного срока. Избранное всегда сохраняется. Сохранённые аудиофайлы удаляются не позднее чем через 30 дней после записи, независимо от этой настройки.';

  @override
  String get smartModeTargetLanguageSubtitle => 'Только для пресета «Перевод».';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'Файл слишком большой для импорта (предел около 5 МБ). Выберите файл настроек, экспортированный из WhisPaste.';

  @override
  String get settingsSearchKeywordsInterface =>
      'тема, темная тема, светлая тема, оформление, язык, автозапуск, запуск, свернуто, уведомления, язык системы, панель, боковая панель, быстрая вставка, панель буфера обмена, положение панели, край экрана, край, трей, ЦП, индикатор, строка состояния, загрузка';

  @override
  String get settingsSearchKeywordsStt =>
      'модель, Whisper, качество, транскрипция, распознавание речи, локально, на устройстве, облако, язык, таймаут, словарь, слова, STT, голос, Deepgram, OpenAI, ключ API, только цифры, пунктуация, движок, тишина, обрезка, слова-паразиты, перенос строки, абзац, строка, GPU, графика, ускорение, процессор, железо';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'пресет, очистка, сокращение, перевод, Gemma, модель, текстовая модель, загрузка, постобработка, полировка, редактировать выделение, выделение, выделенный текст, переписать';

  @override
  String get settingsSearchKeywordsAudio =>
      'микрофон, запись, усиление, громкость, нажать для разговора, удерживать для записи, вход';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'буфер обмена, вставка, автовставка, копирование, действие, вывод, ничего не делать, список блокировки, восстановить буфер, оставить транскрипцию, предыдущее содержимое';

  @override
  String get settingsSearchKeywordsOverlay =>
      'оверлей, плавающее, отображение, состояние, положение, окно, сверху по центру, снизу по центру, начальное положение, живая транскрипция';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'фон, цвет, морской, графит, ледник, стекло, непрозрачный, янтарный';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'волна, волны, цвет, голубой, фиолетовый, нейтральный, анимация, янтарный';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'кнопка, плавающая, всегда поверх, кнопка записи, быстрый доступ';

  @override
  String get settingsSearchKeywordsHotkey =>
      'горячая клавиша, сочетание клавиш, глобальная клавиша, глобальное сочетание, клавиатура, клавиши, назначение клавиш, хоткей';

  @override
  String get settingsSearchKeywordsSound =>
      'звук, тон, аудио, сигнал, писк, громкость, звук записи, уведомление, звук завершения, оповещение';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'безопасность, тишина, автоостановка, таймаут, таймаут микрофона, определение тишины, защита, микрофон без сигнала, максимальная длительность';

  @override
  String get settingsSearchKeywordsHistory =>
      'записи, история, элементы истории, корзина, очистка, хранение, максимум, автоудаление, удаление, хранилище, скрыть, конфиденциальность, PIN, блокировка, заблокировать, защита';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'экспорт, импорт, перенос, передача, резервная копия, восстановление, смена устройства, переносимость, новый компьютер, автоматическая резервная копия, автосохранение';

  @override
  String get settingsSearchKeywordsAdvanced =>
      'сброс, значения по умолчанию, сброс к заводским';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'автоматизация, API, скрипт, токен, bearer, HTTP, localhost, порт';

  @override
  String get settingsSearchKeywordsUpdates =>
      'обновление, бета, канал, канал выпусков, предварительная версия, проверить, автоматически, новая версия, стабильная, версия';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'знакомство, онбординг, первоначальная настройка, настройка, экскурсия, тур, снова, ещё раз, первые шаги';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'оценка, оценить, звезды, магазин, поддержать, отзыв, рейтинг';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'конфиденциальность, аналитика, статистика, отслеживание, анонимно, отчеты об ошибках, отчеты о сбоях, статистика использования, данные, поделиться, согласие, хранить записи, последние записи';

  @override
  String get manualNoticeLabel => 'Сообщение в приложении';

  @override
  String get manualC01Title => 'Начало работы';

  @override
  String get manualC01S1Heading => 'Настройка при первом запуске';

  @override
  String get manualC01S1B1 =>
      'При первом запуске WhisPaste проведёт вас через настройку. Можно вернуться к любому шагу. Всё можно изменить позже в настройках.';

  @override
  String get manualC01S1B2I1 => 'Добро пожаловать: краткий обзор WhisPaste.';

  @override
  String get manualC01S1B2I2 =>
      'Конфиденциальность: что остаётся на вашем устройстве.';

  @override
  String get manualC01S1B2I3 =>
      'Модель распознавания речи: выберите нужную и загрузите её. Если для облачного провайдера уже сохранён API-ключ, можно выбрать этого провайдера.';

  @override
  String get manualC01S1B2I4 =>
      'Горячая клавиша: задайте сочетание клавиш, которым начинается запись.';

  @override
  String get manualC01S1B2I5 =>
      'Внешний вид: включение или выключение автозапуска при входе в систему.';

  @override
  String manualC01S1B2I6(String k1) {
    return '$k1: вставлять ли текст автоматически. В Linux этот шаг пропускается.';
  }

  @override
  String get manualC01S1B2I7 =>
      'Проверка: пробная запись, и можно начинать. Без модели распознавания речи или выбранного облачного провайдера с API-ключом завершить нельзя.';

  @override
  String get manualC01S2Heading => 'Системные требования';

  @override
  String manualC01S2B1(String ram) {
    return 'WhisPaste требует устройство с оперативной памятью (RAM) не менее $ram. На устройствах с меньшим объёмом WhisPaste вместо приложения показывает только уведомление.';
  }

  @override
  String get manualC01S2B2 =>
      'Для записи нужен микрофон. В начальной настройке можно продолжить без него, но записывать можно будет только при подключённом микрофоне.';

  @override
  String get manualC01S3Heading => 'Загрузка модели распознавания речи';

  @override
  String get manualC01S3B1 =>
      'WhisPaste преобразует вашу речь в текст на вашем устройстве или через облачный провайдер с вашим собственным ключом. На устройстве для этого нужна модель. Загрузку вы запускаете сами, она не начинается автоматически.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: быстрый, для европейских языков, около $k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: все 99 языков, модели примерно от $k1 до $k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'Модели хранятся в папке данных приложения, в подпапке $k1.';
  }

  @override
  String get manualC01S3B4 =>
      'Модель Whisper остаётся загруженной после диктовки, чтобы следующий запуск был быстрее. В разделе «Держать модель загруженной» в настройках распознавания речи выберите: «Всегда» (по умолчанию) экономит время ожидания, но постоянно занимает память. «Автоматически» оставляет модель загруженной, если в компьютере достаточно памяти, иначе выгружает её через 5 минут. «После простоя» выгружает её через заданное вами время. Когда памяти не хватает, WhisPaste сам выгружает модель и загружает её снова, как только появится место.';

  @override
  String get manualC01S3B3 =>
      'В разделе Распознавание речи пункт «Повторить тест производительности» измеряет скорость каждого установленного уровня на вашем компьютере. Результаты показывают на карточках моделей, насколько дольше работает уровень, и определяют рекомендуемый уровень Whisper. Для европейских языков WhisPaste рекомендует Parakeet. Тест не запускается во время записи.';

  @override
  String get manualC02Title => 'Запись и вставка';

  @override
  String get manualC02S1Heading => 'Горячая клавиша';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'Горячая клавиша — это сочетание клавиш, которое работает в любой программе. По умолчанию: $k2 в Windows и Linux, $k3 на Mac. Изменить его можно в настройках, в разделе «Горячие клавиши».';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'Если это сочетание уже занято другой программой, WhisPaste для основной горячей клавиши использует $k2 (на Mac — $k3). Остальные горячие клавиши остаются выключенными, пока вы не зададите свободное сочетание.';
  }

  @override
  String get manualC02S2Heading => 'Удерживать или переключать';

  @override
  String get manualC02S2B1 =>
      'В настройках, в разделе «Горячие клавиши», выберите, как работает горячая клавиша:';

  @override
  String get manualC02S2B2I1 =>
      '«Удерживать для записи» включено: удерживайте горячую клавишу, говорите и отпустите. При отпускании запись завершается.';

  @override
  String get manualC02S2B2I2 =>
      'Выключено: одно нажатие запускает запись, второе — завершает.';

  @override
  String get manualC02S3Heading => 'Индикация записи';

  @override
  String get manualC02S3B1 =>
      'Док внизу главного окна показывает текущее состояние. Во время записи кнопка меняется на «Остановить запись», а зона состояния показывает текущий этап. Док всегда на месте и не отключается.';

  @override
  String get manualC02S3B3 =>
      'В узком окне док переносит менее важные элементы в меню «Ещё»: горячую клавишу, подсказку Auto-Paste и уведомление об обновлении. Всё остаётся доступным там.';

  @override
  String get manualC02S3B2I1 =>
      '«Оверлей записи» → «Плавающий (всегда поверх)»: небольшая форма волны поверх всех программ. По умолчанию: выкл.';

  @override
  String get manualC02S3B2I2 =>
      '«Плавающая кнопка»: кнопка, которой запись запускается кликом. По умолчанию: выкл. В Linux с Wayland рабочий стол может ограничивать положение кнопки и то, остаётся ли она поверх окон.';

  @override
  String get manualC02S4Heading => 'Вставка после записи';

  @override
  String get manualC02S4B1 =>
      'В разделе «После транскрипции» выберите действие после каждой записи:';

  @override
  String get manualC02S4B2I1 =>
      '«Скопировать в буфер обмена» (по умолчанию): текст попадает в буфер, вставлять его нужно самостоятельно.';

  @override
  String get manualC02S4B2I2 =>
      '«Автовставка у курсора»: WhisPaste вставляет текст в место курсора.';

  @override
  String get manualC02S4B2I3 => '«Копировать и вставить»: оба действия.';

  @override
  String get manualC02S4B2I4 =>
      '«Ничего не делать»: WhisPaste не копирует и не вставляет текст.';

  @override
  String get manualC02S4B3 =>
      'Приложения из списка «Исключения для автовставки» не получают автоматическую вставку. Текст тогда попадает в буфер обмена, или только в Записи, если «Копировать в буфер обмена при заблокированных приложениях» выключено.';

  @override
  String get manualC02S4B4 =>
      'В Windows автовставка не работает в программах, запущенных с правами администратора.';

  @override
  String get manualC02S4B5 =>
      'В Linux WhisPaste помечает текст подсказкой, которую учитывает только Klipper из KDE. Другие менеджеры буфера обмена, например GPaste или CopyQ, тоже сохраняют транскрипции: отключите у них запись буфера обмена или удалите запись.';

  @override
  String get manualC02S4B6 =>
      'После вставки WhisPaste обычно возвращает то, что было в буфере обмена раньше. В пункте «Буфер обмена после вставки» можно выбрать «Оставить транскрипцию»: тогда распознанный текст остаётся в буфере обмена. Если вставку не удалось подтвердить вовремя, транскрипция всегда остаётся там. Если macOS запрещает доступ к буферу обмена, WhisPaste не может сохранить прежнее содержимое и не восстанавливает его; транскрипция остаётся в буфере обмена. Один раз появляется подсказка с путём к Системным настройкам.';

  @override
  String get manualC03Title => 'Быстрая заметка';

  @override
  String get manualC03S1Heading => 'Что делает быстрая заметка';

  @override
  String get manualC03S1B1 =>
      'Быстрая заметка — это заметка, в которую WhisPaste добавляет новые записи. Так можно собирать мысли или список, не создавая каждый раз новую заметку.';

  @override
  String get manualC03S1B2 =>
      'Если ещё нет отмеченной заметки, WhisPaste при первом использовании создаёт новую и отмечает её.';

  @override
  String get manualC03S2Heading => 'Настройка';

  @override
  String get manualC03S2B1I1 =>
      'Откройте заметку в разделе «Заметки» и включите «Сделать быстрой заметкой для горячей клавиши». «Убрать отметку быстрой заметки» снимает отметку.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'Включите горячую клавишу быстрой заметки в настройках, в разделе «Горячие клавиши». По умолчанию она выключена. Клавиша — $k1 ($k2, на Mac $k3).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'Что делает Smart Mode';

  @override
  String manualC04S1B1(String k1) {
    return '$k1 редактирует распознанный текст перед вставкой. По умолчанию он выключен, и включить его нужно вручную.';
  }

  @override
  String get manualC04S1B2 =>
      'По умолчанию обработка выполняется на вашем устройстве («Локально на устройстве»). С вариантом «OpenAI» текст отправляется в OpenAI. Подробности — в главе о конфиденциальности.';

  @override
  String get manualC04S2Heading => 'Пресеты';

  @override
  String get manualC04S2B1 => 'Пресет определяет, что происходит с текстом:';

  @override
  String get manualC04S2B2I1 =>
      '«Выкл.»: без постобработки, текст остаётся как распознан.';

  @override
  String get manualC04S2B2I2 =>
      '«Очистка»: убирает слова-паразиты и исправляет пунктуацию и регистр, не меняя формулировок, смысла и языка.';

  @override
  String get manualC04S2B2I3 =>
      '«Краткость»: убирает повторы и слова-паразиты, сохраняя все важные факты и язык.';

  @override
  String get manualC04S2B2I4 =>
      '«Перевод»: переводит текст на выбранный целевой язык.';

  @override
  String get manualC04S3Heading => 'Целевой язык и горячая клавиша';

  @override
  String get manualC04S3B1 =>
      'Для пресета «Перевод» выберите целевой язык: немецкий, английский, испанский, французский, португальский, мандаринский или русский. По умолчанию — английский.';

  @override
  String manualC04S3B2(String k1) {
    return 'Отдельная горячая клавиша для $k1 по умолчанию выключена. Она использует пресет и целевой язык из настроек.';
  }

  @override
  String get manualC04S4Heading => 'Ресурсы';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'Локальный вариант загружает текстовую модель размером около $size. Если в устройстве меньше $ram ОЗУ, WhisPaste предупредит перед загрузкой, но загрузить можно в любом случае. Во время работы текстовой модели нужно ещё 4–5 ГБ ОЗУ.';
  }

  @override
  String get manualC04S4B2 =>
      'Пока текстовая модель не настроена (локальная не скачана или для OpenAI нет ключа), все пресеты, кроме «Выкл», заблокированы. Док и настройки называют причину и ведут к загрузке модели или вводу ключа. Если постобработка всё равно не сработала, WhisPaste сообщает об этом и говорит, вставлен ли неизменённый текст или он только в буфере обмена.';

  @override
  String get manualC05Title => 'Словарь';

  @override
  String get manualC05S1Heading => 'Как работают замены';

  @override
  String get manualC05S1B1 =>
      'Замена автоматически меняет определённые слова или фразы на другой текст при каждой записи.';

  @override
  String get manualC05S1B2 =>
      'У каждой замены есть одна или несколько фраз-триггеров (что искать) и новый текст. Несколько триггеров для одного текста вводятся в разделе «Фразы-триггеры».';

  @override
  String get manualC05S2Heading => 'Совпадение';

  @override
  String get manualC05S2B1I1 =>
      'Точная: заменяется только полностью совпадающая запись.';

  @override
  String get manualC05S2B1I2 =>
      'Похожая: заменяются и немного отличающиеся написания. Работает только для триггеров длиной от 4 символов.';

  @override
  String get manualC05S2B1I3 =>
      'Допуск (строгий, стандартный или мягкий): задаётся для каждой записи отдельно, а не для всех сразу.';

  @override
  String get manualC05S3Heading => 'Импорт и экспорт (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'Замены можно сохранить или перенести в файле CSV. В файле столбцы $k1. Несколько триггеров разделяются символом $k2. Файл может быть размером не больше $k3 и содержать не более $k4 строк.';
  }

  @override
  String get manualC05S3B2 =>
      'Импорт и экспорт находятся в меню «Ещё» (⋯) над списком. Поле проверки также открывается из этого меню.';

  @override
  String get manualC06Title => 'Сниппеты';

  @override
  String get manualC06S1Heading => 'Что такое сниппеты';

  @override
  String get manualC06S1B1 =>
      'Сниппет — это фрагмент текста, который вставляется по слову-триггеру или горячей клавише, например подпись или стандартный ответ.';

  @override
  String get manualC06S1B2I1 =>
      '«Статический»: текст вставляется точно так, как вы его сохранили.';

  @override
  String get manualC06S1B2I2 =>
      '«Интерактивный»: WhisPaste по очереди запрашивает поля голосом и вставляет их в ваш шаблон.';

  @override
  String get manualC06S2Heading => 'Открытие выбора сниппетов';

  @override
  String get manualC06S2B1 => 'Открыть выбор можно двумя способами:';

  @override
  String get manualC06S2B2I1 =>
      'Словом-триггером выбора: скажите только это слово. Оно срабатывает, только если вся запись — ровно это слово. Задаётся в настройках, в разделе «Горячие клавиши», группа «Заметки и сниппеты», сразу под горячей клавишей выбора; оставьте пустым, чтобы выключить выбор.';

  @override
  String get manualC06S2B2I2 =>
      'Горячей клавишей выбора: по умолчанию выключена; включите в «Горячая клавиша панели».';

  @override
  String get manualC06S3Heading => 'Создание сниппета';

  @override
  String get manualC06S3B1I1 =>
      'Создайте сниппет кнопкой «Добавить» и выберите «Статический» или «Интерактивный».';

  @override
  String manualC06S3B1I2(String k1) {
    return 'Для типа «Интерактивный» задайте поля и напишите шаблон. Заполнители ставятся в двойных фигурных скобках, например $k1.';
  }

  @override
  String get manualC07Title => 'Заметки';

  @override
  String get manualC07S1Heading => 'Работа с заметками';

  @override
  String get manualC07S1B1 =>
      'В разделе «Заметки» собирается текст, например идеи или материалы. Если использовать быструю заметку, записи попадают прямо в заметку.';

  @override
  String get manualC07S1B2I1 => '«Добавить в избранное» выделяет заметку.';

  @override
  String get manualC07S1B2I2 => '«Добавить тег» относит заметку к категории.';

  @override
  String get manualC07S2Heading => 'Корзина';

  @override
  String get manualC07S2B1 =>
      '«Переместить в корзину» помещает заметку в корзину. Она остаётся там, пока вы не удалите её окончательно. Корзина никогда не очищается автоматически.';

  @override
  String get manualC07S2B2I1 =>
      '«Удалить навсегда» удаляет заметку из корзины.';

  @override
  String get manualC07S3Heading => 'Быстрая заметка';

  @override
  String get manualC07S3B1 =>
      'В разделе «Заметки» видно, какая заметка — быстрая. Подробности — в главе о быстрой заметке.';

  @override
  String get manualC07S4Heading => 'Изображения и конфиденциальность';

  @override
  String get manualC07S4B1 =>
      'При добавлении изображения WhisPaste удаляет метаданные, например местоположение (GPS), данные камеры и сведения EXIF, XMP и IPTC. Сохраняется только очищенная копия.';

  @override
  String get notesPinGateTitle => 'Заметки заблокированы';

  @override
  String get notesPinGateHint => 'Введите PIN-код, чтобы показать заметки.';

  @override
  String get manualC08Title => 'Записи';

  @override
  String get manualC08S1Heading => 'Что хранится в записях';

  @override
  String get manualC08S1B1 =>
      'В записях отображается каждый элемент: распознанный текст с датой. Если аудио сохранено, аудиофайл относится к этому элементу.';

  @override
  String get manualC08S2Heading => 'Поиск и фильтры';

  @override
  String manualC08S2B1I1(String k1) {
    return 'Введите $k1, чтобы фильтровать по тегам.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'Введите $k1 и язык, чтобы фильтровать по языку.';
  }

  @override
  String get manualC08S2B1I3 => 'Или просто введите ключевое слово.';

  @override
  String get manualC08S2B1I4 =>
      'Над списком находятся фильтры «Избранное», «В архиве», «Корзина» и «Все».';

  @override
  String get manualC08S3Heading => 'Управление элементами';

  @override
  String get manualC08S3B1I1 =>
      '«Копировать текст» снова копирует текст в буфер обмена.';

  @override
  String get manualC08S3B1I2 =>
      '«Добавить в избранное» закрепляет элемент вверху. «Убрать из избранного» отменяет это.';

  @override
  String get manualC08S3B1I3 =>
      '«Архив» убирает элемент из основного списка, не удаляя его.';

  @override
  String get manualC08S3B1I4 =>
      '«Дублировать», «Объединить» (несколько элементов в один) и «Выбрать несколько» помогают навести порядок.';

  @override
  String get manualC08S3B1I5 =>
      '«Добавить примечание» и «Добавить тег…» дополняют элемент.';

  @override
  String get manualC08S4Heading => 'Голосовая заметка';

  @override
  String get manualC08S4B1 =>
      'Запустите голосовую заметку у элемента. Скажите «tag: название», чтобы задать тег, или «correct: текст», чтобы заменить текст элемента.';

  @override
  String get manualC08S4B2 =>
      'Исправление заменяет весь текст элемента, а не одно слово. «correct: текст» работает так же. Сразу после этого изменение можно отменить в уведомлении.';

  @override
  String get manualC08S5Heading => 'Защита PIN-кодом';

  @override
  String get manualC08S5B1 =>
      'Если включена настройка «Защита PIN-кодом», перед показом записей запрашивается PIN-код. Это касается и боковой панели, меню плавающей кнопки и API автоматизации. PIN-код не даёт другим просто смотреть транскрипции, но не шифрует их. Заметки блокируются так же. Если PIN-код задан, меню в трее показывает последние записи только со временем и числом слов, без начала текста.';

  @override
  String get manualC08S5B2 =>
      'Забытый PIN-код восстановить нельзя. Для сброса сразу удаляются все записи и сохранённые аудиофайлы (включая архив и корзину), все заметки с версиями и все изображения заметок. Настройки, текстовые блоки и замены сохраняются.';

  @override
  String get manualC08S5B3 =>
      'Пока записи заблокированы PIN-кодом, вкладка буфера обмена в боковой панели не показывает скопированный текст и не вставляет его. После разблокировки текст снова доступен.';

  @override
  String get manualC08S6Heading => 'Автоочистка';

  @override
  String get manualC08S6B1 =>
      'В настройке «Автоудаление корзины через» задайте срок, в течение которого удалённые элементы остаются в корзине до автоматического удаления.';

  @override
  String get manualC09Title => 'Импорт аудиофайлов';

  @override
  String get manualC09S1Heading => 'Расшифровка аудиофайлов';

  @override
  String manualC09S1B1(String k1) {
    return 'Можно расшифровать готовые аудиофайлы. Выберите «$k1» и укажите файл.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'Помимо $k1 можно импортировать и другие форматы, в зависимости от системы: на Mac $k2, в Linux $k3, в Windows $k4.';
  }

  @override
  String get manualC09S2Heading => 'Ограничения';

  @override
  String get manualC09S2B2 =>
      'Что делать: разбейте запись на части покороче и импортируйте их по одной.';

  @override
  String get manualC09S3Heading => 'Ошибки импорта';

  @override
  String manualC09S3B2(String k1) {
    return 'Что делать: попробуйте снова. Если не поможет, перезапустите WhisPaste или выберите другую модель в разделе $k1.';
  }

  @override
  String get manualC10Title => 'Статистика';

  @override
  String get manualC10S1Heading => 'Разделы';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'Статистика состоит из трёх разделов: $k1, $k2 и $k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'С помощью «$k1» и «$k2» выберите период.';
  }

  @override
  String get manualC10S2Heading => 'Что означают числа';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 и $k2 считают ваши записи и общее время записи.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 — это грубая оценка: WhisPaste считает сэкономленными две трети времени записи, поскольку речь обычно быстрее печати. Это не измерение.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: локальные записи экономят на облачных расходах. WhisPaste оценивает это в $k2 за минуту — фиксированный ориентир.';
  }

  @override
  String get manualC10S3Heading => 'Сброс';

  @override
  String manualC10S3B1(String k1) {
    return '«$k1» удаляет все данные статистики. WhisPaste спрашивает подтверждение, и это нельзя отменить.';
  }

  @override
  String get manualC11Title => 'Настройки';

  @override
  String get manualC11S1Heading => 'Разделы';

  @override
  String get manualC11S1B1 => 'Настройки разбиты на разделы. Самые важные:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: внешний вид приложения.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: модель и язык распознавания.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: микрофон и громкость.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: пресет, целевой язык и поставщик.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: что происходит после записи.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: горячие клавиши.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: срок хранения в корзине.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: экспорт, импорт и автоматическое резервное копирование.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: локальный API и хуки событий для программ на этом компьютере.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: дополнительные параметры, например сброс.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: версия, проверка обновлений, ссылки и лицензии.';
  }

  @override
  String get manualC11S2Heading => 'Резервное копирование и сброс';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 автоматически сохраняет настройки после изменений. Сохраняются последние пять файлов. По умолчанию выключено.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 сразу удаляет все транскрипции, аудиофайлы и настройки и сбрасывает WhisPaste. Внимательно прочитайте подтверждение, прежде чем подтвердить.';
  }

  @override
  String get manualC12Title => 'Конфиденциальность и работа без сети';

  @override
  String get manualC12S1Heading => 'Что остаётся на устройстве';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'По умолчанию распознавание речи работает на вашем устройстве. Аудио уходит в облачный сервис, только если вы сами выбрали облачного поставщика. Транскрипции хранятся в локальной базе данных на вашем устройстве, сохранённые аудиофайлы — как файлы рядом с ней. Аудио ваших последних $count записей сохраняется, только если включено «$k1», не более $days дн.';
  }

  @override
  String get manualC12S1B2 =>
      'Проверка обновлений запрашивает у GitHub новые версии. Отзыв отправляется только при нажатии «Отправить отзыв».';

  @override
  String get manualC12S1B3 =>
      'Если расшифровка не удалась из-за недоступного сервера или соединения, аудио этой записи хранится до 24 часов, чтобы можно было повторить попытку из сообщения об ошибке или в разделе «Конфиденциальность». Это действует и при выключенном хранении аудио. Если хранение включено, действует обычное хранение.';

  @override
  String get manualC12S2Heading => 'Облачные поставщики';

  @override
  String manualC12S2B1(String k1) {
    return 'Поставщикам OpenAI и Deepgram нужен ваш собственный ключ API. Введите его в разделе $k1.';
  }

  @override
  String get manualC12S3Heading =>
      'Статистика использования и отчёты об ошибках';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'Две опции включены по умолчанию: $k1 и $k2. Выключить их можно в разделе $k3.';
  }

  @override
  String get manualC13Title => 'Оборудование и производительность';

  @override
  String get manualC13S1Heading => 'Память';

  @override
  String manualC13S1B1(String k1) {
    return 'WhisPaste рекомендует не менее $k1 оперативной памяти. При меньшем объёме приложение всё равно запускается и предлагает модель распознавания речи «Быстрый».';
  }

  @override
  String get manualC13S2Heading => 'Видеокарта';

  @override
  String get manualC13S2B1 =>
      'WhisPaste использует видеокарту, когда она может ускорить распознавание речи:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, графический интерфейс Apple.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 и $k2 с графикой AMD или Intel: $k3, широко используемый графический интерфейс.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'Карты NVIDIA тоже используют $k1. С дополнительным пакетом CUDA распознавание также использует $k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'Без подходящей видеокарты WhisPaste считает на процессоре ($k1). Это медленнее.';
  }

  @override
  String get manualC13S3Heading => 'Пакет CUDA';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'Пакет CUDA — необязательное дополнение для карт NVIDIA; по данным приложения, для $k1 и $k2. Он доступен для $k3 и $k4 (x64). Включается в разделе $k5.';
  }

  @override
  String get manualC13S3B2 =>
      'Загрузка одноразовая. Размер показывает приложение.';

  @override
  String get manualC13S3B3 =>
      'Пакет содержит компоненты NVIDIA. Перед первой загрузкой вы принимаете лицензию NVIDIA CUDA (версия 2026-01-26); согласие действует для этой установки. Без действующего согласия в строке показано «Требуется согласие», а WhisPaste использует Vulkan или процессор, пока вы не примете лицензию. Если текст лицензии или пакет изменятся, вас спросят снова.';

  @override
  String get manualC13S4Heading => 'Графическое ускорение';

  @override
  String manualC13S4B1(String k1) {
    return 'В разделе «$k1» выберите, использует ли WhisPaste видеокарту. Работа только на процессоре обычно медленнее.';
  }

  @override
  String get manualC13S5Heading => 'Модели и размер';

  @override
  String get manualC13S5B1 =>
      'Модели Whisper бывают трёх уровней: Быстрый, Сбалансированный и Точный. Более точные уровни обычно распознают лучше, но требуют больше времени на обработку.';

  @override
  String get manualC14Title => 'Устранение неполадок';

  @override
  String get manualC14S1Heading => 'Как читать эту страницу';

  @override
  String get manualC14S1B1 =>
      'Каждый раздел начинается с уведомления WhisPaste. Формулировка — оригинальный текст приложения. Ниже указаны причина и следующий шаг.';

  @override
  String get manualC14S2Heading => 'Нет доступа к микрофону';

  @override
  String get manualC14S2B2 =>
      'Что делать: разрешите WhisPaste доступ к микрофону в системных настройках, затем запустите запись заново.';

  @override
  String get manualC14S3Heading => 'Микрофон не найден';

  @override
  String manualC14S3B2(String k1) {
    return 'Что делать: подключите микрофон и выберите его в разделе $k1.';
  }

  @override
  String get manualC14S4Heading => 'Звук не записан';

  @override
  String manualC14S4B2(String k1) {
    return 'Что делать: проверьте, выбран ли нужный микрофон и не стоит ли уровень ($k1) на нуле. Затем запишите снова.';
  }

  @override
  String get manualC14S5Heading => 'Нет модели распознавания речи';

  @override
  String manualC14S5B2(String k1) {
    return 'Что делать: загрузите модель в разделе $k1 и повторите попытку.';
  }

  @override
  String get manualC14S6Heading => 'Неизвестная модель';

  @override
  String manualC14S6B2(String k1) {
    return 'Что делать: выберите установленную модель в разделе $k1.';
  }

  @override
  String get manualC14S7Heading => 'Расшифровка не удалась';

  @override
  String manualC14S7B2(String k1) {
    return 'Что делать: попробуйте снова. Если не поможет, перезапустите WhisPaste или выберите другую модель в разделе $k1.';
  }

  @override
  String get manualC14S8Heading => 'Текст не распознан';

  @override
  String get manualC14S8B2 =>
      'Что делать: говорите отчётливее или немного дольше и попробуйте снова. Проверьте также микрофон.';

  @override
  String get manualC14S9Heading => 'Запись или расшифровка слишком долгие';

  @override
  String get manualC14S9B2 =>
      'Что делать: записывайте более короткие фрагменты.';

  @override
  String get manualC14S10Heading =>
      'Облачный ключ отсутствует или недействителен';

  @override
  String manualC14S10B2(String k1) {
    return 'Что делать: введите ключ заново в разделе $k1 или переключитесь на распознавание на устройстве.';
  }

  @override
  String get manualC14S11Heading => 'Видеопамять заполнена';

  @override
  String get manualC14S11B2 =>
      'Что делать: ничего. Позже модель можно снова выбрать в настройках.';

  @override
  String get manualC14S12Heading => 'Расчёт на процессоре';

  @override
  String manualC14S12B2(String k1) {
    return 'Что делать: обычно ничего. Если это случается часто, проверьте настройку в разделе $k1 и обновите драйвер видеокарты.';
  }

  @override
  String get manualC14S13Heading => 'Автовставка заблокирована (macOS)';

  @override
  String get manualC14S13B2 =>
      'Что делать: разрешите WhisPaste доступ в разделе «Универсальный доступ» системных настроек. Если уведомление не пропадает, перезапустите WhisPaste.';

  @override
  String get manualC14S14Heading => 'Автовставка заблокирована (Windows)';

  @override
  String get manualC14S14B2 =>
      'Что делать: запустите WhisPaste тоже от имени администратора.';

  @override
  String get manualC14S15Heading => 'Автовставка в Linux';

  @override
  String get manualC14S15B1 =>
      'В Linux автовставка использует виртуальное устройство ввода (uinput). Если она не работает, проверьте, может ли WhisPaste обращаться к этому устройству.';

  @override
  String get manualC14S15B2 =>
      'Пакет .deb при установке не выдаёт никакого доступа. Автовставка сначала спрашивает: в начальной настройке или в настройках, раздел «После транскрипции» нажмите «Разрешить (пароль администратора)» и введите пароль администратора. Пока разрешение действует, другие программы в вашем сеансе тоже могут создавать нажатия клавиш. Кнопка «Убрать разрешение» отменяет его в любой момент; при удалении программы оно тоже убирается.';

  @override
  String get manualC14S15B3 =>
      'Версия Flatpak даёт приложению доступ к устройствам ввода системы, чтобы автовставка могла работать. Сам WhisPaste не читает устройства ввода.';

  @override
  String get manualC14S15B4 =>
      'В версии Snap выполните это один раз в терминале:';

  @override
  String get manualC14S15B5 =>
      'AppImage нужен доступ к /dev/uinput. В начальной настройке или в настройках скопируйте команду и выполните её один раз в терминале. Она устанавливает правило udev 71-whispaste-uinput.rules в /etc/udev/rules.d/, которое даёт доступ на запись только активному сеансу. До тех пор автовставка только копирует текст.';

  @override
  String get manualC14S15TerminalHeading => 'Терминалы и Wayland';

  @override
  String get manualC14S15T1 =>
      'В Linux терминалы вставляют через Ctrl+Shift+V. WhisPaste распознаёт распространённые терминалы и сам использует там это сочетание: в X11 и XWayland, а также в KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire и других окружениях на wlroots.';

  @override
  String get manualC14S15T2 =>
      'В GNOME с Wayland WhisPaste определяет целевое приложение только с необязательным расширением WhisPaste для GNOME. Без него WhisPaste не распознаёт терминалы, а список блокировки только копирует текст.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'Если терминал всё равно показывает ^V вместо текста, включите «$k1» в разделе $k2. Тогда WhisPaste везде вставляет через Ctrl+Shift+V. Некоторые приложения используют эти клавиши иначе: LibreOffice, например, открывает диалог.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'В GNOME включите расширение WhisPaste в настройках кнопкой $k1. Пакет .deb уже устанавливает его. Для Flatpak, AppImage или архива установите его один раз скриптом из распакованного пакета для Linux, затем включите:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'Если uinput не настроен, например во Flatpak, WhisPaste вставляет через разрешение рабочего стола: $k1 в разделе $k2. Рабочий стол спросит один раз; разрешение можно там же отозвать в любой момент';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'Этот рабочий стол пока не позволяет приложениям использовать общесистемные сочетания клавиш. Вместо этого WhisPaste может добавить $shortcut в сочетания клавиш GNOME.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'Добавить в GNOME';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut настроено в сочетаниях клавиш GNOME. Если вы измените горячую клавишу, WhisPaste обновит её и там.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'Удалить из GNOME';

  @override
  String get settingsDesktopShortcutFailed =>
      'Не удалось изменить сочетания клавиш GNOME.';

  @override
  String get settingsDesktopShortcutManual =>
      'Этот рабочий стол не позволяет приложениям использовать общесистемные сочетания клавиш. Назначьте эту команду сочетанию клавиш в настройках системы:';

  @override
  String get manualC14S15HotkeyHeading => 'Горячая клавиша в Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'В Wayland приложение получает общесистемные сочетания клавиш только через рабочий стол. KDE Plasma и GNOME 48 или новее это поддерживают. Более старые версии GNOME, например в Ubuntu 24.04, — нет: тогда WhisPaste предлагает «$k1» в разделе $k2 и добавляет горячую клавишу в сочетания клавиш GNOME.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'В других рабочих столах, например Sway или Hyprland, назначьте команду сочетанию клавиш самостоятельно. Точную команду для вашей установки показывают настройки в разделе $k1.';
  }

  @override
  String get manualC14S15H3 =>
      'Если горячая клавиша не работает в других приложениях, в настройках и при первом запуске появляется уведомление с причиной, командой для собственного сочетания клавиш и кнопкой «Подключить снова», которая заново запрашивает клавишу у рабочего стола.';

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'С таким доступом приложение теоретически могло бы читать нажатия клавиш других программ, если у вашего пользователя есть право чтения устройств ввода (например, как члена группы input). Члены группы input могут также создавать виртуальный ввод.';

  @override
  String get manualC14S15B3S =>
      'Автовставке также нужен доступ на запись к /dev/uinput на компьютере: установите правило udev 71-whispaste-uinput.rules в /etc/udev/rules.d/ и затем выполните эти команды:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'Скопировать команду';

  @override
  String get manualCodeCopied => 'Команда скопирована';

  @override
  String get manualCodeCopyFailed =>
      'Не удалось скопировать. Выделите команду и скопируйте её вручную.';

  @override
  String get manualC14S15B3E =>
      'Правило даёт доступ на запись только активному сеансу. Этим командам нужны права администратора (sudo), и они изменяют систему. Если вы этого не хотите, оставьте автовставку выключенной и вставляйте текст вручную. Чтобы удалить правило, воспользуйтесь кнопкой в настройках, которая копирует нужную команду.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'До этого автовставка только копирует текст.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'Горячая клавиша уже занята';

  @override
  String manualC14S16B2(String k1) {
    return 'Что делать: выберите другую комбинацию в разделе $k1.';
  }

  @override
  String get manualC14S17Heading => 'Автозапуск не настроен';

  @override
  String get manualC14S17B2 =>
      'Что делать: проверьте разрешения автозапуска в операционной системе. Без автозапуска WhisPaste не запускается сам.';

  @override
  String get manualC14S18Heading =>
      'Автоматическое резервное копирование не удалось';

  @override
  String manualC14S18B2(String k1) {
    return 'Что делать: выберите другую доступную папку в разделе $k1.';
  }

  @override
  String get manualC14S19Heading => 'Сброс до заводских настроек не завершён';

  @override
  String get manualC14S19B2 =>
      'Что делать: выберите “Повторить” или перезапустите WhisPaste и затем повторите сброс.';

  @override
  String get manualC14S20Heading => 'Звук не обнаружен';

  @override
  String manualC14S20B2(String k1) {
    return 'Что делать: проверьте микрофон в разделе $k1 и запишите снова.';
  }

  @override
  String get manualC14S21Heading => 'Недостаточно памяти';

  @override
  String manualC14S21B1(String k1) {
    return 'WhisPaste запускается и при меньшем объёме памяти, чем рекомендуемые $k1. В этом случае приложение предлагает модель распознавания речи «Быстрый».';
  }

  @override
  String get manualC15Title => 'Сочетания клавиш';

  @override
  String get manualC15S1Heading => 'Только внутри WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'Эти сочетания работают, только когда активно окно WhisPaste. Глобальная горячая клавиша задаётся в разделе $k2.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'На Mac $k1 обычно заменяет $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 открывает справку.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k тоже открывает справку.';
  }

  @override
  String get manualC15S2Heading => 'Записи';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: удалить элемент.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: переключить избранное.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: поиск.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: закрыть поиск или подробности.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: копировать запись.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: отменить правку. При несохранённых изменениях сначала будет запрос.';
  }

  @override
  String get manualC15S3Heading => 'Заметки';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: удалить элемент.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: создать новую заметку.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: поиск.';
  }

  @override
  String get manualC15S4Heading => 'Словарь и сниппеты';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: удалить элемент.';
  }

  @override
  String get manualC15S5Heading => 'Отмена во время записи';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'Пока идёт запись или расшифровка, WhisPaste перехватывает клавишу $k1 во всей системе, чтобы можно было отменить. В это время $k1 не работает в других программах. Если это мешает, выберите $k2 как клавишу отмены в настройках.';
  }

  @override
  String get manualC16Title => 'Отзывы и поддержка';

  @override
  String get manualC16S1Heading => 'Отправка отзыва';

  @override
  String get manualC16S1B1I1 => 'Оценка: обязательна.';

  @override
  String get manualC16S1B1I2 =>
      'Тип: обязательно. Выберите: Проблема, Идея, Похвала или Вопрос.';

  @override
  String get manualC16S1B1I3 => 'Свободный текст до 1000 символов.';

  @override
  String get manualC16S1B1I4 => 'Адрес электронной почты необязателен.';

  @override
  String get manualC16S1B2 =>
      'Если вы недавно уже отправляли отзыв, приложение покажет такое уведомление:';

  @override
  String get manualC16S2Heading => 'Поддержка';

  @override
  String manualC16S2B1(String k1) {
    return 'Вкладка $k1 в разделе помощи показывает, как можно поддержать WhisPaste.';
  }

  @override
  String get manualC16S3Heading => 'Напоминание об оценке';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'Если вы выбрали «Больше не спрашивать» в напоминании об оценке, переключатель «$k2» находится в разделе $k1. Он появляется только в этом случае.';
  }

  @override
  String get manualC16S4B1 =>
      'Отзыв можно отправить со вкладки «Справка», из меню «Справка» в строке меню (macOS) или из меню в заголовке окна (Windows и Linux), а также из трея. Форма открывается в два шага.';

  @override
  String get manualC16S5Heading => 'Предложить идею';

  @override
  String get manualC16S5B1 =>
      'Выберите тип «Идея» или откройте «Предложить идею» в меню «Справка»: тип уже выбран. Идею также можно разместить на публичной доске идей и голосовать за идеи других.';

  @override
  String get manualC16S6Heading => 'Ввод голосом';

  @override
  String get manualC16S6B1 =>
      'Кнопка микрофона в поле сообщения записывает ваш голос и вставляет распознанный текст в позицию курсора.';

  @override
  String get manualC16S7Heading => 'Что отправляется';

  @override
  String get manualC16S7B1I1 => 'Выбранный тип и ваше сообщение.';

  @override
  String get manualC16S7B1I3 =>
      'Адрес почты только если вы его указали. Он нужен только для ответа и удаляется через 90 дней.';

  @override
  String get manualC16S7B1I4 =>
      'Диагностика только если вы включили «Прикрепить диагностику»: версия приложения, операционная система, движок распознавания речи и бэкенд. «Показать предпросмотр» покажет точный текст до отправки.';

  @override
  String get manualC16S7B1I5 =>
      'Только для похвалы: согласие показать вашу похвалу как цитату на сайте. По умолчанию выключено, отозвать можно одним нажатием на этой странице.';

  @override
  String get manualC16S7B2 => 'Записи и расшифровки никогда не прикрепляются.';

  @override
  String get manualC16S4Heading => 'Где найти форму';

  @override
  String get manualC16S7B1I2 => 'Выбранная оценка.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'Не удалось вставить – текст в буфере обмена ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'Проверить разрешение';

  @override
  String get autoPasteResetConfirmTitle => 'Сбросить запись и разрешить снова?';

  @override
  String get autoPasteResetConfirmBody =>
      'macOS сохранила старую запись WhisPaste, которая больше не действует. WhisPaste удалит только эту запись «Универсальный доступ». Затем macOS спросит снова. Остальные разрешения не изменятся.';

  @override
  String get autoPasteResetConfirmButton => 'Сбросить запись и разрешить снова';

  @override
  String get permissionRowMicTitle => 'Микрофон';

  @override
  String get permissionRowMicPurpose =>
      'Записывает ваш голос. Без этого разрешения запись невозможна.';

  @override
  String get permissionRowPasteTitle => 'Автовставка';

  @override
  String get permissionRowPastePurpose =>
      'Вставляет текст в место курсора. Без неё текст останется в буфере обмена.';

  @override
  String get permissionRowAllow => 'Разрешить';

  @override
  String get permissionRowMissingSettings => 'Нет доступа – открыть настройки';

  @override
  String get permissionRowGranted => 'Разрешено';

  @override
  String get permissionRowOptional => 'Необязательно';

  @override
  String get autostartApprovalBody =>
      'macOS ждёт вашего разрешения: WhisPaste запустится при входе, только если вы включите его в разделе «Объекты входа».';

  @override
  String get autostartApprovalAction => 'Открыть объекты входа';

  @override
  String get pasteFailureLinuxUinputHint =>
      'Автовставке нужно ваше однократное разрешение на виртуальную клавиатуру (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'Скопировать команду';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'Автовставка недоступна в этой системе: нет виртуального устройства клавиатуры.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'Автовставке нужен одноразовый доступ к /dev/uinput. Откройте настройки автовставки для одноразовой настройки.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'Теперь автовставка спрашивает, прежде чем использовать виртуальную клавиатуру /dev/uinput, поэтому это обновление убрало прежний доступ. Текст находится в буфере обмена, вставьте его сочетанием $paste. Нажмите здесь, чтобы разрешить.';
  }

  @override
  String get linuxUinputSetupAction => 'Настроить';

  @override
  String get linuxUinputConsentDetail =>
      'Чтобы вставлять текст самостоятельно, WhisPaste нужна виртуальная клавиатура. Пока она разрешена, другие программы в вашем сеансе тоже могут создавать нажатия клавиш. Без разрешения WhisPaste копирует текст, и вы вставляете его сами.';

  @override
  String get linuxUinputGrantButton => 'Разрешить (пароль администратора)';

  @override
  String get linuxUinputGrantFailed =>
      'Не удалось выдать разрешение. WhisPaste по-прежнему только копирует текст.';

  @override
  String get linuxUinputRevokeButton => 'Убрать разрешение';

  @override
  String get linuxUinputRevokeDone =>
      'Разрешение убрано. Теперь WhisPaste только копирует текст.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'API-ключи не удалось полностью удалить.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours ч';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes мин';
  }

  @override
  String get dockErrorCauseEngine =>
      'Модель распознавания речи остановилась с ошибкой.';

  @override
  String get dockErrorCauseRecording => 'Запись не удалось расшифровать.';

  @override
  String get dockErrorAction =>
      'Откройте настройки речи и проверьте модель распознавания речи.';

  @override
  String get overlayDoneCopiedOnly =>
      'Только скопировано – целевое приложение заблокировано или не распознано';

  @override
  String get overlayDoneNotPasted => 'Не вставлено – сохранено в Записях';

  @override
  String get overlayDonePasteFailed => 'Вставка невозможна – скопируйте текст';

  @override
  String get databaseTooNewTitle => 'WhisPaste не может открыть ваши данные';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'Данные записаны более новой версией WhisPaste (версия базы данных $storedVersion). Эта версия поддерживает версии до $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'Установите последнюю версию WhisPaste и запустите приложение снова. Ничего не изменено и не удалено.';

  @override
  String get databaseTooNewQuit => 'Выйти';

  @override
  String get pasteFailureTargetChanged =>
      'Автовставка отменена: вы переключились на другое приложение во время обработки. Текст в буфере обмена.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'Автовставка не подтверждена. Текст в буфере обмена, вставьте его сочетанием $paste.';
  }

  @override
  String get onboardingAppearanceSettingsHint =>
      'Можно изменить в любой момент в Настройках → Оформление';

  @override
  String get onboardingAppearanceSettingsLink =>
      'Открыть предпросмотр в Настройках (завершает настройку)';

  @override
  String get onboardingAppearanceSettingsLinkRevision =>
      'Открыть предпросмотр в Настройках (показать позже снова)';

  @override
  String get fileDialogOpenTitle => 'Открыть файл';

  @override
  String get fileDialogOpenFilesTitle => 'Открыть файлы';

  @override
  String get fileDialogSaveTitle => 'Сохранить файл';

  @override
  String get fileDialogFolderTitle => 'Выбрать папку';

  @override
  String get fileDialogSelectFolder => 'Выбрать';

  @override
  String get dockLanguageAuto => 'Авто';

  @override
  String get settingsLanguageFavoriteAdd => 'Добавить в избранное';

  @override
  String get settingsLanguageFavoriteRemove => 'Убрать из избранного';

  @override
  String get settingsLanguageFavoritesLimit =>
      'Не более 3 избранных. Уберите один, чтобы добавить другой.';

  @override
  String get dockMenuFavorites => 'Избранное';

  @override
  String get dockMenuAllLanguages => 'Все языки';

  @override
  String get traySpeechModel => 'Модель распознавания';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'Значку в трее нужен хост трея. В GNOME установите расширение AppIndicator; до тех пор меню быстрого переключения недоступно.';

  @override
  String get trayLanguage => 'Язык';

  @override
  String get trayLanguageMore => 'Ещё…';

  @override
  String get trayProfile => 'Профиль';

  @override
  String get trayProfileAutomatic => 'Автоматически, по приложению';

  @override
  String get trayProfileNone => 'Без профиля';

  @override
  String profileSwitchedToast(String name) {
    return 'Профиль: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'Следующий избранный язык';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'Следующий избранный язык';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'Переключает язык диктовки на следующий избранный. До трёх языков можно отметить избранными в разделе «Речь в текст».';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'Уже занято: $action. Выберите другую комбинацию.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'Сочетание занято другим приложением или не удалось его зарегистрировать. Выберите другое.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'В Wayland это сочетание может не работать в других приложениях. Если оно не реагирует, создайте для него ярлык на рабочем столе.';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'Язык диктовки: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'Язык диктовки: $language. Применяется с следующей записи.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'Избранных языков пока нет. Отметьте до трёх языков в разделе «Речь в текст», чтобы использовать это сочетание.';

  @override
  String get languageCycleOpenSettings => 'Открыть настройки';

  @override
  String get manualLangFavHeading => 'Избранные языки';

  @override
  String get manualLangFavB1 =>
      'В настройках распознавания речи отметьте звёздочкой в списке языков до трёх избранных. Избранные языки стоят первыми в меню языков панели записи и в меню трея, поэтому переключиться можно одним щелчком.';

  @override
  String get manualLangTrayHeading => 'Язык в меню трея';

  @override
  String get manualLangTrayB1 =>
      'В меню трея есть подменю «Язык». Оно показывает ваши избранные языки и ставит галочку у активного. «Ещё…» открывает окно с полным списком. Parakeet выбирает язык сам, поэтому подменю там скрыто.';

  @override
  String get manualLangCycleHeading => 'Следующий избранный язык';

  @override
  String get manualLangCycleB1 =>
      'В карточке «Диктовка» можно назначить сочетание клавиш, которое при каждом нажатии переключает язык диктовки на следующий избранный. Сочетание выключено, пока вы не запишете комбинацию. Без избранных языков WhisPaste покажет, где их настроить. В Linux под Wayland другие приложения могут не реагировать на сочетание.';

  @override
  String onboardingReadyDesktopShortcutHint(String shortcut) {
    return '$shortcut пока не работает во всей системе на этом рабочем столе. Вернитесь на страницу, где вы выбрали горячую клавишу, чтобы настроить её.';
  }

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut заработает во всей системе только после добавления в сочетания клавиш GNOME.';
  }

  @override
  String get recommendationReasonLanguage =>
      'Рекомендовано, потому что Parakeet поддерживает ваш язык и быстро работает на любом устройстве.';

  @override
  String get recommendationReasonMeasured =>
      'Рекомендовано по замеру на этом устройстве.';

  @override
  String recommendationReasonApple(String memory) {
    return 'Рекомендовано для вашего чипа Apple (Metal) с $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'Рекомендовано для вашей видеокарты NVIDIA с $gb ГБ видеопамяти (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'Рекомендовано для вашей видеокарты $name (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'Рекомендовано для процессора, так как подходящей видеокарты нет: ядер: $cores, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name — программная графика, поэтому работает процессор: ядер: $cores, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb ГБ ОЗУ';
  }

  @override
  String get recommendationMemoryUnknown => 'объём ОЗУ неизвестен';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'Нет модели распознавания речи – скачать $name сейчас ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'Если выбранной модели распознавания речи нет, док показывает «Модель распознавания речи не скачана». Меню речи в доке тогда первым пунктом предлагает её скачать — и для Whisper, и для Parakeet. Если нажать сочетание клавиш без модели, появится уведомление с кнопкой «Скачать сейчас». Если в настройках переключиться на Whisper, а выбранной модели Whisper нет, WhisPaste выберет уже скачанную.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'Процессор (программный Vulkan, $name)';
  }

  @override
  String get menuBarMenuEdit => 'Правка';

  @override
  String get menuBarMenuWindow => 'Окно';

  @override
  String get menuBarEditUndo => 'Отменить';

  @override
  String get menuBarEditRedo => 'Повторить';

  @override
  String get menuBarEditCut => 'Вырезать';

  @override
  String get menuBarEditCopy => 'Копировать';

  @override
  String get menuBarEditPaste => 'Вставить';

  @override
  String get menuBarEditSelectAll => 'Выбрать всё';

  @override
  String get menuBarWindowMinimize => 'Свернуть';

  @override
  String get menuBarWindowZoom => 'Масштаб';

  @override
  String get menuBarAppQuit => 'Выйти из WhisPaste';

  @override
  String get menuBarMenuRecording => 'Запись';

  @override
  String get menuBarAppSettings => 'Настройки…';

  @override
  String get menuBarHelpManual => 'Открыть руководство';

  @override
  String get menuBarHelpFeedback => 'Отправить отзыв…';

  @override
  String get menuBarHelpIdea => 'Предложить идею…';

  @override
  String get manualC15S6Heading => 'Меню';

  @override
  String get manualC15S6B1 =>
      'На Mac главные команды есть и в строке меню вверху. Меню «Запись» запускает и останавливает запись и задаёт язык, модель распознавания речи, Smart Mode, действие после транскрибирования, микрофон и профиль.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: открыть настройки: $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'Правка: вырезать, копировать, вставить и выбрать всё действуют на активное поле ввода.';

  @override
  String get manualC15S6B2I3 => 'Окно: свернуть и развернуть главное окно.';

  @override
  String get manualC15S6B2I4 =>
      'Справка: открыть руководство, отправить отзыв и предложить идею.';

  @override
  String get manualC15S6B3 =>
      'В Windows и Linux те же команды находятся в кнопке меню в правом верхнем углу заголовка окна. Откройте её клавишей Alt или F10, выбирайте пункты стрелками, запускайте Enter и закрывайте Escape.';

  @override
  String get menuBarAppAbout => 'О WhisPaste';

  @override
  String get menuBarAppHide => 'Скрыть';

  @override
  String get menuBarAppHideOthers => 'Скрыть остальные';

  @override
  String get menuBarAppShowAll => 'Показать все';

  @override
  String get titleBarMenuLabel => 'Меню';

  @override
  String get notesTitleLabel => 'Заголовок';

  @override
  String get notesMoreActions => 'Другие действия';

  @override
  String get notesVersionSaveNow => 'Сохранить версию сейчас';

  @override
  String get notesMenuMark => 'Выделить маркером';

  @override
  String get notesMenuAddImage => 'Вставить изображение';

  @override
  String get notesMenuVersions => 'Версии';

  @override
  String get notesMenuSnippet => 'Сохранить как сниппет';

  @override
  String get notesVersionsEmpty => 'Версий пока нет.';

  @override
  String get notesVersionTooLarge => 'Слишком большая для просмотра';

  @override
  String get notesVersionDelete => 'Удалить версию';

  @override
  String get notesVersionSaved => 'Версия сохранена';

  @override
  String get notesVersionUnchanged => 'С последней версии изменений нет.';

  @override
  String get notesVersionRestored => 'Версия восстановлена';

  @override
  String get notesVersionRestoreMessage =>
      'Восстанавливаются только заголовок и текст этой версии. Изображения остаются без изменений.';

  @override
  String get notesVersionDeleteMessage =>
      'Эта версия будет удалена безвозвратно.';

  @override
  String get notesImageFilesLabel => 'Изображения';

  @override
  String get notesImageRejected =>
      'Этот файл не является поддерживаемым изображением (PNG, JPEG, GIF или WebP).';

  @override
  String get notesImageRemove => 'Удалить изображение';

  @override
  String get notesSnippetCreated => 'Сниппет создан';

  @override
  String get notesSnippetNothing =>
      'В этой заметке нет текста для сохранения как сниппета.';

  @override
  String get notesMarkNeedsSelection => 'Сначала выделите текст.';

  @override
  String get notesImageLimitCount =>
      'В этой заметке уже максимальное количество изображений.';

  @override
  String get notesImageLimitBytes =>
      'Изображения этой заметки превысят лимит размера.';

  @override
  String get notesImageLimitTotal =>
      'Хранилище изображений заполнено. Удалите изображение, чтобы добавить другое.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'Файл копировался слишком медленно или изменился во время копирования. Попробуйте ещё раз.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'Этот формат недоступен в этой системе. Преобразуйте файл в WAV и импортируйте его снова.';

  @override
  String get audioDropHint =>
      'Перетащите сюда аудиофайлы, чтобы расшифровать их';

  @override
  String audioDropRejectedFolder(String names) {
    return 'Папки нельзя импортировать: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'Файл не найден: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'Не поддерживается: $names. Допустимые форматы: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'Это не обычный файл, импорт невозможен: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'Слишком большой (не более 1 ГБ): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'Это не обычный файл, импорт невозможен.';

  @override
  String get historyImportRejectedTooLarge => 'Файл больше 1 ГБ.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'Зарезервированное имя устройства, импорт невозможен: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'Windows резервирует это имя файла, поэтому импорт невозможен. Переименуйте файл.';

  @override
  String get historyImportFailureIo =>
      'Память заполнена или запись невозможна.';

  @override
  String get holdToRecordExplained =>
      'Вкл.: удерживайте сочетание клавиш и говорите, отпустите для завершения. Выкл.: нажмите для старта и ещё раз для завершения.';

  @override
  String get settingsAreaProfiles => 'Профили';

  @override
  String get profilesSectionHeading => 'Ваши профили';

  @override
  String get profilesEmptyBody =>
      'Профили переключают модель распознавания, язык, Smart Mode и действие после транскрипции горячей клавишей или автоматически для каждого приложения.';

  @override
  String get profilesAddFirst => 'Создать первый профиль';

  @override
  String get profilesAdd => 'Создать профиль';

  @override
  String get profilesCreate => 'Создать';

  @override
  String get profilesLimitReached =>
      'Не более 9 профилей. Удалите один, чтобы создать новый.';

  @override
  String get profilesActiveBadge => 'Активен';

  @override
  String get profilesMoveUp => 'Выше';

  @override
  String get profilesMoveDown => 'Ниже';

  @override
  String get profilesDragHandle => 'Перетащите для сортировки';

  @override
  String get profilesNewTitle => 'Новый профиль';

  @override
  String get profilesNameLabel => 'Имя';

  @override
  String get profilesNameEmpty => 'Введите имя.';

  @override
  String get profileDetailHeading => 'Настройки профиля';

  @override
  String get profileDetailModel => 'Модель распознавания';

  @override
  String get profileDetailLanguage => 'Язык';

  @override
  String get profileDetailLanguageSubtitle =>
      'Действует для Whisper и облачных сервисов. Parakeet определяет язык сам.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'После транскрипции';

  @override
  String get profileDetailMicrophone => 'Микрофон';

  @override
  String get profileKeepUnchanged => 'Не менять';

  @override
  String profileValueUnavailable(String value) {
    return '$value (недоступно)';
  }

  @override
  String get profileDetailHotkey => 'Горячая клавиша';

  @override
  String get profileDetailHotkeySubtitle =>
      'Переключает на этот профиль по этому сочетанию клавиш.';

  @override
  String get profileHotkeyNone => 'Без горячей клавиши';

  @override
  String get profileHotkeyChange => 'Задать сочетание';

  @override
  String get profileHotkeyRemove => 'Убрать сочетание';

  @override
  String get profileHotkeyNeedsModifier =>
      'Горячей клавише профиля нужен хотя бы один модификатор, например Ctrl, Alt, Shift или Command.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'Уже занято: „$action“. Сочетание не активно.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'Уже занято профилем „$name“. Сочетание не активно.';
  }

  @override
  String get profileDetailApps => 'Приложения';

  @override
  String get profileDetailAppsSubtitle =>
      'Если одно из этих приложений активно во время диктовки, профиль включается автоматически.';

  @override
  String get profileAppIdentifierLabel => 'Идентификатор приложения';

  @override
  String get profileAppAdd => 'Добавить';

  @override
  String get profileAppHintMac => 'macOS: ID пакета, например com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: имя программы без .exe, например chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: WM_CLASS окна, например google-chrome. Под Wayland не определяется.';

  @override
  String profileAppClash(String name) {
    return 'Это приложение уже относится к профилю „$name“.';
  }

  @override
  String get profileAppEmpty => 'Приложения пока не назначены.';

  @override
  String get profileAppRemove => 'Удалить правило приложения';

  @override
  String get profileDetailContext => 'Чтение контекста';

  @override
  String get profileDetailContextSubtitle =>
      'По желанию читает выделенный текст или буфер обмена, чтобы обработка подходила. Для облачных сервисов только с вашего согласия.';

  @override
  String get profileContextNone => 'Ничего не читать';

  @override
  String get profileContextSelection => 'Выделенный текст';

  @override
  String get profileContextClipboard => 'Буфер обмена';

  @override
  String get profileConsentGiven => 'Согласие дано';

  @override
  String get profileConsentMissing => 'Согласие не дано, контекст не читается';

  @override
  String get profileConsentWithdraw => 'Отозвать согласие';

  @override
  String get profileConsentTitle => 'Отправлять контекст в облачный сервис?';

  @override
  String get profileConsentBody =>
      'Когда этот профиль активен, выделенный текст или содержимое буфера обмена окна назначения отправляются облачному провайдеру, указанному в этом профиле, только чтобы улучшить эту диктовку. Согласие можно отозвать в любой момент в настройках профиля.';

  @override
  String get profileConsentAccept => 'Согласиться';

  @override
  String get profileDeleteAction => 'Удалить профиль';

  @override
  String profileDeleteTitle(String name) {
    return 'Удалить профиль „$name“?';
  }

  @override
  String get profileDeleteMessage =>
      'Профиль и его приложения будут удалены. Его горячая клавиша освободится.';

  @override
  String get manualProfilesTitle => 'Профили и быстрое переключение';

  @override
  String get manualProfilesS1Heading => 'Создание профилей';

  @override
  String get manualProfilesS1Body =>
      'Профиль — это именованный набор настроек диктовки. Создайте его в Настройки → Профили и для каждого поля решите, задаёт ли его профиль или оставляет без изменений.';

  @override
  String get manualProfilesS1B1 =>
      'Модель распознавания, язык, Smart Mode, действие после транскрипции и микрофон';

  @override
  String get manualProfilesS1B2 =>
      'До 9 профилей. Любое поле может быть «Не менять».';

  @override
  String get manualProfilesS2Heading => 'Горячие клавиши';

  @override
  String get manualProfilesS2Body =>
      'У каждого профиля может быть своя горячая клавиша. Нажатие включает профиль, и он остаётся активным, пока вы не выберете другой или не измените вручную одно из его полей.';

  @override
  String get manualProfilesS2Tip =>
      'Горячей клавише нужен модификатор. Сочетание, которое уже использует другая функция, остаётся неактивным, и профиль показывает это как конфликт.';

  @override
  String get manualProfilesS3Heading => 'Автоматически по приложению';

  @override
  String get manualProfilesS3Body =>
      'Если добавить приложение в «Приложения», профиль включается, когда оно активно во время диктовки. Идентификатор зависит от системы:';

  @override
  String get manualProfilesS3Mac => 'macOS: ID пакета, например com.apple.mail';

  @override
  String get manualProfilesS3Win =>
      'Windows: имя программы без .exe, например chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: WM_CLASS окна в X11, например google-chrome. Под Wayland WhisPaste не может определить приложение.';

  @override
  String get manualProfilesS4Heading => 'Трей и оверлей';

  @override
  String get manualProfilesS4Body =>
      'В меню трея есть подменю «Профиль»: «Автоматически, по приложению» следует правилам, «Без профиля» отключает их, ниже перечислены ваши профили. В оверлее записи имя активного профиля идёт после времени и языка, например 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'Не менять';

  @override
  String get manualProfilesS5Body =>
      '«Не менять» означает, что профиль не трогает это поле. Действует значение, которое сейчас задано в настройках.';

  @override
  String get manualProfilesS6Heading => 'Что делает ручное переключение';

  @override
  String get manualProfilesS6Body =>
      'Если выбрать профиль в трее или нажать его горячую клавишу, он действует на все следующие диктовки. Если затем изменить поле, которое задаёт профиль, например модель распознавания, отметка активен снимается и снова решают правила для приложений. Выбор сохраняется после перезапуска.';

  @override
  String get profileAppCapture => 'Захватить приложение';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'Переключитесь в целевое приложение через $seconds с …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '„$identifier“ добавлено как целевое приложение.';
  }

  @override
  String get profileAppCaptureNone =>
      'Другое приложение не на переднем плане. Переключитесь в целевое приложение до конца отсчёта.';

  @override
  String get profileAppCaptureUnavailable =>
      'Эта сессия не может определить приложение на переднем плане (например Wayland). Введите идентификатор вручную.';

  @override
  String get waylandHotkeyPortalDescription => 'Диктовка WhisPaste';

  @override
  String get waylandHotkeyNoAppId =>
      'Рабочий стол не смог опознать WhisPaste и не включил горячую клавишу, поэтому она не работает в других приложениях.';

  @override
  String get waylandHotkeyUnavailable =>
      'Рабочий стол не позволяет приложениям задавать глобальные горячие клавиши, поэтому горячая клавиша не работает в других приложениях.';

  @override
  String get waylandHotkeyDeclined =>
      'Горячая клавиша не была подтверждена в диалоге рабочего стола, поэтому она не работает в других приложениях.';

  @override
  String get waylandHotkeyFallback =>
      'Вместо этого можно добавить сочетание клавиш в системных настройках с этой командой:';

  @override
  String get waylandHotkeyReconnect => 'Подключить снова';

  @override
  String get waylandHotkeyCopyCommand => 'Копировать команду';

  @override
  String get waylandHotkeyCommandCopied => 'Скопировано';

  @override
  String get waylandHotkeyOpenKeyboardSettings =>
      'Открыть настройки клавиатуры';

  @override
  String get sttEngineRestartHint =>
      'Распознавание речи зависло. Перезапустите WhisPaste: закройте его через меню в трее («Выход») и откройте снова.';
}
