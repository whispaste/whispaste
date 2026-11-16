import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/config/command_shortcut.dart';
import '../../../core/data/database.dart' show kAudioCap;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/ltr_isolate.dart';
import '../../../core/recording/recording_helpers.dart'
    show displayNameForModel;
import '../../../services/audio/retention/audio_retention.dart'
    show kRetainedAudioMaxAge;
import '../../../services/hardware_info_service.dart' show kMinRamMB;
import '../../../services/model_download_service.dart'
    show sttModels, formatModelSizeLabel;
import '../../../services/stt_parakeet/parakeet_download_service.dart'
    show parakeetDownloadBytes;
import '../../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelFiles, parakeetModelId, parakeetModelTotalBytes;
import '../../../services/smart_mode/smart_mode_model_download_service.dart'
    show smartModeModel;
import '../../settings/sections/smart_mode_section.dart'
    show kSmartModeRamWarningThresholdMB;
import 'manual_model.dart';

/// A figure in gigabytes for the handbook, in the reader's locale. Every
/// number comes from the code constants, so the text cannot drift from the
/// gate or the download metadata.
String _gbLabel(L10n l, double gigabytes) =>
    '${NumberFormat('#,##0.#', l.localeName).format(gigabytes)} GB';

/// What the macOS notice "another app slows the keyboard" / "secure keyboard
/// input" means and what to do (#775, #915, #1607). It lives in the
/// troubleshooting chapter and is also opened on its own from the notice's
/// "What to do?" action (`showManualSectionDialog`).
final ManualSection manualHotkeyDisturbedSection = ManualSection(
  heading: (l) => l.manualC14S13HotkeyHeading,
  blocks: <ManualBlock>[
    // The secure-input notice as the app composes it for an unnamed holder
    // (`hotkeyDisturbanceText`, #1617): the cause with the way out, then the
    // effect on the hotkey.
    ManualNotice(
      (l) =>
          '${l.pasteSecureInputGeneric} '
          '${l.hotkeyDisturbanceSecureInputEffect}',
    ),
    ManualNotice((l) => l.hotkeyDisturbanceSlowTapGeneric),
    ManualParagraph((l) => l.manualC14S13HotkeyB2),
    ManualBullets(<ManualText>[
      (l) => l.manualC14S13HotkeyStep1,
      (l) => l.manualC14S13HotkeyStep2,
      (l) => l.manualC14S13HotkeyStep3,
      (l) => l.manualC14S13HotkeyStep4,
      (l) => l.manualC14S13HotkeyStep5,
    ]),
  ],
);

/// How to put a speech model on the computer by hand, for a machine without a
/// connection to the download server. It lives in the hardware chapter and is
/// also shown on its own from the download error (`showManualSectionDialog`).
///
/// File names, sizes, addresses and the Parakeet folder name come from the
/// model registries (`sttModels`, `parakeetModelFiles`, `parakeetModelId`).
/// The folder texts below are fixed strings that mirror `appDataDir()` and
/// `sttDir()` (`packages/whispaste_diagnostics/lib/src/probes/path_service.dart`);
/// change them together with those.
final ManualSection manualModelInstallSection = ManualSection(
  heading: (l) => l.manualC13S8Heading,
  blocks: <ManualBlock>[
    ManualParagraph((l) => l.manualC13S8B1),
    ManualParagraph((l) => l.manualC13S8B2),
    for (final model in sttModels) ...<ManualBlock>[
      ManualParagraph(
        (l) => l.manualC13S8Model(
          displayNameForModel(model.id, l),
          ltrIsolate(model.filename),
          model.sizeLabel,
        ),
      ),
      ManualCode('model-url-${model.id}', (l) => model.url),
    ],
    ManualParagraph(
      (l) => l.manualC13S8Parakeet(
        ltrIsolate(parakeetModelId),
        formatModelSizeLabel(parakeetModelTotalBytes),
      ),
    ),
    for (final file in parakeetModelFiles)
      ManualCode('model-url-parakeet-${file.filename}', (l) => file.url),
    ManualParagraph((l) => l.manualC13S8B3),
    ManualParagraph((l) => l.manualC13S8MacDirect),
    ManualCode(
      'model-folder-macos',
      (l) => '~/Library/Application Support/WhisPaste/models/stt',
    ),
    ManualParagraph((l) => l.manualC13S8MacStore),
    ManualCode(
      'model-folder-macos-store',
      (l) =>
          '~/Library/Containers/de.whispaste.app/Data/Library/'
          'Application Support/WhisPaste/models/stt',
    ),
    ManualParagraph((l) => l.manualC13S8WinDirect),
    ManualCode(
      'model-folder-windows',
      (l) => r'%APPDATA%\WhisPaste\models\stt',
    ),
    ManualParagraph((l) => l.manualC13S8WinStore),
    ManualCode(
      'model-folder-windows-store',
      (l) =>
          r'%LOCALAPPDATA%\Packages\12342SilvioLindstedt.WhisPaste_*\'
          r'LocalCache\Roaming\WhisPaste\models\stt',
    ),
    ManualParagraph((l) => l.manualC13S8Linux),
    ManualCode('model-folder-linux', (l) => '~/.config/whispaste/models/stt'),
    ManualParagraph((l) => l.manualC13S8LinuxFlatpak),
    ManualCode(
      'model-folder-linux-flatpak',
      (l) => '~/.var/app/de.whispaste.app/config/whispaste/models/stt',
    ),
    ManualParagraph((l) => l.manualC13S8B4),
    ManualTip((l) => l.manualC13S8Tip),
  ],
);

