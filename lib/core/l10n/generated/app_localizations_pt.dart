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
  String get navHistory => 'Histórico';

  @override
  String get navNotes => 'Notas';

  @override
  String get navSettings => 'Configurações';

  @override
  String get navReplacements => 'Substituições';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navAnalytics => 'Estatísticas';

  @override
  String get navAbout => 'Sobre';

  @override
  String get navFeedback => 'Feedback';

  @override
  String get pageHistoryTitle => 'Histórico';

  @override
  String get pageSettingsTitle => 'Configurações';

  @override
  String get pageReplacementsTitle => 'Substituições';

  @override
  String get pageAnalyticsTitle => 'Estatísticas';

  @override
  String get pageAboutTitle => 'Sobre';

  @override
  String get pageFeedbackTitle => 'Feedback';

  @override
  String get historyEmpty => 'Nenhuma gravação ainda';

  @override
  String get historyEmptyHint =>
      'Pressione o botão de gravar ou use o atalho para começar a gravar.';

  @override
  String get historyPrivacyGateTitle => 'Histórico oculto';

  @override
  String get historyPrivacyGateHint =>
      'Suas transcrições anteriores ficam ocultas até você decidir mostrá-las.';

  @override
  String get historyPrivacyGateShow => 'Mostrar histórico';

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
  String get historyCopyAsMarkdown => 'Copiar como Markdown';

  @override
  String get historyDetail => 'Detalhes';

  @override
  String get historyTags => 'Tags';

  @override
  String get historyDuration => 'Duração';

  @override
  String get historyModel => 'Modelo';

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
  String get historyEditing => 'Editando';

  @override
  String get historySearchTranscriptions => 'Pesquisar transcrições…';

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
    return 'Nenhuma transcrição corresponde a \"$query\".\nTente outro termo de pesquisa.';
  }

  @override
  String get historyTrashEmpty => 'A lixeira está vazia';

  @override
  String get historyTrashEmptyHint =>
      'Transcrições excluídas aparecerão aqui.\nOs itens são removidos definitivamente após 30 dias.';

  @override
  String get historyEmptyTrash => 'Esvaziar lixeira';

  @override
  String get historyEmptyTrashConfirm => 'Esvaziar lixeira?';

  @override
  String get historyEmptyTrashConfirmMessage =>
      'Todos os itens da lixeira serão excluídos definitivamente. Esta ação não pode ser desfeita.';

  @override
  String historyTrashEmptied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lixeira esvaziada — $count entradas excluídas',
      one: 'Lixeira esvaziada — 1 entrada excluída',
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
      'Indicador de CPU/GPU na barra de status';

  @override
  String get settingsShowBackendUtilizationSubtitle =>
      'Mostra se a transcrição está realmente rodando na CPU ou na GPU, além do uso';

  @override
  String get settingsAudio => 'Áudio';

  @override
  String get settingsAudioSubtitle => 'Microfone e gravação';

  @override
  String get settingsMicrophone => 'Microfone';

  @override
  String get settingsGain => 'Volume do microfone';

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
  String get settingsSpeechRecognition => 'Reconhecimento de fala';

  @override
  String get settingsSpeechRecognitionSubtitle =>
      'Qualidade e serviço do reconhecimento de voz';

  @override
  String get settingsService => 'Serviço';

  @override
  String get settingsQuality => 'Qualidade';

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
  String get settingsAfterTranscriptionActionLabel => 'Ação';

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
  String get pasteFailureGeneric =>
      'Falha no Auto-Paste. A transcrição está na área de transferência; cole manualmente com ⌘V / Ctrl+V.';

  @override
  String get pasteFailureOpenSettings => 'Abrir configurações';

  @override
  String get pasteNotificationNoTargetTitle => 'WhisPaste: Auto-Paste ignorado';

  @override
  String get pasteNotificationNoTargetBody =>
      'Nenhum app de destino detectado. Foque primeiro o app de destino e depois inicie a gravação. O texto está na área de transferência.';

  @override
  String get pasteNotificationNoTargetTray =>
      'Auto-Paste: app de destino ausente';

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
  String get pasteNotificationFailedBody =>
      'O sistema rejeitou a colagem. O texto está na área de transferência — cole manualmente com ⌘V / Ctrl+V.';

  @override
  String get pasteNotificationFailedTray => 'Falha no Auto-Paste';

  @override
  String get pasteCapabilityCheckTitle => 'Um momento…';

  @override
  String get pasteCapabilityReady => 'Tudo pronto';

  @override
  String get pasteCapabilityReadySubtitle =>
      'Seu ditado aparece bem no cursor.';

  @override
  String get pasteCapabilityPermissionMissing => 'Ainda não permitido';

  @override
  String get pasteCapabilityUnsupported =>
      'O Auto-Paste não está disponível nesta plataforma';

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
  String get pasteManualGrantAlertTitle => 'O reinício não resolveu';

  @override
  String get pasteManualGrantAlertBody =>
      'O WhisPaste já foi reiniciado, mas a permissão do Auto-Paste ainda não está valendo. Verifique em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade se o WhisPaste está ativado e, se necessário, reative a chave.';

  @override
  String get pasteManualGrantAlertConfirm => 'Abrir Ajustes do Sistema';

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
      'O WhisPaste insere seu ditado bem no cursor. Para isso, o macOS exige um interruptor que só você pode ativar: Ajustes do Sistema → Privacidade e Segurança → Acessibilidade. Confirme para abrir exatamente essa página — o WhisPaste detecta sua autorização automaticamente e, se preciso, reinicia sozinho depois.';

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
  String get onboardingPasteTitle =>
      'Assim seu texto aparece onde você está digitando';

  @override
  String get onboardingPasteSubtitle =>
      'Em instantes, o macOS vai perguntar se o WhisPaste pode fazer isso. Diga sim, pronto.';

  @override
  String get onboardingPasteSubtitleWin =>
      'No Windows não é preciso permissão — apenas escolha se o WhisPaste deve inserir o texto ditado para você.';

  @override
  String get onboardingPasteChipReady => 'Auto-Paste pronto';

  @override
  String get onboardingPasteChipPending => 'Acesso do Auto-Paste pendente';

  @override
  String get onboardingPasteChipAction => 'Auto-Paste: ação necessária';

  @override
  String get onboardingPasteGrantCta => 'Permitir Auto-Paste';

  @override
  String get onboardingPasteSkip =>
      'Só copiar por enquanto, sem inserção automática';

  @override
  String get onboardingPasteWhyMac =>
      'Sem permissão, seu texto é copiado para a área de transferência. Depois, você cola manualmente com ⌘V.';

  @override
  String get onboardingPasteWhyWin =>
      'O Auto-Paste pressiona Ctrl+V por você após cada ditado, então o texto aparece exatamente onde você está digitando. Testado e funcionando neste computador — ative abaixo.';

  @override
  String get onboardingPasteWhyWinUipi =>
      'Em alguns apps com proteção UIPI/UAC, o Auto-Paste não funciona. O texto fica na área de transferência e você precisará colá-lo com Ctrl+V.';

  @override
  String get onboardingPasteWinOnTitle => 'O Auto-Paste está ativado';

  @override
  String get onboardingPasteWinOnDetail =>
      'Após cada ditado, o WhisPaste pressiona Ctrl+V por você — o texto aparece direto no cursor. Uma cópia também fica na área de transferência.';

  @override
  String get onboardingPasteWinEnableCta => 'Ativar Auto-Paste';

  @override
  String get onboardingPasteWinAdminCaveat =>
      'Apps executados como administrador não aceitam teclas simuladas — nesses casos, seu texto fica na área de transferência, pronto para colar com Ctrl+V.';

  @override
  String get onboardingPasteWaitingForGrantTitle =>
      'Marque a caixa ao lado de WhisPaste';

  @override
  String get onboardingPasteWaitingForGrantHint =>
      'Os Ajustes do Sistema estão abertos. Procure o WhisPaste na lista e ative-o.\n\nNão está na lista? Arraste o ícone do app para lá ou clique em “+”.';

  @override
  String get onboardingPasteTestTitle => 'Teste o Auto-Paste';

  @override
  String get onboardingPasteTestSubtitle =>
      'Clique no botão. O texto de demonstração deve aparecer no campo abaixo.';

  @override
  String get onboardingPasteDemoText => 'WhisPaste digita por você.';

  @override
  String get onboardingPasteTestSuccess =>
      'O Auto-Paste funciona! Clique em Avançar para continuar.';

  @override
  String get onboardingPasteTestNoFrontmost =>
      'Nenhum campo de entrada detectado. Clique no campo abaixo e tente novamente.';

  @override
  String get onboardingPasteTestFailure =>
      'O teste falhou. Tente reiniciar o app ou continue sem testar.';

  @override
  String get onboardingPasteTestSkip => 'Continuar sem testar';

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
  String get settingsOverlayModeFloating => 'Janela flutuante (sempre visível)';

  @override
  String get settingsOverlayModeOff => 'Desativado';

  @override
  String get settingsOverlayStartPosition => 'Posição do overlay';

  @override
  String get settingsOverlayStartPositionSubtitle =>
      'Onde o overlay flutuante aparece quando a gravação começa';

  @override
  String get settingsOverlayStartTopCenter => 'Centro superior';

  @override
  String get settingsOverlayStartBottomCenter => 'Centro inferior';

  @override
  String get settingsOverlayStartLastPosition => 'Lembrar última posição';

  @override
  String get settingsShowFloatingButton => 'Botão flutuante de gravação';

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
    return '~$count / $budget tokens';
  }

  @override
  String settingsCustomVocabularyBudgetWarning(int budget) {
    return 'Entradas longas podem ser encurtadas automaticamente — só cerca dos primeiros $budget tokens são usados.';
  }

  @override
  String get settingsPunctuationPriming => 'Incentivo à pontuação';

  @override
  String get settingsPunctuationPrimingSubtitle =>
      'Leva o Whisper a gerar texto com pontuação quando nenhum vocabulário personalizado está definido. Não afeta a velocidade.';

  @override
  String get settingsVadEnabled => 'Remover silêncio no final';

  @override
  String get settingsVadEnabledSubtitle =>
      'Remove silêncio ou ruído longos no fim da gravação antes de o Whisper decodificá-la, para que ele não invente uma frase final (por exemplo, alucinações do tipo “Obrigado por assistir”). Custo desprezível; desative se preferir a saída bruta do Whisper.';

  @override
  String get settingsStripPunctuation => 'Remover pontuação';

  @override
  String get settingsStripPunctuationSubtitle =>
      'Remove pontos, vírgulas e outros sinais de pontuação de cada transcrição antes de ela ser salva ou colada. Funciona igual para todos os motores e provedores, não só para o Whisper.';

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
      'Transforma comandos falados como «novo parágrafo» e «nova linha» em quebras de linha reais. Vale para o idioma da transcrição ou, com detecção automática, para todos os idiomas suportados.';

  @override
  String get settingsAppLanguage => 'Idioma do app';

  @override
  String get settingsSttModels => 'Modelos de reconhecimento de voz';

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
  String get settingsFactoryReset => 'Redefinição de fábrica';

  @override
  String get settingsFactoryResetTitle => 'Redefinição de fábrica';

  @override
  String get settingsFactoryResetMessage =>
      'Isso apaga PERMANENTEMENTE TODOS os dados: histórico de gravações, tags, substituições, modelos baixados, logs e configurações. O app voltará ao estado inicial.\n\nIsso não pode ser desfeito.';

  @override
  String get settingsFactoryResetConfirm => 'Apagar tudo';

  @override
  String get settingsFactoryResetSuccess => 'O app foi totalmente redefinido';

  @override
  String get settingsFactoryResetProgressTitle => 'Redefinindo o WhisPaste';

  @override
  String get settingsFactoryResetPhaseStoppingSubprocess =>
      'Parando o serviço de voz…';

  @override
  String get settingsFactoryResetPhaseDeletingModels =>
      'Apagando modelos de voz…';

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
  String get settingsFactoryResetFailedMessage =>
      'A redefinição de fábrica está incompleta. Reinicie o app.';

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
    return 'Isso substitui suas configurações atuais — incluindo interface, configuração de reconhecimento de voz, comportamento, substituições de texto e snippets — pelo conteúdo de $path. Suas chaves de API não são alteradas.';
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
      'O Groq STT foi removido. O provedor voltou para o modo no dispositivo.';

  @override
  String get tccResetAfterUpdateToast =>
      'O macOS redefiniu sua permissão de Auto-Paste durante a atualização.';

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
  String get actionCancel => 'Cancelar';

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
  String get onboardingWelcome => 'Fale uma vez. Cole em qualquer lugar.';

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
  String get analyticsTimeSaved => 'Tempo economizado';

  @override
  String get analyticsAvgLatency => 'Velocidade média';

  @override
  String get analyticsRecordingActivity => 'Atividade de gravação';

  @override
  String get analyticsLast7Days => 'Últimos 7 dias';

  @override
  String get analyticsModelUsage => 'Uso de modelos';

  @override
  String get analyticsDurationDistribution => 'Distribuição de duração';

  @override
  String get analyticsCostSavings => 'Custos e economia';

  @override
  String get analyticsLocalSavings => 'Economia local';

  @override
  String get analyticsCloudCost => 'Custo na nuvem';

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
  String analyticsDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
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
  String get replacementsRemoveTrigger => 'Remover frase-gatilho';

  @override
  String get replacementsReplacementLabel => 'Texto de substituição';

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
      'Ao gravar uma nota no Histórico, diga “correct: …” (ou “korrektur: …”) seguido do texto corrigido para sobrescrevê-la. Corrija a mesma coisa duas vezes e o WhisPaste oferece isso aqui como substituição automática.';

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
      'Quão parecida com um gatilho uma frase ditada precisa soar para ainda contar como correspondência. A rigorosa só pega formulações quase idênticas, então quase nada é substituído por acidente, mas um gatilho mal pronunciado pode passar sem correspondência. A padrão é um equilíbrio para o ditado do dia a dia. A tolerante também pega pronúncias ou formulações bem diferentes, com maior risco de corresponder a algo que você não queria substituir.';

  @override
  String replacementsFuzzyTooShortWarning(int minLength) {
    return 'Frases-gatilho com menos de $minLength caracteres não podem usar correspondência semelhante — gerariam acertos falsos demais.';
  }

  @override
  String get snippetsSearch => 'Pesquisar snippets…';

  @override
  String get snippetsSearchFieldLabel => 'Pesquisar snippets';

  @override
  String get snippetsAdd => 'Adicionar';

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
      'Abra o seletor de snippets durante o ditado para inserir este texto.';

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
      'Nem todos os campos aparecem no modelo ainda — o texto ditado para eles não seria usado.';

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
  String get aboutTagline => 'Voz para texto, na hora.';

  @override
  String get aboutWhatsNew => 'Novidades';

  @override
  String get aboutGitHub => 'GitHub';

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
      'Reconhecimento de voz local otimizado para velocidade em CPUs comuns (~25 idiomas).';

  @override
  String get aboutPrivacyFirst => 'Privacidade em primeiro lugar';

  @override
  String get aboutPrivacyFirstDesc =>
      'Reconhecimento de voz local por padrão: sua voz nunca sai do seu dispositivo, a menos que você escolha um provedor na nuvem.';

  @override
  String get aboutPrivacy => 'Privacidade e dados';

  @override
  String get aboutPrivacyLocal =>
      'Todas as transcrições e o histórico são armazenados localmente no seu dispositivo, nunca em servidores externos.';

  @override
  String get aboutPrivacyCloud =>
      'Provedores na nuvem (OpenAI, Deepgram) só recebem áudio quando você os usa ativamente. Valem as políticas de privacidade deles.';

  @override
  String get aboutPrivacyNoTracking =>
      'As estatísticas de uso são anônimas e estão em conformidade com o GDPR (servidor na UE), e podem ser desativadas em Configurações → Privacidade. Não há contas de usuário. As verificações de atualização consultam o GitHub (apenas versão e IP).';

  @override
  String get aboutKeyboardShortcuts => 'Atalhos de teclado';

  @override
  String get aboutShortcutRecord => 'Iniciar / parar gravação';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutWebsite => 'Site';

  @override
  String get aboutGitHubRepo => 'Repositório no GitHub';

  @override
  String get aboutFollowOnX => 'Siga no X';

  @override
  String get aboutMitLicense => 'Licença MIT';

  @override
  String get aboutViewOnGitHub => 'Ver no GitHub';

  @override
  String get aboutPrivacyPolicy => 'Política de privacidade';

  @override
  String get aboutSystemInfo => 'Informações do sistema';

  @override
  String get aboutSystemInfoDesc =>
      'Copie um resumo compacto de diagnóstico para relatórios de bugs.';

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
  String get feedbackCategoryBug => 'Relatar bug';

  @override
  String get feedbackCategoryFeature => 'Ideia de recurso';

  @override
  String get feedbackCategoryGeneral => 'Geral';

  @override
  String get feedbackCategoryAiQuality => 'Qualidade da IA';

  @override
  String get feedbackRatingLabel =>
      'Como você está se sentindo com o WhisPaste?';

  @override
  String get feedbackCommentsLabel => 'Conte mais';

  @override
  String get feedbackPlaceholderBug =>
      'Descreva o que aconteceu e o que você esperava…';

  @override
  String get feedbackPlaceholderFeature =>
      'O que você gostaria de ver no WhisPaste?';

  @override
  String get feedbackPlaceholderAi => 'Como foi a qualidade da transcrição?';

  @override
  String get feedbackPlaceholderGeneral => 'Compartilhe suas ideias…';

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
  String get sttStatusStandby => 'Em espera';

  @override
  String get sttStatusStarting => 'Iniciando…';

  @override
  String get sttStatusReady => 'Pronto';

  @override
  String get sttStatusError => 'Erro';

  @override
  String get statusBarSttTooltip => 'Serviço de voz e status atual';

  @override
  String statusBarSttBackendTooltip(String backend) {
    return 'Mecanismo de transcrição: $backend';
  }

  @override
  String get statusBarBackendGpuUtilizationUnavailable =>
      'A utilização real da GPU não pode ser medida em todas as plataformas sem privilégios elevados; a porcentagem exibida reflete a atividade de CPU deste processo.';

  @override
  String get statusBarRecording => 'Gravando…';

  @override
  String get statusBarTranscribing => 'Transcrevendo…';

  @override
  String get statusBarRefining => 'Refinando…';

  @override
  String get statusBarDone => 'Concluído';

  @override
  String get statusBarHotkeyTooltip => 'Atalho global: clique para configurar';

  @override
  String get statusBarAutoPasteOffHint =>
      'Auto-Paste desativado; ative em Configurações';

  @override
  String get statusBarAutoPasteOffHintTooltip =>
      'O Auto-Paste está desativado no momento. Clique para abrir as Configurações.';

  @override
  String get statusBarAutoPasteOffHintDismiss => 'Dispensar';

  @override
  String statusBarAutomationApiChipLabel(int port) {
    return 'API: $port';
  }

  @override
  String get statusBarAutomationApiChipLabelError => 'API: erro';

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
  String get modelServerReady => 'Serviço de voz pronto';

  @override
  String get modelServerMissing => 'Serviço de voz não instalado';

  @override
  String get modelServerWhisper => 'Serviço de voz local';

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
  String get modelDownloadingEngine => 'Preparando o serviço de voz…';

  @override
  String get modelVerifying => 'Verificando…';

  @override
  String get modelExtracting => 'Extraindo…';

  @override
  String get modelDeleteConfirm => 'Excluir este modelo?';

  @override
  String get modelDeleteConfirmMessage =>
      'O arquivo do modelo será removido permanentemente. Você pode baixá-lo novamente a qualquer momento.';

  @override
  String get qualityTierCompactLabel => 'Rápido e compacto';

  @override
  String get qualityTierCompactDesc =>
      'Resultados rápidos, download pequeno. Ótimo para notas curtas e mensagens rápidas.';

  @override
  String get qualityTierBalancedLabel => 'Equilibrado';

  @override
  String get qualityTierBalancedDesc =>
      'Preciso e confiável para gravações do dia a dia. Funciona na maioria dos dispositivos.';

  @override
  String get qualityTierPremiumLabel => 'Melhor qualidade';

  @override
  String get qualityTierPremiumDesc =>
      'Máxima precisão para gravações longas e conteúdo complexo. Requer uma GPU potente.';

  @override
  String get qualityTierRecommended => 'Recomendado para o seu dispositivo';

  @override
  String qualityTierDownloadSize(String size) {
    return 'Download de $size';
  }

  @override
  String get qualityTierDownloadAndContinue => 'Baixar modelo';

  @override
  String get qualityTierChooseDifferent => 'Escolher outro nível de qualidade';

  @override
  String get qualityTierActive => 'Ativo';

  @override
  String qualityTierInfoSlow(String ratio) {
    return 'Melhor qualidade, leva cerca de ${ratio}x mais tempo para processar';
  }

  @override
  String qualityTierInfoSlowerThanCompact(String ratio) {
    return 'Melhor qualidade, cerca de ${ratio}x mais lento que o Compacto';
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
  String get qualityTierActionOverride => 'Usar mesmo assim';

  @override
  String get qualityTierActionOverrideHint =>
      'Usar este nível de qualidade apesar do aviso';

  @override
  String qualityTierModelTooltip(String modelName, String size) {
    return 'Whisper $modelName · $size';
  }

  @override
  String analyticsModelDisplayName(String tierLabel, String modelLabel) {
    return '$tierLabel (Whisper $modelLabel)';
  }

  @override
  String get settingsQualityBasic => 'Básico';

  @override
  String get settingsQualityBalanced => 'Equilibrado';

  @override
  String get settingsQualityHigh => 'Alta qualidade';

  @override
  String get settingsQualityBest => 'Melhor qualidade';

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
      'Configurações avançadas do modelo';

  @override
  String get infoEngineDownloading =>
      'O serviço de voz está sendo preparado. Aguarde um instante.';

  @override
  String get infoModelMissing =>
      'Baixe primeiro um modelo de voz em Configurações.';

  @override
  String get infoPipelineBusy =>
      'O WhisPaste ainda está ocupado com a gravação anterior.';

  @override
  String get infoSnippetPickerEmpty =>
      'Palavra-gatilho reconhecida, mas você ainda não tem snippets — o texto foi inserido normalmente.';

  @override
  String get infoSnippetPickerEmptyAction => 'Abrir snippets';

  @override
  String get oomRecoveryTitle =>
      'Falha na gravação: problema de memória da GPU';

  @override
  String get oomRecoveryMessage =>
      'Sua GPU ficou sem memória. Escolha como prosseguir:';

  @override
  String get oomRecoveryTrySmaller => 'Tentar modelo menor';

  @override
  String oomRecoveryTrySmallerHint(String model) {
    return 'Mudar para $model e tentar a gravação novamente';
  }

  @override
  String get oomRecoverySwitchCloud => 'Mudar para a nuvem';

  @override
  String get oomRecoverySwitchCloudHint =>
      'Usar reconhecimento de voz na nuvem';

  @override
  String get oomRecoveryCancel => 'Cancelar';

  @override
  String get oomRecoveryPermanentTitle =>
      'Reconhecimento de voz local indisponível';

  @override
  String get oomRecoveryPermanentMessage =>
      'Todos os modelos locais falharam por limites de memória da GPU. Mude para o reconhecimento de voz na nuvem nas configurações.';

  @override
  String get oomRecoveryPermanentCloud => 'Abrir configurações';

  @override
  String oomRecoveryDowngrading(String model) {
    return 'Mudando para $model…';
  }

  @override
  String get oomRecoverySwitchingCloud =>
      'Mudando para o reconhecimento de voz na nuvem…';

  @override
  String oomRecoveryAttemptFailed(String model) {
    return 'O modelo $model também falhou. Tentando a próxima opção…';
  }

  @override
  String get infoSttCudaOomFallbackModel =>
      'Qualidade reduzida: sua GPU ficou sem memória. Mudado para um modelo mais leve.';

  @override
  String get infoSttCudaOomFallbackCpu =>
      'Sua GPU ficou sem memória. Mudado para o modo CPU para mais estabilidade.';

  @override
  String get errorSttServerConnectionLost =>
      'O serviço de voz parou inesperadamente. Tente novamente.';

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
  String get errorOnboardingNotCompleted =>
      'Conclua primeiro o assistente de configuração.';

  @override
  String get errorSttModelNotFound =>
      'Modelo de voz não encontrado. Baixe-o em Configurações.';

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
  String get errorSttServerFailed => 'O serviço de voz não conseguiu iniciar';

  @override
  String get errorSttModelIncompatibleRuntime =>
      'O modelo de voz é incompatível com o ambiente de execução instalado. Baixe o modelo de voz novamente nas configurações.';

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
      'O serviço de voz falhou na GPU e na CPU. Reinicie o app ou baixe o modelo novamente.';

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
      'O serviço de voz ainda está iniciando. Tente novamente em instantes.';

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
  String get modelDeleteInUse =>
      'O arquivo do modelo está em uso por outro programa e não pôde ser excluído. Feche-o e tente novamente.';

  @override
  String get statusSttLoading => 'Carregando modelo…';

  @override
  String get statusSttReady => 'Modelo pronto';

  @override
  String get historyDuplicate => 'Duplicar';

  @override
  String get historyDuplicated => 'Entrada duplicada';

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
  String get historySmartModeFailedModelMissing =>
      'Modelo do Smart Mode não baixado';

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
  String get tagManageEmpty => 'Nenhuma tag criada ainda.';

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
  String get settingsKeyboardShortcut => 'Atalho de teclado';

  @override
  String get settingsKeyboardShortcutSubtitle =>
      'Atalho global para iniciar e parar a gravação';

  @override
  String get settingsHotkeyEnabled => 'Ativar atalho global';

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
  String get settingsHotkeyRecorderModifierHint =>
      'Qualquer combinação com modificadores funciona, por ex. Alt+Espaço, Ctrl+Alt+V ou Ctrl+Alt+Shift+R';

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
  String get settingsQuickNoteHotkeyEnabled => 'Atalho de nota rápida';

  @override
  String get settingsQuickNoteHotkeyHint =>
      'O texto ditado é acrescentado à nota marcada como sua nota rápida. Você escolhe essa nota na área de Notas.';

  @override
  String get settingsQuickNoteCurrentHotkey => 'Combinação';

  @override
  String settingsQuickNoteHotkeyCollision(String action) {
    return 'Esta combinação já é usada para \"$action\". Escolha outra.';
  }

  @override
  String get settingsQuickNoteHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho de nota rápida está inativo no momento. Escolha outra combinação.';

  @override
  String get settingsHotkeyActionSnippetPicker => 'Seletor de snippets';

  @override
  String get settingsSnippetPickerHotkeyEnabled =>
      'Atalho do seletor de snippets';

  @override
  String get settingsSnippetPickerHotkeyHint =>
      'Abre o seletor de snippets imediatamente, sem gravação e sem a palavra-gatilho falada.';

  @override
  String get settingsSnippetPickerCurrentHotkey => 'Combinação';

  @override
  String settingsSnippetPickerHotkeyCollision(String action) {
    return 'Esta combinação já é usada para \"$action\". Escolha outra.';
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
  String get settingsErrorReporting => 'Relatórios de erros';

  @override
  String get settingsErrorReportingSubtitle =>
      'Envia relatórios de falhas e erros com um ID de dispositivo com hash, nunca seu áudio ou texto';

  @override
  String get settingsErrorReportingRestartHint =>
      'Entra em vigor após reiniciar o WhisPaste.';

  @override
  String get settingsAutoPasteDelay => 'Atraso do Auto-Paste';

  @override
  String get settingsAutoPasteDelaySubtitle =>
      'Tempo de espera antes de colar na janela ativa';

  @override
  String get settingsAutoPasteBlocklist => 'Lista de bloqueio do Auto-Paste';

  @override
  String get settingsAutoPasteBlocklistSubtitle =>
      'Identificadores de apps, separados por vírgula, nos quais o Auto-Paste fica desativado';

  @override
  String get settingsAutoPasteBlocklistPlaceholder =>
      'ex.: com.apple.Terminal, com.1password';

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
  String get onboardingBack => 'Voltar';

  @override
  String get onboardingPrivacyTitle => 'Ajude a tornar o WhisPaste melhor';

  @override
  String get onboardingPrivacyHint =>
      'Áudio e texto ficam no seu computador. Estatísticas anônimas de uso vão para um servidor próprio na UE, e os relatórios de falhas para o Sentry (região UE), em conformidade com o GDPR.';

  @override
  String get onboardingPrivacyToggle =>
      'Compartilhar estatísticas anônimas de uso';

  @override
  String get onboardingPrivacyToggleHint =>
      'Ativado por padrão, desative a qualquer momento';

  @override
  String get onboardingPrivacyCrashToggle =>
      'Enviar relatórios anônimos de falhas';

  @override
  String get onboardingPrivacyCrashToggleHint =>
      'Ajuda a corrigir bugs, ativado por padrão, desative a qualquer momento';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Etapa $current de $total';
  }

  @override
  String get onboardingAppearancePageTitle => 'Aparência';

  @override
  String get onboardingAppearancePageSubtitle =>
      'Como o app inicia e como o overlay de gravação aparece.';

  @override
  String get onboardingBeat1Title => 'Pressione o atalho, fale, pronto';

  @override
  String get onboardingBeat1Caption =>
      'A gravação começa na hora: suas palavras viram texto bem no cursor.';

  @override
  String get onboardingBeat2Title => 'Roda localmente, no seu hardware';

  @override
  String get onboardingBeat2Caption =>
      'A transcrição acontece no seu dispositivo, sem necessidade de internet.';

  @override
  String get onboardingBeat3Title => 'Em qualquer lugar onde você digita';

  @override
  String get onboardingBeat3Caption =>
      'Navegador, e-mail, editor: o WhisPaste funciona em todo o sistema.';

  @override
  String get onboardingMicChipReady => 'Microfone pronto';

  @override
  String get onboardingMicChipPending => 'Acesso ao microfone pendente';

  @override
  String get onboardingMicChipAction => 'Microfone: ação necessária';

  @override
  String get onboardingModelTitle => 'Configurar o reconhecimento de voz';

  @override
  String get onboardingModelSubtitle =>
      'Baixe o modelo de voz para gravar offline. Sua voz nunca sai do seu dispositivo.';

  @override
  String get onboardingModelRecommended => 'Recomendado';

  @override
  String get onboardingModelChangeLater =>
      'Você pode ajustar a qualidade depois nas Configurações';

  @override
  String get onboardingModelDownloading => 'Baixando…';

  @override
  String get onboardingModelReady => 'Modelo pronto';

  @override
  String get onboardingModelGpuCpuFallback =>
      'Aceleração otimizada por GPU indisponível, o app usará a CPU';

  @override
  String get onboardingModelEngineParakeetLabel => 'Rápido e europeu';

  @override
  String get onboardingModelEngineParakeetDesc =>
      'O jeito mais rápido de transformar fala em texto em cerca de 25 idiomas europeus, incluindo alemão. Roda bem em qualquer hardware, com ou sem GPU.';

  @override
  String get onboardingModelEngineWhisperLabel => 'Todos os 99 idiomas';

  @override
  String get onboardingModelEngineWhisperDesc =>
      'A maior cobertura de idiomas, além de vocabulário personalizado e ajuste de pontuação para nomes, siglas e termos técnicos.';

  @override
  String get onboardingModelEngineUnsupportedLanguage =>
      'Ainda não oferece suporte ao idioma escolhido';

  @override
  String get onboardingTestRecordingTitle => 'Experimente';

  @override
  String get onboardingTestRecordingSubtitle =>
      'Pressione o botão abaixo e diga uma frase. O texto aparece no campo de teste. Seu atalho também funciona.';

  @override
  String get onboardingTestRecordingHotkeyLabel => 'Seu atalho';

  @override
  String get onboardingTestRecordingStartCta => 'Iniciar gravação';

  @override
  String get onboardingTestRecordingStopCta => 'Parar gravação';

  @override
  String get onboardingTestRecordingCompletionHint =>
      'Faça uma gravação de teste para continuar.';

  @override
  String get onboardingTestRecordingMicBypassCta => 'Continuar sem microfone';

  @override
  String get onboardingTestRecordingMicBypassHint =>
      'Sem um microfone funcionando, o WhisPaste ainda não consegue iniciar uma gravação. Você pode resolver isso a qualquer momento pelo status do microfone nesta página ou nas Configurações.';

  @override
  String get onboardingTestRecordingPlaceholder =>
      'Seu texto falado aparecerá aqui …';

  @override
  String get onboardingTestRecordingInProgress =>
      'Gravando: é só começar a falar. Pressione de novo para parar.';

  @override
  String get onboardingTestRecordingDoneMessage =>
      'Pronto! É exatamente assim que funciona em qualquer app.';

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
  String get onboardingReadyTitle => 'Tudo pronto!';

  @override
  String get onboardingReadySubtitle => 'Veja como usar o WhisPaste';

  @override
  String get onboardingReadyStep1 =>
      'Pressione o atalho para iniciar a gravação';

  @override
  String get onboardingReadyStep2 =>
      'Pressione de novo para parar e transcrever';

  @override
  String get onboardingReadyStep3AutoPaste =>
      'O texto vai direto para o app ativo';

  @override
  String get onboardingReadyStep3CopyOnly =>
      'O texto está na área de transferência, pressione ⌘V / Ctrl+V para colar';

  @override
  String get onboardingReadyContextCarryoverHint =>
      'O WhisPaste mantém o contexto da gravação anterior por até dez minutos. Antes de mudar rapidamente para um assunto não relacionado, faça uma pequena pausa para que o próximo resultado continue certo.';

  @override
  String get onboardingReadyAutostartToggle =>
      'Iniciar o WhisPaste ao fazer login';

  @override
  String get onboardingReadyAutostartToggleHint =>
      'Desativado por padrão, ative nas Configurações quando quiser';

  @override
  String get onboardingTriggerTitle => 'Como você quer iniciar a gravação?';

  @override
  String get onboardingTriggerSubtitle =>
      'Defina seu atalho e escolha como ele inicia uma gravação.';

  @override
  String get onboardingTriggerCurrentHotkey => 'Atalho atual';

  @override
  String get onboardingTriggerHotkeyConflictTitle => 'Atalho já em uso';

  @override
  String get onboardingTriggerHotkeyConflictBody =>
      'Seu atalho parece estar em uso por outro app. Grave uma nova combinação abaixo para continuar.';

  @override
  String get onboardingReadyHotkeyConflictBody =>
      'Volte à página de atalho e grave uma nova combinação ali.';

  @override
  String get onboardingTriggerModeHoldHint =>
      'Segure o atalho e fale, solte para terminar';

  @override
  String get onboardingTriggerModeToggleHint =>
      'Pressione uma vez para iniciar, pressione de novo para terminar';

  @override
  String get onboardingTriggerSystemWideHint =>
      'Funciona em todo o sistema — não só dentro do WhisPaste.';

  @override
  String get onboardingStartUsing => 'Vamos lá';

  @override
  String get onboardingReviewExit => 'Fechar introdução';

  @override
  String get onboardingReviewDone => 'Concluído';

  @override
  String get onboardingReviewEntry => 'Introdução';

  @override
  String get onboardingReviewSubtitle =>
      'Refaça os cinco passos de configuração quando quiser — nada muda, a menos que você mude.';

  @override
  String get onboardingReviewLabel => 'Rever a introdução';

  @override
  String get onboardingReviewAction => 'Abrir';

  @override
  String get onboardingRevisionNoticeTitle =>
      'O WhisPaste foi atualizado — suas configurações não mudaram.';

  @override
  String get onboardingRevisionExit => 'Sair da introdução';

  @override
  String get onboardingRevisionExitConfirmTitle => 'Sair da introdução?';

  @override
  String get onboardingRevisionExitConfirmBody =>
      'Este guia de atualização é mostrado só uma vez, então os passos que você pular agora não serão configurados para você. Você pode reabrir os mesmos passos a qualquer momento em Configurações → Introdução, e cada configuração deles também tem seu próprio lugar nas Configurações. O que você já configurou permanece intacto.';

  @override
  String get onboardingRevisionExitConfirmAction => 'Sair';

  @override
  String get overlayRecording => 'Gravando';

  @override
  String get overlayTranscribing => 'Transcrevendo…';

  @override
  String get overlayRefining => 'Refinando…';

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
  String get traySettings => 'Configurações';

  @override
  String get trayQuit => 'Sair';

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
      'Nota de voz — diga “tag: …” para adicionar uma tag, ou “correct: …” para reescrever esta transcrição';

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
  String get settingsOverlayStyle => 'Estilo do overlay';

  @override
  String get settingsOverlayStyleSubtitle =>
      'Escolha entre vidro ou um visual sólido e opaco';

  @override
  String get settingsOverlayStyleGlass => 'Vidro';

  @override
  String get settingsOverlayStyleSolid => 'Sólido';

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
  String get buttonContextShowHistory => 'Mostrar histórico';

  @override
  String get buttonContextSettings => 'Configurações';

  @override
  String get buttonContextQuit => 'Sair do WhisPaste';

  @override
  String get settingsHistory => 'Histórico';

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
  String get settingsHistoryHideOnOpen => 'Ocultar histórico ao abrir';

  @override
  String get settingsHistoryHideOnOpenSubtitle =>
      'Mostra um botão “Mostrar histórico” no lugar das suas transcrições sempre que o WhisPaste iniciar ou a janela for reaberta';

  @override
  String get historyPinGateTitle => 'Histórico bloqueado';

  @override
  String get historyPinGateHint =>
      'Digite seu PIN para mostrar suas transcrições.';

  @override
  String get historyPinUnlock => 'Desbloquear';

  @override
  String get historyPinDialogTitle => 'Digite o PIN';

  @override
  String get historyPinDialogSubtitle =>
      'Seu histórico está protegido por PIN.';

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
  String get historyPinForgotConfirmTitle => 'Excluir histórico e remover PIN?';

  @override
  String get historyPinForgotConfirmMessage =>
      'Um PIN esquecido não pode ser recuperado. Para redefini-lo, todo o seu histórico — incluindo arquivo, lixeira e gravações mantidas — é excluído permanentemente. Configurações, notas, snippets e substituições são mantidos.';

  @override
  String get historyPinForgotConfirmAction => 'Excluir histórico';

  @override
  String get historyPinSetTitle => 'Definir PIN';

  @override
  String get historyPinSetSubtitle =>
      '4 a 8 dígitos. Impede que outras pessoas vejam seu histórico neste computador com facilidade — mas não o criptografa.';

  @override
  String get historyPinInvalid => 'Use de 4 a 8 dígitos.';

  @override
  String get historyPinMismatch => 'Os PINs não coincidem.';

  @override
  String get settingsHistoryPin => 'Proteção por PIN';

  @override
  String get settingsHistoryPinSubtitle =>
      'Exige um PIN para mostrar o histórico, incluindo painel lateral, menu do botão flutuante e API de automação.';

  @override
  String get settingsHistoryPinChange => 'Alterar';

  @override
  String get settingsHistoryPinRemove => 'Remover';

  @override
  String get settingsHistoryAutoLock => 'Bloquear automaticamente';

  @override
  String get settingsHistoryAutoLockSubtitle =>
      'Oculta o histórico novamente após este tempo sem atividade.';

  @override
  String get settingsHistoryAutoLockNever => 'Nunca';

  @override
  String settingsHistoryAutoLockMinutes(int minutes) {
    return 'Após $minutes min';
  }

  @override
  String get settingsFloatingButtonSection => 'Botão flutuante';

  @override
  String get settingsFloatingButtonSectionSubtitle =>
      'Botão de gravação sempre no topo, para acesso rápido';

  @override
  String get settingsSttIdleTimeout => 'Tempo de inatividade do motor';

  @override
  String get settingsSttIdleTimeoutSubtitle =>
      'Por quanto tempo o serviço de voz permanece carregado após o uso';

  @override
  String get settingsSttIdleTimeoutKeepAlive => 'Manter ativo';

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
  String get reviewPromptTitle => 'Você está gostando do WhisPaste?';

  @override
  String get reviewPromptBody =>
      'Sua avaliação ajuda outras pessoas a descobri-lo e mantém o desenvolvimento em andamento.';

  @override
  String get reviewPromptYes => 'Adoro!';

  @override
  String get reviewPromptNotNow => 'Agora não';

  @override
  String get reviewPromptNever => 'Não perguntar mais';

  @override
  String get reviewPromptStarGitHub => '⭐ Dar estrela no GitHub';

  @override
  String get reviewPromptRateStore => '★ Avaliar na loja';

  @override
  String get reviewPromptGateBody =>
      'Só uma pergunta rápida para nós, isto não é uma avaliação na loja.';

  @override
  String get reviewPromptGateYes => 'Sim, gosto';

  @override
  String get reviewPromptGateNo => 'Não muito';

  @override
  String get reviewSupportEntry => 'Avalie e apoie o WhisPaste';

  @override
  String get reviewSupportLabel => 'Sua avaliação';

  @override
  String get reviewSupportSubtitle =>
      'Sua avaliação ajuda outras pessoas a encontrar o WhisPaste e apoia o projeto.';

  @override
  String get reviewSupportAction => 'Avaliar';

  @override
  String get ideasBoardLabel => 'Ideias e pedidos de recursos';

  @override
  String get ideasBoardAction => 'Ver quadro';

  @override
  String get feedbackIdeasLink => 'Sugira e vote em ideias';

  @override
  String get insufficientRamTitle => 'Memória insuficiente';

  @override
  String insufficientRamBody(double detectedGb, int requiredGb) {
    final intl.NumberFormat detectedGbNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String detectedGbString = detectedGbNumberFormat.format(detectedGb);

    return 'O WhisPaste precisa de pelo menos $requiredGb GB de RAM para rodar. Seu sistema tem $detectedGbString GB.\n\nCom menos memória, o motor de transcrição por IA pode não carregar ou travar durante a sessão.';
  }

  @override
  String get insufficientRamQuit => 'Sair do WhisPaste';

  @override
  String get insufficientRamLearnMore => 'Requisitos do sistema';

  @override
  String get insufficientRamSystemCheck => 'Verificação do sistema';

  @override
  String get insufficientRamYourSystem => 'Seu sistema';

  @override
  String get insufficientRamRequired => 'Necessário';

  @override
  String get hotkeyRegistrationFailed =>
      'Falha ao registrar o atalho. Defina sua combinação novamente nas Configurações.';

  @override
  String get hotkeyRegistrationFailedDefaultActive =>
      'Falha ao registrar o atalho, usando Ctrl+Shift+Espaço como alternativa. Defina-o novamente nas Configurações.';

  @override
  String hotkeyConflictWarning(String platform, String note) {
    return 'Este atalho é reservado pelo $platform ($note) e pode não funcionar.';
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
      'O serviço de voz não pode iniciar. Reinicie o app ou recarregue o modelo de voz.';

  @override
  String get recoveryExhaustedAction => 'Abrir configurações';

  @override
  String get recoveryVcRuntimeToast =>
      'O serviço de voz não pode iniciar: falta um componente do Windows (Microsoft Visual C++). Instale o Visual C++ Redistributable (x64) e reinicie o WhisPaste.';

  @override
  String get recoveryVcRuntimeAction => 'Instalar';

  @override
  String get modelAbiInfoToast => 'Recarregando o modelo de voz, aguarde.';

  @override
  String get recoveryGpuDisabledToast =>
      'Por causa de um problema na última inicialização, o WhisPaste agora roda sem aceleração por GPU. O ditado continua funcionando normalmente.';

  @override
  String get serverDownloadFailedToast =>
      'Não foi possível baixar o serviço de voz. Verifique sua conexão com a internet?';

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
  String get factoryResetFailedToast =>
      'Redefinição de fábrica incompleta. Reiniciar o app?';

  @override
  String get factoryResetFailedAction => 'Sair do app';

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
      'Define se o serviço de voz usa GPU ou CPU para o reconhecimento local';

  @override
  String get settingsGpuAccelerationAuto => 'Automático (recomendado)';

  @override
  String get settingsGpuAccelerationEnabled => 'GPU (forçado)';

  @override
  String get settingsGpuAccelerationDisabled => 'Somente CPU';

  @override
  String get settingsSttEngine => 'Mecanismo';

  @override
  String get settingsSttEngineSubtitle =>
      'O Whisper cobre 99 idiomas e todos os backends de GPU; o Parakeet é bem mais rápido em hardware só com CPU, mas cobre cerca de 25 idiomas e ainda não tem backend de GPU';

  @override
  String get settingsSttEngineWhisper => 'Whisper';

  @override
  String get settingsSttEngineParakeet => 'Parakeet (mais rápido, ~25 idiomas)';

  @override
  String get parakeetModelTitle => 'Modelo Parakeet TDT';

  @override
  String get parakeetModelSubtitle =>
      'Download único (~640 MB), depois funciona totalmente offline';

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
  String get settingsShareUsageStats =>
      'Compartilhar estatísticas anônimas de uso';

  @override
  String get settingsShareUsageStatsSubtitle =>
      'Sem cookies, com um ID aleatório por sessão e um pseudônimo que muda semanalmente — nos ajuda a entender como o WhisPaste é usado';

  @override
  String get settingsRetainRecentAudio => 'Manter gravações recentes';

  @override
  String get settingsRetainRecentAudioSubtitle =>
      'Mantém o áudio dos seus últimos 20 ditados neste dispositivo, para depuração ou para restaurar uma transcrição anterior; gravações mais antigas são excluídas automaticamente';

  @override
  String get storeThankYouTitle => 'Obrigado pelo seu apoio!';

  @override
  String get storeThankYouBody =>
      'Ficamos muito felizes por você estar aqui. Se o WhisPaste facilita um pouco o seu dia, uma avaliação curta significa muito para nós.';

  @override
  String get storeThankYouCtaStore => '★ Avaliar na loja';

  @override
  String get storeThankYouCtaGitHub => '⭐ Dar estrela no GitHub';

  @override
  String get storeThankYouDismiss => 'Fechar';

  @override
  String get featureSpotlightHeading => 'Novidades no WhisPaste';

  @override
  String get featureSpotlightDismiss => 'Entendi';

  @override
  String get featureSpotlightSnippetPickerTitle => 'Seletor de snippets';

  @override
  String get featureSpotlightSnippetPickerDescription =>
      'Salve blocos de texto reutilizáveis e insira-os em qualquer lugar com um atalho ou um gatilho falado — sem precisar digitar de novo.';

  @override
  String get featureSpotlightSidePanelTitle =>
      'Painel lateral da área de transferência';

  @override
  String get featureSpotlightSidePanelDescription =>
      'Passe o cursor na borda da tela para abrir seu histórico recente da área de transferência e arraste qualquer item direto para o seu documento.';

  @override
  String get featureSpotlightInteractiveSnippetsTitle => 'Snippets interativos';

  @override
  String get featureSpotlightInteractiveSnippetsDescription =>
      'Snippets com lacunas: o WhisPaste guia você por cada campo — dite, pressione Enter para o próximo, e o texto final é colado de uma vez.';

  @override
  String get featureSpotlightSmartModeTitle => 'Smart Mode';

  @override
  String get featureSpotlightSmartModeDescription =>
      'Limpe, encurte ou traduza seu ditado antes de ele ser colado — totalmente no dispositivo, com atalho, predefinição e idioma de destino próprios.';

  @override
  String get featureSpotlightHistoryPinTitle =>
      'Proteja seu histórico com um PIN';

  @override
  String get featureSpotlightHistoryPinDescription =>
      'Mantenha suas transcrições privadas atrás de um PIN — inclusive o painel lateral e o menu do botão flutuante — com bloqueio automático opcional após inatividade. Configurações → Histórico.';

  @override
  String get featureSpotlightChangelogLink => 'Ver changelog completo';

  @override
  String get featureSpotlightReviewLabel => 'Conhecer os novos recursos';

  @override
  String get featureSpotlightReviewAction => 'Mostrar';

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
  String get settingsSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeSubtitle =>
      'Limpeza, encurtamento e tradução de texto local após o ditado';

  @override
  String get smartModeStandardPreset => 'Predefinição padrão';

  @override
  String get smartModePresetOff => 'Desativado';

  @override
  String get smartModePresetOffDescription =>
      'Nenhum pós-processamento automático — o texto ditado é usado exatamente como foi transcrito.';

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
      'Traduz o texto ditado para o idioma de destino definido abaixo.';

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
  String get smartModeDownloadComplete =>
      'Modelo do Smart Mode pronto para uso';

  @override
  String get smartModeRamWarningTitle => 'Memória limitada detectada';

  @override
  String get smartModeRamWarningBody =>
      'O modelo local do Smart Mode funciona melhor com 8 GB de RAM ou mais. Pode funcionar mesmo assim, mas pode ser lento ou falhar neste computador. Baixar mesmo assim?';

  @override
  String get smartModeRamWarningContinue => 'Baixar mesmo assim';

  @override
  String get smartModeRamWarningCancel => 'Cancelar';

  @override
  String get smartModeMemoryFootprintInfo =>
      'Roda totalmente no dispositivo. Enquanto ativo, usa cerca de 4–5 GB de RAM além do espaço em disco — compartilhados com o modelo de transcrição, então o uso total de memória depende de qual modelo STT você também tem carregado.';

  @override
  String get smartModeSpeedExampleInfo =>
      'Exemplo: um ditado típico de 50 palavras leva cerca de 1 a 6 segundos para ser processado, dependendo do hardware do seu dispositivo.';

  @override
  String get smartModeLocalUnavailable =>
      'O Smart Mode no dispositivo não está incluído nesta versão. Mude para a OpenAI ou instale uma versão oficial do WhisPaste.';

  @override
  String get settingsHotkeyActionSmartMode => 'Smart Mode';

  @override
  String get settingsSmartModeHotkeyEnabled => 'Atalho do Smart Mode';

  @override
  String get settingsSmartModeHotkeyHint =>
      'Inicia uma gravação com uma predefinição fixa, independente da predefinição padrão acima. Suporta pressionar para falar, assim como o atalho principal.';

  @override
  String get settingsSmartModeHotkeyPreset => 'Predefinição';

  @override
  String get settingsSmartModeCurrentHotkey => 'Combinação';

  @override
  String settingsSmartModeHotkeyCollision(String action) {
    return 'Esta combinação já está em uso para \"$action\". Escolha outra.';
  }

  @override
  String get settingsSmartModeHotkeyInactive =>
      'Não foi possível registrar esta combinação — o atalho do Smart Mode não está ativo no momento. Escolha outra combinação.';

  @override
  String get smartModeOnboardingHintTitle => 'Experimente o Smart Mode';

  @override
  String get smartModeOnboardingHintBody =>
      'O Smart Mode pode limpar, encurtar ou traduzir seu texto ditado automaticamente — totalmente no dispositivo. Baixe o modelo local agora ou configure depois em Configurações.';

  @override
  String get smartModeOnboardingHintExampleBeforeLabel => 'Ditado bruto';

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
  String get smartModeOnboardingHintSkipCta => 'Pular';

  @override
  String get smartModeUsageHintTitle =>
      'Experimente o Smart Mode no seu próximo ditado';

  @override
  String get smartModeUsageHintBody =>
      'O Smart Mode pode limpar, encurtar ou traduzir um texto como este automaticamente, direto no seu dispositivo. Veja o que você acabou de ditar:';

  @override
  String get smartModeUsageHintCta => 'Configurar';

  @override
  String get smartModeUsageHintDismiss => 'Agora não';

  @override
  String get settingsAutomationApi => 'API local de automação';

  @override
  String get settingsAutomationApiSubtitle =>
      'Inicie ditados a partir dos seus próprios scripts por uma API HTTP restrita ao loopback';

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
  String get settingsSelectionEditHotkeyEnabled => 'Atalho para editar seleção';

  @override
  String get settingsSelectionEditHotkeyHint =>
      'Selecione texto em qualquer app, pressione este atalho e diga o que mudar — ou apenas \"mais curto\", \"melhorar\" ou \"traduzir\". O resultado substitui a seleção; desfazer no app traz o original de volta. Usa o mecanismo do Smart Mode configurado acima.';

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
      'Configure o Smart Mode primeiro (baixe o modelo local ou adicione uma chave da OpenAI) para editar seleções';

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
  String get errorSelectionEditPasteFailed =>
      'Não foi possível substituir a seleção — seu texto foi mantido sem alterações';

  @override
  String get settingsCudaPackTitle => 'Aceleração NVIDIA CUDA';

  @override
  String settingsCudaPackSubtitle(String size) {
    return 'Ditado mais rápido em placas GeForce RTX e GTX 16. Download único de $size.';
  }

  @override
  String get settingsCudaPackInstalledSubtitle =>
      'Instalado. Se o driver de vídeo for antigo demais, o WhisPaste continua usando Vulkan.';

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
  String get recoveryCudaDisabledToast =>
      'A aceleração CUDA foi desativada por causa de um problema na última inicialização. O WhisPaste agora usa Vulkan, e o ditado funciona normalmente.';
}
