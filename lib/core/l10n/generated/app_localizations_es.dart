// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class L10nEs extends L10n {
  L10nEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'Grabaciones';

  @override
  String get navNotes => 'Notas';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navReplacements => 'Diccionario';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navAnalytics => 'Estadísticas';

  @override
  String get navHelp => 'Ayuda';

  @override
  String get actionOpen => 'Abrir';

  @override
  String actionOpenNamed(String name) {
    return 'Abrir $name';
  }

  @override
  String get helpTabManual => 'Manual';

  @override
  String get helpTabIntro => 'Introducción';

  @override
  String get helpTabSupport => 'Apoyo';

  @override
  String get helpTabDiagnostics => 'Diagnóstico';

  @override
  String get manualSearchHint => 'Buscar en el manual';

  @override
  String get manualSearchEmpty => 'Ningún capítulo coincide con la búsqueda.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos encontrados',
      one: '1 capítulo encontrado',
      zero: 'No se han encontrado capítulos',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'Comentarios';

  @override
  String get pageHistoryTitle => 'Grabaciones';

  @override
  String get pageSettingsTitle => 'Ajustes';

  @override
  String get pageReplacementsTitle => 'Diccionario';

  @override
  String get pageAnalyticsTitle => 'Estadísticas';

  @override
  String get pageAboutTitle => 'Acerca de WhisPaste';

  @override
  String get pageFeedbackTitle => 'Comentarios';

  @override
  String get historyEmpty => 'Todavía no hay grabaciones';

  @override
  String get historyEmptyHint =>
      'Pulsa el botón de grabar o usa el atajo para empezar a grabar.';

  @override
  String get historyPrivacyGateTitle => 'Grabaciones ocultas';

  @override
  String get historyPrivacyGateHint =>
      'Las transcripciones y el audio solo quedan ocultos, no borrados, hasta que decidas mostrarlos.';

  @override
  String get historyPrivacyGateShow => 'Mostrar grabaciones';

  @override
  String get historySearch => 'Buscar…';

  @override
  String get historyPinned => 'Favoritos';

  @override
  String get historyToday => 'Hoy';

  @override
  String get historyYesterday => 'Ayer';

  @override
  String get historyThisWeek => 'Esta semana';

  @override
  String get historyOlder => 'Anteriores';

  @override
  String get historyAll => 'Todas';

  @override
  String get historyTrash => 'Papelera';

  @override
  String get historyArchive => 'Archivo';

  @override
  String get historyArchived => 'Archivadas';

  @override
  String get historyList => 'Lista';

  @override
  String get historyCards => 'Tarjetas';

  @override
  String get historyCompact => 'Compacta';

  @override
  String historyItemsSelected(int count) {
    return 'Seleccionadas: $count';
  }

  @override
  String get historyMerge => 'Combinar';

  @override
  String get historyRestore => 'Restaurar';

  @override
  String get historyDeleteForever => 'Eliminar para siempre';

  @override
  String get historyDeletePermanently => 'Eliminar definitivamente';

  @override
  String get historyUnarchive => 'Quitar del archivo';

  @override
  String get historyExport => 'Exportar';

  @override
  String get historyExportAction => 'Exportar…';

  @override
  String historyExportDone(String path) {
    return 'Exportado a $path';
  }

  @override
  String get historyExportFailed =>
      'No se pudo exportar. Comprueba que la carpeta de destino permite escribir e inténtalo de nuevo.';

  @override
  String get historyCopyAsMarkdown => 'Copiar como Markdown';

  @override
  String get historyDetail => 'Detalle';

  @override
  String get historyTags => 'Etiquetas';

  @override
  String get historyDuration => 'Duración';

  @override
  String get historyModel => 'Modelo de voz';

  @override
  String get historyWords => 'Palabras';

  @override
  String get historyCharacters => 'Caracteres';

  @override
  String historyWordCount(int count) {
    return '$count palabras';
  }

  @override
  String historyReadingTime(int minutes) {
    return '$minutes min de lectura';
  }

  @override
  String get historyReadingTimeUnder1 => '< 1 min de lectura';

  @override
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aprox. $count palabras',
      one: 'aprox. 1 palabra',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'Vista y selección';

  @override
  String get historyEditing => 'Editando';

  @override
  String get historySearchTranscriptions => 'Buscar en las grabaciones…';

  @override
  String get historySearchFieldLabel => 'Buscar transcripciones';

  @override
  String get historyNewRecording => 'Nueva grabación';

  @override
  String get historyStopRecording => 'Detener grabación';

  @override
  String get historyNoResults => 'Sin resultados';

  @override
  String historyNoResultsHint(String query) {
    return 'Ninguna entrada coincide con «$query».\nPrueba con otro término de búsqueda.';
  }

  @override
  String get historyTrashEmpty => 'La papelera está vacía';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Se borran definitivamente tras $days días.',
      one: 'Se borran definitivamente tras 1 día.',
      zero: 'Los elementos se quedan hasta que los borres definitivamente.',
    );
    return 'Las transcripciones eliminadas aparecerán aquí.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'Vaciar papelera';

  @override
  String get historyEmptyTrashConfirm => '¿Vaciar la papelera?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminarán definitivamente $count transcripciones. Los archivos de audio guardados se eliminan como máximo 30 días después de la grabación. Esta acción no se puede deshacer.',
      one:
          'Se eliminará definitivamente 1 transcripción. Cualquier archivo de audio guardado se elimina como máximo 30 días después de la grabación. Esta acción no se puede deshacer.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => '¿Eliminar definitivamente?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminarán definitivamente $count transcripciones y sus audios guardados. Esta acción no se puede deshacer.',
      one:
          'Se eliminará definitivamente 1 transcripción y su audio guardado. Esta acción no se puede deshacer.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Papelera vaciada: $count transcripciones eliminadas',
      one: 'Papelera vaciada: 1 transcripción eliminada',
    );
    return '$_temp0';
  }

  @override
  String get historyNoArchivedItems => 'No hay elementos archivados';

  @override
  String get historyNoArchivedItemsHint =>
      'Archiva las transcripciones que quieras conservar\npero que no necesites en tu lista principal.';

  @override
  String get historyNoRecordingsHint =>
      'Pulsa el botón de grabar o usa el atajo para empezar a grabar.\nTus transcripciones aparecerán aquí.';

  @override
  String get historyNoPinned => 'Todavía no hay favoritos';

  @override
  String get historyNoPinnedHint =>
      'Marca una transcripción como favorita para encontrarla aquí rápidamente.';

  @override
  String get historyNoToday => 'Hoy no hay grabaciones';

  @override
  String get historyNoTodayHint =>
      'Las transcripciones de hoy aparecerán aquí.';

  @override
  String get historyNoThisWeek => 'Esta semana no hay grabaciones';

  @override
  String get historyNoThisWeekHint =>
      'Las transcripciones de esta semana aparecerán aquí.';

  @override
  String get historyCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get historyMovedToTrash => 'Movido a la papelera';

  @override
  String get historyRestored => 'Restaurado';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcripciones archivadas',
      one: '1 transcripción archivada',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcripciones movidas a la papelera',
      one: '1 transcripción movida a la papelera',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcripciones restauradas',
      one: '1 transcripción restaurada',
    );
    return '$_temp0';
  }

  @override
  String get historyUndo => 'Deshacer';

  @override
  String get historyEntriesMerged => 'Entradas combinadas';

  @override
  String historyMergeConfirm(int count) {
    return '¿Combinar $count entradas?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'Las entradas seleccionadas se unirán en una sola. Esta acción no se puede deshacer.';

  @override
  String get historyExitSelection => 'Salir de la selección';

  @override
  String get historySelectMultiple => 'Seleccionar varias';

  @override
  String get historyProcessed => 'Procesada';

  @override
  String get historyOnDevice => 'En el dispositivo';

  @override
  String get historyUntitledRecording => 'Grabación sin título';

  @override
  String get historyUntitled => 'Sin título';

  @override
  String get historyShowAll => 'Mostrar todo';

  @override
  String get historyMoreActions => 'Más acciones';

  @override
  String get historyMdTags => 'Etiquetas';

  @override
  String get historyMdDate => 'Fecha';

  @override
  String get historyMdModel => 'Modelo';

  @override
  String get historyPinToTop => 'Añadir a favoritos';

  @override
  String get historyUnpin => 'Quitar de favoritos';

  @override
  String get historyCopyText => 'Copiar texto';

  @override
  String get historyClose => 'Cerrar';

  @override
  String get historyLanguageLabel => 'Idioma';

  @override
  String historyResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
    );
    return '$_temp0';
  }

  @override
  String get historySelectAll => 'Seleccionar todo';

  @override
  String get historyDeselectAll => 'Deseleccionar todo';

  @override
  String get settingsInterface => 'Interfaz';

  @override
  String get settingsInterfaceSubtitle => 'Apariencia y comportamiento';

  @override
  String get settingsReviewPromptRestore =>
      'Volver a mostrar el aviso de valoración';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'Elegiste «No volver a preguntar». Al activarlo, el aviso puede volver a aparecer; las pausas habituales siguen vigentes.';

  @override
  String get settingsLaunchAtStartup => 'Iniciar con el sistema';

  @override
  String get settingsStartMinimized => 'Iniciar minimizada';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Iniciar en segundo plano al arrancar el sistema';

  @override
  String get settingsAutostartNever => 'Nunca';

  @override
  String get settingsAutostartNormal => 'Normal';

  @override
  String get settingsAutostartMinimized => 'Minimizada';

  @override
  String get settingsAutostartSyncFailed =>
      'No se pudo registrar el inicio automático en el sistema operativo. Puede ser un problema de permisos o que tu versión del sistema no sea compatible.';

  @override
  String get settingsShowNotifications => 'Mostrar notificaciones';

  @override
  String get settingsShowBackendUtilization =>
      'Indicador de cálculo en la barra de estado';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Muestra si está trabajando el procesador o la tarjeta gráfica.';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Micrófono y grabación';

  @override
  String get settingsMicrophone => 'Micrófono';

  @override
  String get settingsGain => 'Sensibilidad del micrófono';

  @override
  String get settingsClippingBanner =>
      'La última grabación tuvo saturación. ¿Reducir la ganancia?';

  @override
  String get settingsClippingDismiss => 'Descartar';

  @override
  String get settingsHoldToRecord => 'Mantener para grabar';

  @override
  String get pushToTalkUnavailableTooltip => 'No disponible en esta plataforma';

  @override
  String get pushToTalkUnavailableLinuxTooltip =>
      'Tu escritorio no informa aquí de cuándo sueltas una tecla. Asigna «whispaste --toggle» a un atajo en los ajustes de tu sistema.';

  @override
  String get settingsExperimentalBadge => 'Experimental';

  @override
  String get settingsHoldOrTap => 'Pulsar o mantener';

  @override
  String get settingsHoldOrTapHint =>
      'Una pulsación corta inicia y detiene la grabación; si mantienes pulsado, grabas hasta que lo sueltes.';

  @override
  String get settingsHoldOrTapThreshold => 'Umbral de mantener pulsado';

  @override
  String settingsHoldOrTapThresholdValue(int ms) {
    return '$ms ms';
  }

  @override
  String get settingsModifierOnlyNone => 'Desactivado';

  @override
  String get settingsModifierRightControl => 'Control derecha';

  @override
  String get settingsModifierRightAlt => 'Alt derecha u Opción';

  @override
  String get settingsModifierRightMetaMac => 'Comando derecha';

  @override
  String get settingsModifierRightMetaWindows => 'Windows derecha';

  @override
  String get settingsModifierRightMetaLinux => 'Super derecha';

  @override
  String get settingsModifierFn => 'Fn (solo macOS)';

  @override
  String get settingsModifierLeftShift => 'Mayús izquierda';

  @override
  String get settingsModifierRightShift => 'Mayús derecha';

  @override
  String get settingsModifierLeftControl => 'Ctrl izquierda';

  @override
  String get settingsModifierLeftAlt => 'Alt / Opción izquierda';

  @override
  String get settingsModifierLeftMetaMac => 'Comando izquierda';

  @override
  String get settingsModifierLeftMetaWindows => 'Tecla Windows izquierda';

  @override
  String get settingsModifierLeftMetaLinux => 'Tecla Super izquierda';

  @override
  String get settingsTriggerDoubleTapHint =>
      'Las teclas izquierdas y Mayús solo inician tras mantenerlas solas un momento, así los atajos normales no activan nada.';

  @override
  String get settingsDoubleTapHandsFree => 'Doble toque: dictar sin manos';

  @override
  String get settingsDoubleTapHandsFreeHint =>
      'Dos toques rápidos inician el dictado sin mantener; una pulsación lo termina.';

  @override
  String get settingsDoubleTapBlockedByHoldOrTap =>
      'No junto con «Mantener o tocar»';

  @override
  String get settingsDoubleTapNeedsHold =>
      'Funciona con «Mantener pulsado» o una sola tecla';

  @override
  String get settingsDoubleTapFallbackNotice =>
      'La tecla elegida no se puede usar en este dispositivo. Mientras tanto se aplica la combinación de arriba. Tu elección queda guardada.';

  @override
  String get settingsDoubleTapFallbackNoticeWindows =>
      'La tecla elegida no se puede usar ahora en Windows, porque Windows no permite observarla. Mientras tanto se aplica la combinación de arriba. Tu elección queda guardada.';

  @override
  String get settingsDoubleTapFallbackNoticeLinux =>
      'La tecla elegida no se puede usar en esta sesión de Linux, porque el escritorio no informa cuándo se suelta una tecla. Mientras tanto se aplica la combinación de arriba. Tu elección queda guardada.';

  @override
  String get settingsDoubleTapFallbackNoticeMac =>
      'La tecla elegida aún no se puede usar en el Mac, porque falta el permiso «Monitorización de entrada». Mientras tanto se aplica la combinación de arriba. Tu elección queda guardada y funciona en cuanto concedas el permiso y vuelvas a traer WhisPaste al frente.';

  @override
  String get settingsTriggerKeyUnsupportedFn => 'Solo disponible en Mac.';

  @override
  String get settingsTriggerKeyUnsupportedWayland =>
      'No disponible en Linux con Wayland.';

  @override
  String get settingsTriggerRightAltAltGr =>
      'En muchos teclados es AltGr para @ y €. En ese caso elige mejor otra tecla.';

  @override
  String get settingsSpeechRecognition => 'Reconocimiento de voz';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Calidad y servicio del reconocimiento de voz';

  @override
  String get settingsService => 'El reconocimiento se ejecuta en';

  @override
  String get settingsQuality => 'Velocidad y precisión';

  @override
  String get settingsRecordingSafety => 'Seguridad al grabar';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Comprobaciones y protecciones automáticas';

  @override
  String get settingsDeadMicTimeout => 'Detección de micrófono silencioso';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Detiene la grabación si no se detecta audio en este tiempo (segundos). 0 = desactivado.';

  @override
  String get settingsAutoStopSilence => 'Parar tras silencio';

  @override
  String get settingsAutoStopSilenceHint =>
      'Para automáticamente tras este número de segundos de silencio (después de hablar). 0 = desactivado.';

  @override
  String get settingsEnabled => 'Activado';

  @override
  String get settingsStyle => 'Estilo';

  @override
  String get settingsMicSystemDefault => 'Predeterminado del sistema';

  @override
  String get settingsMicSystemHint =>
      'La entrada de audio la gestionan los ajustes de tu sistema';

  @override
  String get settingsMicNoDeviceHint =>
      'No se encontró ningún dispositivo de entrada. Comprueba en la configuración del sistema que WhisPaste puede usar el micrófono.';

  @override
  String get settingsServiceOnDevicePrivate => 'En el dispositivo';

  @override
  String get settingsLanguageAutoDetect => 'Detección automática';

  @override
  String get settingsLanguageEnglish => 'Inglés';

  @override
  String get settingsLanguageGerman => 'Alemán';

  @override
  String get settingsLanguageFrench => 'Francés';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageHebrew => 'Hebreo';

  @override
  String get settingsSoundFeedback => 'Sonido y avisos';

  @override
  String get settingsSoundFeedbackSubtitle =>
      'Sonidos para los eventos de grabación';

  @override
  String get settingsSoundsEnabled => 'Sonidos';

  @override
  String get settingsRecordStartSound => 'Sonido al empezar a grabar';

  @override
  String get settingsRecordStopSound => 'Sonido al parar la grabación';

  @override
  String get settingsTranscriptionCompleteSound =>
      'Sonido al terminar la transcripción';

  @override
  String get settingsDurationWarningSound => 'Aviso de límite de duración';

  @override
  String get settingsSoundVolume => 'Volumen de los sonidos';

  @override
  String get settingsAfterTranscription => 'Tras la transcripción';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'Qué pasa con el texto transcrito';

  @override
  String get settingsAfterTranscriptionActionLabel => 'Después de grabar';

  @override
  String get settingsAfterTranscriptionClipboard => 'Copiar al portapapeles';

  @override
  String get settingsAfterTranscriptionPaste => 'Auto-Paste en el cursor';

  @override
  String get settingsAfterTranscriptionBoth => 'Copiar y Auto-Paste';

  @override
  String get settingsAfterTranscriptionNothing => 'No hacer nada';

  @override
  String get pasteFailurePermissionMissing =>
      'El sistema bloqueó el Auto-Paste. WhisPaste necesita permiso para insertar texto en otras apps; macOS lo llama «Accesibilidad».';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Paste omitido: no se capturó ninguna ventana de destino. Enfoca la app de destino antes de iniciar una grabación.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Paste bloqueado: la app de destino se ejecuta con derechos de administrador. Reinicia WhisPaste como administrador para pegar en esa app.';

  @override
  String pasteFailureGeneric(String paste) {
    return 'El Auto-Paste falló. La transcripción está en el portapapeles; pégala manualmente con $paste.';
  }

  @override
  String get pasteFailureOpenSettings => 'Abrir ajustes';

  @override
  String get pendingAudioSaveLater =>
      'No se pudo guardar la grabación. El archivo de audio se conserva y WhisPaste lo vuelve a intentar la próxima vez que se inicie.';

  @override
  String get pendingAudioRecovered =>
      'Una grabación que antes no se pudo guardar ya está en Grabaciones.';

  @override
  String get pendingAudioInterruptedDiscarded =>
      'No se pudo procesar una grabación interrumpida y se borró.';

  @override
  String get pasteNotificationNoTargetTitle => 'WhisPaste: Auto-Paste omitido';

  @override
  String get pasteNotificationNoTargetBody =>
      'No se detectó ninguna app de destino. Enfoca primero la app de destino y luego inicia la grabación. El texto está en el portapapeles.';

  @override
  String get pasteNotificationNoTargetTray =>
      'Auto-Paste: falta la app de destino';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: sin señal del micrófono';

  @override
  String get silentMicrophoneNotificationBody =>
      'El micrófono no capta sonido. Comprueba el micrófono seleccionado o si está silenciado. La grabación sigue en curso.';

  @override
  String get pasteNotificationRestartNeededTitle =>
      'WhisPaste: hace falta reiniciar';

  @override
  String get pasteNotificationRestartNeededBody =>
      'El permiso se ha concedido, pero WhisPaste sigue con el estado anterior. Haz clic aquí para reiniciar WhisPaste.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'Auto-Paste bloqueado: hace falta reiniciar';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: Auto-Paste bloqueado';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'WhisPaste necesita permiso para insertar texto en otras apps; macOS lo llama «Accesibilidad». Haz clic aquí: WhisPaste borrará una entrada posiblemente obsoleta y dejará que macOS vuelva a preguntar.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'WhisPaste necesita permiso para insertar texto en otras apps; macOS lo llama «Accesibilidad». Haz clic aquí o en el icono de la bandeja para abrir Ajustes del Sistema.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'Auto-Paste bloqueado: abrir Ajustes del Sistema';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: Auto-Paste bloqueado';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'La app de destino se ejecuta con derechos de administrador. Reinicia también WhisPaste como administrador para pegar en esa app.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'Auto-Paste bloqueado: hace falta administrador';

  @override
  String get pasteNotificationFailedTitle => 'WhisPaste: el Auto-Paste falló';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'El sistema bloqueó la tecla de pegar. El texto está en el portapapeles. Pégalo tú con $paste.';
  }

  @override
  String get pasteNotificationFailedTray => 'Error en Auto-Paste';

  @override
  String get pasteNotificationClipboardHint =>
      'El texto está en el portapapeles.';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'WhisPaste aún no puede usar el teclado virtual /dev/uinput. El texto está en el portapapeles; pégalo con $paste. Haz clic aquí para configurarlo.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'Auto-Paste bloqueado: hace falta configurarlo';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'Auto-Paste no está disponible: en este sistema falta el teclado virtual que necesita. El texto está en el portapapeles; pégalo con $paste. Haz clic aquí para abrir los ajustes de Auto-Paste.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray => 'Auto-Paste no disponible';

  @override
  String get pasteCapabilityCheckTitle => 'Un momento…';

  @override
  String get pasteCapabilityReady => 'Todo listo';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Tu texto aparece justo en el cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Sin permiso todavía';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Paste no está disponible en esta plataforma';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'Auto-Paste no es posible aquí ahora';

  @override
  String get pasteCapabilityTestButton => 'Probar ahora';

  @override
  String get pasteCapabilityGrantButton => 'Continuar';

  @override
  String get pasteCapabilityWhyMac =>
      'WhisPaste necesita permiso para escribir texto en la app en la que estás trabajando; macOS lo llama «Accesibilidad».';

  @override
  String get pasteCapabilityTroubleshoot => '¿Tienes problemas?';

  @override
  String get pasteCapabilityRepairHint =>
      'A veces macOS recuerda una entrada antigua y olvida la nueva autorización. Restablece la entrada. Así macOS volverá a preguntarte correctamente.';

  @override
  String get pasteCapabilityRepairButton => 'Restablecer entrada';

  @override
  String get pasteCapabilityRestartButton => 'Reiniciar WhisPaste';

  @override
  String get pasteCapabilityRestartTitle => 'Casi listo: reinicia WhisPaste';

  @override
  String get pasteCapabilityRestartBody =>
      'Si activaste el permiso, macOS solo lo aplica a una app recién iniciada. Con un clic, WhisPaste se cierra y vuelve a abrirse enseguida.';

  @override
  String get pasteRestartAlertTitle => 'Reiniciar WhisPaste ahora';

  @override
  String get pasteRestartAlertBody =>
      'El permiso de Auto-Paste está activado, pero macOS solo lo aplica tras un reinicio. WhisPaste se cerrará y volverá a abrirse enseguida.';

  @override
  String get pasteRestartAlertConfirm => 'Reiniciar ahora';

  @override
  String get pasteStaleEntryGuideTitle =>
      'Quitar la entrada antigua de WhisPaste';

  @override
  String get pasteStaleEntryGuideBody =>
      'macOS todavía conserva el permiso de Auto-Paste de una versión anterior de WhisPaste. Esa entrada no se puede activar: hay que quitarla una vez:\n\n1. Selecciona «WhisPaste» en la lista.\n2. Haz clic en «−» debajo de la lista.\n3. Vuelve a WhisPaste.\n\nTras reiniciar, macOS te lo volverá a preguntar: simplemente permítelo.';

  @override
  String get pasteStaleEntryGuideConfirm => 'Abrir Ajustes del Sistema';

  @override
  String get pasteStaleEntryRestartTitle => 'Reiniciar WhisPaste';

  @override
  String get pasteStaleEntryRestartBody =>
      'Cuando hayas quitado la entrada antigua, reinicia WhisPaste. macOS volverá a pedir el permiso: confírmalo y activa WhisPaste.';

  @override
  String get pasteStaleEntryRestartConfirm => 'Reiniciar WhisPaste';

  @override
  String get permissionAlertLaterButton => 'Ahora no';

  @override
  String get micGateAlertTitle => 'Falta el acceso al micrófono';

  @override
  String get micGateAlertBody =>
      'WhisPaste no puede grabar sin acceso al micrófono. Confirma para abrir Ajustes del Sistema → Privacidad y seguridad → Micrófono y activa el interruptor de WhisPaste. WhisPaste detecta tu autorización automáticamente.';

  @override
  String get micGateAlertBodyGeneric =>
      'WhisPaste no puede grabar sin acceso al micrófono. Permite el acceso al micrófono para WhisPaste en los ajustes de privacidad de tu sistema. WhisPaste detecta tu autorización automáticamente.';

  @override
  String get micGateAlertConfirm => 'Abrir ajustes';

  @override
  String get micGateRestartAlertTitle => 'Reinicia WhisPaste para terminar';

  @override
  String get micGateRestartAlertBody =>
      'El acceso al micrófono está concedido, pero esta instancia de WhisPaste todavía no lo puede usar. WhisPaste se cerrará y volverá a abrirse enseguida; todo lo demás se mantiene igual.';

  @override
  String get micGateRestartAlertConfirm => 'Reiniciar ahora';

  @override
  String get autoPasteGateAlertTitle => 'Falta un interruptor para Auto-Paste';

  @override
  String get autoPasteGateAlertBody =>
      'WhisPaste inserta tu texto justo en el cursor. Para ello macOS necesita un interruptor que solo tú puedes activar: Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Confirma para abrir exactamente esa página. WhisPaste detecta tu autorización automáticamente y, si hace falta, se reinicia después.';

  @override
  String get autoPasteGateAlertConfirm => 'Abrir Ajustes del Sistema';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'El reinicio no aplicó el permiso';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'Vuelve a abrir el permiso y comprueba en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad que WhisPaste esté realmente activado. Vuelve a activar el interruptor y WhisPaste se reiniciará una vez más.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminaron $count entradas obsoletas. Prueba Auto-Paste una vez para ver peticiones nuevas.',
      one:
          'Se eliminó 1 entrada obsoleta. Prueba Auto-Paste una vez para ver una petición nueva.',
      zero: 'No se encontraron entradas obsoletas. Prueba Auto-Paste una vez.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'No se encontró ninguna entrada antigua. Es probable que un reinicio ayude ahora.';

  @override
  String get pasteCapabilityRepairFailed =>
      'No se pudo ejecutar el restablecimiento de permisos de macOS. Prueba a quitar WhisPaste manualmente de Ajustes del Sistema → Accesibilidad.';

  @override
  String get onboardingPermissionsTitle =>
      'Lo que WhisPaste necesita en tu ordenador.';

  @override
  String get onboardingPermissionsTitleDone => 'Todo listo.';

  @override
  String get onboardingPermissionsSubtitle =>
      'WhisPaste solo lo usa mientras dictas.';

  @override
  String get onboardingPermMicTitle => 'Usar el micrófono';

  @override
  String get onboardingPermMicBody => 'Para que WhisPaste oiga lo que dictas.';

  @override
  String get onboardingPermMicDenied =>
      'Aún no está permitido. Sin micrófono no se puede dictar, pero puedes permitirlo más tarde.';

  @override
  String get onboardingPermPasteTitle => 'Insertar el texto directamente';

  @override
  String get onboardingPermPasteBody =>
      'Tu dictado aparece donde estás escribiendo, en cualquier app.';

  @override
  String get onboardingPermPasteMacNote =>
      'macOS llama a este permiso «Accesibilidad».';

  @override
  String get onboardingPermSkipTitle => '¿Continuar sin permiso?';

  @override
  String get onboardingPermSkipMic =>
      'Sin micrófono, WhisPaste no puede dictar.';

  @override
  String onboardingPermSkipPaste(String shortcut) {
    return 'Sin «Insertar el texto directamente», WhisPaste solo copia el texto y tú lo pegas con $shortcut.';
  }

  @override
  String get onboardingPermSkipLater => 'Puedes hacerlo más tarde en Ajustes.';

  @override
  String get onboardingPermSkipConfirm => 'Continuar de todos modos';

  @override
  String get onboardingPermSkipCancel => 'Permitir ahora';

  @override
  String onboardingPermPasteWithout(String shortcut) {
    return 'Sin este permiso, WhisPaste copia el texto y tú lo pegas con $shortcut.';
  }

  @override
  String get onboardingPasteTitle => 'Para que el texto llegue donde escribes';

  @override
  String get onboardingPasteSubtitle =>
      'macOS te preguntará en un momento si WhisPaste puede hacerlo. Di que sí, y listo.';

  @override
  String get onboardingPasteSubtitleWin =>
      'En Windows no hace falta ningún permiso: solo decide si WhisPaste debe insertar el texto por ti.';

  @override
  String get onboardingPasteSubtitleLinux =>
      'En Linux no aparece ningún cuadro de diálogo del sistema. Abajo se indica si hay que configurar algo para ello.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste listo';

  @override
  String get onboardingPasteChipPending => 'Acceso a Auto-Paste pendiente';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: hay que actuar';

  @override
  String get onboardingPasteSkip => 'Solo copiar, sin Auto-Paste';

  @override
  String get onboardingPasteWhyMac =>
      'Sin permiso, tu texto se copia al portapapeles. Después lo pegarás manualmente con ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'Tras cada grabación, Auto-Paste pulsa Ctrl+V por ti, así el texto aparece justo donde estás escribiendo. Comprobado que funciona en este equipo; actívalo abajo.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'En programas que se ejecutan como administrador, Auto-Paste no funciona. El texto se queda en el portapapeles y lo pegas tú con Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'Auto-Paste está activado';

  @override
  String get onboardingPasteWinOnDetail =>
      'Tras cada grabación, WhisPaste pulsa Ctrl+V por ti: el texto aparece justo en el cursor. Además, una copia se queda en el portapapeles.';

  @override
  String get onboardingPasteLinuxNative =>
      'Auto-Paste necesita tu permiso para el teclado virtual. Con el paquete .deb, elige «Permitir (contraseña de administrador)» e introduce tu contraseña de administrador; si no, copia el comando y ejecútalo una vez en una terminal. Puedes quitar el permiso en los ajustes.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'En la versión Flatpak (--device=all), los dispositivos de entrada del equipo son visibles dentro del sandbox. WhisPaste no lee ninguna entrada. Si tu usuario puede leer esos dispositivos (p. ej., como miembro del grupo input), la app podría leer las pulsaciones de otros programas. Auto-Paste necesita además un comando único: cópialo y ejecútalo una vez en una terminal (pide contraseña de administrador y cambia el sistema). Si no quieres esto, deja Auto-Paste desactivado y pega el texto a mano.';

  @override
  String get onboardingPasteLinuxSnap =>
      'En la versión Snap, ejecuta esto una vez en una terminal: sudo snap connect whispaste:uinput. Hasta entonces, Auto-Paste solo copia el texto.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'Auto-Paste necesita un permiso único para el teclado virtual. Copia el comando y ejecútalo una vez en una terminal. Escribe la regla udev 71-whispaste-uinput.rules, necesita derechos de administrador y cambia el sistema: echo \'KERNEL==\"uinput\", SUBSYSTEM==\"misc\", TAG+=\"uaccess\"\' | sudo tee /etc/udev/rules.d/71-whispaste-uinput.rules && sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. El permiso solo vale para tu sesión iniciada. Hasta entonces, Auto-Paste solo copia el texto.';

  @override
  String get onboardingPasteWinEnableCta => 'Activar Auto-Paste';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'En programas que se ejecutan como administrador, Auto-Paste no funciona. El texto se queda en el portapapeles y lo pegas tú con Ctrl+V.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'Auto-Paste está activado. Hasta que configures el acceso, WhisPaste deja el texto en el portapapeles y lo pegas tú con Ctrl+V.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'El texto va al portapapeles. Pégalo con $shortcut.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Activa el interruptor junto a WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Los Ajustes del Sistema están abiertos. Busca WhisPaste en la lista y actívalo.';

  @override
  String get onboardingAccessRemoveReAddHint =>
      '¿El interruptor no surte efecto? Quita WhisPaste de la lista y añádelo de nuevo.';

  @override
  String get settingsOverlayFloatingButton => 'Overlay de grabación';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Controla cómo se muestra el estado de la grabación mientras grabas';

  @override
  String get settingsShowOverlay => 'Visualización del estado de la grabación';

  @override
  String get settingsShowOverlaySubtitle =>
      'Elige dónde aparecen los avisos en directo mientras grabas';

  @override
  String get settingsOverlayModeFloating => 'Flotante (siempre visible)';

  @override
  String get settingsOverlayModeOff => 'Desactivado';

  @override
  String get settingsOverlayStartPosition => 'Posición inicial del overlay';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Dónde aparece el overlay de grabación al empezar a grabar';

  @override
  String get settingsOverlayStartTopCenter => 'Centro superior';

  @override
  String get settingsOverlayStartBottomCenter => 'Centro inferior';

  @override
  String get settingsOverlayStartLastPosition => 'Recordar la última posición';

  @override
  String get settingsShowFloatingButton => 'Botón flotante';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Botón pequeño siempre visible para iniciar o detener la grabación desde cualquier app';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsRecognitionLanguage => 'Idioma de reconocimiento';

  @override
  String get settingsCustomVocabulary => 'Vocabulario personalizado';

  @override
  String get settingsCustomVocabularyHint =>
      'Nombres y términos técnicos: mejora la precisión del reconocimiento';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'p. ej. WhisPaste, Kubernetes, Dr. Müller';

  @override
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return '~$count de $budget en uso';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Si la lista ocupa más de $budget, el resto se omite automáticamente.';
  }

  @override
  String get settingsPunctuationPriming => 'Preparación de la puntuación';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Hace que la transcripción ponga más signos de puntuación si no hay un vocabulario personalizado. La velocidad no cambia.';

  @override
  String get settingsVadEnabled => 'Recortar el silencio final';

  @override
  String get settingsVadEnabledSubtitle =>
      'Recorta el silencio largo y el ruido al final de una grabación, para que la transcripción no invente una frase de cierre (p. ej., «Gracias por ver el vídeo»).';

  @override
  String get settingsStripPunctuation => 'Quitar la puntuación';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Quita puntos, comas y otros signos de puntuación de cada transcripción antes de guardarla o pegarla. Los números como 3,5 no cambian. Funciona igual con todos los métodos de reconocimiento.';

  @override
  String get settingsNumericOnlyMode => 'Solo números';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Convierte los números hablados (en alemán e inglés) en cifras, p. ej. «five point two» pasa a ser «5.2». Deja la transcripción intacta si no se puede convertir por completo.';

  @override
  String get settingsRemoveFillerWords => 'Quitar muletillas';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'Elimina sonidos de duda como «uh», «um» o «erm» antes de guardar o pegar la transcripción. Solo muletillas inequívocas en inglés y alemán; las palabras con significado nunca se tocan.';

  @override
  String get settingsVoiceLineBreaks => 'Saltos de línea por voz';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'Convierte comandos hablados como «nuevo párrafo» y «nueva línea» en saltos de línea reales. Usa el idioma de la transcripción o, con detección automática, todos los idiomas compatibles.';

  @override
  String get settingsSpokenPunctuation => 'Puntuación por voz';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'Si dices «coma» o «punto» como palabra dentro de una frase, revisa el texto después.';

  @override
  String get settingsWrittenForms => 'Formas escritas';

  @override
  String get settingsWrittenFormsSubtitle =>
      'Escribe de la forma habitual las direcciones de correo, las webs, las fechas, las horas y los importes de dinero que dictas: «john at gmail dot com» pasa a ser john@gmail.com. Solo alemán e inglés. Cada tipo se puede desactivar por separado.';

  @override
  String get settingsWrittenFormEmail => 'Direcciones de correo';

  @override
  String get settingsWrittenFormUrl => 'Direcciones web';

  @override
  String get settingsWrittenFormDate => 'Fechas';

  @override
  String get settingsWrittenFormTime => 'Horas';

  @override
  String get settingsWrittenFormMoney => 'Importes de dinero';

  @override
  String get settingsAppLanguage => 'Idioma de la app';

  @override
  String get settingsSttModels => 'Modelos de voz';

  @override
  String get settingsOpenAiApiKey => 'Clave API de OpenAI';

  @override
  String get settingsDeepgramApiKey => 'Clave API de Deepgram';

  @override
  String get settingsToggleApiKeyVisibility => 'Mostrar u ocultar la clave API';

  @override
  String get settingsAdvanced => 'Avanzado';

  @override
  String get settingsAdvancedSubtitle =>
      'Restablecer, informes de errores, actualizaciones y comportamiento del sistema';

  @override
  String get settingsResetToDefaults => 'Restaurar predeterminados';

  @override
  String get settingsResetTitle => 'Restablecer ajustes';

  @override
  String get settingsResetMessage =>
      'Todos los ajustes volverán a sus valores predeterminados. Las claves API se eliminarán. Esta acción no se puede deshacer.';

  @override
  String get settingsResetConfirm => 'Restablecer';

  @override
  String get settingsResetSuccess =>
      'Ajustes restablecidos a los valores predeterminados';

  @override
  String get settingsFactoryReset => 'Restablecer todo';

  @override
  String get settingsFactoryResetTitle => 'Restablecer de fábrica';

  @override
  String get settingsFactoryResetMessage =>
      'Esto elimina de inmediato: transcripciones con sus etiquetas y notas, archivos de audio guardados, Diccionario, Snippets, Estadísticas, claves de API, modelos descargados, registros y ajustes. La aplicación volverá a su estado inicial.\n\nLa aplicación no puede recuperar nada de ello. Los archivos se borran con un borrado normal y no se sobrescriben, así que herramientas especializadas podrían recuperar partes.';

  @override
  String get settingsFactoryResetConfirm => 'Eliminar todo';

  @override
  String get settingsFactoryResetSuccess =>
      'La app se ha restablecido por completo';

  @override
  String get settingsFactoryResetProgressTitle => 'Restableciendo WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Deteniendo el modelo de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Eliminando los modelos de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio =>
      'Eliminando grabaciones…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase =>
      'Eliminando la base de datos…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Borrando credenciales…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Restaurando los ajustes predeterminados…';

  @override
  String settingsFactoryResetFailedMessage(String areas) {
    return 'El restablecimiento no está completo. Afectado: $areas. Puedes volver a intentarlo.';
  }

  @override
  String get factoryResetAreaDb =>
      'Transcripciones, Notas, Diccionario, Snippets y Estadísticas';

  @override
  String get factoryResetAreaAudio => 'Archivos de audio';

  @override
  String get factoryResetAreaModels => 'Modelos y registros';

  @override
  String get factoryResetAreaSecure => 'Claves de API';

  @override
  String get factoryResetAreaSettings => 'Ajustes';

  @override
  String get factoryResetAreaProcess => 'Proceso en segundo plano';

  @override
  String get factoryResetRetryAction => 'Reintentar';

  @override
  String get factoryResetKeyringHint =>
      'No se pudieron quitar las claves de API del llavero. Si hace falta, borra tú mismo las entradas que empiezan por «wp_» en el gestor de contraseñas del sistema.';

  @override
  String get settingsPortabilitySectionTitle => 'Copia y transferencia';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'Guarda una copia de tu configuración de WhisPaste o llévala a otro ordenador';

  @override
  String get settingsPortabilityExportAction => 'Exportar';

  @override
  String get settingsPortabilityImportAction => 'Importar';

  @override
  String get settingsPortabilityExportLocationLabel =>
      'Destino de la exportación';

  @override
  String get settingsPortabilityImportLocationLabel =>
      'Origen de la importación';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'Se te preguntará en la primera exportación';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'Se te preguntará en la primera importación';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'Elegir otro destino de exportación (todavía no se ha exportado nada)';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'Elegir otro origen de importación (todavía no se ha importado nada)';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'Ajustes exportados a $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'Error al exportar: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle => '¿Importar ajustes?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'Esto sustituye tus ajustes actuales (incluidos la interfaz, la configuración del modelo de voz, el comportamiento, los reemplazos de texto y los snippets) por el contenido de $path. Tus claves API no se modifican.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'Ajustes importados desde $path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'No se encontró ningún archivo de exportación en $path. Exporta los ajustes primero o copia allí un archivo de exportación.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'Error al importar: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'Copia de seguridad automática';

  @override
  String get settingsAutosaveHint =>
      'Guarda tu configuración en la carpeta elegida unos segundos después de cada cambio';

  @override
  String get settingsAutosaveChooseFolder =>
      'Elegir otra carpeta para las copias automáticas (todavía no se ha hecho ninguna copia)';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'Última copia: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'Todavía no hay copias';

  @override
  String get settingsAutosaveLastRunFailed => 'La copia falló';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'El último intento falló; última copia: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'La copia automática falló: la carpeta elegida no está disponible.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'La copia automática falló: $reason';
  }

  @override
  String get groqRemovedToast =>
      'Se ha eliminado el proveedor en la nube que usabas. El reconocimiento de voz ahora se ejecuta en este dispositivo.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grabaciones migradas desde WhisPaste 1.x',
      one: '1 grabación migrada desde WhisPaste 1.x',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Desactivado';

  @override
  String get settingsOn => 'Activado';

  @override
  String get statusReady => 'Listo';

  @override
  String get statusRecording => 'Grabando…';

  @override
  String get statusTranscribing => 'Transcribiendo…';

  @override
  String get statusProcessing => 'Procesando…';

  @override
  String get statusTranscriptionDone => 'Transcripción completada';

  @override
  String get statusSelectionEdited => 'Selección editada';

  @override
  String get statusCopied => '¡Copiado!';

  @override
  String get statusLocal => 'Local';

  @override
  String get statusCloud => 'Nube';

  @override
  String get statusOnline => 'En línea';

  @override
  String get statusOffline => 'Sin conexión';

  @override
  String get recordingGuardFailed =>
      'No se detectó audio. Inténtalo de nuevo. A veces el micrófono necesita un momento para activarse.';

  @override
  String get recordingAutoStopped => 'Grabación detenida: silencio detectado.';

  @override
  String get actionCopy => 'Copiar';

  @override
  String get actionDuplicate => 'Duplicar';

  @override
  String get actionDelete => 'Eliminar';

  @override
  String get actionDismiss => 'Descartar';

  @override
  String get actionEdit => 'Editar';

  @override
  String get actionExport => 'Exportar';

  @override
  String get unsavedInputTitle => '¿Descartar los cambios?';

  @override
  String get unsavedInputMessage =>
      'El texto que escribiste aún no está guardado.';

  @override
  String get unsavedInputDiscard => 'Descartar';

  @override
  String get trayUnavailableMinimizedHint =>
      'El icono de la bandeja no está disponible. WhisPaste se minimizó y sigue en ejecución.';

  @override
  String get settingsSaveFailedToast =>
      'No se pudo guardar el ajuste. Se mantiene el valor anterior.';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionClose => 'Cerrar';

  @override
  String get actionConfirm => 'Confirmar';

  @override
  String get actionSave => 'Guardar';

  @override
  String get actionRetry => 'Reintentar';

  @override
  String get actionClearSearch => 'Borrar búsqueda';

  @override
  String get tooltipLanguage => 'Idioma';

  @override
  String aboutVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackHint => 'Cuéntanos qué opinas. Leemos cada mensaje.';

  @override
  String get analyticsPreviewBanner =>
      'Vista previa: se muestran datos de ejemplo. Las estadísticas reales aparecerán cuando empieces a grabar.';

  @override
  String get analyticsEmptyTitle => 'Aún no hay grabaciones';

  @override
  String get analyticsEmptySubtitle =>
      'Empieza a grabar para ver aquí tus estadísticas.';

  @override
  String get analyticsNoRecordingsInPeriod =>
      'No hay grabaciones en este período';

  @override
  String get analyticsOverview => 'Resumen';

  @override
  String get analyticsOverviewSubtitle =>
      'Tus estadísticas de grabación de un vistazo';

  @override
  String get analyticsActivity => 'Actividad';

  @override
  String get analyticsInsights => 'Análisis';

  @override
  String get analyticsTotalRecordings => 'Grabaciones totales';

  @override
  String get analyticsTotalDuration => 'Duración total';

  @override
  String get analyticsWordsDictated => 'Palabras transcritas';

  @override
  String get analyticsTimeSaved => 'Tiempo ahorrado (estimación)';

  @override
  String analyticsTimeSavedNote(int wpm) {
    return 'Estimación: escribir a $wpm palabras por minuto, menos el tiempo hablado';
  }

  @override
  String get analyticsAvgLatency => 'Tiempo medio hasta el texto';

  @override
  String get analyticsRecordingActivity => 'Actividad de grabación';

  @override
  String get analyticsLast7Days => 'Últimos 7 días';

  @override
  String get analyticsWeekEmpty => 'No hubo grabaciones en los últimos 7 días';

  @override
  String get analyticsModelUsage => 'Uso de modelos de voz';

  @override
  String get analyticsNoModelData =>
      'Todavía no hay datos de modelos en este periodo';

  @override
  String get analyticsLoading => 'Cargando estadísticas';

  @override
  String get analyticsDurationDistribution => 'Distribución de duración';

  @override
  String get analyticsCostSavings => 'Coste y ahorro';

  @override
  String get analyticsLocalSavings => 'Ahorro local';

  @override
  String get analyticsCloudCost => 'Coste en la nube';

  @override
  String get analyticsEstimateNote =>
      'Estimación según los precios de lista por transcripción';

  @override
  String get analyticsPeriod7d => '7 días';

  @override
  String get analyticsPeriod30d => '30 días';

  @override
  String get analyticsPeriod90d => '90 días';

  @override
  String get analyticsPeriodAll => 'Todo el tiempo';

  @override
  String get analyticsReset => 'Restablecer';

  @override
  String get analyticsResetTitle => 'Restablecer estadísticas';

  @override
  String get analyticsResetMessage =>
      '¿Seguro que quieres borrar todos los datos de estadísticas? Esta acción no se puede deshacer.';

  @override
  String get analyticsResetDone => 'Las estadísticas se han restablecido.';

  @override
  String get analyticsDayMon => 'Lun';

  @override
  String get analyticsDayTue => 'Mar';

  @override
  String get analyticsDayWed => 'Mié';

  @override
  String get analyticsDayThu => 'Jue';

  @override
  String get analyticsDayFri => 'Vie';

  @override
  String get analyticsDaySat => 'Sáb';

  @override
  String get analyticsDaySun => 'Dom';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta esta semana';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta frente al mes pasado';
  }

  @override
  String get analyticsDurationLt15s => '< 15 s';

  @override
  String get analyticsDuration15To30s => '15-30 s';

  @override
  String get analyticsDuration30To60s => '30-60 s';

  @override
  String get analyticsDuration1To3m => '1-3 min';

  @override
  String get analyticsDurationGt3m => '> 3 min';

  @override
  String analyticsSavedAmount(String amount) {
    return '$amount ahorrado';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount gastado';
  }

  @override
  String get replacementsSearch => 'Buscar reemplazos…';

  @override
  String get replacementsSearchFieldLabel => 'Buscar reemplazos';

  @override
  String get replacementsAdd => 'Añadir';

  @override
  String get replacementsEmpty => 'Aún no hay reemplazos';

  @override
  String get replacementsEmptyHint =>
      'Añade reemplazos para sustituir palabras automáticamente mientras grabas.\nEjemplo: «btw» → «by the way»';

  @override
  String get replacementsNoMatches => 'No hay coincidencias';

  @override
  String get replacementsNoMatchesHint =>
      'Prueba con otro término de búsqueda.';

  @override
  String get replacementsToggleLabel => 'Activar reemplazos';

  @override
  String get replacementsToggleEnabled => 'Los reemplazos están activos';

  @override
  String get replacementsToggleDisabled => 'Los reemplazos están desactivados';

  @override
  String get replacementsEnableBannerTitle =>
      'Los reemplazos están desactivados';

  @override
  String get replacementsEnableBannerHint =>
      'Actívalos para que las frases de activación se sustituyan automáticamente mientras grabas.';

  @override
  String get replacementsEnableAction => 'Activar';

  @override
  String get replacementsDisableAction => 'Desactivar';

  @override
  String get replacementsEditShortcut => 'Editar reemplazo';

  @override
  String get replacementsNewShortcut => 'Nuevo reemplazo';

  @override
  String get replacementsDialogHint =>
      'Cualquiera de las frases de activación se sustituirá automáticamente mientras grabas.';

  @override
  String get replacementsTriggerLabel => 'Frases de activación';

  @override
  String get replacementsTriggerHint => 'p. ej. btw';

  @override
  String get replacementsAddTrigger => 'Añadir frase de activación';

  @override
  String get replacementsMissingTrigger =>
      'Añade al menos una frase de activación.';

  @override
  String get replacementsRemoveTrigger => 'Quitar frase de activación';

  @override
  String get replacementsReplacementLabel => 'Texto de reemplazo';

  @override
  String get replacementsMissingReplacement => 'Escribe el texto de reemplazo.';

  @override
  String get replacementsReplacementHint => 'p. ej. by the way';

  @override
  String get replacementsReplacementHelper =>
      'Usa \\n para un salto de línea y \\n\\n para una línea en blanco. Para mantener una barra invertida y n como texto, escribe \\\\n.';

  @override
  String get replacementsDeleteTitle => 'Eliminar reemplazo';

  @override
  String replacementsDeleteMessage(String trigger) {
    return '¿Quitar el reemplazo «$trigger»? No se puede deshacer.';
  }

  @override
  String get replacementsImportFromFolder => 'Importar desde carpeta';

  @override
  String get replacementsImportHint =>
      'Analiza una carpeta de proyecto en busca de identificadores y añádelos como reemplazos aproximados. Nada sale de tu dispositivo.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return 'Encontrados $found, añadidos $added, omitidos $skipped duplicado(s)';
  }

  @override
  String get replacementsImportScanning =>
      'Analizando la carpeta; en proyectos grandes puede tardar un momento…';

  @override
  String get replacementsImportError =>
      'No se pudo importar: la carpeta no se pudo analizar.';

  @override
  String get replacementsImportedBadge => 'Importado';

  @override
  String get replacementsLearnedBadge => 'Aprendido';

  @override
  String get correctionLearningToggleLabel => 'Aprender de las correcciones';

  @override
  String get correctionLearningToggleEnabled =>
      'Observando correcciones repetidas para hacer sugerencias';

  @override
  String get correctionLearningToggleDisabled =>
      'No se observan correcciones para hacer sugerencias';

  @override
  String get correctionLearningHowTo =>
      'Mientras grabas una nota en las grabaciones, di «correct: …» (o «korrektur: …») seguido del texto corregido para sobrescribirla. Si corriges lo mismo dos veces, WhisPaste lo ofrece aquí como reemplazo automático.';

  @override
  String get correctionCandidatesCardTitle => 'Basado en tus correcciones';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count sugerencia(s) de correcciones que repetiste: revísalas antes de convertirlas en reemplazos.';
  }

  @override
  String get correctionCandidatesReviewButton => 'Revisar';

  @override
  String get correctionCandidatesReviewTitle =>
      'Revisar correcciones aprendidas';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    return '$count corrección(es) que repetiste: acepta las que WhisPaste debe aplicar automáticamente a partir de ahora. No cambia nada hasta que confirmes.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return 'Se han añadido $added reemplazo(s) aprendido(s)';
  }

  @override
  String get replacementsImportNothingFound =>
      'No se encontraron identificadores nuevos en esta carpeta.';

  @override
  String get replacementsSymbolPackAction => 'Añadir plantillas de símbolos';

  @override
  String get replacementsSymbolPackHint =>
      'Añade reemplazos para símbolos que puedes dictar, como «open bracket» para (. Los disparadores existentes no cambian.';

  @override
  String replacementsSymbolPackAdded(int count) {
    return 'Reglas de símbolos añadidas: $count';
  }

  @override
  String get replacementsSymbolPackNothingNew =>
      'Las plantillas de símbolos ya están.';

  @override
  String get replacementsImportReviewTitle => 'Elige qué importar';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return 'Se encontraron $count candidatos: elige cuáles se convierten en reemplazos. No se añade nada hasta que confirmes.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'Filtrar candidatos';

  @override
  String get replacementsImportReviewSelectAllFiltered =>
      'Seleccionar lo visible';

  @override
  String get replacementsImportReviewDeselectAll => 'Deseleccionar todos';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return '$selected de $total seleccionados';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'Ningún candidato coincide con el filtro.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'Importar seleccionados ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'Coincidencia';

  @override
  String get replacementsMatchModeExact => 'Exacta';

  @override
  String get replacementsMatchModeFuzzy => 'Similar';

  @override
  String get replacementsFuzzyToleranceLabel => 'Tolerancia';

  @override
  String get replacementsFuzzyToleranceStrict => 'Estricta';

  @override
  String get replacementsFuzzyToleranceStandard => 'Estándar';

  @override
  String get replacementsFuzzyToleranceTolerant => 'Flexible';

  @override
  String get replacementsFuzzyToleranceHint =>
      'Cuánto debe parecerse una frase hablada a una frase de activación para contar como coincidencia. Estricta solo detecta formulaciones casi idénticas, así que casi nunca reemplaza algo por error, pero una frase mal pronunciada puede pasar sin detectarse. Estándar es un valor equilibrado para el uso diario. Flexible también detecta pronunciaciones o formulaciones bastante distintas, con más riesgo de reemplazar algo que no querías.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Las frases de activación de menos de $minLength caracteres no pueden usar la coincidencia similar: darían demasiados falsos positivos.';
  }

  @override
  String replacementsSingleSymbolTriggerHint(String smiley, String ellipsis) {
    return 'Un solo signo de puntuación nunca se sustituye. Usa al menos dos caracteres, p. ej. «$smiley» o «$ellipsis».';
  }

  @override
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'La frase de activación «$trigger» ya existe (reemplazo: «$replacement»).';
  }

  @override
  String get snippetsSearch => 'Buscar snippets…';

  @override
  String get snippetsSearchFieldLabel => 'Buscar snippets';

  @override
  String get snippetsAdd => 'Añadir';

  @override
  String get snippetCopySuffix => '(copia)';

  @override
  String get snippetsEmpty => 'Aún no hay snippets';

  @override
  String get snippetsEmptyHint =>
      'Añade un snippet para reutilizar rápidamente un bloque de texto, como una firma o una respuesta tipo.';

  @override
  String get snippetsNoMatches => 'No hay coincidencias';

  @override
  String get snippetsNoMatchesHint => 'Prueba con otro término de búsqueda.';

  @override
  String get snippetsEditSnippet => 'Editar snippet';

  @override
  String get snippetsNewSnippet => 'Nuevo snippet';

  @override
  String get snippetsDialogHint =>
      'Abre el selector de snippets mientras grabas para insertar este texto.';

  @override
  String get snippetsTitleLabel => 'Título';

  @override
  String get snippetsTitleHint => 'p. ej. Firma de correo';

  @override
  String get snippetsBodyLabel => 'Contenido';

  @override
  String get snippetsBodyHint => 'El texto que inserta este snippet…';

  @override
  String get snippetsKindLabel => 'Tipo';

  @override
  String get snippetsKindStatic => 'Estático';

  @override
  String get snippetsKindInteractive => 'Interactivo';

  @override
  String get snippetsFieldsLabel => 'Campos';

  @override
  String get snippetsFieldsHint =>
      'Se te guiará por cada campo con su propia grabación corta, en este orden.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'Nombre del campo $number';
  }

  @override
  String get snippetsFieldMoveUp => 'Mover campo arriba';

  @override
  String get snippetsFieldMoveDown => 'Mover campo abajo';

  @override
  String get snippetsFieldRemove => 'Quitar campo';

  @override
  String get snippetsFieldAdd => 'Añadir campo';

  @override
  String get snippetsFieldInsertIntoTemplate => 'Insertar en la plantilla';

  @override
  String snippetsFieldsMinWarning(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min campos con nombre',
      one: '1 campo con nombre',
    );
    return 'Un snippet interactivo necesita al menos $_temp0.';
  }

  @override
  String get snippetsTemplateLabel => 'Plantilla';

  @override
  String get snippetsTemplateHint =>
      'Escribe el texto del snippet y usa el botón de insertar de cada campo para colocarlo donde quieras.';

  @override
  String get snippetsTemplateFieldHint =>
      'Escribe aquí tu texto e inserta campos con los botones de arriba.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'Todavía no aparecen todos los campos en la plantilla: su texto quedaría sin usar.';

  @override
  String get snippetsSaveMissingTitle => 'Falta el título';

  @override
  String get snippetsSaveMissingBody => 'Falta el texto';

  @override
  String get snippetsFieldsDuplicateWarning =>
      'Cada campo necesita un nombre distinto.';

  @override
  String get snippetsInteractiveBadge => 'Interactivo';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campos',
      one: '1 campo',
    );
    return '$_temp0 · Intro para empezar';
  }

  @override
  String interactiveSnippetBriefingHint(String name) {
    return 'Campo 1: $name · Esc: cancelar';
  }

  @override
  String interactiveSnippetAnnounceLabel(int index, int count, String name) {
    return 'Campo $index/$count: $name';
  }

  @override
  String get interactiveSnippetAnnounceHint => 'Prepárate para hablar…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'Siguiente';

  @override
  String interactiveSnippetSentenceLabel(String names) {
    return 'En una frase: $names';
  }

  @override
  String get interactiveSnippetAssigningLabel => 'Asignando los campos…';

  @override
  String get interactiveSnippetAssigningHint => 'Esc: cancelar';

  @override
  String get snippetsDeleteTitle => 'Eliminar snippet';

  @override
  String snippetsDeleteMessage(String title) {
    return '¿Eliminar el snippet «$title»? No se puede deshacer.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Palabra de activación del selector';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Di solo esta palabra para abrir el selector de snippets. Déjalo vacío para desactivar el selector.';

  @override
  String get snippetsPickerTriggerHint => 'p. ej. snippet';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'La palabra de activación está definida, pero aún no hay snippets: decirla inserta la palabra como texto normal hasta que añadas el primero.';

  @override
  String get snippetsPickerSettingsLink =>
      'Palabra de activación y atajo en Ajustes';

  @override
  String get snippetsPickerHotkeyLabel => 'Atajo del selector';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Abre el selector directamente: la segunda forma de llegar al mismo panel.';

  @override
  String get snippetsPickerHotkeyOff =>
      'El atajo del selector está desactivado.';

  @override
  String get snippetsPickerHotkeyEnable => 'Activar atajo';

  @override
  String get snippetsPickerUnavailable =>
      'El selector de snippets todavía no está disponible en esta plataforma.';

  @override
  String get snippetsPickerSemanticsLabel => 'Selector de snippets';

  @override
  String get snippetsPickerInsertAction => 'Insertar';

  @override
  String get snippetsPickerSentenceAction => 'En una frase';

  @override
  String get snippetsPickerSentenceTooltip =>
      'Dictar todos los campos en una frase';

  @override
  String snippetFieldPreviewAnnounce(int filled, int total) {
    return 'Vista previa: $filled de $total campos reconocidos';
  }

  @override
  String snippetFieldPreviewConfirmEmpty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campos vacíos · Enter inserta igualmente',
      one: '1 campo vacío · Enter inserta igualmente',
    );
    return '$_temp0';
  }

  @override
  String get snippetFieldPreviewEmpty => 'vacío';

  @override
  String get snippetFieldPreviewNextField => 'Campo siguiente';

  @override
  String get snippetFieldPreviewResult => 'Resultado';

  @override
  String snippetFieldPreviewNoModelHint(String example) {
    return 'Sin modelo de texto, WhisPaste reconoce los campos solo por su nombre. Dilos también, por ejemplo: $example';
  }

  @override
  String get aboutTagline => 'Voz a texto, al instante.';

  @override
  String get aboutWhatsNew => 'Novedades';

  @override
  String get aboutReportIssue => 'Informar de un problema';

  @override
  String get aboutSupportTitle => 'Apoya este proyecto';

  @override
  String get aboutSupportDescription =>
      'WhisPaste es gratis y de código abierto bajo la licencia MIT. Los patrocinios cubren costes fijos recurrentes reales (Apple Developer Program, Microsoft Partner Center y alojamiento y dominio) que lo mantienen disponible en todas las plataformas.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Dale una estrella en GitHub';

  @override
  String get aboutSponsorsTitle => 'Patrocinadores';

  @override
  String get supportPromptRecurringTitle => '¿Lo hacemos mensual?';

  @override
  String get supportPromptRecurringDescription =>
      'Gracias por apoyar WhisPaste antes. Si quieres, puedes convertirlo en un pequeño patrocinio mensual que siga cubriendo nuestros costes fijos recurrentes.';

  @override
  String get aboutBuiltWith => 'Creado con';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Interfaz multiplataforma con Flutter. Reconocimiento de voz local con whisper.cpp y Parakeet.';

  @override
  String get aboutWhisper => 'whisper.cpp y OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Reconocimiento de voz local y en la nube: rápido, preciso y multilingüe (99 idiomas).';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet y sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Reconocimiento de voz local, acelerado por GPU donde está disponible (Metal, Vulkan, CUDA) y por CPU en el resto (~25 idiomas).';

  @override
  String get aboutParakeetModelCredit =>
      'Modelo: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'Conversión GGUF: ggml-org, MIT';

  @override
  String get aboutLinks => 'Enlaces';

  @override
  String get helpLegalTitle => 'Aviso legal';

  @override
  String get helpDiagnosticsPublicNote =>
      'Las incidencias de GitHub son públicas. Revisa el informe antes de pegarlo.';

  @override
  String get helpDiagnosticsBuilding => 'Creando el informe …';

  @override
  String get tabsScrollBack => 'Mostrar pestañas anteriores';

  @override
  String get tabsScrollForward => 'Mostrar más pestañas';

  @override
  String get aboutWebsite => 'Sitio web';

  @override
  String get aboutGitHubRepo => 'Repositorio en GitHub';

  @override
  String get aboutFollowOnX => 'Síguenos en X';

  @override
  String get aboutMitLicense => 'Licencia MIT';

  @override
  String get aboutThirdPartyLicenses => 'Licencias de terceros';

  @override
  String get aboutThirdPartyLicensesDetail => 'Fuentes y modelos';

  @override
  String get aboutPrivacyPolicy => 'Política de privacidad';

  @override
  String get aboutImprint => 'Aviso legal';

  @override
  String get aboutSystemInfo => 'Información del sistema';

  @override
  String get aboutSystemInfoDesc =>
      'Copia un resumen compacto de diagnóstico para informar de errores.';

  @override
  String get aboutDiagnosticsContentsTitle => 'Qué contiene el informe';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'Versión de la app, sistema operativo, ruta del programa sin tu nombre de usuario, modelo de voz (variante, modelo, estado, último error), GPU, archivos de modelo y las últimas 40 líneas del registro. Las claves y los tokens están ocultos en las líneas del registro.';

  @override
  String get aboutDiagnosticsPreviewShow => 'Mostrar';

  @override
  String get aboutDiagnosticsPreviewHide => 'Ocultar';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'Diagnóstico incompleto: $error';
  }

  @override
  String get aboutCopyDebugInfo => 'Copiar info de depuración';

  @override
  String get aboutCopied => '¡Copiado!';

  @override
  String get aboutMadeWith => 'Hecho con ♥ por WhisPaste';

  @override
  String get aboutOpenSource => 'Código abierto bajo la licencia MIT';

  @override
  String get feedbackSubtitle =>
      'Ayúdanos a mejorar WhisPaste. Cada opinión cuenta.';

  @override
  String get feedbackCategoryLabel => '¿De qué se trata?';

  @override
  String get feedbackRatingLabel => '¿Qué tal te va con WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Cuéntanos más';

  @override
  String get feedbackContactEmailLabel => 'Correo electrónico (opcional)';

  @override
  String get feedbackContactEmailExplanation =>
      'Solo si quieres recibir respuesta. Lo usaremos únicamente para dar seguimiento a este mensaje, nunca con fines de marketing, y se borra a los 90 días.';

  @override
  String get feedbackContactEmailPlaceholder => 'tu@ejemplo.com';

  @override
  String get feedbackContactEmailInvalid =>
      'Introduce una dirección de correo válida o déjalo vacío.';

  @override
  String get feedbackContactLanguageLabel => 'Responder en';

  @override
  String get feedbackContactLanguageHint =>
      '¿En qué idioma deberíamos responderte si te escribimos?';

  @override
  String get feedbackSubmit => 'Enviar comentarios';

  @override
  String feedbackSubmitMissing(String what) {
    return 'Para enviarlo, $what.';
  }

  @override
  String get feedbackMissingCategory => 'elige de qué se trata';

  @override
  String get feedbackMissingRating => 'valora cómo te sientes con WhisPaste';

  @override
  String get feedbackMissingComment => 'escribe un mensaje';

  @override
  String get feedbackMissingEmail =>
      'corrige la dirección de correo o deja el campo vacío';

  @override
  String get feedbackRequiredMarker => 'Obligatorio';

  @override
  String get feedbackPublishConsentLabel =>
      'Permito que mi comentario aparezca de forma anónima como cita en la web.';

  @override
  String get feedbackPublishConsentExplanation =>
      'Desactivado por defecto. Solo se muestran tu texto y tu valoración, nunca tu nombre ni tu correo. Puedes retirar este permiso en cualquier momento con un clic en la página Comentarios de la app.';

  @override
  String get feedbackPublishReviewHint =>
      'Las citas se escriben como una valoración: qué te gusta y qué aún puede mejorar. Los errores y las ideas van en «Problema» o «Idea» y nunca se publican.';

  @override
  String get feedbackWithdrawConsentLabel => 'Retirar el consentimiento';

  @override
  String get feedbackWithdrawConsentHelp =>
      'Afecta a los comentarios que enviaste con consentimiento desde este dispositivo. La cita desaparece de la web en unas 24 horas.';

  @override
  String get feedbackWithdrawConsentPending =>
      'La retirada está guardada y se enviará cuando WhisPaste se ejecute con conexión a internet (hasta 30 días); si no, retírala por correo electrónico.';

  @override
  String get feedbackWithdrawNoCode =>
      'No hay ningún código de retirada guardado en este dispositivo: retíralo por correo electrónico';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'La retirada del $date se está enviando…';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'Retirada del $date no entregada: retírala por correo electrónico';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'No se pudo entregar la retirada: retírala por correo electrónico.';

  @override
  String get feedbackWithdrawEmailLabel => 'Retirar por correo electrónico';

  @override
  String get feedbackWithdrawEmailSubject =>
      'Retirar mi consentimiento para citar mi comentario';

  @override
  String get feedbackWithdrawEmailBody =>
      'Por favor, retira mi consentimiento para citar mi comentario.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'Fecha del comentario:';

  @override
  String get feedbackWithdrawEmailReferenceLabel =>
      'Referencia de la retirada:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'He enviado el correo';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'No se encontró ninguna app de correo. Envía el mensaje preparado a esta dirección:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'Copiar dirección y mensaje';

  @override
  String get feedbackWithdrawEmailCopied => 'Dirección y mensaje copiados.';

  @override
  String get feedbackWithdrawLocked =>
      'El almacén de credenciales de tu sistema no se puede leer ahora mismo. WhisPaste no puede enviar los consentimientos y retiradas guardados allí. Retíralos por correo electrónico; el correo preparado incluye las referencias necesarias.';

  @override
  String get feedbackWithdrawConsentDone =>
      'Retirada enviada. La cita desaparece de la web en unas 24 horas, en la próxima actualización diaria.';

  @override
  String get feedbackPrivacyNote =>
      'Anónimo por defecto; solo es identificable si añades tu correo arriba.';

  @override
  String get feedbackThankYou => '¡Gracias!';

  @override
  String get feedbackThankYouMessage =>
      'Tus comentarios nos ayudan a mejorar WhisPaste\npara todo el mundo.';

  @override
  String get feedbackSendAnother => 'Enviar otro';

  @override
  String get feedbackRatingFrustrated => 'Frustrado';

  @override
  String get feedbackRatingMeh => 'Regular';

  @override
  String get feedbackRatingOkay => 'Bien';

  @override
  String get feedbackRatingHappy => 'Contento';

  @override
  String get feedbackRatingLoveIt => '¡Me encanta!';

  @override
  String get feedbackSubmitting => 'Enviando…';

  @override
  String get feedbackErrorRateLimited =>
      'Ya enviaste comentarios hace poco. Inténtalo más tarde.';

  @override
  String get feedbackErrorNetwork =>
      'No se pudo conectar con el servidor. Comprueba tu conexión a internet.';

  @override
  String get feedbackErrorServer => 'Algo salió mal. Inténtalo más tarde.';

  @override
  String get feedbackErrorNotConfigured =>
      'Los comentarios no están disponibles en esta versión.';

  @override
  String get statusBarOnDevice => 'En el dispositivo';

  @override
  String get statusBarOverlayFloating => 'Superposición: flotante';

  @override
  String get statusBarOverlayOff => 'Superposición: desactivada';

  @override
  String get statusBarAfterCopy => 'Después: copiar';

  @override
  String get statusBarAfterPaste => 'Después: pegar';

  @override
  String get statusBarAfterBoth => 'Después: copiar y pegar';

  @override
  String get statusBarAfterNothing => 'Después: manual';

  @override
  String get dockOutputCopy => 'Copiar';

  @override
  String get dockOutputPaste => 'Pegar';

  @override
  String get dockOutputBoth => 'Copiar y pegar';

  @override
  String get dockOutputNothing => 'Manual';

  @override
  String get sttStatusStarting => 'Iniciando…';

  @override
  String get sttStatusReady => 'Listo';

  @override
  String get sttStatusError => 'Error';

  @override
  String get statusBarSttTooltip => 'Estado del modelo de voz';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'El reconocimiento se ejecuta en: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'La utilización real de la GPU no se puede medir en todas las plataformas sin privilegios elevados; el porcentaje mostrado refleja la actividad de CPU de este proceso.';

  @override
  String get statusBarRecording => 'Grabando…';

  @override
  String get statusBarTranscribing => 'Procesando…';

  @override
  String get statusBarRefining => 'Procesando…';

  @override
  String get statusBarHotkeyTooltip => 'Atajo global: haz clic para configurar';

  @override
  String get statusBarAutoPasteOffHint => 'Activar Auto-Paste…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste está desactivado. Haz clic para abrir Ajustes.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Descartar';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'Automatización: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'Automatización: error';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'API de automatización activa en el puerto $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'API de automatización activa en el puerto $port (el puerto $requestedPort estaba en uso)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'API de automatización: no se encontró ningún puerto libre';

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
  String get modifierOption => 'Opción';

  @override
  String get modifierAltGr => 'AltGr';

  @override
  String get shortcutKeySpace => 'Espacio';

  @override
  String get shortcutKeyEnter => 'Intro';

  @override
  String get shortcutKeyEscape => 'Esc';

  @override
  String get shortcutKeyBackspace => 'Retroceso';

  @override
  String get shortcutKeyTab => 'Tab';

  @override
  String get shortcutKeyDelete => 'Supr';

  @override
  String get shortcutKeyInsert => 'Insert';

  @override
  String get shortcutKeyHome => 'Inicio';

  @override
  String get shortcutKeyEnd => 'Fin';

  @override
  String get shortcutKeyPageUp => 'Re Pág';

  @override
  String get shortcutKeyPageDown => 'Av Pág';

  @override
  String get modelServerReady => 'Modelo de voz listo';

  @override
  String get modelServerMissing => 'Modelo de voz no instalado';

  @override
  String get modelServerWhisper => 'Modelo de voz local';

  @override
  String get modelReady => 'Listo';

  @override
  String get modelDownloadComplete => 'Modelo listo para usar';

  @override
  String get modelUse => 'Usar';

  @override
  String get modelDownload => 'Descargar';

  @override
  String get modelDownloading => 'Descargando…';

  @override
  String get modelDownloadingEngine => 'Preparando el modelo de voz…';

  @override
  String get modelVerifying => 'Verificando…';

  @override
  String get modelExtracting => 'Extrayendo…';

  @override
  String get modelDeleteConfirm => '¿Eliminar este modelo de voz?';

  @override
  String get modelDeleteConfirmMessage =>
      'El archivo del modelo de voz se borra de este dispositivo. Puedes volver a descargarlo en cualquier momento.';

  @override
  String get modelTierDeleteConfirm => '¿Eliminar estos modelos?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se eliminan de este dispositivo $count modelos ($size). Puedes volver a descargarlos en cualquier momento.',
      one:
          'Se elimina de este dispositivo 1 modelo ($size). Puedes volver a descargarlo en cualquier momento.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'Rápido';

  @override
  String get qualityTierCompactDesc =>
      'Resultados rápidos y descarga pequeña. Ideal para notas breves y mensajes rápidos.';

  @override
  String get qualityTierBalancedLabel => 'Equilibrado';

  @override
  String get qualityTierBalancedDesc =>
      'Preciso y fiable para grabar a diario. Funciona en la mayoría de los dispositivos.';

  @override
  String get qualityTierPremiumLabel => 'Preciso';

  @override
  String get qualityTierPremiumDesc =>
      'Máxima precisión para grabaciones largas y contenido complejo. Necesita una GPU potente.';

  @override
  String get qualityTierRecommended => 'Recomendado para tu dispositivo';

  @override
  String get qualityTierRecommendedMeasured => 'Medido para tu dispositivo';

  @override
  String qualityTierDownloadSize(String size) {
    return 'Descarga de $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Descargar modelo de voz';

  @override
  String get qualityTierChooseDifferent => 'Elegir otro nivel';

  @override
  String get qualityTierActive => 'Activo';

  @override
  String get qualityTierInfoSlow =>
      'Preciso, tarda bastante más en procesarse en este equipo';

  @override
  String get qualityTierInfoSlowEstimate =>
      'Preciso, probablemente tarde bastante más en este equipo (estimación)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Preciso, ~${ratio}x más lento que el nivel rápido';
  }

  @override
  String get qualityTierInfoModerate =>
      'Buen equilibrio entre velocidad y calidad';

  @override
  String get qualityTierBenchmarkReRun => 'Repetir prueba de rendimiento';

  @override
  String get qualityTierBenchmarkRun => 'Probar rendimiento';

  @override
  String get qualityTierInfoBenchmarking => 'Probando rendimiento…';

  @override
  String get benchmarkRowSubtitle =>
      'Mide la velocidad de cada nivel instalado en este equipo. Los resultados determinan las pistas de velocidad y la recomendación.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'Ejecutando… paso $step de $total: $tier';
  }

  @override
  String get benchmarkCancel => 'Cancelar prueba';

  @override
  String get benchmarkCancelled =>
      'Prueba cancelada. Los niveles medidos hasta ahora se han guardado.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count niveles medidos',
      one: '1 nivel medido',
    );
    return 'Medición completada: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'Última medición: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'Ruta de cálculo: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'Procesador (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'Tarjeta gráfica ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds s de cálculo por cada segundo de audio';
  }

  @override
  String get benchmarkNoResult =>
      'Aún no hay mediciones. Ejecuta la prueba para obtener pistas de velocidad para este equipo.';

  @override
  String get benchmarkStaleNotice =>
      'Estos resultados son de otro equipo o de una versión anterior. Se volverán a medir en segundo plano.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'La medición se refiere a los modelos Whisper. Parakeet no se mide.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'Recomendado tras la medición: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'Cambiar a $tier';
  }

  @override
  String get benchmarkErrorBusy =>
      'La prueba no puede ejecutarse durante una grabación. Inícala de nuevo después.';

  @override
  String get benchmarkErrorNoModel =>
      'No hay ningún nivel instalado. Descarga primero un modelo de voz.';

  @override
  String get benchmarkErrorFailed => 'No se pudo completar la prueba.';

  @override
  String get benchmarkRetry => 'Reintentar';

  @override
  String get qualityTierActionOverride => 'Usar igualmente';

  @override
  String get qualityTierActionOverrideHint =>
      'Usar este nivel a pesar de la advertencia';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'Básica';

  @override
  String get settingsQualityBalanced => 'Equilibrada';

  @override
  String get settingsQualityHigh => 'Alta calidad';

  @override
  String get settingsQualityBest => 'Preciso';

  @override
  String get settingsQualityMaximum => 'Máxima precisión';

  @override
  String get settingsQualityRecommended => '★ Recomendada';

  @override
  String get settingsModelStatusReady => 'Modelo de voz listo';

  @override
  String get settingsModelStatusNeeded =>
      'El modelo de voz se descargará al empezar a grabar';

  @override
  String get settingsModelStatusDownloading => 'Descargando modelo de voz…';

  @override
  String get settingsAdvancedModelManagement =>
      'Ajustes avanzados del modelo de voz';

  @override
  String get infoEngineDownloading =>
      'El modelo de voz se está preparando. Espera un momento.';

  @override
  String get infoModelMissing =>
      'Descarga primero un modelo de voz en los ajustes.';

  @override
  String infoModelMissingSelected(String size) {
    return 'El modelo de voz seleccionado ($size) aún no está descargado.';
  }

  @override
  String get infoModelMissingDownload => 'Descargar ahora';

  @override
  String get statusBarModelMissing => 'Falta el modelo de voz';

  @override
  String statusBarModelDownloading(int percent) {
    return 'Descargando modelo de voz… $percent %';
  }

  @override
  String get modelDownloadAction => 'Descargar';

  @override
  String get modelMissingDownloadAction => 'Falta: descargar';

  @override
  String get infoPipelineBusy =>
      'WhisPaste todavía está procesando la grabación anterior.';

  @override
  String get infoSnippetPickerEmpty =>
      'Aún no tienes snippets. Crea uno y se abrirá el selector.';

  @override
  String get infoSnippetPickerEmptyAction => 'Abrir snippets';

  @override
  String get oomRecoveryTitle =>
      'Grabación cancelada: a la tarjeta gráfica le falta memoria';

  @override
  String get oomRecoveryMessage =>
      'La memoria de tu GPU se ha agotado. Elige cómo seguir:';

  @override
  String get oomRecoveryTrySmaller => 'Probar modelo de voz más pequeño';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Cambia a $model y repite la grabación';
  }

  @override
  String get oomRecoverySwitchCloud => 'Cambiar a la nube';

  @override
  String get oomRecoverySwitchCloudHint => 'Usar el modelo de voz en la nube';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'Las grabaciones se enviarán entonces a $provider.';
  }

  @override
  String get oomRecoveryCancel => 'Cancelar';

  @override
  String get oomRecoveryPermanentTitle => 'Modelo de voz local no disponible';

  @override
  String get oomRecoveryPermanentMessage =>
      'Todos los modelos locales han fallado por los límites de memoria de la GPU. Cambia al modelo de voz en la nube en los ajustes.';

  @override
  String get oomRecoveryPermanentCloud => 'Abrir ajustes';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Cambiando a $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Cambiando al modelo de voz en la nube…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'El modelo de voz $model también ha fallado. Probando la siguiente opción…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'No hay ningún modelo más pequeño disponible. Elige otro modelo en Ajustes o usa el reconocimiento de voz en la nube.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'Calidad reducida: la memoria de tu GPU se ha agotado. Se ha cambiado a un modelo de voz más ligero.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'La memoria de tu GPU se ha agotado. Se ha cambiado al modo CPU para mayor fiabilidad.';

  @override
  String get errorSttServerConnectionLost =>
      'El modelo de voz se ha detenido de forma inesperada. Inténtalo de nuevo.';

  @override
  String get errorSttCudaOom =>
      'La memoria de tu GPU se ha agotado. Se ha reducido la calidad para que el próximo intento funcione.';

  @override
  String get errorCloudAuth =>
      'Falta la clave de API de la nube o no es válida. Revísala en Ajustes → Reconocimiento de voz.';

  @override
  String get errorCloudQuota =>
      'El proveedor en la nube ha alcanzado su límite de solicitudes. Espera un momento e inténtalo de nuevo.';

  @override
  String get errorCloudTimeoutLocal =>
      'El servicio en la nube tardó demasiado en responder. Revisa tu conexión o dicta sin conexión con el modelo local.';

  @override
  String get errorCloudTimeout =>
      'El servicio en la nube tardó demasiado en responder. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get errorCloudNetworkLocal =>
      'No se pudo conectar con el servicio en la nube. Revisa tu conexión a internet o dicta sin conexión con el modelo local.';

  @override
  String get errorCloudNetwork =>
      'No se pudo conectar con el servicio en la nube. Revisa tu conexión a internet e inténtalo de nuevo.';

  @override
  String get errorQuickNoteAppendFailed =>
      'No se pudo guardar la nota rápida, así que el texto no se añadió. Copia el texto y pégalo en la nota.';

  @override
  String get errorOnboardingNotCompleted =>
      'Completa primero el asistente de configuración.';

  @override
  String get errorSttModelNotFound =>
      'No se encuentra el modelo de voz. Descárgalo en los ajustes.';

  @override
  String get errorSttModelLoadFailed =>
      'No se pudo cargar el modelo de voz. Reinicia WhisPaste. Si sigue fallando, vuelve a descargar el modelo de voz en los ajustes.';

  @override
  String get errorSttModelFileMissing =>
      'Falta el archivo del modelo de voz. Descarga el modelo de voz en los ajustes.';

  @override
  String get errorSttModelCorrupted =>
      'El archivo del modelo de voz está dañado. Vuelve a descargar el modelo de voz en los ajustes.';

  @override
  String get errorSttEngineRestartNeeded =>
      'El motor de voz sigue ocupado con un dictado anterior. Reinicia WhisPaste para volver a usarlo.';

  @override
  String get pendingRetryFailed =>
      'La nueva transcripción ha fallado. La grabación se conserva para otro intento.';

  @override
  String get pendingRetryExpired =>
      'El plazo de conservación ha vencido. La grabación se ha eliminado y ya no se puede transcribir.';

  @override
  String get errorSttModelUnknown =>
      'Modelo de voz desconocido. Selecciona uno válido en los ajustes.';

  @override
  String get errorRecordingFailed =>
      'No se pudo iniciar la grabación, inténtalo de nuevo';

  @override
  String get errorNoAudioRecorded =>
      'No se ha grabado audio, inténtalo de nuevo';

  @override
  String get errorTranscriptionEmpty =>
      'La transcripción no devolvió texto, inténtalo de nuevo';

  @override
  String get errorSttServerFailed => 'El modelo de voz no se pudo iniciar';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'El modelo de voz parece estar dañado. Descargando una copia nueva automáticamente.';

  @override
  String get errorSttDllMissing =>
      'Falta un componente necesario del sistema. Reintentando en modo CPU.';

  @override
  String get errorSttGpuFatal =>
      'La aceleración por GPU ha fallado. Reintentando en modo CPU.';

  @override
  String get errorSttHeapCorruption =>
      'Se ha producido un error de memoria. Reintentando en modo CPU.';

  @override
  String get errorSttCpuFallbackFailed =>
      'El modelo de voz ha fallado tanto en GPU como en CPU. Reinicia la app o vuelve a descargar el modelo de voz.';

  @override
  String get errorPipelineTimeout =>
      'La grabación ha tardado demasiado. Prueba con una grabación más corta.';

  @override
  String get errorWavFileNotCreated =>
      'No se pudo guardar el archivo de audio. Inténtalo de nuevo.';

  @override
  String get errorWavFileEmpty =>
      'No se ha capturado ningún audio. Revisa tu micrófono.';

  @override
  String get errorSttStartTimeout =>
      'El modelo de voz todavía se está iniciando. Inténtalo de nuevo en un momento.';

  @override
  String get errorTranscriptionTimeout =>
      'La transcripción ha tardado demasiado. Prueba con una grabación más corta.';

  @override
  String get errorMicPermissionDenied =>
      'Se necesita acceso al micrófono. Permítelo en los ajustes del sistema.';

  @override
  String get errorRecordingStartFailed =>
      'No se pudo iniciar la grabación. Inténtalo de nuevo.';

  @override
  String get errorNoMicrophone =>
      'No se ha encontrado ningún micrófono. Conecta uno e inténtalo de nuevo.';

  @override
  String get errorGeneric => 'Algo ha salido mal. Inténtalo de nuevo.';

  @override
  String get modelDownloadFailed =>
      'La descarga ha fallado. Revisa tu conexión a internet.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'No hay suficiente espacio en disco para esta descarga: necesita $needed, libre $free. La descarga no se ha iniciado.';
  }

  @override
  String get modelDeleteInUse =>
      'El archivo del modelo de voz está en uso por otro programa y no se pudo borrar. Ciérralo e inténtalo de nuevo.';

  @override
  String get downloadTlsError =>
      'No se pudo verificar la conexión segura con el servidor de descarga. Comprueba la fecha y la hora del dispositivo o un programa que revise las conexiones (antivirus o proxy) e inténtalo de nuevo.';

  @override
  String get statusSttLoading => 'Cargando modelo de voz…';

  @override
  String get statusSttReady => 'Modelo de voz listo';

  @override
  String get modelDownloadFailedChecksum =>
      'El archivo descargado estaba dañado y se ha eliminado. Descárgalo de nuevo.';

  @override
  String get modelDownloadFailedStorage =>
      'No se pudo guardar el archivo. Comprueba que haya suficiente espacio libre en el disco.';

  @override
  String get modelDownloadFailedUnknown =>
      'La descarga ha fallado. Inténtalo de nuevo.';

  @override
  String get onboardingModelDownloadCancel => 'Cancelar descarga';

  @override
  String get onboardingModelDiskSpaceTitle => 'Poco espacio en disco';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'El modelo de voz necesita $needed, pero solo quedan $free libres. Es probable que la descarga falle.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'Descargar igualmente';

  @override
  String get historyDuplicate => 'Duplicar';

  @override
  String get historyDuplicated => 'Entrada duplicada';

  @override
  String get historyTakeAsNote => 'Usar como nota';

  @override
  String get historyTakenAsNote => 'Usado como nota';

  @override
  String get historyOpenNote => 'Abrir';

  @override
  String get historyViewRaw => 'Original';

  @override
  String get historyViewEdited => 'Editada';

  @override
  String get historyApplySmartModePreset => 'Aplicar preset de Smart Mode';

  @override
  String get historySmartModeApplied => 'Smart Mode aplicado';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode aplicado';

  @override
  String get smartModeUndoAction => 'Deshacer';

  @override
  String get smartModeBusy => 'El Smart Mode sigue en curso';

  @override
  String get smartModeBusyRetry =>
      'El Smart Mode sigue en curso – inténtalo de nuevo en un momento';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nombres cambiados',
      one: '1 nombre cambiado',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'Original copiado al portapapeles: pégalo con $shortcut. Se reemplazó el contenido anterior del portapapeles.';
  }

  @override
  String get selectionUndoUnavailable => 'Deshacer no es posible ahora.';

  @override
  String get smartModeCheckTimedOut =>
      'La comprobación tardó demasiado: tu texto no cambia.';

  @override
  String get historySmartModeUndo => 'Deshacer Smart Mode';

  @override
  String get historySmartModeRestore => 'Restaurar Smart Mode';

  @override
  String get historySmartModeFailedModelMissing =>
      'Modelo de texto no descargado';

  @override
  String get historySmartModeFailedTimeout =>
      'Smart Mode ha superado el tiempo de espera';

  @override
  String get historySmartModeFailedGeneric =>
      'Smart Mode ha fallado, inténtalo de nuevo';

  @override
  String get historySmartModeSelectTargetLanguage =>
      'Elige el idioma de destino';

  @override
  String get historyAddNote => 'Añadir anotación';

  @override
  String get historyEditNote => 'Editar anotación';

  @override
  String get historyNotes => 'Anotaciones';

  @override
  String get historyNotePlaceholder => 'Escribe una anotación…';

  @override
  String get historyVoiceNoteHint =>
      'Consejo: di «tag: nombre» o «correct: texto» mientras grabas.';

  @override
  String get historyNoteAdded => 'Anotación añadida';

  @override
  String get historyNoteDeleted => 'Anotación eliminada';

  @override
  String get historyCopiedAsMarkdown => 'Copiado como Markdown';

  @override
  String get historyAddTag => 'Añadir etiqueta…';

  @override
  String get historySearchTags => 'Buscar o crear…';

  @override
  String get historyNoteEdited => 'editada';

  @override
  String get historyTagAdded => 'Etiqueta añadida';

  @override
  String get historyTagRemoved => 'Etiqueta eliminada';

  @override
  String historyCreateTag(Object tag) {
    return 'Crear «$tag»';
  }

  @override
  String get historyManageTags => 'Gestionar etiquetas';

  @override
  String get tagManageTitle => 'Gestionar etiquetas';

  @override
  String get tagManageEmpty =>
      'Todavía no hay etiquetas. Creas una añadiéndola a una grabación.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
      zero: 'sin usar',
    );
    return '$_temp0';
  }

  @override
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas más',
      one: '1 etiqueta más',
    );
    return '$_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => '¿Eliminar etiqueta?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
    );
    return 'La etiqueta «$name» se usa en $_temp0. Se quitará de todas ellas.';
  }

  @override
  String tagDeleted(String name) {
    return 'Etiqueta «$name» eliminada';
  }

  @override
  String tagRemoveSemanticsLabel(String tag) {
    return 'Quitar etiqueta «$tag»';
  }

  @override
  String get tagDeleteUnusedTitle => '¿Eliminar etiquetas sin usar?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas sin usar se eliminarán',
      one: '1 etiqueta sin usar se eliminará',
    );
    return '$_temp0 de forma permanente.';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return 'Eliminar $count sin usar';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas sin usar eliminadas',
      one: '1 etiqueta sin usar eliminada',
    );
    return '$_temp0';
  }

  @override
  String get historyEditTranscript => 'Editar transcripción';

  @override
  String get historyTranscriptSaved => 'Transcripción guardada';

  @override
  String get historySaveTranscript => 'Guardar';

  @override
  String get historyShortcutHelp => 'Atajos de teclado';

  @override
  String get historyShortcutGeneral => 'GENERAL';

  @override
  String get historyShortcutTags => 'Enfocar el campo de etiquetas';

  @override
  String get historyShortcutNotes => 'Añadir una anotación';

  @override
  String get historyShortcutPin => 'Marcar o desmarcar como favorita';

  @override
  String get historyShortcutClose => 'Guardar y cerrar';

  @override
  String get historyShortcutListGroup => 'LISTA DE GRABACIONES';

  @override
  String get historyShortcutMoveFocus => 'Seleccionar entrada';

  @override
  String get historyShortcutOpenEntry => 'Abrir entrada';

  @override
  String get historyShortcutCopyEntry => 'Copiar entrada';

  @override
  String get historyShortcutDeleteEntry => 'Eliminar entrada';

  @override
  String get historyShortcutSelectAll => 'Seleccionar todo';

  @override
  String get historyShortcutClearSelection => 'Quitar la selección';

  @override
  String get historyShortcutEditing => 'EDICIÓN';

  @override
  String get historyShortcutToggleEdit =>
      'Activar o desactivar el modo edición';

  @override
  String get historyShortcutSave => 'Guardar transcripción';

  @override
  String get historyShortcutBold => 'Negrita';

  @override
  String get historyShortcutItalic => 'Cursiva';

  @override
  String get historyShortcutCopy => 'Copiar al portapapeles';

  @override
  String get historyShortcutEditTitle => 'Editar título';

  @override
  String get historyShortcutDiscardEdit => 'Descartar la edición';

  @override
  String get historyEditTitle => 'Editar título';

  @override
  String get historyTitlePlaceholder => 'Escribe un título…';

  @override
  String get historyTitleSaved => 'Título guardado';

  @override
  String get historySearchHelpTitle => 'Consejos de búsqueda';

  @override
  String get historySearchHelpTags => 'Escribe # para filtrar por etiquetas';

  @override
  String get historySearchHelpLang => 'Escribe lang: para filtrar por idioma';

  @override
  String get historySearchHelpFreeText => 'O escribe cualquier palabra clave';

  @override
  String get historySearchQuickTags => 'Etiquetas populares';

  @override
  String get historyRecentSearches => 'Búsquedas recientes';

  @override
  String get historyRemoveRecentSearch => 'Quitar búsqueda reciente';

  @override
  String get historyRemoveFilter => 'Quitar filtro';

  @override
  String get historyQuickActions => 'Filtros rápidos';

  @override
  String get historyQuickActionAllLangs => 'Todos los idiomas';

  @override
  String get historyQuickActionFavorites => 'Solo favoritas';

  @override
  String get historySortNewest => 'Más recientes primero';

  @override
  String get historySortOldest => 'Más antiguas primero';

  @override
  String get historySortLongest => 'Más largas primero';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'Filtrar por etiqueta';

  @override
  String get historySearchSuggestLang => 'Filtrar por idioma';

  @override
  String get settingsKeyboardShortcut => 'Atajo';

  @override
  String get shortcutsGroupDictate => 'Dictar';

  @override
  String get shortcutsGroupNotes => 'Notas y snippets';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode y editar selección';

  @override
  String get shortcutsAreaIntro =>
      'Estos atajos funcionan en todo el sistema: en casi cualquier app, incluso con WhisPaste en segundo plano. Cada combinación pertenece a un solo atajo.';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Atajo para iniciar y detener la grabación';

  @override
  String get settingsHotkeyEnabled => 'Iniciar o detener grabación';

  @override
  String get settingsCurrentHotkey => 'Atajo actual';

  @override
  String get settingsChangeHotkey => 'Cambiar';

  @override
  String get settingsHotkeyRecorderTitle => 'Definir nuevo atajo';

  @override
  String get settingsHotkeyRecorderHint =>
      'Pulsa la combinación de teclas que quieras usar…';

  @override
  String get settingsHotkeyRecorderDictationTitle => 'Cambiar tecla de dictado';

  @override
  String settingsHotkeyRecorderDictationHint(String key) {
    return 'Pulsa la nueva combinación de teclas. También sirve una sola tecla, por ejemplo: $key.';
  }

  @override
  String get settingsHotkeyRecorderSingleKeyMac =>
      'Para una sola tecla, macOS pide una vez el permiso de «Monitorización de entrada».';

  @override
  String get settingsHotkeyRecorderListening => 'Pulsa ahora la nueva tecla.';

  @override
  String get settingsHotkeyRecorderCurrent => 'Actual';

  @override
  String get hotkeyKeySideLeft => 'izq.';

  @override
  String get hotkeyKeySideRight => 'dcha.';

  @override
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'Vale cualquier combinación de modificadores, p. ej. $first, $second o $third';
  }

  @override
  String get settingsHotkeyRecorderCancel => 'Cancelar';

  @override
  String get settingsHotkeyRecorderSave => 'Guardar';

  @override
  String get settingsHotkeyRecorderClear => 'Borrar';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'Esta tecla no se puede usar como atajo. Prueba con una letra, un número, una tecla de función (F1–F12) o una flecha.';

  @override
  String get settingsHotkeyActionRecording => 'Iniciar o detener grabación';

  @override
  String get settingsHotkeyActionQuickNote => 'Nota rápida';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'Grabar una nota rápida';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'El texto transcrito se añade a la nota marcada como nota rápida. Esa nota la eliges en el área de Notas.';

  @override
  String get settingsQuickNoteOpenInMainWindow =>
      'Abrir notas en la ventana principal';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'Desactivado: la nota rápida se guarda en segundo plano y un aviso ofrece «Abrir nota». Activado: la ventana principal aparece y muestra la nota.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Atajo actual';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Esta combinación ya se usa para «$action». Elige otra.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'Esta combinación ya se usa para «$action». Elige otra.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'No se pudo registrar esta combinación: el atajo de nota rápida no está activo. Elige otra combinación.';

  @override
  String get quickNoteToastSaved => 'Nota rápida guardada';

  @override
  String get quickNoteToastOpenNote => 'Abrir nota';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Selector de snippets';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Abrir el selector de snippets';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Abre el selector de snippets al instante: sin grabar y sin la palabra de activación hablada.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Atajo actual';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Esta combinación ya se usa para «$action». Elige otra.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'No se pudo registrar esta combinación: el atajo del selector de snippets no está activo. Elige otra combinación.';

  @override
  String get settingsMaxRecordDuration => 'Duración máxima de grabación';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Parada automática de seguridad tras este tiempo';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Sin límite';

  @override
  String get settingsCloseToTray => 'Cerrar a la bandeja';

  @override
  String get settingsCloseToTraySubtitle =>
      'Seguir ejecutándose en la bandeja del sistema al cerrar la ventana';

  @override
  String get settingsSidePanelEnabled =>
      'Panel de pegado rápido del portapapeles';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'Panel que se desliza al pasar el ratón por el borde elegido de la pantalla, con transcripciones, snippets e historial del portapapeles';

  @override
  String get settingsSidePanelEdge => 'Posición del panel';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'Borde de la pantalla al que se ancla el panel y desde el que se desliza';

  @override
  String get settingsSidePanelEdgeLeft => 'Borde izquierdo';

  @override
  String get settingsSidePanelEdgeRight => 'Borde derecho';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsAppearanceSubtitle =>
      'Colores de las ventanas de la app. La barra de grabación y el overlay siguen oscuros.';

  @override
  String get settingsAppearanceSystem => 'Según el sistema';

  @override
  String get settingsAppearanceLight => 'Claro';

  @override
  String get settingsAppearanceDark => 'Oscuro';

  @override
  String get settingsAppearanceNavy => 'Marino';

  @override
  String get settingsAppearanceCardNavy => 'Marino';

  @override
  String get settingsLanguageDialogSubtitle =>
      'Elige el idioma que WhisPaste espera al grabar. Con «Detectar automáticamente» lo reconoce por sí mismo.';

  @override
  String get settingsLanguageSearchHint => 'Buscar idiomas';

  @override
  String get settingsLanguageSelectedTitle => 'Seleccionado';

  @override
  String get settingsLanguageSaveAndClose => 'Guardar y cerrar';

  @override
  String get settingsLanguageSavePickOne =>
      'Elige al menos un idioma para guardar.';

  @override
  String get settingsLanguageNoResults => 'Ningún idioma encontrado';

  @override
  String get settingsLanguageChange => 'Cambiar';

  @override
  String get settingsLanguageCancel => 'Cancelar';

  @override
  String get settingsErrorReporting => 'Enviar informes de fallos';

  @override
  String get settingsErrorReportingSubtitle =>
      'Informes técnicos de fallos y errores graves, a través de Sentry en la UE. Nunca tu audio ni tu texto.';

  @override
  String get settingsErrorReportingRestartHint =>
      'Se aplica al reiniciar WhisPaste.';

  @override
  String get settingsAutoPasteBlocklist => 'Lista de bloqueo de Auto-Paste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Apps donde solo se copia (sin pegado automático). Con el interruptor de abajo activado, el texto va al portapapeles; desactivado, solo a Grabaciones. Mientras haya una lista, una app no identificada cuenta como bloqueada.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'Copiar al portapapeles en apps bloqueadas';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'Desactivado: el texto solo se guarda en Grabaciones.';

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
      'En Mac se usan IDs de paquete, p. ej. com.apple.Terminal. Sin punto, una entrada solo coincide con un ID idéntico.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'En GNOME (Wayland), WhisPaste solo identifica la app de destino con la extensión de WhisPaste para GNOME; sin ella, con una lista activa solo se copia';

  @override
  String get settingsLinuxAlwaysShiftPaste => 'Pegar siempre con Ctrl+Mayús+V';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'El atajo de los terminales, también en las demás apps. Algunas apps usan estas teclas para otra cosa; LibreOffice, por ejemplo, abre «Pegado especial»';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'Aquí WhisPaste identifica la app de destino y pega en los terminales con Ctrl+Mayús+V por sí solo';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'En GNOME (Wayland), WhisPaste solo reconoce los terminales con la extensión de WhisPaste para GNOME. Mientras tanto, actívalo si dictas sobre todo en terminales';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'En este escritorio, WhisPaste no reconoce los terminales. Actívalo si dictas sobre todo en terminales';

  @override
  String get settingsLinuxPortalInputTitle =>
      'Pegar mediante el permiso del escritorio';

  @override
  String get settingsLinuxPortalInputBody =>
      'Funciona sin configurar nada: tu escritorio pregunta una vez si WhisPaste puede enviar atajos. WhisPaste solo envía así Ctrl+V y Ctrl+C';

  @override
  String get settingsLinuxPortalInputConnect => 'Pedir permiso';

  @override
  String get settingsLinuxPortalInputRevoke => 'Retirar el permiso';

  @override
  String get settingsLinuxPortalInputConnected =>
      'Permiso concedido. WhisPaste ya puede pegar así';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'No se concedió el permiso. Puedes volver a pedirlo cuando quieras';

  @override
  String get settingsLinuxPortalInputFailed =>
      'No se pudo pedir el permiso. Inténtalo de nuevo más tarde';

  @override
  String get settingsLinuxGnomeExtensionTitle =>
      'Extensión de WhisPaste para GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'En GNOME, WhisPaste solo sabe qué app está activa con esta extensión, por ejemplo para los terminales y la lista de bloqueo. Solo lee el nombre de la app, nunca títulos de ventana ni contenido';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'Activar la extensión';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'Desactivar la extensión';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'La extensión no está instalada aquí. El manual explica cómo instalarla';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'Activada. Si WhisPaste aún no reconoce la app, cierra la sesión y vuelve a entrar una vez';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'No se pudo activar. En un terminal: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'En Wayland, WhisPaste no ve la app activa. Mientras haya apps bloqueadas, el texto solo se copia, no se pega.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'Con Wayland, WhisPaste no puede comprobar si cambiaste de ventana durante el procesamiento: el texto va a la ventana activa al pegar';

  @override
  String get settingsPasteBlocklistAdd => 'Añadir app';

  @override
  String get settingsPasteBlocklistEmpty =>
      'Ninguna app bloqueada: el auto-pegado funciona en casi todas.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'Quitar de la lista de bloqueo: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle =>
      'Añadir app a la lista de bloqueo';

  @override
  String get settingsPasteBlocklistRecentHeading => 'Dictado recientemente en';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'Aún no hay dictados con una app reconocida. Introduce abajo el identificador de la app.';

  @override
  String get settingsPasteBlocklistManualHeading =>
      'Introducir el identificador manualmente';

  @override
  String get settingsPasteBlocklistManualAdd => 'Añadir';

  @override
  String get historyAutoPasteOffForApp =>
      'Desactivar el auto-pegado en esta app';

  @override
  String get settingsPasteClipboardAfter => 'Portapapeles tras pegar';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'Si vuelve a aparecer lo que habías copiado antes de pegar. Si el pegado no se puede confirmar a tiempo, la transcripción se queda en el portapapeles, salvo que la opción de abajo esté activada.';

  @override
  String get settingsPasteClipboardAfterKeep => 'Mantener la transcripción';

  @override
  String get settingsPasteClipboardWithoutReceipt =>
      'Restaurar también sin confirmación';

  @override
  String get settingsPasteClipboardWithoutReceiptSubtitle =>
      'Desactivado: si el pegado no se confirma a tiempo, la transcripción se queda en el portapapeles. Activado: tras una espera fija vuelve el contenido anterior, como en la versión anterior. Solo con «Restaurar lo que habías copiado». Una app muy lenta podría leer aún el contenido antiguo antes de recibir la transcripción. Activado en instalaciones existentes, desactivado en las nuevas.';

  @override
  String get settingsPasteClipboardAfterRestore =>
      'Restaurar lo que habías copiado';

  @override
  String get pasteClipboardUnsavedHint =>
      'No se pudo guardar tu portapapeles anterior: macOS ha denegado el acceso. Permítelo en Ajustes del Sistema → Privacidad y seguridad.';

  @override
  String get pasteClipboardUnsavedAction => 'Abrir Ajustes del Sistema';

  @override
  String get settingsCheckUpdates => 'Buscar actualizaciones';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Busca nuevas versiones al iniciar y cada 24 horas';

  @override
  String get settingsCheckForUpdatesNow => 'Buscar actualizaciones ahora';

  @override
  String get settingsUpdates => 'Actualizaciones';

  @override
  String get settingsUpdatesSubtitle =>
      'Canal de publicación y búsqueda de actualizaciones';

  @override
  String get settingsBetaUpdates => 'Actualizaciones beta';

  @override
  String get settingsBetaUpdatesSubtitle =>
      'Recibe versiones preliminares, menos probadas.';

  @override
  String get settingsStableRevertHintMessage =>
      'Aquí no es posible volver automáticamente a la versión estable. Ya tienes instalada una versión beta más reciente.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'Descarga manualmente la versión estable $stableVersion';
  }

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get onboardingLoadModel => 'Cargar modelo de voz';

  @override
  String get onboardingReadyFixHotkey => 'Cambiar atajo';

  @override
  String get onboardingBack => 'Atrás';

  @override
  String historyRetentionNotice(int maxEntries, int trashDays) {
    String _temp0 = intl.Intl.pluralLogic(
      maxEntries,
      locale: localeName,
      other: 'Se conservan hasta $maxEntries grabaciones.',
      one: 'Se conserva 1 grabación.',
    );
    String _temp1 = intl.Intl.pluralLogic(
      trashDays,
      locale: localeName,
      other: ', que se vacía tras $trashDays días',
      one: ', que se vacía tras 1 día',
      zero: ', que nunca se vacía automáticamente',
    );
    return '$_temp0 Las más antiguas pasan a la papelera$_temp1. Los favoritos se conservan siempre. Puedes cambiarlo en Ajustes → Privacidad y datos.';
  }

  @override
  String get historyRetentionNoticeUnlimited =>
      'No hay límite en el número de grabaciones. Los favoritos se conservan siempre. Puedes cambiarlo en Ajustes → Privacidad y datos.';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingMicStatement =>
      'Di unas palabras. La onda debería moverse.';

  @override
  String get onboardingMicHeard => 'Te he oído. Puedes seguir.';

  @override
  String get onboardingMicSilence =>
      'No ha llegado sonido. ¿Está elegido el micrófono correcto?';

  @override
  String get onboardingMicOpenError =>
      'El micrófono no se pudo iniciar; quizá otra app lo está usando. Sigo intentándolo.';

  @override
  String get onboardingMicPermissionLine =>
      'WhisPaste todavía no puede usar el micrófono.';

  @override
  String get onboardingMicLevelLabel => 'Nivel del micrófono';

  @override
  String get onboardingMicSkip => 'Omitir';

  @override
  String get onboardingModelTitle => 'Configura el modelo de voz';

  @override
  String get onboardingModelSubtitle =>
      'Descarga el modelo de voz para grabar sin conexión. Con el reconocimiento local, tu voz se queda en tu dispositivo.';

  @override
  String get onboardingModelRecommended => 'Recomendado';

  @override
  String get onboardingModelChangeLater =>
      'Puedes cambiar el modelo de voz más tarde en Ajustes';

  @override
  String get onboardingModelDefaultHint =>
      'Preseleccionado. También hay modelos más grandes y precisos; puedes cambiar en Ajustes en cualquier momento.';

  @override
  String get onboardingHotkeyTestRecognized =>
      'Funciona. Así empiezas a dictar.';

  @override
  String get onboardingHotkeyStatusHeld => 'Detectada. Sigue manteniendo …';

  @override
  String get onboardingHotkeyStatusRelease => 'Ahora suelta.';

  @override
  String get onboardingHotkeyStatusHandsFree =>
      'Manos libres activo. Una pulsación lo termina.';

  @override
  String get onboardingHotkeyStatusToggledOn =>
      'Iniciado. Pulsa otra vez para parar.';

  @override
  String get onboardingHotkeyStatusDoneHandsFree =>
      'Funciona, también manos libres.';

  @override
  String get onboardingHotkeySkip => 'Probar más tarde';

  @override
  String get onboardingHotkeySceneIdle => 'Prueba de tecla · micrófono apagado';

  @override
  String onboardingModelFactSize(String size) {
    return 'Descarga $size';
  }

  @override
  String get onboardingModelFactLanguagesParakeet => 'Unos 25 idiomas europeos';

  @override
  String get onboardingModelFactLanguagesWhisper => '99 idiomas';

  @override
  String get onboardingModelFactSpeedParakeet => 'Muy rápido';

  @override
  String get onboardingModelFactSpeedWhisper => 'Más lento';

  @override
  String get onboardingModelNextBlocked =>
      'Descarga un modelo de voz o usa un proveedor en la nube con una clave API guardada para continuar.';

  @override
  String get onboardingModelGpuCpuFallback =>
      'La aceleración por tarjeta gráfica no está disponible; WhisPaste usará el procesador. Sigue funcionando, solo que más despacio.';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'La forma más rápida de pasar de voz a texto. Funciona bien en cualquier hardware, con o sin GPU.';

  @override
  String get onboardingModelDetectingHardware =>
      'Comprobando tu hardware para recomendarte lo adecuado…';

  @override
  String onboardingModelUseCloud(String provider) {
    return 'Usar $provider';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'Ya hay una clave API guardada para $provider. Puedes usarla en lugar de un modelo de voz local.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'Usas $provider para el reconocimiento de voz. No necesitas un modelo de voz local.';
  }

  @override
  String get onboardingModelUseLocal => 'Usar un modelo de voz local';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'Términos propios y ajustes de puntuación para nombres, siglas y términos técnicos.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Todavía no admite el idioma seleccionado';

  @override
  String get onboardingTestRecordingTitle => 'Pruébalo';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Pulsa el atajo, di una frase y vuelve a pulsarlo.';

  @override
  String get onboardingTestRecordingSubtitleHold =>
      'Mantén pulsado el atajo, di una frase y suéltalo.';

  @override
  String get onboardingTestRecordingStopCta => 'Detener grabación';

  @override
  String get onboardingTryOutLaterCta => 'Probar más tarde';

  @override
  String get onboardingPracticeQuestion =>
      '¿Para qué quieres usar WhisPaste primero? Dilo sin más.';

  @override
  String get onboardingPracticePlaceholder => 'Tu texto aparece aquí.';

  @override
  String get onboardingPracticeReceived =>
      'Recibido: así llega tu texto a cualquier app.';

  @override
  String get onboardingPracticeSilence =>
      'No he oído nada: habla un poco más alto o revisa el micrófono.';

  @override
  String get onboardingPracticePasteFailed =>
      'No se pudo pegar: tu texto está en el portapapeles.';

  @override
  String get onboardingPracticeWaiting => 'Esperando el dictado…';

  @override
  String onboardingPracticeModelLoading(int percent) {
    return 'Cargando el modelo de voz… $percent %';
  }

  @override
  String onboardingPracticeModelLoadingEta(int percent, int minutes) {
    return 'Cargando el modelo de voz… $percent % · quedan unos $minutes min';
  }

  @override
  String get onboardingPracticeModelMissing =>
      'Aún falta el modelo de voz. Sin él no puedo oírte.';

  @override
  String onboardingPracticeModelSlow(int seconds) {
    return 'En este equipo el modelo tarda unos $seconds s por cada 10 s de voz. Un modelo más rápido escribe aquí con más fluidez.';
  }

  @override
  String get onboardingPracticeModelSlowParakeet => 'Descargar Parakeet';

  @override
  String get onboardingPracticeModelSlowSmaller =>
      'Descargar un modelo más rápido';

  @override
  String get onboardingPracticeMicMissing =>
      'Permite primero el micrófono; si no, no puedo oírte.';

  @override
  String get onboardingTryoutLockTitle =>
      'Tu modelo de voz aún se está cargando';

  @override
  String get onboardingTryoutLockBody =>
      'Probar empieza en cuanto esté listo, automáticamente.';

  @override
  String get onboardingTryoutLockMissingTitle =>
      'Probar necesita un modelo de voz';

  @override
  String get onboardingTryoutLockReady => 'Cargado – pruébalo ahora';

  @override
  String get onboardingPracticeMicAllow => 'Permitir el micrófono';

  @override
  String get onboardingPracticeChipNote => 'Dicta una nota breve';

  @override
  String get onboardingPracticeChipList => 'Prueba una lista';

  @override
  String get onboardingPracticeChipsLabel => 'Sugerencias';

  @override
  String onboardingPracticeChipReply(String hotkey) {
    return 'Bien, pulsa $hotkey y empieza a hablar.';
  }

  @override
  String onboardingPracticeChipReplyHold(String hotkey) {
    return 'Bien, mantén pulsado $hotkey y empieza a hablar.';
  }

  @override
  String get onboardingPracticeInputHint => 'Escribe un mensaje o dicta';

  @override
  String get onboardingPracticeSend => 'Enviar';

  @override
  String get onboardingPracticeDictate => 'Dictar';

  @override
  String get onboardingTestRecordingInProgress =>
      'Grabando: habla con normalidad. Pulsa de nuevo para detener.';

  @override
  String get onboardingTestRecordingInProgressHold =>
      'Grabando: habla con normalidad. Suelta para detener.';

  @override
  String get onboardingTestRecordingReassurance =>
      'Solo es una prueba: el texto queda en este campo.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'Solo es una prueba: el texto queda en este campo. La grabación se detiene sola a los $seconds segundos (Ajustes → $section).';
  }

  @override
  String get onboardingReadyBackToModel => 'Volver al modelo de voz';

  @override
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'El texto está en tu portapapeles; pulsa $paste para pegarlo';
  }

  @override
  String get onboardingTriggerTitle => 'Prueba tu tecla de dictado.';

  @override
  String get onboardingPhaseStart => 'Inicio';

  @override
  String onboardingPhaseCounter(int index, int total) {
    return '$index de $total';
  }

  @override
  String get onboardingPhasePermissions => 'Permisos';

  @override
  String get onboardingPhaseSetup => 'Configurar';

  @override
  String get onboardingPhaseTry => 'Probar';

  @override
  String get onboardingPhasePersonalize => 'Personalizar';

  @override
  String get onboardingTriggerHoldHint =>
      'Demasiado corto. Mantén la tecla un poco más.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Atajo actual';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Atajo ya en uso';

  @override
  String get onboardingTriggerDesktopConfirmHint =>
      'Tu sistema te preguntará una vez si WhisPaste puede usar este atajo. Confírmalo allí y funcionará en cualquier aplicación.';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Parece que otra app usa tu atajo. Graba una nueva combinación abajo para continuar.';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Pulsa una vez para empezar y otra para terminar';

  @override
  String get onboardingTriggerDoubleTapFallbackHint =>
      'La tecla única no se puede usar aquí, así que vale la combinación.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintWindows =>
      'Windows no permite ahora la tecla única, así que vale la combinación.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintLinux =>
      'Este escritorio no informa la tecla única, así que vale la combinación.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintMac =>
      'Hasta que permitas «Monitorización de entrada», vale la combinación.';

  @override
  String onboardingTriggerDemoPrompt(String shortcut) {
    return 'Pulsa $shortcut una vez para empezar y otra para parar. Así dictas en cualquier app.';
  }

  @override
  String onboardingTriggerDemoPromptDoubleTap(String shortcut) {
    return 'Toca $shortcut dos veces rápido; una pulsación termina. Así dictas en cualquier app.';
  }

  @override
  String onboardingTriggerDemoPromptHold(String shortcut) {
    return 'Mantén pulsado $shortcut y suéltalo. Así dictas en cualquier app.';
  }

  @override
  String get onboardingTriggerChooseOther => 'Cambiar tecla';

  @override
  String get onboardingTriggerSecureInput =>
      'El dictado está bloqueado en este campo. Cambia a otro campo de texto y funcionará.';

  @override
  String get onboardingStartUsing => '¡Vamos!';

  @override
  String get onboardingStartWhisPaste => 'Iniciar WhisPaste';

  @override
  String get onboardingOtherModel => 'Otro modelo de voz';

  @override
  String get onboardingWelcomeStatement =>
      'Habla: el texto aparece donde está tu cursor.';

  @override
  String get onboardingDownloadReady => 'Modelo listo';

  @override
  String get onboardingDownloadFailed => 'Descarga fallida';

  @override
  String get onboardingWelcomeHeadline => 'Habla donde\nsueles escribir.';

  @override
  String get onboardingWelcomeSampleDictation =>
      'La presentación se ve genial, solo acortaría un poco la segunda diapositiva.';

  @override
  String onboardingWelcomeRecommended(String model) {
    return 'Recomendado: $model';
  }

  @override
  String onboardingWelcomeConsentLine(String size) {
    return 'Descarga el modelo de voz ($size) · se queda en tu dispositivo';
  }

  @override
  String onboardingWelcomeReachParakeet(int count) {
    return 'Muy rápido · $count idiomas europeos';
  }

  @override
  String onboardingWelcomeStartSized(String size) {
    return 'Descargar $size y configurar';
  }

  @override
  String get onboardingWelcomeOnDevice =>
      'Funciona por completo en tu equipo, sin nube.';

  @override
  String get onboardingSelectDictationLanguage => 'Idioma de dictado';

  @override
  String get onboardingSelectSpeechModel => 'Reconocimiento de voz';

  @override
  String get onboardingSelectAppLanguage => 'Idioma de la app';

  @override
  String onboardingSelectRecommendedFor(String language) {
    return 'Recomendado para $language';
  }

  @override
  String get onboardingSelectYourChoice => 'Tu elección';

  @override
  String get onboardingSelectSearchLanguage => 'Buscar idioma';

  @override
  String get onboardingWelcomeStart => 'Configurar';

  @override
  String get onboardingWelcomeLaterChangeable =>
      'Puedes cambiar el modelo de voz en cualquier momento en Ajustes.';

  @override
  String get onboardingReviewExit => 'Cerrar introducción';

  @override
  String get onboardingReviewDone => 'Hecho';

  @override
  String get onboardingReviewEntry => 'Introducción';

  @override
  String get onboardingReviewLabel => 'Repasar la introducción';

  @override
  String get onboardingReviewAction => 'Abrir';

  @override
  String get onboardingRevisionNoticeTitle =>
      'WhisPaste se ha actualizado; tus ajustes no han cambiado.';

  @override
  String get onboardingRevisionNoticeExpand => 'Mostrar todas las novedades';

  @override
  String get onboardingRevisionNoticeCollapse => 'Mostrar menos';

  @override
  String get onboardingRevisionExit => 'Salir de la introducción';

  @override
  String get onboardingRevisionExitConfirmTitle => '¿Salir de la introducción?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Esta introducción solo se muestra una vez. Lo que saltes ahora no se configurará por ti; puedes configurarlo después en Ajustes. Los pasos también están en la página Ayuda, en «Repasar la introducción». Lo que ya hayas configurado no cambia.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Salir';

  @override
  String get overlayRecording => 'Grabando';

  @override
  String get overlayTranscribing => 'Procesando…';

  @override
  String transcribingSliceProgress(int current, int total) {
    return 'Procesando parte $current de $total…';
  }

  @override
  String get overlayRefining => 'Refinando…';

  @override
  String get overlayStarting => 'Iniciando…';

  @override
  String get overlayDone => 'Copiado';

  @override
  String get overlayDonePasted => 'Pegado';

  @override
  String get overlayDoneBoth => 'Copiado y pegado';

  @override
  String get overlayDoneReady => 'Listo';

  @override
  String get overlayError => 'Error';

  @override
  String get overlayCancel => 'Cancelar';

  @override
  String get overlayPause => 'Pausar';

  @override
  String get overlayResume => 'Reanudar';

  @override
  String get overlayStop => 'Detener';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'Pulsa $hotkey para detener';
  }

  @override
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey para detener · $cancelKey para cancelar';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return '¿Descartar la grabación? Pulsa $cancelKey de nuevo';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Intro o $hotkey: siguiente campo · Esc: cancelar';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Intro: siguiente campo · Esc: cancelar';

  @override
  String get overlayProcessingLocal => 'Local';

  @override
  String get overlayProcessingCloud => 'Nube';

  @override
  String get overlayRecordingQuickNote => 'Grabando en nota';

  @override
  String get overlayTargetQuickNote => 'Nota';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayMicSignalLost => 'Sin señal del micrófono';

  @override
  String get overlayDoneQuickNote => 'Añadido a la nota';

  @override
  String get floatingButtonHide => 'Ocultar';

  @override
  String get floatingButtonQuit => 'Salir';

  @override
  String get a11yRecordingButton => 'Botón de grabación';

  @override
  String get a11yRecordingOverlay => 'Superposición de grabación';

  @override
  String get a11ySidePanel => 'Panel de pegado rápido';

  @override
  String get trayStatusRecording => 'Grabando…';

  @override
  String get trayStatusReady => 'Listo';

  @override
  String get trayStartRecording => 'Iniciar grabación';

  @override
  String get trayStopRecording => 'Detener grabación';

  @override
  String get trayOpenApp => 'Abrir WhisPaste';

  @override
  String get trayTranscribeFile => 'Transcribir archivo…';

  @override
  String get trayOpenSidePanel => 'Abrir panel de pegado rápido';

  @override
  String get traySettings => 'Ajustes';

  @override
  String get trayResumeOnboarding => 'Reanudar configuración';

  @override
  String get onboardingCloseTitle =>
      '¿Pausar la configuración o cerrar WhisPaste?';

  @override
  String get onboardingCloseBodyPause =>
      'Al pausar se cierra la ventana. WhisPaste sigue en segundo plano y se abre desde el icono de la bandeja o la barra de menús.';

  @override
  String get onboardingCloseBodyNoTray =>
      'Sin icono de bandeja, WhisPaste no puede seguir en segundo plano. Cerrar detiene WhisPaste. En el próximo inicio, la configuración continúa donde lo dejaste.';

  @override
  String get onboardingClosePause => 'Pausar';

  @override
  String get onboardingCloseContinue => 'Seguir configurando';

  @override
  String get onboardingReviewHintMessage =>
      'Nuevo: comprobar la prueba del micrófono y la inserción';

  @override
  String get onboardingReviewHintAction => 'Abrir';

  @override
  String get trayQuit => 'Salir';

  @override
  String get trayRecentRecordings => 'Grabaciones recientes';

  @override
  String get trayUnlockRecordings => 'Desbloquear grabaciones…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count palabras',
      one: '1 palabra',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'Enviar comentarios…';

  @override
  String get quitDuringDictationTitle => 'Una grabación sigue en curso';

  @override
  String get quitDuringDictationMessage =>
      'Si cierras ahora, se detiene la grabación o transcripción en curso y su texto se pierde.';

  @override
  String get trayMicrophone => 'Micrófono';

  @override
  String get settingsComingSoon => 'Próximamente';

  @override
  String get undo => 'Deshacer';

  @override
  String get hintDismiss => 'Cerrar aviso';

  @override
  String get voiceNoteButton => 'Nota de voz';

  @override
  String get voiceNoteRecording => 'Grabando nota de voz…';

  @override
  String get voiceNoteTranscribing => 'Transcribiendo…';

  @override
  String get voiceNoteAdded => 'Nota de voz añadida';

  @override
  String voiceTagAdded(String tag) {
    return 'Etiqueta «$tag» añadida por voz';
  }

  @override
  String get voiceCorrectionApplied => 'Transcripción corregida por voz';

  @override
  String get voiceCorrectionUndone => 'Corrección deshecha';

  @override
  String get voiceNoteEmpty => 'No se ha detectado voz';

  @override
  String get voiceNoteError => 'La nota de voz ha fallado';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'Nota de voz: di «tag: …» para añadir una etiqueta, o «correct: …» para sustituir esta transcripción';

  @override
  String updateAvailable(String version) {
    return 'Actualización disponible: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Descargando actualización… $percent%';
  }

  @override
  String get updateReadyToInstall =>
      'Actualización lista, haz clic para instalar';

  @override
  String get updateUpToDate => 'Tienes la última versión';

  @override
  String get updateCheckNow => 'Buscar ahora';

  @override
  String get updateInstall => 'Instalar actualización';

  @override
  String get updateDownload => 'Descargar';

  @override
  String get updateViewRelease => 'Notas de la versión';

  @override
  String get updateError => 'No se pudo comprobar si hay actualizaciones';

  @override
  String get updateInstallAfterRecording =>
      'La actualización se instalará al terminar la grabación';

  @override
  String get updateInstallerMissing =>
      'Falta el archivo de instalación. Busca actualizaciones de nuevo.';

  @override
  String get updateInstallFailed =>
      'No se pudo iniciar la instalación. Vuelve a intentar instalar la actualización.';

  @override
  String get updateInstallRetry => 'Volver a instalar';

  @override
  String get updateRateLimited => 'Demasiadas solicitudes, inténtalo más tarde';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version disponible';
  }

  @override
  String get settingsOverlaySize => 'Tamaño de superposición';

  @override
  String get settingsOverlaySizeSubtitle =>
      'Elige entre una vista detallada o mínima';

  @override
  String get settingsOverlaySizeNormal => 'Normal';

  @override
  String get settingsOverlaySizeCompact => 'Compacto';

  @override
  String get settingsOverlaySizeMini => 'Mini';

  @override
  String get settingsOverlayColors => 'Colores del overlay';

  @override
  String get settingsOverlayBackground => 'Fondo del overlay y del botón';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'Se aplica al overlay de grabación y al botón flotante.';

  @override
  String get settingsOverlayBackgroundMarine => 'Marino';

  @override
  String get settingsOverlayBackgroundGraphit => 'Grafito';

  @override
  String get settingsOverlayBackgroundGletscher => 'Glaciar';

  @override
  String get settingsOverlayBackgroundAmber => 'Ámbar';

  @override
  String get settingsOverlayWave => 'Color de la onda para overlay y botón';

  @override
  String get settingsOverlayWaveSubtitle =>
      'Se aplica al overlay de grabación y al botón flotante: onda y anillo de grabación.';

  @override
  String get settingsOverlayWaveCyan => 'Cian';

  @override
  String get settingsOverlayWaveViolett => 'Violeta';

  @override
  String get settingsOverlayWaveAmber => 'Ámbar';

  @override
  String get settingsOverlayWaveInk => 'Tinta';

  @override
  String get settingsOverlayWaveCoral => 'Coral';

  @override
  String get settingsOverlayWaveMint => 'Menta';

  @override
  String get settingsOverlayWaveUnavailable => 'No se ve bien sobre este fondo';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '«$from» no se ve bien sobre este fondo. La onda cambió a «$to».';
  }

  @override
  String get settingsOverlayLiveTranscript => 'Transcripción en vivo';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'Muestra el texto reconocido mientras sigues hablando, en lugar de solo la forma de onda. Consume más CPU durante la grabación';

  @override
  String get overlayRetry => 'Reintentar';

  @override
  String get overlayDismiss => 'Cerrar';

  @override
  String get overlayContextCancel => 'Cancelar grabación';

  @override
  String get overlayContextSwitchNormal => 'Cambiar a Normal';

  @override
  String get overlayContextSwitchCompact => 'Cambiar a Compacto';

  @override
  String get overlayContextSwitchMini => 'Cambiar a Mini';

  @override
  String get overlayContextHide => 'Ocultar superposición';

  @override
  String get buttonContextOpen => 'Abrir WhisPaste';

  @override
  String get buttonContextStartRecording => 'Iniciar grabación';

  @override
  String get buttonContextShowHistory => 'Mostrar grabaciones';

  @override
  String get buttonContextSettings => 'Ajustes';

  @override
  String get buttonContextQuit => 'Salir de WhisPaste';

  @override
  String get settingsHistory => 'Grabaciones';

  @override
  String get settingsHistorySubtitle => 'Retención y limpieza automática';

  @override
  String get settingsHistoryMaxEntries => 'Máximo de entradas';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'Sin límite';

  @override
  String get settingsHistoryAutoTrashDays => 'Vaciar la papelera tras';

  @override
  String get settingsHistoryAutoTrashNever => 'Nunca';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String get settingsHistoryRetentionPreset => 'Retención';

  @override
  String get settingsHistoryPresetMinimal => 'Mínima';

  @override
  String get settingsHistoryPresetStandard => 'Estándar';

  @override
  String get settingsHistoryPresetUnlimited => 'Sin límite';

  @override
  String get settingsHistoryPresetCustom => 'Personalizada';

  @override
  String get settingsHistoryHideOnOpen => 'Ocultar grabaciones al abrir';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Muestra un botón «Mostrar grabaciones» en lugar de tus transcripciones cada vez que WhisPaste se inicia o se vuelve a abrir su ventana. No se borra nada.';

  @override
  String get settingsHistorySave => 'Guardar grabaciones';

  @override
  String get settingsHistorySaveSubtitle =>
      'Desactivado: un dictado solo se pega o se copia. No se guarda nada en Grabaciones y no se conserva audio. Las estadísticas y el recordatorio de valoración siguen funcionando. Los archivos importados siguen guardándose en Grabaciones.';

  @override
  String get settingsHistoryDeleteExisting => 'Borrar grabaciones existentes';

  @override
  String get settingsHistoryDeleteExistingSubtitle =>
      'Elimina todas las grabaciones guardadas, también las archivadas y las de la papelera. Las notas no se ven afectadas.';

  @override
  String get settingsHistoryDeleteExistingAction => 'Borrar grabaciones…';

  @override
  String get settingsHistorySaveDeleteTitle =>
      '¿Borrar también las grabaciones existentes?';

  @override
  String get settingsHistorySaveDeleteMessage =>
      'Los nuevos dictados ya no se guardan. Las grabaciones que ya tienes se mantienen hasta que las borres.';

  @override
  String get settingsHistorySaveDeleteKeep => 'Conservarlas';

  @override
  String get settingsHistoryDeleteConfirm => 'Borrar grabaciones';

  @override
  String get settingsHistoryDeleteMessage =>
      'Todas las grabaciones guardadas se eliminan de forma definitiva, también las archivadas y las de la papelera. Las notas no se ven afectadas. No se puede deshacer.';

  @override
  String get historyOffTitle => 'Las grabaciones están desactivadas';

  @override
  String get historyOffHint =>
      'Los nuevos dictados no se guardan aquí. El texto se pega o se copia como de costumbre. Los archivos importados siguen apareciendo aquí.';

  @override
  String get historyOffAction => 'Abrir el ajuste';

  @override
  String get historyPinGateTitle => 'Las grabaciones están bloqueadas';

  @override
  String get historyPinGateHint =>
      'Introduce tu PIN para mostrar tus transcripciones.';

  @override
  String get historyImportUnlockHint =>
      'Desbloquea Grabaciones para transcribir el archivo.';

  @override
  String get historyPinUnlock => 'Desbloquear';

  @override
  String get historyPinDialogTitle => 'Introduce el PIN';

  @override
  String get historyPinDialogSubtitle =>
      'Tus grabaciones están protegidas con un PIN.';

  @override
  String get historyPinFieldHint => 'PIN';

  @override
  String get historyPinRepeatHint => 'Repite el PIN';

  @override
  String get historyPinWrong => 'PIN incorrecto.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'Demasiados intentos. Inténtalo de nuevo en $seconds s.';
  }

  @override
  String get historyPinForgot => '¿Has olvidado el PIN?';

  @override
  String get historyPinForgotHint =>
      'Restablecer elimina de inmediato todas las grabaciones, los archivos de audio guardados, las notas con sus versiones y las imágenes de las notas. Si un archivo no se puede borrar, WhisPaste muestra un aviso.';

  @override
  String get historyPinForgotConfirmTitle =>
      '¿Borrar grabaciones y notas y quitar el PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Un PIN olvidado no se puede recuperar. Para restablecerlo, se borran de inmediato y de forma permanente todas las grabaciones y archivos de audio guardados (incluidos archivo y papelera), todas las notas con sus versiones (incluida la papelera) y todas las imágenes de las notas. Los ajustes, fragmentos y reemplazos se conservan. Si un archivo no se puede borrar, WhisPaste muestra un aviso.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'No se pudieron borrar algunas grabaciones, importaciones o imágenes de notas. WhisPaste las eliminará la próxima vez que se inicie.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'No se pudieron eliminar algunas grabaciones o importaciones, y WhisPaste no puede reintentarlo más tarde. Bórralas manualmente. Ubicación: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'No se pudo eliminar una copia de la base de datos anterior ($path). Bórrala manualmente.';
  }

  @override
  String get historyPinForgotConfirmAction => 'Eliminar';

  @override
  String get historyPinSetTitle => 'Definir PIN';

  @override
  String get historyPinSetSubtitle =>
      'De 4 a 8 dígitos. Evita que otros vean tus transcripciones en este ordenador con facilidad; no las cifra.';

  @override
  String get historyPinInvalid => 'Usa entre 4 y 8 dígitos.';

  @override
  String get historyPinMismatch => 'Los PIN no coinciden.';

  @override
  String get settingsHistoryPin => 'Protección con PIN';

  @override
  String get settingsHistoryPinSubtitle =>
      'Requerir un PIN para mostrar grabaciones y notas, también en el panel lateral, el menú del botón flotante y la API de automatización.';

  @override
  String get settingsHistoryPinChange => 'Cambiar';

  @override
  String get settingsHistoryPinRemove => 'Quitar';

  @override
  String get settingsHistoryAutoLock => 'Bloquear automáticamente';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Vuelve a ocultar las grabaciones tras este tiempo de inactividad.';

  @override
  String get settingsHistoryAutoLockNever => 'Nunca';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Tras $minutes min';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'Activa el botón flotante para cambiar esto.';

  @override
  String get settingsFloatingButtonSection => 'Botón flotante';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Botón de grabación siempre visible sobre otras ventanas, para un acceso rápido';

  @override
  String get settingsFloatingButtonWaylandTitle => 'Límites de Wayland';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'Con Wayland, el escritorio decide dónde aparece el botón y si se mantiene encima. WhisPaste solo puede garantizar ambas cosas de forma limitada. Grabar con un clic sigue funcionando, y el botón no toma el foco del teclado.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'No disponible en este escritorio Linux: el botón necesita X11 o XWayland. Seguir desactivándolo es posible.';

  @override
  String get settingsSttIdleTimeout =>
      'Tiempo de inactividad del modelo de voz';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Cuánto tiempo permanece cargado el modelo de voz tras su último uso';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Mantener activo';

  @override
  String get settingsSttKeepLoaded => 'Mantener el modelo cargado';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'Un modelo cargado inicia el dictado sin esperar a que se cargue. Mientras esté cargado, ocupa memoria.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'Cargado, el modelo necesita unos $size de memoria.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'La memoria de la GPU ($vramMb MB) no basta para este modelo ($requiredMb MB). Se ejecuta en la CPU.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'Siempre';

  @override
  String get settingsSttKeepLoadedAutomatic => 'Automático';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'Tras un periodo de inactividad';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'Descargar tras';

  @override
  String settingsSttIdleTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get reviewSupportEntry => 'Valora y apoya WhisPaste';

  @override
  String get reviewSupportLabel => 'Valorar la app';

  @override
  String get reviewSupportAction => 'Valorar';

  @override
  String get reviewSupportGitHubLabel =>
      'Apoya WhisPaste con una estrella en GitHub';

  @override
  String get reviewSupportGitHubAction => 'Ver en GitHub';

  @override
  String get ideasBoardLabel => 'Ideas y peticiones de funciones';

  @override
  String get ideasBoardAction => 'Ver el tablero';

  @override
  String get feedbackIdeasLink => 'Sugerir y votar ideas';

  @override
  String get feedbackTypeProblem => 'Problema';

  @override
  String get feedbackTypeIdea => 'Idea';

  @override
  String get feedbackTypePraise => 'Elogio';

  @override
  String get feedbackTypeQuestion => 'Pregunta';

  @override
  String get feedbackPromptProblem =>
      '¿Qué ha fallado? Cuéntanos qué hiciste y qué pasó.';

  @override
  String get feedbackPromptIdea => '¿Qué haría WhisPaste mejor para ti?';

  @override
  String get feedbackPromptPraise => '¿Qué te funciona bien?';

  @override
  String get feedbackPromptQuestion => '¿Qué te gustaría saber?';

  @override
  String get feedbackDiagnosticsLabel => 'Adjuntar diagnóstico';

  @override
  String get feedbackDiagnosticsExplanation =>
      'Añade la versión de la app, el sistema operativo, el motor de reconocimiento de voz y el backend. Tus dictados y textos nunca se adjuntan.';

  @override
  String get feedbackDiagnosticsPreview => 'Mostrar vista previa';

  @override
  String get feedbackDiagnosticsPreviewHide => 'Ocultar vista previa';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'Este texto exacto se añade a tu mensaje:';

  @override
  String get feedbackIdeaBoardHint =>
      'También puedes publicar tu idea en el tablero público de ideas y votar por las de otros.';

  @override
  String get feedbackTextTooLong =>
      'El texto es demasiado largo para adjuntar el diagnóstico. Acórtalo un poco.';

  @override
  String get hotkeyRegistrationFailed =>
      'No se pudo registrar el atajo; vuelve a asignarlo en Ajustes.';

  @override
  String get hotkeySelfHealFailed =>
      'El atajo dejó de responder y no se pudo restaurar. Reinicia WhisPaste para solucionarlo.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken ya lo usa otra aplicación. Hasta que elijas otra combinación, $active inicia la grabación.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'Otra aplicación tiene el atajo de $action. Seguirá desactivado hasta que elijas una combinación libre en Ajustes.';
  }

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Este atajo está reservado por $platform ($note) y puede no funcionar.';
  }

  @override
  String hotkeyConflictWarningDesktop(String note) {
    return 'Tu escritorio reserva esta combinación de teclas: $note. Puede que no funcione.';
  }

  @override
  String get exportFormatPickerTitle => 'Elige el formato de exportación';

  @override
  String get exportFormatText => 'Texto';

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
      'La transcripción está tardando un poco más de lo habitual, pero sigue en marcha.';

  @override
  String get recoveryExhaustedToast =>
      'El modelo de voz no puede iniciarse. Reinicia la app o vuelve a cargar el modelo de voz.';

  @override
  String get recoveryExhaustedAction => 'Abrir Ajustes';

  @override
  String get recoveryVcRuntimeToast =>
      'El modelo de voz no puede iniciarse: falta un componente de Windows (Microsoft Visual C++). Instala Visual C++ Redistributable (x64) y reinicia WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Instalar';

  @override
  String get modelAbiInfoToast =>
      'Recargando el modelo de voz, espera un momento.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste funciona ahora sin aceleración por GPU debido a un problema en el último inicio. La grabación sigue funcionando como siempre.';

  @override
  String get serverDownloadFailedToast =>
      'No se pudo descargar el modelo de voz. ¿Compruebas tu conexión a internet?';

  @override
  String get serverDownloadFailedAction => 'Reintentar';

  @override
  String get serverDownloadStalledToast =>
      'Descarga interrumpida: reconectando.';

  @override
  String get historyWriteFailedToast =>
      'No se pudo guardar la entrada; comprueba el espacio de almacenamiento disponible.';

  @override
  String get historyWriteFailedAction => 'Copiar diagnóstico';

  @override
  String get errorSttRejectEmpty =>
      'No hay audio que transcribir; graba de nuevo.';

  @override
  String get errorSttRejectInvalidWav =>
      'El archivo de audio está dañado; graba de nuevo.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'El modelo de voz local no admite este idioma; revísalo en Ajustes.';

  @override
  String get errorSttRejectPromptTooLong =>
      'El vocabulario personalizado es demasiado largo; acórtalo en Ajustes.';

  @override
  String get settingsGpuAcceleration => 'Aceleración gráfica';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Automático usa la tarjeta gráfica si está disponible. «Solo CPU» es más lento, pero funciona en cualquier equipo. Forzar GPU solo si el modo automático no funciona.';

  @override
  String get settingsGpuAccelerationAuto => 'Automática (recomendada)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (forzada)';

  @override
  String get settingsGpuAccelerationDisabled => 'Solo CPU';

  @override
  String get settingsSttEngine => 'Modelo de voz';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 idiomas. Parakeet: más rápido, unos 25 idiomas.';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet';

  @override
  String get settingsSttEngineRecommended => 'Recomendado';

  @override
  String get parakeetModelTitle => 'Modelo Parakeet';

  @override
  String parakeetModelSubtitle(String size) {
    return 'Descarga única ($size); después funciona totalmente sin conexión';
  }

  @override
  String get parakeetModelDownload => 'Descargar';

  @override
  String get parakeetModelDownloading => 'Descargando…';

  @override
  String get parakeetModelInstalled => 'Instalado';

  @override
  String get parakeetModelDelete => 'Eliminar';

  @override
  String get parakeetModelCancel => 'Cancelar';

  @override
  String get settingsSearchHint => 'Buscar en Ajustes…';

  @override
  String get settingsSearchNoResults => 'Sin resultados';

  @override
  String get settingsSearchNoResultsHint =>
      'Prueba con otro término de búsqueda.';

  @override
  String get settingsSearchFieldLabel => 'Buscar en Ajustes';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Sin resultados',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'Privacidad';

  @override
  String get settingsPrivacySubtitle => 'Controla qué datos comparte WhisPaste';

  @override
  String get settingsShareUsageStats => 'Ayuda a mejorar WhisPaste';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Cifras de uso sin cookies, enviadas a nuestro propio servidor en la UE. Nunca tu audio ni tu texto.';

  @override
  String get settingsRetainRecentAudio =>
      'Conservar audio de grabaciones recientes';

  @override
  String get settingsFailedAudioKeep =>
      'Conservar las grabaciones fallidas durante';

  @override
  String get settingsFailedAudioKeepSubtitle =>
      'El audio de una grabación cuya transcripción falló se conserva este tiempo para reintentarla y después se elimina.';

  @override
  String settingsFailedAudioKeepDisabled(int days) {
    return 'No se usa mientras la conservación de audio está activada. Entonces se aplica el plazo de conservación de $days días.';
  }

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'Guarda en este dispositivo el audio de tus últimas $count grabaciones para depurar o recuperar una transcripción anterior; las grabaciones y los archivos importados se eliminan automáticamente como máximo tras $days días';
  }

  @override
  String get pendingAudioRetentionNote =>
      'Una grabación cuya transcripción falla conserva su audio para que puedas reintentarla, aunque esta opción esté desactivada.';

  @override
  String get pendingAudioSectionTitle => 'Grabaciones pendientes de reintentar';

  @override
  String get pendingAudioSectionBody =>
      'Estas grabaciones no se pudieron transcribir, por ejemplo porque se cortó la conexión. El audio se elimina en la fecha que aparece en cada grabación o cuando lo descartas.';

  @override
  String pendingAudioKeptUntil(String until) {
    return 'El audio se conserva hasta $until y después se elimina.';
  }

  @override
  String get pendingAudioEmpty => 'No hay grabaciones pendientes.';

  @override
  String get notesNewNote => 'Nueva nota';

  @override
  String get notesEmptyTitle => 'Aún no hay notas';

  @override
  String get notesEmptyHint =>
      'Crea una nota para empezar a reunir texto desde cualquier lugar.';

  @override
  String get notesUntitled => 'Nota sin título';

  @override
  String get notesEditorPlaceholder => 'Empieza a escribir…';

  @override
  String get notesListSemantics => 'Lista de notas';

  @override
  String get notesCopy => 'Copiar nota';

  @override
  String get notesCopied => 'Nota copiada';

  @override
  String get notesFavorite => 'Marcar como favorita';

  @override
  String get notesUnfavorite => 'Quitar de favoritas';

  @override
  String get notesQuickNoteSet =>
      'Usar como nota rápida a la que añade el atajo';

  @override
  String get notesQuickNoteClear => 'Nota rápida: quitar la marca';

  @override
  String get notesQuickNoteHotkeyLabel => 'Atajo';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'Cambiar el atajo de nota rápida; actualmente $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff =>
      'El atajo de nota rápida está desactivado.';

  @override
  String get notesQuickNoteHotkeyEnable => 'Activar atajo';

  @override
  String get notesMoveToTrash => 'Mover a la papelera';

  @override
  String get notesMovedToTrash => 'Movida a la papelera';

  @override
  String get notesRestore => 'Restaurar';

  @override
  String get notesDeleteForever => 'Eliminar para siempre';

  @override
  String get notesDeleteForeverConfirm => '¿Eliminar la nota para siempre?';

  @override
  String get notesTrash => 'Papelera';

  @override
  String get notesTrashEmpty => 'La papelera está vacía';

  @override
  String get notesTrashEmptyHint =>
      'Las notas eliminadas llegan aquí y no se borran automáticamente.';

  @override
  String get notesUndo => 'Deshacer';

  @override
  String get notesAddTag => 'Añadir etiqueta';

  @override
  String get notesTagPlaceholder => 'Nombre de la etiqueta…';

  @override
  String get notesSearchPlaceholder => 'Buscar notas…';

  @override
  String get notesSearchFieldLabel => 'Buscar notas';

  @override
  String get notesNoResults => 'Sin resultados';

  @override
  String notesNoResultsHint(String query) {
    return 'Ninguna nota coincide con «$query».\nPrueba con otro término de búsqueda.';
  }

  @override
  String notesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
    );
    return '$_temp0';
  }

  @override
  String get notesExport => 'Exportar';

  @override
  String markdownToolbarBold(String shortcut) {
    return 'Negrita ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'Cursiva ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'Encabezado';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'Lista con viñetas ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'Lista numerada';

  @override
  String get markdownToolbarQuote => 'Cita';

  @override
  String get markdownToolbarCode => 'Código';

  @override
  String get findReplaceToggle => 'Buscar y reemplazar en este texto';

  @override
  String get findReplaceFindLabel => 'Buscar en este texto';

  @override
  String get findReplaceFindHint => 'Buscar…';

  @override
  String get findReplaceReplaceLabel => 'Reemplazar coincidencias por';

  @override
  String get findReplaceReplaceHint => 'Reemplazar por…';

  @override
  String get findReplaceNext => 'Siguiente coincidencia';

  @override
  String get findReplacePrevious => 'Coincidencia anterior';

  @override
  String get findReplaceReplaceAction => 'Reemplazar esta coincidencia';

  @override
  String get findReplaceReplaceAllAction =>
      'Reemplazar todas las coincidencias';

  @override
  String get findReplaceClose => 'Cerrar buscar y reemplazar';

  @override
  String get findReplaceNoMatches => 'Sin coincidencias';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current de $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'Transcripciones';

  @override
  String get sidePanelSnippetsTitle => 'Snippets';

  @override
  String get sidePanelClipboardHistoryTitle => 'Historial del portapapeles';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Nada copiado todavía';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Lo que copies mientras WhisPaste está en ejecución aparecerá aquí; se borra al reiniciar la app.';

  @override
  String get sidePanelClipboardLockedTitle => 'Bloqueado por PIN';

  @override
  String get sidePanelClipboardLockedHint =>
      'El texto copiado permanece oculto mientras las grabaciones están bloqueadas. Desbloquéalas con tu PIN para verlo de nuevo.';

  @override
  String get sidePanelClose => 'Cerrar panel';

  @override
  String get sidePanelSearchHint => 'Buscar';

  @override
  String get sidePanelSearchFieldLabel => 'Buscar en esta lista';

  @override
  String get sidePanelNoMatches => 'Sin coincidencias';

  @override
  String get sidePanelNoMatchesHint => 'Prueba con otro término de búsqueda.';

  @override
  String get sidePanelLoadFailedHint =>
      'Cierra el panel y vuelve a abrirlo para intentarlo de nuevo.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Limpieza, acortado y traducción local del texto tras la grabación';

  @override
  String get smartModeStandardPreset => 'Preset estándar';

  @override
  String get smartModePresetOff => 'Desactivado';

  @override
  String get smartModePresetOffDescription =>
      'Sin posprocesado automático: el texto transcrito se usa exactamente como se transcribió.';

  @override
  String get smartModePresetCleanup => 'Limpieza';

  @override
  String get smartModePresetCleanupDescription =>
      'Elimina muletillas como «eh» y corrige la puntuación y las mayúsculas, sin cambiar la redacción, el significado ni el idioma.';

  @override
  String get smartModePresetConcise => 'Conciso';

  @override
  String get smartModePresetConciseDescription =>
      'Acorta el texto eliminando redundancias y muletillas, pero conserva todos los datos importantes, en el mismo idioma.';

  @override
  String get smartModePresetTranslate => 'Traducir';

  @override
  String get smartModePresetTranslateDescription =>
      'Traduce el texto transcrito al idioma de destino que se indica abajo.';

  @override
  String get smartModeTargetLanguage => 'Idioma de destino';

  @override
  String get smartModeTargetLanguageGerman => 'Alemán';

  @override
  String get smartModeTargetLanguageEnglish => 'Inglés';

  @override
  String get smartModeTargetLanguageSpanish => 'Español';

  @override
  String get smartModeTargetLanguageFrench => 'Francés';

  @override
  String get smartModeTargetLanguagePortuguese => 'Portugués';

  @override
  String get smartModeTargetLanguageMandarin => 'Mandarín';

  @override
  String get smartModeTargetLanguageRussian => 'Ruso';

  @override
  String get smartModeDownload => 'Descargar';

  @override
  String get smartModeDownloadComplete => 'Modelo de texto listo para usar';

  @override
  String get smartModeRamWarningTitle => 'Memoria limitada detectada';

  @override
  String get smartModeRamWarningBody =>
      'El modelo de texto local de Smart Mode funciona mejor con 8 GB de RAM o más. Puede que siga funcionando, pero podría ir lento o fallar en este equipo. ¿Descargar de todos modos?';

  @override
  String get smartModeRamWarningContinue => 'Descargar de todos modos';

  @override
  String get smartModeRamWarningCancel => 'Cancelar';

  @override
  String get modelRamPrecheckTitle => 'Poca memoria libre';

  @override
  String modelRamPrecheckBody(String requiredMb, String availableMb) {
    return 'Este modelo necesita unos $requiredMb MB de memoria y ahora mismo hay unos $availableMb MB libres. Puede ir lento o no cargarse. ¿Cargarlo de todos modos?';
  }

  @override
  String get modelRamPrecheckContinue => 'Cargar de todos modos';

  @override
  String modelRamStartupHint(String requiredMb, String availableMb) {
    return 'El modelo de voz elegido necesita unos $requiredMb MB de memoria y ahora hay unos $availableMb MB libres. Se carga igualmente; cierra otras apps si el dictado va lento.';
  }

  @override
  String get smartModeModelDeleteConfirm => '¿Eliminar este modelo de texto?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'El archivo del modelo de texto se borra de este dispositivo. Puedes volver a descargarlo en cualquier momento.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Con el modelo de texto local, todo se ejecuta en el dispositivo. Mientras está activo, el modelo de texto usa unos 4–5 GB de RAM además del espacio en disco; la memoria se comparte con el modelo de voz, así que el uso total depende del modelo de voz que tengas cargado.';

  @override
  String get smartModeFactGuardHint =>
      'El guardián de hechos revisa números, fechas, enlaces, direcciones de correo e IBAN. Los nombres del diccionario se mantienen. Las instrucciones libres pueden cambiar nombres que no están en el diccionario; añádelos al diccionario si deben conservarse.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Ejemplo: una grabación típica de 50 palabras tarda entre 1 y 6 segundos en procesarse, según el hardware del dispositivo.';

  @override
  String get smartModeLocalUnavailable =>
      'Smart Mode en el dispositivo no está incluido en esta versión. Cambia a OpenAI o instala una versión oficial de WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Grabar con Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Inicia una grabación con un preset fijo, independiente del preset estándar de Smart Mode. «Mantener para grabar» también se aplica aquí.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Preset';

  @override
  String get settingsSmartModeCurrentHotkey => 'Atajo actual';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Esta combinación ya se usa para «$action». Elige otra.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Esta combinación no se pudo registrar; el atajo de Smart Mode no está activo ahora mismo. Elige otra.';

  @override
  String get smartModeOnboardingHintTitle => 'Prueba Smart Mode';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'Smart Mode puede limpiar, acortar o traducir tu texto de forma automática, por defecto, totalmente en tu dispositivo. El modelo de texto local ocupa $size en el disco. Descárgalo ahora o configúralo más tarde en Ajustes.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Texto original';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'pues eh la reunión con el cliente se cambió al jueves a las tres de la tarde y todavía necesitamos las diapositivas actualizadas de marketing';

  @override
  String get smartModeOnboardingHintExampleAfterLabel =>
      'Resultado de Smart Mode';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'Así que la reunión con el cliente pasó al jueves a las tres de la tarde, y todavía necesitamos las diapositivas actualizadas de marketing.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Descargar';

  @override
  String get smartModeOnboardingHintSkipCta => 'Más tarde';

  @override
  String get smartModeUsageHintTitle =>
      'Prueba Smart Mode en tu próxima grabación';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode puede limpiar, acortar o traducir un texto como este de forma automática, directamente en tu dispositivo. Esto es lo que acabas de decir:';

  @override
  String get smartModeUsageHintCta => 'Configurar';

  @override
  String get smartModeUsageHintDismiss => 'Ahora no';

  @override
  String get settingsAutomationApi => 'API de automatización local';

  @override
  String get settingsAutomationApiSubtitle =>
      'Otros programas y scripts de este equipo pueden controlar WhisPaste, por ejemplo iniciar una grabación. Otros dispositivos de la red no pueden acceder.';

  @override
  String get settingsAutomationApiEnable =>
      'Activar la API de automatización local';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'Se enlaza solo a 127.0.0.1/::1; nunca es accesible desde la red';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'En ejecución en el puerto $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'En ejecución en el puerto $port (el puerto $requestedPort estaba en uso)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'No se está ejecutando';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'No hay ningún puerto libre en el rango $start–$end';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'Puerto personalizado';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'Déjalo vacío para elegir el puerto automáticamente; si está ocupado, se usa otro';

  @override
  String get settingsAutomationApiCustomPortHint => 'Automático';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'Introduce un puerto entre 1024 y 65535';

  @override
  String get settingsAutomationApiToken => 'Token Bearer';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'Envíalo como «Authorization: Bearer <token>»; las solicitudes sin él se rechazan';

  @override
  String get settingsAutomationApiRegenerate => 'Regenerar';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle =>
      '¿Regenerar el token?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'El token actual deja de funcionar de inmediato. Cualquier script que lo use necesitará el nuevo.';

  @override
  String get settingsAutomationApiCopyToken => 'Copiar token';

  @override
  String get settingsAutomationApiTokenCopied =>
      'Token copiado al portapapeles';

  @override
  String get settingsAutomationApiDocumentation => 'Documentación';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'Referencia de endpoints y ejemplos con curl';

  @override
  String get settingsAutomationApiDocumentationAction => 'Abrir';

  @override
  String historyCharacterCount(int count) {
    return '$count caracteres';
  }

  @override
  String historyPastedInto(String app) {
    return 'Pegado en $app';
  }

  @override
  String get historyShowOriginalTranscript => 'Mostrar transcripción original';

  @override
  String get historyHideOriginalTranscript => 'Ocultar transcripción original';

  @override
  String get historyOriginalTranscriptLabel => 'Transcripción original';

  @override
  String get settingsHotkeyActionSelectionEdit => 'Editar selección';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'Editar selección';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Selecciona texto en cualquier app, pulsa este atajo y di qué cambiar, o simplemente «más corto», «mejorar» o «traducir». El resultado reemplaza la selección; deshacer en la app restaura el original. Usa el modelo de texto configurado en Smart Mode.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'Esta combinación no se pudo registrar; el atajo de edición de selección no está activo ahora mismo. Elige otra.';

  @override
  String get overlayTargetSelectionEdit => 'Editar selección';

  @override
  String get overlayRecordingSelectionEdit => 'Di qué cambiar';

  @override
  String get overlaySelectionEditHint =>
      'Di qué cambiar, o di: más corto · mejorar · traducir';

  @override
  String get overlayEditingSelection => 'Editando selección…';

  @override
  String get overlayDoneSelectionEdit => 'Selección reemplazada';

  @override
  String get errorSelectionEditNoSelection =>
      'No hay texto seleccionado: selecciona texto primero y luego pulsa el atajo';

  @override
  String get errorSelectionEditNoEngine =>
      'Configura primero Smart Mode (descarga el modelo de texto local o añade una clave de OpenAI) para editar selecciones';

  @override
  String get errorSelectionEditUnsupported =>
      'Editar una selección requiere Auto-Paste, que no está disponible en esta versión';

  @override
  String get errorSelectionEditCopyFailed =>
      'No se pudo leer la selección; revisa el permiso de Auto-Paste';

  @override
  String get errorSelectionEditFailed =>
      'La edición falló; tu texto no ha cambiado';

  @override
  String get errorSelectionEditFactsChanged =>
      'La edición cambiaría datos que tu instrucción no menciona; tu texto no ha cambiado';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'La edición cambiaría «$value» sin que tu instrucción lo nombre. Nombra el valor antiguo y el nuevo, p. ej. «cambia 3 a 5»; tu texto no ha cambiado';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'No se pudo reemplazar la selección; tu texto no ha cambiado';

  @override
  String get settingsCudaPackTitle => 'Aceleración NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Transcripción más rápida en tarjetas GeForce RTX y GTX 16. Descarga única de $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Instalado. Si el controlador gráfico es demasiado antiguo, WhisPaste sigue usando Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'Se requiere consentimiento';

  @override
  String get settingsCudaPackConsentReview => 'Revisar licencia';

  @override
  String get settingsCudaPackDownload => 'Descargar';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'Descargando $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'Instalando …';

  @override
  String get settingsCudaPackCancel => 'Cancelar descarga';

  @override
  String get settingsCudaPackRemove => 'Quitar paquete CUDA';

  @override
  String get settingsCudaPackRemoveConfirm => '¿Quitar el paquete CUDA?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'El paquete CUDA se quita de este dispositivo. Puedes volver a descargarlo en cualquier momento.';

  @override
  String get settingsCudaPackToggle => 'Usar CUDA';

  @override
  String get settingsCudaPackErrorNetwork =>
      'La descarga falló. Revisa la conexión e inténtalo de nuevo.';

  @override
  String get settingsCudaPackErrorVerification =>
      'La descarga llegó dañada. Inténtalo de nuevo.';

  @override
  String get settingsCudaPackErrorStorage =>
      'No se pudo guardar el paquete. Revisa el espacio libre en disco.';

  @override
  String get cudaEulaDialogTitle => 'Licencia de NVIDIA CUDA';

  @override
  String cudaEulaDialogBody(String version) {
    return 'El paquete CUDA contiene componentes de NVIDIA bajo el Acuerdo de licencia de usuario final de NVIDIA CUDA ($version). Aceptas el texto completo de esta versión, que puedes leer en «Ver texto completo». Una versión posterior en NVIDIA puede diferir. Debes aceptarlo para descargar.';
  }

  @override
  String get cudaEulaDialogLink => 'Otra versión en NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'Ver texto completo';

  @override
  String get cudaEulaFullTextClose => 'Cerrar';

  @override
  String get cudaEulaDialogCancel => 'Cancelar';

  @override
  String get cudaEulaDialogAccept => 'Aceptar y descargar';

  @override
  String get recoveryCudaDisabledToast =>
      'La aceleración CUDA se desactivó por un problema en el último inicio. WhisPaste usa ahora Vulkan y la grabación funciona como siempre.';

  @override
  String get recoveryGpuProbeFailedToast =>
      'La aceleración por GPU no se usa en esta sesión: la comprobación de la tarjeta gráfica no terminó. WhisPaste transcribe con el procesador. Grabar funciona como siempre.';

  @override
  String get settingsGpuProbeTitle => 'Comprobación de GPU';

  @override
  String get settingsGpuProbeNotChecked =>
      'Aún no comprobada. La comprobación se hace al cargar el modelo por primera vez.';

  @override
  String get settingsGpuProbeUsable => 'Comprobada: se usa la tarjeta gráfica.';

  @override
  String get settingsGpuProbeUnusable =>
      'No utilizable: WhisPaste usa el procesador. Vuelve a comprobar tras actualizar el controlador o la app.';

  @override
  String get settingsGpuProbeRetry => 'Comprobar de nuevo';

  @override
  String get supportPromptSnooze => 'No preguntar durante 90 días';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'Gracias por comprar WhisPaste en la tienda. Cualquier apoyo adicional es opcional.';

  @override
  String get supportShareText =>
      'Uso WhisPaste para escribir con la voz directamente en mis apps. Local en mi ordenador y de código abierto:';

  @override
  String get supportPageTitle => 'Apoyar WhisPaste';

  @override
  String get supportIntroDirect =>
      'WhisPaste es gratuito y de código abierto. Una aportación o una recomendación ayuda al proyecto.';

  @override
  String get supportCostsNote =>
      'Las aportaciones ayudan a cubrir el desarrollo y los costes continuos de publicación, alojamiento y dominio.';

  @override
  String get supportSectionOnce => 'Apoyo único';

  @override
  String get supportSectionOthers => 'Otras formas de apoyar';

  @override
  String get supportSectionReach => 'Recomendar WhisPaste';

  @override
  String get supportStoreTitleWindows => 'WhisPaste en Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste en la Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'El store gestiona la instalación y las actualizaciones.';

  @override
  String get supportStoreFactPurchase => 'Tu compra única apoya WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'Las mismas funciones. La versión directa sigue siendo gratuita.';

  @override
  String get supportStoreCtaWindows => 'Ver en Microsoft Store';

  @override
  String get supportStoreCtaMac => 'Ver en la Mac App Store';

  @override
  String get supportStorePriceNote => 'Precio en la tienda';

  @override
  String get supportStoreCoffeeNote =>
      'Una compra única, más o menos el precio de un café. La tienda muestra el precio actual.';

  @override
  String get supportStoreDismiss => 'Ocultar opción de la tienda';

  @override
  String get supportStoreShowAgain => 'Mostrar opción de la tienda';

  @override
  String get supportSponsorsCta => 'Abrir GitHub Sponsors';

  @override
  String get supportSponsorsNote =>
      'Mensual o con el importe que elijas. Allí eliges el importe y la periodicidad.';

  @override
  String get supportKofiCta => 'Abrir Ko-fi';

  @override
  String get coffeeButtonLabel => 'Invítame a un café';

  @override
  String get coffeeButtonHint =>
      'WhisPaste es gratuito y de código abierto. Un café ayuda a seguir desarrollándolo.';

  @override
  String get coffeeBuyMeACoffeeLabel => 'Buy Me a Coffee';

  @override
  String get supportPayPalCta => 'Apoyar con PayPal';

  @override
  String get supportNativeTitle => 'Apoyar una vez en la tienda';

  @override
  String get supportNativeDescription =>
      'Un importe único que cobra la tienda. Mismas funciones, sin suscripción.';

  @override
  String get supportNativeCta => 'Apoyar una vez';

  @override
  String get supportSheetChoose => 'Elige un importe';

  @override
  String get supportSheetLoading => 'Cargando importes …';

  @override
  String supportSheetBuy(String price) {
    return 'Apoyar por $price';
  }

  @override
  String get supportSheetPurchasing => 'La tienda confirma tu compra …';

  @override
  String get supportSheetThanks => '¡Gracias por tu apoyo!';

  @override
  String get supportSheetThanksDetail =>
      'Tu insignia de apoyo ya está activa. Todas las funciones siguen disponibles para todos.';

  @override
  String get supportSheetPending => 'Tu compra está pendiente de confirmación.';

  @override
  String get supportSheetPurchaseError =>
      'No se pudo completar la compra. Inténtalo más tarde.';

  @override
  String get supportSheetPricesError =>
      'No se pudieron cargar los importes. Inténtalo más tarde.';

  @override
  String get supportSheetUnavailable =>
      'Ahora mismo no hay importes disponibles en la tienda.';

  @override
  String get supportSheetRetry => 'Reintentar';

  @override
  String get supportSheetClose => 'Cerrar';

  @override
  String get supportSelfDeclareCta => 'Ya apoyo WhisPaste';

  @override
  String get supportSelfDeclareNote =>
      'Solo una nota en este dispositivo; no se verifica nada. El botón de patrocinio de la barra de estado se oculta.';

  @override
  String get supportSelfDeclareHint =>
      'No se verifica nada. Úsalo si ya has aportado.';

  @override
  String get supportSupporterLine => 'Apoyas WhisPaste. ¡Gracias!';

  @override
  String get supportSupporterBadge => 'Apoyo';

  @override
  String get supportRateCta => 'Valorar en la tienda';

  @override
  String get supportShareCopy => 'Copiar enlace';

  @override
  String get supportShareCopied => 'Enlace copiado';

  @override
  String get externalLinkOpenFailed => 'No se pudo abrir el enlace';

  @override
  String get externalLinkCopyAddress => 'Copiar dirección';

  @override
  String get supportShareEmail => 'Correo';

  @override
  String get supportChipLabel => 'Patrocinio';

  @override
  String get supportChipTooltip => 'Apoyar WhisPaste';

  @override
  String get supportChipThanksLabel => 'Gracias';

  @override
  String get supportChipThanksTooltip => 'Gracias por tu apoyo';

  @override
  String get settingsSponsorChip => 'Botón de patrocinio en la barra de estado';

  @override
  String get settingsSponsorChipSubtitle =>
      'Muestra el acceso a la página de apoyo. Puedes ocultarlo en cualquier momento y volver a mostrarlo aquí.';

  @override
  String get automationPreviewTitle => '¿Insertar texto de varias líneas?';

  @override
  String get automationPreviewBody =>
      'La automatización quiere insertar texto con saltos de línea. Revísalo antes de que llegue a la app activa.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count líneas',
      one: '1 línea',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'Insertar';

  @override
  String get automationPreviewCancel => 'Cancelar';

  @override
  String get automationIntegrationsHeading => 'Integraciones';

  @override
  String get automationIntegrationsHooksTitle => 'Enviar eventos a otras apps';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'Envía transcripciones terminadas y notas modificadas a una app de este equipo. Los hooks siguen enviando aunque el servidor de la API esté desactivado.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hooks',
      one: '1 hook',
      zero: 'Sin hooks',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'Gestionar';

  @override
  String get automationIntegrationsCliTitle => 'Línea de comandos y MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'Solo desde el código fuente. Ejecuta $path con $token definido; el comando $command inicia el servidor MCP.';
  }

  @override
  String get automationHooksIntro =>
      'Los textos terminados y las notas modificadas se envían a una app de este equipo. La dirección debe estar en este dispositivo.';

  @override
  String get automationHooksEmpty => 'Aún no hay ninguna conexión configurada.';

  @override
  String get automationHooksUrlLabel =>
      'Dirección de destino (solo este equipo)';

  @override
  String get automationHooksEventsLabel => 'Eventos';

  @override
  String get automationHooksEventTranscript => 'Transcripción terminada';

  @override
  String get automationHooksEventNote => 'Nota modificada';

  @override
  String get automationHooksAdd => 'Añadir hook';

  @override
  String get automationHooksRemove => 'Quitar hook';

  @override
  String get automationHooksRemoveConfirm => '¿Quitar este hook?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'El hook se quita de la lista. Puedes volver a añadirlo más tarde.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'Usa $ipv4, $ipv6 o $localhost con un puerto, por ejemplo $example.';
  }

  @override
  String get automationHooksNoEvents => 'Elige al menos un evento.';

  @override
  String automationHooksTooMany(int max) {
    return 'Puedes añadir hasta $max hooks.';
  }

  @override
  String get automationHooksDone => 'Listo';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'Dictar';

  @override
  String get dockOverflow => 'Más';

  @override
  String get dockMenuGroupStatus => 'Estado';

  @override
  String get dockMenuGroupNotices => 'Avisos';

  @override
  String get dockMenuHotkeyChange => 'Cambiar atajo…';

  @override
  String get dockMenuSmartModeSettings => 'Ajustes de Smart Mode…';

  @override
  String get dockMenuSttModels => 'Gestionar modelos de voz…';

  @override
  String get dockMenuGroupCloud => 'Nube';

  @override
  String get dockMenuModelDownload => 'Descargar';

  @override
  String get dockMenuModelLoading => 'cargando';

  @override
  String get dockMenuSttLockedReason =>
      'No se puede cambiar durante una grabación';

  @override
  String get dockMenuSearchHint => 'Buscar…';

  @override
  String get dockMenuSearchNoMatches => 'Sin coincidencias';

  @override
  String get dockMenuAppliesNextRecording =>
      'Se aplica a partir de la próxima grabación';

  @override
  String get dockStopDictation => 'Detener grabación';

  @override
  String get historyImportAddFiles => 'Añadir archivos';

  @override
  String historyImportDescription(String formats) {
    return 'Transcribe archivos de audio ($formats) en este dispositivo. Arrastra los archivos a esta página o añádelos.';
  }

  @override
  String get historyImportQueueTitle => 'Cola de importación';

  @override
  String get historyImportStatusQueued => 'En espera';

  @override
  String get historyImportStatusCopying => 'Copiando';

  @override
  String get historyImportStatusDecoding => 'Decodificando';

  @override
  String get historyImportStatusTranscribing => 'Transcribiendo';

  @override
  String historyImportElapsed(String elapsed) {
    return 'En curso desde hace $elapsed';
  }

  @override
  String historyImportPercent(int percent) {
    return '$percent %';
  }

  @override
  String get historyImportStatusDone => 'Listo';

  @override
  String get historyImportStatusFailed => 'Error';

  @override
  String get historyImportStatusCancelled => 'Cancelado';

  @override
  String get historyImportFailureCopy =>
      'No se pudo copiar el archivo. Comprueba que sigue existiendo y que se puede leer, y vuelve a intentarlo.';

  @override
  String get historyImportFailureUnsupported =>
      'Este formato no es compatible con esta plataforma. Convierte el archivo a WAV e impórtalo de nuevo.';

  @override
  String get historyImportFailureDecode =>
      'No se pudo decodificar el archivo. Probablemente está dañado o incompleto. Importa otra copia o conviértelo a WAV.';

  @override
  String get historyImportFailureInputLimit =>
      'El archivo es demasiado grande o dura más de 6 horas. Divídelo en partes más cortas.';

  @override
  String get historyImportFailureTranscription =>
      'Error en la transcripción. Revisa el reconocimiento de voz en los ajustes y vuelve a intentarlo.';

  @override
  String get historyImportFailureSave =>
      'No se pudo guardar la transcripción. Comprueba el espacio libre del disco y vuelve a intentarlo.';

  @override
  String get historyImportRejectionsTitle => 'Archivos no importados';

  @override
  String get historyImportRejectedFolder =>
      'No se pueden importar carpetas. Elige los archivos de audio que contienen.';

  @override
  String get historyImportRejectedNotFound => 'No se encontró el archivo.';

  @override
  String historyImportRejectedType(String formats) {
    return 'Este tipo de archivo no se puede importar. Compatibles: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'No se pudo abrir el diálogo de archivos. Inténtalo de nuevo o arrastra los archivos a esta página.';

  @override
  String get historyImportDropHere =>
      'Suelta aquí los archivos de audio para transcribirlos';

  @override
  String get historyImportCancel => 'Cancelar importación';

  @override
  String get historyImportRetry => 'Reintentar importación';

  @override
  String get recoveryOffer =>
      'Se encontró una grabación interrumpida. ¿Recuperar su audio y transcribirlo?';

  @override
  String get recoveryNoAudioKept =>
      'Se encontró una grabación interrumpida, pero no se guardó audio porque la retención de audio está desactivada.';

  @override
  String get recoveryNoAudioCaptured =>
      'Se encontró una grabación interrumpida, pero no contiene audio.';

  @override
  String get recoveryRestore => 'Recuperar';

  @override
  String get recoveryDiscard => 'Descartar';

  @override
  String get recoveryDiscardConfirm => '¿Descartar esta grabación?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'Esta grabación interrumpida se elimina de este dispositivo, junto con el audio que se haya guardado.';

  @override
  String historyStatusRecovery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grabaciones interrumpidas',
      one: '1 grabación interrumpida',
    );
    return '$_temp0';
  }

  @override
  String historyStatusImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count importaciones',
      one: '1 importación',
    );
    return '$_temp0';
  }

  @override
  String historyRecoverySummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grabaciones interrumpidas esperan a ser recuperadas',
      one: '1 grabación interrumpida espera a ser recuperada',
    );
    return '$_temp0';
  }

  @override
  String historyImportQueueSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cola de importación: $count archivos',
      one: 'Cola de importación: 1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get pendingAudioDiscardConfirmMessage =>
      'El audio guardado se elimina de este dispositivo. Después ya no es posible volver a intentarlo.';

  @override
  String get recoveryFailed =>
      'No se pudo recuperar. El audio se ha conservado, así que puedes volver a intentarlo.';

  @override
  String recoverySkippedCorrupt(int count) {
    return 'Se omitieron $count entradas de recuperación dañadas y se conservaron en el disco.';
  }

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupDictation => 'Entrada de voz';

  @override
  String get settingsGroupSystem => 'Sistema';

  @override
  String get settingsAreaGeneral => 'General';

  @override
  String get settingsAreaAppearance => 'Apariencia';

  @override
  String get settingsAreaShortcuts => 'Atajos de teclado';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'Atajo de teclado: $combo';
  }

  @override
  String get settingsAreaRecording => 'Grabación y audio';

  @override
  String get settingsAreaSpeech => 'Reconocimiento de voz';

  @override
  String get settingsAreaTextInsert => 'Texto e inserción';

  @override
  String get settingsAreaPrivacy => 'Privacidad y datos';

  @override
  String get settingsAreaAdvanced => 'Avanzado';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'Actualizada';

  @override
  String get settingsNavUpdateAvailable => 'Actualización disponible';

  @override
  String get settingsNavStoreUpdates => 'Actualizaciones a través de la tienda';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'La tienda entrega las actualizaciones de esta versión. Aquí no se pueden buscar actualizaciones en la app.';

  @override
  String get settingsStoreBetaUnavailable =>
      'Las versiones preliminares no se ofrecen en la versión de la tienda.';

  @override
  String get settingsStoreCudaUnavailable =>
      'No disponible en la versión de la tienda: allí no se permiten descargas de controladores desde fuera de la tienda.';

  @override
  String get settingsOverlayPreview => 'Vista previa de la superposición';

  @override
  String get settingsPreviewTitle => 'Vista previa';

  @override
  String get settingsPreviewHint =>
      'Así se ven el overlay y el botón en reposo y al grabar. Los cambios se aplican al momento.';

  @override
  String get settingsPreviewOverlayCaption => 'Overlay';

  @override
  String get settingsPreviewButtonIdleCaption => 'Listo';

  @override
  String get settingsPreviewButtonRecordingCaption => 'Grabando';

  @override
  String get settingsOverlayOptionsGroup => 'Overlay';

  @override
  String get settingsOverlayForm => 'Forma';

  @override
  String get settingsOverlayFormSubtitle =>
      'Píldora o rectángulo con esquinas redondeadas.';

  @override
  String get settingsOverlayFormPill => 'Píldora';

  @override
  String get settingsOverlayFormRoundedRect => 'Redondeada';

  @override
  String get settingsOverlayWaveStyle => 'Estilo de onda';

  @override
  String get settingsOverlayWaveStyleSubtitle =>
      'Cómo se dibuja tu voz en el overlay.';

  @override
  String get settingsOverlayWaveBars => 'Barras';

  @override
  String get settingsOverlayWaveLine => 'Línea';

  @override
  String get settingsOverlayWaveDots => 'Puntos';

  @override
  String get settingsOverlayWaveFluid => 'Contorno fluido';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'El borde reacciona a tu voz. Desactivado con «Reducir movimiento».';

  @override
  String get settingsOverlayShowTimer => 'Mostrar tiempo';

  @override
  String get settingsOverlayShowTimerSubtitle =>
      'Muestra el tiempo de grabación transcurrido.';

  @override
  String get settingsOverlayShowCancel => 'Símbolo de cancelar';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'Detener siempre está visible. Esc sigue cancelando.';

  @override
  String get settingsOverlayOpacity => 'Opacidad';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'Se sube automáticamente si la onda quedaría demasiado tenue.';

  @override
  String get settingsOverlayOpacityFull => '100 %';

  @override
  String get settingsOverlayOpacityReduced => '80 %';

  @override
  String get settingsOverlayOpacitySubtle => '60 %';

  @override
  String get settingsFloatingButtonSize => 'Tamaño';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Diámetro del botón flotante';

  @override
  String get settingsFloatingButtonSizeSmall => 'Pequeño';

  @override
  String get settingsFloatingButtonSizeMedium => 'Mediano';

  @override
  String get settingsFloatingButtonSizeLarge => 'Grande';

  @override
  String get settingsFloatingButtonShape => 'Forma';

  @override
  String get settingsFloatingButtonShapeSubtitle =>
      'Redondo o cuadrado redondeado';

  @override
  String get settingsFloatingButtonShapeRound => 'Redondo';

  @override
  String get settingsFloatingButtonShapeSquare => 'Cuadrado';

  @override
  String get settingsFloatingButtonRing => 'Anillo de grabación';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'Anillo de color alrededor del botón mientras se graba';

  @override
  String get settingsFloatingButtonIdleOpacity => 'Opacidad en reposo';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'Qué tan visible es el botón sin grabar';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'Compartido (colores)';

  @override
  String get settingsAreaSmartMode => 'Modo inteligente';

  @override
  String get settingsAreaDictionary => 'Diccionario';

  @override
  String get settingsSearchEmptyHelp => 'Buscar en la ayuda';

  @override
  String get dictionaryTabTerms => 'Términos';

  @override
  String get dictionaryTabReplacements => 'Reemplazos';

  @override
  String get dictionaryTabSuggestions => 'Sugerencias';

  @override
  String get dictionaryTermsEffectPrompt =>
      'Se pasa al reconocedor de voz como pista. Puede preferir estas grafías, pero no cambia el texto por sí solo.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'El motor de voz activo no acepta pistas. Solo los reemplazos cambian el texto. Tus términos se conservan.';

  @override
  String get dictionaryTermsHelp =>
      'Nombres, jerga y siglas que el reconocedor suele escribir mal. Sepáralos con comas o saltos de línea.';

  @override
  String get dictionaryReplacementsHelp =>
      'Añade solo palabras que el reconocedor escribe realmente mal. Las palabras reconocidas correctamente no cambian.';

  @override
  String get dictionaryTestTitle => 'Probar';

  @override
  String get dictionaryTestInputLabel => 'Frase de ejemplo';

  @override
  String get dictionaryTestInputHint =>
      'Escribe una frase para ver qué reemplazos se aplican.';

  @override
  String get dictionaryTestResultLabel => 'Resultado';

  @override
  String get dictionaryTestNoChange => 'No se aplica ningún reemplazo.';

  @override
  String get dictionaryCsvTitle => 'Importar y exportar (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'Una línea por entrada: frases de activación separadas por $pipe, texto de reemplazo, modo (exact o fuzzy), umbral.';
  }

  @override
  String get dictionaryCsvImport => 'Importar CSV';

  @override
  String get dictionaryCsvExport => 'Exportar CSV';

  @override
  String get dictionaryCsvExportEmpty => 'Aún no hay reemplazos para exportar.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'El archivo supera 1 MB. Divídelo en archivos más pequeños.';

  @override
  String get dictionaryCsvImportReadError => 'No se pudo leer el archivo.';

  @override
  String get dictionaryCsvImportNothing =>
      'No se encontraron entradas válidas.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    return 'Se omitieron $count líneas por estar incompletas o no ser válidas.';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    return 'Solo se leyeron las primeras $count entradas.';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return 'Se añadieron $added entradas.';
  }

  @override
  String get dictionaryCsvExportFailed => 'No se pudo guardar el archivo CSV.';

  @override
  String dictionaryCsvExportDone(int count) {
    return 'Se exportaron $count entradas.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'Línea $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'Faltan columnas.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'Falta la frase de activación.';

  @override
  String get dictionaryCsvReasonTriggerTooLong =>
      'La frase de activación es demasiado larga.';

  @override
  String get dictionaryCsvReasonEmptyReplacement =>
      'Falta el texto de reemplazo.';

  @override
  String get dictionaryCsvReasonReplacementTooLong =>
      'El texto de reemplazo es demasiado largo.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'El modo debe ser exact o fuzzy.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'El umbral debe ser strict, standard, tolerant o un número entre 0,5 y 1.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'La línea contiene un carácter de control o de formato oculto, o un salto de línea.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'Demasiadas frases de activación en una línea (máximo $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'Revisar entradas';

  @override
  String get dictionaryDuplicateBadge => 'Duplicado';

  @override
  String get dictionaryDuplicateHint =>
      'Otra entrada usa la misma frase de activación. Se aplica la que aparece primero en la lista.';

  @override
  String dictionaryUsageCount(int count) {
    return 'Usado $count×';
  }

  @override
  String get dictionaryFavouriteLabel => 'Favorito';

  @override
  String dictionarySuggestionsHint(int count) {
    return 'Aparece una sugerencia cuando la misma corrección se repite $count veces. Nada se añade sin tu confirmación.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'Aún no hay sugerencias';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'Si corriges dos veces la misma palabra, WhisPaste ofrecerá aquí un reemplazo.';

  @override
  String get dictionarySuggestionAccept => 'Aceptar';

  @override
  String get dictionarySuggestionReject => 'Descartar';

  @override
  String get dictionarySuggestionAccepted => 'Reemplazo añadido.';

  @override
  String get dictionarySuggestionRejected =>
      'Sugerencia descartada. No volverá a aparecer.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'Las entradas marcadas como «se añadirá» pasan a tu lista. Las existentes no cambian.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return 'Añadir $count entradas';
  }

  @override
  String get dictionaryCsvImportEncodingError =>
      'El archivo no es texto UTF-8.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'Este archivo usa un formato de paquete que esta app no puede leer.';

  @override
  String get dictionaryCsvRefusedType =>
      'Este archivo no es un paquete de diccionario de reemplazos.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'Paquete: $name (creado el $date)';
  }

  @override
  String get dictionaryCsvPackageNone =>
      'Sin información de paquete (archivo antiguo o ajeno)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'Nuevas: $added · Duplicadas: $duplicates · Conflictos: $conflicts · Referencias circulares: $circular · Erróneas: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel =>
      'Si una frase de activación ya existe';

  @override
  String get dictionaryCsvStrategySkip => 'Omitir';

  @override
  String get dictionaryCsvStrategyOverwrite => 'Sobrescribir';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'Conservar ambos';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'La fila no se importa. Las entradas existentes no cambian.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'Se quita la frase de activación compartida de la entrada anterior y se añade la fila. $changed entradas existentes cambian o se eliminan.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'La fila se añade también. Para la misma frase de activación sigue aplicándose la entrada existente que va antes en la lista.';

  @override
  String get dictionaryCsvStatusAdded => 'se añadirá';

  @override
  String get dictionaryCsvStatusDuplicate => 'ya existe';

  @override
  String get dictionaryCsvStatusConflictSkipped => 'conflicto, se omite';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'conflicto, reemplaza la frase de activación existente';

  @override
  String get dictionaryCsvStatusConflictKept => 'conflicto, se añade además';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'reemplazada por una fila posterior de este archivo';

  @override
  String get dictionaryCsvStatusCircular =>
      'referencia circular, no se importa';

  @override
  String get dictionaryCsvRowWillAdd => 'se añadirá';

  @override
  String get dictionaryCsvRowSkipped => 'Duplicado, se omite';

  @override
  String get dictionaryCsvExportSelectTitle =>
      'Elige las entradas para exportar';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return '$count entradas para elegir';
  }

  @override
  String get dictionaryCsvAllPresent =>
      'Todas las entradas ya existen. No se escribirá nada.';

  @override
  String dictionaryCsvNeverFiresCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count entradas tienen una frase de activación que nunca se activa: un solo signo de puntuación. Se importan igualmente.',
      one:
          '1 entrada tiene una frase de activación que nunca se activa: un solo signo de puntuación. Se importa igualmente.',
    );
    return '$_temp0';
  }

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'Exportar ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'Demasiadas entradas para un archivo: $count. Elige menos (máximo 5000 entradas, 1 MiB).';
  }

  @override
  String get settingsBetaGroupHeading => 'Versiones preliminares';

  @override
  String get analyticsWordingTitle => 'Redacción';

  @override
  String get analyticsWordingPanelTitle => 'Palabras: brutas vs. revisadas';

  @override
  String get analyticsRawWords => 'Palabras brutas';

  @override
  String get analyticsRevisedWords => 'Palabras revisadas';

  @override
  String get analyticsTransformActions => 'Grabaciones revisadas por acciones';

  @override
  String get analyticsCorrectionsTitle => 'Correcciones frecuentes';

  @override
  String get analyticsNoCorrections => 'Aún no hay correcciones registradas.';

  @override
  String get errorNoticeNoModelCause =>
      'No hay ningún modelo de voz instalado.';

  @override
  String get errorNoticeNoModelNext =>
      'Descarga un modelo en Ajustes y vuelve a intentarlo.';

  @override
  String get errorNoticeMicCause => 'WhisPaste no tiene acceso al micrófono.';

  @override
  String get errorNoticeMicNext =>
      'Permite el acceso en los ajustes del sistema e inténtalo de nuevo.';

  @override
  String get errorNoticeTranscribeCause => 'La transcripción ha fallado.';

  @override
  String get errorNoticeTranscribeNext =>
      'Inténtalo de nuevo. Si sigue fallando, reinicia WhisPaste o elige otro modelo en Ajustes.';

  @override
  String get errorNoticeCpuCause =>
      'La GPU no pudo usarse para esta transcripción.';

  @override
  String get errorNoticeCpuNext =>
      'Se ejecutó en la CPU, que es más lenta. Revisa la aceleración por GPU en Ajustes.';

  @override
  String get languageMismatchHint =>
      'El idioma detectado no coincide con tu ajuste.';

  @override
  String get languageMismatchSwitch => 'Cambiar idioma';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'Parakeet no puede transcribir $language. ¿Cambiar a Whisper?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'Cambiar a Whisper';

  @override
  String get titleBarMinimizeLabel => 'Minimizar ventana';

  @override
  String get titleBarCloseLabel => 'Cerrar ventana';

  @override
  String get titleBarMaximizeLabel => 'Maximizar ventana';

  @override
  String get titleBarRestoreLabel => 'Restaurar ventana';

  @override
  String get notificationSmartModeSkippedTitle =>
      'WhisPaste: Smart Mode omitido';

  @override
  String get notificationHotkeyFallbackTitle => 'WhisPaste: atajo ocupado';

  @override
  String get notificationSmartModeSkippedBody =>
      'No se pudo aplicar el posprocesado.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'No hay ningún modelo de texto cargado, así que se omitió el posprocesado.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'El posprocesado tardó demasiado.';

  @override
  String get notificationSmartModeOutcomePasted =>
      'El texto sin editar se ha pegado.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'No se pudo confirmar si el texto sin editar se ha pegado.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'El texto sin editar está en el portapapeles, pero no se ha pegado.';

  @override
  String get notificationSmartModeOutcomeNone =>
      'El texto sin editar no se ha pegado.';

  @override
  String get smartModeNoTextModelHint =>
      'No hay ningún modelo de texto configurado: hasta entonces solo se puede elegir «Desactivado».';

  @override
  String get smartModeLoadTextModelAction =>
      'Sin modelo de texto: cargar ahora';

  @override
  String get smartModeAddOpenAiKeyAction => 'Añadir clave de OpenAI';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'El archivo no es una exportación válida de WhisPaste.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'No se pudo procesar el archivo o los ajustes.';

  @override
  String get historyImportAudioLabel => 'Audio';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'Cambio de app';

  @override
  String get hotkeyConflictNoteQuitApp => 'Salir de la app';

  @override
  String get hotkeyConflictNoteCloseWindow => 'Cerrar ventana';

  @override
  String get hotkeyConflictNoteHideApp => 'Ocultar app';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'Minimizar ventana';

  @override
  String get hotkeyConflictNoteCycleWindows => 'Cambiar entre ventanas';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen =>
      'Captura de pantalla (pantalla completa)';

  @override
  String get hotkeyConflictNoteScreenshotSelection =>
      'Captura de pantalla (selección)';

  @override
  String get hotkeyConflictNoteScreenshotRecording =>
      'Captura/grabación de pantalla';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'Selector de emoji y símbolos';

  @override
  String get hotkeyConflictNoteForceQuit => 'Diálogo de forzar salida';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'Bloquear el equipo';

  @override
  String get hotkeyConflictNoteShowDesktop => 'Mostrar/ocultar escritorio';

  @override
  String get hotkeyConflictNoteFileExplorer => 'Explorador de archivos';

  @override
  String get hotkeyConflictNoteRunDialog => 'Cuadro Ejecutar';

  @override
  String get hotkeyConflictNoteSettings => 'Configuración';

  @override
  String get hotkeyConflictNoteSearch => 'Búsqueda';

  @override
  String get hotkeyConflictNoteTaskView => 'Vista de tareas';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch =>
      'Cambio de idioma de entrada';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'Maximizar ventana';

  @override
  String get hotkeyConflictNoteSnapLeft => 'Ajustar ventana a la izquierda';

  @override
  String get hotkeyConflictNoteSnapRight => 'Ajustar ventana a la derecha';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'Opciones de seguridad / Administrador de tareas';

  @override
  String get hotkeyConflictNoteTaskManager => 'Administrador de tareas';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde =>
      'Bloquear pantalla (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteInputSourceGnome =>
      'Cambiar fuente de entrada (GNOME)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'Cuadro Ejecutar (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'Diálogo de cierre de sesión/apagado';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'Abrir terminal (predeterminado de GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'Bloquear pantalla (GNOME)';

  @override
  String get hotkeyConflictNoteFnDoubleTap =>
      'macOS: Fn abre los emojis o inicia el dictado del sistema';

  @override
  String get hotkeyConflictNoteWindowsDictation =>
      'Escritura por voz de Windows';

  @override
  String get hotkeyConflictNoteWindowsClipboardHistory =>
      'Historial del portapapeles';

  @override
  String get hotkeyConflictActionChooseOther => 'Elige otra combinación.';

  @override
  String get hotkeyConflictActionDisableMacDictation =>
      'En Ajustes del Sistema → Teclado, pon «Pulsar la tecla 🌐 para» en «No hacer nada» y desactiva el atajo del dictado.';

  @override
  String get settingsTextProcessingHeading => 'Procesamiento de texto';

  @override
  String get settingsShowNotificationsSubtitle =>
      'Avisa de problemas, por ejemplo un Auto-Paste bloqueado o una señal de micrófono ausente.';

  @override
  String get settingsGainSubtitle =>
      'Amplifica la señal del micrófono antes de grabarla. Valores demasiado altos pueden distorsionar la grabación.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'Qué pasa con el texto reconocido. Auto-Paste lo pega directamente en el cursor.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'El idioma que espera el reconocimiento. La detección automática suele funcionar bien. Un idioma fijo suele ser más preciso en grabaciones cortas.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'Tu propia clave de OpenAI. Solo es necesaria si usas OpenAI para el reconocimiento o Smart Mode. El audio y el texto van entonces directamente a OpenAI y se facturan según su tarifa.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'Tu propia clave de Deepgram. Solo es necesaria si usas Deepgram para el reconocimiento. El audio va entonces directamente a Deepgram y se factura según su tarifa.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'Restablece todos los ajustes, las claves de API y las estadísticas. Las grabaciones, notas y modelos se conservan.';

  @override
  String get settingsFactoryResetSubtitle =>
      'Borra de inmediato todas las transcripciones, notas, archivos de audio, Diccionario, Snippets, modelos, registros y ajustes de este equipo. No se puede deshacer.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'El atajo global inicia una grabación desde cualquier app. Desactivado, WhisPaste ignora el atajo.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'Busca ahora una versión nueva. Solo se instala después de que lo confirmes.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'Cuántas transcripciones se conservan antes de que las más antiguas pasen a la papelera. En la papelera, las transcripciones se borran de forma definitiva tras el tiempo elegido. Los favoritos siempre se conservan. Los archivos de audio guardados se eliminan como máximo 30 días después de la grabación, independientemente de este ajuste.';

  @override
  String get smartModeTargetLanguageSubtitle => 'Solo para el preset Traducir.';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'El archivo es demasiado grande para importarlo (límite: unos 5 MB). Elige un archivo de ajustes exportado por WhisPaste.';

  @override
  String get settingsSearchKeywordsInterface =>
      'tema, modo oscuro, modo claro, apariencia, idioma, inicio automático, arranque, minimizado, notificaciones, idioma del sistema, panel, panel lateral, pegado rápido, panel del portapapeles, posición del panel, borde de la pantalla, borde, bandeja, CPU, indicador, barra de estado, uso';

  @override
  String get settingsSearchKeywordsStt =>
      'modelo, Whisper, calidad, transcripción, reconocimiento de voz, local, en el dispositivo, nube, idioma, tiempo de espera, vocabulario, diccionario, palabras, STT, reconocimiento de voz, Deepgram, OpenAI, clave de API, solo números, puntuación, motor, silencio, recortar, muletillas, salto de línea, párrafo, línea, GPU, gráficos, aceleración, procesador, hardware';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'preset, limpieza, resumir, traducir, Gemma, modelo, modelo de texto, descargar, posprocesado, pulir, editar selección, selección, texto seleccionado, reescribir';

  @override
  String get settingsSearchKeywordsAudio =>
      'micrófono, grabación, ganancia, volumen, pulsar para hablar, mantener para grabar, entrada';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'portapapeles, pegar, auto-paste, copiar, acción, salida, no hacer nada, lista de bloqueo, restaurar portapapeles, mantener transcripción, contenido anterior';

  @override
  String get settingsSearchKeywordsOverlay =>
      'superposición, flotante, pantalla, estado, posición, ventana, arriba centro, abajo centro, posición inicial, transcripción en vivo';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'fondo, color, marino, grafito, glaciar, cristal, opaco, ámbar';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'onda, ondas, color, cian, violeta, animación, ámbar';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'botón, flotante, siempre visible, botón de grabación, acceso rápido';

  @override
  String get settingsSearchKeywordsHotkey =>
      'atajo de teclado, combinación de teclas, atajo global, tecla global, atajo, teclado, teclas, asignación de teclas';

  @override
  String get settingsSearchKeywordsSound =>
      'sonido, tono, audio, señal, pitido, volumen, sonido de grabación, notificación, sonido de finalización, aviso';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'seguridad, silencio, detener automáticamente, tiempo de espera, tiempo de espera del micrófono, detección de silencio, protección, micrófono sin señal, duración máxima';

  @override
  String get settingsSearchKeywordsHistory =>
      'grabaciones, entradas, papelera, limpieza, retención, máximo, eliminación automática, borrado, almacenamiento, ocultar, privacidad, PIN, bloquear, bloqueo, proteger, historial';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'exportar, importar, migrar, transferir, mudanza, copia de seguridad, restaurar, cambio de equipo, portabilidad, nuevo equipo, copia automática, autoguardado';

  @override
  String get settingsSearchKeywordsAdvanced =>
      'restablecer, valores predeterminados, restablecimiento de fábrica';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'automatización, API, script, token, bearer, HTTP, localhost, puerto';

  @override
  String get settingsSearchKeywordsUpdates =>
      'actualización, beta, canal, canal de versiones, versión preliminar, comprobar, automático, nueva versión, estable, versión';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'introducción, incorporación, configuración inicial, configuración, recorrido, tour, otra vez, de nuevo, primeros pasos';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'valoración, valorar, estrellas, tienda, apoyar, reseña, calificar';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'privacidad, análisis, estadísticas, seguimiento, anónimo, informes de errores, informes de fallos, estadísticas de uso, datos, compartir, consentimiento, mantener grabaciones, grabaciones recientes';

  @override
  String get manualNoticeLabel => 'Mensaje que muestra la app';

  @override
  String get manualC01Title => 'Primeros pasos';

  @override
  String get manualC01S1Heading => 'Configuración en el primer inicio';

  @override
  String get manualC01S1B1 =>
      'Al iniciarlo por primera vez, WhisPaste te guía por seis pasos de configuración. Los puntos y el contador de pasos de arriba muestran en qué paso estás. Cada paso tiene una acción principal y puedes volver atrás en cualquier momento. Todo se puede cambiar más tarde en los ajustes.';

  @override
  String get manualC01S1B2I1 =>
      'Inicio: una visión general y el modelo de voz. Para elegir otro, usa el enlace «Otro modelo de voz». La descarga solo empieza cuando lo confirmas.';

  @override
  String get manualC01S1B2I2 =>
      'Accesos: el permiso con el que WhisPaste puede pegar el texto automáticamente. Los pasos dependen del sistema.';

  @override
  String get manualC01S1B2I3 =>
      'Micrófono: elige el dispositivo de entrada y comprueba que WhisPaste te oye.';

  @override
  String get manualC01S1B2I4 =>
      'Atajo: define la combinación de teclas que inicia una grabación. Si otra app ya la usa, la configuración solo se puede terminar cuando eliges otra.';

  @override
  String get manualC01S1B2I5 =>
      'Primer dictado: habla en el chat de práctica; el texto aparece allí, en la ventana. «Probar más tarde» omite el ejercicio.';

  @override
  String get manualC01S1B2I6 =>
      'Privacidad e inicio: los interruptores de privacidad y la acción principal «Iniciar WhisPaste».';

  @override
  String get manualC01S1B3 =>
      'Pausar la configuración: si cierras la ventana durante la configuración, ábrela de nuevo desde el icono de la bandeja o la barra de menús con «Reanudar configuración».';

  @override
  String get manualC01S1B4 =>
      'Usuarios existentes: tras una actualización, WhisPaste muestra un aviso que abre la página del micrófono para revisarla. Tus ajustes no cambian.';

  @override
  String get manualC01S1B5 =>
      'Primeros pasos: tras la configuración, la página de inicio muestra una tarjeta con tres pasos: un primer dictado pegado en otra app, un dictado de más de 30 segundos y tus propios términos en el diccionario. Un paso se marca solo cuando realmente ha ocurrido. Puedes cerrar la tarjeta en cualquier momento; en Ajustes, en General, “Mostrar de nuevo” la devuelve.';

  @override
  String get manualC01S2Heading => 'Requisitos del sistema';

  @override
  String manualC01S2B1(String ram) {
    return 'WhisPaste recomienda un dispositivo con al menos $ram de memoria (RAM). En dispositivos con menos, WhisPaste se inicia igualmente y recomienda un modelo de voz compacto. Si en ese momento hay muy poca memoria libre para un modelo más grande, WhisPaste pregunta antes de cargarlo.';
  }

  @override
  String get manualC01S2B2 =>
      'Necesitas un micrófono para grabar. En la configuración inicial puedes continuar sin él, pero solo podrás grabar cuando haya uno conectado.';

  @override
  String get manualC01S3Heading => 'Descargar el modelo de voz';

  @override
  String get manualC01S3B1 =>
      'WhisPaste convierte tu voz en texto en tu equipo o mediante un proveedor en la nube con tu propia clave. En tu equipo necesita un modelo. Tú inicias la descarga; no empieza sola.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: rápido, para idiomas europeos, unos $k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: los 99 idiomas, modelos de unos $k1 a unos $k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'Los modelos se guardan en la carpeta de datos de la app, en la subcarpeta $k1.';
  }

  @override
  String get manualC01S3B4 =>
      'Un modelo Whisper permanece cargado tras dictar, para que el siguiente inicio sea más rápido. En “Mantener el modelo cargado”, en la sección de reconocimiento de voz, eliges: Siempre (predeterminado) ahorra tiempo de espera, pero necesita memoria todo el tiempo. Automático mantiene el modelo cargado si el equipo tiene memoria suficiente; si no, se descarga tras 5 minutos. Tras un periodo de inactividad lo descarga al cabo del tiempo que elijas. Cuando la memoria escasea, WhisPaste descarga el modelo automáticamente y lo vuelve a cargar cuando hay espacio.';

  @override
  String get manualC01S3B3 =>
      'En el área Reconocimiento de voz, la opción «Repetir prueba de rendimiento» mide la velocidad de cada nivel instalado en tu equipo. Los resultados muestran en las tarjetas de modelo cuánto más tarda cada nivel y determinan el nivel recomendado de Whisper. Se recomienda el modelo más preciso que funciona con fluidez: el nivel más grande de Whisper si tu equipo lo soporta; si no, Parakeet, si admite tu idioma. Para inglés es Parakeet. La prueba no se inicia durante una grabación.';

  @override
  String get manualC02Title => 'Grabar y pegar';

  @override
  String get manualC02S1Heading => 'El atajo de teclado';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'El atajo es una combinación de teclas que funciona en todos los programas. Por defecto: $k2 en Windows y Linux, $k3 en Mac. Puedes cambiarlo en Ajustes → Atajos de teclado.';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'Si otro programa ya usa la combinación, WhisPaste usa $k2 para el atajo (en Mac, $k3). Los demás atajos quedan desactivados hasta que configures una combinación libre.';
  }

  @override
  String get manualC02S2Heading => 'Mantener o alternar';

  @override
  String get manualC02S2B1 =>
      'En Ajustes → Atajos de teclado eliges cómo funciona el atajo:';

  @override
  String get manualC02S2B2I1 =>
      '«Mantener para grabar» activado (predeterminado en instalaciones nuevas): mantén el atajo, habla y suéltalo. Al soltarlo termina la grabación.';

  @override
  String get manualC02S2B2I2 =>
      'Desactivado: una pulsación inicia la grabación y una segunda la termina.';

  @override
  String get manualC02S3Heading => 'Ver la grabación';

  @override
  String get manualC02S3B1 =>
      'El dock en la parte inferior de la ventana principal muestra el estado actual. Durante una grabación, el botón cambia a “Detener grabación” y la zona de estado muestra el paso actual. El dock siempre está visible y no se puede desactivar.';

  @override
  String get manualC02S3B3 =>
      'En una ventana estrecha, el dock mueve los controles menos importantes al menú “Más”, incluidos el atajo, la sugerencia de Auto-Paste y el aviso de actualización. Todo sigue disponible allí.';

  @override
  String get manualC02S3B2I1 =>
      '«Overlay de grabación» en «Flotante (siempre visible)»: un pequeño overlay de forma de onda sobre todos los programas. Por defecto: desactivado.';

  @override
  String get manualC02S3B2I2 =>
      '«Botón flotante»: un botón para grabar con un clic. Por defecto: desactivado. En Linux con Wayland, el escritorio puede limitar su posición y si se mantiene encima.';

  @override
  String get manualC02S4Heading => 'Pegar después de grabar';

  @override
  String get manualC02S4B1 =>
      'En «Tras la transcripción» eliges qué ocurre después de cada grabación:';

  @override
  String get manualC02S4B2I1 =>
      '«Copiar al portapapeles» (predeterminado): el texto va al portapapeles y lo pegas tú.';

  @override
  String get manualC02S4B2I2 =>
      '«Auto-Paste en el cursor»: WhisPaste pega el texto en la posición del cursor.';

  @override
  String get manualC02S4B2I3 => '«Copiar y Auto-Paste»: ambas cosas.';

  @override
  String get manualC02S4B2I4 =>
      '«No hacer nada»: WhisPaste no copia ni pega el texto.';

  @override
  String get manualC02S4B3 =>
      'Las apps de la «Lista de bloqueo de Auto-Paste» no reciben pegado automático. El texto va entonces al portapapeles, o solo a Grabaciones si «Copiar al portapapeles en apps bloqueadas» está desactivado. Escribe una app por línea en el campo. Si un pegado falla, WhisPaste muestra un aviso y el texto queda en el portapapeles.';

  @override
  String get manualC02S4B4 =>
      'En Windows, Auto-Paste no funciona en programas que se ejecutan con derechos de administrador.';

  @override
  String get manualC02S4B5 =>
      'En Linux, WhisPaste marca el texto con una indicación que solo respeta Klipper de KDE. Otros gestores del portapapeles, como GPaste o CopyQ, también guardan tus transcripciones: desactiva allí el guardado del portapapeles o borra la entrada. En Linux con Wayland, WhisPaste informa de los errores solo mediante notificación y la bandeja.';

  @override
  String get manualC02S4B6 =>
      'Tras pegar, WhisPaste devuelve normalmente lo que había antes en el portapapeles. En «Portapapeles tras pegar» puedes elegir «Mantener la transcripción»: entonces el texto transcrito se queda en el portapapeles. Si el pegado no se puede confirmar a tiempo, la transcripción se queda allí, salvo que actives «Restaurar también sin confirmación». Si WhisPaste no puede escribir el acuse de lectura en el portapapeles, aparece un aviso discreto: Pegado no confirmado: el texto está en el portapapeles. Si macOS deniega el acceso al portapapeles, WhisPaste no puede guardar el contenido anterior y no lo restaura; la transcripción se queda entonces en el portapapeles. Una vez aparece un aviso con el camino a los Ajustes del Sistema.';

  @override
  String get manualC02S4B7 =>
      'Si un texto acaba en el campo equivocado, activa el atajo “Volver a pegar el último dictado” en “Atajos de teclado”. Vuelve a pegar el texto de tu última grabación en la app en primer plano. Viene configurado como Ctrl+Cmd+V en Mac y Alt+Mayús+V en Windows y Linux. Si guardar las grabaciones está desactivado, WhisPaste solo conoce la última grabación desde que se inició. Durante una grabación el atajo no hace nada. Si aún no hay nada que pegar, el overlay lo indica brevemente.';

  @override
  String get manualC02S4B8 =>
      'El “Panel de pegado rápido del portapapeles” se abre en el borde de la pantalla con tus transcripciones, snippets y el historial del portapapeles. Un clic pega una entrada. También puedes arrastrar una entrada directamente a otra aplicación.';

  @override
  String get manualC03Title => 'Nota rápida';

  @override
  String get manualC03S1Heading => 'Qué hace la nota rápida';

  @override
  String get manualC03S1B1 =>
      'La nota rápida es una nota a la que WhisPaste añade las nuevas grabaciones. Así reúnes ideas o una lista sin crear una nota nueva cada vez.';

  @override
  String get manualC03S1B2 =>
      'Si aún no hay ninguna nota marcada, WhisPaste crea una la primera vez y la marca.';

  @override
  String get manualC03S2Heading => 'Configurarla';

  @override
  String get manualC03S2B1I1 =>
      'Abre la nota en el área de notas y activa «Usar como nota rápida a la que añade el atajo». «Nota rápida: quitar la marca» quita la marca.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'Activa el atajo de nota rápida en Ajustes → Atajos de teclado. Viene desactivado por defecto. La tecla es $k1 ($k2, o $k3 en Mac).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'Qué hace Smart Mode';

  @override
  String manualC04S1B1(String k1) {
    return '$k1 edita el texto reconocido antes de pegarlo. Viene desactivado por defecto; lo activas tú.';
  }

  @override
  String get manualC04S1B2 =>
      'Por defecto, el procesamiento se ejecuta en tu equipo («En el dispositivo»). Con «OpenAI», el texto se envía a OpenAI. Los detalles están en el capítulo de privacidad.';

  @override
  String get manualC04S2Heading => 'Presets';

  @override
  String get manualC04S2B1 => 'Un preset define qué pasa con el texto:';

  @override
  String get manualC04S2B2I1 =>
      '«Desactivado»: sin posprocesado; el texto queda como se reconoció.';

  @override
  String get manualC04S2B2I2 =>
      '«Limpieza»: quita muletillas como «eh» y corrige puntuación y mayúsculas, sin cambiar las palabras, el sentido ni el idioma.';

  @override
  String get manualC04S2B2I3 =>
      '«Conciso»: quita repeticiones y muletillas, y mantiene todos los hechos importantes y el idioma.';

  @override
  String get manualC04S2B2I4 =>
      '«Traducir»: traduce el texto al idioma de destino que hayas elegido.';

  @override
  String get manualC04S3Heading => 'Idioma de destino y atajo';

  @override
  String get manualC04S3B1 =>
      'Para «Traducir», elige un idioma de destino: alemán, inglés, español, francés, portugués, mandarín o ruso. El predeterminado es inglés.';

  @override
  String manualC04S3B2(String k1) {
    return 'Un atajo propio para $k1 viene desactivado por defecto. Usa el preset y el idioma de destino de los ajustes.';
  }

  @override
  String get manualC04S4Heading => 'Recursos';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'La variante local descarga un modelo de texto de unos $size. Si tu equipo tiene menos de $ram de RAM, WhisPaste avisa antes de descargar, pero puedes hacerlo igualmente. Durante el uso, el modelo de texto necesita entre 4 y 5 GB de RAM adicionales.';
  }

  @override
  String get manualC04S4B2 =>
      'Mientras no haya ningún modelo de texto configurado (local sin descargar, u OpenAI sin clave), todos los presets excepto «Desactivado» están bloqueados. El dock y los ajustes indican el motivo y te llevan a la descarga o a la clave. Si el posprocesado falla igualmente, WhisPaste lo indica y te dice si el texto sin editar se ha pegado o solo está en el portapapeles.';

  @override
  String get manualC05Title => 'Diccionario';

  @override
  String get manualC05S1Heading => 'Cómo funcionan los reemplazos';

  @override
  String get manualC05S1B1 =>
      'Un reemplazo cambia automáticamente ciertas palabras o frases por otro texto en cada grabación.';

  @override
  String get manualC05S1B2 =>
      'Cada reemplazo tiene una o más frases de activación, es decir, las frases que buscar, y el texto nuevo. Escribe varias frases de activación para el mismo texto en «Frases de activación».';

  @override
  String get manualC05S1B3 =>
      'Para símbolos como paréntesis, @ o %: las plantillas de «Añadir plantillas de símbolos» en el menú los añaden. Los disparadores existentes no cambian.';

  @override
  String get manualC05S1B4 =>
      'El orden importa: las sustituciones se aplican en el orden en que las creaste. Si una sustitución produce un texto que es el disparador de una creada después, esa también se aplica. Crea en el orden deseado las sustituciones que se basan unas en otras.';

  @override
  String get manualC05S2Heading => 'Coincidencia';

  @override
  String get manualC05S2B1I1 =>
      'Exacta: solo se reemplaza la escritura idéntica.';

  @override
  String get manualC05S2B1I2 =>
      'Similar: también se reemplazan escrituras ligeramente distintas. Solo aplica a frases de activación de al menos 4 caracteres.';

  @override
  String get manualC05S2B1I3 =>
      'Tolerancia (estricta, estándar o flexible): se configura por entrada, no para todas a la vez.';

  @override
  String get manualC05S2B2 =>
      'Las frases de activación sin letras ni cifras, como ... o :), necesitan al menos 2 caracteres. Se sustituyen exactamente como están escritos, incluso dentro de una palabra. Un solo carácter, como ?, nunca se sustituye.';

  @override
  String get manualC05S3Heading => 'Importar y exportar (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'Puedes guardar o transferir tus reemplazos como archivo CSV. El archivo tiene las columnas $k1. Separa varias frases de activación con $k2. Un archivo puede tener como máximo $k3 y $k4 líneas.';
  }

  @override
  String get manualC05S3B2 =>
      'La importación y la exportación están en el menú Más (⋯) encima de la lista. El campo de prueba también se abre desde ese menú.';

  @override
  String get manualC06Title => 'Snippets';

  @override
  String get manualC06S1Heading => 'Qué son los snippets';

  @override
  String get manualC06S1B1 =>
      'Un snippet es un bloque de texto que insertas con una palabra de activación o un atajo, como una firma o una respuesta estándar.';

  @override
  String get manualC06S1B2I1 =>
      '«Estático»: el texto se inserta exactamente como lo guardaste.';

  @override
  String get manualC06S1B2I2 =>
      '«Interactivo»: WhisPaste pide los campos uno tras otro mediante grabaciones y los coloca en tu plantilla.';

  @override
  String get manualC06S2Heading => 'Abrir el selector de snippets';

  @override
  String get manualC06S2B1 => 'Hay dos formas de abrir el selector:';

  @override
  String get manualC06S2B2I1 =>
      'Con la palabra de activación del selector: di solo esa palabra para abrir el selector. Si la dices seguida del nombre de un snippet (por ejemplo «firma»), WhisPaste inserta directamente el snippet que corresponda. Si el nombre no es unívoco, el selector se abre con ese nombre como término de búsqueda. Solo funciona si toda la grabación tiene esta forma; en medio de una frase la palabra no tiene efecto. La defines en Ajustes, en Atajos de teclado, grupo Notas y snippets, justo debajo del atajo del selector; déjala vacía para desactivar el selector.';

  @override
  String get manualC06S2B2I2 =>
      'Con el atajo del selector: desactivado por defecto; actívalo en «Atajo del selector».';

  @override
  String manualC06S2B3(String shortcut) {
    return 'También puedes dictar un fragmento interactivo en una sola frase: en el selector, pulsa $shortcut o haz clic en el icono de bocadillo de la fila. Después, una vista previa muestra qué valor ha ido a cada campo. Puedes cambiar cualquier valor; Enter inserta, Esc cancela. Con un modelo de texto configurado basta una frase natural; sin él, di también los nombres de los campos.';
  }

  @override
  String get manualC06S3Heading => 'Crear un snippet';

  @override
  String get manualC06S3B1I1 =>
      'Crea un snippet con «Añadir» y elige «Estático» o «Interactivo».';

  @override
  String manualC06S3B1I2(String k1) {
    return 'En «Interactivo», define los campos y escribe la plantilla. Pon los marcadores entre llaves dobles, por ejemplo $k1.';
  }

  @override
  String get manualC07Title => 'Notas';

  @override
  String get manualC07S1Heading => 'Trabajar con notas';

  @override
  String get manualC07S1B1 =>
      'El área de notas reúne texto, como ideas o investigaciones. Las grabaciones van directamente a una nota cuando usas la nota rápida.';

  @override
  String get manualC07S1B2I1 => '«Marcar como favorita» destaca una nota.';

  @override
  String get manualC07S1B2I2 =>
      '«Añadir etiqueta» asigna una nota a una categoría.';

  @override
  String get manualC07S2Heading => 'Papelera';

  @override
  String get manualC07S2B1 =>
      '«Mover a la papelera» pone una nota en la papelera. Allí se queda hasta que la borres definitivamente. La papelera nunca se vacía sola.';

  @override
  String get manualC07S2B2I1 =>
      '«Eliminar definitivamente» quita la nota de la papelera.';

  @override
  String get manualC07S3Heading => 'Nota rápida';

  @override
  String get manualC07S3B1 =>
      'El área de notas muestra cuál es la nota rápida. Los detalles están en el capítulo de la nota rápida.';

  @override
  String get manualC07S4Heading => 'Imágenes y privacidad';

  @override
  String get manualC07S4B1 =>
      'Al añadir una imagen, WhisPaste elimina metadatos como la ubicación (GPS), los datos de la cámara y la información EXIF, XMP e IPTC. Solo se guarda la copia limpia.';

  @override
  String get notesPinGateTitle => 'Las notas están bloqueadas';

  @override
  String get notesPinGateHint => 'Introduce tu PIN para mostrar tus notas.';

  @override
  String get manualC08Title => 'Grabaciones';

  @override
  String get manualC08S1Heading => 'Qué contienen las grabaciones';

  @override
  String get manualC08S1B1 =>
      'Las grabaciones muestran cada entrada: el texto reconocido, con su fecha. Si se guardó audio, el archivo de audio pertenece a esa entrada.';

  @override
  String get manualC08S2Heading => 'Buscar y filtrar';

  @override
  String manualC08S2B1I1(String k1) {
    return 'Escribe $k1 para filtrar por etiquetas.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'Escribe $k1 y un idioma para filtrar por idioma.';
  }

  @override
  String get manualC08S2B1I3 => 'O simplemente escribe una palabra clave.';

  @override
  String get manualC08S2B1I4 =>
      'Encima de la lista están los filtros «Favoritos», «Archivadas», «Papelera» y «Todas».';

  @override
  String get manualC08S3Heading => 'Gestionar entradas';

  @override
  String get manualC08S3B1I1 =>
      '«Copiar texto» vuelve a copiar el texto al portapapeles.';

  @override
  String get manualC08S3B1I2 =>
      '«Añadir a favoritos» mantiene una entrada arriba. «Quitar de favoritos» lo deshace.';

  @override
  String get manualC08S3B1I3 =>
      '«Archivo» saca una entrada de la lista principal sin borrarla.';

  @override
  String get manualC08S3B1I4 =>
      '«Duplicar», «Combinar» (varias entradas en una) y «Seleccionar varias» ayudan a ordenar.';

  @override
  String get manualC08S3B1I5 =>
      '«Añadir anotación» y «Añadir etiqueta…» añaden detalles a una entrada.';

  @override
  String get manualC08S4Heading => 'Nota de voz';

  @override
  String get manualC08S4B1 =>
      'Inicia una nota de voz en la entrada. Di «tag: nombre» para poner una etiqueta, o «correct: texto» para sustituir el texto de la entrada.';

  @override
  String get manualC08S4B2 =>
      'Una corrección sustituye todo el texto de la entrada, no solo una palabra. «korrektur: texto» funciona igual. Justo después puedes deshacer el cambio desde el aviso.';

  @override
  String get manualC08S5Heading => 'Protección con PIN';

  @override
  String get manualC08S5B1 =>
      'Con «Protección con PIN», se exige un PIN antes de mostrar las grabaciones. Esto también aplica al panel lateral, al menú del botón flotante y a la API de automatización. El PIN evita que otros vean tus transcripciones, pero no las cifra. Las notas se bloquean de la misma forma. Con un PIN configurado, el menú de la bandeja muestra las grabaciones recientes solo con la hora y el número de palabras, sin el inicio del texto.';

  @override
  String get manualC08S5B2 =>
      'Un PIN olvidado no se puede recuperar. Para restablecerlo, se borran de inmediato todas las grabaciones y archivos de audio guardados (incluidos archivo y papelera), todas las notas con sus versiones y todas las imágenes de las notas. Los ajustes, fragmentos y reemplazos se conservan.';

  @override
  String get manualC08S5B3 =>
      'Mientras las grabaciones estén bloqueadas con un PIN, la pestaña del portapapeles del panel lateral no muestra texto copiado ni lo pega. El texto vuelve a aparecer al desbloquearlas.';

  @override
  String get manualC08S6Heading => 'Vaciado automático';

  @override
  String get manualC08S6B1 =>
      'En «Vaciar la papelera tras» defines cuánto tiempo permanecen las entradas borradas en la papelera antes de eliminarse automáticamente.';

  @override
  String get manualC08S7Heading => 'Desactivar el guardado';

  @override
  String manualC08S7B1(Object k1) {
    return 'Puedes desactivar el guardado en $k1. Un dictado solo se pega o se copia al portapapeles: no aparece en Grabaciones y no se conserva audio. Las grabaciones existentes se mantienen hasta que las borres. Las estadísticas y el recordatorio de valoración siguen funcionando. Los archivos importados siguen guardándose en Grabaciones, porque los eliges justo para eso.';
  }

  @override
  String get manualC09Title => 'Importar archivos de audio';

  @override
  String get manualC09S1Heading => 'Transcribir archivos de audio';

  @override
  String manualC09S1B1(String k1) {
    return 'Puedes transcribir archivos de audio que ya tengas. Elige «$k1» y selecciona el archivo.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'Además de $k1, según tu sistema puedes importar más formatos: en Mac $k2, en Linux $k3, en Windows $k4.';
  }

  @override
  String get manualC09S1B3 =>
      'En Linux, M4A/AAC necesita el decodificador AAC de GStreamer. El paquete .deb lo instala como paquete recomendado. Si falta en una instalación .deb o tarball, instálalo en Debian o Ubuntu con este comando y reinicia WhisPaste. La versión Flatpak no está verificada en cuanto a este decodificador, así que M4A/AAC puede faltar allí, y este comando no sirve para ella. La versión Snap debería incluirlo, pero aún no está verificado. Si falta allí, convierte el archivo a WAV.';

  @override
  String get manualC09S1Cmd => 'sudo apt install gstreamer1.0-libav';

  @override
  String get manualC09S2Heading => 'Límites';

  @override
  String get manualC09S2B2 =>
      'Qué hacer: divide la grabación en partes más cortas e impórtalas una a una.';

  @override
  String get manualC09S3Heading => 'Errores de importación';

  @override
  String manualC09S3B2(String k1) {
    return 'Qué hacer: inténtalo de nuevo. Si no funciona, reinicia WhisPaste o elige otro modelo en $k1.';
  }

  @override
  String get manualC10Title => 'Estadísticas';

  @override
  String get manualC10S1Heading => 'Las áreas';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'La estadística tiene tres áreas: $k1, $k2 y $k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'Con $k1 y $k2 eliges el periodo.';
  }

  @override
  String get manualC10S2Heading => 'Qué significan los números';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 y $k2 cuentan tus grabaciones y el tiempo grabado.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 es una estimación aproximada: WhisPaste cuenta dos tercios del tiempo de grabación como ahorrado, porque hablar suele ser más rápido que escribir. No es una medición.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: las grabaciones locales ahorran costes de la nube. WhisPaste lo estima en $k2 por minuto, una tarifa de referencia fija.';
  }

  @override
  String get manualC10S3Heading => 'Restablecer';

  @override
  String manualC10S3B1(String k1) {
    return '«$k1» borra todos los datos de estadísticas. WhisPaste pide confirmación antes, y no se puede deshacer.';
  }

  @override
  String get manualC11Title => 'Ajustes';

  @override
  String get manualC11S1Heading => 'Las secciones';

  @override
  String get manualC11S1B1 =>
      'Los ajustes están agrupados en secciones. Las más importantes:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: el aspecto de la app.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: modelo e idioma de reconocimiento.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: micrófono y volumen.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: preset, idioma de destino y proveedor.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: qué pasa después de una grabación.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: atajos.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: plazo de la papelera.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: exportación, importación y copia automática.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: API local y hooks de eventos para programas de este equipo.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: más opciones, como restablecer.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: versión, comprobación de actualizaciones, enlaces y licencias.';
  }

  @override
  String get manualC11S2Heading => 'Copia y restablecimiento';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 guarda tus ajustes automáticamente tras los cambios. Se conservan los últimos cinco archivos. Viene desactivado por defecto.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 borra de inmediato todas las transcripciones, los archivos de audio y los ajustes, y restablece WhisPaste. Lee la confirmación con atención antes de confirmarla.';
  }

  @override
  String get manualC12Title => 'Privacidad y uso sin conexión';

  @override
  String get manualC12S1Heading => 'Lo que se queda en tu equipo';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'Por defecto, el reconocimiento de voz se ejecuta en tu equipo. El audio solo va a un servicio en la nube si eliges activamente un proveedor en la nube. Las transcripciones se guardan en una base de datos local de tu equipo; los audios guardados, como archivos junto a ella. El audio de tus últimas $count grabaciones solo se conserva si “$k1” está activado, como máximo $days días.';
  }

  @override
  String get manualC12S1B2 =>
      'La comprobación de actualizaciones pregunta a GitHub por nuevas versiones. Los comentarios solo se envían al enviarlos.';

  @override
  String manualC12S1B3(int days) {
    return 'Si una transcripción falla porque el servidor o la conexión no están disponibles, el audio de esa grabación se conserva hasta $days días, para que puedas reintentarla desde el mensaje de error o en «Privacidad y datos». Esto también aplica con la conservación desactivada. Si está activada, se aplica en su lugar la conservación normal.';
  }

  @override
  String get manualC12S1B3Ref =>
      'Si una transcripción falla porque el servidor o la conexión no están disponibles, el audio de esa grabación se conserva durante el plazo que configures en «Privacidad y datos», para que puedas reintentarla desde el mensaje de error o allí. Esto también aplica con la conservación desactivada. Si está activada, se aplica en su lugar la conservación normal.';

  @override
  String get manualC12S1B5Ref =>
      'Cuántas grabaciones se guardan y cuándo pasan a la papelera las más antiguas lo configuras en «Privacidad y datos».';

  @override
  String get manualC12S1B4 =>
      'Las grabaciones interrumpidas, por ejemplo por un fallo o al cerrar la app, se procesan una vez en el próximo inicio y después se borra su audio. Esto también aplica con la conservación desactivada.';

  @override
  String get manualC12S2Heading => 'Proveedores en la nube';

  @override
  String manualC12S2B1(String k1) {
    return 'Los proveedores OpenAI y Deepgram necesitan tu propia clave API. Introdúcela en $k1.';
  }

  @override
  String get manualC12S3Heading => 'Estadísticas de uso e informes de errores';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'Dos opciones vienen activadas por defecto: $k1 y $k2. Puedes desactivar ambas en $k3.';
  }

  @override
  String get manualC13Title => 'Hardware y rendimiento';

  @override
  String get manualC13S1Heading => 'Memoria';

  @override
  String manualC13S1B1(String k1) {
    return 'WhisPaste recomienda al menos $k1 de memoria. Con menos, la app arranca igualmente y propone el modelo de voz “Rápido”.';
  }

  @override
  String get manualC13S2Heading => 'Tarjeta gráfica';

  @override
  String get manualC13S2B1 =>
      'WhisPaste usa la tarjeta gráfica cuando puede acelerar el reconocimiento de voz:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, la interfaz gráfica de Apple.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 y $k2 con gráficos AMD o Intel: $k3, una interfaz gráfica muy extendida.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'Las tarjetas NVIDIA también usan $k1. Con el paquete CUDA opcional, el reconocimiento también usa $k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'Sin una tarjeta gráfica adecuada, WhisPaste calcula en el procesador ($k1). Eso es más lento.';
  }

  @override
  String get manualC13S3Heading => 'El paquete CUDA';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'El paquete CUDA es un complemento opcional para tarjetas NVIDIA, según la app para $k1 y $k2. Está disponible para $k3 y $k4 (x64). Actívalo en $k5.';
  }

  @override
  String get manualC13S3B2 => 'La descarga es única. La app muestra su tamaño.';

  @override
  String get manualC13S3B3 =>
      'El paquete contiene componentes de NVIDIA. Antes de la primera descarga aceptas la licencia CUDA de NVIDIA (versión 2026-01-26); el consentimiento vale para esta instalación. Sin un consentimiento válido, la fila muestra «Se requiere consentimiento» y WhisPaste usa Vulkan o la CPU hasta que aceptes. Si cambia el texto de la licencia o el paquete, se vuelve a preguntar.';

  @override
  String get manualC13S4Heading => 'Aceleración gráfica';

  @override
  String manualC13S4B1(String k1) {
    return 'En $k1 eliges si WhisPaste usa la tarjeta gráfica. Solo el procesador suele ser más lento.';
  }

  @override
  String get manualC13S5Heading => 'Modelos y tamaño';

  @override
  String get manualC13S5B1 =>
      'Los modelos Whisper tienen tres niveles: Rápido, Equilibrado y Preciso. Los niveles más precisos suelen reconocer mejor, pero necesitan más tiempo de cálculo.';

  @override
  String get manualC13S6Heading =>
      'Vista general: último dictado y almacenamiento';

  @override
  String get manualC13S6B1 =>
      'En la vista general, «Último dictado» indica si el último dictado se procesó en el procesador o en la tarjeta gráfica y cuánto tardó el reconocimiento. Si la tarjeta gráfica estaba prevista pero no asumió el trabajo, aparece «Alternativa: la tarjeta gráfica estaba prevista, pero el procesador procesó el dictado.»';

  @override
  String get manualC13S6B2 =>
      '«Almacenamiento de WhisPaste» muestra el espacio de los modelos de voz, las grabaciones y la caché. «Limpiar…» vacía solo la caché, y solo después de preguntar. Los modelos de voz y las grabaciones no se tocan.';

  @override
  String get manualC14Title => 'Solución de problemas';

  @override
  String get manualC14S1Heading => 'Cómo leer esta página';

  @override
  String get manualC14S1B1 =>
      'Cada sección empieza con un aviso que muestra WhisPaste. El texto es el original de la app. Debajo están la causa y el siguiente paso.';

  @override
  String get manualC14S2Heading => 'Sin acceso al micrófono';

  @override
  String get manualC14S2B2 =>
      'Qué hacer: permite el acceso al micrófono para WhisPaste en los ajustes del sistema. Luego vuelve a iniciar la grabación.';

  @override
  String get manualC14S3Heading => 'No se encontró ningún micrófono';

  @override
  String manualC14S3B2(String k1) {
    return 'Qué hacer: conecta un micrófono y elígelo en $k1.';
  }

  @override
  String get manualC14S4Heading => 'No se captó audio';

  @override
  String manualC14S4B2(String k1) {
    return 'Qué hacer: comprueba que el micrófono correcto esté seleccionado y que el $k1 no esté en cero. Luego graba de nuevo.';
  }

  @override
  String get manualC14S5Heading => 'Sin modelo de voz';

  @override
  String manualC14S5B2(String k1) {
    return 'Qué hacer: descarga un modelo en $k1 e inténtalo de nuevo.';
  }

  @override
  String get manualC14S6Heading => 'Modelo desconocido';

  @override
  String manualC14S6B2(String k1) {
    return 'Qué hacer: elige un modelo instalado en $k1.';
  }

  @override
  String get manualC14S7Heading => 'Transcripción fallida';

  @override
  String manualC14S7B2(String k1) {
    return 'Qué hacer: inténtalo de nuevo. Si no funciona, reinicia WhisPaste o elige otro modelo en $k1.';
  }

  @override
  String get manualC14S8Heading => 'No se reconoció texto';

  @override
  String get manualC14S8B2 =>
      'Qué hacer: habla más claro o un poco más y vuelve a intentarlo. Revisa también el micrófono.';

  @override
  String get manualC14S9Heading => 'Grabación o transcripción demasiado larga';

  @override
  String get manualC14S9B2 => 'Qué hacer: graba secciones más cortas.';

  @override
  String get manualC14S10Heading => 'Falta la clave de la nube o no es válida';

  @override
  String manualC14S10B2(String k1) {
    return 'Qué hacer: introduce la clave de nuevo en $k1 o cambia al reconocimiento en el equipo.';
  }

  @override
  String get manualC14S11Heading => 'Memoria gráfica llena';

  @override
  String get manualC14S11B2 =>
      'Qué hacer: nada. Más tarde puedes volver a elegir el modelo en los ajustes.';

  @override
  String get manualC14S12Heading => 'Calculado en el procesador';

  @override
  String manualC14S12B2(String k1) {
    return 'Qué hacer: normalmente nada. Si ocurre a menudo, revisa el ajuste en $k1 y actualiza el controlador gráfico.';
  }

  @override
  String get manualC14S13Heading => 'Auto-Paste bloqueado (macOS)';

  @override
  String get manualC14S13B2 =>
      'Qué hacer: permite que WhisPaste use accesibilidad en los ajustes del sistema. Si el aviso sigue, reinicia WhisPaste.';

  @override
  String get manualC14S13SecureHeading =>
      'Auto-Paste omitido (entrada segura del teclado, macOS)';

  @override
  String get manualC14S13SecureB2 =>
      'Qué hacer: cierra la aplicación indicada en el aviso o cambia a otra y pega el texto de nuevo. Terminal e iTerm2 tienen la opción «Entrada segura del teclado» en su menú. Un campo de contraseña o PIN también activa la entrada segura; allí pega el texto a mano, porque macOS no pega automáticamente en esos campos.';

  @override
  String get manualC14S14Heading => 'Auto-Paste bloqueado (Windows)';

  @override
  String get manualC14S14B2 =>
      'Qué hacer: inicia WhisPaste también como administrador.';

  @override
  String get manualC14S15Heading => 'Auto-Paste en Linux';

  @override
  String get manualC14S15B1 =>
      'En Linux, Auto-Paste usa un dispositivo de entrada virtual (uinput). Si no funciona, comprueba si WhisPaste puede acceder a ese dispositivo.';

  @override
  String get manualC14S15B2 =>
      'El paquete .deb no da ningún acceso al instalarse. Auto-Paste pregunta primero: en la configuración inicial o en Ajustes → Después de la transcripción, elige «Permitir (contraseña de administrador)» e introduce tu contraseña de administrador. Mientras el permiso exista, otros programas de tu sesión también pueden generar pulsaciones. Con «Quitar permiso» lo retiras cuando quieras; al desinstalar también se quita.';

  @override
  String get manualC14S15B3 =>
      'La versión Flatpak da a la app acceso a los dispositivos de entrada del sistema, para que el pegado automático funcione. WhisPaste no lee por sí mismo ningún dispositivo de entrada.';

  @override
  String get manualC14S15B4 =>
      'En la versión Snap, ejecuta esto una vez en una terminal:';

  @override
  String get manualC14S15B5 =>
      'El AppImage necesita acceso a /dev/uinput. En la configuración inicial o en los ajustes, copia el comando y ejecútalo una vez en una terminal. Instala la regla udev 71-whispaste-uinput.rules en /etc/udev/rules.d/, que da acceso de escritura solo a la sesión iniciada. Hasta entonces, Auto-Paste solo copia el texto.';

  @override
  String get manualC14S15TerminalHeading => 'Terminales y Wayland';

  @override
  String get manualC14S15T1 =>
      'En Linux, los terminales pegan con Ctrl+Mayús+V. WhisPaste reconoce los terminales habituales y usa ese atajo por sí solo: con X11 y XWayland, y en KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire y otros escritorios wlroots.';

  @override
  String get manualC14S15T2 =>
      'En GNOME con Wayland, WhisPaste solo identifica la app de destino con la extensión opcional de WhisPaste para GNOME. Sin ella, WhisPaste no reconoce los terminales y una lista de bloqueo solo copia el texto.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'Si un terminal sigue mostrando ^V en lugar del texto, activa «$k1» en $k2. WhisPaste pegará entonces con Ctrl+Mayús+V en todas partes. Algunas apps usan estas teclas para otra cosa; LibreOffice, por ejemplo, abre un diálogo.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'En GNOME, activa la extensión de WhisPaste en los ajustes con $k1. El paquete .deb ya la instala. Con Flatpak, AppImage o el tarball, instálala una vez con el script del paquete de Linux descomprimido y luego actívala:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'Sin uinput configurado, por ejemplo en Flatpak, WhisPaste pega mediante el permiso del escritorio: $k1 en $k2. Tu escritorio pregunta una vez; puedes retirar el permiso allí cuando quieras';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'Este escritorio todavía no permite que las apps usen atajos de todo el sistema. WhisPaste puede añadir $shortcut a los atajos de teclado de GNOME.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'Añadir a GNOME';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut está configurado en los atajos de teclado de GNOME. Si cambias el atajo, WhisPaste lo actualiza allí.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'Quitar de GNOME';

  @override
  String get settingsDesktopShortcutFailed =>
      'No se pudieron cambiar los atajos de teclado de GNOME.';

  @override
  String get settingsDesktopShortcutManual =>
      'Este escritorio no permite que las apps usen atajos de todo el sistema. Asigna este comando a una combinación de teclas en los ajustes de tu sistema:';

  @override
  String get manualC14S15HotkeyHeading => 'Atajo global en Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'En Wayland, una app solo obtiene atajos de todo el sistema a través del escritorio. KDE Plasma y GNOME 48 o posterior los ofrecen. Las versiones anteriores de GNOME, como la de Ubuntu 24.04, no: entonces WhisPaste ofrece «$k1» en $k2 y añade el atajo a los atajos de teclado de GNOME. Antes de guardar una combinación, el grabador de atajos lo indica: el escritorio asigna el atajo, no WhisPaste.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'En otros escritorios, como Sway o Hyprland, asigna tú mismo el comando a una combinación de teclas. Los ajustes muestran el comando exacto para tu instalación en $k1.';
  }

  @override
  String get manualC14S15H3 =>
      'Si el atajo no funciona en otras apps, Ajustes y la configuración inicial muestran un aviso con el motivo, el comando para una combinación propia y el botón «Volver a conectar», que vuelve a pedir el atajo al escritorio.';

  @override
  String get manualC14S15G1 =>
      'Mantener o pulsar: si mantienes la tecla más tiempo que el umbral (250 ms por defecto), funciona como pulsar para hablar. Un toque breve inicia y detiene la grabación.';

  @override
  String get manualC14S15G2 =>
      'Una sola tecla: en lugar de una combinación puedes usar una sola tecla como atajo de dictado, distinguiendo izquierda y derecha. Mantenerla pulsada dicta hasta que la sueltas. Dos toques rápidos (en 400 ms) inician el dictado sin manos; una pulsación lo termina. Lo mismo vale para una combinación; desactiva «Doble toque: dictar sin manos» en «Atajos de teclado». Elige la tecla en «Atajos de teclado» → «Cambiar atajo».';

  @override
  String get manualC14S15G3 =>
      'Una sola tecla: son posibles Mayús, Ctrl, Alt u Opción y Comando, Windows o Super, cada una izquierda o derecha, además de Fn (solo Mac). Las teclas izquierdas y Mayús solo inician tras mantenerlas solas un momento, así los atajos normales no activan nada. En Linux con Wayland no hay teclas sueltas. Si la tecla no se puede usar en el dispositivo, se aplica de momento la combinación guardada; tu elección se conserva.';

  @override
  String get manualC14S15G4 =>
      'Permiso concedido más tarde: si WhisPaste no puede observar la tecla, lo vuelve a intentar en cuanto traes WhisPaste al frente. En el Mac, WhisPaste pide antes la Monitorización de entrada. Si la concedes más tarde en Ajustes del Sistema, la tecla funciona sin reiniciar. Esto solo vale mientras la combinación funciona como sustituto. En Windows, Windows puede negarse a dejar observar la tecla. En Linux la tecla no se puede usar si la sesión no informa cuándo se suelta una tecla.';

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'Con este acceso, la app podría en teoría leer las pulsaciones de otros programas si tu usuario puede leer los dispositivos de entrada (p. ej. como miembro del grupo input). Los miembros del grupo input también pueden generar entradas virtuales.';

  @override
  String get manualC14S15B3S =>
      'Auto-Paste además necesita acceso de escritura a /dev/uinput en el equipo: instala la regla udev 71-whispaste-uinput.rules en /etc/udev/rules.d/ y ejecuta después estos comandos:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'Copiar comando';

  @override
  String get manualCodeCopied => 'Comando copiado';

  @override
  String get manualCodeCopyFailed =>
      'No se pudo copiar. Selecciona el comando y cópialo a mano.';

  @override
  String get manualC14S15B3E =>
      'La regla da acceso de escritura solo a la sesión iniciada. Estos comandos requieren permisos de administrador (sudo) y modifican el sistema. Si no lo quieres, deja Auto-Paste desactivado y pega el texto a mano. Para quitar la regla, usa el botón de los ajustes que copia el comando correspondiente.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'Hasta entonces, Auto-Paste solo copia el texto.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'El atajo ya está en uso';

  @override
  String manualC14S16B2(String k1) {
    return 'Qué hacer: elige otra combinación en $k1. En el Mac, un toque en Fn abre los emojis y dos toques pueden iniciar el dictado del sistema. Para evitarlo, pon «Pulsar la tecla 🌐 para» en «No hacer nada» en Ajustes del Sistema → Teclado.';
  }

  @override
  String get manualC14S16B3 =>
      'WhisPaste avisa de una combinación que el sistema ya usa. Aun así puedes guardarla; el aviso indica la función del sistema y el siguiente paso.';

  @override
  String get manualC14S17Heading => 'Inicio automático no configurado';

  @override
  String get manualC14S17B2 =>
      'Qué hacer: revisa los permisos de inicio automático en el sistema operativo. Sin él, WhisPaste no se inicia solo.';

  @override
  String get manualC14S18Heading => 'Copia automática fallida';

  @override
  String manualC14S18B2(String k1) {
    return 'Qué hacer: elige otra carpeta accesible en $k1.';
  }

  @override
  String get manualC14S19Heading => 'Restablecimiento de fábrica incompleto';

  @override
  String get manualC14S19B2 =>
      'Qué hacer: elige “Reintentar” o reinicia WhisPaste y vuelve a ejecutar el restablecimiento después.';

  @override
  String get manualC14S20Heading => 'No se detectó sonido';

  @override
  String manualC14S20B2(String k1) {
    return 'Qué hacer: revisa el micrófono en $k1 y graba de nuevo.';
  }

  @override
  String get manualC14S21Heading => 'Memoria insuficiente';

  @override
  String get manualC14S22Heading => 'El atajo dejó de responder';

  @override
  String get manualC14S22B1 =>
      'A veces el sistema pierde el atajo global, por ejemplo tras la suspensión o cuando el equipo estaba muy ocupado. WhisPaste lo vuelve a registrar por sí mismo: al despertar el equipo, después de descargar el modelo de voz para liberar memoria, tras un bloqueo largo de la ventana y cada cinco minutos. No lo hace mientras dictas o mantienes pulsada la tecla. Si el atajo sigue sin responder, reinicia WhisPaste. Un aviso solo aparece tras tres intentos fallidos seguidos.';

  @override
  String manualC14S22B2(String k1) {
    return 'Si otra app usa la misma combinación, elige otra en $k1.';
  }

  @override
  String manualC14S21B1(String k1) {
    return 'WhisPaste también arranca con menos memoria de la recomendada ($k1). En ese caso, la app propone el modelo de voz “Rápido”.';
  }

  @override
  String get manualC15Title => 'Atajos de teclado';

  @override
  String get manualC15S1Heading => 'Solo dentro de WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'Estos atajos solo funcionan con la ventana de WhisPaste activa. El atajo de todo el sistema, en cambio, se configura en $k2.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'En Mac, $k1 suele sustituir a $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 abre la ayuda.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k también abre la ayuda.';
  }

  @override
  String get manualC15S2Heading => 'Grabaciones';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: borrar la entrada.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: cambiar favorito.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: buscar.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: cerrar la búsqueda o la vista de detalle.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: copiar la entrada.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: descartar la edición. Si hay cambios sin guardar, primero se pregunta.';
  }

  @override
  String get manualC15S3Heading => 'Notas';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: borrar la entrada.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: crear una nota nueva.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: buscar.';
  }

  @override
  String get manualC15S4Heading => 'Diccionario y snippets';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: borrar la entrada.';
  }

  @override
  String get manualC15S5Heading => 'Cancelar durante una grabación';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'Mientras hay una grabación o transcripción en curso, WhisPaste captura la tecla $k1 en todo el sistema para que puedas cancelar. Entonces $k1 no hace nada en otras aplicaciones. Si te molesta, elige $k2 como tecla de cancelar en Ajustes.';
  }

  @override
  String get manualC16Title => 'Comentarios y apoyo';

  @override
  String get manualC16S1Heading => 'Enviar comentarios';

  @override
  String get manualC16S1B1I1 => 'Valoración: obligatoria.';

  @override
  String get manualC16S1B1I2 =>
      'Tipo: obligatorio. Elige Problema, Idea, Elogio o Pregunta.';

  @override
  String get manualC16S1B1I3 => 'Texto libre de hasta 1000 caracteres.';

  @override
  String get manualC16S1B1I4 => 'La dirección de correo es opcional.';

  @override
  String get manualC16S1B2 =>
      'Si has enviado comentarios hace poco, la app muestra este aviso:';

  @override
  String get manualC16S2Heading => 'Apoyo';

  @override
  String manualC16S2B1(String k1) {
    return 'La pestaña $k1 de la ayuda muestra cómo puedes apoyar WhisPaste.';
  }

  @override
  String manualC16S2B2(String k1) {
    return 'Las descargas directas (instalador y portable de Windows, versión directa de Mac, Linux) muestran arriba de la pestaña $k1, bajo la versión en Ajustes, los botones de café Ko-fi y, donde se ofrezca, Buy Me a Coffee. Las versiones de tienda (Mac App Store, Microsoft Store) no tienen páginas externas; como mucho, ofrecen la propina de la propia tienda. El menú de la bandeja abre esa pestaña.';
  }

  @override
  String get manualC16S3Heading => 'Aviso de valoración';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'Si elegiste «No volver a preguntar» en el aviso de valoración, encontrarás el interruptor «$k2» en $k1. Solo aparece en ese caso.';
  }

  @override
  String get manualC16S4B1 =>
      'Puedes ponerte en contacto desde la tarjeta «Contactar» de la pestaña Ayuda, desde «Contactar…» en el menú Ayuda de la barra de menús (macOS) o en el menú de la barra de título (Windows y Linux), y desde el menú de la bandeja. Desde allí, el formulario está a dos pasos.';

  @override
  String get manualC16S5Heading => 'Compartir una idea';

  @override
  String get manualC16S5B1 =>
      'Elige Idea o abre Sugerir una idea desde el menú Ayuda: el tipo ya queda seleccionado. También puedes publicar tu idea en el tablero público de ideas y votar por las de otros.';

  @override
  String get manualC16S6Heading => 'Escribir con la voz';

  @override
  String get manualC16S6B1 =>
      'El botón del micrófono en el campo del mensaje graba tu voz e inserta el texto reconocido en el cursor.';

  @override
  String get manualC16S7Heading => 'Qué se envía';

  @override
  String get manualC16S7B1I1 => 'El tipo que elegiste y tu mensaje.';

  @override
  String get manualC16S7B1I3 =>
      'Tu correo solo si lo escribiste. Se usa únicamente para responderte y se borra a los 90 días.';

  @override
  String get manualC16S7B1I4 =>
      'El diagnóstico solo si activas Adjuntar diagnóstico: versión de la app, sistema operativo, motor de voz y backend. Mostrar vista previa te enseña el texto exacto antes de enviar.';

  @override
  String get manualC16S7B1I5 =>
      'Solo en Elogio: el permiso para mostrar tu elogio como cita en la web. Está desactivado por defecto y puedes retirarlo con un clic en esta página.';

  @override
  String get manualC16S7B2 =>
      'Las grabaciones y las transcripciones nunca se adjuntan.';

  @override
  String get manualC16S8Heading => 'Participar en el resumen';

  @override
  String get manualC16S8B1 =>
      'Las dos tarjetas muestran las estrellas en GitHub y los suscriptores en YouTube. La app consulta las cifras al servidor como máximo una vez al día, solo mientras el resumen está abierto. Las cifras de más de siete días ya no se muestran; sin cifra, la tarjeta solo indica para qué sirve el enlace. Abajo en el resumen, los enlaces llevan al código fuente y a los vídeos. «Apoya el proyecto» abre Ayuda → Apoyo, que muestra lo que ofrece tu versión. Las versiones de descarga directa muestran además el tablero de ideas; las versiones de la tienda, la valoración en la tienda. Puedes ocultar la sección con «Ocultar esta sección» o en «Personalizar resumen».';

  @override
  String get manualC16S4Heading => 'Dónde encontrar el formulario';

  @override
  String get manualC16S7B1I2 => 'La valoración que elegiste.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'No se pudo pegar: el texto está en el portapapeles ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'Comprobar permiso';

  @override
  String get autoPasteResetConfirmTitle =>
      '¿Restablecer la entrada y permitir de nuevo?';

  @override
  String get autoPasteResetConfirmBody =>
      'macOS guardó una entrada antigua de WhisPaste que ya no se aplica. WhisPaste elimina solo esta entrada de Accesibilidad. Después macOS volverá a preguntar. Los demás permisos no cambian.';

  @override
  String get autoPasteResetConfirmButton =>
      'Restablecer entrada y permitir de nuevo';

  @override
  String get permissionRowMicTitle => 'Micrófono';

  @override
  String get permissionRowMicPurpose =>
      'Graba tu voz. Sin este permiso no se puede grabar nada.';

  @override
  String get permissionRowPasteTitle => 'Auto-Paste';

  @override
  String get permissionRowPastePurpose =>
      'Coloca el texto en el cursor. Sin él, el texto queda en el portapapeles.';

  @override
  String get permissionRowAllow => 'Permitir';

  @override
  String get permissionRowMissingSettings => 'Falta – abrir Ajustes';

  @override
  String get permissionRowGranted => 'Permitido';

  @override
  String get permissionRowOptional => 'Opcional';

  @override
  String get autostartApprovalBody =>
      'macOS espera tu aprobación: WhisPaste solo se inicia al entrar si lo activas en Elementos de inicio.';

  @override
  String get autostartApprovalAction => 'Abrir Elementos de inicio';

  @override
  String get pasteFailureLinuxUinputHint =>
      'El pegado automático necesita una vez tu permiso para el teclado virtual (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'Copiar comando';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'El pegado automático no está disponible en este sistema: no hay ningún dispositivo de teclado virtual.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'El pegado automático necesita acceso único a /dev/uinput. Abre los ajustes de Auto-Paste para la configuración única.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'Auto-Paste ahora pregunta antes de usar el teclado virtual /dev/uinput, por eso esta actualización quitó el acceso anterior. El texto está en el portapapeles; pégalo con $paste. Haz clic aquí para permitirlo.';
  }

  @override
  String get linuxUinputSetupAction => 'Configurar';

  @override
  String get linuxUinputConsentDetail =>
      'Para pegar el texto por sí mismo, WhisPaste necesita un teclado virtual. Mientras esté permitido, otros programas de tu sesión también pueden generar pulsaciones. Sin permiso, WhisPaste copia el texto y lo pegas tú.';

  @override
  String get linuxUinputGrantButton => 'Permitir (contraseña de administrador)';

  @override
  String get linuxUinputGrantFailed =>
      'No se pudo dar el permiso. WhisPaste sigue copiando solo el texto.';

  @override
  String get linuxUinputRevokeButton => 'Quitar permiso';

  @override
  String get linuxUinputRevokeDone =>
      'Permiso quitado. WhisPaste ahora solo copia el texto.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'No se pudieron eliminar por completo las claves de API.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours h';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get dockErrorCauseEngine => 'El modelo de voz se detuvo con un error.';

  @override
  String get dockErrorCauseRecording => 'La grabación no se pudo transcribir.';

  @override
  String get dockErrorAction =>
      'Abre los ajustes de voz para revisar el modelo.';

  @override
  String get overlayDoneCopiedOnly =>
      'Solo copiado – app de destino bloqueada o no reconocida';

  @override
  String get overlayDoneNotPasted => 'No pegado – guardado en Grabaciones';

  @override
  String get overlayDonePasteFailed => 'Pegado no posible: copia el texto';

  @override
  String get overlayDoneInClipboard => 'En el portapapeles';

  @override
  String get databaseTooNewTitle => 'WhisPaste no puede abrir tus datos';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'Los datos proceden de una versión más reciente de WhisPaste (versión de la base de datos $storedVersion). Esta versión admite hasta la versión $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'Instala la última versión de WhisPaste y vuelve a abrir la app. No se ha cambiado ni borrado nada.';

  @override
  String get databaseTooNewQuit => 'Salir';

  @override
  String get databaseUpgradeInterruptedTitle =>
      'WhisPaste no pudo actualizar tus datos';

  @override
  String get databaseUpgradeInterruptedCause =>
      'Ahora mismo no se pudieron pasar tus datos a la nueva versión: el archivo estaba ocupado o el disco no respondió. No se ha cambiado nada y todos tus datos siguen ahí.';

  @override
  String get databaseUpgradeInterruptedNextStep =>
      'Cierra otros programas que puedan estar usando el archivo, comprueba el espacio libre en el disco y vuelve a intentarlo.';

  @override
  String get pasteFailureTargetChanged =>
      'Auto-pegado cancelado: cambiaste de app durante el procesamiento. El texto está en el portapapeles.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'Auto-pegado no confirmado. El texto está en el portapapeles, pégalo con $paste.';
  }

  @override
  String get pasteHintSecureField =>
      'macOS no permite el auto-pegado en los campos de contraseña y PIN. Pega el texto allí a mano.';

  @override
  String pasteSecureInputNamed(String app) {
    return '“$app” tiene activada la entrada segura del teclado, así que WhisPaste no pega automáticamente. Cierra $app o cambia a otra aplicación.';
  }

  @override
  String get pasteSecureInputGeneric =>
      'Una aplicación tiene activada la entrada segura del teclado, así que WhisPaste no pega automáticamente. Cierra esa aplicación o cambia a otra.';

  @override
  String pasteSecureInputClipboard(String paste) {
    return 'El texto está en el portapapeles. Pégalo con $paste.';
  }

  @override
  String get pasteSecureInputTerminalTip =>
      'En Terminal, abre el menú Terminal y desactiva «Entrada segura del teclado».';

  @override
  String get pasteSecureInputItermTip =>
      'En iTerm2, desactiva «Secure Keyboard Entry» (Entrada segura del teclado) en la barra de menús.';

  @override
  String get pasteNotificationReceiptRefusedTitle =>
      'WhisPaste: pegado no confirmado';

  @override
  String get pasteReceiptRefusedText =>
      'Pegado no confirmado: el texto está en el portapapeles.';

  @override
  String get fileDialogOpenTitle => 'Abrir archivo';

  @override
  String get fileDialogOpenFilesTitle => 'Abrir archivos';

  @override
  String get fileDialogSaveTitle => 'Guardar archivo';

  @override
  String get fileDialogFolderTitle => 'Elegir carpeta';

  @override
  String get fileDialogSelectFolder => 'Seleccionar';

  @override
  String get dockLanguageAuto => 'Automático';

  @override
  String get settingsLanguageFavoriteAdd => 'Añadir a favoritos';

  @override
  String get settingsLanguageFavoriteRemove => 'Quitar de favoritos';

  @override
  String get settingsLanguageFavoritesLimit =>
      'Hasta 3 favoritos. Quita uno para añadir otro.';

  @override
  String get dockMenuFavorites => 'Favoritos';

  @override
  String get dockMenuAllLanguages => 'Todos los idiomas';

  @override
  String get traySpeechModel => 'Modelo de voz';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'El icono de la bandeja necesita un host de bandeja. En GNOME, instala la extensión AppIndicator; hasta entonces el menú de cambio rápido no está disponible.';

  @override
  String get trayLanguage => 'Idioma';

  @override
  String get trayLanguageMore => 'Más…';

  @override
  String get trayProfile => 'Perfil';

  @override
  String get trayProfileAutomatic => 'Automático según la app';

  @override
  String get trayProfileNone => 'Sin perfil';

  @override
  String profileSwitchedToast(String name) {
    return 'Perfil: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'Siguiente idioma favorito';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'Siguiente idioma favorito';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'Cambia el idioma de dictado al siguiente favorito. Marca hasta tres idiomas como favoritos en Voz a texto.';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'Ya lo usa $action. Elige otra combinación.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'Otra aplicación usa este atajo o no se pudo registrar. Elige otra combinación.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'En Wayland, este atajo puede no funcionar en otras apps. Crea un atajo de escritorio si no responde.';

  @override
  String get settingsHotkeyActionRepaste => 'Volver a pegar el último dictado';

  @override
  String get settingsRepasteHotkeyEnabled => 'Volver a pegar el último dictado';

  @override
  String get settingsRepasteHotkeyHint =>
      'Vuelve a pegar el texto de tu última grabación en la app en primer plano, por ejemplo si acabó en el campo equivocado.';

  @override
  String get repasteNothingYet => 'Aún no hay ningún dictado para pegar';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'Idioma de dictado: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'Idioma de dictado: $language. Se aplica a partir de la próxima grabación.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'Aún no hay idiomas favoritos. Marca hasta tres idiomas en Voz a texto para usar este atajo.';

  @override
  String get languageCycleOpenSettings => 'Abrir ajustes';

  @override
  String get manualLangFavHeading => 'Idiomas favoritos';

  @override
  String get manualLangFavB1 =>
      'En los ajustes de reconocimiento de voz, marca hasta tres idiomas como favoritos con la estrella de la lista de idiomas. Los favoritos aparecen primero en el menú de idiomas de la barra de grabación y en el menú de la bandeja, para cambiar con un clic.';

  @override
  String get manualLangTrayHeading => 'Idioma en el menú de la bandeja';

  @override
  String get manualLangTrayB1 =>
      'El menú de la bandeja tiene un submenú Idioma. Muestra tus favoritos y marca con una señal el idioma activo. Más… abre la ventana con la lista completa. Parakeet elige su propio idioma, así que el submenú está oculto allí.';

  @override
  String get manualLangCycleHeading => 'Siguiente idioma favorito';

  @override
  String get manualLangCycleB1 =>
      'En la tarjeta Dictado puedes asignar una combinación de teclas que cambia el idioma de dictado al siguiente favorito en cada pulsación. El atajo permanece desactivado hasta que grabes una combinación. Sin favoritos, WhisPaste te indica dónde ajustarlos. En Linux con Wayland, otras apps pueden no responder al atajo.';

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut solo funciona en todo el sistema cuando se añade a los atajos de teclado de GNOME.';
  }

  @override
  String get recommendationReasonLanguage =>
      'Recomendado porque Parakeet admite tu idioma y es la opción más precisa que funciona con fluidez en este equipo.';

  @override
  String get recommendationReasonMeasured =>
      'Recomendado según la medición en este equipo.';

  @override
  String recommendationReasonApple(String memory) {
    return 'Recomendado para tu chip de Apple (Metal) con $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'Recomendado para tu tarjeta gráfica NVIDIA con $gb GB de memoria de vídeo (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'Recomendado para tu tarjeta gráfica $name (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'Recomendado para el procesador, porque no hay una tarjeta gráfica utilizable: $cores núcleos, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name es gráfica por software, así que el procesador hace el trabajo: $cores núcleos, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb GB de RAM';
  }

  @override
  String get recommendationMemoryUnknown => 'RAM desconocida';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'Sin modelo de voz – descargar $name ahora ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'Si falta el modelo de voz seleccionado, el dock muestra «Falta el modelo de voz». El menú de voz del dock lo ofrece entonces como primera entrada para descargarlo, tanto para Whisper como para Parakeet. Si pulsas el atajo sin modelo, aparece un aviso con «Descargar ahora». Si cambias a Whisper en Ajustes y falta el modelo Whisper seleccionado, WhisPaste elige uno ya descargado.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'Procesador (Vulkan por software, $name)';
  }

  @override
  String get menuBarMenuEdit => 'Editar';

  @override
  String get menuBarMenuWindow => 'Ventana';

  @override
  String get menuBarEditUndo => 'Deshacer';

  @override
  String get menuBarEditRedo => 'Rehacer';

  @override
  String get menuBarEditCut => 'Cortar';

  @override
  String get menuBarEditCopy => 'Copiar';

  @override
  String get menuBarEditPaste => 'Pegar';

  @override
  String get menuBarEditSelectAll => 'Seleccionar todo';

  @override
  String get menuBarWindowMinimize => 'Minimizar';

  @override
  String get menuBarWindowZoom => 'Ampliar';

  @override
  String get menuBarAppQuit => 'Salir de WhisPaste';

  @override
  String get menuBarMenuRecording => 'Grabación';

  @override
  String get menuBarAppSettings => 'Ajustes…';

  @override
  String get menuBarHelpManual => 'Abrir el manual';

  @override
  String get menuBarHelpFeedback => 'Enviar comentarios…';

  @override
  String get menuBarHelpIdea => 'Sugerir una idea…';

  @override
  String get menuBarHelpContact => 'Contactar…';

  @override
  String get helpContactHeading => 'Contactar';

  @override
  String get helpContactBody =>
      '¿Tienes una pregunta o necesitas ayuda? Escríbenos, con gusto te ayudamos.';

  @override
  String get helpContactAction => 'Contactar';

  @override
  String get helpContactIdeasLink =>
      'Las ideas van al tablero público de votación';

  @override
  String get manualC15S6Heading => 'Menú';

  @override
  String get manualC15S6B1 =>
      'En el Mac, los comandos más importantes también están en la barra de menús superior. El menú «Grabación» inicia y detiene una grabación y ajusta el idioma, el modelo de voz, el Smart Mode, la acción tras la transcripción, el micrófono y el perfil.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: abrir los ajustes con $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'Editar: cortar, copiar, pegar y seleccionar todo actúan sobre el campo de texto activo.';

  @override
  String get manualC15S6B2I3 =>
      'Ventana: minimizar y ampliar la ventana principal.';

  @override
  String get manualC15S6B2I4 =>
      'Ayuda: abrir el manual, enviar comentarios y sugerir una idea.';

  @override
  String get manualC15S6B3 =>
      'En Windows y Linux, los mismos comandos están en un botón de menú arriba a la derecha de la barra de título. Pulsa Alt o F10 para abrirlo, usa las flechas para elegir una entrada, Intro para ejecutarla y Escape para cerrar el menú.';

  @override
  String get menuBarAppAbout => 'Acerca de WhisPaste';

  @override
  String get menuBarAppHide => 'Ocultar';

  @override
  String get menuBarAppHideOthers => 'Ocultar otros';

  @override
  String get menuBarAppShowAll => 'Mostrar todo';

  @override
  String get titleBarMenuLabel => 'Menú';

  @override
  String get notesTitleLabel => 'Título';

  @override
  String get notesMoreActions => 'Más acciones';

  @override
  String get notesVersionSaveNow => 'Guardar versión ahora';

  @override
  String get notesMenuMark => 'Resaltar';

  @override
  String get notesMenuAddImage => 'Insertar imagen';

  @override
  String get notesMenuVersions => 'Versiones';

  @override
  String get notesMenuSnippet => 'Guardar como snippet';

  @override
  String get notesVersionsEmpty => 'Todavía no hay versiones.';

  @override
  String get notesVersionTooLarge => 'Demasiado grande para la vista previa';

  @override
  String get notesVersionDelete => 'Eliminar versión';

  @override
  String get notesVersionSaved => 'Versión guardada';

  @override
  String get notesVersionUnchanged => 'No hay cambios desde la última versión.';

  @override
  String get notesVersionRestored => 'Versión restaurada';

  @override
  String get notesVersionRestoreMessage =>
      'Solo se restauran el título y el texto de esta versión. Las imágenes no cambian.';

  @override
  String get notesVersionDeleteMessage =>
      'Esta versión se elimina de forma permanente y no se puede recuperar.';

  @override
  String get notesImageFilesLabel => 'Imágenes';

  @override
  String get notesImageRejected =>
      'Este archivo no es una imagen compatible (PNG, JPEG, GIF o WebP).';

  @override
  String get notesImageRemove => 'Quitar imagen';

  @override
  String get notesSnippetCreated => 'Snippet creado';

  @override
  String get notesSnippetNothing =>
      'Esta nota no tiene texto para guardar como snippet.';

  @override
  String get notesMarkNeedsSelection => 'Primero selecciona un texto.';

  @override
  String get notesImageLimitCount =>
      'Esta nota ya tiene el número máximo de imágenes.';

  @override
  String get notesImageLimitBytes =>
      'Las imágenes de esta nota superarían el límite de tamaño.';

  @override
  String get notesImageLimitTotal =>
      'El almacenamiento de imágenes está lleno. Quita una imagen para añadir otra.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'El archivo llegó demasiado lento o cambió durante la copia. Inténtalo de nuevo.';

  @override
  String get historyImportFailureDecoderUnavailableLinux =>
      'Para M4A/AAC falta en Linux un paquete extra: el decodificador AAC de GStreamer. Instala gstreamer1.0-libav (en Debian o Ubuntu con sudo apt install gstreamer1.0-libav; en otras distribuciones, busca el paquete libav de GStreamer en tu gestor de paquetes), reinicia WhisPaste e impórtalo de nuevo.';

  @override
  String get historyImportFailureDecoderUnavailableSnap =>
      'Falta el decodificador AAC de GStreamer para M4A/AAC. La versión Snap debería incluirlo. Informa de este caso a través de Comentarios e indica tu versión de Snap. Mientras tanto, convierte el archivo a WAV e impórtalo de nuevo.';

  @override
  String get historyImportFailureDecoderUnavailableFlatpak =>
      'Falta el decodificador AAC de GStreamer para M4A/AAC en la versión Flatpak. La sandbox de Flatpak no se puede ampliar con el gestor de paquetes. Convierte el archivo a WAV e impórtalo de nuevo. El manual describe el soporte de M4A/AAC en Flatpak en el capítulo Importar archivos de audio; si no resuelve tu caso, notifícalo a través de Comentarios.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'Este formato no está disponible en este sistema. Convierte el archivo a WAV e impórtalo de nuevo.';

  @override
  String get audioDropHint =>
      'Suelta aquí los archivos de audio para transcribirlos';

  @override
  String audioDropRejectedFolder(String names) {
    return 'No se pueden importar carpetas: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'Archivo no encontrado: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'No compatible: $names. Formatos permitidos: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'No es un archivo normal, no se puede importar: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'Demasiado grande (máximo 1 GB): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'No es un archivo normal y no se puede importar.';

  @override
  String get historyImportRejectedTooLarge => 'El archivo es mayor de 1 GB.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'Nombre de dispositivo reservado, no se puede importar: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'Windows reserva este nombre de archivo y no se puede importar. Cambie el nombre del archivo.';

  @override
  String get historyImportFailureIo =>
      'El almacenamiento está lleno o no se puede escribir.';

  @override
  String get holdToRecordExplained =>
      'Activado: mantén pulsado el atajo y habla; suéltalo para terminar. Desactivado: pulsa una vez para empezar y otra para terminar.';

  @override
  String get settingsAreaProfiles => 'Perfiles';

  @override
  String get profilesSectionHeading => 'Tus perfiles';

  @override
  String get profilesEmptyBody =>
      'Los perfiles cambian el modelo de voz, el idioma, Smart Mode y la acción tras la transcripción con un atajo o automáticamente por aplicación.';

  @override
  String get profilesAddFirst => 'Crear el primer perfil';

  @override
  String get profilesAdd => 'Crear perfil';

  @override
  String get profilesCreate => 'Crear';

  @override
  String get profilesLimitReached =>
      'Máximo 9 perfiles. Elimina uno para crear otro.';

  @override
  String get profilesActiveBadge => 'Activo';

  @override
  String get profilesMoveUp => 'Subir';

  @override
  String get profilesMoveDown => 'Bajar';

  @override
  String get profilesDragHandle => 'Arrastra para ordenar';

  @override
  String get profilesNewTitle => 'Nuevo perfil';

  @override
  String get profilesNameLabel => 'Nombre';

  @override
  String get profilesNameEmpty => 'Introduce un nombre.';

  @override
  String get profileDetailHeading => 'Ajustes del perfil';

  @override
  String get profileDetailModel => 'Modelo de voz';

  @override
  String get profileDetailLanguage => 'Idioma';

  @override
  String get profileDetailLanguageSubtitle =>
      'Se aplica a Whisper y a los servicios en la nube. Parakeet detecta el idioma por sí mismo.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'Tras la transcripción';

  @override
  String get profileDetailMicrophone => 'Micrófono';

  @override
  String get profileKeepUnchanged => 'Dejar sin cambios';

  @override
  String profileValueUnavailable(String value) {
    return '$value (no disponible)';
  }

  @override
  String get profileDetailHotkey => 'Atajo';

  @override
  String get profileDetailHotkeySubtitle =>
      'Cambia a este perfil con esta pulsación.';

  @override
  String get profileHotkeyNone => 'Sin atajo';

  @override
  String get profileHotkeyChange => 'Definir atajo';

  @override
  String get profileHotkeyRemove => 'Quitar atajo';

  @override
  String get profileHotkeyNeedsModifier =>
      'Un atajo de perfil necesita al menos una tecla modificadora, como Ctrl, Alt, Mayús o Comando.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'Ya lo usa «$action». El atajo no está activo.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'Ya lo usa el perfil «$name». El atajo no está activo.';
  }

  @override
  String get profileDetailApps => 'Aplicaciones de destino';

  @override
  String get profileDetailAppsSubtitle =>
      'Si una de estas apps está en primer plano al dictar, el perfil se activa solo.';

  @override
  String get profileAppIdentifierLabel => 'Identificador de la app';

  @override
  String get profileAppAdd => 'Añadir';

  @override
  String get profileAppHintMac =>
      'macOS: ID del paquete, p. ej. com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: nombre del programa sin .exe, p. ej. chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: WM_CLASS de la ventana, p. ej. google-chrome. No detectable en Wayland.';

  @override
  String profileAppClash(String name) {
    return 'Esta app ya pertenece al perfil «$name».';
  }

  @override
  String get profileAppEmpty => 'Aún no hay ninguna app asignada.';

  @override
  String get profileAppRemove => 'Quitar regla de app';

  @override
  String get profileDetailContext => 'Leer contexto';

  @override
  String get profileDetailContextSubtitle =>
      'Opcionalmente lee el texto seleccionado o el portapapeles para ajustar el procesamiento. Con servicios en la nube, solo con tu consentimiento.';

  @override
  String get profileContextNone => 'No leer nada';

  @override
  String get profileContextSelection => 'Texto seleccionado';

  @override
  String get profileContextClipboard => 'Portapapeles';

  @override
  String get profileConsentGiven => 'Consentimiento dado';

  @override
  String get profileConsentMissing =>
      'Falta el consentimiento; no se lee contexto';

  @override
  String get profileConsentWithdraw => 'Retirar consentimiento';

  @override
  String get profileConsentTitle =>
      '¿Enviar contexto a un servicio en la nube?';

  @override
  String get profileConsentBody =>
      'Cuando este perfil está activo, el texto seleccionado o el contenido del portapapeles de la ventana de destino se envían al proveedor en la nube indicado en este perfil, solo para refinar este dictado. Puedes retirar este consentimiento en cualquier momento en los ajustes del perfil.';

  @override
  String get profileConsentAccept => 'Consentir';

  @override
  String get profileDeleteAction => 'Eliminar perfil';

  @override
  String profileDeleteTitle(String name) {
    return '¿Eliminar el perfil «$name»?';
  }

  @override
  String get profileDeleteMessage =>
      'Se eliminarán el perfil y sus apps de destino. Su atajo quedará libre.';

  @override
  String get manualProfilesTitle => 'Perfiles y cambio rápido';

  @override
  String get manualProfilesS1Heading => 'Crear perfiles';

  @override
  String get manualProfilesS1Body =>
      'Un perfil es un conjunto con nombre de ajustes de dictado. Lo creas en Ajustes → Perfiles y decides en cada campo si el perfil lo define o lo deja sin cambios.';

  @override
  String get manualProfilesS1B1 =>
      'Modelo de voz, idioma, Smart Mode, acción tras la transcripción y micrófono';

  @override
  String get manualProfilesS1B2 =>
      'Hasta 9 perfiles. Cada campo puede quedar en «Dejar sin cambios».';

  @override
  String get manualProfilesS2Heading => 'Atajos';

  @override
  String get manualProfilesS2Body =>
      'Cada perfil puede tener su propio atajo. Al pulsarlo, el perfil se activa y sigue activo hasta que elijas otro o cambies a mano uno de sus campos.';

  @override
  String get manualProfilesS2Tip =>
      'Un atajo necesita una tecla modificadora. Una combinación que ya usa otra función queda inactiva y el perfil la muestra como conflicto.';

  @override
  String get manualProfilesS3Heading => 'Automático por aplicación';

  @override
  String get manualProfilesS3Body =>
      'Si añades una app en Aplicaciones de destino, el perfil se activa cuando esa app está en primer plano al dictar. El identificador depende del sistema operativo:';

  @override
  String get manualProfilesS3Mac =>
      'macOS: ID del paquete, por ejemplo com.apple.mail';

  @override
  String get manualProfilesS3Win =>
      'Windows: nombre del programa sin .exe, por ejemplo chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: WM_CLASS de la ventana en X11, por ejemplo google-chrome. En Wayland WhisPaste no puede detectar la app.';

  @override
  String get manualProfilesS4Heading => 'Bandeja y superposición';

  @override
  String get manualProfilesS4Body =>
      'El menú de la bandeja tiene un submenú Perfil: «Automático según la app» sigue las reglas, «Sin perfil» las desactiva, y debajo están tus perfiles. En la superposición de grabación, el nombre del perfil activo aparece tras la hora y el idioma, por ejemplo 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'Dejar sin cambios';

  @override
  String get manualProfilesS5Body =>
      '«Dejar sin cambios» significa que el perfil no toca ese campo. Se aplica el valor que esté configurado ahora en los ajustes.';

  @override
  String get manualProfilesS6Heading => 'Qué hace un cambio manual';

  @override
  String get manualProfilesS6Body =>
      'Si eliges un perfil en la bandeja o pulsas su atajo, se aplica a todos los dictados siguientes. Si luego cambias un campo que el perfil define, como el modelo de voz, la marca activo desaparece y vuelven a decidir las reglas por app. La elección se mantiene tras reiniciar.';

  @override
  String get profileAppCapture => 'Capturar app';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'Cambia a la app de destino en $seconds s …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '«$identifier» se añadió como app de destino.';
  }

  @override
  String get profileAppCaptureNone =>
      'No hay otra app en primer plano. Cambia a la app de destino antes de que termine la cuenta atrás.';

  @override
  String get profileAppCaptureUnavailable =>
      'Esta sesión no puede leer la app en primer plano (por ejemplo Wayland). Escribe el identificador a mano.';

  @override
  String get waylandHotkeyPortalDescription => 'Dictado de WhisPaste';

  @override
  String get waylandHotkeyNoAppId =>
      'Tu escritorio no pudo identificar WhisPaste y no ha activado el atajo, así que no funciona en otras apps.';

  @override
  String get waylandHotkeyUnavailable =>
      'Tu escritorio no permite que las apps usen un atajo global, así que el atajo no funciona en otras apps.';

  @override
  String get waylandHotkeyDeclined =>
      'El atajo no se confirmó en el diálogo de tu escritorio, así que no funciona en otras apps.';

  @override
  String get waylandHotkeyFallback =>
      'En su lugar, puedes crear un atajo de teclado en la configuración del sistema con este comando:';

  @override
  String waylandHotkeyBoundTrigger(String trigger) {
    return 'El escritorio asignó $trigger a WhisPaste. Puedes cambiarlo en los ajustes de teclado del sistema.';
  }

  @override
  String get waylandHotkeyBoundNoTrigger =>
      'El escritorio asigna el atajo, no WhisPaste. Puedes cambiarlo en los ajustes de teclado del sistema.';

  @override
  String get waylandHotkeyReconnect => 'Volver a conectar';

  @override
  String get waylandHotkeyCopyCommand => 'Copiar comando';

  @override
  String get waylandHotkeyCommandCopied => 'Copiado';

  @override
  String get waylandHotkeyOpenKeyboardSettings =>
      'Abrir configuración del teclado';

  @override
  String get sttEngineRestartHint =>
      'El reconocimiento de voz está bloqueado. Reinicia WhisPaste: ciérralo desde el menú de la bandeja (Salir) y vuelve a abrirlo.';

  @override
  String get shortPressHintMessage =>
      'Pulsación corta detectada. Para un teclado en pantalla o pulsaciones rápidas, activa «Pulsar o mantener».';

  @override
  String get shortPressHintAction => 'Activar «Pulsar o mantener»';

  @override
  String get manualA11yHeading => 'Teclado en pantalla y movilidad reducida';

  @override
  String get manualA11yB1 =>
      'Con un teclado en pantalla no se puede mantener una tecla pulsada: un clic la presiona y la suelta de inmediato. Por eso la grabación se detiene al instante al mantener. Usa «Pulsar o mantener» en su lugar: una pulsación corta inicia la grabación y la siguiente la termina.';

  @override
  String get manualA11yB2 =>
      'Recomendamos este ajuste para un teclado en pantalla o si mantener pulsado te resulta difícil. Lo encuentras en Ajustes → Atajos de teclado.';

  @override
  String get manualA11yB3 =>
      'El botón flotante ya no se mueve cuando haces clic con una mano que tiembla un poco. Solo se arrastra cuando lo mueves claramente.';

  @override
  String get settingsSttCustomEndpoint => 'Endpoint propio';

  @override
  String get customEndpointUrlTitle => 'Dirección del servidor';

  @override
  String get customEndpointUrlSubtitle =>
      'Dirección base que termina en /v1, p. ej. http://localhost:1234/v1 para LM Studio. Sirve también para Ollama, llama.cpp o un proveedor externo.';

  @override
  String get customEndpointUrlInvalid =>
      'Esta dirección no es válida. Ejemplo: http://localhost:1234/v1';

  @override
  String get customEndpointUrlCredentials =>
      'La dirección no puede contener credenciales, consulta (?) ni fragmento (#). Introduce la clave en el campo «Clave».';

  @override
  String get customEndpointUrlHttpRemote =>
      'Los servidores de internet necesitan https. Con http, la clave y el contenido viajarían sin cifrar por internet. http solo se permite para este dispositivo y la red local.';

  @override
  String get customEndpointNoticeLocal => 'Permanece en este dispositivo.';

  @override
  String get customEndpointNoticeLan => 'Permanece en la red local.';

  @override
  String get customEndpointHttpLanWarning =>
      'Sin cifrar en la red local: otros dispositivos de la red pueden leer el audio o el texto. Usa https si el servidor lo admite.';

  @override
  String get manualC12S2B4 =>
      'La ruta de transcripción es fija: /audio/transcriptions, como en OpenAI; Smart Mode usa /chat/completions. El servidor debe ofrecer ambas bajo la dirección que termina en /v1.';

  @override
  String customEndpointNoticeRemoteAudio(String host) {
    return 'El audio se envía a $host.';
  }

  @override
  String customEndpointNoticeRemoteText(String host) {
    return 'El texto transcrito se envía a $host.';
  }

  @override
  String get customEndpointKeyTitle => 'Clave (opcional)';

  @override
  String get customEndpointKeySubtitle =>
      'Solo si tu servidor lo exige. Se guarda en el almacén de claves del sistema y nunca se exporta.';

  @override
  String get customEndpointSttModelTitle => 'Nombre del modelo de voz';

  @override
  String get customEndpointSmartModelTitle => 'Nombre del modelo de texto';

  @override
  String get customEndpointModelSubtitle =>
      'El nombre del modelo tal como lo conoce el servidor.';

  @override
  String get customEndpointTestTitle => 'Comprobar la conexión';

  @override
  String get customEndpointTestSubtitle =>
      'Solo consulta la lista de modelos. No se envían audio ni texto.';

  @override
  String get customEndpointTestAction => 'Probar conexión';

  @override
  String get customEndpointTestDisabledHint =>
      'Introduce antes una dirección válida y un nombre de modelo.';

  @override
  String get customEndpointProbeConnected =>
      'Conectado. El servidor responde y el modelo está disponible.';

  @override
  String get customEndpointProbeConnectedUnverified =>
      'Conectado. El servidor no lista modelos; el nombre del modelo se comprueba en el primer dictado.';

  @override
  String customEndpointProbeModelMissing(String models) {
    return 'Falta el modelo: el servidor no conoce este modelo. Disponibles: $models. Ajusta el nombre del modelo o carga el modelo en el servidor.';
  }

  @override
  String get customEndpointProbeUnreachable =>
      'No se puede acceder. ¿Está el servidor en marcha y son correctos la dirección y el puerto?';

  @override
  String get customEndpointProbeUnauthorized =>
      'El servidor rechaza la clave o exige una. Revisa la clave.';

  @override
  String get customEndpointProbeBadFormat =>
      'Formato incorrecto: el servidor no responde como un servicio compatible con OpenAI. La dirección suele terminar en /v1.';

  @override
  String get customEndpointProbeServerError =>
      'El servidor informa de un error. Revisa su registro y vuelve a probar.';

  @override
  String get smartModeConfigureEndpointAction => 'Configurar endpoint propio';

  @override
  String get errorCustomEndpointUnreachable =>
      'El endpoint propio no es accesible. ¿Está el servidor en marcha y son correctos la dirección y el puerto? La grabación se conserva.';

  @override
  String get errorCustomEndpointNotConfigured =>
      'El endpoint propio no está configurado. Introduce la dirección y el nombre del modelo en los ajustes.';

  @override
  String get errorCustomModelMissing =>
      'El servidor no conoce el modelo seleccionado. Revisa el nombre del modelo en los ajustes.';

  @override
  String get errorCustomBadResponse =>
      'El endpoint propio responde con un formato incorrecto. Revisa la dirección, suele terminar en /v1.';

  @override
  String get errorCustomEndpointUnauthorized =>
      'El endpoint propio rechaza la clave o exige una. Revisa la clave en los ajustes.';

  @override
  String get errorCustomEndpointServerError =>
      'El endpoint propio informa de un error del servidor. Revisa su registro y vuelve a intentarlo.';

  @override
  String get manualC12S2B2 =>
      'Endpoint propio: para un servidor en tu red o en este dispositivo (LM Studio, Ollama, llama.cpp) introduce su dirección que termine en /v1, una clave opcional y el nombre del modelo. Con «Probar conexión» compruebas el acceso, la clave y el modelo.';

  @override
  String get manualC12S2B3 =>
      'Adónde van el audio y el texto: en este dispositivo (localhost, 127.0.0.1, ::1) todo permanece aquí. En la red local (direcciones privadas como 192.168.x.x y nombres .local) permanece en la red; otros dispositivos allí pueden leer el http sin cifrar. Un servidor en internet recibe el audio (transcripción) o el texto (Smart Mode) y solo es accesible por https.';

  @override
  String onboardingAccessibilityDragHint(String app) {
    return 'Arrastra con el ratón el icono de $app de la derecha hacia arriba, a la lista.';
  }

  @override
  String get onboardingContactOpen => 'Abrir el formulario de contacto';

  @override
  String get onboardingContactTitle => 'Escríbenos';

  @override
  String get onboardingContactClose => 'Cerrar';

  @override
  String get onboardingContactGreeting => '¡Hola! ¿De qué se trata?';

  @override
  String get onboardingContactKindIdea => 'Idea o deseo';

  @override
  String get onboardingContactKindProblem => 'Informar de un problema';

  @override
  String get onboardingContactKindQuestion => 'Hacer una pregunta';

  @override
  String get onboardingContactKindOther => 'Otra cosa';

  @override
  String get onboardingContactIdeaText =>
      'Reunimos las ideas públicamente en nuestro tablero de ideas. Allí puedes proponer nuevas y votar las existentes.';

  @override
  String get onboardingContactIdeaOpen => 'Ir al tablero de ideas';

  @override
  String get onboardingContactBack => 'Cambiar tema';

  @override
  String get onboardingContactNote =>
      'Respondemos por correo electrónico. No es un chat en vivo.';

  @override
  String onboardingContactSentReply(String email) {
    return 'Gracias: tu mensaje se ha enviado. Responderemos a $email.';
  }

  @override
  String get onboardingContactDone => 'Listo';

  @override
  String get onboardingContactSpeakerYou => 'Tú';

  @override
  String get onboardingContactEmailHint =>
      'Sin dirección no podemos responderte.';

  @override
  String get onboardingContactProblemText =>
      'Describe brevemente qué no funciona.';

  @override
  String get onboardingContactQuestionText =>
      'Escríbenos tu pregunta. Añade un correo si quieres una respuesta.';

  @override
  String get onboardingContactOtherText => 'Cuéntanos de qué se trata.';

  @override
  String get onboardingContactMessageLabel => 'Tu mensaje';

  @override
  String onboardingContactMessageTooShort(int count) {
    return 'Escribe al menos $count caracteres.';
  }

  @override
  String get onboardingContactEmailLabel =>
      'Correo electrónico para la respuesta (opcional)';

  @override
  String get onboardingContactEmailInvalid =>
      'Esta dirección de correo no parece completa.';

  @override
  String get onboardingContactDiagnosticsLabel => 'Enviar datos técnicos';

  @override
  String get onboardingContactDiagnosticsExplanation =>
      'Solo el paso actual, la versión de la app y el sistema operativo.';

  @override
  String get onboardingContactSend => 'Enviar mensaje';

  @override
  String get onboardingContactSent => '¡Gracias! Tu mensaje ha llegado.';

  @override
  String get onboardingContactErrorOffline =>
      'No ha funcionado. ¿Tienes conexión? Tu texto se conserva.';

  @override
  String get onboardingContactErrorRateLimited =>
      'Ahora mismo llegan demasiados mensajes. Inténtalo más tarde.';

  @override
  String get onboardingContactErrorUnavailable =>
      'El envío no está disponible en esta versión. Escribe a kontakt@whispaste.de.';

  @override
  String get onboardingContactRetry => 'Reintentar';

  @override
  String get onboardingContactMailAddress => 'kontakt@whispaste.de';

  @override
  String onboardingContactSendSoon(String address) {
    return 'Pronto podrás enviar directamente desde la app. Mientras tanto, escríbenos a $address.';
  }

  @override
  String get onboardingContactWriteMail => 'Escribir un correo';

  @override
  String get onboardingAboutTitle => 'Haz WhisPaste tuyo.';

  @override
  String get onboardingAboutSubtitle => 'Todo es opcional.';

  @override
  String get onboardingAboutNameLabel => 'Tu nombre';

  @override
  String get onboardingAboutNameHint => 'Opcional';

  @override
  String get onboardingAboutRolesLabel => '¿Para qué usas WhisPaste?';

  @override
  String get onboardingAboutRolesHint => 'Puedes elegir varias';

  @override
  String get onboardingAboutRoleWriting => 'Escritura';

  @override
  String get onboardingAboutRoleDev => 'Desarrollo';

  @override
  String get onboardingAboutRoleLegal => 'Derecho';

  @override
  String get onboardingAboutRoleEducation => 'Educación';

  @override
  String get onboardingAboutRoleBusiness => 'Oficina y negocios';

  @override
  String get onboardingAboutOther => 'Otro';

  @override
  String get onboardingAboutFoundLabel => '¿Cómo nos encontraste?';

  @override
  String get onboardingAboutFoundSearch => 'Búsqueda';

  @override
  String get onboardingAboutFoundAi => 'ChatGPT y similares';

  @override
  String get onboardingAboutFoundFriend => 'Recomendación';

  @override
  String get onboardingAboutFoundStore => 'Tienda de apps';

  @override
  String get onboardingAboutFoundSocial => 'Redes sociales';

  @override
  String get onboardingAboutFoundVideo => 'Vídeo';

  @override
  String get onboardingAboutFoundGithub => 'GitHub';

  @override
  String get onboardingAboutPreviewLabel => 'Vista previa';

  @override
  String onboardingAboutPreviewSample(String name) {
    return 'Soy $name. Con gusto me encargo de organizar la próxima reunión del equipo.';
  }

  @override
  String get onboardingStickerOpenSource => 'Código abierto';

  @override
  String get onboardingStickerLocal => 'Funciona en local';

  @override
  String get onboardingAboutPreviewSampleAnonymous =>
      'Con gusto me encargo de organizar la próxima reunión del equipo.';

  @override
  String get onboardingPermissionsSceneSentence =>
      'Las bebidas para la fiesta de verano ya están pedidas, la lista está en la cocina.';

  @override
  String get onboardingPermissionsSceneGreeting => 'Hola a todos:';

  @override
  String get onboardingMicTitle => 'Prueba tu micrófono.';

  @override
  String get onboardingMicModelStillLoading =>
      'El modelo de voz aún se está descargando en segundo plano. Sigue adelante; solo tiene que estar listo para la prueba.';

  @override
  String get onboardingMicQuiet =>
      'Apenas llega sonido. Habla un poco más alto o más cerca del micrófono.';

  @override
  String get onboardingMicNoDevice =>
      'No se encontró ningún micrófono. Conecta uno y seguirá solo.';

  @override
  String get onboardingMicDisconnected =>
      'El micrófono se desconectó. En cuanto vuelva, seguirá solo.';

  @override
  String get onboardingMicChooseOther => 'Elegir otro micrófono';

  @override
  String get onboardingMicBluetoothHint =>
      'Los auriculares Bluetooth suelen sonar apagados al dictar. WhisPaste suele entender mejor un micrófono integrado o USB.';

  @override
  String get onboardingPrivacyReadyTitle => 'Listo para dictar.';

  @override
  String get onboardingPrivacyAlmostReadyTitle => 'Casi listo para dictar.';

  @override
  String get onboardingPrivacyModeLocal =>
      'Tu audio y tu texto se quedan en este dispositivo; el reconocimiento es local.';

  @override
  String onboardingPrivacyModeCloud(String provider) {
    return 'Tu audio va directamente a $provider, nunca a través de servidores de WhisPaste.';
  }

  @override
  String onboardingPrivacyModeCustom(String host) {
    return 'Tu audio va directamente a tu servidor: $host.';
  }

  @override
  String get onboardingPrivacySettingsHint =>
      'Puedes cambiarlo cuando quieras en Ajustes → Privacidad. Allí también decides si se conserva el audio de tus grabaciones.';

  @override
  String onboardingHotkeyCueHold(String shortcut) {
    return 'Ahora mantén pulsado $shortcut';
  }

  @override
  String onboardingHotkeyCuePress(String shortcut) {
    return 'Ahora pulsa $shortcut';
  }

  @override
  String onboardingHotkeyCueDoubleTap(String shortcut) {
    return 'Ahora toca $shortcut dos veces rápido';
  }

  @override
  String onboardingPracticeLonger(String shortcut) {
    return '¿Vas a hablar más tiempo? Toca $shortcut dos veces rápido y dictarás sin manos. Una pulsación lo termina.';
  }

  @override
  String get onboardingPracticeReceivedHandsFree =>
      'Llegó sin manos. Así dictas cómodamente también textos largos.';

  @override
  String get firstStepsTitle => 'Primeros pasos';

  @override
  String firstStepsProgress(int done, int total) {
    return '$done de $total completados';
  }

  @override
  String get firstStepsItemPasteTitle => 'Dictar una vez en otra app';

  @override
  String get firstStepsItemPasteAction => 'Ir al atajo';

  @override
  String get firstStepsItemCopyTitle => 'Encuentra una grabación y cópiala';

  @override
  String get firstStepsItemCopyAction => 'Ir a las grabaciones';

  @override
  String get firstStepsItemPersonalizeTitle =>
      'Añadir una palabra al diccionario';

  @override
  String get firstStepsItemPersonalizeAction => 'Ir al diccionario';

  @override
  String get firstStepsItemNoteTitle => 'Dicta una nota';

  @override
  String get firstStepsItemNoteAction => 'Ir a las notas';

  @override
  String get firstStepsComplete =>
      'Listo. Ya puedes hablar y escribir con libertad.';

  @override
  String get firstStepsRestoreTitle => 'Primeros pasos';

  @override
  String get firstStepsRestoreSubtitle =>
      'Volver a mostrar la tarjeta con los primeros pasos en la pantalla de inicio.';

  @override
  String get firstStepsRestoreAction => 'Mostrar de nuevo';

  @override
  String get navOverview => 'Resumen';

  @override
  String get overviewBadgeHint => 'Novedades de esta versión';

  @override
  String overviewGreetingNamed(String name) {
    return 'Hola $name, dicta en cualquier lugar con';
  }

  @override
  String get overviewGreetingAnonymous => 'Dicta en cualquier lugar con';

  @override
  String get overviewHotkeyModeHold => 'mantener';

  @override
  String get overviewHotkeyModeToggle => 'pulsar';

  @override
  String get overviewStatusModelMissing =>
      'No hay ningún modelo de voz instalado. Dictar funcionará cuando haya uno cargado.';

  @override
  String get overviewStatusModelDownloading =>
      'Se está descargando el modelo de voz. El dictado funcionará cuando termine.';

  @override
  String get overviewStatusModelFailed =>
      'No se pudo descargar el modelo de voz. El dictado funcionará cuando se descargue.';

  @override
  String get overviewStatusMicDenied =>
      'WhisPaste no tiene permiso para usar el micrófono. El dictado funcionará cuando lo permitas.';

  @override
  String get overviewStatusHotkeyUnbound =>
      'El atajo de dictado aún no está activo.';

  @override
  String get overviewStatusModelAction => 'Configurar modelo de voz';

  @override
  String get overviewStatusModelProgressAction => 'Ver progreso';

  @override
  String get overviewStatusMicAction => 'Permitir micrófono';

  @override
  String get overviewStatusHotkeyAction => 'Configurar atajo';

  @override
  String get overviewCustomize => 'Personalizar resumen';

  @override
  String get overviewCustomizeTips => 'Consejos';

  @override
  String get overviewCustomizeFirstSteps =>
      'Volver a mostrar los primeros pasos';

  @override
  String get overviewStatusMicSettingsAction => 'Abrir ajustes del sistema';

  @override
  String get overviewStatusModelRetryAction => 'Reintentar';

  @override
  String get overviewStatusRecoveryAction => 'Recuperar grabación';

  @override
  String overviewStatusRecovery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Todavía se pueden recuperar $count grabaciones interrumpidas.',
      one: 'Todavía se puede recuperar una grabación interrumpida.',
    );
    return '$_temp0';
  }

  @override
  String get overviewFiguresTitle => 'Tus cifras';

  @override
  String get overviewFiguresWords => 'Palabras';

  @override
  String get overviewFiguresWordsPerMinute => 'Palabras por minuto';

  @override
  String get overviewFiguresTooFewData => 'Aún no hay suficientes datos';

  @override
  String get overviewFiguresTimeSaved => 'Tiempo ahorrado';

  @override
  String get overviewPeriodWeek => 'Esta semana';

  @override
  String get overviewPeriodAll => 'Total';

  @override
  String get overviewStreakLabel => 'Días con dictado esta semana';

  @override
  String get overviewStreakLabelAll => 'Días con dictado en total';

  @override
  String get overviewRecentTitle => 'Últimas grabaciones';

  @override
  String get overviewRecentAll => 'Todas las grabaciones';

  @override
  String get overviewRecentEmptyBefore => 'Aún no hay grabaciones – pulsa';

  @override
  String get overviewRecentEmptyAfter => 'en cualquier aplicación.';

  @override
  String get overviewRecentEmptyPutAway =>
      'Todas las grabaciones están archivadas o en la papelera.';

  @override
  String get overviewRecentEmptyNotSaved =>
      'Las grabaciones no se guardan. El dictado sigue funcionando.';

  @override
  String get overviewRecentEmptyNotSavedAction => 'Activar guardado';

  @override
  String get overviewRecentLocalNote =>
      'Tus grabaciones se quedan en este dispositivo.';

  @override
  String overviewMilestoneTitle(int count) {
    return '$count dictados con WhisPaste';
  }

  @override
  String get overviewMilestoneBody =>
      'Es texto que no tuviste que escribir. Gracias por escribir con WhisPaste.';

  @override
  String get overviewMilestoneClose => 'Cerrar';

  @override
  String get overviewRateTitle => 'Recomendar WhisPaste';

  @override
  String get overviewRateBody =>
      'Una valoración o un enlace compartido ayuda a otros a encontrar WhisPaste.';

  @override
  String get overviewRateStore => 'Valorar en la tienda';

  @override
  String get overviewRateGitHub => 'Dar una estrella en GitHub';

  @override
  String get overviewShareCopyLink => 'Copiar enlace';

  @override
  String get overviewShareCopied => 'Enlace al sitio web copiado';

  @override
  String get overviewRateLater => 'Más tarde';

  @override
  String get overviewRateNever => 'No volver a preguntar';

  @override
  String get overviewRecentCopy => 'Copiar';

  @override
  String get overviewRecentOpen => 'Abrir en grabaciones';

  @override
  String get overviewTipHeading => 'Descubrir';

  @override
  String get overviewTipTry => 'Probar';

  @override
  String get overviewTipHide => 'Ocultar este consejo';

  @override
  String get overviewTipsOff => 'No más consejos';

  @override
  String get overviewTipSmartBody =>
      'Limpia, acorta o traduce el texto antes de pegarlo, por defecto en tu dispositivo.';

  @override
  String get overviewTipVocabularyBody =>
      'Añade una vez los nombres y términos técnicos que se escriben mal.';

  @override
  String get overviewTipSnippetsBody =>
      'Guarda textos recurrentes e insértalos con un atajo o con la voz.';

  @override
  String get overviewTipNotesBody =>
      'Anota ideas sin depender de una grabación.';

  @override
  String get overviewTipOverlayTitle => 'Diseña la superposición';

  @override
  String get overviewTipOverlayBody =>
      'Ajusta el tamaño, la forma y el color de la superposición de dictado.';

  @override
  String get overviewTipRecordingModeTitle => 'Modo de grabación';

  @override
  String get overviewTipRecordingModeBody =>
      'Mantén pulsado para dictar o pulsa una vez para iniciar y detener.';

  @override
  String get overviewWhatsNewTitle => 'Novedades de esta versión';

  @override
  String get overviewWhatsNewClose => 'Entendido';

  @override
  String get overviewStorageTitle => 'Almacenamiento de WhisPaste';

  @override
  String get overviewStorageModels => 'Modelos de voz';

  @override
  String get overviewStorageRecordings => 'Grabaciones';

  @override
  String get overviewStorageCache => 'Caché';

  @override
  String get overviewStorageCleanup => 'Limpiar…';

  @override
  String get overviewStorageCleanupTitle => '¿Vaciar la caché?';

  @override
  String overviewStorageCleanupMessage(String size) {
    return 'Se eliminarán $size. Los modelos de voz y las grabaciones no se tocan; la caché se vuelve a crear cuando hace falta.';
  }

  @override
  String get overviewStorageCleanupConfirm => 'Vaciar';

  @override
  String get overviewStorageCleanupFailed =>
      'No se pudo vaciar la caché. Revisa los permisos de su carpeta.';

  @override
  String get overviewStorageUnreadable => 'no legible';

  @override
  String get overviewStorageManage => 'Cambiar la retención';

  @override
  String get overviewLastDictationTitle => 'Último dictado';

  @override
  String get overviewCommunityTitle => 'Participa';

  @override
  String get overviewCommunityHide => 'Ocultar esta sección';

  @override
  String get overviewCommunityProject => 'Para WhisPaste';

  @override
  String get overviewCommunityDeveloper => 'Del desarrollador';

  @override
  String get overviewCommunityGithub => 'WhisPaste en GitHub';

  @override
  String get overviewCommunityYoutube => 'WhisPaste en YouTube';

  @override
  String get overviewCommunitySupport => 'Apoyar WhisPaste';

  @override
  String get overviewCommunityRateStore => 'Valorar en la tienda';

  @override
  String get overviewCommunityVotepit => 'Proponer ideas y votar';

  @override
  String get overviewCommunityGithubBenefit =>
      'Una estrella ayuda a otros a encontrar WhisPaste. Aquí también puedes reportar errores.';

  @override
  String get overviewCommunityGithubAction => 'Dar una estrella en GitHub';

  @override
  String get overviewCommunityYoutubeBenefit =>
      'Consejos y novedades sobre WhisPaste.';

  @override
  String get overviewCommunityYoutubeAction => 'Suscribirse en YouTube';

  @override
  String get overviewCommunityStarsLabel => 'estrellas';

  @override
  String get overviewCommunitySubscribersLabel => 'suscriptores';

  @override
  String get overviewCommunityProfileGithub => 'Perfil de GitHub';

  @override
  String get overviewCommunityOpensBrowser => 'se abre en el navegador';

  @override
  String get overviewCommunityOpensStore => 'abre la tienda';

  @override
  String get overviewCommunityMenu => 'Participa';

  @override
  String get overviewLastDictationNone =>
      'Todavía no hay ningún dictado en este dispositivo.';

  @override
  String get overviewLastDictationCpu => 'Procesador';

  @override
  String get overviewLastDictationGpu => 'Tarjeta gráfica';

  @override
  String get overviewLastDictationCloud => 'Servicio en la nube';

  @override
  String overviewLastDictationDuration(String seconds) {
    return 'Procesamiento $seconds s';
  }

  @override
  String get overviewLastDictationFallback =>
      'Alternativa: la tarjeta gráfica estaba prevista, pero el procesador procesó el dictado.';
}