/// Handbook chapters in reading order. Every text is an ARB key (`manualC...`),
/// so the wording lives in the translation files.
final List<ManualChapter> manualChapters = <ManualChapter>[
  ManualChapter(
    slug: 'first-steps',
    title: (l) => l.manualC01Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC01S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC01S1B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC01S1B2I1,
            (l) => l.manualC01S1B2About,
            (l) => l.manualC01S1B2I2,
            (l) => l.manualC01S1B2I3,
            (l) => l.manualC01S1B2I4,
            (l) => l.manualC01S1B2I5,
            (l) => l.manualC01S1B2I6,
          ]),
          ManualParagraph((l) => l.manualC01S1B3),
          ManualParagraph((l) => l.manualC01S1B3Panel),
          ManualParagraph((l) => l.manualC01S1B4),
          ManualParagraph((l) => l.manualC01S1B5),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC01S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC01S2B1(ltrIsolate(_gbLabel(l, kMinRamMB / 1024))),
          ),
          ManualParagraph((l) => l.manualC01S2B2),
          ManualParagraph((l) => l.manualC01S2B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC01S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC01S3B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC01S3B2I1(
              ltrIsolate(
                formatModelSizeLabel(
                  parakeetDownloadBytes(gpuWanted: false),
                  locale: l.localeName,
                ),
              ),
            ),
            (l) => l.manualC01S3B2I2(
              ltrIsolate(
                formatModelSizeLabel(
                  sttModels.first.sizeBytes,
                  locale: l.localeName,
                ),
              ),
              ltrIsolate(
                formatModelSizeLabel(
                  sttModels.last.sizeBytes,
                  locale: l.localeName,
                ),
              ),
            ),
            (l) => l.manualC01S3B2I3(ltrIsolate('models/stt')),
          ]),
          ManualParagraph((l) => l.manualC01S3B3),
          ManualParagraph((l) => l.manualC01S3B4),
          ManualParagraph((l) => l.manualC01S3B5),
          ManualParagraph((l) => l.manualC01S3B6),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'recording',
    title: (l) => l.manualC02Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC02S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC02S1B1(
              ltrIsolate('Ctrl+Shift+D'),
              ltrIsolate('Cmd+Shift+D'),
            ),
          ),
          ManualParagraph(
            (l) => l.manualC02S1B2(
              ltrIsolate('Ctrl+Shift+Space'),
              ltrIsolate('Cmd+Shift+Space'),
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC02S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC02S2B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC02S2B2I1,
            (l) => l.manualC02S2B2I2,
            (l) => l.manualC02S2B2I3,
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC02S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC02S3B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC02S3B2I1,
            (l) => l.manualC02S3B2I2,
            (l) => l.manualC02S3B2I3,
            (l) => l.manualC02S3B2I4,
          ]),
          ManualParagraph((l) => l.manualC02S3B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC02S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC02S4B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC02S4B2I1,
            (l) => l.manualC02S4B2I2,
            (l) => l.manualC02S4B2I3,
            (l) => l.manualC02S4B2I4,
          ]),
          ManualParagraph((l) => l.manualC02S4B3),
          ManualTip((l) => l.manualC02S4B4),
          ManualParagraph((l) => l.manualC02S4B5),
          ManualParagraph((l) => l.manualC02S4B6),
          ManualParagraph((l) => l.manualC02S4B7),
          ManualParagraph((l) => l.manualC02S4B8),
          ManualParagraph((l) => l.manualC02S4B9),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'quick-note',
    title: (l) => l.manualC03Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC03S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC03S1B1),
          ManualParagraph((l) => l.manualC03S1B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC03S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC03S2B1I1,
            (l) => l.manualC03S2B1I2(
              ltrIsolate('N'),
              ltrIsolate('Ctrl+Shift+N'),
              ltrIsolate('Cmd+Shift+N'),
            ),
          ]),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'smart-mode',
    title: (l) => l.manualC04Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC04S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC04S1B1(ltrIsolate('Smart Mode'))),
          ManualParagraph((l) => l.manualC04S1B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC04S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC04S2B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC04S2B2I1,
            (l) => l.manualC04S2B2I2,
            (l) => l.manualC04S2B2I3,
            (l) => l.manualC04S2B2I4,
            (l) => l.manualC04S2B2I5,
          ]),
          ManualParagraph((l) => l.manualC04S2B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC04S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC04S3B1),
          ManualParagraph((l) => l.manualC04S3B2(ltrIsolate('Smart Mode'))),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC04S5Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC04S5B1),
          ManualParagraph((l) => l.manualC04S5B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC04S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC04S4B1(
              ltrIsolate(
                formatModelSizeLabel(
                  smartModeModel.sizeBytes,
                  locale: l.localeName,
                ),
              ),
              ltrIsolate(_gbLabel(l, kSmartModeRamWarningThresholdMB / 1024)),
            ),
          ),
          ManualParagraph((l) => l.manualC04S4B2),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'replacements',
    title: (l) => l.manualC05Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC05S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC05S1B1),
          ManualParagraph((l) => l.manualC05S1B2),
          ManualParagraph((l) => l.manualC05S1B3),
          ManualParagraph((l) => l.manualC05S1B4),
          ManualParagraph((l) => l.manualC05S1B5),
          ManualParagraph((l) => l.manualC05S1B6),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC05S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC05S2B1I1,
            (l) => l.manualC05S2B1I2,
            (l) => l.manualC05S2B1I3,
          ]),
          ManualParagraph((l) => l.manualC05S2B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC05S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC05S3B1(
              ltrIsolate('triggers, replacement, match_mode, threshold'),
              ltrIsolate('|'),
              ltrIsolate('1 MB'),
              ltrIsolate('5000'),
            ),
          ),
          ManualParagraph((l) => l.manualC05S3B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC05S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC05S4B1),
          ManualParagraph((l) => l.manualC05S4B2),
          ManualParagraph((l) => l.manualC05S4B3),
          ManualParagraph((l) => l.manualC05S4B4),
          ManualParagraph((l) => l.manualC05S4B5),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC05S5Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC05S5B1),
          ManualParagraph((l) => l.manualC05S5B2),
          ManualParagraph((l) => l.manualC05S5B3),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'snippets',
    title: (l) => l.manualC06Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC06S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC06S1B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC06S1B2I1,
            (l) => l.manualC06S1B2I2,
          ]),
          ManualParagraph((l) => l.manualC06S1B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC06S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC06S2B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC06S2B2I1,
            (l) => l.manualC06S2B2I2,
          ]),
          ManualParagraph((l) => l.manualC06S2B3(mainShortcutLabel('Enter'))),
          ManualParagraph((l) => l.manualC06S2B4),
          ManualParagraph((l) => l.manualC06S2B5),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC06S3Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC06S3B1I1,
            (l) => l.manualC06S3B1I2(ltrIsolate('{{Name}}')),
            (l) => l.manualC06S3B1I3(
              ltrIsolate(
                r'{$date}, {$time}, {$clipboard}, {$title}, {$cursor}',
              ),
              ltrIsolate(r'{$date:yyyy-MM-dd}'),
            ),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC06S4Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC06S4B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC06S5Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC06S5B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC06S6Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC06S6B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC06S7Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC06S7B1(
              commandShortcutLabel('I', shift: true, l10n: l),
            ),
          ),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'notes',
    title: (l) => l.manualC07Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC07S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC07S1B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC07S1B2I1,
            (l) => l.manualC07S1B2I2,
            (l) => l.manualC07S1B2I3,
            (l) => l.manualC07S1B2I4,
            (l) => l.manualC07S1B2I5,
            (l) => l.manualC07S1B2I6,
            (l) => l.manualC07S1B2I7,
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC07S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC07S2B1),
          ManualBullets(<ManualText>[(l) => l.manualC07S2B2I1]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC07S3Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC07S3B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC07S4Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC07S4B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC07S5Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC07S5B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC07S6Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) =>
                l.manualC07S6B1(ltrIsolate(mainShortcutLabel('Shift+Enter'))),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC07S7Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC07S7B1),
          ManualParagraph((l) => l.manualC07S7B2),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'history',
    title: (l) => l.manualC08Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC08S1Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC08S1B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC08S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC08S2B1I1(ltrIsolate('#')),
            (l) => l.manualC08S2B1I2(ltrIsolate('lang:')),
            (l) => l.manualC08S2B1I3,
            (l) => l.manualC08S2B1I4,
            (l) => l.manualC08S2B1I5(ltrIsolate('date:')),
            (l) => l.manualC08S2B1I6(
              ltrIsolate('longer:'),
              ltrIsolate('shorter:'),
            ),
          ]),
          ManualTip(
            (l) => l.manualC08S2B2(l.settingsIndexRebuild, l.settingsHistory),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC08S3Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC08S3B1I1,
            (l) => l.manualC08S3B1I2,
            (l) => l.manualC08S3B1I3,
            (l) => l.manualC08S3B1I4,
            (l) => l.manualC08S3B1I5,
            (l) => l.manualC08S3B1I6,
          ]),
          ManualParagraph((l) => l.manualC08S3B2),
          ManualParagraph((l) => l.manualC08S3B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC08S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC08S4B1),
          ManualTip((l) => l.manualC08S4B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC08S5Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC08S5B1),
          ManualParagraph((l) => l.manualC08S5B2),
          ManualParagraph((l) => l.manualC08S5B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC08S6Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC08S6B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC08S7Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC08S7B1(l.settingsHistory)),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'file-import',
    title: (l) => l.manualC09Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC09S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC09S1B1(l.historyImportAddFiles)),
          ManualParagraph(
            (l) => l.manualC09S1B2(
              ltrIsolate('WAV'),
              ltrIsolate('MP3, FLAC, M4A, AAC, Ogg/Opus'),
              ltrIsolate('MP3, FLAC, Ogg/Opus, M4A and AAC (with GStreamer)'),
              ltrIsolate('MP3, FLAC, M4A, AAC, Ogg/Opus'),
            ),
          ),
          // "Transcribe with WhisPaste" in the file manager (#1684): the
          // audio types of audioImportExtensions.
          ManualParagraph(
            (l) => l.manualC09S1B4(
              ltrIsolate('WAV, MP3, FLAC, M4A, AAC, Ogg, Opus'),
            ),
          ),
          // The GStreamer decoder and its apt command are Linux facts. The
          // other platforms decode M4A/AAC natively, so they get no block.
          if (defaultTargetPlatform == TargetPlatform.linux) ...[
            ManualParagraph((l) => l.manualC09S1B3),
            ManualCode('gstreamer-libav-install', (l) => l.manualC09S1Cmd),
          ],
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC09S2Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.historyImportFailureInputLimit),
          ManualParagraph((l) => l.manualC09S2B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC09S3Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.historyImportFailureTranscription),
          ManualParagraph((l) => l.manualC09S3B2(l.settingsSpeechRecognition)),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'statistics',
    title: (l) => l.manualC10Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC10S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC10S1B1(
              l.analyticsOverview,
              l.analyticsActivity,
              l.analyticsInsights,
            ),
          ),
          ManualParagraph(
            (l) => l.manualC10S1B2(l.analyticsPeriod7d, l.analyticsPeriodAll),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC10S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC10S2B1I1(
              l.analyticsTotalRecordings,
              l.analyticsTotalDuration,
            ),
            (l) => l.manualC10S2B1I2(l.analyticsTimeSaved),
            (l) => l.manualC10S2B1I3(
              l.analyticsCostSavings,
              ltrIsolate('0.006 USD'),
            ),
            (l) => l.manualC10S2B1I4,
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC10S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC10S3B1(l.analyticsReset)),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'settings',
    title: (l) => l.manualC11Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC11S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC11S1B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC11S1B2I1(l.settingsInterface),
            (l) => l.manualC11S1B2I2(l.settingsSpeechRecognition),
            (l) => l.manualC11S1B2I3(l.settingsAudio),
            (l) => l.manualC11S1B2I4(l.settingsSmartMode),
            (l) => l.manualC11S1B2I5(l.settingsAfterTranscription),
            (l) => l.manualC11S1B2I6(l.settingsAreaShortcuts),
            (l) => l.manualC11S1B2I7(l.settingsHistory),
            (l) => l.manualC11S1B2I8(l.settingsPortabilitySectionTitle),
            (l) => l.manualC11S1B2I9(l.settingsAutomationApi),
            (l) => l.manualC11S1B2I10(l.settingsAdvanced),
            (l) => l.manualC11S1B2I11(l.pageAboutTitle),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC11S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC11S2B1I1(l.settingsAutosaveLabel),
            (l) => l.manualC11S2B1I2(l.settingsFactoryReset),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualLangFavHeading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualLangFavB1)],
      ),
      ManualSection(
        heading: (l) => l.manualLangTrayHeading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualLangTrayB1)],
      ),
      ManualSection(
        heading: (l) => l.manualSoundHeading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) =>
                l.manualSoundB1(l.settingsSoundProfile, l.settingsSoundVolume),
          ),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'privacy',
    title: (l) => l.manualC12Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC12S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC12S1B1(
              l.settingsRetainRecentAudio,
              kAudioCap,
              kRetainedAudioMaxAge.inDays,
            ),
          ),
          ManualParagraph((l) => l.manualC12S1B2),
          // No fixed day counts here: the values in use are set under
          // Privacy & data, and the onboarding privacy page shows them.
          ManualParagraph((l) => l.manualC12S1B3Ref),
          ManualParagraph((l) => l.manualC12S1B4),
          ManualParagraph((l) => l.manualC12S1B5Ref),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC12S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC12S2B1(l.settingsAreaApiKeys)),
          ManualParagraph((l) => l.manualC12S2B2),
          ManualParagraph((l) => l.manualC12S2B3),
          ManualParagraph((l) => l.manualC12S2B4),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC12S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC12S3B1(
              l.settingsShareUsageStats,
              l.settingsErrorReporting,
              l.settingsPrivacy,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC12S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC12S4B1),
          ManualParagraph(
            (l) => l.manualC12S4B2(
              l.dataKeyAllow,
              l.settingsPrivacy,
              l.dataKeyTitle,
            ),
          ),
          ManualParagraph((l) => l.manualC12S4B3),
          ManualParagraph((l) => l.manualC12S4B4),
          ManualParagraph(
            (l) => l.manualC12S4B5(
              l.settingsPrivacy,
              l.dataKeyTitle,
              l.dataKeyBackupAction,
              l.dataKeyRestore,
              l.dataKeyRetry,
              l.settingsFactoryReset,
            ),
          ),
          ManualParagraph(
            (l) => l.manualC12S4B6(l.dataKeyRestore, l.dataKeyNewAction),
          ),
          // 1.5 encrypts the database and kept audio (#1020, #1021); 1.4.x
          // cannot read either and has no guard, so the way out of a bad 1.5
          // build is fix-forward, never a downgrade (#1637).
          ManualParagraph((l) => l.manualC12S4B7),
        ],
      ),
      // Permissions overview, with Input Monitoring withdrawn later (#1200).
      ManualSection(
        heading: (l) => l.settingsPermissions,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC12S5B1(
              l.settingsAreaPrivacy,
              l.settingsPermissions,
              l.permissionRowMicTitle,
              l.permissionRowPasteTitle,
              l.permissionRowInputMonitoringTitle,
            ),
          ),
          ManualParagraph(
            (l) => l.manualC12S5B2(
              l.permissionRowInputMonitoringTitle,
              l.permissionRowMissing,
              l.permissionRowGrant,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC12S6Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC12S6B1),
          ManualParagraph((l) => l.manualC12S6B2),
        ],
      ),
      // Weather card of the overview: what goes to which service (#1569).
      ManualSection(
        heading: (l) => l.manualC12S7Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC12S7B1(l.overviewWeatherTitle, l.overviewCustomize),
          ),
          ManualParagraph((l) => l.manualC12S7B2(l.overviewWeatherSearch)),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'hardware',
    title: (l) => l.manualC13Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC13S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC13S1B1(ltrIsolate('8 GB'))),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC13S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC13S2B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC13S2B2I1(ltrIsolate('macOS'), ltrIsolate('Metal')),
            (l) => l.manualC13S2B2I2(
              ltrIsolate('Windows'),
              ltrIsolate('Linux'),
              ltrIsolate('Vulkan'),
            ),
            (l) => l.manualC13S2B2I3(ltrIsolate('Vulkan'), ltrIsolate('CUDA')),
            (l) => l.manualC13S2B2I4(ltrIsolate('CPU')),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC13S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC13S3B1(
              ltrIsolate('GeForce RTX'),
              ltrIsolate('GTX 16'),
              ltrIsolate('Windows'),
              ltrIsolate('Linux'),
              l.settingsCudaPackToggle,
            ),
          ),
          ManualParagraph((l) => l.manualC13S3B2),
          ManualParagraph((l) => l.manualC13S3B3),
          ManualParagraph((l) => l.manualC13S3B4),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC13S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC13S4B1(l.settingsGpuAcceleration)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC13S5Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC13S5B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC13S6Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC13S6B1),
          ManualParagraph((l) => l.manualC13S6B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC13S7Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC13S7B1),
          ManualParagraph((l) => l.manualC13S7B2),
          ManualParagraph((l) => l.manualC13S7B3),
        ],
      ),
      manualModelInstallSection,
    ],
  ),
  ManualChapter(
    slug: 'troubleshooting',
    title: (l) => l.manualC14Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC14S1Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC14S1B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC14S2Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorMicPermissionDenied),
          ManualParagraph((l) => l.manualC14S2B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S3Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorNoMicrophone),
          ManualParagraph((l) => l.manualC14S3B2(l.settingsAudio)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S4Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorWavFileEmpty),
          ManualParagraph((l) => l.manualC14S4B2(l.settingsAutoLevel)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S5Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorSttModelNotFound),
          ManualParagraph((l) => l.manualC14S5B2(l.settingsSpeechRecognition)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualDownloadOfflineHeading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualDownloadOfflineCause),
          ManualParagraph(
            (l) => l.manualDownloadOfflineAction(
              l.manualC13S8Heading,
              l.manualC13Title,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S6Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorSttModelUnknown),
          ManualParagraph((l) => l.manualC14S6B2(l.settingsSpeechRecognition)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S7Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorNoticeTranscribeCause),
          ManualParagraph((l) => l.manualC14S7B2(l.settingsSpeechRecognition)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S8Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorTranscriptionEmpty),
          ManualParagraph((l) => l.manualC14S8B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S9Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorPipelineTimeout),
          ManualParagraph((l) => l.manualC14S9B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14HangHeading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.hangWatchdogRestartedNotice),
          ManualParagraph((l) => l.manualC14HangB2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S10Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorCloudAuth(l.settingsAreaApiKeys)),
          ManualParagraph((l) => l.manualC14S10B2(l.settingsAreaApiKeys)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S11Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.infoSttCudaOomFallbackModel),
          ManualParagraph((l) => l.manualC14S11B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S12Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.errorNoticeCpuCause),
          ManualParagraph((l) => l.manualC14S12B2(l.settingsGpuAcceleration)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S13Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.pasteFailurePermissionMissing),
          ManualParagraph((l) => l.manualC14S13B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S13SecureHeading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.pasteSecureInputGeneric),
          ManualParagraph((l) => l.manualC14S13SecureB2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S13PasswordHeading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.pastePasswordFieldTitle),
          ManualParagraph((l) => l.manualC14S13PasswordB2),
        ],
      ),
      manualHotkeyDisturbedSection,
      ManualSection(
        heading: (l) => l.manualC14S14Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.pasteFailureElevationBlocked),
          ManualParagraph((l) => l.manualC14S14B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S15B1),
          ManualParagraph((l) => l.manualC14S15B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15FlatpakHeading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S15B3),
          ManualNotice((l) => l.manualC14S15B3W),
          ManualParagraph((l) => l.manualC14S15B3S),
          ManualCode('udev-reload', (l) => l.manualC14S15Cmd),
          ManualParagraph((l) => l.manualC14S15B3E),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15SnapHeading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S15B4),
          ManualCode('snap-connect-uinput', (l) => l.manualC14S15SnapCmd),
          ManualParagraph((l) => l.manualC14S15Fallback),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15AppImageHeading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC14S15B5)],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15TerminalHeading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S15T1),
          ManualParagraph((l) => l.manualC14S15T2),
          ManualParagraph(
            (l) => l.manualC14S15T3(
              l.settingsLinuxAlwaysShiftPaste,
              l.settingsAfterTranscription,
            ),
          ),
          ManualParagraph(
            (l) => l.manualC14S15T4(l.settingsLinuxGnomeExtensionEnable),
          ),
          ManualCode(
            'gnome-extension-install',
            (l) => l.manualC14S15InstallExtCmd,
          ),
          ManualCode(
            'gnome-extension-enable',
            (l) => l.manualC14S15EnableExtCmd,
          ),
          ManualParagraph(
            (l) => l.manualC14S15T5(
              l.settingsLinuxPortalInputConnect,
              l.settingsAfterTranscription,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S15HotkeyHeading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC14S15H1(
              l.settingsDesktopShortcutAdd,
              l.settingsKeyboardShortcut,
            ),
          ),
          ManualParagraph((l) => l.manualC14S15H2(l.settingsKeyboardShortcut)),
          ManualParagraph((l) => l.manualC14S15H3),
          ManualParagraph((l) => l.manualC14S15H4),
          ManualParagraph((l) => l.manualC14S15G1),
          ManualParagraph((l) => l.manualC14S15G2),
          ManualParagraph((l) => l.manualC14S15G3),
          ManualParagraph((l) => l.manualC14S15G4),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S16Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.onboardingTriggerHotkeyConflictTitle),
          ManualParagraph((l) => l.manualC14S16B2(l.settingsAreaShortcuts)),
          ManualParagraph((l) => l.manualC14S16B3),
          ManualParagraph((l) => l.manualC14S16B4),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S17Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.settingsAutostartSyncFailed),
          ManualParagraph((l) => l.manualC14S17B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S18Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.settingsAutosaveErrorLocation),
          ManualParagraph((l) => l.manualC14S18B2(l.settingsAutosaveLabel)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S19Heading,
        blocks: <ManualBlock>[
          ManualNotice(
            (l) => l.settingsFactoryResetFailedMessage(l.factoryResetAreaDb),
          ),
          ManualParagraph((l) => l.manualC14S19B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S20Heading,
        blocks: <ManualBlock>[
          ManualNotice((l) => l.recordingGuardFailed),
          ManualParagraph((l) => l.manualC14S20B2(l.settingsAudio)),
          ManualParagraph((l) => l.manualC14S20B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S21Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S21B1(ltrIsolate('8 GB'))),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S22Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC14S22B1),
          ManualParagraph((l) => l.manualC14S22B2(l.settingsAreaShortcuts)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC14S23Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC14S23B1)],
      ),
    ],
  ),
  ManualChapter(
    slug: 'shortcuts',
    title: (l) => l.manualC15Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC15S1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC15S1B1(l.settingsAreaShortcuts)),
          ManualParagraph(
            (l) => l.manualC15S1B2(ltrIsolate('Cmd'), ltrIsolate('Ctrl')),
          ),
          ManualBullets(<ManualText>[
            (l) => l.manualC15S1B3I1,
            (l) => l.manualC15S1B3I2(ltrIsolate(mainShortcutLabel('?'))),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC15S2Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC15S2B1I1(ltrIsolate('Delete / Backspace')),
            (l) => l.manualC15S2B1I2(ltrIsolate('F')),
            (l) => l.manualC15S2B1I3(ltrIsolate(mainShortcutLabel('F'))),
            (l) => l.manualC15S2B1I4(ltrIsolate('Esc')),
            (l) => l.manualC15S2B1I5(ltrIsolate('Enter')),
            (l) => l.manualC15S2B1I6(ltrIsolate('Esc')),
            (l) => l.manualC15S2B1I7,
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC15S3Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC15S3B1I1(ltrIsolate('Delete / Backspace')),
            (l) => l.manualC15S3B1I2(ltrIsolate(mainShortcutLabel('N'))),
            (l) => l.manualC15S3B1I3(ltrIsolate(mainShortcutLabel('F'))),
            (l) =>
                l.manualC15S3B1I4(ltrIsolate(mainShortcutLabel('Shift+Enter'))),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC15S4Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC15S4B1I1(ltrIsolate('Delete / Backspace')),
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC15S5Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC15S5B1(ltrIsolate('Esc'), ltrIsolate('F12')),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualLangCycleHeading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualLangCycleB1)],
      ),
      ManualSection(
        heading: (l) => l.manualViewMemoryHeading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualViewMemoryB1(
              ltrIsolate(mainShortcutLabel('+')),
              ltrIsolate(mainShortcutLabel('-')),
              ltrIsolate(mainShortcutLabel('0')),
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC15S6Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC15S6B1),
          ManualBullets(<ManualText>[
            (l) => l.manualC15S6B2I1(ltrIsolate(mainShortcutLabel(','))),
            (l) => l.manualC15S6B2I2,
            (l) => l.manualC15S6B2I3,
            (l) => l.manualC15S6B2I4,
          ]),
          ManualParagraph((l) => l.manualC15S6B3),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualA11yHeading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualA11yB1),
          ManualParagraph((l) => l.manualA11yB2),
          ManualParagraph((l) => l.manualA11yB3),
        ],
      ),
    ],
  ),
  ManualChapter(
    slug: 'profiles',
    title: (l) => l.manualProfilesTitle,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualProfilesS1Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualProfilesS1Body),
          ManualBullets(<ManualText>[
            (l) => l.manualProfilesS1B1,
            (l) => l.manualProfilesS1B2,
          ]),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualProfilesS2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualProfilesS2Body),
          ManualTip((l) => l.manualProfilesS2Tip),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualProfilesS3Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualProfilesS3Body),
          ManualBullets(<ManualText>[
            (l) => l.manualProfilesS3Mac,
            (l) => l.manualProfilesS3Win,
            (l) => l.manualProfilesS3Linux,
          ]),
          ManualParagraph((l) => l.manualProfilesS3Recent),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualProfilesS4Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualProfilesS4Body)],
      ),
      ManualSection(
        heading: (l) => l.manualProfilesS5Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualProfilesS5Body)],
      ),
      ManualSection(
        heading: (l) => l.manualProfilesS6Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualProfilesS6Body)],
      ),
    ],
  ),
  ManualChapter(
    slug: 'feedback-support',
    title: (l) => l.manualC16Title,
    sections: <ManualSection>[
      ManualSection(
        heading: (l) => l.manualC16S1Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC16S1B1I1,
            (l) => l.manualC16S1B1I2,
            (l) => l.manualC16S1B1I3,
            (l) => l.manualC16S1B1I4,
          ]),
          ManualParagraph((l) => l.manualC16S1B2),
          ManualNotice((l) => l.feedbackErrorRateLimited),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC16S2Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC16S2B1(l.helpTabSupport)),
          ManualParagraph((l) => l.manualC16S2B2(l.helpTabSupport)),
          ManualParagraph(
            (l) => l.manualC16S2B3(
              l.overviewSupportAction,
              l.overviewAskLater,
              l.overviewAskNever,
              l.helpTabSupport,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC16S3Heading,
        blocks: <ManualBlock>[
          ManualParagraph(
            (l) => l.manualC16S3B1(
              l.settingsInterface,
              l.settingsReviewPromptRestore,
            ),
          ),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC16S4Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC16S4B1(l.helpTabFeedback)),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC16S5Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC16S5B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC16S6Heading,
        blocks: <ManualBlock>[ManualParagraph((l) => l.manualC16S6B1)],
      ),
      ManualSection(
        heading: (l) => l.manualC16S8Heading,
        blocks: <ManualBlock>[
          ManualParagraph((l) => l.manualC16S8B1),
          ManualParagraph((l) => l.manualC16S8B2),
        ],
      ),
      ManualSection(
        heading: (l) => l.manualC16S7Heading,
        blocks: <ManualBlock>[
          ManualBullets(<ManualText>[
            (l) => l.manualC16S7B1I1,
            (l) => l.manualC16S7B1I2,
            (l) => l.manualC16S7B1I3,
            (l) => l.manualC16S7B1I4,
            (l) => l.manualC16S7B1I5,
          ]),
          ManualParagraph((l) => l.manualC16S7B2),
        ],
      ),
    ],
  ),
];

/// A shortcut with the platform's own main modifier: Cmd on macOS, Ctrl on
/// Windows and Linux. The reference must not name Ctrl on a Mac (UIA-HLP-03).
String mainShortcutLabel(String key, {bool? mac}) {
  final isMac = mac ?? defaultTargetPlatform == TargetPlatform.macOS;
  return isMac ? 'Cmd+$key' : 'Ctrl+$key';
}
