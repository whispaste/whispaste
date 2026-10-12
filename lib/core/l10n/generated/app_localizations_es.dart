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
  String get navHistory => 'Historial';

  @override
  String get navNotes => 'Notas';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navReplacements => 'Reemplazos';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navAnalytics => 'Estadísticas';

  @override
  String get navAbout => 'Acerca de';

  @override
  String get navFeedback => 'Comentarios';

  @override
  String get pageHistoryTitle => 'Historial';

  @override
  String get pageSettingsTitle => 'Ajustes';

  @override
  String get pageReplacementsTitle => 'Reemplazos';

  @override
  String get pageAnalyticsTitle => 'Estadísticas';

  @override
  String get pageAboutTitle => 'Acerca de';

  @override
  String get pageFeedbackTitle => 'Comentarios';

  @override
  String get historyEmpty => 'Todavía no hay grabaciones';

  @override
  String get historyEmptyHint =>
      'Pulsa el botón de grabar o usa el atajo para empezar a grabar.';

  @override
  String get historyPrivacyGateTitle => 'Historial oculto';

  @override
  String get historyPrivacyGateHint =>
      'Tus transcripciones anteriores seguirán ocultas hasta que decidas mostrarlas.';

  @override
  String get historyPrivacyGateShow => 'Mostrar historial';

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
  String get historyCopyAsMarkdown => 'Copiar como Markdown';

  @override
  String get historyDetail => 'Detalle';

  @override
  String get historyTags => 'Etiquetas';

  @override
  String get historyDuration => 'Duración';

  @override
  String get historyModel => 'Modelo';

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
  String get historyEditing => 'Editando';

  @override
  String get historySearchTranscriptions => 'Buscar transcripciones…';

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
    return 'Ninguna transcripción coincide con «$query».\nPrueba con otro término de búsqueda.';
  }

  @override
  String get historyTrashEmpty => 'La papelera está vacía';

  @override
  String get historyTrashEmptyHint =>
      'Las transcripciones eliminadas aparecerán aquí.\nSe borran definitivamente tras 30 días.';

  @override
  String get historyEmptyTrash => 'Vaciar papelera';

  @override
  String get historyEmptyTrashConfirm => '¿Vaciar la papelera?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'Se eliminarán definitivamente todos los elementos de la papelera. Esta acción no se puede deshacer.';

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Papelera vaciada: $count entradas eliminadas',
      one: 'Papelera vaciada: 1 entrada eliminada',
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
      'Indicador de CPU/GPU en la barra de estado';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Muestra si la transcripción se ejecuta de verdad en la CPU o en la GPU, y con qué carga';

  @override
  String get settingsAudio => 'Audio';

  @override
  String get settingsAudioSubtitle => 'Micrófono y grabación';

  @override
  String get settingsMicrophone => 'Micrófono';

  @override
  String get settingsGain => 'Volumen del micrófono';

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
  String get settingsSpeechRecognition => 'Reconocimiento de voz';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Calidad y servicio del reconocimiento de voz';

  @override
  String get settingsService => 'Servicio';

  @override
  String get settingsQuality => 'Calidad';

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
  String get settingsAfterTranscriptionActionLabel => 'Acción';

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
  String get pasteFailureGeneric =>
      'El Auto-Paste falló. La transcripción está en el portapapeles; pégala manualmente con ⌘V / Ctrl+V.';

  @override
  String get pasteFailureOpenSettings => 'Abrir ajustes';

  @override
  String get pasteNotificationNoTargetTitle => 'WhisPaste: Auto-Paste omitido';

  @override
  String get pasteNotificationNoTargetBody =>
      'No se detectó ninguna app de destino. Enfoca primero la app de destino y luego inicia la grabación. El texto está en el portapapeles.';

  @override
  String get pasteNotificationNoTargetTray =>
      'Auto-Paste: falta la app de destino';

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
  String get pasteNotificationFailedBody =>
      'El sistema rechazó el pegado. El texto está en el portapapeles; pégalo manualmente con ⌘V / Ctrl+V.';

  @override
  String get pasteNotificationFailedTray => 'Error en Auto-Paste';

  @override
  String get pasteCapabilityCheckTitle => 'Un momento…';

  @override
  String get pasteCapabilityReady => 'Todo listo';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Tu dictado aparece justo en el cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Sin permiso todavía';

  @override
  String get pasteCapabilityUnsupported =>
      'Auto-Paste no está disponible en esta plataforma';

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
  String get pasteManualGrantAlertTitle => 'El reinicio no sirvió';

  @override
  String get pasteManualGrantAlertBody =>
      'WhisPaste ya se ha reiniciado, pero el permiso de Auto-Paste sigue sin aplicarse. Comprueba en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad que WhisPaste esté activado y, si hace falta, vuelve a activar el interruptor.';

  @override
  String get pasteManualGrantAlertConfirm => 'Abrir Ajustes del Sistema';

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
      'WhisPaste inserta tu dictado justo en el cursor. Para ello macOS necesita un interruptor que solo tú puedes activar: Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Confirma para abrir exactamente esa página. WhisPaste detecta tu autorización automáticamente y, si hace falta, se reinicia después.';

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
  String get onboardingPasteTitle => 'Para que el texto llegue donde escribes';

  @override
  String get onboardingPasteSubtitle =>
      'macOS te preguntará en un momento si WhisPaste puede hacerlo. Di que sí, y listo.';

  @override
  String get onboardingPasteSubtitleWin =>
      'En Windows no hace falta ningún permiso: solo decide si WhisPaste debe insertar el dictado por ti.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste listo';

  @override
  String get onboardingPasteChipPending => 'Acceso a Auto-Paste pendiente';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: hay que actuar';

  @override
  String get onboardingPasteGrantCta => 'Permitir Auto-Paste';

  @override
  String get onboardingPasteSkip => 'Solo copiar, sin Auto-Paste';

  @override
  String get onboardingPasteWhyMac =>
      'Sin permiso, tu texto se copia al portapapeles. Después lo pegarás manualmente con ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'Tras cada dictado, Auto-Paste pulsa Ctrl+V por ti, así el texto aparece justo donde estás escribiendo. Comprobado que funciona en este equipo; actívalo abajo.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'En ciertas apps con protección UIPI/UAC, Auto-Paste no funciona. El texto quedará en el portapapeles y tendrás que pegarlo tú con Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'Auto-Paste está activado';

  @override
  String get onboardingPasteWinOnDetail =>
      'Tras cada dictado, WhisPaste pulsa Ctrl+V por ti: el texto aparece justo en el cursor. Además, una copia se queda en el portapapeles.';

  @override
  String get onboardingPasteWinEnableCta => 'Activar Auto-Paste';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'Las apps que se ejecutan como administrador no aceptan pulsaciones simuladas; ahí el texto se queda en el portapapeles, listo para pegarlo con Ctrl+V.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Marca la casilla junto a WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Los Ajustes del Sistema están abiertos. Busca WhisPaste en la lista y actívalo.\n¿No aparece en la lista? Arrastra el icono de la app o haz clic en «+».';

  @override
  String get onboardingPasteTestTitle => 'Prueba Auto-Paste';

  @override
  String get onboardingPasteTestSubtitle =>
      'Haz clic en el botón. El texto de demostración debería aparecer en el campo de abajo.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste escribe por ti.';

  @override
  String get onboardingPasteTestSuccess =>
      '¡Auto-Paste funciona! Haz clic en Siguiente para continuar.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'No se detectó ningún campo de texto. Haz clic en el campo de abajo e inténtalo de nuevo.';

  @override
  String get onboardingPasteTestFailure =>
      'La prueba falló. Prueba a reiniciar la app o continúa sin probar.';

  @override
  String get onboardingPasteTestSkip => 'Continuar sin probar';

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
  String get settingsOverlayModeFloating =>
      'Ventana flotante (siempre visible)';

  @override
  String get settingsOverlayModeOff => 'Desactivado';

  @override
  String get settingsOverlayStartPosition => 'Posición inicial del overlay';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Dónde aparece el overlay flotante al empezar a grabar';

  @override
  String get settingsOverlayStartTopCenter => 'Centro superior';

  @override
  String get settingsOverlayStartBottomCenter => 'Centro inferior';

  @override
  String get settingsOverlayStartLastPosition => 'Recordar la última posición';

  @override
  String get settingsShowFloatingButton => 'Botón flotante de grabación';

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
    return '~$count / $budget tokens';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Las entradas largas pueden acortarse automáticamente: solo se usan aproximadamente los primeros $budget tokens.';
  }

  @override
  String get settingsPunctuationPriming => 'Preparación de la puntuación';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Orienta a Whisper hacia una salida con puntuación cuando no hay vocabulario personalizado. No afecta a la velocidad.';

  @override
  String get settingsVadEnabled => 'Recortar el silencio final';

  @override
  String get settingsVadEnabledSubtitle =>
      'Elimina el silencio o el ruido largo al final de la grabación antes de que Whisper la procese, para que no invente una frase de cierre (por ejemplo, alucinaciones tipo «Gracias por ver el vídeo»). Coste insignificante; desactívalo si prefieres la salida sin procesar de Whisper.';

  @override
  String get settingsStripPunctuation => 'Quitar la puntuación';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Elimina puntos, comas y otros signos de puntuación de cada transcripción antes de guardarla o pegarla. Funciona igual con todos los motores y proveedores, no solo con Whisper.';

  @override
  String get settingsNumericOnlyMode => 'Solo números';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Convierte los números dictados (en alemán e inglés) en cifras, p. ej. «five point two» pasa a ser «5.2». Deja la transcripción intacta si no se puede convertir por completo.';

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
  String get settingsAppLanguage => 'Idioma de la app';

  @override
  String get settingsSttModels => 'Modelos de reconocimiento de voz';

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
  String get settingsFactoryReset => 'Restablecer de fábrica';

  @override
  String get settingsFactoryResetTitle => 'Restablecer de fábrica';

  @override
  String get settingsFactoryResetMessage =>
      'Se eliminarán DEFINITIVAMENTE todos los datos: historial de grabaciones, etiquetas, reemplazos, modelos descargados, registros y ajustes. La app volverá a su estado inicial.\n\nEsta acción no se puede deshacer.';

  @override
  String get settingsFactoryResetConfirm => 'Eliminar todo';

  @override
  String get settingsFactoryResetSuccess =>
      'La app se ha restablecido por completo';

  @override
  String get settingsFactoryResetProgressTitle => 'Restableciendo WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Deteniendo el servicio de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Eliminando los modelos de voz…';

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
  String get settingsFactoryResetFailedMessage =>
      'El restablecimiento de fábrica no se completó. Reinicia la app.';

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
    return 'Esto sustituye tus ajustes actuales (incluidos la interfaz, la configuración del reconocimiento de voz, el comportamiento, los reemplazos de texto y los snippets) por el contenido de $path. Tus claves API no se modifican.';
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
      'Groq STT se ha eliminado. El proveedor se ha restablecido a En el dispositivo.';

  @override
  String get tccResetAfterUpdateToast =>
      'macOS restableció tu permiso de Auto-Paste durante la actualización.';

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
  String get actionCancel => 'Cancelar';

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
  String get onboardingWelcome => 'Dilo una vez. Pégalo donde quieras.';

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
  String get analyticsTimeSaved => 'Tiempo ahorrado';

  @override
  String get analyticsAvgLatency => 'Velocidad media';

  @override
  String get analyticsRecordingActivity => 'Actividad de grabación';

  @override
  String get analyticsLast7Days => 'Últimos 7 días';

  @override
  String get analyticsModelUsage => 'Uso de modelos';

  @override
  String get analyticsDurationDistribution => 'Distribución de duración';

  @override
  String get analyticsCostSavings => 'Coste y ahorro';

  @override
  String get analyticsLocalSavings => 'Ahorro local';

  @override
  String get analyticsCloudCost => 'Coste en la nube';

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
  String analyticsDurationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
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
  String get replacementsRemoveTrigger => 'Quitar frase de activación';

  @override
  String get replacementsReplacementLabel => 'Texto de reemplazo';

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
      'Mientras grabas una nota en el historial, di «correct: …» (o «korrektur: …») seguido del texto corregido para sobrescribirla. Si corriges lo mismo dos veces, WhisPaste lo ofrece aquí como reemplazo automático.';

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
      'Lo parecida que debe sonar una frase dictada a una frase de activación para contar como coincidencia. Estricta solo detecta formulaciones casi idénticas, así que casi nunca reemplaza algo por error, pero una frase mal pronunciada puede pasar sin detectarse. Estándar es un valor equilibrado para el dictado diario. Flexible también detecta pronunciaciones o formulaciones bastante distintas, con más riesgo de reemplazar algo que no querías.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Las frases de activación de menos de $minLength caracteres no pueden usar la coincidencia similar: darían demasiados falsos positivos.';
  }

  @override
  String get snippetsSearch => 'Buscar snippets…';

  @override
  String get snippetsSearchFieldLabel => 'Buscar snippets';

  @override
  String get snippetsAdd => 'Añadir';

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
      'Abre el selector de snippets mientras dictas para insertar este texto.';

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
      'Todavía no aparecen todos los campos en la plantilla: su texto dictado no se usaría.';

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
      'La palabra de activación está definida, pero aún no hay snippets: dictarla inserta la palabra como texto normal hasta que añadas el primero.';

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
  String get aboutTagline => 'Voz a texto, al instante.';

  @override
  String get aboutWhatsNew => 'Novedades';

  @override
  String get aboutGitHub => 'GitHub';

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
      'Reconocimiento de voz local optimizado para la velocidad en CPU convencionales (~25 idiomas).';

  @override
  String get aboutPrivacyFirst => 'Privacidad ante todo';

  @override
  String get aboutPrivacyFirstDesc =>
      'Reconocimiento de voz local por defecto: tu voz no sale de tu dispositivo salvo que elijas un proveedor en la nube.';

  @override
  String get aboutPrivacy => 'Privacidad y datos';

  @override
  String get aboutPrivacyLocal =>
      'Todas las transcripciones y el historial se guardan localmente en tu dispositivo, nunca en servidores externos.';

  @override
  String get aboutPrivacyCloud =>
      'Los proveedores en la nube (OpenAI, Deepgram) solo reciben audio cuando los usas activamente. Se aplican sus políticas de privacidad.';

  @override
  String get aboutPrivacyNoTracking =>
      'Las estadísticas de uso son anónimas y cumplen el RGPD (servidor en la UE); se pueden desactivar en Ajustes → Privacidad. No hay cuentas de usuario. Las comprobaciones de actualizaciones contactan con GitHub (solo versión e IP).';

  @override
  String get aboutKeyboardShortcuts => 'Atajos de teclado';

  @override
  String get aboutShortcutRecord => 'Iniciar / detener grabación';

  @override
  String get aboutLinks => 'Enlaces';

  @override
  String get aboutWebsite => 'Sitio web';

  @override
  String get aboutGitHubRepo => 'Repositorio en GitHub';

  @override
  String get aboutFollowOnX => 'Síguenos en X';

  @override
  String get aboutMitLicense => 'Licencia MIT';

  @override
  String get aboutViewOnGitHub => 'Ver en GitHub';

  @override
  String get aboutPrivacyPolicy => 'Política de privacidad';

  @override
  String get aboutSystemInfo => 'Información del sistema';

  @override
  String get aboutSystemInfoDesc =>
      'Copia un resumen compacto de diagnóstico para informar de errores.';

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
  String get feedbackCategoryBug => 'Informe de error';

  @override
  String get feedbackCategoryFeature => 'Idea de función';

  @override
  String get feedbackCategoryGeneral => 'General';

  @override
  String get feedbackCategoryAiQuality => 'Calidad de la IA';

  @override
  String get feedbackRatingLabel => '¿Qué tal te va con WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Cuéntanos más';

  @override
  String get feedbackPlaceholderBug => 'Describe qué pasó y qué esperabas…';

  @override
  String get feedbackPlaceholderFeature => '¿Qué te gustaría ver en WhisPaste?';

  @override
  String get feedbackPlaceholderAi =>
      '¿Qué tal fue la calidad de la transcripción?';

  @override
  String get feedbackPlaceholderGeneral => 'Comparte tus ideas…';

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
  String get sttStatusStandby => 'En espera';

  @override
  String get sttStatusStarting => 'Iniciando…';

  @override
  String get sttStatusReady => 'Listo';

  @override
  String get sttStatusError => 'Error';

  @override
  String get statusBarSttTooltip => 'Servicio de voz y estado actual';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Motor de transcripción: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'La utilización real de la GPU no se puede medir en todas las plataformas sin privilegios elevados; el porcentaje mostrado refleja la actividad de CPU de este proceso.';

  @override
  String get statusBarRecording => 'Grabando…';

  @override
  String get statusBarTranscribing => 'Transcribiendo…';

  @override
  String get statusBarRefining => 'Refinando…';

  @override
  String get statusBarDone => 'Hecho';

  @override
  String get statusBarHotkeyTooltip => 'Atajo global: haz clic para configurar';

  @override
  String get statusBarAutoPasteOffHint =>
      'Auto-Paste desactivado; actívalo en Ajustes';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'Auto-Paste está desactivado. Haz clic para abrir Ajustes.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Descartar';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'API: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'API: error';

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
  String get modelServerReady => 'Servicio de voz listo';

  @override
  String get modelServerMissing => 'Servicio de voz no instalado';

  @override
  String get modelServerWhisper => 'Servicio de voz local';

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
  String get modelDownloadingEngine => 'Preparando el servicio de voz…';

  @override
  String get modelVerifying => 'Verificando…';

  @override
  String get modelExtracting => 'Extrayendo…';

  @override
  String get modelDeleteConfirm => '¿Eliminar este modelo?';

  @override
  String get modelDeleteConfirmMessage =>
      'El archivo del modelo se eliminará de forma permanente. Puedes volver a descargarlo en cualquier momento.';

  @override
  String get qualityTierCompactLabel => 'Rápido y compacto';

  @override
  String get qualityTierCompactDesc =>
      'Resultados rápidos y descarga pequeña. Ideal para notas breves y mensajes rápidos.';

  @override
  String get qualityTierBalancedLabel => 'Equilibrado';

  @override
  String get qualityTierBalancedDesc =>
      'Preciso y fiable para grabar a diario. Funciona en la mayoría de los dispositivos.';

  @override
  String get qualityTierPremiumLabel => 'Máxima calidad';

  @override
  String get qualityTierPremiumDesc =>
      'Máxima precisión para grabaciones largas y contenido complejo. Necesita una GPU potente.';

  @override
  String get qualityTierRecommended => 'Recomendado para tu dispositivo';

  @override
  String qualityTierDownloadSize(String size) {
    return 'Descarga de $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Descargar modelo';

  @override
  String get qualityTierChooseDifferent => 'Elegir otro nivel de calidad';

  @override
  String get qualityTierActive => 'Activo';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Máxima calidad, tarda ~${ratio}x más en procesarse';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Máxima calidad, ~${ratio}x más lento que el nivel compacto';
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
  String get qualityTierActionOverride => 'Usar igualmente';

  @override
  String get qualityTierActionOverrideHint =>
      'Usa este nivel de calidad a pesar de la advertencia';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

  @override
  String get settingsQualityBasic => 'Básica';

  @override
  String get settingsQualityBalanced => 'Equilibrada';

  @override
  String get settingsQualityHigh => 'Alta calidad';

  @override
  String get settingsQualityBest => 'Mejor calidad';

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
  String get settingsAdvancedModelManagement => 'Ajustes avanzados del modelo';

  @override
  String get infoEngineDownloading =>
      'El servicio de voz se está preparando. Espera un momento.';

  @override
  String get infoModelMissing =>
      'Descarga primero un modelo de voz en los ajustes.';

  @override
  String get infoPipelineBusy =>
      'WhisPaste todavía está procesando la grabación anterior.';

  @override
  String get infoSnippetPickerEmpty =>
      'Palabra de activación reconocida, pero aún no tienes snippets: el texto se ha insertado como de costumbre.';

  @override
  String get infoSnippetPickerEmptyAction => 'Abrir snippets';

  @override
  String get oomRecoveryTitle => 'Error al grabar: falta de memoria de la GPU';

  @override
  String get oomRecoveryMessage =>
      'La memoria de tu GPU se ha agotado. Elige cómo seguir:';

  @override
  String get oomRecoveryTrySmaller => 'Probar modelo más pequeño';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Cambia a $model y repite la grabación';
  }

  @override
  String get oomRecoverySwitchCloud => 'Cambiar a la nube';

  @override
  String get oomRecoverySwitchCloudHint =>
      'Usar el reconocimiento de voz en la nube';

  @override
  String get oomRecoveryCancel => 'Cancelar';

  @override
  String get oomRecoveryPermanentTitle =>
      'Reconocimiento de voz local no disponible';

  @override
  String get oomRecoveryPermanentMessage =>
      'Todos los modelos locales han fallado por los límites de memoria de la GPU. Cambia al reconocimiento de voz en la nube en los ajustes.';

  @override
  String get oomRecoveryPermanentCloud => 'Abrir ajustes';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Cambiando a $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Cambiando al reconocimiento de voz en la nube…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'El modelo $model también ha fallado. Probando la siguiente opción…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'Calidad reducida: la memoria de tu GPU se ha agotado. Se ha cambiado a un modelo más ligero.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'La memoria de tu GPU se ha agotado. Se ha cambiado al modo CPU para mayor fiabilidad.';

  @override
  String get errorSttServerConnectionLost =>
      'El servicio de voz se ha detenido de forma inesperada. Inténtalo de nuevo.';

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
  String get errorOnboardingNotCompleted =>
      'Completa primero el asistente de configuración.';

  @override
  String get errorSttModelNotFound =>
      'No se encuentra el modelo de voz. Descárgalo en los ajustes.';

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
  String get errorSttServerFailed => 'El servicio de voz no se pudo iniciar';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'El modelo de voz no es compatible con el motor instalado. Vuelve a descargarlo en los ajustes.';

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
      'El servicio de voz ha fallado tanto en GPU como en CPU. Reinicia la app o vuelve a descargar el modelo.';

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
      'El servicio de voz todavía se está iniciando. Inténtalo de nuevo en un momento.';

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
  String get modelDeleteInUse =>
      'El archivo del modelo está en uso por otro programa y no se pudo borrar. Ciérralo e inténtalo de nuevo.';

  @override
  String get statusSttLoading => 'Cargando modelo…';

  @override
  String get statusSttReady => 'Modelo listo';

  @override
  String get historyDuplicate => 'Duplicar';

  @override
  String get historyDuplicated => 'Entrada duplicada';

  @override
  String get historyViewRaw => 'Original';

  @override
  String get historyViewEdited => 'Editada';

  @override
  String get historyApplySmartModePreset => 'Aplicar preset de Smart Mode';

  @override
  String get historySmartModeApplied => 'Smart Mode aplicado';

  @override
  String get historySmartModeFailedModelMissing =>
      'Modelo de Smart Mode no descargado';

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
  String get tagManageEmpty => 'Todavía no hay etiquetas creadas.';

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
  String get settingsKeyboardShortcut => 'Atajo de teclado';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Atajo global para iniciar y detener la grabación';

  @override
  String get settingsHotkeyEnabled => 'Activar atajo global';

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
  String get settingsHotkeyRecorderModifierHint =>
      'Vale cualquier combinación de modificadores, p. ej. Alt+Espacio, Ctrl+Alt+V o Ctrl+Alt+Shift+R';

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
  String get settingsQuickNoteHotkeyEnabled => 'Atajo de nota rápida';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'El texto dictado se añade a la nota marcada como nota rápida. Esa nota la eliges en el área de Notas.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Combinación';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Esta combinación ya se usa para «$action». Elige otra.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'No se pudo registrar esta combinación: el atajo de nota rápida no está activo. Elige otra combinación.';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Selector de snippets';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Atajo del selector de snippets';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Abre el selector de snippets al instante: sin grabar y sin la palabra de activación hablada.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Combinación';

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
  String get settingsErrorReporting => 'Informes de errores';

  @override
  String get settingsErrorReportingSubtitle =>
      'Envía informes de fallos y errores con un hash del ID del dispositivo; nunca tu audio ni tu texto';

  @override
  String get settingsErrorReportingRestartHint =>
      'Se aplica al reiniciar WhisPaste.';

  @override
  String get settingsAutoPasteDelay => 'Retraso de Auto-Paste';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Tiempo de espera antes de pegar en la ventana activa';

  @override
  String get settingsAutoPasteBlocklist => 'Lista de bloqueo de Auto-Paste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Identificadores de apps separados por comas en los que Auto-Paste está desactivado';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'p. ej. com.apple.Terminal, com.1password';

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
  String get onboardingBack => 'Atrás';

  @override
  String get onboardingPrivacyTitle => 'Ayuda a mejorar WhisPaste';

  @override
  String get onboardingPrivacyHint =>
      'El audio y el texto se quedan en tu equipo. Las estadísticas de uso anónimas se envían a un servidor propio en la UE, y los informes de fallos a Sentry (región UE), conforme al RGPD.';

  @override
  String get onboardingPrivacyToggle =>
      'Compartir estadísticas de uso anónimas';

  @override
  String get onboardingPrivacyToggleHint =>
      'Activado por defecto; desactívalo cuando quieras';

  @override
  String get onboardingPrivacyCrashToggle =>
      'Enviar informes de fallos anónimos';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'Ayuda a corregir errores; activado por defecto, desactívalo cuando quieras';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'Apariencia';

  @override
  String get onboardingAppearancePageSubtitle =>
      'Cómo se inicia la app y cómo se ve la superposición de grabación.';

  @override
  String get onboardingBeat1Title => 'Pulsa el atajo, habla y listo';

  @override
  String get onboardingBeat1Caption =>
      'La grabación empieza al instante: tus palabras aparecen como texto justo en el cursor.';

  @override
  String get onboardingBeat2Title => 'Funciona en local, en tu hardware';

  @override
  String get onboardingBeat2Caption =>
      'La transcripción se hace en tu dispositivo, sin necesidad de internet.';

  @override
  String get onboardingBeat3Title => 'En cualquier lugar donde escribas';

  @override
  String get onboardingBeat3Caption =>
      'Navegador, correo, editor: WhisPaste funciona en todo el sistema.';

  @override
  String get onboardingMicChipReady => 'Micrófono listo';

  @override
  String get onboardingMicChipPending => 'Acceso al micrófono pendiente';

  @override
  String get onboardingMicChipAction => 'Micrófono: hay que actuar';

  @override
  String get onboardingModelTitle => 'Configura el reconocimiento de voz';

  @override
  String get onboardingModelSubtitle =>
      'Descarga el modelo de voz para grabar sin conexión. Tu voz nunca sale de tu dispositivo.';

  @override
  String get onboardingModelRecommended => 'Recomendado';

  @override
  String get onboardingModelChangeLater =>
      'Puedes ajustar la calidad más tarde en Ajustes';

  @override
  String get onboardingModelDownloading => 'Descargando…';

  @override
  String get onboardingModelReady => 'Modelo listo';

  @override
  String get onboardingModelGpuCpuFallback =>
      'La aceleración optimizada por GPU no está disponible; la app usará la CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Rápido y europeo';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'La forma más rápida de pasar de voz a texto en unos 25 idiomas europeos, incluido el alemán. Funciona bien en cualquier hardware, con o sin GPU.';

  @override
  String get onboardingModelEngineWhisperLabel => '99 idiomas';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'La mayor cobertura de idiomas, además de vocabulario personalizado y ajuste de puntuación para nombres, siglas y jerga.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Todavía no admite el idioma seleccionado';

  @override
  String get onboardingTestRecordingTitle => 'Pruébalo';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Pulsa el botón y di una frase. El texto aparece en el campo de prueba. Tu atajo también sirve.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Tu atajo';

  @override
  String get onboardingTestRecordingStartCta => 'Empezar a grabar';

  @override
  String get onboardingTestRecordingStopCta => 'Detener grabación';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'Haz una grabación de prueba para continuar.';

  @override
  String get onboardingTestRecordingMicBypassCta => 'Continuar sin micrófono';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'Sin un micrófono que funcione, WhisPaste todavía no puede empezar a grabar. Puedes solucionarlo cuando quieras desde el estado del micrófono en esta página o en Ajustes.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'Tu texto hablado aparecerá aquí…';

  @override
  String get onboardingTestRecordingInProgress =>
      'Grabando: habla con normalidad. Pulsa de nuevo para detener.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      '¡Listo! Así funciona en cualquier app.';

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
  String get onboardingReadyTitle => '¡Todo listo!';

  @override
  String get onboardingReadySubtitle => 'Así se usa WhisPaste';

  @override
  String get onboardingReadyStep1 => 'Pulsa el atajo para empezar a grabar';

  @override
  String get onboardingReadyStep2 => 'Pulsa de nuevo para parar y transcribir';

  @override
  String get onboardingReadyStep3AutoPaste =>
      'El texto va directamente a la app activa';

  @override
  String get onboardingReadyStep3CopyOnly =>
      'El texto está en tu portapapeles; pulsa ⌘V / Ctrl+V para pegarlo';

  @override
  String get onboardingReadyContextCarryoverHint =>
      'WhisPaste mantiene el contexto de tu grabación anterior durante hasta diez minutos. Haz una pausa breve antes de cambiar de golpe a un tema no relacionado, para que el siguiente resultado no se desvíe.';

  @override
  String get onboardingReadyAutostartToggle =>
      'Abrir WhisPaste al iniciar sesión';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Desactivado por defecto; actívalo cuando quieras en Ajustes';

  @override
  String get onboardingTriggerTitle => '¿Cómo quieres empezar a grabar?';

  @override
  String get onboardingTriggerSubtitle =>
      'Configura tu atajo y elige cómo inicia la grabación.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Atajo actual';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Atajo ya en uso';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Parece que otra app usa tu atajo. Graba una nueva combinación abajo para continuar.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Vuelve a la página del atajo y graba allí una nueva combinación.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Mantén pulsado el atajo y habla; suéltalo para terminar';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Pulsa una vez para empezar y otra para terminar';

  @override
  String get onboardingTriggerSystemWideHint =>
      'Funciona en todo el sistema, no solo dentro de WhisPaste.';

  @override
  String get onboardingStartUsing => '¡Vamos!';

  @override
  String get onboardingReviewExit => 'Cerrar introducción';

  @override
  String get onboardingReviewDone => 'Hecho';

  @override
  String get onboardingReviewEntry => 'Introducción';

  @override
  String get onboardingReviewSubtitle =>
      'Repasa los cinco pasos de configuración cuando quieras; no cambia nada salvo que lo modifiques tú.';

  @override
  String get onboardingReviewLabel => 'Repasar la introducción';

  @override
  String get onboardingReviewAction => 'Abrir';

  @override
  String get onboardingRevisionNoticeTitle =>
      'WhisPaste se ha actualizado; tus ajustes no han cambiado.';

  @override
  String get onboardingRevisionExit => 'Salir de la introducción';

  @override
  String get onboardingRevisionExitConfirmTitle => '¿Salir de la introducción?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Este recorrido de la actualización solo se muestra una vez, así que los pasos que saltes ahora no se configurarán por ti. Puedes volver a abrir los mismos pasos cuando quieras en Ajustes → Introducción, y cada ajuste que cubren tiene también su sitio en Ajustes. Lo que ya hayas configurado no se modifica.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Salir';

  @override
  String get overlayRecording => 'Grabando';

  @override
  String get overlayTranscribing => 'Transcribiendo…';

  @override
  String get overlayRefining => 'Refinando…';

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
  String get traySettings => 'Ajustes';

  @override
  String get trayQuit => 'Salir';

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
      'Nota de voz: di «tag: …» para añadir una etiqueta, o «correct: …» para reescribir esta transcripción';

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
  String get settingsOverlayStyle => 'Estilo de superposición';

  @override
  String get settingsOverlayStyleSubtitle =>
      'Elige entre un aspecto de cristal o uno sólido y opaco';

  @override
  String get settingsOverlayStyleGlass => 'Cristal';

  @override
  String get settingsOverlayStyleSolid => 'Sólido';

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
  String get buttonContextShowHistory => 'Mostrar historial';

  @override
  String get buttonContextSettings => 'Ajustes';

  @override
  String get buttonContextQuit => 'Salir de WhisPaste';

  @override
  String get settingsHistory => 'Historial';

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
  String get settingsHistoryHideOnOpen => 'Ocultar historial al abrir';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Muestra un botón «Mostrar historial» en lugar de tus transcripciones cada vez que WhisPaste se inicia o se vuelve a abrir su ventana';

  @override
  String get historyPinGateTitle => 'El historial está bloqueado';

  @override
  String get historyPinGateHint =>
      'Introduce tu PIN para mostrar tus transcripciones.';

  @override
  String get historyPinUnlock => 'Desbloquear';

  @override
  String get historyPinDialogTitle => 'Introduce el PIN';

  @override
  String get historyPinDialogSubtitle =>
      'Tu historial está protegido con un PIN.';

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
  String get historyPinForgotConfirmTitle =>
      '¿Eliminar el historial y quitar el PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Un PIN olvidado no se puede recuperar. Para restablecerlo, se elimina de forma permanente todo el historial, incluidos el archivo, la papelera y las grabaciones guardadas. Los ajustes, las notas, los snippets y los reemplazos se conservan.';

  @override
  String get historyPinForgotConfirmAction => 'Eliminar historial';

  @override
  String get historyPinSetTitle => 'Definir PIN';

  @override
  String get historyPinSetSubtitle =>
      'De 4 a 8 dígitos. Evita que otros vean tu historial en este ordenador con facilidad; no lo cifra.';

  @override
  String get historyPinInvalid => 'Usa entre 4 y 8 dígitos.';

  @override
  String get historyPinMismatch => 'Los PIN no coinciden.';

  @override
  String get settingsHistoryPin => 'Protección con PIN';

  @override
  String get settingsHistoryPinSubtitle =>
      'Requiere un PIN para mostrar el historial, también en el panel lateral, el menú del botón flotante y la API de automatización.';

  @override
  String get settingsHistoryPinChange => 'Cambiar';

  @override
  String get settingsHistoryPinRemove => 'Quitar';

  @override
  String get settingsHistoryAutoLock => 'Bloquear automáticamente';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Vuelve a ocultar el historial tras este tiempo de inactividad.';

  @override
  String get settingsHistoryAutoLockNever => 'Nunca';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Tras $minutes min';
  }

  @override
  String get settingsFloatingButtonSection => 'Botón flotante';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Botón de grabación siempre visible sobre otras ventanas, para un acceso rápido';

  @override
  String get settingsSttIdleTimeout => 'Tiempo de inactividad del motor';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Cuánto tiempo permanece cargado el servicio de voz tras su último uso';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Mantener activo';

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
  String get reviewPromptTitle => '¿Te gusta WhisPaste?';

  @override
  String get reviewPromptBody =>
      'Tu valoración ayuda a otros a descubrirlo y mantiene el desarrollo en marcha.';

  @override
  String get reviewPromptYes => '¡Me encanta!';

  @override
  String get reviewPromptNotNow => 'Ahora no';

  @override
  String get reviewPromptNever => 'No volver a preguntar';

  @override
  String get reviewPromptStarGitHub => '⭐ Dar una estrella en GitHub';

  @override
  String get reviewPromptRateStore => '★ Valorar en la tienda';

  @override
  String get reviewPromptGateBody =>
      'Solo una pregunta rápida para nosotros; esto no es una valoración de la tienda.';

  @override
  String get reviewPromptGateYes => 'Sí, me gusta';

  @override
  String get reviewPromptGateNo => 'No mucho';

  @override
  String get reviewSupportEntry => 'Valora y apoya WhisPaste';

  @override
  String get reviewSupportLabel => 'Tu valoración';

  @override
  String get reviewSupportSubtitle =>
      'Tu valoración ayuda a otros a encontrar WhisPaste y apoya el proyecto.';

  @override
  String get reviewSupportAction => 'Valorar';

  @override
  String get ideasBoardLabel => 'Ideas y peticiones de funciones';

  @override
  String get ideasBoardAction => 'Ver el tablero';

  @override
  String get feedbackIdeasLink => 'Sugerir y votar ideas';

  @override
  String get insufficientRamTitle => 'Memoria insuficiente';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'WhisPaste necesita al menos $requiredGb GB de RAM para funcionar. Tu sistema tiene $detectedGbString GB.\n\nCon menos memoria, el motor de transcripción con IA puede no cargarse o fallar a mitad de sesión.';
  }

  @override
  String get insufficientRamQuit => 'Salir de WhisPaste';

  @override
  String get insufficientRamLearnMore => 'Requisitos del sistema';

  @override
  String get insufficientRamSystemCheck => 'Comprobación del sistema';

  @override
  String get insufficientRamYourSystem => 'Tu sistema';

  @override
  String get insufficientRamRequired => 'Necesario';

  @override
  String get hotkeyRegistrationFailed =>
      'No se pudo registrar el atajo; vuelve a asignarlo en Ajustes.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'No se pudo registrar el atajo; se usa Ctrl+Shift+Space como alternativa. Vuelve a asignarlo en Ajustes.';

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Este atajo está reservado por $platform ($note) y puede no funcionar.';
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
      'El servicio de voz no puede iniciarse. Reinicia la app o vuelve a cargar el modelo de voz.';

  @override
  String get recoveryExhaustedAction => 'Abrir Ajustes';

  @override
  String get recoveryVcRuntimeToast =>
      'El servicio de voz no puede iniciarse: falta un componente de Windows (Microsoft Visual C++). Instala Visual C++ Redistributable (x64) y reinicia WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Instalar';

  @override
  String get modelAbiInfoToast =>
      'Recargando el modelo de voz, espera un momento.';

  @override
  String get recoveryGpuDisabledToast =>
      'WhisPaste funciona ahora sin aceleración por GPU debido a un problema en el último inicio. El dictado sigue funcionando como siempre.';

  @override
  String get serverDownloadFailedToast =>
      'No se pudo descargar el servicio de voz. ¿Compruebas tu conexión a internet?';

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
  String get factoryResetFailedToast =>
      'El restablecimiento de fábrica no se completó. ¿Reiniciar la app?';

  @override
  String get factoryResetFailedAction => 'Salir de la app';

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
      'Define si el servicio de voz usa la GPU o la CPU para el reconocimiento local';

  @override
  String get settingsGpuAccelerationAuto => 'Automática (recomendada)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (forzada)';

  @override
  String get settingsGpuAccelerationDisabled => 'Solo CPU';

  @override
  String get settingsSttEngine => 'Motor';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper cubre 99 idiomas y todos los backends de GPU; Parakeet es mucho más rápido en equipos solo con CPU, pero cubre unos 25 idiomas y todavía no tiene backend de GPU';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet =>
      'Parakeet (el más rápido, unos 25 idiomas)';

  @override
  String get parakeetModelTitle => 'Modelo Parakeet TDT';

  @override
  String get parakeetModelSubtitle =>
      'Descarga única (unos 640 MB); después funciona totalmente sin conexión';

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
  String get settingsShareUsageStats =>
      'Compartir estadísticas de uso anónimas';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Sin cookies, con un ID aleatorio por sesión y un seudónimo que cambia cada semana; nos ayuda a entender cómo se usa WhisPaste';

  @override
  String get settingsRetainRecentAudio => 'Conservar grabaciones recientes';

  @override
  String get settingsRetainRecentAudioSubtitle =>
      'Guarda en este dispositivo el audio de tus últimos 20 dictados para depurar o recuperar una transcripción anterior; las grabaciones más antiguas se eliminan automáticamente';

  @override
  String get storeThankYouTitle => '¡Gracias por tu apoyo!';

  @override
  String get storeThankYouBody =>
      'Nos alegra mucho que estés aquí. Si WhisPaste te facilita un poco el día, una valoración breve significa mucho para nosotros.';

  @override
  String get storeThankYouCtaStore => '★ Valorar en la tienda';

  @override
  String get storeThankYouCtaGitHub => '⭐ Dar una estrella en GitHub';

  @override
  String get storeThankYouDismiss => 'Cerrar';

  @override
  String get featureSpotlightHeading => 'Novedades en WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Entendido';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Selector de snippets';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Guarda bloques de texto reutilizables e insértalos donde quieras con un atajo o con una palabra hablada, sin tener que volver a escribirlos.';

  @override
  String get featureSpotlightSidePanelTitle => 'Panel lateral del portapapeles';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Pasa el cursor por el borde de la pantalla para abrir tu historial reciente del portapapeles y arrastra cualquier elemento directamente a tu documento.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle =>
      'Snippets interactivos';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'Snippets con huecos: WhisPaste te guía por cada campo; dicta, pulsa Intro para pasar al siguiente y el texto terminado se pega de una vez.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Limpia, acorta o traduce tu dictado antes de pegarlo; todo se procesa en el dispositivo, con su propio atajo, preset e idioma de destino.';

  @override
  String get featureSpotlightHistoryPinTitle =>
      'Protege tu historial con un PIN';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'Mantén tus transcripciones privadas tras un PIN, también en el panel lateral y en el menú del botón flotante, con bloqueo automático opcional tras un periodo de inactividad. Ajustes → Historial.';

  @override
  String get featureSpotlightEditSelectionTitle =>
      'Edita el texto seleccionado con la voz';

  @override
  String get featureSpotlightEditSelectionDescription =>
      'Selecciona texto en cualquier app, pulsa el atajo «Editar selección» y di qué debe cambiar, o simplemente «más corto», «mejorar» o «traducir». Usa tu motor de Smart Mode. Desactivado por defecto: actívalo en Ajustes → Smart Mode.';

  @override
  String get featureSpotlightChangelogLink =>
      'Ver el registro de cambios completo';

  @override
  String get featureSpotlightReviewLabel => 'Revisar las nuevas funciones';

  @override
  String get featureSpotlightReviewAction => 'Mostrar';

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
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Limpieza, acortado y traducción local del texto tras el dictado';

  @override
  String get smartModeStandardPreset => 'Preset estándar';

  @override
  String get smartModePresetOff => 'Desactivado';

  @override
  String get smartModePresetOffDescription =>
      'Sin posprocesado automático: el texto dictado se usa exactamente como se transcribió.';

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
      'Traduce el texto dictado al idioma de destino que se indica abajo.';

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
  String get smartModeDownloadComplete =>
      'Modelo de Smart Mode listo para usar';

  @override
  String get smartModeRamWarningTitle => 'Memoria limitada detectada';

  @override
  String get smartModeRamWarningBody =>
      'El modelo local de Smart Mode funciona mejor con 8 GB de RAM o más. Puede que siga funcionando, pero podría ir lento o fallar en este equipo. ¿Descargar de todos modos?';

  @override
  String get smartModeRamWarningContinue => 'Descargar de todos modos';

  @override
  String get smartModeRamWarningCancel => 'Cancelar';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Se ejecuta totalmente en el dispositivo. Mientras está activo, usa unos 4–5 GB de RAM además del espacio en disco; la memoria se comparte con el modelo de transcripción, así que el uso total depende del modelo STT que tengas cargado.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Ejemplo: un dictado típico de 50 palabras tarda entre 1 y 6 segundos en procesarse, según el hardware del dispositivo.';

  @override
  String get smartModeLocalUnavailable =>
      'Smart Mode en el dispositivo no está incluido en esta versión. Cambia a OpenAI o instala una versión oficial de WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Atajo de Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Inicia una grabación con un preset fijo, independiente del preset estándar de arriba. Admite push-to-talk, igual que el atajo principal.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Preset';

  @override
  String get settingsSmartModeCurrentHotkey => 'Combinación';

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
  String get smartModeOnboardingHintBody =>
      'Smart Mode puede limpiar, acortar o traducir tu texto dictado de forma automática, totalmente en el dispositivo. Descarga ahora el modelo local o configúralo más tarde en Ajustes.';

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Dictado original';

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
  String get smartModeOnboardingHintSkipCta => 'Omitir';

  @override
  String get smartModeUsageHintTitle =>
      'Prueba Smart Mode en tu próximo dictado';

  @override
  String get smartModeUsageHintBody =>
      'Smart Mode puede limpiar, acortar o traducir un texto como este de forma automática, directamente en tu dispositivo. Esto es lo que acabas de dictar:';

  @override
  String get smartModeUsageHintCta => 'Configurar';

  @override
  String get smartModeUsageHintDismiss => 'Ahora no';

  @override
  String get settingsAutomationApi => 'API de automatización local';

  @override
  String get settingsAutomationApiSubtitle =>
      'Lanza dictados desde tus propios scripts a través de una API HTTP solo local';

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
  String get settingsSelectionEditHotkeyEnabled =>
      'Atajo de edición de selección';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Selecciona texto en cualquier app, pulsa este atajo y di qué cambiar, o simplemente «más corto», «mejorar» o «traducir». El resultado reemplaza la selección; deshacer en la app restaura el original. Usa el motor de Smart Mode configurado arriba.';

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
      'Configura primero Smart Mode (descarga el modelo local o añade una clave de OpenAI) para editar selecciones';

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
  String get errorSelectionEditPasteFailed =>
      'No se pudo reemplazar la selección; tu texto no ha cambiado';

  @override
  String get settingsCudaPackTitle => 'Aceleración NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Dictado más rápido en tarjetas GeForce RTX y GTX 16. Descarga única de $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Instalado. Si el controlador gráfico es demasiado antiguo, WhisPaste sigue usando Vulkan.';

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
  String get recoveryCudaDisabledToast =>
      'La aceleración CUDA se desactivó por un problema en el último inicio. WhisPaste usa ahora Vulkan y el dictado funciona como siempre.';
}
