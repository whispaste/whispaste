// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class L10nPt extends L10n {
  L10nPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'WhisPaste';

  @override
  String get navHistory => 'Gravações';

  @override
  String get navNotes => 'Notas';

  @override
  String get navSettings => 'Configurações';

  @override
  String get navReplacements => 'Dicionário';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navAnalytics => 'Estatísticas';

  @override
  String get navHelp => 'Ajuda';

  @override
  String get actionOpen => 'Abrir';

  @override
  String actionOpenNamed(String name) {
    return 'Abrir $name';
  }

  @override
  String get helpTabManual => 'Manual';

  @override
  String get helpTabIntro => 'Introdução';

  @override
  String get helpTabSupport => 'Apoio';

  @override
  String get helpTabDiagnostics => 'Diagnóstico';

  @override
  String get manualSearchHint => 'Pesquisar no manual';

  @override
  String get manualSearchEmpty => 'Nenhum capítulo corresponde à pesquisa.';

  @override
  String manualSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos encontrados',
      one: '1 capítulo encontrado',
      zero: 'Nenhum capítulo encontrado',
    );
    return '$_temp0';
  }

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'Gravações';

  @override
  String get pageSettingsTitle => 'Configurações';

  @override
  String get pageReplacementsTitle => 'Dicionário';

  @override
  String get pageAnalyticsTitle => 'Estatísticas';

  @override
  String get pageAboutTitle => 'Sobre o WhisPaste';

  @override
  String get pageFeedbackTitle => 'Feedback';

  @override
  String get historyEmpty => 'Ainda não há gravações';

  @override
  String get historyEmptyHint =>
      'Pressione o botão de gravar ou use o atalho para começar a gravar.';

  @override
  String get historyPrivacyGateTitle => 'Gravações ocultas';

  @override
  String get historyPrivacyGateHint =>
      'As transcrições e o áudio ficam apenas ocultos, não apagados, até você decidir mostrá-los.';

  @override
  String get historyPrivacyGateShow => 'Mostrar gravações';

  @override
  String get historySearch => 'Pesquisar…';

  @override
  String get historyPinned => 'Favoritos';

  @override
  String get historyToday => 'Hoje';

  @override
  String get historyYesterday => 'Ontem';

  @override
  String get historyThisWeek => 'Esta semana';

  @override
  String get historyOlder => 'Mais antigos';

  @override
  String get historyAll => 'Todos';

  @override
  String get historyTrash => 'Lixeira';

  @override
  String get historyArchive => 'Arquivo';

  @override
  String get historyArchived => 'Arquivados';

  @override
  String get historyList => 'Lista';

  @override
  String get historyCards => 'Cartões';

  @override
  String get historyCompact => 'Compacto';

  @override
  String historyItemsSelected(int count) {
    return '$count selecionados';
  }

  @override
  String get historyMerge => 'Mesclar';

  @override
  String get historyRestore => 'Restaurar';

  @override
  String get historyDeleteForever => 'Excluir definitivamente';

  @override
  String get historyDeletePermanently => 'Excluir definitivamente';

  @override
  String get historyUnarchive => 'Desarquivar';

  @override
  String get historyExport => 'Exportar';

  @override
  String get historyExportAction => 'Exportar…';

  @override
  String historyExportDone(String path) {
    return 'Exportado para $path';
  }

  @override
  String get historyExportFailed =>
      'Falha na exportação. Verifique se a pasta de destino permite gravação e tente novamente.';

  @override
  String get historyCopyAsMarkdown => 'Copiar como Markdown';

  @override
  String get historyDetail => 'Detalhes';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Duração';

  @override
  String get historyModel => 'Modelo de voz';

  @override
  String get historyWords => 'Palavras';

  @override
  String get historyCharacters => 'Caracteres';

  @override
  String historyWordCount(int count) {
    return '$count palavras';
  }

  @override
  String historyReadingTime(int minutes) {
    return '$minutes min de leitura';
  }

  @override
  String get historyReadingTimeUnder1 => '< 1 min de leitura';

  @override
  String historyListWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aprox. $count palavras',
      one: 'aprox. 1 palavra',
    );
    return '$_temp0';
  }

  @override
  String get historyToolsMenu => 'Visualização e seleção';

  @override
  String get historyEditing => 'Editando';

  @override
  String get historySearchTranscriptions => 'Pesquisar nas gravações…';

  @override
  String get historySearchFieldLabel => 'Pesquisar transcrições';

  @override
  String get historyNewRecording => 'Nova gravação';

  @override
  String get historyStopRecording => 'Parar gravação';

  @override
  String get historyNoResults => 'Nenhum resultado';

  @override
  String historyNoResultsHint(String query) {
    return 'Nenhuma entrada corresponde a \"$query\".\nTente outro termo de pesquisa.';
  }

  @override
  String get historyTrashEmpty => 'A lixeira está vazia';

  @override
  String historyTrashEmptyHint(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Os itens são removidos definitivamente após $days dias.',
      one: 'Os itens são removidos definitivamente após 1 dia.',
      zero: 'Os itens ficam até você excluí-los definitivamente.',
    );
    return 'Transcrições excluídas aparecerão aqui.\n$_temp0';
  }

  @override
  String get historyEmptyTrash => 'Esvaziar lixeira';

  @override
  String get historyEmptyTrashConfirm => 'Esvaziar lixeira?';

  @override
  String historyEmptyTrashConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Serão excluídas definitivamente $count transcrições. Os arquivos de áudio salvos são removidos no máximo 30 dias após a gravação. Esta ação não pode ser desfeita.',
      one:
          'Será excluída definitivamente 1 transcrição. Qualquer arquivo de áudio salvo é removido no máximo 30 dias após a gravação. Esta ação não pode ser desfeita.',
    );
    return '$_temp0';
  }

  @override
  String get historyDeletePermanentlyConfirm => 'Excluir definitivamente?';

  @override
  String historyDeletePermanentlyConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Serão excluídas definitivamente $count transcrições, junto com os áudios salvos. Esta ação não pode ser desfeita.',
      one:
          'Será excluída definitivamente 1 transcrição, junto com o áudio salvo. Esta ação não pode ser desfeita.',
    );
    return '$_temp0';
  }

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lixeira esvaziada — $count transcrições excluídas',
      one: 'Lixeira esvaziada — 1 transcrição excluída',
    );
    return '$_temp0';
  }

  @override
  String get historyNoArchivedItems => 'Nenhum item arquivado';

  @override
  String get historyNoArchivedItemsHint =>
      'Arquive as transcrições que você quer guardar\nmas não precisa na lista principal.';

  @override
  String get historyNoRecordingsHint =>
      'Pressione o botão de gravar ou use o atalho para começar a gravar.\nSuas transcrições aparecerão aqui.';

  @override
  String get historyNoPinned => 'Nenhum favorito ainda';

  @override
  String get historyNoPinnedHint =>
      'Marque uma transcrição como favorita para encontrá-la aqui rapidamente.';

  @override
  String get historyNoToday => 'Nada gravado hoje';

  @override
  String get historyNoTodayHint => 'As transcrições de hoje aparecerão aqui.';

  @override
  String get historyNoThisWeek => 'Nada gravado esta semana';

  @override
  String get historyNoThisWeekHint =>
      'As transcrições desta semana aparecerão aqui.';

  @override
  String get historyCopiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get historyMovedToTrash => 'Movido para a lixeira';

  @override
  String get historyRestored => 'Restaurado';

  @override
  String historyBulkArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcrições arquivadas',
      one: '1 transcrição arquivada',
    );
    return '$_temp0';
  }

  @override
  String historyBulkMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcrições movidas para a lixeira',
      one: '1 transcrição movida para a lixeira',
    );
    return '$_temp0';
  }

  @override
  String historyBulkRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcrições restauradas',
      one: '1 transcrição restaurada',
    );
    return '$_temp0';
  }

  @override
  String get historyUndo => 'Desfazer';

  @override
  String get historyEntriesMerged => 'Entradas mescladas';

  @override
  String historyMergeConfirm(int count) {
    return 'Mesclar $count entradas?';
  }

  @override
  String get historyMergeConfirmMessage =>
      'As entradas selecionadas serão combinadas em uma só. Não é possível desfazer.';

  @override
  String get historyExitSelection => 'Sair da seleção';

  @override
  String get historySelectMultiple => 'Selecionar vários';

  @override
  String get historyProcessed => 'Processado';

  @override
  String get historyOnDevice => 'No dispositivo';

  @override
  String get historyUntitledRecording => 'Gravação sem título';

  @override
  String get historyUntitled => 'Sem título';

  @override
  String get historyShowAll => 'Mostrar tudo';

  @override
  String get historyMoreActions => 'Mais ações';

  @override
  String get historyMdTags => 'Etiquetas';

  @override
  String get historyMdDate => 'Data';

  @override
  String get historyMdModel => 'Modelo';

  @override
  String get historyPinToTop => 'Adicionar aos favoritos';

  @override
  String get historyUnpin => 'Remover dos favoritos';

  @override
  String get historyCopyText => 'Copiar texto';

  @override
  String get historyClose => 'Fechar';

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
  String get historySelectAll => 'Selecionar tudo';

  @override
  String get historyDeselectAll => 'Desmarcar tudo';

  @override
  String get settingsInterface => 'Interface';

  @override
  String get settingsInterfaceSubtitle => 'Aparência e comportamento';

  @override
  String get settingsReviewPromptRestore =>
      'Mostrar o aviso de avaliação novamente';

  @override
  String get settingsReviewPromptRestoreSubtitle =>
      'Você escolheu «Não perguntar mais». Ativando, o aviso pode voltar; as pausas habituais continuam valendo.';

  @override
  String get settingsLaunchAtStartup => 'Iniciar com o sistema';

  @override
  String get settingsStartMinimized => 'Iniciar minimizado';

  @override
  String get settingsStartMinimizedSubtitle =>
      'Iniciar em segundo plano quando o sistema for ligado';

  @override
  String get settingsAutostartNever => 'Nunca';

  @override
  String get settingsAutostartNormal => 'Normal';

  @override
  String get settingsAutostartMinimized => 'Minimizado';

  @override
  String get settingsAutostartSyncFailed =>
      'Não foi possível registrar a inicialização automática no sistema operacional. Pode ser um problema de permissões ou sua versão do sistema não é compatível.';

  @override
  String get settingsShowNotifications => 'Mostrar notificações';

  @override
  String get settingsShowBackendUtilization =>
      'Indicador de processamento na barra de status';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Mostra se o processador ou a placa de vídeo está trabalhando.';

  @override
  String get settingsAudio => 'Áudio';

  @override
  String get settingsAudioSubtitle => 'Microfone e gravação';

  @override
  String get settingsMicrophone => 'Microfone';

  @override
  String get settingsGain => 'Sensibilidade do microfone';

  @override
  String get settingsClippingBanner =>
      'A última gravação teve clipping. Reduzir o ganho?';

  @override
  String get settingsClippingDismiss => 'Dispensar';

  @override
  String get settingsHoldToRecord => 'Manter pressionado para gravar';

  @override
  String get pushToTalkUnavailableTooltip => 'Não disponível nesta plataforma';

  @override
  String get pushToTalkUnavailableLinuxTooltip =>
      'Seu desktop não informa a liberação de teclas aqui. Associe “whispaste --toggle” a um atalho nas configurações do sistema.';

  @override
  String get settingsExperimentalBadge => 'Experimental';

  @override
  String get settingsHoldOrTap => 'Toque ou mantenha';

  @override
  String get settingsHoldOrTapHint =>
      'Um toque curto inicia e para a gravação; mantendo pressionado, a gravação dura até você soltar.';

  @override
  String get settingsHoldOrTapThreshold => 'Limiar de manter pressionado';

  @override
  String settingsHoldOrTapThresholdValue(int ms) {
    return '$ms ms';
  }

  @override
  String get settingsModifierOnlyNone => 'Desativado';

  @override
  String get settingsModifierRightControl => 'Control direito';

  @override
  String get settingsModifierRightAlt => 'Alt direito ou Option';

  @override
  String get settingsModifierRightMetaMac => 'Command direito';

  @override
  String get settingsModifierRightMetaWindows => 'Windows direito';

  @override
  String get settingsModifierRightMetaLinux => 'Super direito';

  @override
  String get settingsModifierFn => 'Fn (somente macOS)';

  @override
  String get settingsModifierLeftShift => 'Shift esquerdo';

  @override
  String get settingsModifierRightShift => 'Shift direito';

  @override
  String get settingsModifierLeftControl => 'Ctrl esquerdo';

  @override
  String get settingsModifierLeftAlt => 'Alt / Option esquerdo';

  @override
  String get settingsModifierLeftMetaMac => 'Command esquerdo';

  @override
  String get settingsModifierLeftMetaWindows => 'Tecla Windows esquerda';

  @override
  String get settingsModifierLeftMetaLinux => 'Tecla Super esquerda';

  @override
  String get settingsTriggerDoubleTapHint =>
      'As teclas esquerdas e o Shift só iniciam depois de segurá-las sozinhas por um instante, assim os atalhos comuns não acionam nada.';

  @override
  String get settingsDoubleTapHandsFree => 'Toque duplo: ditar sem as mãos';

  @override
  String get settingsDoubleTapHandsFreeHint =>
      'Dois toques rápidos iniciam o ditado sem segurar; um toque o termina.';

  @override
  String get settingsDoubleTapBlockedByHoldOrTap =>
      'Não junto com \"Segurar ou tocar\"';

  @override
  String get settingsDoubleTapNeedsHold =>
      'Funciona com \"Segurar\" ou uma única tecla';

  @override
  String get settingsDoubleTapFallbackNotice =>
      'A tecla escolhida não pode ser usada neste dispositivo. Até lá vale a combinação acima. Sua escolha continua salva.';

  @override
  String get settingsDoubleTapFallbackNoticeWindows =>
      'A tecla escolhida não pode ser usada no Windows agora, porque o Windows não permite observá-la. Até lá vale a combinação acima. Sua escolha continua salva.';

  @override
  String get settingsDoubleTapFallbackNoticeLinux =>
      'A tecla escolhida não pode ser usada nesta sessão do Linux, porque a área de trabalho não informa quando uma tecla é solta. Até lá vale a combinação acima. Sua escolha continua salva.';

  @override
  String get settingsDoubleTapFallbackNoticeMac =>
      'A tecla escolhida ainda não pode ser usada no Mac, porque falta a permissão \"Monitoramento de Entrada\". Até lá vale a combinação acima. Sua escolha continua salva e passa a valer assim que você conceder a permissão e trouxer o WhisPaste para a frente.';

  @override
  String get settingsTriggerKeyUnsupportedFn => 'Disponível só no Mac.';

  @override
  String get settingsTriggerKeyUnsupportedWayland =>
      'Não disponível no Linux com Wayland.';

  @override
  String get settingsTriggerRightAltAltGr =>
      'Em muitos teclados esta é a AltGr para @ e €. Nesse caso, escolha outra tecla.';

  @override
  String get settingsSpeechRecognition => 'Reconhecimento de fala';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Qualidade e serviço do reconhecimento de voz';

  @override
  String get settingsService => 'O reconhecimento roda em';

  @override
  String get settingsQuality => 'Velocidade e precisão';

  @override
  String get settingsRecordingSafety => 'Segurança da gravação';

  @override
  String get settingsRecordingSafetySubtitle =>
      'Verificações e proteções automáticas';

  @override
  String get settingsDeadMicTimeout => 'Detecção de microfone silencioso';

  @override
  String get settingsDeadMicTimeoutHint =>
      'Parar a gravação se nenhum áudio for detectado dentro deste tempo (segundos). 0 = desativado.';

  @override
  String get settingsAutoStopSilence => 'Parada automática por silêncio';

  @override
  String get settingsAutoStopSilenceHint =>
      'Parar automaticamente após esta quantidade de segundos de silêncio (depois da fala). 0 = desativado.';

  @override
  String get settingsEnabled => 'Ativado';

  @override
  String get settingsStyle => 'Estilo';

  @override
  String get settingsMicSystemDefault => 'Padrão do sistema';

  @override
  String get settingsMicSystemHint =>
      'A entrada de áudio é gerenciada pelas configurações do sistema';

  @override
  String get settingsMicNoDeviceHint =>
      'Nenhum dispositivo de entrada encontrado. Verifique nas configurações do sistema se o WhisPaste pode usar o microfone.';

  @override
  String get settingsServiceOnDevicePrivate => 'Localmente no dispositivo';

  @override
  String get settingsLanguageAutoDetect => 'Detectar automaticamente';

  @override
  String get settingsLanguageEnglish => 'Inglês';

  @override
  String get settingsLanguageGerman => 'Alemão';

  @override
  String get settingsLanguageFrench => 'Francês';

  @override
  String get settingsLanguageSpanish => 'Espanhol';

  @override
  String get settingsLanguageHebrew => 'Hebraico';

  @override
  String get settingsSoundFeedback => 'Sons e feedback';

  @override
  String get settingsSoundFeedbackSubtitle =>
      'Sinais sonoros para eventos de gravação';

  @override
  String get settingsSoundsEnabled => 'Sons';

  @override
  String get settingsRecordStartSound => 'Som de início da gravação';

  @override
  String get settingsRecordStopSound => 'Som de fim da gravação';

  @override
  String get settingsTranscriptionCompleteSound =>
      'Som de transcrição concluída';

  @override
  String get settingsDurationWarningSound => 'Aviso de limite de duração';

  @override
  String get settingsSoundVolume => 'Volume dos sons';

  @override
  String get settingsAfterTranscription => 'Após a transcrição';

  @override
  String get settingsAfterTranscriptionSubtitle =>
      'O que acontece com o texto transcrito';

  @override
  String get settingsAfterTranscriptionActionLabel => 'Depois de gravar';

  @override
  String get settingsAfterTranscriptionClipboard =>
      'Copiar para a área de transferência';

  @override
  String get settingsAfterTranscriptionPaste =>
      'Colar automaticamente no cursor';

  @override
  String get settingsAfterTranscriptionBoth => 'Copiar e colar automaticamente';

  @override
  String get settingsAfterTranscriptionNothing => 'Não fazer nada';

  @override
  String get pasteFailurePermissionMissing =>
      'O Auto-Paste foi bloqueado pelo sistema. O WhisPaste precisa de permissão para inserir texto em outros apps — o macOS chama essa permissão de \'Acessibilidade\'.';

  @override
  String get pasteFailureNoTarget =>
      'Auto-Paste ignorado, nenhuma janela de destino foi capturada. Foque o app de destino antes de iniciar uma gravação.';

  @override
  String get pasteFailureElevationBlocked =>
      'Auto-Paste bloqueado: o app de destino está sendo executado com privilégios de administrador. Reinicie o WhisPaste como administrador para colar nesse app.';

  @override
  String pasteFailureGeneric(String paste) {
    return 'Falha no Auto-Paste. A transcrição está na área de transferência; cole manualmente com $paste.';
  }

  @override
  String get pasteFailureOpenSettings => 'Abrir configurações';

  @override
  String get pendingAudioSaveLater =>
      'Não foi possível salvar a gravação. O arquivo de áudio é mantido, e o WhisPaste tenta de novo na próxima vez que for iniciado.';

  @override
  String get pendingAudioRecovered =>
      'Uma gravação que antes não pôde ser salva já está em Gravações.';

  @override
  String get pendingAudioInterruptedDiscarded =>
      'Não foi possível processar uma gravação interrompida e ela foi apagada.';

  @override
  String get pasteNotificationNoTargetTitle => 'WhisPaste: Auto-Paste ignorado';

  @override
  String get pasteNotificationNoTargetBody =>
      'Nenhum app de destino detectado. Foque primeiro o app de destino e depois inicie a gravação. O texto está na área de transferência.';

  @override
  String get pasteNotificationNoTargetTray =>
      'Auto-Paste: app de destino ausente';

  @override
  String get silentMicrophoneNotificationTitle =>
      'WhisPaste: sem sinal do microfone';

  @override
  String get silentMicrophoneNotificationBody =>
      'O microfone não capta som. Verifique o microfone selecionado ou se está silenciado. A gravação continua.';

  @override
  String get pasteNotificationRestartNeededTitle =>
      'WhisPaste: reinício necessário';

  @override
  String get pasteNotificationRestartNeededBody =>
      'A permissão foi concedida, mas o WhisPaste ainda está com o estado antigo. Clique aqui para reiniciar o WhisPaste.';

  @override
  String get pasteNotificationRestartNeededTray =>
      'Auto-Paste bloqueado — reinício necessário';

  @override
  String get pasteNotificationPermissionBlockedTitle =>
      'WhisPaste: Auto-Paste bloqueado';

  @override
  String get pasteNotificationPermissionResetEntryBody =>
      'O WhisPaste precisa de permissão para inserir texto em outros apps — o macOS chama essa permissão de \'Acessibilidade\'. Clique aqui: o WhisPaste remove uma entrada possivelmente desatualizada e deixa o macOS perguntar de novo.';

  @override
  String get pasteNotificationPermissionOpenSettingsBody =>
      'O WhisPaste precisa de permissão para inserir texto em outros apps — o macOS chama essa permissão de \'Acessibilidade\'. Clique aqui ou no ícone da bandeja para abrir os Ajustes do Sistema.';

  @override
  String get pasteNotificationPermissionBlockedTray =>
      'Auto-Paste bloqueado — abrir Ajustes do Sistema';

  @override
  String get pasteNotificationElevationBlockedTitle =>
      'WhisPaste: Auto-Paste bloqueado';

  @override
  String get pasteNotificationElevationBlockedBody =>
      'O app de destino está sendo executado com privilégios de administrador. Reinicie também o WhisPaste como administrador para colar nesse app.';

  @override
  String get pasteNotificationElevationBlockedTray =>
      'Auto-Paste bloqueado — administrador necessário';

  @override
  String get pasteNotificationFailedTitle => 'WhisPaste: falha no Auto-Paste';

  @override
  String pasteNotificationFailedBody(String paste) {
    return 'O sistema bloqueou a tecla de colar. O texto está na área de transferência. Cole você mesmo com $paste.';
  }

  @override
  String get pasteNotificationFailedTray => 'Falha no Auto-Paste';

  @override
  String get pasteNotificationClipboardHint =>
      'O texto está na área de transferência.';

  @override
  String pasteNotificationLinuxUinputBody(String paste) {
    return 'O WhisPaste ainda não pode usar o teclado virtual /dev/uinput. O texto está na área de transferência; cole-o com $paste. Clique aqui para configurar.';
  }

  @override
  String get pasteNotificationLinuxUinputTray =>
      'Auto-Paste bloqueado — configuração necessária';

  @override
  String pasteNotificationLinuxNoDeviceBody(String paste) {
    return 'O Auto-Paste não está disponível: este sistema não tem o teclado virtual que ele precisa. O texto está na área de transferência; cole-o com $paste. Clique aqui para abrir as configurações do Auto-Paste.';
  }

  @override
  String get pasteNotificationLinuxNoDeviceTray => 'Auto-Paste indisponível';

  @override
  String get pasteCapabilityCheckTitle => 'Um momento…';

  @override
  String get pasteCapabilityReady => 'Tudo pronto';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Seu texto aparece direto no cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Ainda não permitido';

  @override
  String get pasteCapabilityUnsupported =>
      'O Auto-Paste não está disponível nesta plataforma';

  @override
  String get pasteCapabilityUnavailableLinux =>
      'O Auto-Paste não é possível aqui agora';

  @override
  String get pasteCapabilityTestButton => 'Testar agora';

  @override
  String get pasteCapabilityGrantButton => 'Continuar';

  @override
  String get pasteCapabilityWhyMac =>
      'O WhisPaste precisa de permissão para digitar texto no app em que você está trabalhando — o macOS chama essa permissão de \'Acessibilidade\'.';

  @override
  String get pasteCapabilityTroubleshoot => 'Com problemas?';

  @override
  String get pasteCapabilityRepairHint =>
      'Às vezes o macOS lembra de uma entrada antiga e esquece a nova autorização. Redefina a entrada. Assim o macOS perguntará de novo, do jeito certo.';

  @override
  String get pasteCapabilityRepairButton => 'Redefinir entrada';

  @override
  String get pasteCapabilityRestartButton => 'Reiniciar o WhisPaste';

  @override
  String get pasteCapabilityRestartTitle => 'Quase lá — reinicie o WhisPaste';

  @override
  String get pasteCapabilityRestartBody =>
      'Se você ativou a permissão, o macOS só a aplica em um app recém-iniciado. Um clique — o WhisPaste fecha e volta logo em seguida.';

  @override
  String get pasteRestartAlertTitle => 'Reiniciar o WhisPaste agora';

  @override
  String get pasteRestartAlertBody =>
      'A permissão do Auto-Paste está definida, mas o macOS só a aplica após um reinício. O WhisPaste vai fechar e voltar logo em seguida.';

  @override
  String get pasteRestartAlertConfirm => 'Reiniciar agora';

  @override
  String get pasteStaleEntryGuideTitle =>
      'Remover a entrada antiga do WhisPaste';

  @override
  String get pasteStaleEntryGuideBody =>
      'O macOS ainda guarda a permissão do Auto-Paste de uma versão anterior do WhisPaste. Essa entrada não pode ser ativada — ela precisa ser removida uma vez:\n\n1. Selecione “WhisPaste” na lista.\n2. Clique em “−” abaixo da lista.\n3. Volte ao WhisPaste.\n\nDepois de reiniciar, o macOS pergunta de novo — é só permitir.';

  @override
  String get pasteStaleEntryGuideConfirm => 'Abrir Ajustes do Sistema';

  @override
  String get pasteStaleEntryRestartTitle => 'Reiniciar o WhisPaste';

  @override
  String get pasteStaleEntryRestartBody =>
      'Depois de remover a entrada antiga, reinicie o WhisPaste. O macOS vai pedir a permissão de novo — confirme e ative o WhisPaste.';

  @override
  String get pasteStaleEntryRestartConfirm => 'Reiniciar o WhisPaste';

  @override
  String get permissionAlertLaterButton => 'Agora não';

  @override
  String get micGateAlertTitle => 'Falta acesso ao microfone';

  @override
  String get micGateAlertBody =>
      'O WhisPaste não consegue gravar sem acesso ao microfone. Confirme para abrir Ajustes do Sistema → Privacidade e Segurança → Microfone e ative ali a chave do WhisPaste. O WhisPaste detecta sua autorização automaticamente.';

  @override
  String get micGateAlertBodyGeneric =>
      'O WhisPaste não consegue gravar sem acesso ao microfone. Permita o acesso ao microfone para o WhisPaste nas configurações de privacidade do seu sistema — o WhisPaste detecta sua autorização automaticamente.';

  @override
  String get micGateAlertConfirm => 'Abrir configurações';

  @override
  String get micGateRestartAlertTitle => 'Reinicie o WhisPaste para concluir';

  @override
  String get micGateRestartAlertBody =>
      'O acesso ao microfone foi concedido, mas esta instância do WhisPaste em execução ainda não consegue usá-lo. O WhisPaste vai fechar e voltar logo em seguida — tudo continua como está.';

  @override
  String get micGateRestartAlertConfirm => 'Reiniciar agora';

  @override
  String get autoPasteGateAlertTitle =>
      'Falta um interruptor para a inserção automática';

  @override
  String get autoPasteGateAlertBody =>
      'O WhisPaste insere seu texto direto no cursor. Para isso, o macOS exige um interruptor que só você pode ativar: Ajustes do Sistema → Privacidade e Segurança → Acessibilidade. Confirme para abrir exatamente essa página — o WhisPaste detecta sua autorização automaticamente e, se preciso, reinicia sozinho depois.';

  @override
  String get autoPasteGateAlertConfirm => 'Abrir Ajustes do Sistema';

  @override
  String get pasteCapabilityRestartIneffectiveTitle =>
      'O reinício não aplicou a permissão';

  @override
  String get pasteCapabilityRestartIneffectiveSubtitle =>
      'Abra a permissão de novo e verifique em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade se o WhisPaste está realmente ativado. Reative a chave e o WhisPaste reinicia mais uma vez.';

  @override
  String pasteCapabilityRepairDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count entradas desatualizadas removidas. Tente colar uma vez para ver os novos prompts.',
      one:
          '1 entrada desatualizada removida. Tente colar uma vez para ver um novo prompt.',
      zero: 'Nenhuma entrada desatualizada encontrada. Tente colar uma vez.',
    );
    return '$_temp0';
  }

  @override
  String get pasteCapabilityRepairNothingToClear =>
      'Nenhuma entrada antiga encontrada. Um reinício provavelmente ajuda agora.';

  @override
  String get pasteCapabilityRepairFailed =>
      'Não foi possível executar a redefinição de permissão do macOS. Tente remover o WhisPaste manualmente em Ajustes do Sistema → Acessibilidade.';

  @override
  String get onboardingPermissionsTitle =>
      'O que o WhisPaste precisa no teu computador.';

  @override
  String get onboardingPermissionsTitleDone => 'Tudo pronto.';

  @override
  String get onboardingPermissionsSubtitle =>
      'O WhisPaste só usa isto enquanto ditas.';

  @override
  String get onboardingPermMicTitle => 'Usar o microfone';

  @override
  String get onboardingPermMicBody => 'Para o WhisPaste ouvir o que ditas.';

  @override
  String get onboardingPermMicDenied =>
      'Ainda não permitido. Sem microfone não dá para ditar, mas podes permitir mais tarde.';

  @override
  String get onboardingPermPasteTitle => 'Inserir o texto diretamente';

  @override
  String get onboardingPermPasteBody =>
      'O teu ditado aparece onde estás a escrever, em qualquer app.';

  @override
  String get onboardingPermPasteMacNote =>
      'O macOS chama esta permissão de \"Acessibilidade\".';

  @override
  String get onboardingPermSkipTitle => 'Continuar sem permissão?';

  @override
  String get onboardingPermSkipMic =>
      'Sem o microfone, o WhisPaste não consegue ditar.';

  @override
  String onboardingPermSkipPaste(String shortcut) {
    return 'Sem \"Inserir o texto diretamente\", o WhisPaste apenas copia o texto e você o cola com $shortcut.';
  }

  @override
  String get onboardingPermSkipLater =>
      'Você pode fazer isso depois nas Configurações.';

  @override
  String get onboardingPermSkipConfirm => 'Continuar mesmo assim';

  @override
  String get onboardingPermSkipCancel => 'Permitir agora';

  @override
  String onboardingPermPasteWithout(String shortcut) {
    return 'Sem esta permissão, o WhisPaste copia o texto e tu colas com $shortcut.';
  }

  @override
  String get onboardingPasteTitle =>
      'Assim seu texto aparece onde você está digitando';

  @override
  String get onboardingPasteSubtitle =>
      'Em instantes, o macOS vai perguntar se o WhisPaste pode fazer isso. Diga sim, pronto.';

  @override
  String get onboardingPasteSubtitleWin =>
      'No Windows não é preciso permissão — apenas escolha se o WhisPaste deve inserir o texto para você.';

  @override
  String get onboardingPasteSubtitleLinux =>
      'No Linux nenhuma janela do sistema pede permissão. Abaixo está indicado se é preciso configurar algo para isso.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste pronto';

  @override
  String get onboardingPasteChipPending => 'Acesso do Auto-Paste pendente';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: ação necessária';

  @override
  String get onboardingPasteSkip =>
      'Só copiar por enquanto, sem inserção automática';

  @override
  String get onboardingPasteWhyMac =>
      'Sem permissão, seu texto é copiado para a área de transferência. Depois, você cola manualmente com ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'O Auto-Paste pressiona Ctrl+V por você após cada gravação, então o texto aparece exatamente onde você está digitando. Testado e funcionando neste computador — ative abaixo.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'Em programas executados como administrador, o Auto-Paste não funciona. O texto fica na área de transferência e você o cola com Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'O Auto-Paste está ativado';

  @override
  String get onboardingPasteWinOnDetail =>
      'Após cada gravação, o WhisPaste pressiona Ctrl+V por você — o texto aparece direto no cursor. Uma cópia também fica na área de transferência.';

  @override
  String get onboardingPasteLinuxNative =>
      'O Auto-Paste precisa da sua permissão para o teclado virtual. Com o pacote .deb, escolha «Permitir (senha de administrador)» e digite sua senha de administrador; caso contrário, copie o comando e execute-o uma vez em um terminal. Você pode remover a permissão nas configurações.';

  @override
  String get onboardingPasteLinuxFlatpak =>
      'Na versão Flatpak (--device=all), os dispositivos de entrada do computador ficam visíveis dentro do sandbox. O WhisPaste não lê nenhuma entrada. Se a sua conta puder ler esses dispositivos (por exemplo, como membro do grupo input), o app poderia ler as teclas digitadas em outros programas. O Auto-Paste também precisa de um comando único: copie-o e execute-o uma vez em um terminal (pede senha de administrador e altera o sistema). Se não quiser isso, deixe o Auto-Paste desligado e cole o texto à mão.';

  @override
  String get onboardingPasteLinuxSnap =>
      'Na versão Snap, execute isto uma vez em um terminal: sudo snap connect whispaste:uinput. Até lá, o Auto-Paste apenas copia o texto.';

  @override
  String get onboardingPasteLinuxAppImage =>
      'O Auto-Paste precisa de uma permissão única para o teclado virtual. Copie o comando e execute-o uma vez em um terminal. Ele grava a regra udev 71-whispaste-uinput.rules, precisa de direitos de administrador e altera o sistema: echo \'KERNEL==\"uinput\", SUBSYSTEM==\"misc\", TAG+=\"uaccess\"\' | sudo tee /etc/udev/rules.d/71-whispaste-uinput.rules && sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput. A permissão vale só para a sua sessão conectada. Até lá, o Auto-Paste só copia o texto.';

  @override
  String get onboardingPasteWinEnableCta => 'Ativar Auto-Paste';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'Em programas executados como administrador, o Auto-Paste não funciona. O texto fica na área de transferência e você o cola com Ctrl+V.';

  @override
  String get onboardingPasteLinuxClipboardFallback =>
      'O Auto-Paste está ativado. Até o acesso ser configurado, o WhisPaste coloca o texto na área de transferência e você o cola com Ctrl+V.';

  @override
  String onboardingPasteLinuxUnavailableDetail(Object shortcut) {
    return 'O texto vai para a área de transferência. Cole-o com $shortcut.';
  }

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Ative o interruptor ao lado de WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Os Ajustes do Sistema estão abertos. Procure o WhisPaste na lista e ative-o.';

  @override
  String get onboardingAccessRemoveReAddHint =>
      'O interruptor não funciona? Remova o WhisPaste da lista e adicione-o novamente.';

  @override
  String get settingsOverlayFloatingButton => 'Overlay de gravação';

  @override
  String get settingsOverlayFloatingButtonSubtitle =>
      'Defina como o status da gravação aparece enquanto você grava';

  @override
  String get settingsShowOverlay => 'Exibição do status da gravação';

  @override
  String get settingsShowOverlaySubtitle =>
      'Escolha onde o feedback da gravação ao vivo aparece enquanto você grava';

  @override
  String get settingsOverlayModeFloating => 'Flutuante (sempre visível)';

  @override
  String get settingsOverlayModeOff => 'Desativado';

  @override
  String get settingsOverlayStartPosition => 'Posição do overlay';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Onde o overlay de gravação aparece quando a gravação começa';

  @override
  String get settingsOverlayStartTopCenter => 'Centro superior';

  @override
  String get settingsOverlayStartBottomCenter => 'Centro inferior';

  @override
  String get settingsOverlayStartLastPosition => 'Lembrar última posição';

  @override
  String get settingsShowFloatingButton => 'Botão flutuante';

  @override
  String get settingsShowFloatingButtonSubtitle =>
      'Pequeno botão sempre visível para iniciar ou parar a gravação em qualquer app';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsRecognitionLanguage => 'Idioma de reconhecimento';

  @override
  String get settingsCustomVocabulary => 'Vocabulário personalizado';

  @override
  String get settingsCustomVocabularyHint =>
      'Nomes e termos técnicos: melhora a precisão do reconhecimento';

  @override
  String get settingsCustomVocabularyPlaceholder =>
      'ex.: WhisPaste, Kubernetes, Dr. Müller';

  @override
  String settingsCustomVocabularyBudgetCounter(int count, int budget) {
    return '~$count de $budget em uso';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Se a lista ocupar mais de $budget, o restante é omitido automaticamente.';
  }

  @override
  String get settingsPunctuationPriming => 'Incentivo à pontuação';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Faz o reconhecimento tender a incluir pontuação quando não há vocabulário personalizado. A velocidade não muda.';

  @override
  String get settingsVadEnabled => 'Remover silêncio no final';

  @override
  String get settingsVadEnabledSubtitle =>
      'Corta silêncio longo e ruído no fim de uma gravação, para que a transcrição não invente uma frase final (por exemplo, «Obrigado por assistir»).';

  @override
  String get settingsStripPunctuation => 'Remover pontuação';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Remove pontos, vírgulas e outros sinais de pontuação de cada transcrição antes de ela ser salva ou colada. Números como 3,5 não são alterados. Funciona igual para todos os métodos de reconhecimento.';

  @override
  String get settingsNumericOnlyMode => 'Somente números';

  @override
  String get settingsNumericOnlyModeSubtitle =>
      'Converte números falados (em alemão e inglês) em algarismos, por exemplo \"five point two\" vira \"5.2\". Deixa a transcrição intacta se ela não puder ser convertida por completo.';

  @override
  String get settingsRemoveFillerWords => 'Remover palavras de preenchimento';

  @override
  String get settingsRemoveFillerWordsSubtitle =>
      'Remove hesitações como \"uh\", \"um\" e \"erm\" antes de a transcrição ser salva ou colada. Só palavras de preenchimento inequívocas em inglês e alemão; palavras que podem ter significado nunca são alteradas.';

  @override
  String get settingsVoiceLineBreaks => 'Quebras de linha por voz';

  @override
  String get settingsVoiceLineBreaksSubtitle =>
      'Transforma comandos falados como “novo parágrafo” e “nova linha” em quebras de linha reais. Vale para o idioma da transcrição ou, com detecção automática, para todos os idiomas suportados.';

  @override
  String get settingsSpokenPunctuation => 'Pontuação por voz';

  @override
  String get settingsSpokenPunctuationSubtitle =>
      'Se você disser «vírgula» ou «ponto» como palavra dentro de uma frase, revise o texto depois.';

  @override
  String get settingsWrittenForms => 'Formas escritas';

  @override
  String get settingsWrittenFormsSubtitle =>
      'Escreve do jeito usual os endereços de e-mail, sites, datas, horas e valores em dinheiro que você dita: «john at gmail dot com» vira john@gmail.com. Somente alemão e inglês. Cada tipo pode ser desligado separadamente.';

  @override
  String get settingsWrittenFormEmail => 'Endereços de e-mail';

  @override
  String get settingsWrittenFormUrl => 'Endereços da web';

  @override
  String get settingsWrittenFormDate => 'Datas';

  @override
  String get settingsWrittenFormTime => 'Horas';

  @override
  String get settingsWrittenFormMoney => 'Valores em dinheiro';

  @override
  String get settingsAppLanguage => 'Idioma do app';

  @override
  String get settingsSttModels => 'Modelos de voz';

  @override
  String get settingsOpenAiApiKey => 'Chave de API da OpenAI';

  @override
  String get settingsDeepgramApiKey => 'Chave de API da Deepgram';

  @override
  String get settingsToggleApiKeyVisibility => 'Mostrar/ocultar chave de API';

  @override
  String get settingsAdvanced => 'Avançado';

  @override
  String get settingsAdvancedSubtitle =>
      'Redefinição, relatórios de erro, atualizações e comportamento do sistema';

  @override
  String get settingsResetToDefaults => 'Restaurar padrões';

  @override
  String get settingsResetTitle => 'Redefinir configurações';

  @override
  String get settingsResetMessage =>
      'Todas as configurações voltarão aos padrões. As chaves de API serão removidas. Isso não pode ser desfeito.';

  @override
  String get settingsResetConfirm => 'Redefinir';

  @override
  String get settingsResetSuccess =>
      'Configurações redefinidas para os padrões';

  @override
  String get settingsFactoryReset => 'Redefinir tudo';

  @override
  String get settingsFactoryResetTitle => 'Redefinição de fábrica';

  @override
  String get settingsFactoryResetMessage =>
      'Isso apaga imediatamente: transcrições com suas tags e notas, arquivos de áudio salvos, Dicionário, Snippets, Estatísticas, chaves de API, modelos baixados, registros e configurações. O aplicativo voltará ao estado inicial.\n\nO aplicativo não consegue restaurar nada disso. Os arquivos são excluídos de forma comum e não são sobrescritos, então ferramentas especializadas podem recuperar partes deles.';

  @override
  String get settingsFactoryResetConfirm => 'Apagar tudo';

  @override
  String get settingsFactoryResetSuccess => 'O app foi totalmente redefinido';

  @override
  String get settingsFactoryResetProgressTitle => 'Redefinindo o WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Parando o modelo de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Apagando modelos de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingAudio => 'Apagando gravações…';

  @override
  String get settingsFactoryResetPhaseDeletingDatabase =>
      'Apagando banco de dados…';

  @override
  String get settingsFactoryResetPhaseResettingSecureStore =>
      'Limpando credenciais…';

  @override
  String get settingsFactoryResetPhaseResettingSettings =>
      'Restaurando configurações padrão…';

  @override
  String settingsFactoryResetFailedMessage(String areas) {
    return 'A redefinição não está completa. Afetado: $areas. Você pode tentar novamente.';
  }

  @override
  String get factoryResetAreaDb =>
      'Transcrições, Notas, Dicionário, Snippets e Estatísticas';

  @override
  String get factoryResetAreaAudio => 'Arquivos de áudio';

  @override
  String get factoryResetAreaModels => 'Modelos e registros';

  @override
  String get factoryResetAreaSecure => 'Chaves de API';

  @override
  String get factoryResetAreaSettings => 'Configurações';

  @override
  String get factoryResetAreaProcess => 'Processo em segundo plano';

  @override
  String get factoryResetRetryAction => 'Tentar novamente';

  @override
  String get factoryResetKeyringHint =>
      'Não foi possível remover as chaves de API do chaveiro. Se necessário, apague você mesmo as entradas que começam com “wp_” no gerenciador de senhas do sistema.';

  @override
  String get settingsPortabilitySectionTitle => 'Backup e transferência';

  @override
  String get settingsPortabilitySectionSubtitle =>
      'Mantenha um backup da sua configuração do WhisPaste ou leve-a para outro computador';

  @override
  String get settingsPortabilityExportAction => 'Exportar';

  @override
  String get settingsPortabilityImportAction => 'Importar';

  @override
  String get settingsPortabilityExportLocationLabel => 'Destino da exportação';

  @override
  String get settingsPortabilityImportLocationLabel => 'Origem da importação';

  @override
  String get settingsPortabilityExportLocationUnset =>
      'Será perguntado na primeira exportação';

  @override
  String get settingsPortabilityImportLocationUnset =>
      'Será perguntado na primeira importação';

  @override
  String get settingsPortabilityChooseExportLocation =>
      'Escolher outro destino de exportação (nada foi exportado ainda)';

  @override
  String get settingsPortabilityChooseImportLocation =>
      'Escolher outra origem de importação (nada foi importado ainda)';

  @override
  String settingsPortabilityExportSuccess(String path) {
    return 'Configurações exportadas para $path';
  }

  @override
  String settingsPortabilityExportError(String reason) {
    return 'Falha na exportação: $reason';
  }

  @override
  String get settingsPortabilityImportConfirmTitle => 'Importar configurações?';

  @override
  String settingsPortabilityImportConfirmMessage(String path) {
    return 'Isso substitui suas configurações atuais — incluindo interface, configuração do modelo de voz, comportamento, substituições de texto e snippets — pelo conteúdo de $path. Suas chaves de API não são alteradas.';
  }

  @override
  String settingsPortabilityImportSuccess(String path) {
    return 'Configurações importadas de $path';
  }

  @override
  String settingsPortabilityImportNotFound(String path) {
    return 'Nenhum arquivo de exportação encontrado em $path. Exporte as configurações primeiro ou copie um arquivo de exportação para lá.';
  }

  @override
  String settingsPortabilityImportError(String reason) {
    return 'Falha na importação: $reason';
  }

  @override
  String get settingsAutosaveLabel => 'Backup automático';

  @override
  String get settingsAutosaveHint =>
      'Salva sua configuração na pasta escolhida alguns segundos após cada alteração';

  @override
  String get settingsAutosaveChooseFolder =>
      'Escolher outra pasta para backups automáticos (nada foi salvo ainda)';

  @override
  String settingsAutosaveLastRun(String time) {
    return 'Último backup: $time';
  }

  @override
  String get settingsAutosaveNeverRun => 'Nenhum backup ainda';

  @override
  String get settingsAutosaveLastRunFailed => 'Falha no backup';

  @override
  String settingsAutosaveLastRunFailedSince(String time) {
    return 'A última tentativa falhou — último backup: $time';
  }

  @override
  String get settingsAutosaveErrorLocation =>
      'Falha no backup automático: a pasta escolhida não está disponível.';

  @override
  String settingsAutosaveErrorWrite(String reason) {
    return 'Falha no backup automático: $reason';
  }

  @override
  String get groqRemovedToast =>
      'O provedor na nuvem que você usava foi removido. O reconhecimento de voz agora roda neste dispositivo.';

  @override
  String migrationComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gravações migradas do WhisPaste 1.x',
      one: '1 gravação migrada do WhisPaste 1.x',
    );
    return '$_temp0';
  }

  @override
  String get settingsOff => 'Desativado';

  @override
  String get settingsOn => 'Ativado';

  @override
  String get statusReady => 'Pronto';

  @override
  String get statusRecording => 'Gravando…';

  @override
  String get statusTranscribing => 'Transcrevendo…';

  @override
  String get statusProcessing => 'Processando…';

  @override
  String get statusTranscriptionDone => 'Transcrição concluída';

  @override
  String get statusSelectionEdited => 'Seleção editada';

  @override
  String get statusCopied => 'Copiado!';

  @override
  String get statusLocal => 'Local';

  @override
  String get statusCloud => 'Nuvem';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get recordingGuardFailed =>
      'Nenhum áudio detectado. Tente novamente. Às vezes o microfone precisa de um momento para ser ativado.';

  @override
  String get recordingAutoStopped =>
      'Gravação interrompida: silêncio detectado.';

  @override
  String get actionCopy => 'Copiar';

  @override
  String get actionDuplicate => 'Duplicar';

  @override
  String get actionDelete => 'Excluir';

  @override
  String get actionDismiss => 'Fechar';

  @override
  String get actionEdit => 'Editar';

  @override
  String get actionExport => 'Exportar';

  @override
  String get unsavedInputTitle => 'Descartar as alterações?';

  @override
  String get unsavedInputMessage => 'O texto digitado ainda não foi salvo.';

  @override
  String get unsavedInputDiscard => 'Descartar';

  @override
  String get trayUnavailableMinimizedHint =>
      'O ícone da bandeja não está disponível. O WhisPaste foi minimizado e continua em execução.';

  @override
  String get settingsSaveFailedToast =>
      'A configuração não pôde ser salva. O valor anterior foi mantido.';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionClose => 'Fechar';

  @override
  String get actionConfirm => 'Confirmar';

  @override
  String get actionSave => 'Salvar';

  @override
  String get actionRetry => 'Tentar novamente';

  @override
  String get actionClearSearch => 'Limpar pesquisa';

  @override
  String get tooltipLanguage => 'Idioma';

  @override
  String aboutVersion(String version) {
    return 'Versão $version';
  }

  @override
  String get feedbackTitle => 'Enviar feedback';

  @override
  String get feedbackHint => 'Conte o que você acha. Lemos cada mensagem.';

  @override
  String get analyticsPreviewBanner =>
      'Prévia: mostrando dados de exemplo. As estatísticas reais aparecerão quando você começar a gravar.';

  @override
  String get analyticsEmptyTitle => 'Nenhuma gravação ainda';

  @override
  String get analyticsEmptySubtitle =>
      'Comece a gravar para ver suas estatísticas aqui.';

  @override
  String get analyticsNoRecordingsInPeriod => 'Nenhuma gravação neste período';

  @override
  String get analyticsOverview => 'Visão geral';

  @override
  String get analyticsOverviewSubtitle =>
      'Suas estatísticas de gravação de relance';

  @override
  String get analyticsActivity => 'Atividade';

  @override
  String get analyticsInsights => 'Insights';

  @override
  String get analyticsTotalRecordings => 'Total de gravações';

  @override
  String get analyticsTotalDuration => 'Duração total';

  @override
  String get analyticsWordsDictated => 'Palavras transcritas';

  @override
  String get analyticsTimeSaved => 'Tempo economizado (estimativa)';

  @override
  String analyticsTimeSavedNote(int wpm) {
    return 'Estimativa: digitar a $wpm palavras por minuto, menos o tempo de fala';
  }

  @override
  String get analyticsAvgLatency => 'Tempo médio até o texto';

  @override
  String get analyticsRecordingActivity => 'Atividade de gravação';

  @override
  String get analyticsLast7Days => 'Últimos 7 dias';

  @override
  String get analyticsWeekEmpty => 'Nenhuma gravação nos últimos 7 dias';

  @override
  String get analyticsModelUsage => 'Uso de modelos de voz';

  @override
  String get analyticsNoModelData =>
      'Ainda não há dados de modelos neste período';

  @override
  String get analyticsLoading => 'Carregando estatísticas';

  @override
  String get analyticsDurationDistribution => 'Distribuição de duração';

  @override
  String get analyticsCostSavings => 'Custos e economia';

  @override
  String get analyticsLocalSavings => 'Economia local';

  @override
  String get analyticsCloudCost => 'Custo na nuvem';

  @override
  String get analyticsEstimateNote =>
      'Estimativa com base nos preços de tabela por transcrição';

  @override
  String get analyticsPeriod7d => '7 dias';

  @override
  String get analyticsPeriod30d => '30 dias';

  @override
  String get analyticsPeriod90d => '90 dias';

  @override
  String get analyticsPeriodAll => 'Todo o período';

  @override
  String get analyticsReset => 'Redefinir';

  @override
  String get analyticsResetTitle => 'Redefinir estatísticas';

  @override
  String get analyticsResetMessage =>
      'Tem certeza de que deseja apagar todos os dados estatísticos? Esta ação não pode ser desfeita.';

  @override
  String get analyticsResetDone => 'As estatísticas foram redefinidas.';

  @override
  String get analyticsDayMon => 'Seg';

  @override
  String get analyticsDayTue => 'Ter';

  @override
  String get analyticsDayWed => 'Qua';

  @override
  String get analyticsDayThu => 'Qui';

  @override
  String get analyticsDayFri => 'Sex';

  @override
  String get analyticsDaySat => 'Sáb';

  @override
  String get analyticsDaySun => 'Dom';

  @override
  String analyticsThisWeek(String delta) {
    return '$delta nesta semana';
  }

  @override
  String analyticsVsLastMonth(String delta) {
    return '$delta em relação ao mês passado';
  }

  @override
  String get analyticsDurationLt15s => '< 15s';

  @override
  String get analyticsDuration15To30s => '15-30s';

  @override
  String get analyticsDuration30To60s => '30-60s';

  @override
  String get analyticsDuration1To3m => '1-3min';

  @override
  String get analyticsDurationGt3m => '> 3min';

  @override
  String analyticsSavedAmount(String amount) {
    return '$amount economizados';
  }

  @override
  String analyticsSpentAmount(String amount) {
    return '$amount gastos';
  }

  @override
  String get replacementsSearch => 'Pesquisar substituições…';

  @override
  String get replacementsSearchFieldLabel => 'Pesquisar substituições';

  @override
  String get replacementsAdd => 'Adicionar';

  @override
  String get replacementsEmpty => 'Nenhuma substituição ainda';

  @override
  String get replacementsEmptyHint =>
      'Adicione substituições para trocar palavras automaticamente enquanto você grava.\nExemplo: \"tbm\" → \"também\"';

  @override
  String get replacementsNoMatches => 'Nenhum resultado';

  @override
  String get replacementsNoMatchesHint => 'Tente outro termo de pesquisa.';

  @override
  String get replacementsToggleLabel => 'Ativar substituições';

  @override
  String get replacementsToggleEnabled => 'As substituições estão ativas';

  @override
  String get replacementsToggleDisabled => 'As substituições estão desativadas';

  @override
  String get replacementsEnableBannerTitle =>
      'As substituições estão desativadas';

  @override
  String get replacementsEnableBannerHint =>
      'Ative-as para que as frases-gatilho sejam substituídas automaticamente durante a gravação.';

  @override
  String get replacementsEnableAction => 'Ativar';

  @override
  String get replacementsDisableAction => 'Desativar';

  @override
  String get replacementsEditShortcut => 'Editar substituição';

  @override
  String get replacementsNewShortcut => 'Nova substituição';

  @override
  String get replacementsDialogHint =>
      'Qualquer uma das frases-gatilho será substituída automaticamente durante a gravação.';

  @override
  String get replacementsTriggerLabel => 'Frases-gatilho';

  @override
  String get replacementsTriggerHint => 'ex.: tbm';

  @override
  String get replacementsAddTrigger => 'Adicionar frase-gatilho';

  @override
  String get replacementsMissingTrigger =>
      'Adicione pelo menos uma frase-gatilho.';

  @override
  String get replacementsRemoveTrigger => 'Remover frase-gatilho';

  @override
  String get replacementsReplacementLabel => 'Texto de substituição';

  @override
  String get replacementsMissingReplacement =>
      'Digite o texto de substituição.';

  @override
  String get replacementsReplacementHint => 'ex.: também';

  @override
  String get replacementsReplacementHelper =>
      'Use \\n para uma quebra de linha e \\n\\n para uma linha em branco. Para manter uma barra invertida e n como texto, escreva \\\\n.';

  @override
  String get replacementsDeleteTitle => 'Excluir substituição';

  @override
  String replacementsDeleteMessage(String trigger) {
    return 'Remover a substituição \"$trigger\"? Isso não pode ser desfeito.';
  }

  @override
  String get replacementsImportFromFolder => 'Importar de uma pasta';

  @override
  String get replacementsImportHint =>
      'Procura identificadores em uma pasta de projeto e os adiciona como substituições semelhantes — nada sai do seu dispositivo.';

  @override
  String replacementsImportSummary(int found, int added, int skipped) {
    return 'Encontrados $found, adicionados $added, ignorados $skipped duplicado(s)';
  }

  @override
  String get replacementsImportScanning =>
      'Analisando a pasta — em projetos grandes, isso pode levar um momento…';

  @override
  String get replacementsImportError =>
      'Falha na importação — não foi possível analisar a pasta.';

  @override
  String get replacementsImportedBadge => 'Importado';

  @override
  String get replacementsLearnedBadge => 'Aprendido';

  @override
  String get correctionLearningToggleLabel => 'Aprender com correções';

  @override
  String get correctionLearningToggleEnabled =>
      'Observando correções repetidas para sugestões';

  @override
  String get correctionLearningToggleDisabled =>
      'Não observando correções para sugestões';

  @override
  String get correctionLearningHowTo =>
      'Ao gravar uma nota nas Gravações, diga “correct: …” (ou “korrektur: …”) seguido do texto corrigido para sobrescrevê-la. Corrija a mesma coisa duas vezes e o WhisPaste oferece isso aqui como substituição automática.';

  @override
  String get correctionCandidatesCardTitle =>
      'Sugerido a partir das suas correções';

  @override
  String correctionCandidatesCardHint(int count) {
    return '$count sugestão(ões) de correções repetidas — revise antes que virem substituições.';
  }

  @override
  String get correctionCandidatesReviewButton => 'Revisar';

  @override
  String get correctionCandidatesReviewTitle => 'Revisar correções aprendidas';

  @override
  String correctionCandidatesReviewSubtitle(int count) {
    return '$count correção(ões) que você repetiu — aceite as que o WhisPaste deve aplicar automaticamente daqui em diante. Nada muda até você confirmar.';
  }

  @override
  String correctionCandidatesCommitSummary(int added) {
    return '$added substituição(ões) aprendida(s) adicionada(s)';
  }

  @override
  String get replacementsImportNothingFound =>
      'Nenhum identificador novo encontrado nesta pasta.';

  @override
  String get replacementsSymbolPackAction => 'Adicionar modelos de símbolos';

  @override
  String get replacementsSymbolPackHint =>
      'Adiciona substituições para símbolos que você pode ditar, como «open bracket» para (. Os gatilhos existentes permanecem.';

  @override
  String replacementsSymbolPackAdded(int count) {
    return 'Regras de símbolos adicionadas: $count';
  }

  @override
  String get replacementsSymbolPackNothingNew =>
      'Os modelos de símbolos já existem.';

  @override
  String get replacementsImportReviewTitle => 'Escolha o que importar';

  @override
  String replacementsImportReviewSubtitle(int count) {
    return '$count candidatos encontrados — escolha quais viram substituições. Nada é adicionado até você confirmar.';
  }

  @override
  String get replacementsImportReviewSearchHint => 'Filtrar candidatos';

  @override
  String get replacementsImportReviewSelectAllFiltered =>
      'Selecionar todos os exibidos';

  @override
  String get replacementsImportReviewDeselectAll => 'Desmarcar todos';

  @override
  String replacementsImportReviewSelectedCount(int selected, int total) {
    return '$selected de $total selecionados';
  }

  @override
  String get replacementsImportReviewNoMatches =>
      'Nenhum candidato corresponde ao seu filtro.';

  @override
  String replacementsImportReviewImportButton(int count) {
    return 'Importar selecionados ($count)';
  }

  @override
  String get replacementsMatchModeLabel => 'Correspondência';

  @override
  String get replacementsMatchModeExact => 'Exata';

  @override
  String get replacementsMatchModeFuzzy => 'Semelhante';

  @override
  String get replacementsFuzzyToleranceLabel => 'Tolerância';

  @override
  String get replacementsFuzzyToleranceStrict => 'Rigorosa';

  @override
  String get replacementsFuzzyToleranceStandard => 'Padrão';

  @override
  String get replacementsFuzzyToleranceTolerant => 'Tolerante';

  @override
  String get replacementsFuzzyToleranceHint =>
      'Quão parecida com um gatilho uma frase falada precisa soar para ainda contar como correspondência. A «Rigorosa» só pega formulações quase idênticas, então quase nada é substituído por acidente, mas um gatilho mal pronunciado pode passar sem correspondência. O «Padrão» é um equilíbrio para o uso do dia a dia. A «Tolerante» também pega pronúncias ou formulações bem diferentes, com maior risco de corresponder a algo que você não queria substituir.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Frases-gatilho com menos de $minLength caracteres não podem usar correspondência semelhante — gerariam acertos falsos demais.';
  }

  @override
  String replacementsSingleSymbolTriggerHint(String smiley, String ellipsis) {
    return 'Um único sinal de pontuação nunca é substituído. Use pelo menos dois caracteres, por ex. “$smiley” ou “$ellipsis”.';
  }

  @override
  String replacementsDuplicateTrigger(String trigger, String replacement) {
    return 'O gatilho «$trigger» já existe (substituição: «$replacement»).';
  }

  @override
  String get snippetsSearch => 'Pesquisar snippets…';

  @override
  String get snippetsSearchFieldLabel => 'Pesquisar snippets';

  @override
  String get snippetsAdd => 'Adicionar';

  @override
  String get snippetCopySuffix => '(cópia)';

  @override
  String get snippetsEmpty => 'Nenhum snippet ainda';

  @override
  String get snippetsEmptyHint =>
      'Adicione um snippet para reutilizar rapidamente um bloco de texto, como uma assinatura ou uma resposta padrão.';

  @override
  String get snippetsNoMatches => 'Nada encontrado';

  @override
  String get snippetsNoMatchesHint => 'Tente outro termo de pesquisa.';

  @override
  String get snippetsEditSnippet => 'Editar snippet';

  @override
  String get snippetsNewSnippet => 'Novo snippet';

  @override
  String get snippetsDialogHint =>
      'Abra o seletor de snippets durante a gravação para inserir este texto.';

  @override
  String get snippetsTitleLabel => 'Título';

  @override
  String get snippetsTitleHint => 'ex.: Assinatura de e-mail';

  @override
  String get snippetsBodyLabel => 'Texto';

  @override
  String get snippetsBodyHint => 'O texto que este snippet insere…';

  @override
  String get snippetsKindLabel => 'Tipo';

  @override
  String get snippetsKindStatic => 'Estático';

  @override
  String get snippetsKindInteractive => 'Interativo';

  @override
  String get snippetsFieldsLabel => 'Campos';

  @override
  String get snippetsFieldsHint =>
      'Você será guiado por cada campo, nesta ordem, com uma gravação curta própria.';

  @override
  String snippetsFieldNameHint(int number) {
    return 'Nome do campo $number';
  }

  @override
  String get snippetsFieldMoveUp => 'Mover campo para cima';

  @override
  String get snippetsFieldMoveDown => 'Mover campo para baixo';

  @override
  String get snippetsFieldRemove => 'Remover campo';

  @override
  String get snippetsFieldAdd => 'Adicionar campo';

  @override
  String get snippetsFieldInsertIntoTemplate => 'Inserir no modelo';

  @override
  String snippetsFieldsMinWarning(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min campos nomeados',
      one: '1 campo nomeado',
    );
    return 'Um snippet interativo precisa de pelo menos $_temp0.';
  }

  @override
  String get snippetsTemplateLabel => 'Modelo';

  @override
  String get snippetsTemplateHint =>
      'Escreva o texto do snippet e use o botão de cada campo para posicioná-lo onde quiser.';

  @override
  String get snippetsTemplateFieldHint =>
      'Escreva seu texto aqui e insira os campos com os botões acima.';

  @override
  String get snippetsTemplateMissingFieldsWarning =>
      'Nem todos os campos aparecem no modelo ainda — o texto para eles não seria usado.';

  @override
  String get snippetsSaveMissingTitle => 'Falta o título';

  @override
  String get snippetsSaveMissingBody => 'Falta o texto';

  @override
  String get snippetsFieldsDuplicateWarning =>
      'Cada campo precisa de um nome diferente.';

  @override
  String get snippetsInteractiveBadge => 'Interativo';

  @override
  String interactiveSnippetBriefingLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campos',
      one: '1 campo',
    );
    return '$_temp0 · Enter para começar';
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
  String get interactiveSnippetAnnounceHint => 'Prepare-se para falar…';

  @override
  String interactiveSnippetSpeakNowLabel(String name, int index, int count) {
    return '$index/$count: $name';
  }

  @override
  String get interactiveSnippetAdvance => 'Próximo';

  @override
  String interactiveSnippetSentenceLabel(String names) {
    return 'Numa frase: $names';
  }

  @override
  String get interactiveSnippetAssigningLabel => 'A preencher os campos…';

  @override
  String get interactiveSnippetAssigningHint => 'Esc: cancelar';

  @override
  String get snippetsDeleteTitle => 'Excluir snippet';

  @override
  String snippetsDeleteMessage(String title) {
    return 'Remover o snippet \"$title\"? Isso não pode ser desfeito.';
  }

  @override
  String get snippetsPickerTriggerLabel => 'Palavra-gatilho do seletor';

  @override
  String get snippetsPickerTriggerSubtitle =>
      'Diga apenas esta palavra para abrir o seletor de snippets. Deixe em branco para desativar o seletor.';

  @override
  String get snippetsPickerTriggerHint => 'ex.: snippet';

  @override
  String get snippetsPickerTriggerEmptyListHint =>
      'A palavra-gatilho está definida, mas ainda não há snippets — ditá-la insere a palavra como texto comum até você adicionar o primeiro snippet.';

  @override
  String get snippetsPickerSettingsLink =>
      'Palavra-gatilho e atalho nas Configurações';

  @override
  String get snippetsPickerHotkeyLabel => 'Atalho do seletor';

  @override
  String get snippetsPickerHotkeySubtitle =>
      'Abre o seletor imediatamente — a segunda forma de chegar ao mesmo painel.';

  @override
  String get snippetsPickerHotkeyOff => 'O atalho do seletor está desativado.';

  @override
  String get snippetsPickerHotkeyEnable => 'Ativar atalho';

  @override
  String get snippetsPickerUnavailable =>
      'O seletor de snippets ainda não está disponível nesta plataforma.';

  @override
  String get snippetsPickerSemanticsLabel => 'Seletor de snippets';

  @override
  String get snippetsPickerInsertAction => 'Inserir';

  @override
  String get snippetsPickerSentenceAction => 'Numa frase';

  @override
  String get snippetsPickerSentenceTooltip =>
      'Ditar todos os campos numa frase';

  @override
  String snippetFieldPreviewAnnounce(int filled, int total) {
    return 'Pré-visualização: $filled de $total campos reconhecidos';
  }

  @override
  String snippetFieldPreviewConfirmEmpty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campos vazios · Enter insere mesmo assim',
      one: '1 campo vazio · Enter insere mesmo assim',
    );
    return '$_temp0';
  }

  @override
  String get snippetFieldPreviewEmpty => 'vazio';

  @override
  String get snippetFieldPreviewNextField => 'Campo seguinte';

  @override
  String get snippetFieldPreviewResult => 'Resultado';

  @override
  String snippetFieldPreviewNoModelHint(String example) {
    return 'Sem modelo de texto, o WhisPaste reconhece os campos apenas pelo nome. Diga-os também, por exemplo: $example';
  }

  @override
  String get aboutTagline => 'Voz para texto, na hora.';

  @override
  String get aboutWhatsNew => 'Novidades';

  @override
  String get aboutReportIssue => 'Relatar problema';

  @override
  String get aboutSupportTitle => 'Apoie este projeto';

  @override
  String get aboutSupportDescription =>
      'O WhisPaste é gratuito e de código aberto sob a licença MIT. Os patrocínios cobrem custos fixos recorrentes reais (Apple Developer Program, Microsoft Partner Center, hospedagem e domínio) que mantêm o app disponível em todas as plataformas.';

  @override
  String get aboutGitHubSponsors => 'GitHub Sponsors';

  @override
  String get aboutKofi => 'Ko-fi';

  @override
  String get aboutStarOnGitHub => 'Dar estrela no GitHub';

  @override
  String get aboutSponsorsTitle => 'Apoiadores';

  @override
  String get supportPromptRecurringTitle => 'Tornar mensal?';

  @override
  String get supportPromptRecurringDescription =>
      'Obrigado por já ter apoiado o WhisPaste antes. Se quiser, você pode transformar isso em um pequeno patrocínio mensal que continua cobrindo nossos custos fixos recorrentes.';

  @override
  String get aboutBuiltWith => 'Feito com';

  @override
  String get aboutFlutterGo => 'Flutter';

  @override
  String get aboutFlutterGoDesc =>
      'Interface multiplataforma com Flutter. Reconhecimento de voz local via whisper.cpp e Parakeet.';

  @override
  String get aboutWhisper => 'whisper.cpp e OpenAI Whisper';

  @override
  String get aboutWhisperDesc =>
      'Reconhecimento de voz local e na nuvem: rápido, preciso, multilíngue (99 idiomas).';

  @override
  String get aboutParakeet => 'NVIDIA Parakeet e sherpa-onnx';

  @override
  String get aboutParakeetDesc =>
      'Reconhecimento de voz local, acelerado por GPU quando disponível (Metal, Vulkan, CUDA) e por CPU nos demais casos (~25 idiomas).';

  @override
  String get aboutParakeetModelCredit =>
      'Modelo: NVIDIA parakeet-tdt-0.6b-v3, CC-BY-4.0';

  @override
  String get aboutParakeetGgufCredit => 'Conversão GGUF: ggml-org, MIT';

  @override
  String get aboutLinks => 'Links';

  @override
  String get helpLegalTitle => 'Informações legais';

  @override
  String get helpDiagnosticsPublicNote =>
      'As issues do GitHub são públicas. Verifique o relatório antes de colá-lo.';

  @override
  String get helpDiagnosticsBuilding => 'Criando o relatório …';

  @override
  String get tabsScrollBack => 'Mostrar abas anteriores';

  @override
  String get tabsScrollForward => 'Mostrar mais abas';

  @override
  String get aboutWebsite => 'Site';

  @override
  String get aboutGitHubRepo => 'Repositório no GitHub';

  @override
  String get aboutFollowOnX => 'Siga no X';

  @override
  String get aboutMitLicense => 'Licença MIT';

  @override
  String get aboutThirdPartyLicenses => 'Licenças de terceiros';

  @override
  String get aboutThirdPartyLicensesDetail => 'Fontes e modelos';

  @override
  String get aboutPrivacyPolicy => 'Política de privacidade';

  @override
  String get aboutImprint => 'Aviso legal';

  @override
  String get aboutSystemInfo => 'Informações do sistema';

  @override
  String get aboutSystemInfoDesc =>
      'Copie um resumo compacto de diagnóstico para relatórios de bugs.';

  @override
  String get aboutDiagnosticsContentsTitle => 'O que o relatório contém';

  @override
  String get aboutDiagnosticsContentsDesc =>
      'Versão do app, sistema operacional, caminho do programa sem o seu nome de usuário, modelo de voz (varianter, modelo, estado, último erro), GPU, arquivos de modelo e as últimas 40 linhas do registro. Chaves e tokens são ocultados nas linhas do registro.';

  @override
  String get aboutDiagnosticsPreviewShow => 'Mostrar';

  @override
  String get aboutDiagnosticsPreviewHide => 'Ocultar';

  @override
  String aboutDiagnosticsIncomplete(String error) {
    return 'Diagnóstico incompleto: $error';
  }

  @override
  String get aboutCopyDebugInfo => 'Copiar informações de depuração';

  @override
  String get aboutCopied => 'Copiado!';

  @override
  String get aboutMadeWith => 'Feito com ♥ pelo WhisPaste';

  @override
  String get aboutOpenSource => 'Código aberto sob a licença MIT';

  @override
  String get feedbackSubtitle =>
      'Ajude a melhorar o WhisPaste. Cada opinião conta.';

  @override
  String get feedbackCategoryLabel => 'Sobre o que se trata?';

  @override
  String get feedbackRatingLabel =>
      'Como você está se sentindo com o WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Conte mais';

  @override
  String get feedbackContactEmailLabel => 'E-mail (opcional)';

  @override
  String get feedbackContactEmailExplanation =>
      'Somente se quiser receber uma resposta. Usaremos apenas para acompanhar esta mensagem, nunca para marketing, e ele é excluído após 90 dias.';

  @override
  String get feedbackContactEmailPlaceholder => 'voce@exemplo.com';

  @override
  String get feedbackContactEmailInvalid =>
      'Digite um endereço de e-mail válido ou deixe o campo vazio.';

  @override
  String get feedbackContactLanguageLabel => 'Responder em';

  @override
  String get feedbackContactLanguageHint =>
      'Em qual idioma devemos responder caso entremos em contato?';

  @override
  String get feedbackSubmit => 'Enviar feedback';

  @override
  String feedbackSubmitMissing(String what) {
    return 'Para enviar, $what.';
  }

  @override
  String get feedbackMissingCategory => 'escolha do que se trata';

  @override
  String get feedbackMissingRating =>
      'avalie como você se sente com o WhisPaste';

  @override
  String get feedbackMissingComment => 'escreva uma mensagem';

  @override
  String get feedbackMissingEmail =>
      'corrija o endereço de e-mail ou deixe o campo vazio';

  @override
  String get feedbackRequiredMarker => 'Obrigatório';

  @override
  String get feedbackPublishConsentLabel =>
      'Permito que o meu feedback apareça de forma anónima como citação no site.';

  @override
  String get feedbackPublishConsentExplanation =>
      'Desligado por padrão. Só são mostrados o seu texto e a sua avaliação, nunca o seu nome ou e-mail. Pode retirar esta autorização a qualquer momento com um clique na página Feedback da app.';

  @override
  String get feedbackPublishReviewHint =>
      'As citações são escritas como uma avaliação: o que gosta e o que ainda pode melhorar. Erros e ideias vão em «Problema» ou «Ideia» e nunca são publicados.';

  @override
  String get feedbackWithdrawConsentLabel => 'Retirar consentimento';

  @override
  String get feedbackWithdrawConsentHelp =>
      'Aplica-se aos feedbacks enviados com consentimento a partir deste dispositivo. A citação desaparece do site em cerca de 24 horas.';

  @override
  String get feedbackWithdrawConsentPending =>
      'A retirada está guardada e será enviada quando o WhisPaste estiver a correr com ligação à internet (até 30 dias); caso contrário, retire por e-mail.';

  @override
  String get feedbackWithdrawNoCode =>
      'Não há nenhum código de retirada guardado neste dispositivo – retire por e-mail';

  @override
  String feedbackWithdrawEntrySending(Object date) {
    return 'A retirada de $date está a ser enviada…';
  }

  @override
  String feedbackWithdrawEntryFailed(Object date) {
    return 'Retirada de $date não entregue – retire por e-mail';
  }

  @override
  String get feedbackWithdrawConsentUndelivered =>
      'Não foi possível entregar a retirada – retire por e-mail.';

  @override
  String get feedbackWithdrawEmailLabel => 'Retirar por e-mail';

  @override
  String get feedbackWithdrawEmailSubject =>
      'Retirar o meu consentimento para citar o meu feedback';

  @override
  String get feedbackWithdrawEmailBody =>
      'Por favor, retire o meu consentimento para citar o meu feedback.';

  @override
  String get feedbackWithdrawEmailDateLabel => 'Data do feedback:';

  @override
  String get feedbackWithdrawEmailReferenceLabel => 'Referência da retirada:';

  @override
  String get feedbackWithdrawEmailSentLabel => 'Enviei o e-mail';

  @override
  String get feedbackWithdrawEmailLaunchFailed =>
      'Nenhuma app de e-mail encontrada. Envie a mensagem preparada para este endereço:';

  @override
  String get feedbackWithdrawEmailCopyLabel => 'Copiar endereço e mensagem';

  @override
  String get feedbackWithdrawEmailCopied => 'Endereço e mensagem copiados.';

  @override
  String get feedbackWithdrawLocked =>
      'O armazenamento de credenciais do sistema não pode ser lido neste momento. O WhisPaste não consegue enviar os consentimentos e retiradas guardados lá. Retire por e-mail; o e-mail preparado contém as referências necessárias.';

  @override
  String get feedbackWithdrawConsentDone =>
      'Retirada enviada. A citação desaparece do site em cerca de 24 horas, na próxima atualização diária.';

  @override
  String get feedbackPrivacyNote =>
      'Anônimo por padrão; só é identificável se você informar seu e-mail acima.';

  @override
  String get feedbackThankYou => 'Obrigado!';

  @override
  String get feedbackThankYouMessage =>
      'Seu feedback ajuda a tornar o WhisPaste melhor\npara todos.';

  @override
  String get feedbackSendAnother => 'Enviar outro';

  @override
  String get feedbackRatingFrustrated => 'Frustrado';

  @override
  String get feedbackRatingMeh => 'Mais ou menos';

  @override
  String get feedbackRatingOkay => 'Ok';

  @override
  String get feedbackRatingHappy => 'Feliz';

  @override
  String get feedbackRatingLoveIt => 'Adorei!';

  @override
  String get feedbackSubmitting => 'Enviando…';

  @override
  String get feedbackErrorRateLimited =>
      'Você já enviou feedback recentemente. Tente novamente mais tarde.';

  @override
  String get feedbackErrorNetwork =>
      'Não foi possível conectar ao servidor. Verifique sua conexão com a internet.';

  @override
  String get feedbackErrorServer =>
      'Algo deu errado. Tente novamente mais tarde.';

  @override
  String get feedbackErrorNotConfigured =>
      'O feedback não está disponível nesta versão.';

  @override
  String get statusBarOnDevice => 'No dispositivo';

  @override
  String get statusBarOverlayFloating => 'Overlay: flutuante';

  @override
  String get statusBarOverlayOff => 'Overlay: desativado';

  @override
  String get statusBarAfterCopy => 'Depois: copiar';

  @override
  String get statusBarAfterPaste => 'Depois: colar';

  @override
  String get statusBarAfterBoth => 'Depois: copiar e colar';

  @override
  String get statusBarAfterNothing => 'Depois: manual';

  @override
  String get dockOutputCopy => 'Copiar';

  @override
  String get dockOutputPaste => 'Colar';

  @override
  String get dockOutputBoth => 'Copiar e colar';

  @override
  String get dockOutputNothing => 'Manual';

  @override
  String get sttStatusStarting => 'Iniciando…';

  @override
  String get sttStatusReady => 'Pronto';

  @override
  String get sttStatusError => 'Erro';

  @override
  String get statusBarSttTooltip => 'Status do modelo de voz';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'O reconhecimento roda em: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'A utilização real da GPU não pode ser medida em todas as plataformas sem privilégios elevados; a porcentagem exibida reflete a atividade de CPU deste processo.';

  @override
  String get statusBarRecording => 'Gravando…';

  @override
  String get statusBarTranscribing => 'Processando…';

  @override
  String get statusBarRefining => 'Processando…';

  @override
  String get statusBarHotkeyTooltip => 'Atalho global: clique para configurar';

  @override
  String get statusBarAutoPasteOffHint => 'Ativar Auto-Paste…';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'O Auto-Paste está desativado no momento. Clique para abrir as Configurações.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Dispensar';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'Automação: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'Automação: erro';

  @override
  String statusBarAutomationApiTooltip(int port) {
    return 'API de automação ativa na porta $port';
  }

  @override
  String statusBarAutomationApiTooltipFallback(int port, int requestedPort) {
    return 'API de automação ativa na porta $port (a porta $requestedPort estava em uso)';
  }

  @override
  String get statusBarAutomationApiTooltipError =>
      'API de automação: nenhuma porta livre encontrada';

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
  String get shortcutKeySpace => 'Espaço';

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
  String get modelServerReady => 'Modelo de voz pronto';

  @override
  String get modelServerMissing => 'Modelo de voz não instalado';

  @override
  String get modelServerWhisper => 'Modelo de voz local';

  @override
  String get modelReady => 'Pronto';

  @override
  String get modelDownloadComplete => 'Modelo pronto para uso';

  @override
  String get modelUse => 'Usar';

  @override
  String get modelDownload => 'Baixar';

  @override
  String get modelDownloading => 'Baixando…';

  @override
  String get modelDownloadingEngine => 'Preparando o modelo de voz…';

  @override
  String get modelVerifying => 'Verificando…';

  @override
  String get modelExtracting => 'Extraindo…';

  @override
  String get modelDeleteConfirm => 'Excluir este modelo de voz?';

  @override
  String get modelDeleteConfirmMessage =>
      'O arquivo do modelo de voz é excluído deste dispositivo. Você pode baixá-lo novamente a qualquer momento.';

  @override
  String get modelTierDeleteConfirm => 'Excluir estes modelos?';

  @override
  String modelTierDeleteConfirmMessage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count modelos ($size) são excluídos deste dispositivo. Você pode baixá-los novamente a qualquer momento.',
      one:
          '1 modelo ($size) é excluído deste dispositivo. Você pode baixá-lo novamente a qualquer momento.',
    );
    return '$_temp0';
  }

  @override
  String get qualityTierCompactLabel => 'Rápido';

  @override
  String get qualityTierCompactDesc =>
      'Resultados rápidos, download pequeno. Ótimo para notas curtas e mensagens rápidas.';

  @override
  String get qualityTierBalancedLabel => 'Equilibrado';

  @override
  String get qualityTierBalancedDesc =>
      'Preciso e confiável para gravações do dia a dia. Funciona na maioria dos dispositivos.';

  @override
  String get qualityTierPremiumLabel => 'Preciso';

  @override
  String get qualityTierPremiumDesc =>
      'Máxima precisão para gravações longas e conteúdo complexo. Requer uma GPU potente.';

  @override
  String get qualityTierRecommended => 'Recomendado para o seu dispositivo';

  @override
  String get qualityTierRecommendedMeasured => 'Medido para o seu dispositivo';

  @override
  String qualityTierDownloadSize(String size) {
    return 'Download de $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Baixar modelo de voz';

  @override
  String get qualityTierChooseDifferent => 'Escolher outro nível';

  @override
  String get qualityTierActive => 'Ativo';

  @override
  String get qualityTierInfoSlow =>
      'Preciso, leva bem mais tempo para processar neste computador';

  @override
  String get qualityTierInfoSlowEstimate =>
      'Preciso, provavelmente leva bem mais tempo neste computador (estimativa)';

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Preciso, cerca de ${ratio}x mais lento que o Rápido';
  }

  @override
  String get qualityTierInfoModerate =>
      'Bom equilíbrio entre velocidade e qualidade';

  @override
  String get qualityTierBenchmarkReRun => 'Executar benchmark novamente';

  @override
  String get qualityTierBenchmarkRun => 'Executar benchmark';

  @override
  String get qualityTierInfoBenchmarking => 'Testando desempenho…';

  @override
  String get benchmarkRowSubtitle =>
      'Mede a velocidade de cada nível instalado neste computador. Os resultados definem as dicas de velocidade e a recomendação.';

  @override
  String benchmarkRunningStep(int step, int total, String tier) {
    return 'Em execução… passo $step de $total: $tier';
  }

  @override
  String get benchmarkCancel => 'Cancelar teste';

  @override
  String get benchmarkCancelled =>
      'Teste cancelado. Os níveis já medidos foram salvos.';

  @override
  String benchmarkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count níveis medidos',
      one: '1 nível medido',
    );
    return 'Medição concluída: $_temp0.';
  }

  @override
  String benchmarkLastMeasured(String when) {
    return 'Última medição: $when';
  }

  @override
  String benchmarkBackendLine(String backend) {
    return 'Caminho de cálculo: $backend';
  }

  @override
  String get benchmarkBackendCpu => 'Processador (CPU)';

  @override
  String benchmarkBackendGpu(String name) {
    return 'Placa de vídeo ($name)';
  }

  @override
  String benchmarkTierResult(String tier, String seconds) {
    return '$tier: $seconds s de processamento por segundo de áudio';
  }

  @override
  String get benchmarkNoResult =>
      'Ainda não há medição. Execute o teste para obter dicas de velocidade para este computador.';

  @override
  String get benchmarkStaleNotice =>
      'Estes resultados são de outro computador ou de uma versão anterior. Serão medidos novamente em segundo plano.';

  @override
  String get benchmarkParakeetNotMeasured =>
      'A medição vale para os modelos Whisper. O Parakeet não é medido.';

  @override
  String benchmarkRecommendation(String tier) {
    return 'Recomendado após a medição: $tier';
  }

  @override
  String benchmarkSwitchTo(String tier) {
    return 'Mudar para $tier';
  }

  @override
  String get benchmarkErrorBusy =>
      'O teste não pode rodar durante uma gravação. Inicie-o novamente depois.';

  @override
  String get benchmarkErrorNoModel =>
      'Nenhum nível está instalado. Baixe um modelo de voz primeiro.';

  @override
  String get benchmarkErrorFailed => 'Não foi possível concluir o teste.';

  @override
  String get benchmarkRetry => 'Tentar novamente';

  @override
  String get qualityTierActionOverride => 'Usar mesmo assim';

  @override
  String get qualityTierActionOverrideHint => 'Usar este nível apesar do aviso';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String get settingsQualityBasic => 'Básico';

  @override
  String get settingsQualityBalanced => 'Equilibrado';

  @override
  String get settingsQualityHigh => 'Alta qualidade';

  @override
  String get settingsQualityBest => 'Preciso';

  @override
  String get settingsQualityMaximum => 'Máxima precisão';

  @override
  String get settingsQualityRecommended => '★ Recomendado';

  @override
  String get settingsModelStatusReady => 'Modelo de voz pronto';

  @override
  String get settingsModelStatusNeeded =>
      'O modelo de voz será baixado quando você iniciar a gravação';

  @override
  String get settingsModelStatusDownloading => 'Baixando modelo de voz…';

  @override
  String get settingsAdvancedModelManagement =>
      'Configurações avançadas do modelo de voz';

  @override
  String get infoEngineDownloading =>
      'O modelo de voz está sendo preparado. Aguarde um instante.';

  @override
  String get infoModelMissing =>
      'Baixe primeiro um modelo de voz em Configurações.';

  @override
  String infoModelMissingSelected(String size) {
    return 'O modelo de voz selecionado ($size) ainda não foi baixado.';
  }

  @override
  String get infoModelMissingDownload => 'Baixar agora';

  @override
  String get statusBarModelMissing => 'Modelo de voz ausente';

  @override
  String statusBarModelDownloading(int percent) {
    return 'Baixando modelo de voz… $percent %';
  }

  @override
  String get modelDownloadAction => 'Baixar';

  @override
  String get modelMissingDownloadAction => 'Ausente: baixar';

  @override
  String get infoPipelineBusy =>
      'O WhisPaste ainda está ocupado com a gravação anterior.';

  @override
  String get infoSnippetPickerEmpty =>
      'Você ainda não tem snippets. Crie um e o seletor vai abrir.';

  @override
  String get infoSnippetPickerEmptyAction => 'Abrir snippets';

  @override
  String get oomRecoveryTitle =>
      'Gravação cancelada: falta memória na placa de vídeo';

  @override
  String get oomRecoveryMessage =>
      'Sua GPU ficou sem memória. Escolha como prosseguir:';

  @override
  String get oomRecoveryTrySmaller => 'Tentar modelo de voz menor';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Mudar para $model e tentar a gravação novamente';
  }

  @override
  String get oomRecoverySwitchCloud => 'Mudar para a nuvem';

  @override
  String get oomRecoverySwitchCloudHint => 'Usar modelo de voz na nuvem';

  @override
  String oomRecoveryCloudNotice(String provider) {
    return 'As gravações são então enviadas para $provider.';
  }

  @override
  String get oomRecoveryCancel => 'Cancelar';

  @override
  String get oomRecoveryPermanentTitle => 'Modelo de voz local indisponível';

  @override
  String get oomRecoveryPermanentMessage =>
      'Todos os modelos locais falharam por limites de memória da GPU. Mude para o modelo de voz na nuvem nas configurações.';

  @override
  String get oomRecoveryPermanentCloud => 'Abrir configurações';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Mudando para $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Mudando para o modelo de voz na nuvem…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'O modelo de voz $model também falhou. Tentando a próxima opção…';
  }

  @override
  String get oomRecoveryNoSmallerModel =>
      'Nenhum modelo menor está disponível. Escolha outro modelo em Configurações ou use o reconhecimento de voz na nuvem.';

  @override
  String get infoSttCudaOomFallbackModel =>
      'Qualidade reduzida: sua GPU ficou sem memória. Mudado para um modelo de voz mais leve.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Sua GPU ficou sem memória. Mudado para o modo CPU para mais estabilidade.';

  @override
  String get errorSttServerConnectionLost =>
      'O modelo de voz parou inesperadamente. Tente novamente.';

  @override
  String get errorSttCudaOom =>
      'Sua GPU ficou sem memória. A qualidade foi reduzida para que a próxima tentativa funcione.';

  @override
  String get errorCloudAuth =>
      'A chave de API da nuvem está ausente ou é inválida. Verifique em Configurações → Reconhecimento de voz.';

  @override
  String get errorCloudQuota =>
      'Limite de requisições do provedor na nuvem atingido. Aguarde um instante e tente novamente.';

  @override
  String get errorCloudTimeoutLocal =>
      'O serviço na nuvem demorou demais para responder. Verifique sua conexão ou dite offline com o modelo local.';

  @override
  String get errorCloudTimeout =>
      'O serviço na nuvem demorou demais para responder. Verifique sua conexão e tente novamente.';

  @override
  String get errorCloudNetworkLocal =>
      'Não foi possível conectar ao serviço na nuvem. Verifique sua conexão com a internet ou dite offline com o modelo local.';

  @override
  String get errorCloudNetwork =>
      'Não foi possível conectar ao serviço na nuvem. Verifique sua conexão com a internet e tente novamente.';

  @override
  String get errorQuickNoteAppendFailed =>
      'Não foi possível salvar a nota rápida, então o texto não foi adicionado. Copie o texto e cole-o na nota.';

  @override
  String get errorOnboardingNotCompleted =>
      'Conclua primeiro o assistente de configuração.';

  @override
  String get errorSttModelNotFound =>
      'Modelo de voz não encontrado. Baixe-o em Configurações.';

  @override
  String get errorSttModelLoadFailed =>
      'Não foi possível carregar o modelo de voz. Reinicie o WhisPaste. Se continuar falhando, baixe o modelo de voz novamente nas configurações.';

  @override
  String get errorSttModelFileMissing =>
      'O arquivo do modelo de voz não foi encontrado. Baixe o modelo de voz nas configurações.';

  @override
  String get errorSttModelCorrupted =>
      'O arquivo do modelo de voz está danificado. Baixe o modelo de voz novamente nas configurações.';

  @override
  String get errorSttEngineRestartNeeded =>
      'O motor de voz ainda está ocupado com um ditado anterior. Reinicie o WhisPaste para usá-lo novamente.';

  @override
  String get pendingRetryFailed =>
      'A nova transcrição falhou. A gravação fica guardada para mais uma tentativa.';

  @override
  String get pendingRetryExpired =>
      'O prazo de retenção expirou. A gravação foi excluída e já não pode ser transcrita.';

  @override
  String get errorSttModelUnknown =>
      'Modelo de voz desconhecido. Selecione um modelo válido em Configurações.';

  @override
  String get errorRecordingFailed =>
      'Não foi possível iniciar a gravação, tente novamente';

  @override
  String get errorNoAudioRecorded => 'Nenhum áudio gravado, tente novamente';

  @override
  String get errorTranscriptionEmpty =>
      'A transcrição retornou texto vazio, tente novamente';

  @override
  String get errorSttServerFailed => 'O modelo de voz não conseguiu iniciar';

  @override
  String get errorSttModelCorruptedRedownloading =>
      'O modelo de voz parece corrompido. Baixando uma cópia nova automaticamente.';

  @override
  String get errorSttDllMissing =>
      'Um componente obrigatório do sistema está ausente. Tentando novamente no modo CPU.';

  @override
  String get errorSttGpuFatal =>
      'A aceleração por GPU falhou. Tentando novamente no modo CPU.';

  @override
  String get errorSttHeapCorruption =>
      'Ocorreu um erro de memória. Tentando novamente no modo CPU.';

  @override
  String get errorSttCpuFallbackFailed =>
      'O modelo de voz falhou na GPU e na CPU. Reinicie o app ou baixe o modelo de voz novamente.';

  @override
  String get errorPipelineTimeout =>
      'A gravação demorou demais. Tente uma gravação mais curta.';

  @override
  String get errorWavFileNotCreated =>
      'Não foi possível salvar o arquivo de áudio. Tente novamente.';

  @override
  String get errorWavFileEmpty =>
      'Nenhum áudio foi capturado. Verifique seu microfone.';

  @override
  String get errorSttStartTimeout =>
      'O modelo de voz ainda está iniciando. Tente novamente em instantes.';

  @override
  String get errorTranscriptionTimeout =>
      'A transcrição demorou demais. Tente uma gravação mais curta.';

  @override
  String get errorMicPermissionDenied =>
      'É necessário acesso ao microfone. Permita-o nas configurações do sistema.';

  @override
  String get errorRecordingStartFailed =>
      'Não foi possível iniciar a gravação. Tente novamente.';

  @override
  String get errorNoMicrophone =>
      'Nenhum microfone encontrado. Conecte um microfone e tente novamente.';

  @override
  String get errorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get modelDownloadFailed =>
      'Falha no download. Verifique sua conexão com a internet.';

  @override
  String modelDownloadDiskSpaceShort(String needed, String free) {
    return 'Espaço em disco insuficiente para este download: necessário $needed / livre $free. O download não foi iniciado.';
  }

  @override
  String get modelDeleteInUse =>
      'O arquivo do modelo de voz está em uso por outro programa e não pôde ser excluído. Feche-o e tente novamente.';

  @override
  String get downloadTlsError =>
      'Não foi possível verificar a conexão segura com o servidor de download. Verifique a data e a hora do dispositivo ou um programa que analisa conexões (antivírus ou proxy) e tente novamente.';

  @override
  String get statusSttLoading => 'Carregando modelo de voz…';

  @override
  String get statusSttReady => 'Modelo de voz pronto';

  @override
  String get modelDownloadFailedChecksum =>
      'O arquivo baixado estava corrompido e foi removido. Baixe-o novamente.';

  @override
  String get modelDownloadFailedStorage =>
      'Não foi possível salvar o arquivo. Verifique se há espaço livre suficiente no disco.';

  @override
  String get modelDownloadFailedUnknown =>
      'Falha no download. Tente novamente.';

  @override
  String get onboardingModelDownloadCancel => 'Cancelar download';

  @override
  String get onboardingModelDiskSpaceTitle => 'Pouco espaço em disco';

  @override
  String onboardingModelDiskSpaceBody(String needed, String free) {
    return 'O modelo de voz precisa de $needed, mas só há $free livres. O download provavelmente vai falhar.';
  }

  @override
  String get onboardingModelDiskSpaceContinue => 'Baixar mesmo assim';

  @override
  String get historyDuplicate => 'Duplicar';

  @override
  String get historyDuplicated => 'Entrada duplicada';

  @override
  String get historyTakeAsNote => 'Usar como nota';

  @override
  String get historyTakenAsNote => 'Transformado em nota';

  @override
  String get historyOpenNote => 'Abrir';

  @override
  String get historyViewRaw => 'Original';

  @override
  String get historyViewEdited => 'Editado';

  @override
  String get historyApplySmartModePreset =>
      'Aplicar predefinição do Smart Mode';

  @override
  String get historySmartModeApplied => 'Smart Mode aplicado';

  @override
  String get smartModeUndoToastMessage => 'Smart Mode aplicado';

  @override
  String get smartModeUndoAction => 'Desfazer';

  @override
  String get smartModeBusy => 'O Smart Mode ainda está em execução';

  @override
  String get smartModeBusyRetry =>
      'O Smart Mode ainda está em execução – tente novamente em instantes';

  @override
  String smartModeNameChangeToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nomes alterados',
      one: '1 nome alterado',
    );
    return '$_temp0';
  }

  @override
  String selectionUndoCopiedToClipboard(String shortcut) {
    return 'Original copiado para a área de transferência – cole com $shortcut. O conteúdo anterior da área de transferência foi substituído.';
  }

  @override
  String get selectionUndoUnavailable => 'Desfazer não é possível agora.';

  @override
  String get smartModeCheckTimedOut =>
      'A verificação demorou demais – seu texto permanece inalterado.';

  @override
  String get historySmartModeUndo => 'Desfazer Smart Mode';

  @override
  String get historySmartModeRestore => 'Restaurar Smart Mode';

  @override
  String get historySmartModeFailedModelMissing =>
      'Modelo de texto não baixado';

  @override
  String get historySmartModeFailedTimeout => 'Tempo esgotado no Smart Mode';

  @override
  String get historySmartModeFailedGeneric =>
      'Falha no Smart Mode — tente novamente';

  @override
  String get historySmartModeSelectTargetLanguage =>
      'Selecione o idioma de destino';

  @override
  String get historyAddNote => 'Adicionar anotação';

  @override
  String get historyEditNote => 'Editar anotação';

  @override
  String get historyNotes => 'Anotações';

  @override
  String get historyNotePlaceholder => 'Escreva uma anotação…';

  @override
  String get historyVoiceNoteHint =>
      'Dica: diga “tag: nome” ou “correct: texto” durante a gravação.';

  @override
  String get historyNoteAdded => 'Anotação adicionada';

  @override
  String get historyNoteDeleted => 'Anotação excluída';

  @override
  String get historyCopiedAsMarkdown => 'Copiado como Markdown';

  @override
  String get historyAddTag => 'Adicionar tag…';

  @override
  String get historySearchTags => 'Pesquisar ou criar…';

  @override
  String get historyNoteEdited => 'editada';

  @override
  String get historyTagAdded => 'Tag adicionada';

  @override
  String get historyTagRemoved => 'Tag removida';

  @override
  String historyCreateTag(Object tag) {
    return 'Criar \"$tag\"';
  }

  @override
  String get historyManageTags => 'Gerenciar tags';

  @override
  String get tagManageTitle => 'Gerenciar tags';

  @override
  String get tagManageEmpty =>
      'Ainda não há tags. Você cria uma adicionando-a a uma gravação.';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
      zero: 'sem uso',
    );
    return '$_temp0';
  }

  @override
  String tagOverflowMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mais $count tags',
      one: 'mais 1 tag',
    );
    return '$_temp0';
  }

  @override
  String get tagDeleteConfirmTitle => 'Excluir tag?';

  @override
  String tagDeleteConfirmMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
    );
    return 'A tag \"$name\" é usada em $_temp0. Ela será removida de todas.';
  }

  @override
  String tagDeleted(String name) {
    return 'Tag \"$name\" excluída';
  }

  @override
  String tagRemoveSemanticsLabel(String tag) {
    return 'Remover tag \"$tag\"';
  }

  @override
  String get tagDeleteUnusedTitle => 'Excluir tags sem uso?';

  @override
  String tagDeleteUnusedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags sem uso serão excluídas permanentemente.',
      one: '1 tag sem uso será excluída permanentemente.',
    );
    return '$_temp0';
  }

  @override
  String tagDeleteUnusedAction(int count) {
    return 'Excluir $count sem uso';
  }

  @override
  String tagDeletedUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags sem uso excluídas',
      one: '1 tag sem uso excluída',
    );
    return '$_temp0';
  }

  @override
  String get historyEditTranscript => 'Editar transcrição';

  @override
  String get historyTranscriptSaved => 'Transcrição salva';

  @override
  String get historySaveTranscript => 'Salvar';

  @override
  String get historyShortcutHelp => 'Atalhos de teclado';

  @override
  String get historyShortcutGeneral => 'GERAL';

  @override
  String get historyShortcutTags => 'Focar campo de tags';

  @override
  String get historyShortcutNotes => 'Adicionar uma anotação';

  @override
  String get historyShortcutPin => 'Favoritar / desfavoritar';

  @override
  String get historyShortcutClose => 'Salvar e fechar';

  @override
  String get historyShortcutListGroup => 'LISTA DE GRAVAÇÕES';

  @override
  String get historyShortcutMoveFocus => 'Selecionar entrada';

  @override
  String get historyShortcutOpenEntry => 'Abrir entrada';

  @override
  String get historyShortcutCopyEntry => 'Copiar entrada';

  @override
  String get historyShortcutDeleteEntry => 'Excluir entrada';

  @override
  String get historyShortcutSelectAll => 'Selecionar tudo';

  @override
  String get historyShortcutClearSelection => 'Limpar a seleção';

  @override
  String get historyShortcutEditing => 'EDIÇÃO';

  @override
  String get historyShortcutToggleEdit => 'Alternar modo de edição';

  @override
  String get historyShortcutSave => 'Salvar transcrição';

  @override
  String get historyShortcutBold => 'Negrito';

  @override
  String get historyShortcutItalic => 'Itálico';

  @override
  String get historyShortcutCopy => 'Copiar para a área de transferência';

  @override
  String get historyShortcutEditTitle => 'Editar título';

  @override
  String get historyShortcutDiscardEdit => 'Descartar a edição';

  @override
  String get historyEditTitle => 'Editar título';

  @override
  String get historyTitlePlaceholder => 'Digite um título…';

  @override
  String get historyTitleSaved => 'Título salvo';

  @override
  String get historySearchHelpTitle => 'Dicas de pesquisa';

  @override
  String get historySearchHelpTags => 'Digite # para filtrar por tags';

  @override
  String get historySearchHelpLang => 'Digite lang: para filtrar por idioma';

  @override
  String get historySearchHelpFreeText => 'Ou digite qualquer palavra-chave';

  @override
  String get historySearchQuickTags => 'Tags populares';

  @override
  String get historyRecentSearches => 'Pesquisas recentes';

  @override
  String get historyRemoveRecentSearch => 'Remover pesquisa recente';

  @override
  String get historyRemoveFilter => 'Remover filtro';

  @override
  String get historyQuickActions => 'Filtros rápidos';

  @override
  String get historyQuickActionAllLangs => 'Todos os idiomas';

  @override
  String get historyQuickActionFavorites => 'Somente favoritos';

  @override
  String get historySortNewest => 'Mais recentes primeiro';

  @override
  String get historySortOldest => 'Mais antigos primeiro';

  @override
  String get historySortLongest => 'Mais longos primeiro';

  @override
  String historySearchActiveTag(String tag) {
    return '#$tag';
  }

  @override
  String historySearchActiveLang(String code) {
    return 'lang:$code';
  }

  @override
  String get historySearchSuggestTag => 'Filtrar por tag';

  @override
  String get historySearchSuggestLang => 'Filtrar por idioma';

  @override
  String get settingsKeyboardShortcut => 'Atalho';

  @override
  String get shortcutsGroupDictate => 'Ditar';

  @override
  String get shortcutsGroupNotes => 'Notas e snippets';

  @override
  String get shortcutsGroupSmartMode => 'Smart Mode e editar seleção';

  @override
  String get shortcutsAreaIntro =>
      'Estes atalhos funcionam em todo o sistema: em quase qualquer app, mesmo com o WhisPaste em segundo plano. Cada combinação pertence a um único atalho.';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Atalho para iniciar e parar a gravação';

  @override
  String get settingsHotkeyEnabled => 'Iniciar/parar gravação';

  @override
  String get settingsCurrentHotkey => 'Atalho atual';

  @override
  String get settingsChangeHotkey => 'Alterar';

  @override
  String get settingsHotkeyRecorderTitle => 'Gravar novo atalho';

  @override
  String get settingsHotkeyRecorderHint =>
      'Pressione a combinação de teclas que deseja usar…';

  @override
  String get settingsHotkeyRecorderDictationTitle => 'Alterar tecla de ditado';

  @override
  String settingsHotkeyRecorderDictationHint(String key) {
    return 'Pressione a nova combinação de teclas. Uma única tecla também funciona, por exemplo: $key.';
  }

  @override
  String get settingsHotkeyRecorderSingleKeyMac =>
      'Para uma única tecla, o macOS pede uma vez a permissão de “Monitoramento de entrada”.';

  @override
  String get settingsHotkeyRecorderListening => 'Pressione agora a nova tecla.';

  @override
  String get settingsHotkeyRecorderCurrent => 'Atual';

  @override
  String get hotkeyKeySideLeft => 'esq.';

  @override
  String get hotkeyKeySideRight => 'dir.';

  @override
  String settingsHotkeyRecorderModifierHint(
    String first,
    String second,
    String third,
  ) {
    return 'Qualquer combinação com modificadores funciona, por ex. $first, $second ou $third';
  }

  @override
  String get settingsHotkeyRecorderCancel => 'Cancelar';

  @override
  String get settingsHotkeyRecorderSave => 'Salvar';

  @override
  String get settingsHotkeyRecorderClear => 'Limpar';

  @override
  String get settingsHotkeyRecorderInvalidKey =>
      'Esta tecla não pode ser usada como atalho. Tente uma letra, um dígito, uma tecla de função (F1-F12) ou uma tecla de seta.';

  @override
  String get settingsHotkeyActionRecording => 'Iniciar/parar gravação';

  @override
  String get settingsHotkeyActionQuickNote => 'Nota rápida';

  @override
  String get settingsQuickNoteHotkeyEnabled => 'Gravar uma nota rápida';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'O texto transcrito é acrescentado à nota marcada como sua nota rápida. Você escolhe essa nota na área de notas.';

  @override
  String get settingsQuickNoteOpenInMainWindow =>
      'Abrir notas na janela principal';

  @override
  String get settingsQuickNoteOpenInMainWindowHint =>
      'Desligado: a nota rápida é salva em segundo plano e uma mensagem oferece «Abrir nota». Ligado: a janela principal aparece e mostra a nota.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Atalho atual';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Esta combinação já é usada para “$action”. Escolha outra.';
  }

  @override
  String settingsDictationHotkeyCollision(Object action) {
    return 'Esta combinação já é usada para “$action”. Escolha outra.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho de nota rápida está inativo no momento. Escolha outra combinação.';

  @override
  String get quickNoteToastSaved => 'Nota rápida salva';

  @override
  String get quickNoteToastOpenNote => 'Abrir nota';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Seletor de snippets';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Abrir o seletor de snippets';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Abre o seletor de snippets imediatamente, sem gravação e sem a palavra-gatilho falada.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Atalho atual';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Esta combinação já é usada para “$action”. Escolha outra.';
  }

  @override
  String get settingsSnippetPickerHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho do seletor de snippets está inativo no momento. Escolha outra combinação.';

  @override
  String get settingsMaxRecordDuration => 'Duração máxima da gravação';

  @override
  String get settingsMaxRecordDurationSubtitle =>
      'Parada automática de segurança após este tempo';

  @override
  String get settingsMaxRecordDurationUnlimited => 'Ilimitada';

  @override
  String get settingsCloseToTray => 'Fechar para a bandeja';

  @override
  String get settingsCloseToTraySubtitle =>
      'Continuar em execução na bandeja do sistema ao fechar a janela';

  @override
  String get settingsSidePanelEnabled => 'Painel de colagem rápida';

  @override
  String get settingsSidePanelEnabledSubtitle =>
      'Painel que desliza ao passar o mouse na borda escolhida da tela, com transcrições, snippets e histórico da área de transferência';

  @override
  String get settingsSidePanelEdge => 'Posição do painel';

  @override
  String get settingsSidePanelEdgeSubtitle =>
      'Em qual borda da tela o painel se encaixa e de onde ele desliza';

  @override
  String get settingsSidePanelEdgeLeft => 'Borda esquerda';

  @override
  String get settingsSidePanelEdgeRight => 'Borda direita';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsAppearanceSubtitle =>
      'Cores das janelas do app. A barra de gravação e o overlay continuam escuros.';

  @override
  String get settingsAppearanceSystem => 'Seguir o sistema';

  @override
  String get settingsAppearanceLight => 'Claro';

  @override
  String get settingsAppearanceDark => 'Escuro';

  @override
  String get settingsAppearanceNavy => 'Marinho';

  @override
  String get settingsAppearanceCardNavy => 'Marinho';

  @override
  String get settingsLanguageDialogSubtitle =>
      'Escolha o idioma que o WhisPaste espera ao gravar. Com «Detectar automaticamente» ligado, ele reconhece o idioma sozinho.';

  @override
  String get settingsLanguageSearchHint => 'Pesquisar idiomas';

  @override
  String get settingsLanguageSelectedTitle => 'Selecionado';

  @override
  String get settingsLanguageSaveAndClose => 'Salvar e fechar';

  @override
  String get settingsLanguageSavePickOne =>
      'Escolha pelo menos um idioma para salvar.';

  @override
  String get settingsLanguageNoResults => 'Nenhum idioma encontrado';

  @override
  String get settingsLanguageChange => 'Alterar';

  @override
  String get settingsLanguageCancel => 'Cancelar';

  @override
  String get settingsErrorReporting => 'Enviar relatórios de falhas';

  @override
  String get settingsErrorReportingSubtitle =>
      'Relatórios técnicos de falhas e erros graves, via Sentry na UE. Nunca seu áudio ou texto.';

  @override
  String get settingsErrorReportingRestartHint =>
      'Entra em vigor após reiniciar o WhisPaste.';

  @override
  String get settingsAutoPasteBlocklist => 'Lista de bloqueio do Auto-Paste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Apps em que só se copia (sem colagem automática). Com o interruptor abaixo ligado, o texto vai para a área de transferência; desligado, só para as Gravações. Enquanto houver uma lista, um app não identificado conta como bloqueado.';

  @override
  String get settingsAutoPasteBlocklistCopyToggle =>
      'Copiar para a área de transferência em apps bloqueados';

  @override
  String get settingsAutoPasteBlocklistCopyToggleSubtitle =>
      'Desligado: o texto só é salvo em Gravações.';

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
      'No Mac use IDs de pacote, p. ex. com.apple.Terminal. Sem ponto, uma entrada só corresponde a um ID idêntico.';

  @override
  String get settingsAutoPasteBlocklistNoDetectionHintGnome =>
      'No GNOME (Wayland), o WhisPaste só identifica o app de destino com a extensão do WhisPaste para GNOME; sem ela, com lista ativa, só se copia';

  @override
  String get settingsLinuxAlwaysShiftPaste => 'Sempre colar com Ctrl+Shift+V';

  @override
  String get settingsLinuxAlwaysShiftPasteSubtitle =>
      'O atalho dos terminais, também em todos os outros apps. Alguns apps usam essas teclas para outra coisa; o LibreOffice, por exemplo, abre “Colar especial”';

  @override
  String get settingsLinuxTargetStatusAvailable =>
      'Aqui o WhisPaste identifica o app de destino e cola nos terminais com Ctrl+Shift+V sozinho';

  @override
  String get settingsLinuxTargetStatusGnome =>
      'No GNOME (Wayland), o WhisPaste só reconhece terminais com a extensão do WhisPaste para GNOME. Até lá, ative se você dita principalmente em terminais';

  @override
  String get settingsLinuxTargetStatusUnsupported =>
      'Nesta área de trabalho, o WhisPaste não reconhece terminais. Ative se você dita principalmente em terminais';

  @override
  String get settingsLinuxPortalInputTitle =>
      'Colar pela permissão da área de trabalho';

  @override
  String get settingsLinuxPortalInputBody =>
      'Funciona sem configuração: sua área de trabalho pergunta uma vez se o WhisPaste pode enviar atalhos. O WhisPaste só envia assim Ctrl+V e Ctrl+C';

  @override
  String get settingsLinuxPortalInputConnect => 'Pedir permissão';

  @override
  String get settingsLinuxPortalInputRevoke => 'Retirar a permissão';

  @override
  String get settingsLinuxPortalInputConnected =>
      'Permissão concedida. O WhisPaste já pode colar assim';

  @override
  String get settingsLinuxPortalInputCancelled =>
      'Permissão não concedida. Você pode pedir de novo a qualquer momento';

  @override
  String get settingsLinuxPortalInputFailed =>
      'Não foi possível pedir a permissão. Tente de novo mais tarde';

  @override
  String get settingsLinuxGnomeExtensionTitle =>
      'Extensão do WhisPaste para GNOME';

  @override
  String get settingsLinuxGnomeExtensionBody =>
      'No GNOME, o WhisPaste só sabe qual app está ativo com esta extensão, por exemplo para terminais e a lista de bloqueio. Ela só lê o nome do app, nunca títulos de janela ou conteúdo';

  @override
  String get settingsLinuxGnomeExtensionEnable => 'Ativar a extensão';

  @override
  String get settingsLinuxGnomeExtensionDisable => 'Desativar a extensão';

  @override
  String get settingsLinuxGnomeExtensionNotInstalled =>
      'A extensão não está instalada aqui. O manual explica como instalá-la';

  @override
  String get settingsLinuxGnomeExtensionRelogin =>
      'Ativada. Se o WhisPaste ainda não reconhecer o app, saia da sessão e entre de novo uma vez';

  @override
  String settingsLinuxGnomeExtensionFailed(String command) {
    return 'Não foi possível ativar. Em um terminal: $command';
  }

  @override
  String get settingsAutoPasteBlocklistNoDetectionHint =>
      'No Wayland, o WhisPaste não consegue ver o app ativo. Enquanto houver apps bloqueados, o texto só é copiado, não colado.';

  @override
  String get settingsPasteWaylandFocusHint =>
      'Com Wayland, o WhisPaste não consegue verificar se você trocou de janela durante o processamento: o texto vai para a janela ativa ao colar';

  @override
  String get settingsPasteBlocklistAdd => 'Adicionar app';

  @override
  String get settingsPasteBlocklistEmpty =>
      'Nenhum app bloqueado: o auto-colar funciona em quase todos.';

  @override
  String settingsPasteBlocklistRemoveTooltip(String name) {
    return 'Remover da lista de bloqueio: $name';
  }

  @override
  String get settingsPasteBlocklistPickerTitle =>
      'Adicionar app à lista de bloqueio';

  @override
  String get settingsPasteBlocklistRecentHeading => 'Ditado recente em';

  @override
  String get settingsPasteBlocklistPickerEmpty =>
      'Ainda não há ditados com um app reconhecido. Digite abaixo o identificador do app.';

  @override
  String get settingsPasteBlocklistManualHeading =>
      'Digitar o identificador manualmente';

  @override
  String get settingsPasteBlocklistManualAdd => 'Adicionar';

  @override
  String get historyAutoPasteOffForApp => 'Desativar o auto-colar neste app';

  @override
  String get settingsPasteClipboardAfter => 'Área de transferência após colar';

  @override
  String get settingsPasteClipboardAfterSubtitle =>
      'Se o conteúdo anterior da área de transferência volta depois de colar. Se a colagem não puder ser confirmada a tempo, a transcrição fica na área de transferência, a menos que a opção abaixo esteja ativa.';

  @override
  String get settingsPasteClipboardAfterKeep => 'Manter a transcrição';

  @override
  String get settingsPasteClipboardWithoutReceipt =>
      'Restaurar mesmo sem confirmação';

  @override
  String get settingsPasteClipboardWithoutReceiptSubtitle =>
      'Desativado: se a colagem não for confirmada a tempo, a transcrição fica na área de transferência. Ativado: após uma espera fixa volta o conteúdo anterior, como na versão anterior. Só com «Restaurar o que você tinha copiado». Um app muito lento ainda pode ler o conteúdo antigo antes de receber a transcrição. Ativado em instalações existentes, desativado nas novas.';

  @override
  String get settingsPasteClipboardAfterRestore =>
      'Restaurar o que você tinha copiado';

  @override
  String get pasteClipboardUnsavedHint =>
      'Não foi possível salvar a sua área de transferência anterior: o macOS negou o acesso. Permita em Ajustes do Sistema → Privacidade e Segurança.';

  @override
  String get pasteClipboardUnsavedAction => 'Abrir Ajustes do Sistema';

  @override
  String get settingsCheckUpdates => 'Verificar atualizações';

  @override
  String get settingsCheckUpdatesSubtitle =>
      'Verifica novas versões na inicialização e a cada 24 horas';

  @override
  String get settingsCheckForUpdatesNow => 'Verificar atualizações agora';

  @override
  String get settingsUpdates => 'Atualizações';

  @override
  String get settingsUpdatesSubtitle =>
      'Canal de lançamento e verificação de atualizações';

  @override
  String get settingsBetaUpdates => 'Atualizações beta';

  @override
  String get settingsBetaUpdatesSubtitle =>
      'Receba versões de pré-lançamento, menos testadas.';

  @override
  String get settingsStableRevertHintMessage =>
      'Não é possível voltar automaticamente para a versão estável por aqui. Você já tem instalada uma versão beta mais recente.';

  @override
  String settingsStableRevertHintLink(String stableVersion) {
    return 'Baixar manualmente a versão estável $stableVersion';
  }

  @override
  String get onboardingNext => 'Avançar';

  @override
  String get onboardingLoadModel => 'Carregar modelo de voz';

  @override
  String get onboardingReadyFixHotkey => 'Alterar atalho';

  @override
  String get onboardingBack => 'Voltar';

  @override
  String historyRetentionNotice(int maxEntries, int trashDays) {
    String _temp0 = intl.Intl.pluralLogic(
      maxEntries,
      locale: localeName,
      other: 'Ficam guardadas até $maxEntries gravações.',
      one: 'Fica guardada 1 gravação.',
    );
    String _temp1 = intl.Intl.pluralLogic(
      trashDays,
      locale: localeName,
      other: ', que é esvaziada após $trashDays dias',
      one: ', que é esvaziada após 1 dia',
      zero: ', que nunca é esvaziada automaticamente',
    );
    return '$_temp0 As mais antigas vão para a lixeira$_temp1. Os favoritos são sempre mantidos. Você pode alterar isso em Configurações → Privacidade e dados.';
  }

  @override
  String get historyRetentionNoticeUnlimited =>
      'Não há limite para o número de gravações. Os favoritos são sempre mantidos. Você pode alterar isso em Configurações → Privacidade e dados.';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Etapa $current de $total';
  }

  @override
  String get onboardingMicStatement =>
      'Diga algumas palavras. A onda deve se mover.';

  @override
  String get onboardingMicHeard => 'Ouvi você. Pode continuar.';

  @override
  String get onboardingMicSilence =>
      'Não chegou som. O microfone certo está selecionado?';

  @override
  String get onboardingMicOpenError =>
      'O microfone não arrancou; talvez outra app o esteja a usar. Continuo a tentar.';

  @override
  String get onboardingMicPermissionLine =>
      'O WhisPaste ainda não pode usar o microfone.';

  @override
  String get onboardingMicLevelLabel => 'Nível do microfone';

  @override
  String get onboardingMicSkip => 'Ignorar';

  @override
  String get onboardingModelTitle => 'Configurar o modelo de voz';

  @override
  String get onboardingModelSubtitle =>
      'Baixe o modelo de voz para gravar offline. Com o reconhecimento local, sua voz fica no seu dispositivo.';

  @override
  String get onboardingModelRecommended => 'Recomendado';

  @override
  String get onboardingModelChangeLater =>
      'Você pode trocar o modelo de voz depois nas Configurações';

  @override
  String get onboardingModelDefaultHint =>
      'Pré-selecionado. Também há modelos maiores e mais precisos; você pode trocar a qualquer momento nas Configurações.';

  @override
  String get onboardingHotkeyTestRecognized =>
      'Funciona. É assim que você começa a ditar.';

  @override
  String get onboardingHotkeyStatusHeld => 'Detectada. Continue segurando …';

  @override
  String get onboardingHotkeyStatusRelease => 'Agora solte.';

  @override
  String get onboardingHotkeyStatusHandsFree =>
      'Mãos livres ativo. Um toque termina.';

  @override
  String get onboardingHotkeyStatusToggledOn =>
      'Iniciado. Pressione de novo para parar.';

  @override
  String get onboardingHotkeyStatusDoneHandsFree =>
      'Funciona, também sem as mãos.';

  @override
  String get onboardingHotkeySkip => 'Testar depois';

  @override
  String get onboardingHotkeySceneIdle =>
      'Teste de tecla · microfone desligado';

  @override
  String onboardingModelFactSize(String size) {
    return 'Download $size';
  }

  @override
  String get onboardingModelFactLanguagesParakeet =>
      'Cerca de 25 idiomas europeus';

  @override
  String get onboardingModelFactLanguagesWhisper => '99 idiomas';

  @override
  String get onboardingModelFactSpeedParakeet => 'Muito rápido';

  @override
  String get onboardingModelFactSpeedWhisper => 'Mais lento';

  @override
  String get onboardingModelNextBlocked =>
      'Baixe um modelo de voz ou use um provedor na nuvem com uma chave de API salva para continuar.';

  @override
  String get onboardingModelGpuCpuFallback =>
      'A aceleração pela placa de vídeo não está disponível; o WhisPaste usará o processador. Funciona, só que mais devagar.';

  @override
  String get onboardingModelEngineParakeetLabel => 'Parakeet';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'O jeito mais rápido de transformar fala em texto. Roda bem em qualquer hardware, com ou sem GPU.';

  @override
  String get onboardingModelDetectingHardware =>
      'Verificando seu hardware para a recomendação certa…';

  @override
  String onboardingModelUseCloud(String provider) {
    return 'Usar $provider';
  }

  @override
  String onboardingModelCloudKeySaved(String provider) {
    return 'Já existe uma chave de API salva para $provider. Você pode usá-la em vez de um modelo de voz local.';
  }

  @override
  String onboardingModelCloudInUse(String provider) {
    return 'Você usa $provider para o reconhecimento de voz. Não precisa de um modelo de voz local.';
  }

  @override
  String get onboardingModelUseLocal => 'Usar um modelo de voz local';

  @override
  String get onboardingModelEngineWhisperLabel => 'Whisper';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'Termos próprios e ajustes de pontuação para nomes, siglas e termos técnicos.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Ainda não oferece suporte ao idioma escolhido';

  @override
  String get onboardingTestRecordingTitle => 'Experimente';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Pressione o atalho, diga uma frase e pressione-o de novo.';

  @override
  String get onboardingTestRecordingSubtitleHold =>
      'Segure o atalho, diga uma frase e solte.';

  @override
  String get onboardingTestRecordingStopCta => 'Parar gravação';

  @override
  String get onboardingTryOutLaterCta => 'Experimentar depois';

  @override
  String get onboardingPracticeQuestion =>
      'Para o que você quer usar o WhisPaste primeiro? É só dizer.';

  @override
  String get onboardingPracticePlaceholder => 'Seu texto aparece aqui.';

  @override
  String get onboardingPracticeReceived =>
      'Recebido – é assim que o seu texto chega a qualquer app.';

  @override
  String get onboardingPracticeSilence =>
      'Não ouvi nada – fale um pouco mais alto ou verifique o microfone.';

  @override
  String get onboardingPracticePasteFailed =>
      'Não deu para colar, seu texto está na área de transferência.';

  @override
  String get onboardingPracticeWaiting => 'Aguardando o ditado…';

  @override
  String onboardingPracticeModelLoading(int percent) {
    return 'Modelo de voz carregando… $percent %';
  }

  @override
  String onboardingPracticeModelLoadingEta(int percent, int minutes) {
    return 'Modelo de voz carregando… $percent % · faltam cerca de $minutes min';
  }

  @override
  String get onboardingPracticeModelMissing =>
      'O modelo de voz ainda falta. Sem ele não consigo ouvir você.';

  @override
  String onboardingPracticeModelSlow(int seconds) {
    return 'Neste computador o modelo demora cerca de $seconds s para 10 s de fala. Um modelo mais rápido escreve aqui com mais fluidez.';
  }

  @override
  String get onboardingPracticeModelSlowParakeet => 'Transferir o Parakeet';

  @override
  String get onboardingPracticeModelSlowSmaller =>
      'Transferir um modelo mais rápido';

  @override
  String get onboardingPracticeMicMissing =>
      'Permita o microfone primeiro; sem ele não consigo ouvir você.';

  @override
  String get onboardingTryoutLockTitle =>
      'Seu modelo de voz ainda está carregando';

  @override
  String get onboardingTryoutLockBody =>
      'Os testes começam assim que estiver pronto – automaticamente.';

  @override
  String get onboardingTryoutLockMissingTitle =>
      'Testar precisa de um modelo de voz';

  @override
  String get onboardingTryoutLockReady => 'Carregado – experimente agora';

  @override
  String get onboardingPracticeMicAllow => 'Permitir o microfone';

  @override
  String get onboardingPracticeChipNote => 'Dite uma nota curta';

  @override
  String get onboardingPracticeChipList => 'Experimente uma lista';

  @override
  String get onboardingPracticeChipsLabel => 'Sugestões';

  @override
  String onboardingPracticeChipReply(String hotkey) {
    return 'Ótimo, então pressione $hotkey e comece a falar.';
  }

  @override
  String onboardingPracticeChipReplyHold(String hotkey) {
    return 'Ótimo, então segure $hotkey e comece a falar.';
  }

  @override
  String get onboardingPracticeInputHint => 'Escreva uma mensagem ou dite';

  @override
  String get onboardingPracticeSend => 'Enviar';

  @override
  String get onboardingPracticeDictate => 'Ditar';

  @override
  String get onboardingTestRecordingInProgress =>
      'Gravando: é só começar a falar. Pressione de novo para parar.';

  @override
  String get onboardingTestRecordingInProgressHold =>
      'Gravando: é só começar a falar. Solte para parar.';

  @override
  String get onboardingTestRecordingReassurance =>
      'Só um teste, o texto fica neste campo.';

  @override
  String onboardingTestRecordingReassuranceWithDuration(
    int seconds,
    String section,
  ) {
    return 'Só um teste, o texto fica neste campo — as gravações param automaticamente após $seconds segundos, ajustável em Configurações → $section.';
  }

  @override
  String get onboardingReadyBackToModel => 'Voltar ao modelo de voz';

  @override
  String onboardingReadyStep3CopyOnly(String paste) {
    return 'O texto está na área de transferência, pressione $paste para colar';
  }

  @override
  String get onboardingTriggerTitle => 'Teste sua tecla de ditado.';

  @override
  String get onboardingPhaseStart => 'Início';

  @override
  String onboardingPhaseCounter(int index, int total) {
    return '$index de $total';
  }

  @override
  String get onboardingPhasePermissions => 'Permissões';

  @override
  String get onboardingPhaseSetup => 'Configurar';

  @override
  String get onboardingPhaseTry => 'Testar';

  @override
  String get onboardingPhasePersonalize => 'Personalizar';

  @override
  String get onboardingTriggerHoldHint =>
      'Muito curto. Segure a tecla um pouco mais.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Atalho atual';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Atalho já em uso';

  @override
  String get onboardingTriggerDesktopConfirmHint =>
      'O seu sistema vai perguntar uma vez se o WhisPaste pode usar este atalho. Confirme lá e ele funcionará em qualquer aplicativo.';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Seu atalho parece estar em uso por outro app. Grave uma nova combinação abaixo para continuar.';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Pressione uma vez para iniciar, pressione de novo para terminar';

  @override
  String get onboardingTriggerDoubleTapFallbackHint =>
      'A tecla única não pode ser usada aqui, então vale a combinação.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintWindows =>
      'O Windows não permite a tecla única agora, então vale a combinação.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintLinux =>
      'Esta área de trabalho não informa a tecla única, então vale a combinação.';

  @override
  String get onboardingTriggerDoubleTapFallbackHintMac =>
      'Até permitir \"Monitoramento de entrada\", vale a combinação.';

  @override
  String onboardingTriggerDemoPrompt(String shortcut) {
    return 'Pressione $shortcut uma vez para começar e outra para parar. É assim que você dita em qualquer app.';
  }

  @override
  String onboardingTriggerDemoPromptDoubleTap(String shortcut) {
    return 'Toque $shortcut duas vezes rápido; um toque termina. É assim que você dita em qualquer app.';
  }

  @override
  String onboardingTriggerDemoPromptHold(String shortcut) {
    return 'Segure $shortcut e solte. É assim que você dita em qualquer app.';
  }

  @override
  String get onboardingTriggerChooseOther => 'Trocar tecla';

  @override
  String get onboardingTriggerSecureInput =>
      'O ditado está bloqueado neste campo. Mude para outro campo de texto e ele funciona.';

  @override
  String get onboardingStartUsing => 'Vamos lá';

  @override
  String get onboardingStartWhisPaste => 'Iniciar o WhisPaste';

  @override
  String get onboardingOtherModel => 'Outro modelo de voz';

  @override
  String get onboardingWelcomeStatement =>
      'Fale – o texto aparece onde está o seu cursor.';

  @override
  String get onboardingDownloadReady => 'Modelo pronto';

  @override
  String get onboardingDownloadFailed => 'Falha no download';

  @override
  String get onboardingWelcomeHeadline => 'Fale onde\nvocê costuma digitar.';

  @override
  String get onboardingWelcomeSampleDictation =>
      'A apresentação está ótima, só encurtaria um pouco o segundo slide.';

  @override
  String onboardingWelcomeRecommended(String model) {
    return 'Recomendado: $model';
  }

  @override
  String onboardingWelcomeConsentLine(String size) {
    return 'Baixa o modelo de voz ($size) · fica no seu dispositivo';
  }

  @override
  String onboardingWelcomeReachParakeet(int count) {
    return 'Muito rápido · $count idiomas europeus';
  }

  @override
  String onboardingWelcomeStartSized(String size) {
    return 'Baixar $size e configurar';
  }

  @override
  String get onboardingWelcomeOnDevice =>
      'Roda inteiramente no seu dispositivo, sem nuvem.';

  @override
  String get onboardingSelectDictationLanguage => 'Idioma de ditado';

  @override
  String get onboardingSelectSpeechModel => 'Reconhecimento de voz';

  @override
  String get onboardingSelectAppLanguage => 'Idioma do app';

  @override
  String onboardingSelectRecommendedFor(String language) {
    return 'Recomendado para $language';
  }

  @override
  String get onboardingSelectYourChoice => 'Sua escolha';

  @override
  String get onboardingSelectSearchLanguage => 'Buscar idioma';

  @override
  String get onboardingWelcomeStart => 'Configurar';

  @override
  String get onboardingWelcomeLaterChangeable =>
      'Você pode trocar o modelo de voz a qualquer momento nas Configurações.';

  @override
  String get onboardingReviewExit => 'Fechar introdução';

  @override
  String get onboardingReviewDone => 'Concluído';

  @override
  String get onboardingReviewEntry => 'Introdução';

  @override
  String get onboardingReviewLabel => 'Rever a introdução';

  @override
  String get onboardingReviewAction => 'Abrir';

  @override
  String get onboardingRevisionNoticeTitle =>
      'O WhisPaste foi atualizado — suas configurações não mudaram.';

  @override
  String get onboardingRevisionNoticeExpand => 'Mostrar todas as novidades';

  @override
  String get onboardingRevisionNoticeCollapse => 'Mostrar menos';

  @override
  String get onboardingRevisionExit => 'Sair da introdução';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Sair da introdução?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Esta introdução só é mostrada uma vez. O que você pular agora não será configurado para você; pode configurar depois nas Configurações. Os passos também estão na página Ajuda, em «Rever a introdução». O que você já configurou permanece igual.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Sair';

  @override
  String get overlayRecording => 'Gravando';

  @override
  String get overlayTranscribing => 'Processando…';

  @override
  String transcribingSliceProgress(int current, int total) {
    return 'Processando parte $current de $total…';
  }

  @override
  String get overlayRefining => 'Refinando…';

  @override
  String get overlayStarting => 'Iniciando…';

  @override
  String get overlayDone => 'Copiado';

  @override
  String get overlayDonePasted => 'Colado';

  @override
  String get overlayDoneBoth => 'Copiado e colado';

  @override
  String get overlayDoneReady => 'Concluído';

  @override
  String get overlayError => 'Erro';

  @override
  String get overlayCancel => 'Cancelar';

  @override
  String get overlayPause => 'Pausar';

  @override
  String get overlayResume => 'Continuar';

  @override
  String get overlayStop => 'Parar';

  @override
  String overlayKeyboardHint(String hotkey) {
    return 'Pressione $hotkey para parar';
  }

  @override
  String overlayStopAndCancelHint(String hotkey, String cancelKey) {
    return '$hotkey para parar · $cancelKey para cancelar';
  }

  @override
  String overlayDiscardConfirm(String cancelKey) {
    return 'Descartar a gravação? Pressione $cancelKey novamente';
  }

  @override
  String overlayKeyboardHintNextFieldEnter(String hotkey) {
    return 'Enter ou $hotkey: próximo campo · Esc: cancelar';
  }

  @override
  String get overlayKeyboardHintNextFieldEnterOnly =>
      'Enter: próximo campo · Esc: cancelar';

  @override
  String get overlayProcessingLocal => 'Local';

  @override
  String get overlayProcessingCloud => 'Nuvem';

  @override
  String get overlayRecordingQuickNote => 'Gravando para nota';

  @override
  String get overlayTargetQuickNote => 'Nota';

  @override
  String overlayRecordingTargetTimer(String elapsed, String target) {
    return '$elapsed · $target';
  }

  @override
  String get overlayMicSignalLost => 'Sem sinal do microfone';

  @override
  String get overlayDoneQuickNote => 'Adicionado à nota';

  @override
  String get floatingButtonHide => 'Ocultar';

  @override
  String get floatingButtonQuit => 'Sair';

  @override
  String get a11yRecordingButton => 'Botão de gravação';

  @override
  String get a11yRecordingOverlay => 'Overlay de gravação';

  @override
  String get a11ySidePanel => 'Painel de colagem rápida';

  @override
  String get trayStatusRecording => 'Gravando…';

  @override
  String get trayStatusReady => 'Pronto';

  @override
  String get trayStartRecording => 'Iniciar gravação';

  @override
  String get trayStopRecording => 'Parar gravação';

  @override
  String get trayOpenApp => 'Abrir WhisPaste';

  @override
  String get trayTranscribeFile => 'Transcrever arquivo…';

  @override
  String get trayOpenSidePanel => 'Abrir painel de colagem rápida';

  @override
  String get traySettings => 'Configurações';

  @override
  String get trayResumeOnboarding => 'Retomar configuração';

  @override
  String get onboardingCloseTitle =>
      'Pausar a configuração ou encerrar o WhisPaste?';

  @override
  String get onboardingCloseBodyPause =>
      'Pausar fecha a janela. O WhisPaste continua em segundo plano e abre pelo ícone da bandeja ou pela barra de menus.';

  @override
  String get onboardingCloseBodyNoTray =>
      'Sem ícone na bandeja, o WhisPaste não pode continuar em segundo plano. Encerrar interrompe o WhisPaste. Na próxima abertura, a configuração continua de onde parou.';

  @override
  String get onboardingClosePause => 'Pausar';

  @override
  String get onboardingCloseContinue => 'Continuar configuração';

  @override
  String get onboardingReviewHintMessage =>
      'Novo: verificar o teste do microfone e a colagem';

  @override
  String get onboardingReviewHintAction => 'Abrir';

  @override
  String get trayQuit => 'Sair';

  @override
  String get trayRecentRecordings => 'Gravações recentes';

  @override
  String get trayUnlockRecordings => 'Desbloquear gravações…';

  @override
  String trayRecentMeta(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count palavras',
      one: '1 palavra',
    );
    return '$time · $_temp0';
  }

  @override
  String get trayFeedback => 'Enviar feedback…';

  @override
  String get quitDuringDictationTitle => 'Uma gravação ainda está em andamento';

  @override
  String get quitDuringDictationMessage =>
      'Ao encerrar agora, a gravação ou transcrição em andamento é interrompida e o texto se perde.';

  @override
  String get trayMicrophone => 'Microfone';

  @override
  String get settingsComingSoon => 'Em breve';

  @override
  String get undo => 'Desfazer';

  @override
  String get hintDismiss => 'Dispensar dica';

  @override
  String get voiceNoteButton => 'Nota de voz';

  @override
  String get voiceNoteRecording => 'Gravando nota de voz…';

  @override
  String get voiceNoteTranscribing => 'Transcrevendo…';

  @override
  String get voiceNoteAdded => 'Nota de voz adicionada';

  @override
  String voiceTagAdded(String tag) {
    return 'Tag \"$tag\" adicionada por voz';
  }

  @override
  String get voiceCorrectionApplied => 'Transcrição corrigida por voz';

  @override
  String get voiceCorrectionUndone => 'Correção desfeita';

  @override
  String get voiceNoteEmpty => 'Nenhuma fala detectada';

  @override
  String get voiceNoteError => 'Falha na nota de voz';

  @override
  String get historyVoiceNoteButtonTooltip =>
      'Nota de voz — diga «tag: …» para adicionar uma tag, ou «correct: …» para substituir esta transcrição';

  @override
  String updateAvailable(String version) {
    return 'Atualização disponível: v$version';
  }

  @override
  String updateDownloading(int percent) {
    return 'Baixando atualização… $percent%';
  }

  @override
  String get updateReadyToInstall => 'Atualização pronta, clique para instalar';

  @override
  String get updateUpToDate => 'Você está na versão mais recente';

  @override
  String get updateCheckNow => 'Verificar agora';

  @override
  String get updateInstall => 'Instalar atualização';

  @override
  String get updateDownload => 'Baixar';

  @override
  String get updateViewRelease => 'Notas da versão';

  @override
  String get updateError => 'Falha ao verificar atualizações';

  @override
  String get updateInstallAfterRecording =>
      'A atualização será instalada após a gravação';

  @override
  String get updateInstallerMissing =>
      'O arquivo de instalação não existe. Verifique novamente se há atualizações.';

  @override
  String get updateInstallFailed =>
      'Não foi possível iniciar a instalação. Tente instalar a atualização novamente.';

  @override
  String get updateInstallRetry => 'Instalar novamente';

  @override
  String get updateRateLimited =>
      'Muitas solicitações, tente novamente mais tarde';

  @override
  String updateStatusBarChip(String version) {
    return 'v$version disponível';
  }

  @override
  String get settingsOverlaySize => 'Tamanho do overlay';

  @override
  String get settingsOverlaySizeSubtitle =>
      'Escolha entre exibição detalhada ou mínima';

  @override
  String get settingsOverlaySizeNormal => 'Normal';

  @override
  String get settingsOverlaySizeCompact => 'Compacto';

  @override
  String get settingsOverlaySizeMini => 'Mini';

  @override
  String get settingsOverlayColors => 'Cores do overlay';

  @override
  String get settingsOverlayBackground => 'Fundo do overlay e do botão';

  @override
  String get settingsOverlayBackgroundSubtitle =>
      'Aplica-se ao overlay de gravação e ao botão flutuante.';

  @override
  String get settingsOverlayBackgroundMarine => 'Marinho';

  @override
  String get settingsOverlayBackgroundGraphit => 'Grafite';

  @override
  String get settingsOverlayBackgroundGletscher => 'Geleira';

  @override
  String get settingsOverlayBackgroundAmber => 'Âmbar';

  @override
  String get settingsOverlayWave => 'Cor da onda para overlay e botão';

  @override
  String get settingsOverlayWaveSubtitle =>
      'Aplica-se ao overlay de gravação e ao botão flutuante: onda e anel de gravação.';

  @override
  String get settingsOverlayWaveCyan => 'Ciano';

  @override
  String get settingsOverlayWaveViolett => 'Violeta';

  @override
  String get settingsOverlayWaveAmber => 'Âmbar';

  @override
  String get settingsOverlayWaveInk => 'Tinta';

  @override
  String get settingsOverlayWaveCoral => 'Coral';

  @override
  String get settingsOverlayWaveMint => 'Menta';

  @override
  String get settingsOverlayWaveUnavailable =>
      'Não fica bem visível neste fundo';

  @override
  String settingsOverlayWaveReplacedToast(String from, String to) {
    return '«$from» não fica bem visível neste fundo. A onda foi alterada para «$to».';
  }

  @override
  String get settingsOverlayLiveTranscript => 'Transcrição ao vivo';

  @override
  String get settingsOverlayLiveTranscriptSubtitle =>
      'Mostra o texto reconhecido ao vivo enquanto você ainda fala, em vez de só a forma de onda. Usa CPU extra durante a gravação';

  @override
  String get overlayRetry => 'Tentar novamente';

  @override
  String get overlayDismiss => 'Fechar';

  @override
  String get overlayContextCancel => 'Cancelar gravação';

  @override
  String get overlayContextSwitchNormal => 'Mudar para Normal';

  @override
  String get overlayContextSwitchCompact => 'Mudar para Compacto';

  @override
  String get overlayContextSwitchMini => 'Mudar para Mini';

  @override
  String get overlayContextHide => 'Ocultar overlay';

  @override
  String get buttonContextOpen => 'Abrir WhisPaste';

  @override
  String get buttonContextStartRecording => 'Iniciar gravação';

  @override
  String get buttonContextShowHistory => 'Mostrar gravações';

  @override
  String get buttonContextSettings => 'Configurações';

  @override
  String get buttonContextQuit => 'Sair do WhisPaste';

  @override
  String get settingsHistory => 'Gravações';

  @override
  String get settingsHistorySubtitle => 'Retenção e limpeza automática';

  @override
  String get settingsHistoryMaxEntries => 'Máximo de entradas';

  @override
  String get settingsHistoryMaxEntriesUnlimited => 'Ilimitado';

  @override
  String get settingsHistoryAutoTrashDays =>
      'Excluir lixeira automaticamente após';

  @override
  String get settingsHistoryAutoTrashNever => 'Nunca';

  @override
  String settingsHistoryAutoTrashDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String get settingsHistoryRetentionPreset => 'Retenção';

  @override
  String get settingsHistoryPresetMinimal => 'Mínimo';

  @override
  String get settingsHistoryPresetStandard => 'Padrão';

  @override
  String get settingsHistoryPresetUnlimited => 'Ilimitado';

  @override
  String get settingsHistoryPresetCustom => 'Personalizado';

  @override
  String get settingsHistoryHideOnOpen => 'Ocultar gravações ao abrir';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Mostra um botão “Mostrar gravações” no lugar das suas transcrições sempre que o WhisPaste iniciar ou a janela for reaberta. Nada é apagado.';

  @override
  String get settingsHistorySave => 'Guardar gravações';

  @override
  String get settingsHistorySaveSubtitle =>
      'Desligado: um ditado só é colado ou copiado. Nada é gravado em Gravações e nenhum áudio é guardado. As estatísticas e o lembrete de avaliação continuam a funcionar. Os ficheiros importados continuam a ir para Gravações.';

  @override
  String get settingsHistoryDeleteExisting => 'Apagar gravações existentes';

  @override
  String get settingsHistoryDeleteExistingSubtitle =>
      'Remove todas as gravações guardadas, incluindo as arquivadas e as do lixo. As notas não são afetadas.';

  @override
  String get settingsHistoryDeleteExistingAction => 'Apagar gravações…';

  @override
  String get settingsHistorySaveDeleteTitle =>
      'Apagar também as gravações existentes?';

  @override
  String get settingsHistorySaveDeleteMessage =>
      'Os novos ditados deixam de ser guardados. As gravações que já tem ficam até as apagar.';

  @override
  String get settingsHistorySaveDeleteKeep => 'Manter';

  @override
  String get settingsHistoryDeleteConfirm => 'Apagar gravações';

  @override
  String get settingsHistoryDeleteMessage =>
      'Todas as gravações guardadas são removidas definitivamente, incluindo as arquivadas e as do lixo. As notas não são afetadas. Não é possível desfazer.';

  @override
  String get historyOffTitle => 'As gravações estão desligadas';

  @override
  String get historyOffHint =>
      'Os novos ditados não são guardados aqui. O texto é colado ou copiado como de costume. Os ficheiros importados continuam a aparecer aqui.';

  @override
  String get historyOffAction => 'Abrir a definição';

  @override
  String get historyPinGateTitle => 'Gravações bloqueadas';

  @override
  String get historyPinGateHint =>
      'Digite seu PIN para mostrar suas transcrições.';

  @override
  String get historyImportUnlockHint =>
      'Desbloqueie Gravações para transcrever o arquivo.';

  @override
  String get historyPinUnlock => 'Desbloquear';

  @override
  String get historyPinDialogTitle => 'Digite o PIN';

  @override
  String get historyPinDialogSubtitle =>
      'Suas gravações estão protegidas por PIN.';

  @override
  String get historyPinFieldHint => 'PIN';

  @override
  String get historyPinRepeatHint => 'Repita o PIN';

  @override
  String get historyPinWrong => 'PIN incorreto.';

  @override
  String historyPinLockedOut(int seconds) {
    return 'Muitas tentativas. Tente de novo em $seconds s.';
  }

  @override
  String get historyPinForgot => 'Esqueceu o PIN?';

  @override
  String get historyPinForgotHint =>
      'Repor apaga de imediato todas as transcrições, os ficheiros de áudio guardados, as notas com as suas versões e as imagens das notas. Se um ficheiro não puder ser apagado, o WhisPaste mostra um aviso.';

  @override
  String get historyPinForgotConfirmTitle =>
      'Apagar gravações e notas e remover o PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Um PIN esquecido não pode ser recuperado. Para o repor, são apagados de imediato e de forma permanente todas as transcrições e ficheiros de áudio guardados (incluindo arquivo e lixo), todas as notas com as suas versões (incluindo lixo) e todas as imagens das notas. As definições, os blocos de texto e as substituições são mantidos. Se um ficheiro não puder ser apagado, o WhisPaste mostra um aviso.';

  @override
  String get historyPinForgotLeftoverAudio =>
      'Algumas gravações, importações ou imagens de notas não puderam ser apagadas. O WhisPaste remove-as na próxima vez que arrancar.';

  @override
  String historyPinForgotLeftoverUnqueued(String folder) {
    return 'Algumas gravações ou importações não puderam ser excluídas, e o WhisPaste não consegue tentar novamente depois. Exclua-as manualmente. Local: $folder';
  }

  @override
  String historyPinForgotMigrationCopyLeft(String path) {
    return 'Não foi possível excluir uma cópia da base de dados antiga ($path). Exclua-a manualmente.';
  }

  @override
  String get historyPinForgotConfirmAction => 'Excluir';

  @override
  String get historyPinSetTitle => 'Definir PIN';

  @override
  String get historyPinSetSubtitle =>
      '4 a 8 dígitos. Impede que outras pessoas vejam suas transcrições neste computador com facilidade — mas não as criptografa.';

  @override
  String get historyPinInvalid => 'Use de 4 a 8 dígitos.';

  @override
  String get historyPinMismatch => 'Os PINs não coincidem.';

  @override
  String get settingsHistoryPin => 'Proteção por PIN';

  @override
  String get settingsHistoryPinSubtitle =>
      'Exigir um PIN para mostrar gravações e notas, incluindo o painel lateral, o menu do botão flutuante e a API de automação.';

  @override
  String get settingsHistoryPinChange => 'Alterar';

  @override
  String get settingsHistoryPinRemove => 'Remover';

  @override
  String get settingsHistoryAutoLock => 'Bloquear automaticamente';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Oculta as gravações novamente após este tempo sem atividade.';

  @override
  String get settingsHistoryAutoLockNever => 'Nunca';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Após $minutes min';
  }

  @override
  String get settingsFloatingButtonLookLocked =>
      'Ative o botão flutuante para alterar isto.';

  @override
  String get settingsFloatingButtonSection => 'Botão flutuante';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Botão de gravação sempre no topo, para acesso rápido';

  @override
  String get settingsFloatingButtonWaylandTitle => 'Limites do Wayland';

  @override
  String get settingsFloatingButtonWaylandLimit =>
      'No Wayland, o ambiente de trabalho decide onde o botão aparece e se ele fica sempre por cima. O WhisPaste só consegue garantir isso de forma limitada. Gravar com um clique continua funcionando, e o botão não tira o foco do teclado.';

  @override
  String get settingsFloatingButtonUnavailable =>
      'Não disponível neste ambiente Linux: o botão precisa de X11 ou XWayland. Desligar continua possível.';

  @override
  String get settingsSttIdleTimeout => 'Tempo de inatividade do modelo de voz';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Por quanto tempo o modelo de voz permanece carregado após o uso';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Manter ativo';

  @override
  String get settingsSttKeepLoaded => 'Manter o modelo carregado';

  @override
  String get settingsSttKeepLoadedSubtitle =>
      'Um modelo carregado inicia o ditado sem esperar pelo carregamento. Enquanto estiver carregado, ocupa memória.';

  @override
  String settingsSttKeepLoadedMemory(String size) {
    return 'Carregado, o modelo precisa de cerca de $size de memória.';
  }

  @override
  String settingsSttVramGateNotice(int vramMb, int requiredMb) {
    return 'A memória da GPU ($vramMb MB) não basta para este modelo ($requiredMb MB). Ele roda na CPU.';
  }

  @override
  String get settingsSttKeepLoadedAlways => 'Sempre';

  @override
  String get settingsSttKeepLoadedAutomatic => 'Automático';

  @override
  String get settingsSttKeepLoadedAfterIdle => 'Após um período ocioso';

  @override
  String get settingsSttKeepLoadedUnloadAfter => 'Descarregar após';

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
  String get reviewSupportEntry => 'Avalie e apoie o WhisPaste';

  @override
  String get reviewSupportLabel => 'Avaliar o app';

  @override
  String get reviewSupportAction => 'Avaliar';

  @override
  String get reviewSupportGitHubLabel =>
      'Apoie o WhisPaste com uma estrela no GitHub';

  @override
  String get reviewSupportGitHubAction => 'Ver no GitHub';

  @override
  String get ideasBoardLabel => 'Ideias e pedidos de recursos';

  @override
  String get ideasBoardAction => 'Ver quadro';

  @override
  String get feedbackIdeasLink => 'Sugira e vote em ideias';

  @override
  String get feedbackTypeProblem => 'Problema';

  @override
  String get feedbackTypeIdea => 'Ideia';

  @override
  String get feedbackTypePraise => 'Elogio';

  @override
  String get feedbackTypeQuestion => 'Pergunta';

  @override
  String get feedbackPromptProblem =>
      'O que deu errado? Conte o que você fez e o que aconteceu.';

  @override
  String get feedbackPromptIdea =>
      'O que tornaria o WhisPaste melhor para você?';

  @override
  String get feedbackPromptPraise => 'O que funciona bem para você?';

  @override
  String get feedbackPromptQuestion => 'O que você gostaria de saber?';

  @override
  String get feedbackDiagnosticsLabel => 'Anexar diagnóstico';

  @override
  String get feedbackDiagnosticsExplanation =>
      'Adiciona a versão do app, o sistema operacional, o motor de reconhecimento de voz e o backend. Seus ditados e textos nunca são anexados.';

  @override
  String get feedbackDiagnosticsPreview => 'Mostrar prévia';

  @override
  String get feedbackDiagnosticsPreviewHide => 'Ocultar prévia';

  @override
  String get feedbackDiagnosticsPreviewHeading =>
      'Este texto exato é adicionado à sua mensagem:';

  @override
  String get feedbackIdeaBoardHint =>
      'Você também pode publicar sua ideia no quadro público de ideias e votar nas dos outros.';

  @override
  String get feedbackTextTooLong =>
      'O texto é longo demais para anexar o diagnóstico. Encurte-o um pouco.';

  @override
  String get hotkeyRegistrationFailed =>
      'Falha ao registrar o atalho. Defina sua combinação novamente nas Configurações.';

  @override
  String get hotkeySelfHealFailed =>
      'O atalho parou de responder e não pôde ser restaurado. Reinicie o WhisPaste para resolver.';

  @override
  String hotkeyFallbackActive(String taken, String active) {
    return '$taken já está em uso por outro app. Até você escolher outra combinação, $active inicia a gravação.';
  }

  @override
  String hotkeyConflictActive(String action) {
    return 'Outro aplicativo está usando o atalho de $action. Ele fica desativado até você escolher uma combinação livre em Configurações.';
  }

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Este atalho é reservado pelo $platform ($note) e pode não funcionar.';
  }

  @override
  String hotkeyConflictWarningDesktop(String note) {
    return 'Seu desktop reserva esta combinação de teclas: $note. Ela pode não funcionar.';
  }

  @override
  String get exportFormatPickerTitle => 'Escolha o formato de exportação';

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
      'A transcrição está demorando um pouco mais que o normal agora, mas continua funcionando.';

  @override
  String get recoveryExhaustedToast =>
      'O modelo de voz não pode iniciar. Reinicie o app ou recarregue o modelo de voz.';

  @override
  String get recoveryExhaustedAction => 'Abrir configurações';

  @override
  String get recoveryVcRuntimeToast =>
      'O modelo de voz não pode iniciar: falta um componente do Windows (Microsoft Visual C++). Instale o Visual C++ Redistributable (x64) e reinicie o WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Instalar';

  @override
  String get modelAbiInfoToast => 'Recarregando o modelo de voz, aguarde.';

  @override
  String get recoveryGpuDisabledToast =>
      'Por causa de um problema na última inicialização, o WhisPaste agora roda sem aceleração por GPU. A gravação continua funcionando normalmente.';

  @override
  String get serverDownloadFailedToast =>
      'Não foi possível baixar o modelo de voz. Verifique sua conexão com a internet?';

  @override
  String get serverDownloadFailedAction => 'Tentar novamente';

  @override
  String get serverDownloadStalledToast => 'Download travado: reconectando.';

  @override
  String get historyWriteFailedToast =>
      'Não foi possível salvar a entrada. Verifique o espaço de armazenamento disponível.';

  @override
  String get historyWriteFailedAction => 'Copiar diagnóstico';

  @override
  String get errorSttRejectEmpty =>
      'Nenhum áudio para transcrever. Grave novamente.';

  @override
  String get errorSttRejectInvalidWav =>
      'O arquivo de áudio está corrompido. Grave novamente.';

  @override
  String get errorSttRejectUnsupportedLanguage =>
      'Este idioma não é compatível com o modelo de voz local. Revise o idioma em Configurações.';

  @override
  String get errorSttRejectPromptTooLong =>
      'O vocabulário personalizado está muito longo. Encurte-o em Configurações.';

  @override
  String get settingsGpuAcceleration => 'Aceleração por GPU';

  @override
  String get settingsGpuAccelerationSubtitle =>
      'Automático usa a placa de vídeo quando ela está disponível. «Somente CPU» é mais lento, mas funciona em qualquer dispositivo. Escolha «GPU (forçado)» somente se o automático não funcionar.';

  @override
  String get settingsGpuAccelerationAuto => 'Automático (recomendado)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (forçado)';

  @override
  String get settingsGpuAccelerationDisabled => 'Somente CPU';

  @override
  String get settingsSttEngine => 'Modelo de voz';

  @override
  String get settingsSttEngineSubtitle =>
      'Whisper: 99 idiomas. Parakeet: mais rápido, cerca de 25 idiomas.';

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
    return 'Download único ($size), depois funciona totalmente offline';
  }

  @override
  String get parakeetModelDownload => 'Baixar';

  @override
  String get parakeetModelDownloading => 'Baixando…';

  @override
  String get parakeetModelInstalled => 'Instalado';

  @override
  String get parakeetModelDelete => 'Excluir';

  @override
  String get parakeetModelCancel => 'Cancelar';

  @override
  String get settingsSearchHint => 'Pesquisar configurações…';

  @override
  String get settingsSearchNoResults => 'Nenhum resultado';

  @override
  String get settingsSearchNoResultsHint => 'Tente outro termo de pesquisa.';

  @override
  String get settingsSearchFieldLabel => 'Pesquisar configurações';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Nenhum resultado',
    );
    return '$_temp0';
  }

  @override
  String get settingsPrivacy => 'Privacidade';

  @override
  String get settingsPrivacySubtitle =>
      'Controle quais dados o WhisPaste compartilha';

  @override
  String get settingsShareUsageStats => 'Ajude a melhorar o WhisPaste';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Contagens de uso sem cookies, enviadas ao nosso próprio servidor na UE. Nunca seu áudio ou texto.';

  @override
  String get settingsRetainRecentAudio => 'Manter áudio de gravações recentes';

  @override
  String get settingsFailedAudioKeep => 'Manter gravações com falha por';

  @override
  String get settingsFailedAudioKeepSubtitle =>
      'O áudio de uma gravação cuja transcrição falhou fica disponível para nova tentativa por este tempo e depois é excluído.';

  @override
  String settingsFailedAudioKeepDisabled(int days) {
    return 'Não é usado enquanto a retenção de áudio estiver ligada. Então vale o prazo de retenção de $days dias.';
  }

  @override
  String settingsRetainRecentAudioSubtitle(int count, int days) {
    return 'Mantém o áudio das suas últimas $count gravações neste dispositivo, para depuração ou para restaurar uma transcrição anterior; as gravações e os arquivos importados são excluídos automaticamente após no máximo $days dias';
  }

  @override
  String get pendingAudioRetentionNote =>
      'Uma gravação cuja transcrição falhou mantém o áudio para você tentar de novo, mesmo com esta opção desligada.';

  @override
  String get pendingAudioSectionTitle => 'Gravações aguardando nova tentativa';

  @override
  String get pendingAudioSectionBody =>
      'Estas gravações não puderam ser transcritas, por exemplo porque a conexão caiu. O áudio é excluído na data mostrada em cada gravação, ou quando você o descarta.';

  @override
  String pendingAudioKeptUntil(String until) {
    return 'O áudio fica guardado até $until e depois é excluído.';
  }

  @override
  String get pendingAudioEmpty => 'Nenhuma gravação aguarda.';

  @override
  String get notesNewNote => 'Nova nota';

  @override
  String get notesEmptyTitle => 'Nenhuma nota ainda';

  @override
  String get notesEmptyHint =>
      'Crie uma nota para começar a reunir texto de qualquer lugar.';

  @override
  String get notesUntitled => 'Nota sem título';

  @override
  String get notesEditorPlaceholder => 'Comece a digitar…';

  @override
  String get notesListSemantics => 'Lista de notas';

  @override
  String get notesCopy => 'Copiar nota';

  @override
  String get notesCopied => 'Nota copiada';

  @override
  String get notesFavorite => 'Marcar como favorita';

  @override
  String get notesUnfavorite => 'Remover dos favoritos';

  @override
  String get notesQuickNoteSet =>
      'Definir como nota rápida: o atalho acrescenta texto a ela';

  @override
  String get notesQuickNoteClear => 'Nota rápida — remover a marcação';

  @override
  String get notesQuickNoteHotkeyLabel => 'Atalho';

  @override
  String notesQuickNoteHotkeyChange(String combination) {
    return 'Alterar o atalho da nota rápida — atualmente $combination';
  }

  @override
  String get notesQuickNoteHotkeyOff =>
      'O atalho da nota rápida está desativado.';

  @override
  String get notesQuickNoteHotkeyEnable => 'Ativar atalho';

  @override
  String get notesMoveToTrash => 'Mover para a lixeira';

  @override
  String get notesMovedToTrash => 'Movida para a lixeira';

  @override
  String get notesRestore => 'Restaurar';

  @override
  String get notesDeleteForever => 'Excluir definitivamente';

  @override
  String get notesDeleteForeverConfirm => 'Excluir a nota definitivamente?';

  @override
  String get notesTrash => 'Lixeira';

  @override
  String get notesTrashEmpty => 'A lixeira está vazia';

  @override
  String get notesTrashEmptyHint =>
      'Notas excluídas vão para cá e não são removidas automaticamente.';

  @override
  String get notesUndo => 'Desfazer';

  @override
  String get notesAddTag => 'Adicionar tag';

  @override
  String get notesTagPlaceholder => 'Nome da tag…';

  @override
  String get notesSearchPlaceholder => 'Pesquisar notas…';

  @override
  String get notesSearchFieldLabel => 'Pesquisar notas';

  @override
  String get notesNoResults => 'Nenhum resultado';

  @override
  String notesNoResultsHint(String query) {
    return 'Nenhuma nota corresponde a \"$query\".\nTente outro termo de pesquisa.';
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
    return 'Negrito ($shortcut)';
  }

  @override
  String markdownToolbarItalic(String shortcut) {
    return 'Itálico ($shortcut)';
  }

  @override
  String get markdownToolbarHeading => 'Título';

  @override
  String markdownToolbarBulletList(String shortcut) {
    return 'Lista com marcadores ($shortcut)';
  }

  @override
  String get markdownToolbarNumberedList => 'Lista numerada';

  @override
  String get markdownToolbarQuote => 'Citação';

  @override
  String get markdownToolbarCode => 'Código';

  @override
  String get findReplaceToggle => 'Localizar e substituir neste texto';

  @override
  String get findReplaceFindLabel => 'Localizar neste texto';

  @override
  String get findReplaceFindHint => 'Localizar…';

  @override
  String get findReplaceReplaceLabel => 'Substituir ocorrências por';

  @override
  String get findReplaceReplaceHint => 'Substituir por…';

  @override
  String get findReplaceNext => 'Próxima ocorrência';

  @override
  String get findReplacePrevious => 'Ocorrência anterior';

  @override
  String get findReplaceReplaceAction => 'Substituir esta ocorrência';

  @override
  String get findReplaceReplaceAllAction => 'Substituir todas as ocorrências';

  @override
  String get findReplaceClose => 'Fechar localizar e substituir';

  @override
  String get findReplaceNoMatches => 'Nenhuma ocorrência';

  @override
  String findReplaceMatchCount(int current, int total) {
    return '$current de $total';
  }

  @override
  String get sidePanelTranscriptionsTitle => 'Transcrições';

  @override
  String get sidePanelSnippetsTitle => 'Snippets';

  @override
  String get sidePanelClipboardHistoryTitle =>
      'Histórico da área de transferência';

  @override
  String get sidePanelClipboardHistoryEmpty => 'Nada copiado ainda';

  @override
  String get sidePanelClipboardHistoryEmptyHint =>
      'Tudo o que você copiar enquanto o WhisPaste estiver em execução aparece aqui — é apagado quando o app reinicia.';

  @override
  String get sidePanelClipboardLockedTitle => 'Bloqueado por PIN';

  @override
  String get sidePanelClipboardLockedHint =>
      'O texto copiado fica oculto enquanto as gravações estiverem bloqueadas. Desbloqueie-as com o seu PIN para o ver de novo.';

  @override
  String get sidePanelClose => 'Fechar painel';

  @override
  String get sidePanelSearchHint => 'Pesquisar';

  @override
  String get sidePanelSearchFieldLabel => 'Pesquisar nesta lista';

  @override
  String get sidePanelNoMatches => 'Nenhuma correspondência';

  @override
  String get sidePanelNoMatchesHint => 'Tente outro termo de pesquisa.';

  @override
  String get sidePanelLoadFailedHint =>
      'Feche o painel e abra-o de novo para tentar outra vez.';

  @override
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Limpeza, encurtamento e tradução de texto local após a gravação';

  @override
  String get smartModeStandardPreset => 'Predefinição padrão';

  @override
  String get smartModePresetOff => 'Desativado';

  @override
  String get smartModePresetOffDescription =>
      'Nenhum pós-processamento automático — o texto transcrito é usado exatamente como foi transcrito.';

  @override
  String get smartModePresetCleanup => 'Limpeza';

  @override
  String get smartModePresetCleanupDescription =>
      'Remove palavras de preenchimento como \"hum\" e corrige pontuação e maiúsculas, sem alterar a redação, o sentido ou o idioma.';

  @override
  String get smartModePresetConcise => 'Conciso';

  @override
  String get smartModePresetConciseDescription =>
      'Encurta o texto eliminando redundâncias e palavras de preenchimento, mantendo todos os fatos importantes, no mesmo idioma.';

  @override
  String get smartModePresetTranslate => 'Traduzir';

  @override
  String get smartModePresetTranslateDescription =>
      'Traduz o texto transcrito para o idioma de destino definido abaixo.';

  @override
  String get smartModeTargetLanguage => 'Idioma de destino';

  @override
  String get smartModeTargetLanguageGerman => 'Alemão';

  @override
  String get smartModeTargetLanguageEnglish => 'Inglês';

  @override
  String get smartModeTargetLanguageSpanish => 'Espanhol';

  @override
  String get smartModeTargetLanguageFrench => 'Francês';

  @override
  String get smartModeTargetLanguagePortuguese => 'Português';

  @override
  String get smartModeTargetLanguageMandarin => 'Mandarim';

  @override
  String get smartModeTargetLanguageRussian => 'Russo';

  @override
  String get smartModeDownload => 'Baixar';

  @override
  String get smartModeDownloadComplete => 'Modelo de texto pronto para uso';

  @override
  String get smartModeRamWarningTitle => 'Memória limitada detectada';

  @override
  String get smartModeRamWarningBody =>
      'O modelo de texto local do Smart Mode funciona melhor com 8 GB de RAM ou mais. Pode funcionar mesmo assim, mas pode ser lento ou falhar neste computador. Baixar mesmo assim?';

  @override
  String get smartModeRamWarningContinue => 'Baixar mesmo assim';

  @override
  String get smartModeRamWarningCancel => 'Cancelar';

  @override
  String get modelRamPrecheckTitle => 'Pouca memória livre';

  @override
  String modelRamPrecheckBody(String requiredMb, String availableMb) {
    return 'Este modelo precisa de cerca de $requiredMb MB de memória, e agora há cerca de $availableMb MB livres. Pode ficar lento ou não carregar. Carregar mesmo assim?';
  }

  @override
  String get modelRamPrecheckContinue => 'Carregar mesmo assim';

  @override
  String modelRamStartupHint(String requiredMb, String availableMb) {
    return 'O modelo de voz escolhido precisa de cerca de $requiredMb MB de memória, e agora há cerca de $availableMb MB livres. Ele carrega mesmo assim; feche outros apps se o ditado ficar lento.';
  }

  @override
  String get smartModeModelDeleteConfirm => 'Excluir este modelo de texto?';

  @override
  String get smartModeModelDeleteConfirmMessage =>
      'O arquivo do modelo de texto é excluído deste dispositivo. Você pode baixá-lo novamente a qualquer momento.';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Com o modelo de texto local, tudo roda no dispositivo. Enquanto ativo, o modelo de texto usa cerca de 4–5 GB de RAM além do espaço em disco — compartilhados com o modelo de voz, então o uso total de memória depende de qual modelo de voz você também tem carregado.';

  @override
  String get smartModeFactGuardHint =>
      'O guardião de factos verifica números, datas, links, e-mails e IBANs. Os nomes do dicionário são mantidos. Instruções livres podem alterar nomes que não estão no dicionário; adicione-os ao dicionário se devem ser mantidos.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Exemplo: uma gravação típica de 50 palavras leva cerca de 1 a 6 segundos para ser processada, dependendo do hardware do seu dispositivo.';

  @override
  String get smartModeLocalUnavailable =>
      'O Smart Mode no dispositivo não está incluído nesta versão. Mude para a OpenAI ou instale uma versão oficial do WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Gravar com Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Inicia uma gravação com uma predefinição fixa, independente da predefinição padrão do Smart Mode. “Manter pressionado para gravar” também vale aqui.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Predefinição';

  @override
  String get settingsSmartModeCurrentHotkey => 'Atalho atual';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Esta combinação já está em uso para “$action”. Escolha outra.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho do Smart Mode não está ativo no momento. Escolha outra combinação.';

  @override
  String get smartModeOnboardingHintTitle => 'Experimente o Smart Mode';

  @override
  String smartModeOnboardingHintBody(String size) {
    return 'O Smart Mode pode limpar, encurtar ou traduzir seu texto automaticamente, por padrão, totalmente no seu dispositivo. O modelo de texto local ocupa $size no disco. Baixe agora ou configure depois nas Configurações.';
  }

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Texto bruto';

  @override
  String get smartModeOnboardingHintExampleBefore =>
      'então hum o encontro com o cliente foi mudado para quinta às três da tarde e ah ainda precisamos dos slides atualizados do marketing';

  @override
  String get smartModeOnboardingHintExampleAfterLabel =>
      'Resultado do Smart Mode';

  @override
  String get smartModeOnboardingHintExampleAfter =>
      'O encontro com o cliente foi remarcado para quinta-feira às 15h, e ainda precisamos dos slides atualizados do Marketing.';

  @override
  String get smartModeOnboardingHintDownloadCta => 'Baixar';

  @override
  String get smartModeOnboardingHintSkipCta => 'Depois';

  @override
  String get smartModeUsageHintTitle =>
      'Experimente o Smart Mode na sua próxima gravação';

  @override
  String get smartModeUsageHintBody =>
      'O Smart Mode pode limpar, encurtar ou traduzir um texto como este automaticamente, direto no seu dispositivo. Veja o que você acabou de dizer:';

  @override
  String get smartModeUsageHintCta => 'Configurar';

  @override
  String get smartModeUsageHintDismiss => 'Agora não';

  @override
  String get settingsAutomationApi => 'API local de automação';

  @override
  String get settingsAutomationApiSubtitle =>
      'Outros programas e scripts deste computador podem controlar o WhisPaste, por exemplo iniciar uma gravação. Outros dispositivos da rede não conseguem acessá-lo.';

  @override
  String get settingsAutomationApiEnable => 'Ativar API local de automação';

  @override
  String get settingsAutomationApiEnableSubtitle =>
      'Vincula-se apenas a 127.0.0.1/::1 — nunca acessível pela rede';

  @override
  String settingsAutomationApiStatusRunning(int port) {
    return 'Em execução na porta $port';
  }

  @override
  String settingsAutomationApiStatusRunningFallback(
    int port,
    int requestedPort,
  ) {
    return 'Em execução na porta $port (a porta $requestedPort estava em uso)';
  }

  @override
  String get settingsAutomationApiStatusStopped => 'Não está em execução';

  @override
  String settingsAutomationApiStatusError(int start, int end) {
    return 'Nenhuma porta livre encontrada no intervalo $start–$end';
  }

  @override
  String get settingsAutomationApiCustomPortLabel => 'Porta personalizada';

  @override
  String get settingsAutomationApiCustomPortSubtitle =>
      'Deixe em branco para escolher a porta automaticamente — se ela estiver ocupada, outra é usada';

  @override
  String get settingsAutomationApiCustomPortHint => 'Automática';

  @override
  String get settingsAutomationApiCustomPortInvalid =>
      'Digite uma porta entre 1024 e 65535';

  @override
  String get settingsAutomationApiToken => 'Token Bearer';

  @override
  String get settingsAutomationApiTokenSubtitle =>
      'Envie como \"Authorization: Bearer <token>\" — toda requisição sem ele é rejeitada';

  @override
  String get settingsAutomationApiRegenerate => 'Gerar novamente';

  @override
  String get settingsAutomationApiRegenerateConfirmTitle =>
      'Gerar um novo token?';

  @override
  String get settingsAutomationApiRegenerateConfirmMessage =>
      'O token atual deixa de funcionar imediatamente. Qualquer script que o use precisará do novo.';

  @override
  String get settingsAutomationApiCopyToken => 'Copiar token';

  @override
  String get settingsAutomationApiTokenCopied =>
      'Token copiado para a área de transferência';

  @override
  String get settingsAutomationApiDocumentation => 'Documentação';

  @override
  String get settingsAutomationApiDocumentationSubtitle =>
      'Referência de endpoints e exemplos com curl';

  @override
  String get settingsAutomationApiDocumentationAction => 'Abrir';

  @override
  String historyCharacterCount(int count) {
    return '$count caracteres';
  }

  @override
  String historyPastedInto(String app) {
    return 'Colado em $app';
  }

  @override
  String get historyShowOriginalTranscript => 'Mostrar transcrição original';

  @override
  String get historyHideOriginalTranscript => 'Ocultar transcrição original';

  @override
  String get historyOriginalTranscriptLabel => 'Transcrição original';

  @override
  String get settingsHotkeyActionSelectionEdit => 'Editar seleção';

  @override
  String get settingsSelectionEditHotkeyEnabled => 'Editar seleção';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Selecione texto em qualquer app, pressione este atalho e diga o que mudar — ou apenas \"mais curto\", \"melhorar\" ou \"traduzir\". O resultado substitui a seleção; desfazer no app traz o original de volta. Usa o modelo de texto configurado no Smart Mode.';

  @override
  String get settingsSelectionEditHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho de editar seleção não está ativo no momento. Escolha outra combinação.';

  @override
  String get overlayTargetSelectionEdit => 'Editar seleção';

  @override
  String get overlayRecordingSelectionEdit => 'Diga o que mudar';

  @override
  String get overlaySelectionEditHint =>
      'Diga o que mudar — ou: mais curto · melhorar · traduzir';

  @override
  String get overlayEditingSelection => 'Editando seleção…';

  @override
  String get overlayDoneSelectionEdit => 'Seleção substituída';

  @override
  String get errorSelectionEditNoSelection =>
      'Nenhum texto selecionado — selecione um texto primeiro e depois pressione o atalho';

  @override
  String get errorSelectionEditNoEngine =>
      'Configure o Smart Mode primeiro (baixe o modelo de texto local ou adicione uma chave da OpenAI) para editar seleções';

  @override
  String get errorSelectionEditUnsupported =>
      'Editar uma seleção exige o Auto-Paste, que não está disponível nesta versão';

  @override
  String get errorSelectionEditCopyFailed =>
      'Não foi possível ler a seleção — verifique a permissão do Auto-Paste';

  @override
  String get errorSelectionEditFailed =>
      'A edição falhou — seu texto foi mantido sem alterações';

  @override
  String get errorSelectionEditFactsChanged =>
      'A edição alteraria dados que a sua instrução não menciona — seu texto foi mantido sem alterações';

  @override
  String errorSelectionEditFactsChangedValue(String value) {
    return 'A edição alteraria «$value» sem que a sua instrução o mencione. Indique o valor antigo e o novo, p. ex. «troque 3 por 5»; o seu texto não mudou';
  }

  @override
  String get errorSelectionEditPasteFailed =>
      'Não foi possível substituir a seleção — seu texto foi mantido sem alterações';

  @override
  String get settingsCudaPackTitle => 'Aceleração NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Transcrição mais rápida em placas GeForce RTX e GTX 16. Download único de $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Instalado. Se o driver de vídeo for antigo demais, o WhisPaste continua usando Vulkan.';

  @override
  String get settingsCudaPackConsentRequired => 'Consentimento necessário';

  @override
  String get settingsCudaPackConsentReview => 'Revisar licença';

  @override
  String get settingsCudaPackDownload => 'Baixar';

  @override
  String settingsCudaPackDownloading(int percent) {
    return 'Baixando $percent %';
  }

  @override
  String get settingsCudaPackInstalling => 'Instalando …';

  @override
  String get settingsCudaPackCancel => 'Cancelar download';

  @override
  String get settingsCudaPackRemove => 'Remover pacote CUDA';

  @override
  String get settingsCudaPackRemoveConfirm => 'Remover o pacote CUDA?';

  @override
  String get settingsCudaPackRemoveConfirmMessage =>
      'O pacote CUDA é removido deste dispositivo. Você pode baixá-lo novamente a qualquer momento.';

  @override
  String get settingsCudaPackToggle => 'Usar CUDA';

  @override
  String get settingsCudaPackErrorNetwork =>
      'O download falhou. Verifique a conexão e tente novamente.';

  @override
  String get settingsCudaPackErrorVerification =>
      'O download chegou corrompido. Tente novamente.';

  @override
  String get settingsCudaPackErrorStorage =>
      'Não foi possível salvar o pacote. Verifique o espaço livre em disco.';

  @override
  String get cudaEulaDialogTitle => 'Licença NVIDIA CUDA';

  @override
  String cudaEulaDialogBody(String version) {
    return 'O pacote CUDA contém componentes da NVIDIA sob o Contrato de Licença de Usuário Final NVIDIA CUDA ($version). Você aceita o texto completo desta versão, que pode ler em «Ver texto completo». Uma versão posterior na NVIDIA pode diferir. Você precisa aceitá-lo para baixar.';
  }

  @override
  String get cudaEulaDialogLink => 'Outra versão na NVIDIA';

  @override
  String get cudaEulaFullTextOpen => 'Ver texto completo';

  @override
  String get cudaEulaFullTextClose => 'Fechar';

  @override
  String get cudaEulaDialogCancel => 'Cancelar';

  @override
  String get cudaEulaDialogAccept => 'Aceitar e baixar';

  @override
  String get recoveryCudaDisabledToast =>
      'A aceleração CUDA foi desativada por causa de um problema na última inicialização. O WhisPaste agora usa Vulkan, e a gravação funciona normalmente.';

  @override
  String get recoveryGpuProbeFailedToast =>
      'A aceleração por GPU não é usada nesta sessão: a verificação da placa de vídeo não foi concluída. O WhisPaste transcreve com o processador. Gravar funciona normalmente.';

  @override
  String get settingsGpuProbeTitle => 'Verificação da GPU';

  @override
  String get settingsGpuProbeNotChecked =>
      'Ainda não verificada. A verificação ocorre ao carregar o modelo pela primeira vez.';

  @override
  String get settingsGpuProbeUsable => 'Verificada: a placa de vídeo é usada.';

  @override
  String get settingsGpuProbeUnusable =>
      'Não utilizável: o WhisPaste usa o processador. Verifique de novo após atualizar o driver ou o app.';

  @override
  String get settingsGpuProbeRetry => 'Verificar novamente';

  @override
  String get supportPromptSnooze => 'Não perguntar por 90 dias';

  @override
  String get supportPayPalLabel => 'PayPal';

  @override
  String get supportStoreThankYouLine =>
      'Obrigado por comprar o WhisPaste na loja. Qualquer apoio extra é opcional.';

  @override
  String get supportShareText =>
      'Eu uso o WhisPaste para escrever com a voz direto nos meus apps. Local no meu computador e de código aberto:';

  @override
  String get supportPageTitle => 'Apoiar o WhisPaste';

  @override
  String get supportIntroDirect =>
      'O WhisPaste é gratuito e de código aberto. Uma contribuição ou uma recomendação ajuda o projeto.';

  @override
  String get supportCostsNote =>
      'As contribuições ajudam a cobrir o desenvolvimento e os custos contínuos de publicação, hospedagem e domínio.';

  @override
  String get supportSectionOnce => 'Apoio único';

  @override
  String get supportSectionOthers => 'Outras formas de apoiar';

  @override
  String get supportSectionReach => 'Recomendar o WhisPaste';

  @override
  String get supportStoreTitleWindows => 'WhisPaste na Microsoft Store';

  @override
  String get supportStoreTitleMac => 'WhisPaste na Mac App Store';

  @override
  String get supportStoreFactManaged =>
      'A instalação e as atualizações são feitas pela loja.';

  @override
  String get supportStoreFactPurchase => 'Sua compra única apoia o WhisPaste.';

  @override
  String get supportStoreFactSameFeatures =>
      'As mesmas funções. A versão direta continua gratuita.';

  @override
  String get supportStoreCtaWindows => 'Ver na Microsoft Store';

  @override
  String get supportStoreCtaMac => 'Ver na Mac App Store';

  @override
  String get supportStorePriceNote => 'Preço na loja';

  @override
  String get supportStoreCoffeeNote =>
      'Uma compra única, mais ou menos o preço de um café. A loja mostra o preço atual.';

  @override
  String get supportStoreDismiss => 'Ocultar opção da loja';

  @override
  String get supportStoreShowAgain => 'Mostrar opção da loja';

  @override
  String get supportSponsorsCta => 'Abrir GitHub Sponsors';

  @override
  String get supportSponsorsNote =>
      'Mensal ou com um valor à sua escolha. Escolha o valor e a periodicidade por lá.';

  @override
  String get supportKofiCta => 'Abrir Ko-fi';

  @override
  String get coffeeButtonLabel => 'Me pague um café';

  @override
  String get coffeeButtonHint =>
      'O WhisPaste é gratuito e de código aberto. Um café ajuda a continuar o desenvolvimento.';

  @override
  String get coffeeBuyMeACoffeeLabel => 'Buy Me a Coffee';

  @override
  String get supportPayPalCta => 'Apoiar com PayPal';

  @override
  String get supportNativeTitle => 'Apoiar uma vez na loja';

  @override
  String get supportNativeDescription =>
      'Um valor único cobrado pela loja. Mesmas funções, sem assinatura.';

  @override
  String get supportNativeCta => 'Apoiar uma vez';

  @override
  String get supportSheetChoose => 'Escolha um valor';

  @override
  String get supportSheetLoading => 'Carregando valores …';

  @override
  String supportSheetBuy(String price) {
    return 'Apoiar por $price';
  }

  @override
  String get supportSheetPurchasing => 'A loja está confirmando sua compra …';

  @override
  String get supportSheetThanks => 'Obrigado pelo seu apoio!';

  @override
  String get supportSheetThanksDetail =>
      'Seu selo de apoiador já está ativo. Todas as funções continuam disponíveis para todos.';

  @override
  String get supportSheetPending => 'Sua compra aguarda confirmação.';

  @override
  String get supportSheetPurchaseError =>
      'Não foi possível concluir a compra. Tente novamente mais tarde.';

  @override
  String get supportSheetPricesError =>
      'Não foi possível carregar os valores. Tente novamente mais tarde.';

  @override
  String get supportSheetUnavailable =>
      'No momento não há valores disponíveis na loja.';

  @override
  String get supportSheetRetry => 'Tentar novamente';

  @override
  String get supportSheetClose => 'Fechar';

  @override
  String get supportSelfDeclareCta => 'Já apoio o WhisPaste';

  @override
  String get supportSelfDeclareNote =>
      'Apenas um registro neste dispositivo, nada é verificado. O botão de apoio na barra de status fica oculto.';

  @override
  String get supportSelfDeclareHint =>
      'Nada é verificado. Use isto se já contribuiu.';

  @override
  String get supportSupporterLine => 'Você apoia o WhisPaste. Obrigado!';

  @override
  String get supportSupporterBadge => 'Apoiador';

  @override
  String get supportRateCta => 'Avaliar na loja';

  @override
  String get supportShareCopy => 'Copiar link';

  @override
  String get supportShareCopied => 'Link copiado';

  @override
  String get externalLinkOpenFailed => 'Não foi possível abrir o link';

  @override
  String get externalLinkCopyAddress => 'Copiar endereço';

  @override
  String get supportShareEmail => 'E-mail';

  @override
  String get supportChipLabel => 'Patrocinador';

  @override
  String get supportChipTooltip => 'Apoiar o WhisPaste';

  @override
  String get supportChipThanksLabel => 'Obrigado';

  @override
  String get supportChipThanksTooltip => 'Obrigado pelo seu apoio';

  @override
  String get settingsSponsorChip => 'Botão de apoio na barra de status';

  @override
  String get settingsSponsorChipSubtitle =>
      'Mostra o caminho para a página de apoio. Você pode ocultá-lo a qualquer momento e voltar a exibi-lo aqui.';

  @override
  String get automationPreviewTitle => 'Inserir texto com várias linhas?';

  @override
  String get automationPreviewBody =>
      'A automação quer inserir texto com quebras de linha. Verifique-o antes que chegue ao app ativo.';

  @override
  String automationPreviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count linhas',
      one: '1 linha',
    );
    return '$_temp0';
  }

  @override
  String get automationPreviewInsert => 'Inserir';

  @override
  String get automationPreviewCancel => 'Cancelar';

  @override
  String get automationIntegrationsHeading => 'Integrações';

  @override
  String get automationIntegrationsHooksTitle =>
      'Enviar eventos para outros apps';

  @override
  String get automationIntegrationsHooksSubtitle =>
      'Envia transcrições concluídas e notas alteradas para um app neste computador. Os hooks continuam disparando mesmo com o servidor da API desligado.';

  @override
  String automationIntegrationsHooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hooks',
      one: '1 hook',
      zero: 'Nenhum hook',
    );
    return '$_temp0';
  }

  @override
  String get automationIntegrationsHooksManage => 'Gerenciar';

  @override
  String get automationIntegrationsCliTitle => 'Linha de comando e MCP';

  @override
  String automationIntegrationsCliSubtitle(
    String path,
    String token,
    String command,
  ) {
    return 'Somente a partir do código-fonte. Execute $path com $token definido; o comando $command inicia o servidor MCP.';
  }

  @override
  String get automationHooksIntro =>
      'Textos finalizados e notas alteradas são enviados a um app neste computador. O endereço precisa estar neste dispositivo.';

  @override
  String get automationHooksEmpty => 'Nenhuma conexão configurada ainda.';

  @override
  String get automationHooksUrlLabel =>
      'Endereço de destino (somente este computador)';

  @override
  String get automationHooksEventsLabel => 'Eventos';

  @override
  String get automationHooksEventTranscript => 'Transcrição concluída';

  @override
  String get automationHooksEventNote => 'Nota alterada';

  @override
  String get automationHooksAdd => 'Adicionar hook';

  @override
  String get automationHooksRemove => 'Remover hook';

  @override
  String get automationHooksRemoveConfirm => 'Remover este hook?';

  @override
  String get automationHooksRemoveConfirmMessage =>
      'O hook é removido da lista. Você pode adicioná-lo novamente depois.';

  @override
  String automationHooksInvalidUrl(
    String ipv4,
    String ipv6,
    String localhost,
    String example,
  ) {
    return 'Use $ipv4, $ipv6 ou $localhost com uma porta, por exemplo $example.';
  }

  @override
  String get automationHooksNoEvents => 'Escolha pelo menos um evento.';

  @override
  String automationHooksTooMany(int max) {
    return 'Você pode adicionar até $max hooks.';
  }

  @override
  String get automationHooksDone => 'Concluído';

  @override
  String get navSmartMode => 'Smart Mode';

  @override
  String get dockDictate => 'Ditar';

  @override
  String get dockOverflow => 'Mais';

  @override
  String get dockMenuGroupStatus => 'Estado';

  @override
  String get dockMenuGroupNotices => 'Avisos';

  @override
  String get dockMenuHotkeyChange => 'Alterar atalho…';

  @override
  String get dockMenuSmartModeSettings => 'Configurações do Smart Mode…';

  @override
  String get dockMenuSttModels => 'Gerir modelos de voz…';

  @override
  String get dockMenuGroupCloud => 'Nuvem';

  @override
  String get dockMenuModelDownload => 'Baixar';

  @override
  String get dockMenuModelLoading => 'carregando';

  @override
  String get dockMenuSttLockedReason =>
      'Não é possível alterar durante uma gravação';

  @override
  String get dockMenuSearchHint => 'Pesquisar…';

  @override
  String get dockMenuSearchNoMatches => 'Nenhum resultado';

  @override
  String get dockMenuAppliesNextRecording =>
      'Vale a partir da próxima gravação';

  @override
  String get dockStopDictation => 'Parar gravação';

  @override
  String get historyImportAddFiles => 'Adicionar arquivos';

  @override
  String historyImportDescription(String formats) {
    return 'Transcreve arquivos de áudio ($formats) neste dispositivo. Arraste os arquivos para esta página ou adicione-os.';
  }

  @override
  String get historyImportQueueTitle => 'Fila de importação';

  @override
  String get historyImportStatusQueued => 'Aguardando';

  @override
  String get historyImportStatusCopying => 'Copiando';

  @override
  String get historyImportStatusDecoding => 'Decodificando';

  @override
  String get historyImportStatusTranscribing => 'Transcrevendo';

  @override
  String historyImportElapsed(String elapsed) {
    return 'Em andamento há $elapsed';
  }

  @override
  String historyImportPercent(int percent) {
    return '$percent%';
  }

  @override
  String get historyImportStatusDone => 'Concluído';

  @override
  String get historyImportStatusFailed => 'Falhou';

  @override
  String get historyImportStatusCancelled => 'Cancelado';

  @override
  String get historyImportFailureCopy =>
      'Não foi possível copiar o arquivo. Verifique se ele ainda existe e pode ser lido, e tente novamente.';

  @override
  String get historyImportFailureUnsupported =>
      'Este formato não é compatível com esta plataforma. Converta o arquivo para WAV e importe-o novamente.';

  @override
  String get historyImportFailureDecode =>
      'Não foi possível decodificar o arquivo. Provavelmente está danificado ou incompleto. Importe outra cópia ou converta para WAV.';

  @override
  String get historyImportFailureInputLimit =>
      'O arquivo é grande demais ou tem mais de 6 horas. Divida-o em partes menores.';

  @override
  String get historyImportFailureTranscription =>
      'A transcrição falhou. Verifique o reconhecimento de fala nas configurações e tente novamente.';

  @override
  String get historyImportFailureSave =>
      'Não foi possível salvar a transcrição. Verifique o espaço livre no disco e tente novamente.';

  @override
  String get historyImportRejectionsTitle => 'Arquivos não importados';

  @override
  String get historyImportRejectedFolder =>
      'Não é possível importar pastas. Escolha os arquivos de áudio dentro delas.';

  @override
  String get historyImportRejectedNotFound => 'O arquivo não foi encontrado.';

  @override
  String historyImportRejectedType(String formats) {
    return 'Este tipo de arquivo não pode ser importado. Compatíveis: $formats.';
  }

  @override
  String get historyImportDialogFailed =>
      'Não foi possível abrir a janela de arquivos. Tente novamente ou arraste os arquivos para esta página.';

  @override
  String get historyImportDropHere =>
      'Solte os arquivos de áudio aqui para transcrevê-los';

  @override
  String get historyImportCancel => 'Cancelar importação';

  @override
  String get historyImportRetry => 'Repetir importação';

  @override
  String get recoveryOffer =>
      'Foi encontrada uma gravação interrompida. Recuperar o áudio e transcrevê-lo?';

  @override
  String get recoveryNoAudioKept =>
      'Foi encontrada uma gravação interrompida, mas nenhum áudio foi guardado porque a retenção de áudio está desativada.';

  @override
  String get recoveryNoAudioCaptured =>
      'Foi encontrada uma gravação interrompida, mas ela não contém áudio.';

  @override
  String get recoveryRestore => 'Recuperar';

  @override
  String get recoveryDiscard => 'Descartar';

  @override
  String get recoveryDiscardConfirm => 'Descartar esta gravação?';

  @override
  String get recoveryDiscardConfirmMessage =>
      'Esta gravação interrompida é removida deste dispositivo, junto com o áudio que tiver sido guardado.';

  @override
  String historyStatusRecovery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gravações interrompidas',
      one: '1 gravação interrompida',
    );
    return '$_temp0';
  }

  @override
  String historyStatusImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count importações',
      one: '1 importação',
    );
    return '$_temp0';
  }

  @override
  String historyRecoverySummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gravações interrompidas aguardam recuperação',
      one: '1 gravação interrompida aguarda recuperação',
    );
    return '$_temp0';
  }

  @override
  String historyImportQueueSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fila de importação: $count arquivos',
      one: 'Fila de importação: 1 arquivo',
    );
    return '$_temp0';
  }

  @override
  String get pendingAudioDiscardConfirmMessage =>
      'O áudio salvo será removido deste dispositivo. Depois disso, não é possível tentar novamente.';

  @override
  String get recoveryFailed =>
      'A recuperação falhou. O áudio foi mantido e você pode tentar novamente.';

  @override
  String recoverySkippedCorrupt(int count) {
    return '$count entradas de recuperação danificadas foram ignoradas e mantidas no disco.';
  }

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupDictation => 'Entrada de voz';

  @override
  String get settingsGroupSystem => 'Sistema';

  @override
  String get settingsAreaGeneral => 'Geral';

  @override
  String get settingsAreaAppearance => 'Aparência';

  @override
  String get settingsAreaShortcuts => 'Atalhos de teclado';

  @override
  String settingsSmartModeShortcutLink(String combo) {
    return 'Atalho de teclado: $combo';
  }

  @override
  String get settingsAreaRecording => 'Gravação e áudio';

  @override
  String get settingsAreaSpeech => 'Reconhecimento de fala';

  @override
  String get settingsAreaTextInsert => 'Texto e inserção';

  @override
  String get settingsAreaPrivacy => 'Privacidade e dados';

  @override
  String get settingsAreaAdvanced => 'Avançado';

  @override
  String settingsNavVersion(String version) {
    return 'WhisPaste $version';
  }

  @override
  String get settingsNavUpToDate => 'Atualizado';

  @override
  String get settingsNavUpdateAvailable => 'Atualização disponível';

  @override
  String get settingsNavStoreUpdates => 'Atualizações pela loja';

  @override
  String get settingsStoreUpdatesUnavailable =>
      'A loja entrega as atualizações desta versão. A verificação de atualizações no app não está disponível aqui.';

  @override
  String get settingsStoreBetaUnavailable =>
      'Versões de teste não são oferecidas na versão da loja.';

  @override
  String get settingsStoreCudaUnavailable =>
      'Não disponível na versão da loja: downloads de drivers de fora da loja não são permitidos ali.';

  @override
  String get settingsOverlayPreview => 'Pré-visualização do overlay';

  @override
  String get settingsPreviewTitle => 'Pré-visualização';

  @override
  String get settingsPreviewHint =>
      'É assim que o overlay e o botão aparecem em repouso e ao gravar. As alterações valem na hora.';

  @override
  String get settingsPreviewOverlayCaption => 'Overlay';

  @override
  String get settingsPreviewButtonIdleCaption => 'Pronto';

  @override
  String get settingsPreviewButtonRecordingCaption => 'Gravando';

  @override
  String get settingsOverlayOptionsGroup => 'Overlay';

  @override
  String get settingsOverlayForm => 'Forma';

  @override
  String get settingsOverlayFormSubtitle =>
      'Pílula ou retângulo com cantos arredondados.';

  @override
  String get settingsOverlayFormPill => 'Pílula';

  @override
  String get settingsOverlayFormRoundedRect => 'Arredondado';

  @override
  String get settingsOverlayWaveStyle => 'Estilo da onda';

  @override
  String get settingsOverlayWaveStyleSubtitle =>
      'Como sua voz aparece no overlay.';

  @override
  String get settingsOverlayWaveBars => 'Barras';

  @override
  String get settingsOverlayWaveLine => 'Linha';

  @override
  String get settingsOverlayWaveDots => 'Pontos';

  @override
  String get settingsOverlayWaveFluid => 'Contorno fluido';

  @override
  String get settingsOverlayWaveFluidSubtitle =>
      'A borda reage à sua voz. Desligado com «Reduzir movimento».';

  @override
  String get settingsOverlayShowTimer => 'Mostrar tempo';

  @override
  String get settingsOverlayShowTimerSubtitle =>
      'Mostra o tempo de gravação decorrido.';

  @override
  String get settingsOverlayShowCancel => 'Símbolo de cancelar';

  @override
  String get settingsOverlayShowCancelSubtitle =>
      'Parar fica sempre visível. Esc continua cancelando.';

  @override
  String get settingsOverlayOpacity => 'Opacidade';

  @override
  String get settingsOverlayOpacitySubtitle =>
      'É aumentada automaticamente se a onda ficaria fraca demais.';

  @override
  String get settingsOverlayOpacityFull => '100 %';

  @override
  String get settingsOverlayOpacityReduced => '80 %';

  @override
  String get settingsOverlayOpacitySubtle => '60 %';

  @override
  String get settingsFloatingButtonSize => 'Tamanho';

  @override
  String get settingsFloatingButtonSizeSubtitle =>
      'Diâmetro do botão flutuante';

  @override
  String get settingsFloatingButtonSizeSmall => 'Pequeno';

  @override
  String get settingsFloatingButtonSizeMedium => 'Médio';

  @override
  String get settingsFloatingButtonSizeLarge => 'Grande';

  @override
  String get settingsFloatingButtonShape => 'Forma';

  @override
  String get settingsFloatingButtonShapeSubtitle =>
      'Redondo ou quadrado arredondado';

  @override
  String get settingsFloatingButtonShapeRound => 'Redondo';

  @override
  String get settingsFloatingButtonShapeSquare => 'Quadrado';

  @override
  String get settingsFloatingButtonRing => 'Anel de gravação';

  @override
  String get settingsFloatingButtonRingSubtitle =>
      'Anel colorido em volta do botão durante a gravação';

  @override
  String get settingsFloatingButtonIdleOpacity => 'Opacidade em repouso';

  @override
  String get settingsFloatingButtonIdleOpacitySubtitle =>
      'Quão visível é o botão sem gravar';

  @override
  String get settingsFloatingButtonIdleOpacityReduced => '70 %';

  @override
  String get settingsFloatingButtonIdleOpacitySubtle => '40 %';

  @override
  String get settingsOverlayColorsGroup => 'Em comum (cores)';

  @override
  String get settingsAreaSmartMode => 'Modo inteligente';

  @override
  String get settingsAreaDictionary => 'Dicionário';

  @override
  String get settingsSearchEmptyHelp => 'Pesquisar na ajuda';

  @override
  String get dictionaryTabTerms => 'Termos';

  @override
  String get dictionaryTabReplacements => 'Substituições';

  @override
  String get dictionaryTabSuggestions => 'Sugestões';

  @override
  String get dictionaryTermsEffectPrompt =>
      'É passado ao reconhecimento de voz como dica. Ele pode preferir essas grafias, mas não altera o texto sozinho.';

  @override
  String get dictionaryTermsEffectReplacementOnly =>
      'O mecanismo de voz ativo não aceita dicas. Só as substituições alteram o texto. Seus termos continuam salvos.';

  @override
  String get dictionaryTermsHelp =>
      'Nomes, jargões e siglas que o reconhecimento costuma escrever errado. Separe-os com vírgulas ou quebras de linha.';

  @override
  String get dictionaryReplacementsHelp =>
      'Adicione apenas palavras que o reconhecimento realmente escreve errado. Palavras reconhecidas corretamente não mudam.';

  @override
  String get dictionaryTestTitle => 'Testar';

  @override
  String get dictionaryTestInputLabel => 'Frase de exemplo';

  @override
  String get dictionaryTestInputHint =>
      'Digite uma frase para ver quais substituições se aplicam.';

  @override
  String get dictionaryTestResultLabel => 'Resultado';

  @override
  String get dictionaryTestNoChange => 'Nenhuma substituição se aplica.';

  @override
  String get dictionaryCsvTitle => 'Importar e exportar (CSV)';

  @override
  String dictionaryCsvHint(String pipe) {
    return 'Uma linha por entrada: gatilhos separados por $pipe, texto de substituição, modo (exact ou fuzzy), limite.';
  }

  @override
  String get dictionaryCsvImport => 'Importar CSV';

  @override
  String get dictionaryCsvExport => 'Exportar CSV';

  @override
  String get dictionaryCsvExportEmpty =>
      'Ainda não há substituições para exportar.';

  @override
  String get dictionaryCsvImportTooLarge =>
      'O arquivo tem mais de 1 MB. Divida-o em arquivos menores.';

  @override
  String get dictionaryCsvImportReadError => 'Não foi possível ler o arquivo.';

  @override
  String get dictionaryCsvImportNothing => 'Nenhuma entrada válida encontrada.';

  @override
  String dictionaryCsvErrorSummary(int count) {
    return '$count linhas foram ignoradas por estarem incompletas ou inválidas.';
  }

  @override
  String dictionaryCsvTruncated(int count) {
    return 'Somente as primeiras $count entradas foram lidas.';
  }

  @override
  String dictionaryCsvImportDone(int added) {
    return '$added entradas adicionadas.';
  }

  @override
  String get dictionaryCsvExportFailed =>
      'Não foi possível salvar o arquivo CSV.';

  @override
  String dictionaryCsvExportDone(int count) {
    return '$count entradas exportadas.';
  }

  @override
  String dictionaryCsvLineError(int line, String reason) {
    return 'Linha $line: $reason';
  }

  @override
  String get dictionaryCsvReasonMissingFields => 'Colunas insuficientes.';

  @override
  String get dictionaryCsvReasonEmptyTrigger => 'Nenhum gatilho.';

  @override
  String get dictionaryCsvReasonTriggerTooLong => 'O gatilho é longo demais.';

  @override
  String get dictionaryCsvReasonEmptyReplacement =>
      'Nenhum texto de substituição.';

  @override
  String get dictionaryCsvReasonReplacementTooLong =>
      'O texto de substituição é longo demais.';

  @override
  String get dictionaryCsvReasonUnknownMatchMode =>
      'O modo deve ser exact ou fuzzy.';

  @override
  String get dictionaryCsvReasonInvalidThreshold =>
      'O limite deve ser strict, standard, tolerant ou um número de 0,5 a 1.';

  @override
  String get dictionaryCsvReasonControlCharacter =>
      'A linha contém um caractere de controle ou de formatação oculto, ou uma quebra de linha.';

  @override
  String dictionaryCsvReasonTooManyTriggers(int max) {
    return 'Gatilhos demais em uma linha (no máximo $max).';
  }

  @override
  String get dictionaryCsvPreviewTitle => 'Revisar entradas';

  @override
  String get dictionaryDuplicateBadge => 'Duplicado';

  @override
  String get dictionaryDuplicateHint =>
      'Outra entrada usa o mesmo gatilho. Vale a entrada que aparece primeiro na lista.';

  @override
  String dictionaryUsageCount(int count) {
    return 'Usado $count×';
  }

  @override
  String get dictionaryFavouriteLabel => 'Favorito';

  @override
  String dictionarySuggestionsHint(int count) {
    return 'Uma sugestão aparece quando a mesma correção se repete $count vezes. Nada é adicionado sem a sua confirmação.';
  }

  @override
  String get dictionarySuggestionsEmpty => 'Ainda não há sugestões';

  @override
  String get dictionarySuggestionsEmptyHint =>
      'Se você corrigir a mesma palavra duas vezes, o WhisPaste oferece aqui uma substituição.';

  @override
  String get dictionarySuggestionAccept => 'Aceitar';

  @override
  String get dictionarySuggestionReject => 'Dispensar';

  @override
  String get dictionarySuggestionAccepted => 'Substituição adicionada.';

  @override
  String get dictionarySuggestionRejected =>
      'Sugestão dispensada. Ela não aparecerá novamente.';

  @override
  String get dictionaryCsvPreviewIntro =>
      'As entradas marcadas como “será adicionado” vão para a sua lista. As existentes não mudam.';

  @override
  String dictionaryCsvPreviewAddCount(int count) {
    return 'Adicionar $count entradas';
  }

  @override
  String get dictionaryCsvImportEncodingError => 'O arquivo não é texto UTF-8.';

  @override
  String get dictionaryCsvRefusedFormat =>
      'Este arquivo usa um formato de pacote que este app não consegue ler.';

  @override
  String get dictionaryCsvRefusedType =>
      'Este arquivo não é um pacote de dicionário de substituições.';

  @override
  String dictionaryCsvPackageHeader(String name, String date) {
    return 'Pacote: $name (criado em $date)';
  }

  @override
  String get dictionaryCsvPackageNone =>
      'Sem informações do pacote (arquivo antigo ou de outra origem)';

  @override
  String dictionaryCsvSummaryLine(
    int added,
    int duplicates,
    int conflicts,
    int circular,
    int errors,
  ) {
    return 'Novas: $added · Duplicadas: $duplicates · Conflitos: $conflicts · Referências circulares: $circular · Com erro: $errors';
  }

  @override
  String get dictionaryCsvStrategyLabel => 'Se um gatilho já existir';

  @override
  String get dictionaryCsvStrategySkip => 'Ignorar';

  @override
  String get dictionaryCsvStrategyOverwrite => 'Substituir';

  @override
  String get dictionaryCsvStrategyKeepBoth => 'Manter ambos';

  @override
  String get dictionaryCsvStrategySkipHint =>
      'A linha não é importada. As entradas existentes não mudam.';

  @override
  String dictionaryCsvStrategyOverwriteHint(int changed) {
    return 'O gatilho em comum sai da entrada antiga e a linha é adicionada. $changed entradas existentes mudam ou são excluídas.';
  }

  @override
  String get dictionaryCsvStrategyKeepBothHint =>
      'A linha é adicionada também. Para o mesmo gatilho, continua valendo a entrada existente que vem primeiro na lista.';

  @override
  String get dictionaryCsvStatusAdded => 'será adicionada';

  @override
  String get dictionaryCsvStatusDuplicate => 'já existe';

  @override
  String get dictionaryCsvStatusConflictSkipped => 'conflito, será ignorado';

  @override
  String get dictionaryCsvStatusConflictReplaced =>
      'conflito, substitui o gatilho existente';

  @override
  String get dictionaryCsvStatusConflictKept =>
      'conflito, adicionada além disso';

  @override
  String get dictionaryCsvStatusSuperseded =>
      'substituída por uma linha posterior deste arquivo';

  @override
  String get dictionaryCsvStatusCircular =>
      'referência circular, não é importada';

  @override
  String get dictionaryCsvRowWillAdd => 'será adicionada';

  @override
  String get dictionaryCsvRowSkipped => 'Duplicado, será ignorado';

  @override
  String get dictionaryCsvExportSelectTitle =>
      'Escolha as entradas para exportar';

  @override
  String dictionaryCsvExportSelectSubtitle(int count) {
    return '$count entradas para escolher';
  }

  @override
  String get dictionaryCsvAllPresent =>
      'Todas as entradas já existem. Nada será gravado.';

  @override
  String dictionaryCsvNeverFiresCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count entradas têm um gatilho que nunca dispara: um único sinal de pontuação. Elas são importadas mesmo assim.',
      one:
          '1 entrada tem um gatilho que nunca dispara: um único sinal de pontuação. Ela é importada mesmo assim.',
    );
    return '$_temp0';
  }

  @override
  String dictionaryCsvExportConfirm(int count) {
    return 'Exportar ($count)';
  }

  @override
  String dictionaryCsvExportTooMany(int count) {
    return 'Entradas demais para um arquivo: $count. Escolha menos (no máximo 5000 entradas, 1 MiB).';
  }

  @override
  String get settingsBetaGroupHeading => 'Versões prévias';

  @override
  String get analyticsWordingTitle => 'Redação';

  @override
  String get analyticsWordingPanelTitle => 'Palavras: brutas vs. revisadas';

  @override
  String get analyticsRawWords => 'Palavras brutas';

  @override
  String get analyticsRevisedWords => 'Palavras revisadas';

  @override
  String get analyticsTransformActions => 'Gravações revisadas por ações';

  @override
  String get analyticsCorrectionsTitle => 'Correções frequentes';

  @override
  String get analyticsNoCorrections => 'Ainda não há correções registradas.';

  @override
  String get errorNoticeNoModelCause => 'Nenhum modelo de voz está instalado.';

  @override
  String get errorNoticeNoModelNext =>
      'Baixe um modelo em Configurações e tente novamente.';

  @override
  String get errorNoticeMicCause => 'O WhisPaste não tem acesso ao microfone.';

  @override
  String get errorNoticeMicNext =>
      'Permita o acesso nas configurações do sistema e tente novamente.';

  @override
  String get errorNoticeTranscribeCause => 'A transcrição falhou.';

  @override
  String get errorNoticeTranscribeNext =>
      'Tente novamente. Se continuar falhando, reinicie o WhisPaste ou escolha outro modelo nas configurações.';

  @override
  String get errorNoticeCpuCause =>
      'A GPU não pôde ser usada nesta transcrição.';

  @override
  String get errorNoticeCpuNext =>
      'Ela rodou na CPU, que é mais lenta. Verifique a aceleração por GPU nas configurações.';

  @override
  String get languageMismatchHint =>
      'O idioma detectado não corresponde à sua configuração.';

  @override
  String get languageMismatchSwitch => 'Trocar idioma';

  @override
  String parakeetLanguageUnsupported(String language) {
    return 'O Parakeet não consegue transcrever $language. Mudar para o Whisper?';
  }

  @override
  String get parakeetLanguageSwitchToWhisper => 'Mudar para o Whisper';

  @override
  String get titleBarMinimizeLabel => 'Minimizar janela';

  @override
  String get titleBarCloseLabel => 'Fechar janela';

  @override
  String get titleBarMaximizeLabel => 'Maximizar janela';

  @override
  String get titleBarRestoreLabel => 'Restaurar janela';

  @override
  String get notificationSmartModeSkippedTitle =>
      'WhisPaste: Smart Mode ignorado';

  @override
  String get notificationHotkeyFallbackTitle => 'WhisPaste: atalho ocupado';

  @override
  String get notificationSmartModeSkippedBody =>
      'Não foi possível aplicar o pós-processamento.';

  @override
  String get notificationSmartModeSkippedNoTextModel =>
      'Nenhum modelo de texto está carregado, por isso o pós-processamento foi ignorado.';

  @override
  String get notificationSmartModeSkippedTimedOut =>
      'O pós-processamento demorou demais.';

  @override
  String get notificationSmartModeOutcomePasted =>
      'O texto não editado foi colado.';

  @override
  String get notificationSmartModeOutcomeUnconfirmed =>
      'Não foi possível confirmar se o texto não editado foi colado.';

  @override
  String get notificationSmartModeOutcomeClipboard =>
      'O texto não editado está na área de transferência, mas não foi colado.';

  @override
  String get notificationSmartModeOutcomeNone =>
      'O texto não editado não foi colado.';

  @override
  String get smartModeNoTextModelHint =>
      'Nenhum modelo de texto configurado: até lá só é possível escolher “Desativado”.';

  @override
  String get smartModeLoadTextModelAction =>
      'Sem modelo de texto: carregar agora';

  @override
  String get smartModeAddOpenAiKeyAction => 'Adicionar chave da OpenAI';

  @override
  String get settingsPortabilityErrorInvalidFile =>
      'O arquivo não é uma exportação válida do WhisPaste.';

  @override
  String get settingsPortabilityErrorGeneric =>
      'Não foi possível processar o arquivo ou as configurações.';

  @override
  String get historyImportAudioLabel => 'Áudio';

  @override
  String get hotkeyConflictNoteSpotlight => 'Spotlight';

  @override
  String get hotkeyConflictNoteAppSwitcher => 'Alternador de apps';

  @override
  String get hotkeyConflictNoteQuitApp => 'Sair do app';

  @override
  String get hotkeyConflictNoteCloseWindow => 'Fechar janela';

  @override
  String get hotkeyConflictNoteHideApp => 'Ocultar app';

  @override
  String get hotkeyConflictNoteMinimizeWindow => 'Minimizar janela';

  @override
  String get hotkeyConflictNoteCycleWindows => 'Alternar janelas';

  @override
  String get hotkeyConflictNoteScreenshotFullScreen =>
      'Captura de tela (tela inteira)';

  @override
  String get hotkeyConflictNoteScreenshotSelection =>
      'Captura de tela (seleção)';

  @override
  String get hotkeyConflictNoteScreenshotRecording =>
      'Captura/gravação de tela';

  @override
  String get hotkeyConflictNoteEmojiPicker => 'Seletor de emoji e símbolos';

  @override
  String get hotkeyConflictNoteForceQuit => 'Forçar Encerrar';

  @override
  String get hotkeyConflictNoteLockWorkstation => 'Bloquear o computador';

  @override
  String get hotkeyConflictNoteShowDesktop =>
      'Mostrar/ocultar área de trabalho';

  @override
  String get hotkeyConflictNoteFileExplorer => 'Explorador de Arquivos';

  @override
  String get hotkeyConflictNoteRunDialog => 'Caixa de diálogo Executar';

  @override
  String get hotkeyConflictNoteSettings => 'Configurações';

  @override
  String get hotkeyConflictNoteSearch => 'Pesquisa';

  @override
  String get hotkeyConflictNoteTaskView => 'Visão de Tarefas';

  @override
  String get hotkeyConflictNoteInputLanguageSwitch =>
      'Alternar idioma de entrada';

  @override
  String get hotkeyConflictNoteMaximizeWindow => 'Maximizar janela';

  @override
  String get hotkeyConflictNoteSnapLeft => 'Encaixar janela à esquerda';

  @override
  String get hotkeyConflictNoteSnapRight => 'Encaixar janela à direita';

  @override
  String get hotkeyConflictNoteSecurityOptionsTaskManager =>
      'Opções de segurança / Gerenciador de Tarefas';

  @override
  String get hotkeyConflictNoteTaskManager => 'Gerenciador de Tarefas';

  @override
  String get hotkeyConflictNoteLockScreenGnomeKde =>
      'Bloquear tela (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteInputSourceGnome =>
      'Trocar fonte de entrada (GNOME)';

  @override
  String get hotkeyConflictNoteRunDialogKde => 'Caixa Executar (GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLogoutShutdownDialog =>
      'Diálogo de encerrar sessão/desligar';

  @override
  String get hotkeyConflictNoteOpenTerminal =>
      'Abrir terminal (padrão do GNOME/KDE)';

  @override
  String get hotkeyConflictNoteLockScreenGnome => 'Bloquear tela (GNOME)';

  @override
  String get hotkeyConflictNoteFnDoubleTap =>
      'macOS: Fn abre os emojis ou inicia o ditado do sistema';

  @override
  String get hotkeyConflictNoteWindowsDictation =>
      'Digitação por voz do Windows';

  @override
  String get hotkeyConflictNoteWindowsClipboardHistory =>
      'Histórico da área de transferência';

  @override
  String get hotkeyConflictActionChooseOther => 'Escolha outra combinação.';

  @override
  String get hotkeyConflictActionDisableMacDictation =>
      'Em Ajustes do Sistema → Teclado, defina \"Pressionar a tecla 🌐 para\" como \"Não Fazer Nada\" e desative o atalho do ditado.';

  @override
  String get settingsTextProcessingHeading => 'Processamento de texto';

  @override
  String get settingsShowNotificationsSubtitle =>
      'Avisa sobre problemas, por exemplo um Auto-Paste bloqueado ou um sinal de microfone ausente.';

  @override
  String get settingsGainSubtitle =>
      'Amplifica o sinal do microfone antes de ele ser gravado. Valores altos demais podem distorcer a gravação.';

  @override
  String get settingsAfterTranscriptionActionSubtitle =>
      'O que acontece com o texto reconhecido. O Auto-Paste o coloca direto no cursor.';

  @override
  String get settingsRecognitionLanguageSubtitle =>
      'O idioma que o reconhecimento espera. A detecção automática costuma funcionar bem. Um idioma fixo costuma ser mais preciso em gravações curtas.';

  @override
  String get settingsOpenAiApiKeySubtitle =>
      'Sua própria chave da OpenAI. Só é necessária se você usar a OpenAI para o reconhecimento ou o Smart Mode. Áudio e texto vão então diretamente para a OpenAI e são cobrados por ela.';

  @override
  String get settingsDeepgramApiKeySubtitle =>
      'Sua própria chave da Deepgram. Só é necessária se você usar a Deepgram para o reconhecimento. O áudio vai então diretamente para a Deepgram e é cobrado por ela.';

  @override
  String get settingsResetToDefaultsSubtitle =>
      'Redefine todas as configurações, chaves de API e estatísticas. Gravações, notas e modelos são mantidos.';

  @override
  String get settingsFactoryResetSubtitle =>
      'Apaga imediatamente todas as transcrições, notas, arquivos de áudio, Dicionário, Snippets, modelos, registros e configurações deste dispositivo. Não pode ser desfeito.';

  @override
  String get settingsHotkeyEnabledSubtitle =>
      'O atalho global inicia uma gravação em qualquer app. Desativado, o WhisPaste ignora o atalho.';

  @override
  String get settingsCheckForUpdatesNowSubtitle =>
      'Procura agora uma nova versão. Ela só é instalada depois da sua confirmação.';

  @override
  String get settingsHistoryRetentionSubtitle =>
      'Quantas transcrições são mantidas antes de as mais antigas irem para a lixeira. Na lixeira, as transcrições são apagadas definitivamente após o tempo escolhido. Os favoritos são sempre mantidos. Os arquivos de áudio salvos são removidos no máximo 30 dias após a gravação, independentemente desta configuração.';

  @override
  String get smartModeTargetLanguageSubtitle =>
      'Somente para a predefinição «Traduzir».';

  @override
  String get settingsPortabilityErrorTooLarge =>
      'O arquivo é grande demais para importar (limite: cerca de 5 MB). Escolha um arquivo de configurações exportado pelo WhisPaste.';

  @override
  String get settingsSearchKeywordsInterface =>
      'tema, modo escuro, modo claro, aparência, idioma, início automático, inicialização, minimizado, notificações, idioma do sistema, painel, painel lateral, colagem rápida, painel da área de transferência, posição do painel, borda da tela, borda, bandeja, CPU, indicador, barra de status, uso';

  @override
  String get settingsSearchKeywordsStt =>
      'modelo, Whisper, qualidade, transcrição, reconhecimento de voz, local, no dispositivo, nuvem, idioma, tempo limite, vocabulário, dicionário, palavras, STT, reconhecimento de voz, Deepgram, OpenAI, chave de API, somente números, pontuação, motor, silêncio, cortar, palavras de preenchimento, quebra de linha, parágrafo, linha, GPU, gráficos, aceleração, processador, hardware';

  @override
  String get settingsSearchKeywordsSmartMode =>
      'predefinição, limpeza, resumir, traduzir, Gemma, modelo, modelo de texto, baixar, pós-processamento, polir, editar seleção, seleção, texto selecionado, reescrever';

  @override
  String get settingsSearchKeywordsAudio =>
      'microfone, gravação, ganho, volume, pressionar para falar, manter para gravar, entrada';

  @override
  String get settingsSearchKeywordsAfterTranscription =>
      'área de transferência, colar, auto-paste, copiar, ação, saída, não fazer nada, lista de bloqueio, restaurar área de transferência, manter transcrição, conteúdo anterior';

  @override
  String get settingsSearchKeywordsOverlay =>
      'sobreposição, flutuante, exibição, status, posição, janela, centro superior, centro inferior, posição inicial, transcrição ao vivo';

  @override
  String get settingsSearchKeywordsOverlayBackground =>
      'fundo, cor, marinho, grafite, geleira, vidro, opaco, âmbar';

  @override
  String get settingsSearchKeywordsOverlayWave =>
      'onda, ondas, cor, ciano, violeta, animação, âmbar';

  @override
  String get settingsSearchKeywordsFloatingButton =>
      'botão, flutuante, sempre visível, botão de gravação, acesso rápido';

  @override
  String get settingsSearchKeywordsHotkey =>
      'atalho de teclado, combinação de teclas, atalho global, tecla global, atalho, teclado, teclas, vinculação de teclas';

  @override
  String get settingsSearchKeywordsSound =>
      'som, tom, áudio, sinal, bipe, volume, som de gravação, notificação, som de conclusão, aviso';

  @override
  String get settingsSearchKeywordsRecordingSafety =>
      'segurança, silêncio, parar automaticamente, tempo limite, tempo limite do microfone, detecção de silêncio, proteção, microfone sem sinal, duração máxima';

  @override
  String get settingsSearchKeywordsHistory =>
      'gravações, entradas, lixeira, limpeza, retenção, máximo, exclusão automática, exclusão, armazenamento, ocultar, privacidade, PIN, bloquear, bloqueio, proteger, histórico';

  @override
  String get settingsSearchKeywordsSettingsPortability =>
      'exportar, importar, migrar, transferir, mudança, backup, restaurar, troca de dispositivo, portabilidade, novo computador, backup automático, salvamento automático';

  @override
  String get settingsSearchKeywordsAdvanced =>
      'redefinir, padrões, redefinição de fábrica';

  @override
  String get settingsSearchKeywordsAutomationApi =>
      'automação, API, script, token, bearer, HTTP, localhost, porta';

  @override
  String get settingsSearchKeywordsUpdates =>
      'atualização, beta, canal, canal de lançamento, versão prévia, verificar, automático, nova versão, estável, versão';

  @override
  String get settingsSearchKeywordsOnboardingReview =>
      'introdução, onboarding, configuração inicial, configuração, passeio, tour, novamente, de novo, primeiros passos';

  @override
  String get settingsSearchKeywordsReviewSupport =>
      'avaliação, avaliar, estrelas, loja, apoiar, análise, classificar';

  @override
  String get settingsSearchKeywordsPrivacy =>
      'privacidade, análise, estatísticas, rastreamento, anônimo, relatórios de erros, relatórios de falhas, estatísticas de uso, dados, compartilhar, consentimento, manter gravações, gravações recentes';

  @override
  String get manualNoticeLabel => 'Mensagem exibida no app';

  @override
  String get manualC01Title => 'Primeiros passos';

  @override
  String get manualC01S1Heading => 'Configuração no primeiro início';

  @override
  String get manualC01S1B1 =>
      'No primeiro início, o WhisPaste guia você por seis etapas de configuração. Os pontos e a contagem de etapas no topo mostram onde você está. Cada etapa tem uma ação principal, e você pode voltar a qualquer momento. Tudo pode ser alterado depois nas configurações.';

  @override
  String get manualC01S1B2I1 =>
      'Início: visão geral e modelo de voz. Para escolher outro, use o link «Outro modelo de voz». O download só começa quando você confirma.';

  @override
  String get manualC01S1B2I2 =>
      'Acessos: a permissão que deixa o WhisPaste colar o texto automaticamente. As etapas dependem do sistema.';

  @override
  String get manualC01S1B2I3 =>
      'Microfone: escolha o dispositivo de entrada e confira se o WhisPaste ouve você.';

  @override
  String get manualC01S1B2I4 =>
      'Atalho: defina a combinação de teclas que inicia uma gravação. Se outro app já a usar, a configuração só pode ser concluída depois que você escolher outra.';

  @override
  String get manualC01S1B2I5 =>
      'Primeiro ditado: fale no chat de prática; o texto aparece ali, na janela. «Experimentar depois» pula o exercício.';

  @override
  String get manualC01S1B2I6 =>
      'Privacidade e início: os interruptores de privacidade e a ação principal «Iniciar o WhisPaste».';

  @override
  String get manualC01S1B3 =>
      'Pausar a configuração: se você fechar a janela durante a configuração, reabra-a pelo ícone da bandeja ou pela barra de menus com «Retomar configuração».';

  @override
  String get manualC01S1B4 =>
      'Usuários existentes: após uma atualização, o WhisPaste mostra uma dica que abre a página do microfone para conferência. Suas configurações permanecem iguais.';

  @override
  String get manualC01S1B5 =>
      'Primeiros passos: após a configuração, a página inicial mostra um cartão com três passos: um primeiro ditado colado em outro app, um ditado com mais de 30 segundos e os seus próprios termos no dicionário. Um passo só é marcado quando realmente aconteceu. Você pode fechar o cartão a qualquer momento; em Configurações, em Geral, “Mostrar novamente” o traz de volta.';

  @override
  String get manualC01S2Heading => 'Requisitos do sistema';

  @override
  String manualC01S2B1(String ram) {
    return 'O WhisPaste recomenda um dispositivo com pelo menos $ram de memória (RAM). Em dispositivos com menos, o WhisPaste inicia mesmo assim e recomenda um modelo de voz compacto. Se houver memória livre insuficiente para um modelo maior, o WhisPaste pergunta antes de carregá-lo.';
  }

  @override
  String get manualC01S2B2 =>
      'Você precisa de um microfone para gravar. Na configuração inicial, você pode continuar sem ele, mas só poderá gravar quando houver um conectado.';

  @override
  String get manualC01S3Heading => 'Baixar o modelo de voz';

  @override
  String get manualC01S3B1 =>
      'O WhisPaste converte sua fala em texto no seu dispositivo ou por um provedor na nuvem com a sua própria chave. No dispositivo, ele precisa de um modelo. Você inicia o download; ele não começa sozinho.';

  @override
  String manualC01S3B2I1(String k1) {
    return 'Parakeet: rápido, para idiomas europeus, cerca de $k1.';
  }

  @override
  String manualC01S3B2I2(String k1, String k2) {
    return 'Whisper: todos os 99 idiomas, modelos de cerca de $k1 a $k2.';
  }

  @override
  String manualC01S3B2I3(String k1) {
    return 'Os modelos ficam na pasta de dados do app, na subpasta $k1.';
  }

  @override
  String get manualC01S3B4 =>
      'Um modelo Whisper fica carregado depois de ditar, para que o próximo início seja mais rápido. Em “Manter o modelo carregado”, na seção de reconhecimento de voz, você escolhe: Sempre (padrão) economiza tempo de espera, mas precisa de memória o tempo todo. Automático mantém o modelo carregado se o computador tiver memória suficiente; caso contrário, ele é descarregado após 5 minutos. Após um período ocioso, ele é descarregado depois do tempo que você definir. Quando a memória fica escassa, o WhisPaste descarrega o modelo automaticamente e o carrega de novo quando houver espaço.';

  @override
  String get manualC01S3B3 =>
      'Na área Reconhecimento de fala, a opção “Executar benchmark novamente” mede a velocidade de cada nível instalado no seu computador. Os resultados mostram nos cartões de modelo quanto mais tempo cada nível leva e definem o nível recomendado do Whisper. É recomendado o modelo mais preciso que corre com fluidez: o maior nível do Whisper se o seu computador o suportar; caso contrário, o Parakeet, se suportar o seu idioma. Para inglês é o Parakeet. O teste não começa durante uma gravação.';

  @override
  String get manualC02Title => 'Gravar e colar';

  @override
  String get manualC02S1Heading => 'O atalho';

  @override
  String manualC02S1B1(String k2, String k3) {
    return 'O atalho é uma combinação de teclas que funciona em todos os programas. Padrão: $k2 no Windows e no Linux, $k3 no Mac. Você pode alterá-lo em Configurações → Atalhos de teclado.';
  }

  @override
  String manualC02S1B2(String k2, String k3) {
    return 'Se outro programa já usar a combinação, o WhisPaste usa $k2 para o atalho (no Mac, $k3). Os outros atalhos ficam desativados até você definir uma combinação livre.';
  }

  @override
  String get manualC02S2Heading => 'Manter ou alternar';

  @override
  String get manualC02S2B1 =>
      'Em Configurações → Atalhos de teclado, escolha como o atalho funciona:';

  @override
  String get manualC02S2B2I1 =>
      '«Manter pressionado para gravar» ativado (padrão em instalações novas): segure o atalho, fale e solte. Ao soltar, a gravação termina.';

  @override
  String get manualC02S2B2I2 =>
      'Desativado: um toque inicia a gravação e um segundo toque a encerra.';

  @override
  String get manualC02S3Heading => 'Ver a gravação';

  @override
  String get manualC02S3B1 =>
      'O dock na parte inferior da janela principal mostra o estado atual. Durante a gravação, o botão passa a “Parar gravação”, e a área de status mostra a etapa atual. O dock está sempre visível e não pode ser desligado.';

  @override
  String get manualC02S3B3 =>
      'Em uma janela estreita, o dock move os controles menos importantes para o menu “Mais”, incluindo o atalho, a dica do Auto-Paste e o aviso de atualização. Tudo continua disponível ali.';

  @override
  String get manualC02S3B2I1 =>
      '«Overlay de gravação» em «Flutuante (sempre visível)»: uma pequena janela de forma de onda sobre todos os programas. Padrão: desativado.';

  @override
  String get manualC02S3B2I2 =>
      '«Botão flutuante»: um botão para gravar com um clique. Padrão: desativado. No Linux com Wayland, o ambiente pode limitar a posição e se ele fica sempre no topo.';

  @override
  String get manualC02S4Heading => 'Colar após gravar';

  @override
  String get manualC02S4B1 =>
      'Em «Após a transcrição», escolha o que acontece após cada gravação:';

  @override
  String get manualC02S4B2I1 =>
      '«Copiar para a área de transferência» (padrão): o texto vai para a área de transferência e você o cola.';

  @override
  String get manualC02S4B2I2 =>
      '«Colar automaticamente no cursor»: o WhisPaste cola o texto na posição do cursor.';

  @override
  String get manualC02S4B2I3 =>
      '«Copiar e colar automaticamente»: as duas coisas.';

  @override
  String get manualC02S4B2I4 =>
      '«Não fazer nada»: o WhisPaste não copia nem cola o texto.';

  @override
  String get manualC02S4B3 =>
      'Os apps na «Lista de bloqueio do Auto-Paste» não recebem colagem automática. O texto vai então para a área de transferência, ou só para as Gravações se «Copiar para a área de transferência em apps bloqueados» estiver desligado. Escreva um app por linha no campo. Se uma colagem falhar, o WhisPaste mostra um aviso e o texto fica na área de transferência.';

  @override
  String get manualC02S4B4 =>
      'No Windows, o Auto-Paste não funciona em programas executados com privilégios de administrador.';

  @override
  String get manualC02S4B5 =>
      'No Linux, o WhisPaste marca o texto com uma dica que só o Klipper do KDE respeita. Outros gerenciadores da área de transferência, como GPaste ou CopyQ, também registram suas transcrições: desative lá o registro da área de transferência ou apague a entrada. No Linux com Wayland, o WhisPaste informa erros somente por notificação e pela bandeja.';

  @override
  String get manualC02S4B6 =>
      'Depois de colar, o WhisPaste normalmente devolve o que estava antes na área de transferência. Em «Área de transferência após colar» você pode escolher «Manter a transcrição»: então o texto transcrito fica na área de transferência. Se a colagem não puder ser confirmada a tempo, a transcrição fica lá, a menos que você ative «Restaurar mesmo sem confirmação». Se o WhisPaste não conseguir gravar o recibo de leitura na área de transferência, aparece um aviso discreto: Colagem não confirmada – o texto está na área de transferência. Se o macOS negar o acesso à área de transferência, o WhisPaste não consegue guardar o conteúdo anterior e não o restaura; a transcrição fica então na área de transferência. Uma vez aparece um aviso com o caminho para os Ajustes do Sistema.';

  @override
  String get manualC02S4B7 =>
      'Se um texto for parar no campo errado, ative o atalho “Colar o último ditado novamente” em “Atalhos de teclado”. Ele cola novamente o texto da sua última gravação no app em primeiro plano. O padrão é Ctrl+Cmd+V no Mac e Alt+Shift+V no Windows e no Linux. Com o salvamento das gravações desligado, o WhisPaste só conhece a última gravação desde que foi iniciado. Durante uma gravação o atalho não faz nada. Se ainda não houver nada para colar, o overlay avisa rapidamente.';

  @override
  String get manualC02S4B8 =>
      'O “Painel de colagem rápida” abre na borda da tela com suas transcrições, snippets e o histórico da área de transferência. Um clique cola um item. Você também pode arrastar um item direto para outro aplicativo.';

  @override
  String get manualC03Title => 'Nota rápida';

  @override
  String get manualC03S1Heading => 'O que a nota rápida faz';

  @override
  String get manualC03S1B1 =>
      'A nota rápida é uma nota à qual o WhisPaste acrescenta novas gravações. Assim você reúne ideias ou uma lista sem criar uma nota nova a cada vez.';

  @override
  String get manualC03S1B2 =>
      'Se ainda não houver nenhuma nota marcada, o WhisPaste cria uma na primeira vez e a marca.';

  @override
  String get manualC03S2Heading => 'Configurar';

  @override
  String get manualC03S2B1I1 =>
      'Abra a nota na área de notas e ative «Definir como nota rápida: o atalho acrescenta texto a ela». «Nota rápida — remover a marcação» remove a marcação.';

  @override
  String manualC03S2B1I2(String k1, String k2, String k3) {
    return 'Ative o atalho de nota rápida em Configurações → Atalhos de teclado. Ele vem desativado por padrão. A tecla é $k1 ($k2, ou $k3 no Mac).';
  }

  @override
  String get manualC04Title => 'Smart Mode';

  @override
  String get manualC04S1Heading => 'O que o Smart Mode faz';

  @override
  String manualC04S1B1(String k1) {
    return 'O $k1 edita o texto reconhecido antes de colá-lo. Ele vem desativado por padrão; você o ativa.';
  }

  @override
  String get manualC04S1B2 =>
      'Por padrão, o processamento roda no seu dispositivo («Localmente no dispositivo»). Com «OpenAI», o texto é enviado à OpenAI. Os detalhes estão no capítulo de privacidade.';

  @override
  String get manualC04S2Heading => 'Predefinições';

  @override
  String get manualC04S2B1 =>
      'Uma predefinição define o que acontece com o texto:';

  @override
  String get manualC04S2B2I1 =>
      '«Desativado»: sem pós-processamento; o texto fica como foi reconhecido.';

  @override
  String get manualC04S2B2I2 =>
      '«Limpeza»: remove palavras de preenchimento (por exemplo, hum) e corrige pontuação e maiúsculas, sem mudar as palavras, o sentido ou o idioma.';

  @override
  String get manualC04S2B2I3 =>
      '«Conciso»: remove repetições e palavras de preenchimento, e mantém todos os fatos importantes e o idioma.';

  @override
  String get manualC04S2B2I4 =>
      '«Traduzir»: traduz o texto para o idioma de destino escolhido.';

  @override
  String get manualC04S3Heading => 'Idioma de destino e atalho';

  @override
  String get manualC04S3B1 =>
      'Para «Traduzir», escolha um idioma de destino: alemão, inglês, espanhol, francês, português, mandarim ou russo. O padrão é inglês.';

  @override
  String manualC04S3B2(String k1) {
    return 'Um atalho próprio para o $k1 vem desativado por padrão. Ele usa a predefinição e o idioma de destino das configurações.';
  }

  @override
  String get manualC04S4Heading => 'Recursos';

  @override
  String manualC04S4B1(String size, String ram) {
    return 'A variante local baixa um modelo de texto de cerca de $size. Se o seu dispositivo tiver menos de $ram de RAM, o WhisPaste avisa antes do download, mas você pode baixar mesmo assim. Durante o uso, o modelo de texto precisa de 4 a 5 GB extras de RAM.';
  }

  @override
  String get manualC04S4B2 =>
      'Enquanto nenhum modelo de texto estiver configurado (local sem download, ou OpenAI sem chave), todas as predefinições exceto “Desativado” ficam bloqueadas. O dock e as configurações mostram o motivo e levam ao download ou à chave. Se o pós-processamento falhar mesmo assim, o WhisPaste avisa e diz se o texto não editado foi colado ou está só na área de transferência.';

  @override
  String get manualC05Title => 'Dicionário';

  @override
  String get manualC05S1Heading => 'Como as substituições funcionam';

  @override
  String get manualC05S1B1 =>
      'Uma substituição troca automaticamente certas palavras ou expressões por outro texto em cada gravação.';

  @override
  String get manualC05S1B2 =>
      'Cada substituição tem uma ou mais frases-gatilho, ou seja, as expressões a procurar, e o texto novo. Digite várias frases-gatilho para o mesmo texto em «Frases-gatilho».';

  @override
  String get manualC05S1B3 =>
      'Para símbolos como parênteses, @ ou %: os modelos em «Adicionar modelos de símbolos» no menu os adicionam. Os gatilhos existentes permanecem.';

  @override
  String get manualC05S1B4 =>
      'A ordem importa: as substituições são aplicadas na ordem em que você as criou. Se uma substituição produz um texto que é o gatilho de uma criada depois, essa também é aplicada. Crie na ordem desejada as substituições que se baseiam umas nas outras.';

  @override
  String get manualC05S2Heading => 'Correspondência';

  @override
  String get manualC05S2B1I1 => 'Exata: só a grafia idêntica é substituída.';

  @override
  String get manualC05S2B1I2 =>
      'Similar: grafias levemente diferentes também são substituídas. Vale só para frases-gatilho com pelo menos 4 caracteres.';

  @override
  String get manualC05S2B1I3 =>
      'Tolerância («Rigorosa», «Padrão» ou «Tolerante»): definida por entrada, não para todas de uma vez.';

  @override
  String get manualC05S2B2 =>
      'Frases-gatilho sem letras nem números, como ... ou :), precisam de pelo menos 2 caracteres. São substituídas exatamente como escritas, mesmo no meio de uma palavra. Um único caractere, como ?, nunca é substituído.';

  @override
  String get manualC05S3Heading => 'Importar e exportar (CSV)';

  @override
  String manualC05S3B1(String k1, String k2, String k3, String k4) {
    return 'Você pode salvar ou transferir suas substituições como arquivo CSV. O arquivo tem as colunas $k1. Separe várias frases-gatilho com $k2. O arquivo pode ter no máximo $k3 e $k4 linhas.';
  }

  @override
  String get manualC05S3B2 =>
      'A importação e a exportação estão no menu Mais (⋯) acima da lista. O campo de teste também abre por esse menu.';

  @override
  String get manualC06Title => 'Snippets';

  @override
  String get manualC06S1Heading => 'O que são snippets';

  @override
  String get manualC06S1B1 =>
      'Um snippet é um bloco de texto que você insere com uma palavra-gatilho ou um atalho, como uma assinatura ou uma resposta padrão.';

  @override
  String get manualC06S1B2I1 =>
      '«Estático»: o texto é inserido exatamente como você o salvou.';

  @override
  String get manualC06S1B2I2 =>
      '«Interativo»: o WhisPaste pede cada campo por gravação, um após o outro, e os coloca no seu modelo.';

  @override
  String get manualC06S2Heading => 'Abrir o seletor de snippets';

  @override
  String get manualC06S2B1 => 'Há duas formas de abrir o seletor:';

  @override
  String get manualC06S2B2I1 =>
      'Com a palavra-gatilho do seletor: diga só essa palavra para abrir o seletor. Se você a disser seguida do nome de um snippet (por exemplo «assinatura»), o WhisPaste insere diretamente o snippet correspondente. Se o nome não for único, o seletor abre com esse nome como termo de busca. Só vale se a gravação inteira tiver essa forma; no meio de uma frase, a palavra não tem efeito. Você a define em Configurações, em Atalhos de teclado, grupo Notas e snippets, logo abaixo do atalho do seletor; deixe vazia para desligar o seletor.';

  @override
  String get manualC06S2B2I2 =>
      'Com o atalho do seletor: desativado por padrão; ative em «Atalho do seletor».';

  @override
  String manualC06S2B3(String shortcut) {
    return 'Também pode ditar um fragmento interativo numa só frase: no seletor, prima $shortcut ou clique no ícone de balão da linha. Depois, uma pré-visualização mostra que valor ficou em cada campo. Pode alterar qualquer valor; Enter insere, Esc cancela. Com um modelo de texto configurado basta uma frase natural; sem ele, diga também os nomes dos campos.';
  }

  @override
  String get manualC06S3Heading => 'Criar um snippet';

  @override
  String get manualC06S3B1I1 =>
      'Crie um snippet com «Adicionar» e escolha «Estático» ou «Interativo».';

  @override
  String manualC06S3B1I2(String k1) {
    return 'Em «Interativo», defina os campos e escreva o modelo. Coloque os marcadores entre chaves duplas, como $k1.';
  }

  @override
  String get manualC07Title => 'Notas';

  @override
  String get manualC07S1Heading => 'Trabalhar com notas';

  @override
  String get manualC07S1B1 =>
      'A área de notas reúne texto, como ideias ou pesquisas. As gravações vão direto para uma nota quando você usa a nota rápida.';

  @override
  String get manualC07S1B2I1 => '«Marcar como favorita» destaca uma nota.';

  @override
  String get manualC07S1B2I2 =>
      '«Adicionar tag» atribui uma nota a uma categoria.';

  @override
  String get manualC07S2Heading => 'Lixeira';

  @override
  String get manualC07S2B1 =>
      '«Mover para a lixeira» coloca uma nota na lixeira. Ela fica lá até você excluí-la definitivamente. A lixeira nunca é esvaziada automaticamente.';

  @override
  String get manualC07S2B2I1 =>
      '«Excluir definitivamente» remove a nota da lixeira.';

  @override
  String get manualC07S3Heading => 'Nota rápida';

  @override
  String get manualC07S3B1 =>
      'A área de notas mostra qual nota é a nota rápida. Os detalhes estão no capítulo da nota rápida.';

  @override
  String get manualC07S4Heading => 'Imagens e privacidade';

  @override
  String get manualC07S4B1 =>
      'Ao adicionar uma imagem, o WhisPaste remove metadados como a localização (GPS), os dados da câmera e as informações EXIF, XMP e IPTC. Só a cópia limpa é guardada.';

  @override
  String get notesPinGateTitle => 'As notas estão bloqueadas';

  @override
  String get notesPinGateHint =>
      'Introduza o seu PIN para mostrar as suas notas.';

  @override
  String get manualC08Title => 'Gravações';

  @override
  String get manualC08S1Heading => 'O que as gravações contêm';

  @override
  String get manualC08S1B1 =>
      'As gravações mostram cada entrada: o texto reconhecido, com a data. Se houver áudio salvo, o arquivo de áudio pertence a essa entrada.';

  @override
  String get manualC08S2Heading => 'Pesquisar e filtrar';

  @override
  String manualC08S2B1I1(String k1) {
    return 'Digite $k1 para filtrar por tags.';
  }

  @override
  String manualC08S2B1I2(String k1) {
    return 'Digite $k1 e um idioma para filtrar por idioma.';
  }

  @override
  String get manualC08S2B1I3 => 'Ou simplesmente digite uma palavra-chave.';

  @override
  String get manualC08S2B1I4 =>
      'Acima da lista estão os filtros «Favoritos», «Arquivados», «Lixeira» e «Todos».';

  @override
  String get manualC08S3Heading => 'Gerenciar entradas';

  @override
  String get manualC08S3B1I1 =>
      '«Copiar texto» copia o texto para a área de transferência novamente.';

  @override
  String get manualC08S3B1I2 =>
      '«Adicionar aos favoritos» mantém uma entrada no topo. «Remover dos favoritos» desfaz isso.';

  @override
  String get manualC08S3B1I3 =>
      '«Arquivo» tira uma entrada da lista principal sem excluí-la.';

  @override
  String get manualC08S3B1I4 =>
      '«Duplicar», «Mesclar» (várias entradas em uma) e «Selecionar vários» ajudam a organizar.';

  @override
  String get manualC08S3B1I5 =>
      '«Adicionar anotação» e «Adicionar tag…» acrescentam detalhes a uma entrada.';

  @override
  String get manualC08S4Heading => 'Nota de voz';

  @override
  String get manualC08S4B1 =>
      'Inicie uma nota de voz na entrada. Diga «tag: nome» para definir uma tag, ou «correct: texto» para substituir o texto da entrada.';

  @override
  String get manualC08S4B2 =>
      'Uma correção substitui todo o texto da entrada, não só uma palavra. «korrektur: texto» funciona da mesma forma. Logo depois você pode desfazer a alteração pelo aviso.';

  @override
  String get manualC08S5Heading => 'Proteção por PIN';

  @override
  String get manualC08S5B1 =>
      'Com «Proteção por PIN», um PIN é exigido antes de mostrar as gravações. Isso vale também para o painel lateral, o menu do botão flutuante e a API de automação. O PIN impede que outros vejam suas transcrições, mas não as criptografa. As notas ficam bloqueadas da mesma forma. Com um PIN definido, o menu da bandeja mostra as gravações recentes apenas com a hora e o número de palavras, sem o início do texto.';

  @override
  String get manualC08S5B2 =>
      'Um PIN esquecido não pode ser recuperado. Para o repor, são apagados de imediato todas as transcrições e ficheiros de áudio guardados (incluindo arquivo e lixo), todas as notas com as suas versões e todas as imagens das notas. As definições, os blocos de texto e as substituições são mantidos.';

  @override
  String get manualC08S5B3 =>
      'Enquanto as gravações estiverem bloqueadas por PIN, a aba da área de transferência no painel lateral não mostra texto copiado nem o cola. O texto volta a aparecer ao desbloqueá-las.';

  @override
  String get manualC08S6Heading => 'Esvaziamento automático';

  @override
  String get manualC08S6B1 =>
      'Em «Excluir lixeira automaticamente após», defina por quanto tempo as entradas excluídas ficam na lixeira antes de serem removidas automaticamente.';

  @override
  String get manualC08S7Heading => 'Desligar o guardar';

  @override
  String manualC08S7B1(Object k1) {
    return 'Pode desligar o guardar em $k1. Um ditado é então apenas colado ou copiado para a área de transferência: não aparece em Gravações e nenhum áudio é guardado. As gravações existentes ficam até as apagar. As estatísticas e o lembrete de avaliação continuam a funcionar. Os ficheiros importados continuam a ir para Gravações, porque os escolhes precisamente para isso.';
  }

  @override
  String get manualC09Title => 'Importar arquivos de áudio';

  @override
  String get manualC09S1Heading => 'Transcrever arquivos de áudio';

  @override
  String manualC09S1B1(String k1) {
    return 'Você pode transcrever arquivos de áudio que já tem. Escolha «$k1» e selecione o arquivo.';
  }

  @override
  String manualC09S1B2(String k1, String k2, String k3, String k4) {
    return 'Além de $k1, dependendo do sistema, você pode importar mais formatos: no Mac $k2, no Linux $k3, no Windows $k4.';
  }

  @override
  String get manualC09S1B3 =>
      'No Linux, M4A/AAC precisa do decodificador AAC do GStreamer. O pacote .deb o instala como pacote recomendado. Se ele faltar em uma instalação .deb ou tarball, instale-o no Debian ou Ubuntu com este comando e reinicie o WhisPaste. A versão Flatpak ainda não foi verificada quanto a esse decodificador, então M4A/AAC pode faltar lá, e este comando não se aplica. A versão Snap deveria incluí-lo, mas isso ainda não foi verificado. Se faltar lá, converta o arquivo para WAV.';

  @override
  String get manualC09S1Cmd => 'sudo apt install gstreamer1.0-libav';

  @override
  String get manualC09S2Heading => 'Limites';

  @override
  String get manualC09S2B2 =>
      'O que fazer: divida a gravação em partes menores e importe uma a uma.';

  @override
  String get manualC09S3Heading => 'Erros de importação';

  @override
  String manualC09S3B2(String k1) {
    return 'O que fazer: tente novamente. Se não resolver, reinicie o WhisPaste ou escolha outro modelo em $k1.';
  }

  @override
  String get manualC10Title => 'Estatísticas';

  @override
  String get manualC10S1Heading => 'As áreas';

  @override
  String manualC10S1B1(String k1, String k2, String k3) {
    return 'As estatísticas têm três áreas: $k1, $k2 e $k3.';
  }

  @override
  String manualC10S1B2(String k1, String k2) {
    return 'Com $k1 e $k2 você escolhe o período.';
  }

  @override
  String get manualC10S2Heading => 'O que os números significam';

  @override
  String manualC10S2B1I1(String k1, String k2) {
    return '$k1 e $k2 contam suas gravações e o tempo gravado.';
  }

  @override
  String manualC10S2B1I2(String k1) {
    return '$k1 é uma estimativa aproximada: o WhisPaste considera dois terços do tempo de gravação como economizados, porque falar costuma ser mais rápido que digitar. Não é uma medição.';
  }

  @override
  String manualC10S2B1I3(String k1, String k2) {
    return '$k1: gravações locais economizam custos de nuvem. O WhisPaste estima isso em $k2 por minuto, uma taxa de referência fixa.';
  }

  @override
  String get manualC10S3Heading => 'Redefinir';

  @override
  String manualC10S3B1(String k1) {
    return '«$k1» apaga todos os dados das estatísticas. O WhisPaste pede confirmação antes, e isso não pode ser desfeito.';
  }

  @override
  String get manualC11Title => 'Configurações';

  @override
  String get manualC11S1Heading => 'As seções';

  @override
  String get manualC11S1B1 =>
      'As configurações são organizadas em seções. As mais importantes:';

  @override
  String manualC11S1B2I1(String k1) {
    return '$k1: a aparência do app.';
  }

  @override
  String manualC11S1B2I2(String k1) {
    return '$k1: modelo e idioma de reconhecimento.';
  }

  @override
  String manualC11S1B2I3(String k1) {
    return '$k1: microfone e volume.';
  }

  @override
  String manualC11S1B2I4(String k1) {
    return '$k1: predefinição, idioma de destino e provedor.';
  }

  @override
  String manualC11S1B2I5(String k1) {
    return '$k1: o que acontece após uma gravação.';
  }

  @override
  String manualC11S1B2I6(String k1) {
    return '$k1: atalhos.';
  }

  @override
  String manualC11S1B2I7(String k1) {
    return '$k1: prazo da lixeira.';
  }

  @override
  String manualC11S1B2I8(String k1) {
    return '$k1: exportação, importação e backup automático.';
  }

  @override
  String manualC11S1B2I9(String k1) {
    return '$k1: API local e hooks de eventos para programas deste computador.';
  }

  @override
  String manualC11S1B2I10(String k1) {
    return '$k1: mais opções, como redefinir.';
  }

  @override
  String manualC11S1B2I11(String k1) {
    return '$k1: versão, verificação de atualizações, links e licenças.';
  }

  @override
  String get manualC11S2Heading => 'Backup e redefinição';

  @override
  String manualC11S2B1I1(String k1) {
    return '$k1 salva suas configurações automaticamente após as alterações. Os últimos cinco arquivos são mantidos. Vem desativado por padrão.';
  }

  @override
  String manualC11S2B1I2(String k1) {
    return '$k1 apaga imediatamente todas as transcrições, os arquivos de áudio e as configurações e redefine o WhisPaste. Leia a confirmação com atenção antes de confirmar.';
  }

  @override
  String get manualC12Title => 'Privacidade e uso offline';

  @override
  String get manualC12S1Heading => 'O que fica no seu dispositivo';

  @override
  String manualC12S1B1(String k1, int count, int days) {
    return 'Por padrão, o reconhecimento de fala roda no seu dispositivo. O áudio só vai a um serviço na nuvem se você escolher ativamente um provedor de nuvem. As transcrições ficam em um banco de dados local no seu dispositivo; os áudios salvos, como arquivos ao lado dele. O áudio das suas últimas $count gravações só é mantido se “$k1” estiver ativado, por no máximo $days dias.';
  }

  @override
  String get manualC12S1B2 =>
      'A verificação de atualizações consulta o GitHub por novas versões. O feedback só é enviado quando você o envia.';

  @override
  String manualC12S1B3(int days) {
    return 'Se uma transcrição falhar porque o servidor ou a conexão não estão disponíveis, o áudio dessa gravação fica guardado por até $days dias, para você tentar de novo pela mensagem de erro ou em «Privacidade e dados». Isso também vale com a retenção desligada. Se estiver ligada, vale a retenção normal.';
  }

  @override
  String get manualC12S1B3Ref =>
      'Se uma transcrição falhar porque o servidor ou a conexão não estão disponíveis, o áudio dessa gravação fica salvo pelo prazo que você define em «Privacidade e dados», para você tentar de novo pela mensagem de erro ou ali. Isso também vale com a retenção desligada. Se estiver ligada, vale a retenção normal.';

  @override
  String get manualC12S1B5Ref =>
      'Quantas gravações ficam guardadas e quando as mais antigas vão para a lixeira você define em «Privacidade e dados».';

  @override
  String get manualC12S1B4 =>
      'Gravações interrompidas, por exemplo por uma falha ou ao fechar o app, são processadas uma vez na próxima inicialização e depois o áudio é apagado. Isso também vale com a retenção desligada.';

  @override
  String get manualC12S2Heading => 'Provedores de nuvem';

  @override
  String manualC12S2B1(String k1) {
    return 'Os provedores OpenAI e Deepgram precisam da sua própria chave de API. Insira-a em $k1.';
  }

  @override
  String get manualC12S3Heading => 'Estatísticas de uso e relatórios de erro';

  @override
  String manualC12S3B1(String k1, String k2, String k3) {
    return 'Duas opções vêm ativadas por padrão: $k1 e $k2. Você pode desativar as duas em $k3.';
  }

  @override
  String get manualC13Title => 'Hardware e desempenho';

  @override
  String get manualC13S1Heading => 'Memória';

  @override
  String manualC13S1B1(String k1) {
    return 'O WhisPaste recomenda pelo menos $k1 de memória. Com menos, o app inicia mesmo assim e sugere o modelo de voz “Rápido”.';
  }

  @override
  String get manualC13S2Heading => 'Placa de vídeo';

  @override
  String get manualC13S2B1 =>
      'O WhisPaste usa a placa de vídeo quando ela pode acelerar o reconhecimento de fala:';

  @override
  String manualC13S2B2I1(String k1, String k2) {
    return '$k1: $k2, a interface gráfica da Apple.';
  }

  @override
  String manualC13S2B2I2(String k1, String k2, String k3) {
    return '$k1 e $k2 com gráficos AMD ou Intel: $k3, uma interface gráfica muito usada.';
  }

  @override
  String manualC13S2B2I3(String k1, String k2) {
    return 'As placas NVIDIA também usam $k1. Com o pacote CUDA opcional, o reconhecimento também usa $k2.';
  }

  @override
  String manualC13S2B2I4(String k1) {
    return 'Sem uma placa de vídeo adequada, o WhisPaste calcula no processador ($k1). Isso é mais lento.';
  }

  @override
  String get manualC13S3Heading => 'O pacote CUDA';

  @override
  String manualC13S3B1(String k1, String k2, String k3, String k4, String k5) {
    return 'O pacote CUDA é um complemento opcional para placas NVIDIA, segundo o app, para $k1 e $k2. Ele está disponível para $k3 e $k4 (x64). Ative-o em $k5.';
  }

  @override
  String get manualC13S3B2 => 'O download é único. O app mostra o tamanho.';

  @override
  String get manualC13S3B3 =>
      'O pacote contém componentes da NVIDIA. Antes do primeiro download você aceita a licença CUDA da NVIDIA (versão 2026-01-26); o consentimento vale para esta instalação. Sem um consentimento válido, a linha mostra «Consentimento necessário» e o WhisPaste usa Vulkan ou a CPU até você aceitar. Se o texto da licença ou o pacote mudar, a pergunta é feita de novo.';

  @override
  String get manualC13S4Heading => 'Aceleração gráfica';

  @override
  String manualC13S4B1(String k1) {
    return 'Em $k1, escolha se o WhisPaste usa a placa de vídeo. Só o processador costuma ser mais lento.';
  }

  @override
  String get manualC13S5Heading => 'Modelos e tamanho';

  @override
  String get manualC13S5B1 =>
      'Os modelos Whisper vêm em três níveis: Rápido, Equilibrado e Preciso. Níveis mais precisos costumam reconhecer melhor, mas precisam de mais tempo de processamento.';

  @override
  String get manualC13S6Heading => 'Visão geral: último ditado e armazenamento';

  @override
  String get manualC13S6B1 =>
      'Na visão geral, “Último ditado” mostra se o último ditado foi processado no processador ou na placa gráfica e quanto tempo levou o reconhecimento. Se a placa gráfica estava prevista, mas não assumiu o trabalho, aparece “Recuo: a placa gráfica estava prevista, mas o processador tratou do ditado.”';

  @override
  String get manualC13S6B2 =>
      '“Armazenamento do WhisPaste” mostra o espaço usado por modelos de voz, gravações e cache. “Limpar…” esvazia apenas o cache, e só depois de perguntar. Os modelos de voz e as gravações não são alterados.';

  @override
  String get manualC14Title => 'Solução de problemas';

  @override
  String get manualC14S1Heading => 'Como ler esta página';

  @override
  String get manualC14S1B1 =>
      'Cada seção começa com um aviso que o WhisPaste mostra. O texto é o próprio do app. Abaixo estão a causa e o próximo passo.';

  @override
  String get manualC14S2Heading => 'Sem acesso ao microfone';

  @override
  String get manualC14S2B2 =>
      'O que fazer: permita o acesso ao microfone para o WhisPaste nas configurações do sistema. Depois, inicie a gravação de novo.';

  @override
  String get manualC14S3Heading => 'Nenhum microfone encontrado';

  @override
  String manualC14S3B2(String k1) {
    return 'O que fazer: conecte um microfone e escolha-o em $k1.';
  }

  @override
  String get manualC14S4Heading => 'Nenhum áudio captado';

  @override
  String manualC14S4B2(String k1) {
    return 'O que fazer: confira se o microfone certo está selecionado e se o $k1 não está em zero. Depois, grave de novo.';
  }

  @override
  String get manualC14S5Heading => 'Sem modelo de voz';

  @override
  String manualC14S5B2(String k1) {
    return 'O que fazer: baixe um modelo em $k1 e tente de novo.';
  }

  @override
  String get manualC14S6Heading => 'Modelo desconhecido';

  @override
  String manualC14S6B2(String k1) {
    return 'O que fazer: escolha um modelo instalado em $k1.';
  }

  @override
  String get manualC14S7Heading => 'Transcrição falhou';

  @override
  String manualC14S7B2(String k1) {
    return 'O que fazer: tente novamente. Se não resolver, reinicie o WhisPaste ou escolha outro modelo em $k1.';
  }

  @override
  String get manualC14S8Heading => 'Nenhum texto reconhecido';

  @override
  String get manualC14S8B2 =>
      'O que fazer: fale mais claramente ou um pouco mais e tente de novo. Verifique também o microfone.';

  @override
  String get manualC14S9Heading => 'Gravação ou transcrição longa demais';

  @override
  String get manualC14S9B2 => 'O que fazer: grave trechos mais curtos.';

  @override
  String get manualC14S10Heading => 'Chave da nuvem ausente ou inválida';

  @override
  String manualC14S10B2(String k1) {
    return 'O que fazer: insira a chave novamente em $k1 ou mude para o reconhecimento no dispositivo.';
  }

  @override
  String get manualC14S11Heading => 'Memória gráfica cheia';

  @override
  String get manualC14S11B2 =>
      'O que fazer: nada. Depois você pode escolher o modelo de novo nas configurações.';

  @override
  String get manualC14S12Heading => 'Calculado no processador';

  @override
  String manualC14S12B2(String k1) {
    return 'O que fazer: normalmente nada. Se acontecer com frequência, confira a opção em $k1 e atualize o driver gráfico.';
  }

  @override
  String get manualC14S13Heading => 'Auto-Paste bloqueado (macOS)';

  @override
  String get manualC14S13B2 =>
      'O que fazer: permita o acesso do WhisPaste à Acessibilidade nas configurações do sistema. Se o aviso continuar, reinicie o WhisPaste.';

  @override
  String get manualC14S13SecureHeading =>
      'Auto-colagem ignorada (introdução segura pelo teclado, macOS)';

  @override
  String get manualC14S13SecureB2 =>
      'O que fazer: feche a aplicação indicada no aviso ou mude para outra e cole o texto de novo. O Terminal e o iTerm2 têm a opção «Secure Keyboard Entry» no menu. Um campo de senha ou PIN também ativa a introdução segura; aí cole o texto manualmente, porque o macOS não cola automaticamente nesses campos.';

  @override
  String get manualC14S14Heading => 'Auto-Paste bloqueado (Windows)';

  @override
  String get manualC14S14B2 =>
      'O que fazer: inicie o WhisPaste também como administrador.';

  @override
  String get manualC14S15Heading => 'Auto-Paste no Linux';

  @override
  String get manualC14S15B1 =>
      'No Linux, o Auto-Paste usa um dispositivo de entrada virtual (uinput). Se não funcionar, verifique se o WhisPaste pode acessar esse dispositivo.';

  @override
  String get manualC14S15B2 =>
      'O pacote .deb não dá nenhum acesso ao ser instalado. O Auto-Paste pergunta primeiro: na configuração inicial ou em Configurações → Depois da transcrição, escolha “Permitir (senha de administrador)” e digite sua senha de administrador. Enquanto a permissão existir, outros programas da sua sessão também podem gerar teclas. Com “Remover permissão” você a retira a qualquer momento; ao desinstalar, ela também é removida.';

  @override
  String get manualC14S15B3 =>
      'A versão Flatpak dá ao app acesso aos dispositivos de entrada do sistema, para que o Auto-Paste funcione. O próprio WhisPaste não lê nenhum dispositivo de entrada.';

  @override
  String get manualC14S15B4 =>
      'Na versão Snap, execute isto uma vez em um terminal:';

  @override
  String get manualC14S15B5 =>
      'O AppImage precisa de acesso a /dev/uinput. Na configuração inicial ou nas configurações, copie o comando e execute-o uma vez em um terminal. Ele instala a regra udev 71-whispaste-uinput.rules em /etc/udev/rules.d/, que dá acesso de escrita só à sessão conectada. Até lá, o Auto-Paste só copia o texto.';

  @override
  String get manualC14S15TerminalHeading => 'Terminais e Wayland';

  @override
  String get manualC14S15T1 =>
      'No Linux, os terminais colam com Ctrl+Shift+V. O WhisPaste reconhece os terminais comuns e usa esse atalho sozinho: com X11 e XWayland, e no KDE Plasma, Sway, Hyprland, niri, labwc, Wayfire e outros desktops wlroots.';

  @override
  String get manualC14S15T2 =>
      'No GNOME com Wayland, o WhisPaste só identifica o app de destino com a extensão opcional do WhisPaste para GNOME. Sem ela, o WhisPaste não reconhece terminais, e uma lista de bloqueio só copia o texto.';

  @override
  String manualC14S15T3(String k1, String k2) {
    return 'Se um terminal ainda mostrar ^V em vez do texto, ative “$k1” em $k2. O WhisPaste passa a colar com Ctrl+Shift+V em todo lugar. Alguns apps usam essas teclas para outra coisa; o LibreOffice, por exemplo, abre uma caixa de diálogo.';
  }

  @override
  String manualC14S15T4(String k1) {
    return 'No GNOME, ative a extensão do WhisPaste nas configurações com $k1. O pacote .deb já a instala. Com Flatpak, AppImage ou o tarball, instale-a uma vez com o script do pacote Linux descompactado e depois ative-a:';
  }

  @override
  String get manualC14S15InstallExtCmd => 'bash install-gnome-extension.sh';

  @override
  String get manualC14S15EnableExtCmd =>
      'gnome-extensions enable whispaste-focus@whispaste.de';

  @override
  String manualC14S15T5(String k1, String k2) {
    return 'Sem uinput configurado, por exemplo no Flatpak, o WhisPaste cola pela permissão da área de trabalho: $k1 em $k2. Sua área de trabalho pergunta uma vez; você pode retirar a permissão ali a qualquer momento';
  }

  @override
  String settingsDesktopShortcutGnome(String shortcut) {
    return 'Este desktop ainda não permite que apps usem atalhos de todo o sistema. O WhisPaste pode adicionar $shortcut aos atalhos de teclado do GNOME.';
  }

  @override
  String get settingsDesktopShortcutAdd => 'Adicionar ao GNOME';

  @override
  String settingsDesktopShortcutInstalled(String shortcut) {
    return '$shortcut está configurado nos atalhos de teclado do GNOME. Se você mudar o atalho, o WhisPaste o atualiza lá.';
  }

  @override
  String get settingsDesktopShortcutRemove => 'Remover do GNOME';

  @override
  String get settingsDesktopShortcutFailed =>
      'Não foi possível alterar os atalhos de teclado do GNOME.';

  @override
  String get settingsDesktopShortcutManual =>
      'Este desktop não permite que apps usem atalhos de todo o sistema. Associe este comando a uma combinação de teclas nas configurações do sistema:';

  @override
  String get manualC14S15HotkeyHeading => 'Atalho global no Wayland';

  @override
  String manualC14S15H1(String k1, String k2) {
    return 'No Wayland, um app só recebe atalhos de todo o sistema pelo desktop. O KDE Plasma e o GNOME 48 ou mais recente oferecem isso. Versões mais antigas do GNOME, como a do Ubuntu 24.04, não: nesse caso o WhisPaste oferece “$k1” em $k2 e adiciona o atalho aos atalhos de teclado do GNOME. Antes de salvar uma combinação, o gravador de atalhos avisa que é o desktop que define o atalho, não o WhisPaste.';
  }

  @override
  String manualC14S15H2(String k1) {
    return 'Em outros desktops, como Sway ou Hyprland, associe você mesmo o comando a uma combinação de teclas. As configurações mostram o comando exato para a sua instalação em $k1.';
  }

  @override
  String get manualC14S15H3 =>
      'Se o atalho não funciona em outros apps, as Configurações e a introdução mostram um aviso com o motivo, o comando para uma combinação própria e o botão «Reconectar», que pede o atalho ao ambiente de novo.';

  @override
  String get manualC14S15G1 =>
      'Manter ou tocar: se mantiveres a tecla mais tempo do que o limiar (250 ms por padrão), ela funciona como pulsar para falar. Um toque curto inicia e para a gravação.';

  @override
  String get manualC14S15G2 =>
      'Uma única tecla: em vez de uma combinação, você pode usar uma única tecla como atalho de ditado, separando esquerda e direita. Segurá-la dita até você soltar. Dois toques rápidos (em 400 ms) iniciam o ditado sem as mãos; um toque o termina. O mesmo vale para uma combinação; desative \"Toque duplo: ditar sem as mãos\" em \"Atalhos de teclado\". Escolha a tecla em \"Atalhos de teclado\" → \"Alterar atalho\".';

  @override
  String get manualC14S15G3 =>
      'Uma única tecla: são possíveis Shift, Ctrl, Alt ou Option e Command, Windows ou Super, cada uma esquerda ou direita, além de Fn (só Mac). As teclas esquerdas e o Shift só iniciam depois de segurá-las sozinhas por um instante, assim os atalhos comuns não acionam nada. No Linux com Wayland não há teclas únicas. Se a tecla não puder ser usada no dispositivo, vale por enquanto a combinação salva; sua escolha é mantida.';

  @override
  String get manualC14S15G4 =>
      'Permissão concedida depois: se o WhisPaste não conseguir observar a tecla, ele tenta de novo assim que você trouxer o WhisPaste para a frente. No Mac, o WhisPaste pede antes o Monitoramento de Entrada. Se você o conceder depois em Ajustes do Sistema, a tecla passa a funcionar sem reiniciar. Isso só vale enquanto a combinação funciona como substituta. No Windows, o Windows pode se recusar a deixar observar a tecla. No Linux a tecla não pode ser usada se a sessão não informar quando uma tecla é solta.';

  @override
  String get manualC14S15FlatpakHeading => 'Flatpak';

  @override
  String get manualC14S15B3W =>
      'Com esse acesso, o app poderia, em teoria, ler as teclas digitadas em outros programas, se o seu usuário tiver permissão de leitura nos dispositivos de entrada (por exemplo, como membro do grupo input). Os membros do grupo input também podem gerar entradas virtuais.';

  @override
  String get manualC14S15B3S =>
      'O Auto-Paste também precisa de acesso de escrita a /dev/uinput no computador: instale a regra udev 71-whispaste-uinput.rules em /etc/udev/rules.d/ e execute depois estes comandos:';

  @override
  String get manualC14S15Cmd =>
      'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  @override
  String get manualCodeCopy => 'Copiar comando';

  @override
  String get manualCodeCopied => 'Comando copiado';

  @override
  String get manualCodeCopyFailed =>
      'Não foi possível copiar. Selecione o comando e copie-o manualmente.';

  @override
  String get manualC14S15B3E =>
      'A regra dá acesso de escrita só à sessão conectada. Estes comandos precisam de permissões de administrador (sudo) e alteram o sistema. Se não quiser isso, deixe o Auto-Paste desligado e cole o texto à mão. Para remover a regra, use o botão nas configurações que copia o comando correspondente.';

  @override
  String get manualC14S15SnapHeading => 'Snap';

  @override
  String get manualC14S15SnapCmd => 'sudo snap connect whispaste:uinput';

  @override
  String get manualC14S15Fallback =>
      'Até lá, o Auto-Paste apenas copia o texto.';

  @override
  String get manualC14S15AppImageHeading => 'AppImage';

  @override
  String get manualC14S16Heading => 'O atalho já está em uso';

  @override
  String manualC14S16B2(String k1) {
    return 'O que fazer: escolha outra combinação em $k1. No Mac, um toque em Fn abre os emojis e dois toques podem iniciar o ditado do sistema. Para evitar isso, defina \"Pressionar a tecla 🌐 para\" como \"Não Fazer Nada\" em Ajustes do Sistema → Teclado.';
  }

  @override
  String get manualC14S16B3 =>
      'O WhisPaste avisa sobre uma combinação que o sistema já usa. Você ainda pode salvar; o aviso mostra a função do sistema e o próximo passo.';

  @override
  String get manualC14S17Heading => 'Início automático não configurado';

  @override
  String get manualC14S17B2 =>
      'O que fazer: verifique as permissões de inicialização automática no sistema operacional. Sem isso, o WhisPaste não inicia sozinho.';

  @override
  String get manualC14S18Heading => 'Backup automático falhou';

  @override
  String manualC14S18B2(String k1) {
    return 'O que fazer: escolha outra pasta acessível em $k1.';
  }

  @override
  String get manualC14S19Heading => 'Redefinição de fábrica incompleta';

  @override
  String get manualC14S19B2 =>
      'O que fazer: escolha “Tentar novamente” ou reinicie o WhisPaste e execute a redefinição novamente depois.';

  @override
  String get manualC14S20Heading => 'Nenhum som detectado';

  @override
  String manualC14S20B2(String k1) {
    return 'O que fazer: verifique o microfone em $k1 e grave de novo.';
  }

  @override
  String get manualC14S21Heading => 'Memória insuficiente';

  @override
  String get manualC14S22Heading => 'O atalho parou de responder';

  @override
  String get manualC14S22B1 =>
      'Às vezes o sistema perde o atalho global, por exemplo após a suspensão ou quando o computador estava muito ocupado. O WhisPaste o registra novamente por conta própria: ao acordar o computador, depois de descarregar o modelo de voz para liberar memória, após um travamento longo da janela e a cada cinco minutos. Isso não acontece enquanto você dita ou mantém a tecla pressionada. Se o atalho continuar sem resposta, reinicie o WhisPaste. Um aviso aparece só após três tentativas seguidas sem sucesso.';

  @override
  String manualC14S22B2(String k1) {
    return 'Se outro app usar a mesma combinação, escolha outra em $k1.';
  }

  @override
  String manualC14S21B1(String k1) {
    return 'O WhisPaste também inicia com menos memória do que a recomendada ($k1). Nesse caso, o app sugere o modelo de voz “Rápido”.';
  }

  @override
  String get manualC15Title => 'Atalhos de teclado';

  @override
  String get manualC15S1Heading => 'Somente no WhisPaste';

  @override
  String manualC15S1B1(String k2) {
    return 'Estes atalhos só funcionam com a janela do WhisPaste ativa. Já o atalho do sistema inteiro é definido em $k2.';
  }

  @override
  String manualC15S1B2(String k1, String k2) {
    return 'No Mac, $k1 normalmente substitui $k2.';
  }

  @override
  String get manualC15S1B3I1 => 'F1 abre a ajuda.';

  @override
  String manualC15S1B3I2(String k) {
    return '$k também abre a ajuda.';
  }

  @override
  String get manualC15S2Heading => 'Gravações';

  @override
  String manualC15S2B1I1(String k1) {
    return '$k1: excluir a entrada.';
  }

  @override
  String manualC15S2B1I2(String k1) {
    return '$k1: alternar favorito.';
  }

  @override
  String manualC15S2B1I3(String k1) {
    return '$k1: pesquisar.';
  }

  @override
  String manualC15S2B1I4(String k1) {
    return '$k1: fechar a pesquisa ou a visualização de detalhes.';
  }

  @override
  String manualC15S2B1I5(String k1) {
    return '$k1: copiar a entrada.';
  }

  @override
  String manualC15S2B1I6(String k1) {
    return '$k1: descartar a edição. Alterações não salvas pedem confirmação antes.';
  }

  @override
  String get manualC15S3Heading => 'Notas';

  @override
  String manualC15S3B1I1(String k1) {
    return '$k1: excluir a entrada.';
  }

  @override
  String manualC15S3B1I2(String k1) {
    return '$k1: criar uma nova nota.';
  }

  @override
  String manualC15S3B1I3(String k1) {
    return '$k1: pesquisar.';
  }

  @override
  String get manualC15S4Heading => 'Dicionário e snippets';

  @override
  String manualC15S4B1I1(String k1) {
    return '$k1: excluir a entrada.';
  }

  @override
  String get manualC15S5Heading => 'Cancelar durante uma gravação';

  @override
  String manualC15S5B1(String k1, String k2) {
    return 'Enquanto uma gravação ou transcrição está em andamento, o WhisPaste intercepta a tecla $k1 em todo o sistema para você poder cancelar. Nesse período, $k1 não faz nada em outros aplicativos. Se isso incomodar, escolha $k2 como tecla de cancelar em Configurações.';
  }

  @override
  String get manualC16Title => 'Feedback e apoio';

  @override
  String get manualC16S1Heading => 'Enviar feedback';

  @override
  String get manualC16S1B1I1 => 'Avaliação: obrigatória.';

  @override
  String get manualC16S1B1I2 =>
      'Tipo: obrigatório. Escolha Problema, Ideia, Elogio ou Pergunta.';

  @override
  String get manualC16S1B1I3 => 'Texto livre de até 1000 caracteres.';

  @override
  String get manualC16S1B1I4 => 'O endereço de e-mail é opcional.';

  @override
  String get manualC16S1B2 =>
      'Se você enviou feedback recentemente, o app mostra este aviso:';

  @override
  String get manualC16S2Heading => 'Apoio';

  @override
  String manualC16S2B1(String k1) {
    return 'A aba $k1 da ajuda mostra como você pode apoiar o WhisPaste.';
  }

  @override
  String manualC16S2B2(String k1) {
    return 'Os downloads diretos (instalador e portátil do Windows, versão direta do Mac, Linux) mostram os botões de café Ko-fi e, onde for oferecido, Buy Me a Coffee no topo da aba $k1, abaixo da versão nas Configurações. As versões da loja (Mac App Store, Microsoft Store) não têm páginas externas; no máximo, oferecem a gorjeta da própria loja. O menu da bandeja abre essa aba.';
  }

  @override
  String get manualC16S3Heading => 'Aviso de avaliação';

  @override
  String manualC16S3B1(String k1, String k2) {
    return 'Se escolheu «Não perguntar novamente» no aviso de avaliação, encontra o interruptor «$k2» em $k1. Ele só aparece nesse caso.';
  }

  @override
  String get manualC16S4B1 =>
      'Você pode entrar em contato pelo cartão «Entrar em contato» na aba Ajuda, pelo item «Entrar em contato…» no menu Ajuda da barra de menus (macOS) ou no menu da barra de título (Windows e Linux), e pelo menu da bandeja. Dali, o formulário está a dois passos.';

  @override
  String get manualC16S5Heading => 'Compartilhar uma ideia';

  @override
  String get manualC16S5B1 =>
      'Escolha Ideia ou abra Sugerir uma ideia no menu Ajuda: o tipo já vem selecionado. Você também pode publicar sua ideia no quadro público de ideias e votar nas dos outros.';

  @override
  String get manualC16S6Heading => 'Escrever por voz';

  @override
  String get manualC16S6B1 =>
      'O botão do microfone no campo da mensagem grava sua voz e insere o texto reconhecido na posição do cursor.';

  @override
  String get manualC16S7Heading => 'O que é enviado';

  @override
  String get manualC16S7B1I1 => 'O tipo que você escolheu e sua mensagem.';

  @override
  String get manualC16S7B1I3 =>
      'Seu e-mail somente se você o informou. Ele é usado apenas para responder e é apagado após 90 dias.';

  @override
  String get manualC16S7B1I4 =>
      'Diagnóstico somente se você ativar Anexar diagnóstico: versão do app, sistema operacional, motor de voz e backend. Mostrar prévia exibe o texto exato antes de enviar.';

  @override
  String get manualC16S7B1I5 =>
      'Apenas em Elogio: a autorização para mostrar o seu elogio como citação no site. Vem desligada por padrão e pode ser retirada com um clique nesta página.';

  @override
  String get manualC16S7B2 => 'Gravações e transcrições nunca são anexadas.';

  @override
  String get manualC16S8Heading => 'Participar na visão geral';

  @override
  String get manualC16S8B1 =>
      'Os dois cartões mostram as estrelas no GitHub e os inscritos no YouTube. O app consulta os números no servidor no máximo uma vez por dia, e só enquanto a visão geral estiver aberta. Números com mais de sete dias não são mais mostrados; sem número, o cartão apenas indica para que serve o link. Na parte de baixo da visão geral, os links levam ao código-fonte e aos vídeos. «Apoie o projeto» abre Ajuda → Apoio, que mostra o que a sua versão oferece. As versões de download direto mostram também o quadro de ideias; as versões da loja, a avaliação na loja. Você pode ocultar a seção com «Ocultar esta seção» ou em «Personalizar visão geral».';

  @override
  String get manualC16S4Heading => 'Onde encontrar o formulário';

  @override
  String get manualC16S7B1I2 => 'A avaliação que você escolheu.';

  @override
  String pasteFailureClipboardCopy(Object paste) {
    return 'Não foi possível colar – o texto está na área de transferência ($paste).';
  }

  @override
  String get pasteFailureCheckPermission => 'Verificar permissão';

  @override
  String get autoPasteResetConfirmTitle =>
      'Redefinir a entrada e permitir novamente?';

  @override
  String get autoPasteResetConfirmBody =>
      'O macOS guardou uma entrada antiga do WhisPaste que não se aplica mais. O WhisPaste remove apenas essa entrada de Acessibilidade. Depois o macOS vai perguntar de novo. As demais permissões não mudam.';

  @override
  String get autoPasteResetConfirmButton =>
      'Redefinir entrada e permitir novamente';

  @override
  String get permissionRowMicTitle => 'Microfone';

  @override
  String get permissionRowMicPurpose =>
      'Grava a sua voz. Sem essa permissão não é possível gravar nada.';

  @override
  String get permissionRowPasteTitle => 'Auto-Paste';

  @override
  String get permissionRowPastePurpose =>
      'Coloca o texto no cursor. Sem ela, o texto fica na área de transferência.';

  @override
  String get permissionRowAllow => 'Permitir';

  @override
  String get permissionRowMissingSettings => 'Em falta – abrir Ajustes';

  @override
  String get permissionRowGranted => 'Permitido';

  @override
  String get permissionRowOptional => 'Opcional';

  @override
  String get autostartApprovalBody =>
      'O macOS aguarda a sua aprovação: o WhisPaste só inicia no login depois de o ativar em Itens de Início de Sessão.';

  @override
  String get autostartApprovalAction => 'Abrir Itens de Início de Sessão';

  @override
  String get pasteFailureLinuxUinputHint =>
      'A colagem automática precisa uma única vez da sua permissão para o teclado virtual (/dev/uinput).';

  @override
  String get pasteFailureLinuxUinputCopy => 'Copiar comando';

  @override
  String get pasteFailureLinuxNoDeviceHint =>
      'A colagem automática não está disponível neste sistema: não há nenhum dispositivo de teclado virtual.';

  @override
  String get pasteFailureLinuxUinputSettingsHint =>
      'A colagem automática precisa de acesso único a /dev/uinput. Abra as definições do Auto-Paste para a configuração única.';

  @override
  String linuxUinputConsentNotice(String paste) {
    return 'O Auto-Paste agora pergunta antes de usar o teclado virtual /dev/uinput, por isso esta atualização removeu o acesso antigo. O texto está na área de transferência; cole-o com $paste. Clique aqui para permitir.';
  }

  @override
  String get linuxUinputSetupAction => 'Configurar';

  @override
  String get linuxUinputConsentDetail =>
      'Para colar o texto sozinho, o WhisPaste precisa de um teclado virtual. Enquanto ele estiver permitido, outros programas da sua sessão também podem gerar teclas. Sem permissão, o WhisPaste copia o texto e você cola.';

  @override
  String get linuxUinputGrantButton => 'Permitir (senha de administrador)';

  @override
  String get linuxUinputGrantFailed =>
      'Não foi possível dar a permissão. O WhisPaste continua só copiando o texto.';

  @override
  String get linuxUinputRevokeButton => 'Remover permissão';

  @override
  String get linuxUinputRevokeDone =>
      'Permissão removida. Agora o WhisPaste só copia o texto.';

  @override
  String get settingsSecureKeysNotRemoved =>
      'As chaves de API não puderam ser removidas por completo.';

  @override
  String analyticsDurationHours(String hours) {
    return '$hours h';
  }

  @override
  String analyticsDurationMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get dockErrorCauseEngine => 'O modelo de voz parou com um erro.';

  @override
  String get dockErrorCauseRecording => 'A gravação não pôde ser transcrita.';

  @override
  String get dockErrorAction =>
      'Abra as configurações de voz para verificar o modelo de voz.';

  @override
  String get overlayDoneCopiedOnly =>
      'Apenas copiado – app de destino bloqueado ou não reconhecido';

  @override
  String get overlayDoneNotPasted => 'Não colado – salvo em Gravações';

  @override
  String get overlayDonePasteFailed => 'Colagem não possível – copie o texto';

  @override
  String get overlayDoneInClipboard => 'Na área de transferência';

  @override
  String get databaseTooNewTitle => 'O WhisPaste não consegue abrir seus dados';

  @override
  String databaseTooNewCause(int storedVersion, int supportedVersion) {
    return 'Os dados foram gravados por uma versão mais recente do WhisPaste (versão do banco de dados $storedVersion). Esta versão suporta até a versão $supportedVersion.';
  }

  @override
  String get databaseTooNewNextStep =>
      'Instale a versão mais recente do WhisPaste e abra o app novamente. Nada foi alterado nem apagado.';

  @override
  String get databaseTooNewQuit => 'Sair';

  @override
  String get databaseUpgradeInterruptedTitle =>
      'O WhisPaste não conseguiu atualizar seus dados';

  @override
  String get databaseUpgradeInterruptedCause =>
      'Não foi possível levar seus dados para a nova versão agora: o arquivo estava em uso ou o disco não respondeu. Nada foi alterado, e todos os seus dados continuam lá.';

  @override
  String get databaseUpgradeInterruptedNextStep =>
      'Feche outros programas que possam estar usando o arquivo, verifique o espaço livre no disco e tente novamente.';

  @override
  String get pasteFailureTargetChanged =>
      'Auto-colagem cancelada: você trocou de app durante o processamento. O texto está na área de transferência.';

  @override
  String pasteFailureUnconfirmed(String paste) {
    return 'Auto-colagem não confirmada. O texto está na área de transferência, cole-o com $paste.';
  }

  @override
  String get pasteHintSecureField =>
      'O macOS não permite a auto-colagem em campos de senha e PIN. Cole o texto ali manualmente.';

  @override
  String pasteSecureInputNamed(String app) {
    return '“$app” tem a introdução segura pelo teclado ativada, por isso o WhisPaste não cola automaticamente. Feche $app ou mude para outra aplicação.';
  }

  @override
  String get pasteSecureInputGeneric =>
      'Uma aplicação tem a introdução segura pelo teclado ativada, por isso o WhisPaste não cola automaticamente. Feche essa aplicação ou mude para outra.';

  @override
  String pasteSecureInputClipboard(String paste) {
    return 'O texto está na área de transferência. Cole-o com $paste.';
  }

  @override
  String get pasteSecureInputTerminalTip =>
      'No Terminal, abra o menu Terminal e desative «Secure Keyboard Entry» (Introdução segura pelo teclado).';

  @override
  String get pasteSecureInputItermTip =>
      'No iTerm2, desative «Secure Keyboard Entry» (Introdução segura pelo teclado) na barra de menus.';

  @override
  String get pasteNotificationReceiptRefusedTitle =>
      'WhisPaste: colagem não confirmada';

  @override
  String get pasteReceiptRefusedText =>
      'Colagem não confirmada – o texto está na área de transferência.';

  @override
  String get fileDialogOpenTitle => 'Abrir arquivo';

  @override
  String get fileDialogOpenFilesTitle => 'Abrir arquivos';

  @override
  String get fileDialogSaveTitle => 'Salvar arquivo';

  @override
  String get fileDialogFolderTitle => 'Escolher pasta';

  @override
  String get fileDialogSelectFolder => 'Selecionar';

  @override
  String get dockLanguageAuto => 'Automático';

  @override
  String get settingsLanguageFavoriteAdd => 'Adicionar aos favoritos';

  @override
  String get settingsLanguageFavoriteRemove => 'Remover dos favoritos';

  @override
  String get settingsLanguageFavoritesLimit =>
      'Até 3 favoritos. Remova um para adicionar outro.';

  @override
  String get dockMenuFavorites => 'Favoritos';

  @override
  String get dockMenuAllLanguages => 'Todos os idiomas';

  @override
  String get traySpeechModel => 'Modelo de fala';

  @override
  String trayTooltipSmartMode(String preset) {
    return 'Smart Mode: $preset';
  }

  @override
  String get trayLinuxNoTrayHost =>
      'O ícone da bandeja precisa de um host de bandeja. No GNOME, instale a extensão AppIndicator; até lá, o menu de troca rápida não está disponível.';

  @override
  String get trayLanguage => 'Idioma';

  @override
  String get trayLanguageMore => 'Mais…';

  @override
  String get trayProfile => 'Perfil';

  @override
  String get trayProfileAutomatic => 'Automático, por app';

  @override
  String get trayProfileNone => 'Sem perfil';

  @override
  String profileSwitchedToast(String name) {
    return 'Perfil: $name';
  }

  @override
  String get settingsHotkeyActionLanguageCycle => 'Próximo idioma favorito';

  @override
  String get settingsLanguageCycleHotkeyEnabled => 'Próximo idioma favorito';

  @override
  String get settingsLanguageCycleHotkeyHint =>
      'Muda o idioma do ditado para o próximo favorito. Marque até três idiomas como favoritos em Fala para texto.';

  @override
  String settingsLanguageCycleHotkeyCollision(String action) {
    return 'Já usado por $action. Escolha outra combinação.';
  }

  @override
  String get settingsLanguageCycleHotkeyInactive =>
      'O atalho está em uso por outro aplicativo ou não pôde ser registrado. Escolha outra combinação.';

  @override
  String get settingsLanguageCycleHotkeyWaylandNotice =>
      'No Wayland, este atalho pode não funcionar em outros aplicativos. Crie um atalho de área de trabalho se ele não responder.';

  @override
  String get settingsHotkeyActionRepaste => 'Colar o último ditado novamente';

  @override
  String get settingsRepasteHotkeyEnabled => 'Colar o último ditado novamente';

  @override
  String get settingsRepasteHotkeyHint =>
      'Cola novamente o texto da sua última gravação no app em primeiro plano, por exemplo quando ele foi parar no campo errado.';

  @override
  String get repasteNothingYet => 'Ainda não há ditado para colar';

  @override
  String languageCycleSwitchedToast(String language) {
    return 'Idioma do ditado: $language';
  }

  @override
  String languageCycleSwitchedNextRecordingToast(String language) {
    return 'Idioma do ditado: $language. Vale a partir da próxima gravação.';
  }

  @override
  String get languageCycleNoFavoritesToast =>
      'Ainda não há idiomas favoritos. Marque até três idiomas em Fala para texto para usar este atalho.';

  @override
  String get languageCycleOpenSettings => 'Abrir configurações';

  @override
  String get manualLangFavHeading => 'Idiomas favoritos';

  @override
  String get manualLangFavB1 =>
      'Nas configurações de reconhecimento de fala, marque até três idiomas como favoritos com a estrela na lista de idiomas. Os favoritos aparecem primeiro no menu de idiomas da barra de gravação e no menu da bandeja, para trocar com um clique.';

  @override
  String get manualLangTrayHeading => 'Idioma no menu da bandeja';

  @override
  String get manualLangTrayB1 =>
      'O menu da bandeja tem um submenu Idioma. Ele lista seus favoritos e marca com um visto o idioma ativo. Mais… abre a janela com a lista completa. O Parakeet escolhe o próprio idioma, então o submenu fica oculto ali.';

  @override
  String get manualLangCycleHeading => 'Próximo idioma favorito';

  @override
  String get manualLangCycleB1 =>
      'Na seção Ditado você pode atribuir uma combinação de teclas que troca o idioma do ditado para o próximo favorito a cada toque. O atalho fica desativado até você gravar uma combinação. Sem favoritos, o WhisPaste indica onde ajustá-los. No Linux com Wayland, outros aplicativos podem não responder ao atalho.';

  @override
  String desktopShortcutToast(String shortcut) {
    return '$shortcut só funciona em todo o sistema depois de ser adicionado aos atalhos de teclado do GNOME.';
  }

  @override
  String get recommendationReasonLanguage =>
      'Recomendado porque o Parakeet suporta a tua língua e é a opção mais precisa que corre com fluidez neste dispositivo.';

  @override
  String get recommendationReasonMeasured =>
      'Recomendado pela medição neste aparelho.';

  @override
  String recommendationReasonApple(String memory) {
    return 'Recomendado para seu chip da Apple (Metal) com $memory.';
  }

  @override
  String recommendationReasonCuda(String gb) {
    return 'Recomendado para sua placa de vídeo NVIDIA com $gb GB de memória de vídeo (CUDA).';
  }

  @override
  String recommendationReasonVulkan(String name) {
    return 'Recomendado para sua placa de vídeo $name (Vulkan).';
  }

  @override
  String recommendationReasonCpu(int cores, String memory) {
    return 'Recomendado para o processador, pois não há placa de vídeo utilizável: $cores núcleos, $memory.';
  }

  @override
  String recommendationReasonSoftware(String name, int cores, String memory) {
    return '$name é gráfico por software, então o processador faz o trabalho: $cores núcleos, $memory.';
  }

  @override
  String recommendationMemory(String gb) {
    return '$gb GB de RAM';
  }

  @override
  String get recommendationMemoryUnknown => 'RAM desconhecida';

  @override
  String dockMenuDownloadMissing(String name, String size) {
    return 'Sem modelo de voz – baixar $name agora ($size)';
  }

  @override
  String get manualC01S3B5 =>
      'Se o modelo de voz selecionado estiver faltando, o dock mostra “Modelo de voz ausente”. O menu de voz do dock então o oferece como primeira opção para baixar, tanto para Whisper quanto para Parakeet. Se você pressionar o atalho sem modelo, aparece um aviso com “Baixar agora”. Se você mudar para Whisper em Configurações e o modelo Whisper selecionado estiver faltando, o WhisPaste escolhe um já baixado.';

  @override
  String benchmarkBackendSoftwareVulkan(String name) {
    return 'Processador (Vulkan por software, $name)';
  }

  @override
  String get menuBarMenuEdit => 'Editar';

  @override
  String get menuBarMenuWindow => 'Janela';

  @override
  String get menuBarEditUndo => 'Desfazer';

  @override
  String get menuBarEditRedo => 'Refazer';

  @override
  String get menuBarEditCut => 'Recortar';

  @override
  String get menuBarEditCopy => 'Copiar';

  @override
  String get menuBarEditPaste => 'Colar';

  @override
  String get menuBarEditSelectAll => 'Selecionar tudo';

  @override
  String get menuBarWindowMinimize => 'Minimizar';

  @override
  String get menuBarWindowZoom => 'Ampliar';

  @override
  String get menuBarAppQuit => 'Sair do WhisPaste';

  @override
  String get menuBarMenuRecording => 'Gravação';

  @override
  String get menuBarAppSettings => 'Configurações…';

  @override
  String get menuBarHelpManual => 'Abrir o manual';

  @override
  String get menuBarHelpFeedback => 'Enviar feedback…';

  @override
  String get menuBarHelpIdea => 'Sugerir uma ideia…';

  @override
  String get menuBarHelpContact => 'Entrar em contato…';

  @override
  String get helpContactHeading => 'Entrar em contato';

  @override
  String get helpContactBody =>
      'Tem uma pergunta ou precisa de ajuda? Escreva para nós, teremos prazer em ajudar.';

  @override
  String get helpContactAction => 'Entrar em contato';

  @override
  String get helpContactIdeasLink =>
      'As ideias vão para o quadro público de votação';

  @override
  String get manualC15S6Heading => 'Menu';

  @override
  String get manualC15S6B1 =>
      'No Mac, os comandos mais importantes também estão na barra de menus no topo. O menu «Gravação» inicia e para uma gravação e define o idioma, o modelo de fala, o Smart Mode, o que acontece após a transcrição, o microfone e o perfil.';

  @override
  String manualC15S6B2I1(String k1) {
    return 'WhisPaste: abrir as configurações com $k1';
  }

  @override
  String get manualC15S6B2I2 =>
      'Editar: recortar, copiar, colar e selecionar tudo atuam sobre o campo de texto ativo.';

  @override
  String get manualC15S6B2I3 =>
      'Janela: minimizar e ampliar a janela principal.';

  @override
  String get manualC15S6B2I4 =>
      'Ajuda: abrir o manual, enviar feedback e sugerir uma ideia.';

  @override
  String get manualC15S6B3 =>
      'No Windows e no Linux, os mesmos comandos estão num botão de menu no canto superior direito da barra de título. Pressione Alt ou F10 para abri-lo, use as setas para escolher uma entrada, Enter para executá-la e Esc para fechar o menu.';

  @override
  String get menuBarAppAbout => 'Sobre o WhisPaste';

  @override
  String get menuBarAppHide => 'Ocultar';

  @override
  String get menuBarAppHideOthers => 'Ocultar outros';

  @override
  String get menuBarAppShowAll => 'Mostrar tudo';

  @override
  String get titleBarMenuLabel => 'Menu';

  @override
  String get notesTitleLabel => 'Título';

  @override
  String get notesMoreActions => 'Mais ações';

  @override
  String get notesVersionSaveNow => 'Salvar versão agora';

  @override
  String get notesMenuMark => 'Destacar';

  @override
  String get notesMenuAddImage => 'Inserir imagem';

  @override
  String get notesMenuVersions => 'Versões';

  @override
  String get notesMenuSnippet => 'Salvar como snippet';

  @override
  String get notesVersionsEmpty => 'Ainda não há versões.';

  @override
  String get notesVersionTooLarge => 'Grande demais para visualizar';

  @override
  String get notesVersionDelete => 'Excluir versão';

  @override
  String get notesVersionSaved => 'Versão salva';

  @override
  String get notesVersionUnchanged =>
      'Não há alterações desde a última versão.';

  @override
  String get notesVersionRestored => 'Versão restaurada';

  @override
  String get notesVersionRestoreMessage =>
      'Só o título e o texto são restaurados para esta versão. As imagens permanecem como estão.';

  @override
  String get notesVersionDeleteMessage =>
      'Esta versão será excluída permanentemente e não pode ser recuperada.';

  @override
  String get notesImageFilesLabel => 'Imagens';

  @override
  String get notesImageRejected =>
      'Este arquivo não é uma imagem compatível (PNG, JPEG, GIF ou WebP).';

  @override
  String get notesImageRemove => 'Remover imagem';

  @override
  String get notesSnippetCreated => 'Snippet criado';

  @override
  String get notesSnippetNothing =>
      'Esta nota não tem texto para salvar como snippet.';

  @override
  String get notesMarkNeedsSelection => 'Selecione um texto primeiro.';

  @override
  String get notesImageLimitCount =>
      'Esta nota já tem o número máximo de imagens.';

  @override
  String get notesImageLimitBytes =>
      'As imagens desta nota excederiam o limite de tamanho.';

  @override
  String get notesImageLimitTotal =>
      'O armazenamento de imagens está cheio. Remova uma imagem para adicionar outra.';

  @override
  String get historyImportFailureCopyInterrupted =>
      'O arquivo chegou devagar demais ou mudou durante a cópia. Tente novamente.';

  @override
  String get historyImportFailureDecoderUnavailableLinux =>
      'No Linux, falta um pacote extra para M4A/AAC: o decodificador AAC do GStreamer. Instale gstreamer1.0-libav (no Debian ou Ubuntu com sudo apt install gstreamer1.0-libav; em outras distribuições, procure o pacote libav do GStreamer no gerenciador de pacotes), reinicie o WhisPaste e importe o arquivo novamente.';

  @override
  String get historyImportFailureDecoderUnavailableSnap =>
      'Falta o decodificador AAC do GStreamer para M4A/AAC. A versão Snap deveria incluí-lo. Informe este caso pelo Feedback e indique a sua versão do Snap. Até lá, converta o arquivo para WAV e importe-o novamente.';

  @override
  String get historyImportFailureDecoderUnavailableFlatpak =>
      'Falta o decodificador AAC do GStreamer para M4A/AAC na versão Flatpak. O sandbox do Flatpak não pode ser ampliado pelo gerenciador de pacotes. Converta o arquivo para WAV e importe-o novamente. O manual descreve o suporte a M4A/AAC no Flatpak no capítulo Importar arquivos de áudio; se isso não resolver o seu caso, informe pelo Feedback.';

  @override
  String get historyImportFailureDecoderUnavailable =>
      'Este formato não está disponível neste sistema. Converta o arquivo para WAV e importe-o novamente.';

  @override
  String get audioDropHint =>
      'Solte aqui arquivos de áudio para transcrevê-los';

  @override
  String audioDropRejectedFolder(String names) {
    return 'Não é possível importar pastas: $names';
  }

  @override
  String audioDropRejectedNotFound(String names) {
    return 'Arquivo não encontrado: $names';
  }

  @override
  String audioDropRejectedFormat(String names, String formats) {
    return 'Não compatível: $names. Formatos permitidos: $formats.';
  }

  @override
  String audioDropRejectedNotRegular(Object names) {
    return 'Não é um arquivo comum, não pode ser importado: $names';
  }

  @override
  String audioDropRejectedTooLarge(Object names) {
    return 'Muito grande (máximo 1 GB): $names';
  }

  @override
  String get historyImportRejectedNotRegularFile =>
      'Não é um arquivo comum e não pode ser importado.';

  @override
  String get historyImportRejectedTooLarge => 'O arquivo é maior que 1 GB.';

  @override
  String audioDropRejectedReservedName(Object names) {
    return 'Nome de dispositivo reservado, não pode ser importado: $names';
  }

  @override
  String get historyImportRejectedReservedName =>
      'O Windows reserva este nome de arquivo e ele não pode ser importado. Renomeie o arquivo.';

  @override
  String get historyImportFailureIo =>
      'O armazenamento está cheio ou não é gravável.';

  @override
  String get holdToRecordExplained =>
      'Ativado: segure o atalho e fale, solte para terminar. Desativado: pressione uma vez para iniciar e de novo para terminar.';

  @override
  String get settingsAreaProfiles => 'Perfis';

  @override
  String get profilesSectionHeading => 'Seus perfis';

  @override
  String get profilesEmptyBody =>
      'Perfis trocam o modelo de fala, o idioma, o Smart Mode e a ação após a transcrição com um atalho ou automaticamente por app.';

  @override
  String get profilesAddFirst => 'Criar primeiro perfil';

  @override
  String get profilesAdd => 'Criar perfil';

  @override
  String get profilesCreate => 'Criar';

  @override
  String get profilesLimitReached =>
      'No máximo 9 perfis. Exclua um para criar outro.';

  @override
  String get profilesActiveBadge => 'Ativo';

  @override
  String get profilesMoveUp => 'Mover para cima';

  @override
  String get profilesMoveDown => 'Mover para baixo';

  @override
  String get profilesDragHandle => 'Arraste para reordenar';

  @override
  String get profilesNewTitle => 'Novo perfil';

  @override
  String get profilesNameLabel => 'Nome';

  @override
  String get profilesNameEmpty => 'Digite um nome.';

  @override
  String get profileDetailHeading => 'Configurações do perfil';

  @override
  String get profileDetailModel => 'Modelo de fala';

  @override
  String get profileDetailLanguage => 'Idioma';

  @override
  String get profileDetailLanguageSubtitle =>
      'Vale para Whisper e serviços na nuvem. O Parakeet detecta o idioma sozinho.';

  @override
  String get profileDetailSmartMode => 'Smart Mode';

  @override
  String get profileDetailAfter => 'Após a transcrição';

  @override
  String get profileDetailMicrophone => 'Microfone';

  @override
  String get profileKeepUnchanged => 'Deixar sem alteração';

  @override
  String profileValueUnavailable(String value) {
    return '$value (indisponível)';
  }

  @override
  String get profileDetailHotkey => 'Atalho';

  @override
  String get profileDetailHotkeySubtitle =>
      'Muda para este perfil com esta combinação.';

  @override
  String get profileHotkeyNone => 'Sem atalho';

  @override
  String get profileHotkeyChange => 'Definir atalho';

  @override
  String get profileHotkeyRemove => 'Remover atalho';

  @override
  String get profileHotkeyNeedsModifier =>
      'Um atalho de perfil precisa de pelo menos uma tecla modificadora, como Ctrl, Alt, Shift ou Comando.';

  @override
  String profileHotkeyTakenByApp(String action) {
    return 'Já usado por «$action». O atalho não está ativo.';
  }

  @override
  String profileHotkeyTakenByProfile(String name) {
    return 'Já usado pelo perfil «$name». O atalho não está ativo.';
  }

  @override
  String get profileDetailApps => 'Apps de destino';

  @override
  String get profileDetailAppsSubtitle =>
      'Quando um destes apps está em primeiro plano ao ditar, o perfil fica ativo automaticamente.';

  @override
  String get profileAppIdentifierLabel => 'Identificador do app';

  @override
  String get profileAppAdd => 'Adicionar';

  @override
  String get profileAppHintMac => 'macOS: ID do pacote, ex.: com.apple.mail';

  @override
  String get profileAppHintWindows =>
      'Windows: nome do programa sem .exe, ex.: chrome';

  @override
  String get profileAppHintLinux =>
      'Linux: WM_CLASS da janela, ex.: google-chrome. No Wayland não é detectável.';

  @override
  String profileAppClash(String name) {
    return 'Este app já pertence ao perfil «$name».';
  }

  @override
  String get profileAppEmpty => 'Nenhum app atribuído ainda.';

  @override
  String get profileAppRemove => 'Remover regra do app';

  @override
  String get profileDetailContext => 'Ler contexto';

  @override
  String get profileDetailContextSubtitle =>
      'Opcionalmente lê o texto selecionado ou a área de transferência para adequar o processamento. Com serviços na nuvem, só com o seu consentimento.';

  @override
  String get profileContextNone => 'Não ler nada';

  @override
  String get profileContextSelection => 'Texto selecionado';

  @override
  String get profileContextClipboard => 'Área de transferência';

  @override
  String get profileConsentGiven => 'Consentimento dado';

  @override
  String get profileConsentMissing =>
      'Falta o consentimento; nenhum contexto é lido';

  @override
  String get profileConsentWithdraw => 'Retirar consentimento';

  @override
  String get profileConsentTitle => 'Enviar contexto a um serviço na nuvem?';

  @override
  String get profileConsentBody =>
      'Quando este perfil está ativo, o texto selecionado ou o conteúdo da área de transferência da janela de destino são enviados ao provedor na nuvem indicado neste perfil, apenas para refinar este ditado. Você pode retirar este consentimento a qualquer momento nas configurações do perfil.';

  @override
  String get profileConsentAccept => 'Consentir';

  @override
  String get profileDeleteAction => 'Excluir perfil';

  @override
  String profileDeleteTitle(String name) {
    return 'Excluir o perfil «$name»?';
  }

  @override
  String get profileDeleteMessage =>
      'O perfil e os seus apps de destino serão removidos. O atalho dele ficará livre.';

  @override
  String get manualProfilesTitle => 'Perfis e troca rápida';

  @override
  String get manualProfilesS1Heading => 'Criar perfis';

  @override
  String get manualProfilesS1Body =>
      'Um perfil é um conjunto nomeado de configurações de ditado. Você o cria em Configurações → Perfis e decide, em cada campo, se o perfil o define ou o deixa sem alteração.';

  @override
  String get manualProfilesS1B1 =>
      'Modelo de fala, idioma, Smart Mode, ação após a transcrição e microfone';

  @override
  String get manualProfilesS1B2 =>
      'Até 9 perfis. Cada campo pode ficar em «Deixar sem alteração».';

  @override
  String get manualProfilesS2Heading => 'Atalhos';

  @override
  String get manualProfilesS2Body =>
      'Cada perfil pode ter o seu próprio atalho. Ao pressioná-lo, o perfil fica ativo até que você escolha outro ou altere à mão um dos seus campos.';

  @override
  String get manualProfilesS2Tip =>
      'Um atalho precisa de uma tecla modificadora. Uma combinação que outra função já usa fica inativa e o perfil a mostra como conflito.';

  @override
  String get manualProfilesS3Heading => 'Automático por app';

  @override
  String get manualProfilesS3Body =>
      'Se você adicionar um app em Apps de destino, o perfil fica ativo sempre que esse app estiver em primeiro plano ao ditar. O identificador depende do sistema operacional:';

  @override
  String get manualProfilesS3Mac =>
      'macOS: ID do pacote, por exemplo com.apple.mail';

  @override
  String get manualProfilesS3Win =>
      'Windows: nome do programa sem .exe, por exemplo chrome';

  @override
  String get manualProfilesS3Linux =>
      'Linux: WM_CLASS da janela no X11, por exemplo google-chrome. No Wayland o WhisPaste não consegue detectar o app.';

  @override
  String get manualProfilesS4Heading => 'Bandeja e sobreposição';

  @override
  String get manualProfilesS4Body =>
      'O menu da bandeja tem um submenu Perfil: «Automático, por app» segue as regras, «Sem perfil» as desativa, e abaixo ficam os seus perfis. No overlay de gravação, o nome do perfil ativo aparece depois da hora e do idioma, por exemplo 0:07 · DE · Mail.';

  @override
  String get manualProfilesS5Heading => 'Deixar sem alteração';

  @override
  String get manualProfilesS5Body =>
      '«Deixar sem alteração» significa que o perfil não mexe nesse campo. Vale o valor que está definido agora nas configurações.';

  @override
  String get manualProfilesS6Heading => 'O que uma troca manual faz';

  @override
  String get manualProfilesS6Body =>
      'Se você escolher um perfil na bandeja ou pressionar o atalho dele, ele vale para todos os ditados seguintes. Se depois alterar um campo que o perfil define, como o modelo de fala, a marca ativo termina e as regras por app voltam a decidir. A escolha se mantém após reiniciar.';

  @override
  String get profileAppCapture => 'Capturar app';

  @override
  String profileAppCaptureCountdown(int seconds) {
    return 'Mude para o app de destino em $seconds s …';
  }

  @override
  String profileAppCaptured(Object identifier) {
    return '«$identifier» foi adicionado como app de destino.';
  }

  @override
  String get profileAppCaptureNone =>
      'Nenhum outro app está em primeiro plano. Mude para o app de destino antes da contagem terminar.';

  @override
  String get profileAppCaptureUnavailable =>
      'Esta sessão não consegue ler o app em primeiro plano (por exemplo Wayland). Digite o identificador manualmente.';

  @override
  String get waylandHotkeyPortalDescription => 'Ditado do WhisPaste';

  @override
  String get waylandHotkeyNoAppId =>
      'Sua área de trabalho não conseguiu identificar o WhisPaste e não ativou o atalho, por isso ele não funciona em outros apps.';

  @override
  String get waylandHotkeyUnavailable =>
      'Sua área de trabalho não permite que apps usem um atalho global, por isso o atalho não funciona em outros apps.';

  @override
  String get waylandHotkeyDeclined =>
      'O atalho não foi confirmado no diálogo da sua área de trabalho, por isso ele não funciona em outros apps.';

  @override
  String get waylandHotkeyFallback =>
      'Em vez disso, você pode criar um atalho de teclado nas configurações do sistema com este comando:';

  @override
  String waylandHotkeyBoundTrigger(String trigger) {
    return 'O sistema definiu $trigger para o WhisPaste. Você pode alterá-lo nas configurações de teclado do sistema.';
  }

  @override
  String get waylandHotkeyBoundNoTrigger =>
      'O atalho é definido pelo sistema, não pelo WhisPaste. Você pode alterá-lo nas configurações de teclado do sistema.';

  @override
  String get waylandHotkeyReconnect => 'Reconectar';

  @override
  String get waylandHotkeyCopyCommand => 'Copiar comando';

  @override
  String get waylandHotkeyCommandCopied => 'Copiado';

  @override
  String get waylandHotkeyOpenKeyboardSettings =>
      'Abrir configurações do teclado';

  @override
  String get sttEngineRestartHint =>
      'O reconhecimento de voz travou. Reinicie o WhisPaste: feche-o pelo menu da bandeja (Sair) e abra-o de novo.';

  @override
  String get shortPressHintMessage =>
      'Toque curto detectado. Para um teclado na tela ou toques rápidos, ative «Toque ou mantenha».';

  @override
  String get shortPressHintAction => 'Ativar «Toque ou mantenha»';

  @override
  String get manualA11yHeading => 'Teclado na tela e mobilidade reduzida';

  @override
  String get manualA11yB1 =>
      'Com um teclado na tela não é possível manter uma tecla pressionada: um clique a pressiona e solta imediatamente. Por isso a gravação para logo ao segurar. Use «Toque ou mantenha»: um toque curto inicia a gravação e o próximo a encerra.';

  @override
  String get manualA11yB2 =>
      'Recomendamos esta configuração para um teclado na tela ou se manter pressionado for difícil para você. Você a encontra em Configurações → Atalhos de teclado.';

  @override
  String get manualA11yB3 =>
      'O botão flutuante não se move mais quando você clica com a mão levemente trêmula. Ele só é arrastado quando você o move claramente.';

  @override
  String get settingsSttCustomEndpoint => 'Endpoint próprio';

  @override
  String get customEndpointUrlTitle => 'Endereço do servidor';

  @override
  String get customEndpointUrlSubtitle =>
      'Endereço base terminando em /v1, por ex. http://localhost:1234/v1 para o LM Studio. Serve também para Ollama, llama.cpp ou um provedor terceiro.';

  @override
  String get customEndpointUrlInvalid =>
      'Este endereço não é válido. Exemplo: http://localhost:1234/v1';

  @override
  String get customEndpointUrlCredentials =>
      'O endereço não pode conter dados de acesso, consulta (?) nem fragmento (#). Insira a chave no campo «Chave».';

  @override
  String get customEndpointUrlHttpRemote =>
      'Servidores na internet precisam de https. Com http, a chave e o conteúdo viajariam sem criptografia pela internet. http só é permitido para este dispositivo e a rede local.';

  @override
  String get customEndpointNoticeLocal => 'Fica neste dispositivo.';

  @override
  String get customEndpointNoticeLan => 'Fica na rede local.';

  @override
  String get customEndpointHttpLanWarning =>
      'Sem criptografia na rede local: outros dispositivos da rede podem ler o áudio ou o texto. Use https se o servidor suportar.';

  @override
  String get manualC12S2B4 =>
      'O caminho de transcrição é fixo em /audio/transcriptions, como na OpenAI; o Smart Mode usa /chat/completions. O servidor deve oferecer os dois sob o endereço terminado em /v1.';

  @override
  String customEndpointNoticeRemoteAudio(String host) {
    return 'O áudio é enviado para $host.';
  }

  @override
  String customEndpointNoticeRemoteText(String host) {
    return 'O texto transcrito é enviado para $host.';
  }

  @override
  String get customEndpointKeyTitle => 'Chave (opcional)';

  @override
  String get customEndpointKeySubtitle =>
      'Só se o seu servidor exigir. É guardada no cofre de chaves do sistema e nunca é exportada.';

  @override
  String get customEndpointSttModelTitle => 'Nome do modelo de voz';

  @override
  String get customEndpointSmartModelTitle => 'Nome do modelo de texto';

  @override
  String get customEndpointModelSubtitle =>
      'O nome do modelo como o servidor o conhece.';

  @override
  String get customEndpointTestTitle => 'Verificar a conexão';

  @override
  String get customEndpointTestSubtitle =>
      'Consulta apenas a lista de modelos. Nenhum áudio ou texto é enviado.';

  @override
  String get customEndpointTestAction => 'Testar conexão';

  @override
  String get customEndpointTestDisabledHint =>
      'Insira primeiro um endereço válido e um nome de modelo.';

  @override
  String get customEndpointProbeConnected =>
      'Conectado. O servidor responde e o modelo está disponível.';

  @override
  String get customEndpointProbeConnectedUnverified =>
      'Conectado. O servidor não lista modelos; o nome do modelo é verificado no primeiro ditado.';

  @override
  String customEndpointProbeModelMissing(String models) {
    return 'Modelo ausente: o servidor não conhece este modelo. Disponíveis: $models. Ajuste o nome do modelo ou carregue-o no servidor.';
  }

  @override
  String get customEndpointProbeUnreachable =>
      'Não é possível acessar. O servidor está em execução e o endereço e a porta estão corretos?';

  @override
  String get customEndpointProbeUnauthorized =>
      'O servidor recusa a chave ou exige uma. Verifique a chave.';

  @override
  String get customEndpointProbeBadFormat =>
      'Formato incorreto: o servidor não responde como um serviço compatível com a OpenAI. O endereço geralmente termina em /v1.';

  @override
  String get customEndpointProbeServerError =>
      'O servidor informa um erro. Verifique o registro dele e teste novamente.';

  @override
  String get smartModeConfigureEndpointAction => 'Configurar endpoint próprio';

  @override
  String get errorCustomEndpointUnreachable =>
      'O endpoint próprio não está acessível. O servidor está em execução e o endereço e a porta estão corretos? A gravação é mantida.';

  @override
  String get errorCustomEndpointNotConfigured =>
      'O endpoint próprio não está configurado. Insira o endereço e o nome do modelo nas configurações.';

  @override
  String get errorCustomModelMissing =>
      'O servidor não conhece o modelo selecionado. Verifique o nome do modelo nas configurações.';

  @override
  String get errorCustomBadResponse =>
      'O endpoint próprio responde em formato incorreto. Verifique o endereço; ele geralmente termina em /v1.';

  @override
  String get errorCustomEndpointUnauthorized =>
      'O endpoint próprio recusa a chave ou exige uma. Verifique a chave nas configurações.';

  @override
  String get errorCustomEndpointServerError =>
      'O endpoint próprio informa um erro do servidor. Verifique o registro dele e tente novamente.';

  @override
  String get manualC12S2B2 =>
      'Endpoint próprio: para um servidor na sua rede ou neste dispositivo (LM Studio, Ollama, llama.cpp), insira o endereço terminando em /v1, uma chave opcional e o nome do modelo. Com «Testar conexão» você verifica o acesso, a chave e o modelo.';

  @override
  String get manualC12S2B3 =>
      'Para onde vão o áudio e o texto: neste dispositivo (localhost, 127.0.0.1, ::1) tudo fica aqui. Na rede local (endereços privados como 192.168.x.x e nomes .local) fica na rede; outros dispositivos ali podem ler o http sem criptografia. Um servidor na internet recebe o áudio (transcrição) ou o texto (Smart Mode) e só é acessível por https.';

  @override
  String onboardingAccessibilityDragHint(String app) {
    return 'Arraste com o mouse o ícone do $app à direita para cima, até a lista.';
  }

  @override
  String get onboardingContactOpen => 'Abrir o formulário de contato';

  @override
  String get onboardingContactTitle => 'Escreva para nós';

  @override
  String get onboardingContactClose => 'Fechar';

  @override
  String get onboardingContactGreeting => 'Olá! Sobre o que é?';

  @override
  String get onboardingContactKindIdea => 'Ideia ou desejo';

  @override
  String get onboardingContactKindProblem => 'Relatar um problema';

  @override
  String get onboardingContactKindQuestion => 'Fazer uma pergunta';

  @override
  String get onboardingContactKindOther => 'Outro assunto';

  @override
  String get onboardingContactIdeaText =>
      'Reunimos ideias publicamente no nosso quadro de ideias. Lá você pode sugerir novas e votar nas existentes.';

  @override
  String get onboardingContactIdeaOpen => 'Abrir o quadro de ideias';

  @override
  String get onboardingContactBack => 'Mudar o assunto';

  @override
  String get onboardingContactNote =>
      'Respondemos por e-mail. Isto não é um chat ao vivo.';

  @override
  String onboardingContactSentReply(String email) {
    return 'Obrigado, sua mensagem foi enviada. Responderemos para $email.';
  }

  @override
  String get onboardingContactDone => 'Concluir';

  @override
  String get onboardingContactSpeakerYou => 'Você';

  @override
  String get onboardingContactEmailHint =>
      'Sem endereço não conseguimos responder.';

  @override
  String get onboardingContactProblemText =>
      'Descreva rapidamente o que não está funcionando.';

  @override
  String get onboardingContactQuestionText =>
      'Envie sua pergunta. Informe um e-mail se quiser uma resposta.';

  @override
  String get onboardingContactOtherText => 'Conte para nós do que se trata.';

  @override
  String get onboardingContactMessageLabel => 'Sua mensagem';

  @override
  String onboardingContactMessageTooShort(int count) {
    return 'Escreva pelo menos $count caracteres.';
  }

  @override
  String get onboardingContactEmailLabel => 'E-mail para a resposta (opcional)';

  @override
  String get onboardingContactEmailInvalid =>
      'Este e-mail não parece completo.';

  @override
  String get onboardingContactDiagnosticsLabel => 'Enviar dados técnicos';

  @override
  String get onboardingContactDiagnosticsExplanation =>
      'Apenas a etapa atual, a versão do app e o sistema operacional.';

  @override
  String get onboardingContactSend => 'Enviar mensagem';

  @override
  String get onboardingContactSent => 'Obrigado! Sua mensagem chegou.';

  @override
  String get onboardingContactErrorOffline =>
      'Não deu certo. Você está on-line? Seu texto foi mantido.';

  @override
  String get onboardingContactErrorRateLimited =>
      'Muitas mensagens agora. Tente novamente mais tarde.';

  @override
  String get onboardingContactErrorUnavailable =>
      'O envio não está disponível nesta versão. Escreva para kontakt@whispaste.de.';

  @override
  String get onboardingContactRetry => 'Tentar novamente';

  @override
  String get onboardingContactMailAddress => 'kontakt@whispaste.de';

  @override
  String onboardingContactSendSoon(String address) {
    return 'Em breve você poderá enviar direto pelo app. Até lá, fale conosco por e-mail em $address.';
  }

  @override
  String get onboardingContactWriteMail => 'Escrever um e-mail';

  @override
  String get onboardingAboutTitle => 'Deixe o WhisPaste com a sua cara.';

  @override
  String get onboardingAboutSubtitle => 'Tudo é opcional.';

  @override
  String get onboardingAboutNameLabel => 'Seu primeiro nome';

  @override
  String get onboardingAboutNameHint => 'Opcional';

  @override
  String get onboardingAboutRolesLabel => 'Para que você usa o WhisPaste?';

  @override
  String get onboardingAboutRolesHint => 'Pode escolher várias';

  @override
  String get onboardingAboutRoleWriting => 'Escrita';

  @override
  String get onboardingAboutRoleDev => 'Desenvolvimento';

  @override
  String get onboardingAboutRoleLegal => 'Jurídico';

  @override
  String get onboardingAboutRoleEducation => 'Educação';

  @override
  String get onboardingAboutRoleBusiness => 'Escritório e negócios';

  @override
  String get onboardingAboutOther => 'Outro';

  @override
  String get onboardingAboutFoundLabel => 'Como você nos encontrou?';

  @override
  String get onboardingAboutFoundSearch => 'Pesquisa';

  @override
  String get onboardingAboutFoundAi => 'ChatGPT e similares';

  @override
  String get onboardingAboutFoundFriend => 'Recomendação';

  @override
  String get onboardingAboutFoundStore => 'Loja de apps';

  @override
  String get onboardingAboutFoundSocial => 'Redes sociais';

  @override
  String get onboardingAboutFoundVideo => 'Vídeo';

  @override
  String get onboardingAboutFoundGithub => 'GitHub';

  @override
  String get onboardingAboutPreviewLabel => 'Pré-visualização';

  @override
  String onboardingAboutPreviewSample(String name) {
    return 'Aqui é $name. Fico com gosto com a organização da próxima reunião de equipa.';
  }

  @override
  String get onboardingStickerOpenSource => 'Código aberto';

  @override
  String get onboardingStickerLocal => 'Funciona localmente';

  @override
  String get onboardingAboutPreviewSampleAnonymous =>
      'Fico com gosto com a organização da próxima reunião de equipa.';

  @override
  String get onboardingPermissionsSceneSentence =>
      'as bebidas para a festa de verão já estão encomendadas, a lista está na cozinha.';

  @override
  String get onboardingPermissionsSceneGreeting => 'Olá a todos,';

  @override
  String get onboardingMicTitle => 'Testa o teu microfone.';

  @override
  String get onboardingMicModelStillLoading =>
      'O modelo de voz ainda está a ser descarregado em segundo plano. Continua; só tem de estar pronto para o teste.';

  @override
  String get onboardingMicQuiet =>
      'Quase não chega som. Fala um pouco mais alto ou mais perto do microfone.';

  @override
  String get onboardingMicNoDevice =>
      'Nenhum microfone encontrado. Liga um e continua sozinho.';

  @override
  String get onboardingMicDisconnected =>
      'O microfone foi desligado. Assim que voltar, continua sozinho.';

  @override
  String get onboardingMicChooseOther => 'Escolher outro microfone';

  @override
  String get onboardingMicBluetoothHint =>
      'Os auscultadores Bluetooth soam muitas vezes abafados ao ditar. O WhisPaste costuma perceber melhor um microfone integrado ou USB.';

  @override
  String get onboardingPrivacyReadyTitle => 'Pronto para ditar.';

  @override
  String get onboardingPrivacyAlmostReadyTitle => 'Quase pronto para ditar.';

  @override
  String get onboardingPrivacyModeLocal =>
      'Seu áudio e seu texto ficam neste dispositivo; o reconhecimento é local.';

  @override
  String onboardingPrivacyModeCloud(String provider) {
    return 'Seu áudio vai direto para $provider, nunca por servidores do WhisPaste.';
  }

  @override
  String onboardingPrivacyModeCustom(String host) {
    return 'Seu áudio vai direto para o seu servidor: $host.';
  }

  @override
  String get onboardingPrivacySettingsHint =>
      'Altere quando quiser em Configurações → Privacidade. Lá você também decide se o áudio das suas gravações é mantido.';

  @override
  String onboardingHotkeyCueHold(String shortcut) {
    return 'Agora segure $shortcut';
  }

  @override
  String onboardingHotkeyCuePress(String shortcut) {
    return 'Agora pressione $shortcut';
  }

  @override
  String onboardingHotkeyCueDoubleTap(String shortcut) {
    return 'Agora toque $shortcut duas vezes rápido';
  }

  @override
  String onboardingPracticeLonger(String shortcut) {
    return 'Vai falar por mais tempo? Toque $shortcut duas vezes rápido e dite sem as mãos. Um toque encerra.';
  }

  @override
  String get onboardingPracticeReceivedHandsFree =>
      'Chegou sem as mãos. Assim você dita com conforto também textos longos.';

  @override
  String get firstStepsTitle => 'Primeiros passos';

  @override
  String firstStepsProgress(int done, int total) {
    return '$done de $total concluídos';
  }

  @override
  String get firstStepsItemPasteTitle => 'Ditar uma vez noutra app';

  @override
  String get firstStepsItemPasteAction => 'Ir para o atalho';

  @override
  String get firstStepsItemCopyTitle => 'Encontre uma gravação e copie-a';

  @override
  String get firstStepsItemCopyAction => 'Ir para as gravações';

  @override
  String get firstStepsItemPersonalizeTitle =>
      'Adicionar uma palavra ao dicionário';

  @override
  String get firstStepsItemPersonalizeAction => 'Ir para o dicionário';

  @override
  String get firstStepsItemNoteTitle => 'Dite uma nota';

  @override
  String get firstStepsItemNoteAction => 'Ir para as notas';

  @override
  String get firstStepsComplete =>
      'Pronto. Já é possível falar e escrever à vontade.';

  @override
  String get firstStepsRestoreTitle => 'Primeiros passos';

  @override
  String get firstStepsRestoreSubtitle =>
      'Mostrar novamente o cartão com os primeiros passos na tela inicial.';

  @override
  String get firstStepsRestoreAction => 'Mostrar novamente';

  @override
  String get navOverview => 'Visão geral';

  @override
  String get overviewBadgeHint => 'Novidades nesta versão';

  @override
  String overviewGreetingNamed(String name) {
    return 'Olá, $name! Dite em qualquer lugar com';
  }

  @override
  String get overviewGreetingAnonymous => 'Dite em qualquer lugar com';

  @override
  String get overviewHotkeyModeHold => 'manter';

  @override
  String get overviewHotkeyModeToggle => 'premir';

  @override
  String get overviewStatusModelMissing =>
      'Nenhum modelo de voz instalado. Ditar funciona assim que um estiver carregado.';

  @override
  String get overviewStatusModelDownloading =>
      'O modelo de voz está sendo baixado. O ditado funciona quando terminar.';

  @override
  String get overviewStatusModelFailed =>
      'Não foi possível baixar o modelo de voz. O ditado funciona depois que ele for baixado.';

  @override
  String get overviewStatusMicDenied =>
      'O WhisPaste não tem permissão para usar o microfone. O ditado funciona depois que você permitir.';

  @override
  String get overviewStatusHotkeyUnbound =>
      'O atalho de ditado ainda não está ativo.';

  @override
  String get overviewStatusModelAction => 'Configurar modelo de voz';

  @override
  String get overviewStatusModelProgressAction => 'Ver progresso';

  @override
  String get overviewStatusMicAction => 'Permitir microfone';

  @override
  String get overviewStatusHotkeyAction => 'Configurar atalho';

  @override
  String get overviewCustomize => 'Personalizar visão geral';

  @override
  String get overviewCustomizeTips => 'Dicas';

  @override
  String get overviewCustomizeFirstSteps =>
      'Mostrar primeiros passos novamente';

  @override
  String get overviewStatusMicSettingsAction =>
      'Abrir configurações do sistema';

  @override
  String get overviewStatusModelRetryAction => 'Tentar de novo';

  @override
  String get overviewStatusRecoveryAction => 'Recuperar gravação';

  @override
  String overviewStatusRecovery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gravações interrompidas ainda podem ser recuperadas.',
      one: 'Uma gravação interrompida ainda pode ser recuperada.',
    );
    return '$_temp0';
  }

  @override
  String get overviewFiguresTitle => 'Os seus números';

  @override
  String get overviewFiguresWords => 'Palavras';

  @override
  String get overviewFiguresWordsPerMinute => 'Palavras por minuto';

  @override
  String get overviewFiguresTooFewData => 'Ainda não há dados suficientes';

  @override
  String get overviewFiguresTimeSaved => 'Tempo economizado';

  @override
  String get overviewPeriodWeek => 'Esta semana';

  @override
  String get overviewPeriodAll => 'Total';

  @override
  String get overviewStreakLabel => 'Dias com ditado esta semana';

  @override
  String get overviewStreakLabelAll => 'Dias com ditado no total';

  @override
  String get overviewRecentTitle => 'Últimas gravações';

  @override
  String get overviewRecentAll => 'Todas as gravações';

  @override
  String get overviewRecentEmptyBefore => 'Ainda não há gravações – pressione';

  @override
  String get overviewRecentEmptyAfter => 'em qualquer aplicativo.';

  @override
  String get overviewRecentEmptyPutAway =>
      'Todas as gravações estão arquivadas ou na lixeira.';

  @override
  String get overviewRecentEmptyNotSaved =>
      'As gravações não são salvas. O ditado continua funcionando.';

  @override
  String get overviewRecentEmptyNotSavedAction => 'Ativar salvamento';

  @override
  String get overviewRecentLocalNote =>
      'Suas gravações ficam neste dispositivo.';

  @override
  String overviewMilestoneTitle(int count) {
    return '$count ditados com o WhisPaste';
  }

  @override
  String get overviewMilestoneBody =>
      'É texto que você não precisou digitar. Obrigado por escrever com o WhisPaste.';

  @override
  String get overviewMilestoneClose => 'Fechar';

  @override
  String get overviewRateTitle => 'Recomendar o WhisPaste';

  @override
  String get overviewRateBody =>
      'Uma avaliação ou um link compartilhado ajuda outras pessoas a encontrar o WhisPaste.';

  @override
  String get overviewRateStore => 'Avaliar na loja';

  @override
  String get overviewRateGitHub => 'Dar uma estrela no GitHub';

  @override
  String get overviewShareCopyLink => 'Copiar link';

  @override
  String get overviewShareCopied => 'Link do site copiado';

  @override
  String get overviewRateLater => 'Mais tarde';

  @override
  String get overviewRateNever => 'Não perguntar novamente';

  @override
  String get overviewRecentCopy => 'Copiar';

  @override
  String get overviewRecentOpen => 'Abrir nas gravações';

  @override
  String get overviewTipHeading => 'Descobrir';

  @override
  String get overviewTipTry => 'Experimentar';

  @override
  String get overviewTipHide => 'Ocultar esta dica';

  @override
  String get overviewTipsOff => 'Sem mais dicas';

  @override
  String get overviewTipSmartBody =>
      'Limpe, encurte ou traduza o texto antes de colá-lo, por padrão no seu dispositivo.';

  @override
  String get overviewTipVocabularyBody =>
      'Adicione uma vez os nomes e termos técnicos escritos errado.';

  @override
  String get overviewTipSnippetsBody =>
      'Salve textos recorrentes e insira-os com um atalho ou com a voz.';

  @override
  String get overviewTipNotesBody =>
      'Registre ideias sem depender de uma gravação.';

  @override
  String get overviewTipOverlayTitle => 'Personalize o overlay';

  @override
  String get overviewTipOverlayBody =>
      'Ajuste o tamanho, a forma e a cor do overlay de ditado.';

  @override
  String get overviewTipRecordingModeTitle => 'Modo de gravação';

  @override
  String get overviewTipRecordingModeBody =>
      'Mantenha pressionado para ditar ou pressione uma vez para iniciar e parar.';

  @override
  String get overviewWhatsNewTitle => 'Novidades nesta versão';

  @override
  String get overviewWhatsNewClose => 'Entendi';

  @override
  String get overviewStorageTitle => 'Armazenamento do WhisPaste';

  @override
  String get overviewStorageModels => 'Modelos de voz';

  @override
  String get overviewStorageRecordings => 'Gravações';

  @override
  String get overviewStorageCache => 'Cache';

  @override
  String get overviewStorageCleanup => 'Limpar…';

  @override
  String get overviewStorageCleanupTitle => 'Esvaziar o cache?';

  @override
  String overviewStorageCleanupMessage(String size) {
    return '$size serão apagados. Os modelos de voz e as gravações não são alterados; o cache é recriado quando necessário.';
  }

  @override
  String get overviewStorageCleanupConfirm => 'Esvaziar';

  @override
  String get overviewStorageCleanupFailed =>
      'Não foi possível esvaziar o cache. Verifique as permissões da pasta.';

  @override
  String get overviewStorageUnreadable => 'não legível';

  @override
  String get overviewStorageManage => 'Alterar a retenção';

  @override
  String get overviewLastDictationTitle => 'Último ditado';

  @override
  String get overviewCommunityTitle => 'Participe';

  @override
  String get overviewCommunityHide => 'Ocultar esta seção';

  @override
  String get overviewCommunityProject => 'Para o WhisPaste';

  @override
  String get overviewCommunityDeveloper => 'Do desenvolvedor';

  @override
  String get overviewCommunityGithub => 'WhisPaste no GitHub';

  @override
  String get overviewCommunityYoutube => 'WhisPaste no YouTube';

  @override
  String get overviewCommunitySupport => 'Apoiar o WhisPaste';

  @override
  String get overviewCommunityRateStore => 'Avaliar na loja';

  @override
  String get overviewCommunityVotepit => 'Sugerir ideias e votar';

  @override
  String get overviewCommunityGithubBenefit =>
      'Uma estrela ajuda outras pessoas a encontrar o WhisPaste. Aqui também dá para relatar erros.';

  @override
  String get overviewCommunityGithubAction => 'Dar uma estrela no GitHub';

  @override
  String get overviewCommunityYoutubeBenefit =>
      'Dicas e novidades sobre o WhisPaste.';

  @override
  String get overviewCommunityYoutubeAction => 'Inscrever-se no YouTube';

  @override
  String get overviewCommunityStarsLabel => 'estrelas';

  @override
  String get overviewCommunitySubscribersLabel => 'inscritos';

  @override
  String get overviewCommunityProfileGithub => 'Perfil no GitHub';

  @override
  String get overviewCommunityOpensBrowser => 'abre no navegador';

  @override
  String get overviewCommunityOpensStore => 'abre a loja';

  @override
  String get overviewCommunityMenu => 'Participe';

  @override
  String get overviewLastDictationNone =>
      'Ainda não há nenhum ditado neste dispositivo.';

  @override
  String get overviewLastDictationCpu => 'Processador';

  @override
  String get overviewLastDictationGpu => 'Placa gráfica';

  @override
  String get overviewLastDictationCloud => 'Serviço na nuvem';

  @override
  String overviewLastDictationDuration(String seconds) {
    return 'Processamento $seconds s';
  }

  @override
  String get overviewLastDictationFallback =>
      'Recuo: a placa gráfica estava prevista, mas o processador tratou do ditado.';
}
