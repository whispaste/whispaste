// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $HistoryEntriesTable extends HistoryEntries
    with TableInfo<$HistoryEntriesTable, HistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<double> durationSec = GeneratedColumn<double>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _processingDurationSecMeta =
      const VerificationMeta('processingDurationSec');
  @override
  late final GeneratedColumn<double> processingDurationSec =
      GeneratedColumn<double>(
        'processing_duration_sec',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.0),
      );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _languageHintMeta = const VerificationMeta(
    'languageHint',
  );
  @override
  late final GeneratedColumn<String> languageHint = GeneratedColumn<String>(
    'language_hint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('dictation'),
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isLocalMeta = const VerificationMeta(
    'isLocal',
  );
  @override
  late final GeneratedColumn<bool> isLocal = GeneratedColumn<bool>(
    'is_local',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_local" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _costUsdMeta = const VerificationMeta(
    'costUsd',
  );
  @override
  late final GeneratedColumn<double> costUsd = GeneratedColumn<double>(
    'cost_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titleEditedMeta = const VerificationMeta(
    'titleEdited',
  );
  @override
  late final GeneratedColumn<bool> titleEdited = GeneratedColumn<bool>(
    'title_edited',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("title_edited" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorSlotMeta = const VerificationMeta(
    'colorSlot',
  );
  @override
  late final GeneratedColumn<int> colorSlot = GeneratedColumn<int>(
    'color_slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _smartModeEditedContentMeta =
      const VerificationMeta('smartModeEditedContent');
  @override
  late final GeneratedColumn<String> smartModeEditedContent =
      GeneratedColumn<String>(
        'smart_mode_edited_content',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _originalTranscriptMeta =
      const VerificationMeta('originalTranscript');
  @override
  late final GeneratedColumn<String> originalTranscript =
      GeneratedColumn<String>(
        'original_transcript',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _targetAppMeta = const VerificationMeta(
    'targetApp',
  );
  @override
  late final GeneratedColumn<String> targetApp = GeneratedColumn<String>(
    'target_app',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smartModeInputMeta = const VerificationMeta(
    'smartModeInput',
  );
  @override
  late final GeneratedColumn<String> smartModeInput = GeneratedColumn<String>(
    'smart_mode_input',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smartModeOutputMeta = const VerificationMeta(
    'smartModeOutput',
  );
  @override
  late final GeneratedColumn<String> smartModeOutput = GeneratedColumn<String>(
    'smart_mode_output',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smartModeAppliedMeta = const VerificationMeta(
    'smartModeApplied',
  );
  @override
  late final GeneratedColumn<bool> smartModeApplied = GeneratedColumn<bool>(
    'smart_mode_applied',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("smart_mode_applied" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    title,
    timestamp,
    durationSec,
    processingDurationSec,
    language,
    languageHint,
    tags,
    pinned,
    source,
    model,
    isLocal,
    costUsd,
    archived,
    titleEdited,
    deletedAt,
    colorSlot,
    smartModeEditedContent,
    originalTranscript,
    targetApp,
    smartModeInput,
    smartModeOutput,
    smartModeApplied,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('processing_duration_sec')) {
      context.handle(
        _processingDurationSecMeta,
        processingDurationSec.isAcceptableOrUnknown(
          data['processing_duration_sec']!,
          _processingDurationSecMeta,
        ),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('language_hint')) {
      context.handle(
        _languageHintMeta,
        languageHint.isAcceptableOrUnknown(
          data['language_hint']!,
          _languageHintMeta,
        ),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('is_local')) {
      context.handle(
        _isLocalMeta,
        isLocal.isAcceptableOrUnknown(data['is_local']!, _isLocalMeta),
      );
    }
    if (data.containsKey('cost_usd')) {
      context.handle(
        _costUsdMeta,
        costUsd.isAcceptableOrUnknown(data['cost_usd']!, _costUsdMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('title_edited')) {
      context.handle(
        _titleEditedMeta,
        titleEdited.isAcceptableOrUnknown(
          data['title_edited']!,
          _titleEditedMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('color_slot')) {
      context.handle(
        _colorSlotMeta,
        colorSlot.isAcceptableOrUnknown(data['color_slot']!, _colorSlotMeta),
      );
    }
    if (data.containsKey('smart_mode_edited_content')) {
      context.handle(
        _smartModeEditedContentMeta,
        smartModeEditedContent.isAcceptableOrUnknown(
          data['smart_mode_edited_content']!,
          _smartModeEditedContentMeta,
        ),
      );
    }
    if (data.containsKey('original_transcript')) {
      context.handle(
        _originalTranscriptMeta,
        originalTranscript.isAcceptableOrUnknown(
          data['original_transcript']!,
          _originalTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('target_app')) {
      context.handle(
        _targetAppMeta,
        targetApp.isAcceptableOrUnknown(data['target_app']!, _targetAppMeta),
      );
    }
    if (data.containsKey('smart_mode_input')) {
      context.handle(
        _smartModeInputMeta,
        smartModeInput.isAcceptableOrUnknown(
          data['smart_mode_input']!,
          _smartModeInputMeta,
        ),
      );
    }
    if (data.containsKey('smart_mode_output')) {
      context.handle(
        _smartModeOutputMeta,
        smartModeOutput.isAcceptableOrUnknown(
          data['smart_mode_output']!,
          _smartModeOutputMeta,
        ),
      );
    }
    if (data.containsKey('smart_mode_applied')) {
      context.handle(
        _smartModeAppliedMeta,
        smartModeApplied.isAcceptableOrUnknown(
          data['smart_mode_applied']!,
          _smartModeAppliedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}duration_sec'],
      )!,
      processingDurationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}processing_duration_sec'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      languageHint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language_hint'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      isLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_local'],
      )!,
      costUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost_usd'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      titleEdited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}title_edited'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      colorSlot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_slot'],
      )!,
      smartModeEditedContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smart_mode_edited_content'],
      ),
      originalTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_transcript'],
      ),
      targetApp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_app'],
      ),
      smartModeInput: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smart_mode_input'],
      ),
      smartModeOutput: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smart_mode_output'],
      ),
      smartModeApplied: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}smart_mode_applied'],
      ),
    );
  }

  @override
  $HistoryEntriesTable createAlias(String alias) {
    return $HistoryEntriesTable(attachedDatabase, alias);
  }
}

class HistoryEntry extends DataClass implements Insertable<HistoryEntry> {
  final String id;
  final String content;
  final String title;
  final DateTime timestamp;
  final double durationSec;
  final double processingDurationSec;
  final String language;

  /// Language the engine detected for an `auto` recording (DEV-132); empty
  /// when unknown. Read by retroactive Smart Mode for the fact guard's name
  /// rule. Stored in this existing column, so no migration was needed.
  final String languageHint;
  final String tags;
  final bool pinned;
  final String source;
  final String model;
  final bool isLocal;
  final double costUsd;
  final bool archived;
  final bool titleEdited;
  final DateTime? deletedAt;

  /// Decorative color slot (v18) — an index into the 8 rotating category
  /// hues (`WpCategorySlot.categories`, index 0–7). Assigned once at real
  /// creation time in [DriftRecordingStore.save] and never touched again;
  /// see `insertHistoryEntry` in `database.dart`. Purely decorative, not a
  /// content category — the 9th slot, `WpCategorySlot.neutral`, is never a
  /// value here because there is no "uncategorized" case for this rotation.
  final int colorSlot;

  /// Smart Mode's "current edited version" (v22, Smart-Mode-v2 ticket 05) —
  /// overwritten in place by every preset application (live or retroactive),
  /// never a version stack. `null` means no preset has ever been applied to
  /// this entry; [content] (the raw transcript) is never touched by Smart
  /// Mode and stays the source of truth for the "raw" view.
  final String? smartModeEditedContent;

  /// Original transcript before live Smart-Mode refinement / text
  /// replacements were applied (v24, ticket 12). `null` for entries where
  /// no transform changed the transcript, or for pre-v24 entries — never
  /// backfilled. [content] stays the final, post-transform text; this
  /// column only exists so the detail panel can show what was originally
  /// dictated when it actually differs from [content].
  final String? originalTranscript;

  /// Bundle ID (macOS) / process identifier (Windows) of the app the
  /// dictation was pasted into, captured via the same auto-paste target
  /// lookup the blocklist uses (v24, ticket 12). `null` when unavailable
  /// (Linux, no target captured, permission missing, or pre-v24 entries).
  final String? targetApp;

  /// Exact input of the Smart-Mode run that produced [content] (v27). `null`
  /// when that input equals [originalTranscript], which is then the input
  /// (BIZ-25: the raw text is stored once).
  final String? smartModeInput;

  /// Result of that Smart-Mode run while an undo is in effect (v27): the
  /// content holds the input, and this holds the result for a restore. `null`
  /// when the entry shows the result.
  final String? smartModeOutput;

  /// Whether a Smart-Mode run changed this entry and no manual edit or
  /// re-transcription has happened since (v27). This marker is what makes an
  /// entry undoable; without it, a manual edit could be mistaken for a run.
  final bool? smartModeApplied;
  const HistoryEntry({
    required this.id,
    required this.content,
    required this.title,
    required this.timestamp,
    required this.durationSec,
    required this.processingDurationSec,
    required this.language,
    required this.languageHint,
    required this.tags,
    required this.pinned,
    required this.source,
    required this.model,
    required this.isLocal,
    required this.costUsd,
    required this.archived,
    required this.titleEdited,
    this.deletedAt,
    required this.colorSlot,
    this.smartModeEditedContent,
    this.originalTranscript,
    this.targetApp,
    this.smartModeInput,
    this.smartModeOutput,
    this.smartModeApplied,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    map['title'] = Variable<String>(title);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['duration_sec'] = Variable<double>(durationSec);
    map['processing_duration_sec'] = Variable<double>(processingDurationSec);
    map['language'] = Variable<String>(language);
    map['language_hint'] = Variable<String>(languageHint);
    map['tags'] = Variable<String>(tags);
    map['pinned'] = Variable<bool>(pinned);
    map['source'] = Variable<String>(source);
    map['model'] = Variable<String>(model);
    map['is_local'] = Variable<bool>(isLocal);
    map['cost_usd'] = Variable<double>(costUsd);
    map['archived'] = Variable<bool>(archived);
    map['title_edited'] = Variable<bool>(titleEdited);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['color_slot'] = Variable<int>(colorSlot);
    if (!nullToAbsent || smartModeEditedContent != null) {
      map['smart_mode_edited_content'] = Variable<String>(
        smartModeEditedContent,
      );
    }
    if (!nullToAbsent || originalTranscript != null) {
      map['original_transcript'] = Variable<String>(originalTranscript);
    }
    if (!nullToAbsent || targetApp != null) {
      map['target_app'] = Variable<String>(targetApp);
    }
    if (!nullToAbsent || smartModeInput != null) {
      map['smart_mode_input'] = Variable<String>(smartModeInput);
    }
    if (!nullToAbsent || smartModeOutput != null) {
      map['smart_mode_output'] = Variable<String>(smartModeOutput);
    }
    if (!nullToAbsent || smartModeApplied != null) {
      map['smart_mode_applied'] = Variable<bool>(smartModeApplied);
    }
    return map;
  }

  HistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return HistoryEntriesCompanion(
      id: Value(id),
      content: Value(content),
      title: Value(title),
      timestamp: Value(timestamp),
      durationSec: Value(durationSec),
      processingDurationSec: Value(processingDurationSec),
      language: Value(language),
      languageHint: Value(languageHint),
      tags: Value(tags),
      pinned: Value(pinned),
      source: Value(source),
      model: Value(model),
      isLocal: Value(isLocal),
      costUsd: Value(costUsd),
      archived: Value(archived),
      titleEdited: Value(titleEdited),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      colorSlot: Value(colorSlot),
      smartModeEditedContent: smartModeEditedContent == null && nullToAbsent
          ? const Value.absent()
          : Value(smartModeEditedContent),
      originalTranscript: originalTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(originalTranscript),
      targetApp: targetApp == null && nullToAbsent
          ? const Value.absent()
          : Value(targetApp),
      smartModeInput: smartModeInput == null && nullToAbsent
          ? const Value.absent()
          : Value(smartModeInput),
      smartModeOutput: smartModeOutput == null && nullToAbsent
          ? const Value.absent()
          : Value(smartModeOutput),
      smartModeApplied: smartModeApplied == null && nullToAbsent
          ? const Value.absent()
          : Value(smartModeApplied),
    );
  }

  factory HistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryEntry(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      title: serializer.fromJson<String>(json['title']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      durationSec: serializer.fromJson<double>(json['durationSec']),
      processingDurationSec: serializer.fromJson<double>(
        json['processingDurationSec'],
      ),
      language: serializer.fromJson<String>(json['language']),
      languageHint: serializer.fromJson<String>(json['languageHint']),
      tags: serializer.fromJson<String>(json['tags']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      source: serializer.fromJson<String>(json['source']),
      model: serializer.fromJson<String>(json['model']),
      isLocal: serializer.fromJson<bool>(json['isLocal']),
      costUsd: serializer.fromJson<double>(json['costUsd']),
      archived: serializer.fromJson<bool>(json['archived']),
      titleEdited: serializer.fromJson<bool>(json['titleEdited']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      colorSlot: serializer.fromJson<int>(json['colorSlot']),
      smartModeEditedContent: serializer.fromJson<String?>(
        json['smartModeEditedContent'],
      ),
      originalTranscript: serializer.fromJson<String?>(
        json['originalTranscript'],
      ),
      targetApp: serializer.fromJson<String?>(json['targetApp']),
      smartModeInput: serializer.fromJson<String?>(json['smartModeInput']),
      smartModeOutput: serializer.fromJson<String?>(json['smartModeOutput']),
      smartModeApplied: serializer.fromJson<bool?>(json['smartModeApplied']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'title': serializer.toJson<String>(title),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'durationSec': serializer.toJson<double>(durationSec),
      'processingDurationSec': serializer.toJson<double>(processingDurationSec),
      'language': serializer.toJson<String>(language),
      'languageHint': serializer.toJson<String>(languageHint),
      'tags': serializer.toJson<String>(tags),
      'pinned': serializer.toJson<bool>(pinned),
      'source': serializer.toJson<String>(source),
      'model': serializer.toJson<String>(model),
      'isLocal': serializer.toJson<bool>(isLocal),
      'costUsd': serializer.toJson<double>(costUsd),
      'archived': serializer.toJson<bool>(archived),
      'titleEdited': serializer.toJson<bool>(titleEdited),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'colorSlot': serializer.toJson<int>(colorSlot),
      'smartModeEditedContent': serializer.toJson<String?>(
        smartModeEditedContent,
      ),
      'originalTranscript': serializer.toJson<String?>(originalTranscript),
      'targetApp': serializer.toJson<String?>(targetApp),
      'smartModeInput': serializer.toJson<String?>(smartModeInput),
      'smartModeOutput': serializer.toJson<String?>(smartModeOutput),
      'smartModeApplied': serializer.toJson<bool?>(smartModeApplied),
    };
  }

  HistoryEntry copyWith({
    String? id,
    String? content,
    String? title,
    DateTime? timestamp,
    double? durationSec,
    double? processingDurationSec,
    String? language,
    String? languageHint,
    String? tags,
    bool? pinned,
    String? source,
    String? model,
    bool? isLocal,
    double? costUsd,
    bool? archived,
    bool? titleEdited,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? colorSlot,
    Value<String?> smartModeEditedContent = const Value.absent(),
    Value<String?> originalTranscript = const Value.absent(),
    Value<String?> targetApp = const Value.absent(),
    Value<String?> smartModeInput = const Value.absent(),
    Value<String?> smartModeOutput = const Value.absent(),
    Value<bool?> smartModeApplied = const Value.absent(),
  }) => HistoryEntry(
    id: id ?? this.id,
    content: content ?? this.content,
    title: title ?? this.title,
    timestamp: timestamp ?? this.timestamp,
    durationSec: durationSec ?? this.durationSec,
    processingDurationSec: processingDurationSec ?? this.processingDurationSec,
    language: language ?? this.language,
    languageHint: languageHint ?? this.languageHint,
    tags: tags ?? this.tags,
    pinned: pinned ?? this.pinned,
    source: source ?? this.source,
    model: model ?? this.model,
    isLocal: isLocal ?? this.isLocal,
    costUsd: costUsd ?? this.costUsd,
    archived: archived ?? this.archived,
    titleEdited: titleEdited ?? this.titleEdited,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    colorSlot: colorSlot ?? this.colorSlot,
    smartModeEditedContent: smartModeEditedContent.present
        ? smartModeEditedContent.value
        : this.smartModeEditedContent,
    originalTranscript: originalTranscript.present
        ? originalTranscript.value
        : this.originalTranscript,
    targetApp: targetApp.present ? targetApp.value : this.targetApp,
    smartModeInput: smartModeInput.present
        ? smartModeInput.value
        : this.smartModeInput,
    smartModeOutput: smartModeOutput.present
        ? smartModeOutput.value
        : this.smartModeOutput,
    smartModeApplied: smartModeApplied.present
        ? smartModeApplied.value
        : this.smartModeApplied,
  );
  HistoryEntry copyWithCompanion(HistoryEntriesCompanion data) {
    return HistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      title: data.title.present ? data.title.value : this.title,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      processingDurationSec: data.processingDurationSec.present
          ? data.processingDurationSec.value
          : this.processingDurationSec,
      language: data.language.present ? data.language.value : this.language,
      languageHint: data.languageHint.present
          ? data.languageHint.value
          : this.languageHint,
      tags: data.tags.present ? data.tags.value : this.tags,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      source: data.source.present ? data.source.value : this.source,
      model: data.model.present ? data.model.value : this.model,
      isLocal: data.isLocal.present ? data.isLocal.value : this.isLocal,
      costUsd: data.costUsd.present ? data.costUsd.value : this.costUsd,
      archived: data.archived.present ? data.archived.value : this.archived,
      titleEdited: data.titleEdited.present
          ? data.titleEdited.value
          : this.titleEdited,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      colorSlot: data.colorSlot.present ? data.colorSlot.value : this.colorSlot,
      smartModeEditedContent: data.smartModeEditedContent.present
          ? data.smartModeEditedContent.value
          : this.smartModeEditedContent,
      originalTranscript: data.originalTranscript.present
          ? data.originalTranscript.value
          : this.originalTranscript,
      targetApp: data.targetApp.present ? data.targetApp.value : this.targetApp,
      smartModeInput: data.smartModeInput.present
          ? data.smartModeInput.value
          : this.smartModeInput,
      smartModeOutput: data.smartModeOutput.present
          ? data.smartModeOutput.value
          : this.smartModeOutput,
      smartModeApplied: data.smartModeApplied.present
          ? data.smartModeApplied.value
          : this.smartModeApplied,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntry(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('title: $title, ')
          ..write('timestamp: $timestamp, ')
          ..write('durationSec: $durationSec, ')
          ..write('processingDurationSec: $processingDurationSec, ')
          ..write('language: $language, ')
          ..write('languageHint: $languageHint, ')
          ..write('tags: $tags, ')
          ..write('pinned: $pinned, ')
          ..write('source: $source, ')
          ..write('model: $model, ')
          ..write('isLocal: $isLocal, ')
          ..write('costUsd: $costUsd, ')
          ..write('archived: $archived, ')
          ..write('titleEdited: $titleEdited, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('colorSlot: $colorSlot, ')
          ..write('smartModeEditedContent: $smartModeEditedContent, ')
          ..write('originalTranscript: $originalTranscript, ')
          ..write('targetApp: $targetApp, ')
          ..write('smartModeInput: $smartModeInput, ')
          ..write('smartModeOutput: $smartModeOutput, ')
          ..write('smartModeApplied: $smartModeApplied')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    content,
    title,
    timestamp,
    durationSec,
    processingDurationSec,
    language,
    languageHint,
    tags,
    pinned,
    source,
    model,
    isLocal,
    costUsd,
    archived,
    titleEdited,
    deletedAt,
    colorSlot,
    smartModeEditedContent,
    originalTranscript,
    targetApp,
    smartModeInput,
    smartModeOutput,
    smartModeApplied,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry &&
          other.id == this.id &&
          other.content == this.content &&
          other.title == this.title &&
          other.timestamp == this.timestamp &&
          other.durationSec == this.durationSec &&
          other.processingDurationSec == this.processingDurationSec &&
          other.language == this.language &&
          other.languageHint == this.languageHint &&
          other.tags == this.tags &&
          other.pinned == this.pinned &&
          other.source == this.source &&
          other.model == this.model &&
          other.isLocal == this.isLocal &&
          other.costUsd == this.costUsd &&
          other.archived == this.archived &&
          other.titleEdited == this.titleEdited &&
          other.deletedAt == this.deletedAt &&
          other.colorSlot == this.colorSlot &&
          other.smartModeEditedContent == this.smartModeEditedContent &&
          other.originalTranscript == this.originalTranscript &&
          other.targetApp == this.targetApp &&
          other.smartModeInput == this.smartModeInput &&
          other.smartModeOutput == this.smartModeOutput &&
          other.smartModeApplied == this.smartModeApplied);
}

class HistoryEntriesCompanion extends UpdateCompanion<HistoryEntry> {
  final Value<String> id;
  final Value<String> content;
  final Value<String> title;
  final Value<DateTime> timestamp;
  final Value<double> durationSec;
  final Value<double> processingDurationSec;
  final Value<String> language;
  final Value<String> languageHint;
  final Value<String> tags;
  final Value<bool> pinned;
  final Value<String> source;
  final Value<String> model;
  final Value<bool> isLocal;
  final Value<double> costUsd;
  final Value<bool> archived;
  final Value<bool> titleEdited;
  final Value<DateTime?> deletedAt;
  final Value<int> colorSlot;
  final Value<String?> smartModeEditedContent;
  final Value<String?> originalTranscript;
  final Value<String?> targetApp;
  final Value<String?> smartModeInput;
  final Value<String?> smartModeOutput;
  final Value<bool?> smartModeApplied;
  final Value<int> rowid;
  const HistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.title = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.processingDurationSec = const Value.absent(),
    this.language = const Value.absent(),
    this.languageHint = const Value.absent(),
    this.tags = const Value.absent(),
    this.pinned = const Value.absent(),
    this.source = const Value.absent(),
    this.model = const Value.absent(),
    this.isLocal = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.archived = const Value.absent(),
    this.titleEdited = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.colorSlot = const Value.absent(),
    this.smartModeEditedContent = const Value.absent(),
    this.originalTranscript = const Value.absent(),
    this.targetApp = const Value.absent(),
    this.smartModeInput = const Value.absent(),
    this.smartModeOutput = const Value.absent(),
    this.smartModeApplied = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryEntriesCompanion.insert({
    required String id,
    this.content = const Value.absent(),
    this.title = const Value.absent(),
    required DateTime timestamp,
    this.durationSec = const Value.absent(),
    this.processingDurationSec = const Value.absent(),
    this.language = const Value.absent(),
    this.languageHint = const Value.absent(),
    this.tags = const Value.absent(),
    this.pinned = const Value.absent(),
    this.source = const Value.absent(),
    this.model = const Value.absent(),
    this.isLocal = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.archived = const Value.absent(),
    this.titleEdited = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.colorSlot = const Value.absent(),
    this.smartModeEditedContent = const Value.absent(),
    this.originalTranscript = const Value.absent(),
    this.targetApp = const Value.absent(),
    this.smartModeInput = const Value.absent(),
    this.smartModeOutput = const Value.absent(),
    this.smartModeApplied = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       timestamp = Value(timestamp);
  static Insertable<HistoryEntry> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? title,
    Expression<DateTime>? timestamp,
    Expression<double>? durationSec,
    Expression<double>? processingDurationSec,
    Expression<String>? language,
    Expression<String>? languageHint,
    Expression<String>? tags,
    Expression<bool>? pinned,
    Expression<String>? source,
    Expression<String>? model,
    Expression<bool>? isLocal,
    Expression<double>? costUsd,
    Expression<bool>? archived,
    Expression<bool>? titleEdited,
    Expression<DateTime>? deletedAt,
    Expression<int>? colorSlot,
    Expression<String>? smartModeEditedContent,
    Expression<String>? originalTranscript,
    Expression<String>? targetApp,
    Expression<String>? smartModeInput,
    Expression<String>? smartModeOutput,
    Expression<bool>? smartModeApplied,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (title != null) 'title': title,
      if (timestamp != null) 'timestamp': timestamp,
      if (durationSec != null) 'duration_sec': durationSec,
      if (processingDurationSec != null)
        'processing_duration_sec': processingDurationSec,
      if (language != null) 'language': language,
      if (languageHint != null) 'language_hint': languageHint,
      if (tags != null) 'tags': tags,
      if (pinned != null) 'pinned': pinned,
      if (source != null) 'source': source,
      if (model != null) 'model': model,
      if (isLocal != null) 'is_local': isLocal,
      if (costUsd != null) 'cost_usd': costUsd,
      if (archived != null) 'archived': archived,
      if (titleEdited != null) 'title_edited': titleEdited,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (colorSlot != null) 'color_slot': colorSlot,
      if (smartModeEditedContent != null)
        'smart_mode_edited_content': smartModeEditedContent,
      if (originalTranscript != null) 'original_transcript': originalTranscript,
      if (targetApp != null) 'target_app': targetApp,
      if (smartModeInput != null) 'smart_mode_input': smartModeInput,
      if (smartModeOutput != null) 'smart_mode_output': smartModeOutput,
      if (smartModeApplied != null) 'smart_mode_applied': smartModeApplied,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<String>? title,
    Value<DateTime>? timestamp,
    Value<double>? durationSec,
    Value<double>? processingDurationSec,
    Value<String>? language,
    Value<String>? languageHint,
    Value<String>? tags,
    Value<bool>? pinned,
    Value<String>? source,
    Value<String>? model,
    Value<bool>? isLocal,
    Value<double>? costUsd,
    Value<bool>? archived,
    Value<bool>? titleEdited,
    Value<DateTime?>? deletedAt,
    Value<int>? colorSlot,
    Value<String?>? smartModeEditedContent,
    Value<String?>? originalTranscript,
    Value<String?>? targetApp,
    Value<String?>? smartModeInput,
    Value<String?>? smartModeOutput,
    Value<bool?>? smartModeApplied,
    Value<int>? rowid,
  }) {
    return HistoryEntriesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      title: title ?? this.title,
      timestamp: timestamp ?? this.timestamp,
      durationSec: durationSec ?? this.durationSec,
      processingDurationSec:
          processingDurationSec ?? this.processingDurationSec,
      language: language ?? this.language,
      languageHint: languageHint ?? this.languageHint,
      tags: tags ?? this.tags,
      pinned: pinned ?? this.pinned,
      source: source ?? this.source,
      model: model ?? this.model,
      isLocal: isLocal ?? this.isLocal,
      costUsd: costUsd ?? this.costUsd,
      archived: archived ?? this.archived,
      titleEdited: titleEdited ?? this.titleEdited,
      deletedAt: deletedAt ?? this.deletedAt,
      colorSlot: colorSlot ?? this.colorSlot,
      smartModeEditedContent:
          smartModeEditedContent ?? this.smartModeEditedContent,
      originalTranscript: originalTranscript ?? this.originalTranscript,
      targetApp: targetApp ?? this.targetApp,
      smartModeInput: smartModeInput ?? this.smartModeInput,
      smartModeOutput: smartModeOutput ?? this.smartModeOutput,
      smartModeApplied: smartModeApplied ?? this.smartModeApplied,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<double>(durationSec.value);
    }
    if (processingDurationSec.present) {
      map['processing_duration_sec'] = Variable<double>(
        processingDurationSec.value,
      );
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (languageHint.present) {
      map['language_hint'] = Variable<String>(languageHint.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (isLocal.present) {
      map['is_local'] = Variable<bool>(isLocal.value);
    }
    if (costUsd.present) {
      map['cost_usd'] = Variable<double>(costUsd.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (titleEdited.present) {
      map['title_edited'] = Variable<bool>(titleEdited.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (colorSlot.present) {
      map['color_slot'] = Variable<int>(colorSlot.value);
    }
    if (smartModeEditedContent.present) {
      map['smart_mode_edited_content'] = Variable<String>(
        smartModeEditedContent.value,
      );
    }
    if (originalTranscript.present) {
      map['original_transcript'] = Variable<String>(originalTranscript.value);
    }
    if (targetApp.present) {
      map['target_app'] = Variable<String>(targetApp.value);
    }
    if (smartModeInput.present) {
      map['smart_mode_input'] = Variable<String>(smartModeInput.value);
    }
    if (smartModeOutput.present) {
      map['smart_mode_output'] = Variable<String>(smartModeOutput.value);
    }
    if (smartModeApplied.present) {
      map['smart_mode_applied'] = Variable<bool>(smartModeApplied.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('title: $title, ')
          ..write('timestamp: $timestamp, ')
          ..write('durationSec: $durationSec, ')
          ..write('processingDurationSec: $processingDurationSec, ')
          ..write('language: $language, ')
          ..write('languageHint: $languageHint, ')
          ..write('tags: $tags, ')
          ..write('pinned: $pinned, ')
          ..write('source: $source, ')
          ..write('model: $model, ')
          ..write('isLocal: $isLocal, ')
          ..write('costUsd: $costUsd, ')
          ..write('archived: $archived, ')
          ..write('titleEdited: $titleEdited, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('colorSlot: $colorSlot, ')
          ..write('smartModeEditedContent: $smartModeEditedContent, ')
          ..write('originalTranscript: $originalTranscript, ')
          ..write('targetApp: $targetApp, ')
          ..write('smartModeInput: $smartModeInput, ')
          ..write('smartModeOutput: $smartModeOutput, ')
          ..write('smartModeApplied: $smartModeApplied, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyStatsTable extends DailyStats
    with TableInfo<$DailyStatsTable, DailyStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isLocalMeta = const VerificationMeta(
    'isLocal',
  );
  @override
  late final GeneratedColumn<bool> isLocal = GeneratedColumn<bool>(
    'is_local',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_local" IN (0, 1))',
    ),
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalDurationSecMeta = const VerificationMeta(
    'totalDurationSec',
  );
  @override
  late final GeneratedColumn<double> totalDurationSec = GeneratedColumn<double>(
    'total_duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _totalProcessingSecMeta =
      const VerificationMeta('totalProcessingSec');
  @override
  late final GeneratedColumn<double> totalProcessingSec =
      GeneratedColumn<double>(
        'total_processing_sec',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.0),
      );
  static const VerificationMeta _totalWordsMeta = const VerificationMeta(
    'totalWords',
  );
  @override
  late final GeneratedColumn<int> totalWords = GeneratedColumn<int>(
    'total_words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalCostUsdMeta = const VerificationMeta(
    'totalCostUsd',
  );
  @override
  late final GeneratedColumn<double> totalCostUsd = GeneratedColumn<double>(
    'total_cost_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _durUnder15sMeta = const VerificationMeta(
    'durUnder15s',
  );
  @override
  late final GeneratedColumn<int> durUnder15s = GeneratedColumn<int>(
    'dur_under15s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dur15To30sMeta = const VerificationMeta(
    'dur15To30s',
  );
  @override
  late final GeneratedColumn<int> dur15To30s = GeneratedColumn<int>(
    'dur15_to30s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dur30To60sMeta = const VerificationMeta(
    'dur30To60s',
  );
  @override
  late final GeneratedColumn<int> dur30To60s = GeneratedColumn<int>(
    'dur30_to60s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dur1To3mMeta = const VerificationMeta(
    'dur1To3m',
  );
  @override
  late final GeneratedColumn<int> dur1To3m = GeneratedColumn<int>(
    'dur1_to3m',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durOver3mMeta = const VerificationMeta(
    'durOver3m',
  );
  @override
  late final GeneratedColumn<int> durOver3m = GeneratedColumn<int>(
    'dur_over3m',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    model,
    isLocal,
    count,
    totalDurationSec,
    totalProcessingSec,
    totalWords,
    totalCostUsd,
    durUnder15s,
    dur15To30s,
    dur30To60s,
    dur1To3m,
    durOver3m,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyStat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('is_local')) {
      context.handle(
        _isLocalMeta,
        isLocal.isAcceptableOrUnknown(data['is_local']!, _isLocalMeta),
      );
    } else if (isInserting) {
      context.missing(_isLocalMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('total_duration_sec')) {
      context.handle(
        _totalDurationSecMeta,
        totalDurationSec.isAcceptableOrUnknown(
          data['total_duration_sec']!,
          _totalDurationSecMeta,
        ),
      );
    }
    if (data.containsKey('total_processing_sec')) {
      context.handle(
        _totalProcessingSecMeta,
        totalProcessingSec.isAcceptableOrUnknown(
          data['total_processing_sec']!,
          _totalProcessingSecMeta,
        ),
      );
    }
    if (data.containsKey('total_words')) {
      context.handle(
        _totalWordsMeta,
        totalWords.isAcceptableOrUnknown(data['total_words']!, _totalWordsMeta),
      );
    }
    if (data.containsKey('total_cost_usd')) {
      context.handle(
        _totalCostUsdMeta,
        totalCostUsd.isAcceptableOrUnknown(
          data['total_cost_usd']!,
          _totalCostUsdMeta,
        ),
      );
    }
    if (data.containsKey('dur_under15s')) {
      context.handle(
        _durUnder15sMeta,
        durUnder15s.isAcceptableOrUnknown(
          data['dur_under15s']!,
          _durUnder15sMeta,
        ),
      );
    }
    if (data.containsKey('dur15_to30s')) {
      context.handle(
        _dur15To30sMeta,
        dur15To30s.isAcceptableOrUnknown(data['dur15_to30s']!, _dur15To30sMeta),
      );
    }
    if (data.containsKey('dur30_to60s')) {
      context.handle(
        _dur30To60sMeta,
        dur30To60s.isAcceptableOrUnknown(data['dur30_to60s']!, _dur30To60sMeta),
      );
    }
    if (data.containsKey('dur1_to3m')) {
      context.handle(
        _dur1To3mMeta,
        dur1To3m.isAcceptableOrUnknown(data['dur1_to3m']!, _dur1To3mMeta),
      );
    }
    if (data.containsKey('dur_over3m')) {
      context.handle(
        _durOver3mMeta,
        durOver3m.isAcceptableOrUnknown(data['dur_over3m']!, _durOver3mMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date, model, isLocal};
  @override
  DailyStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyStat(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      isLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_local'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      totalDurationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_duration_sec'],
      )!,
      totalProcessingSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_processing_sec'],
      )!,
      totalWords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_words'],
      )!,
      totalCostUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_cost_usd'],
      )!,
      durUnder15s: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur_under15s'],
      )!,
      dur15To30s: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur15_to30s'],
      )!,
      dur30To60s: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur30_to60s'],
      )!,
      dur1To3m: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur1_to3m'],
      )!,
      durOver3m: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur_over3m'],
      )!,
    );
  }

  @override
  $DailyStatsTable createAlias(String alias) {
    return $DailyStatsTable(attachedDatabase, alias);
  }
}

class DailyStat extends DataClass implements Insertable<DailyStat> {
  final String date;
  final String model;
  final bool isLocal;
  final int count;
  final double totalDurationSec;
  final double totalProcessingSec;
  final int totalWords;
  final double totalCostUsd;
  final int durUnder15s;
  final int dur15To30s;
  final int dur30To60s;
  final int dur1To3m;
  final int durOver3m;
  const DailyStat({
    required this.date,
    required this.model,
    required this.isLocal,
    required this.count,
    required this.totalDurationSec,
    required this.totalProcessingSec,
    required this.totalWords,
    required this.totalCostUsd,
    required this.durUnder15s,
    required this.dur15To30s,
    required this.dur30To60s,
    required this.dur1To3m,
    required this.durOver3m,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['model'] = Variable<String>(model);
    map['is_local'] = Variable<bool>(isLocal);
    map['count'] = Variable<int>(count);
    map['total_duration_sec'] = Variable<double>(totalDurationSec);
    map['total_processing_sec'] = Variable<double>(totalProcessingSec);
    map['total_words'] = Variable<int>(totalWords);
    map['total_cost_usd'] = Variable<double>(totalCostUsd);
    map['dur_under15s'] = Variable<int>(durUnder15s);
    map['dur15_to30s'] = Variable<int>(dur15To30s);
    map['dur30_to60s'] = Variable<int>(dur30To60s);
    map['dur1_to3m'] = Variable<int>(dur1To3m);
    map['dur_over3m'] = Variable<int>(durOver3m);
    return map;
  }

  DailyStatsCompanion toCompanion(bool nullToAbsent) {
    return DailyStatsCompanion(
      date: Value(date),
      model: Value(model),
      isLocal: Value(isLocal),
      count: Value(count),
      totalDurationSec: Value(totalDurationSec),
      totalProcessingSec: Value(totalProcessingSec),
      totalWords: Value(totalWords),
      totalCostUsd: Value(totalCostUsd),
      durUnder15s: Value(durUnder15s),
      dur15To30s: Value(dur15To30s),
      dur30To60s: Value(dur30To60s),
      dur1To3m: Value(dur1To3m),
      durOver3m: Value(durOver3m),
    );
  }

  factory DailyStat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyStat(
      date: serializer.fromJson<String>(json['date']),
      model: serializer.fromJson<String>(json['model']),
      isLocal: serializer.fromJson<bool>(json['isLocal']),
      count: serializer.fromJson<int>(json['count']),
      totalDurationSec: serializer.fromJson<double>(json['totalDurationSec']),
      totalProcessingSec: serializer.fromJson<double>(
        json['totalProcessingSec'],
      ),
      totalWords: serializer.fromJson<int>(json['totalWords']),
      totalCostUsd: serializer.fromJson<double>(json['totalCostUsd']),
      durUnder15s: serializer.fromJson<int>(json['durUnder15s']),
      dur15To30s: serializer.fromJson<int>(json['dur15To30s']),
      dur30To60s: serializer.fromJson<int>(json['dur30To60s']),
      dur1To3m: serializer.fromJson<int>(json['dur1To3m']),
      durOver3m: serializer.fromJson<int>(json['durOver3m']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'model': serializer.toJson<String>(model),
      'isLocal': serializer.toJson<bool>(isLocal),
      'count': serializer.toJson<int>(count),
      'totalDurationSec': serializer.toJson<double>(totalDurationSec),
      'totalProcessingSec': serializer.toJson<double>(totalProcessingSec),
      'totalWords': serializer.toJson<int>(totalWords),
      'totalCostUsd': serializer.toJson<double>(totalCostUsd),
      'durUnder15s': serializer.toJson<int>(durUnder15s),
      'dur15To30s': serializer.toJson<int>(dur15To30s),
      'dur30To60s': serializer.toJson<int>(dur30To60s),
      'dur1To3m': serializer.toJson<int>(dur1To3m),
      'durOver3m': serializer.toJson<int>(durOver3m),
    };
  }

  DailyStat copyWith({
    String? date,
    String? model,
    bool? isLocal,
    int? count,
    double? totalDurationSec,
    double? totalProcessingSec,
    int? totalWords,
    double? totalCostUsd,
    int? durUnder15s,
    int? dur15To30s,
    int? dur30To60s,
    int? dur1To3m,
    int? durOver3m,
  }) => DailyStat(
    date: date ?? this.date,
    model: model ?? this.model,
    isLocal: isLocal ?? this.isLocal,
    count: count ?? this.count,
    totalDurationSec: totalDurationSec ?? this.totalDurationSec,
    totalProcessingSec: totalProcessingSec ?? this.totalProcessingSec,
    totalWords: totalWords ?? this.totalWords,
    totalCostUsd: totalCostUsd ?? this.totalCostUsd,
    durUnder15s: durUnder15s ?? this.durUnder15s,
    dur15To30s: dur15To30s ?? this.dur15To30s,
    dur30To60s: dur30To60s ?? this.dur30To60s,
    dur1To3m: dur1To3m ?? this.dur1To3m,
    durOver3m: durOver3m ?? this.durOver3m,
  );
  DailyStat copyWithCompanion(DailyStatsCompanion data) {
    return DailyStat(
      date: data.date.present ? data.date.value : this.date,
      model: data.model.present ? data.model.value : this.model,
      isLocal: data.isLocal.present ? data.isLocal.value : this.isLocal,
      count: data.count.present ? data.count.value : this.count,
      totalDurationSec: data.totalDurationSec.present
          ? data.totalDurationSec.value
          : this.totalDurationSec,
      totalProcessingSec: data.totalProcessingSec.present
          ? data.totalProcessingSec.value
          : this.totalProcessingSec,
      totalWords: data.totalWords.present
          ? data.totalWords.value
          : this.totalWords,
      totalCostUsd: data.totalCostUsd.present
          ? data.totalCostUsd.value
          : this.totalCostUsd,
      durUnder15s: data.durUnder15s.present
          ? data.durUnder15s.value
          : this.durUnder15s,
      dur15To30s: data.dur15To30s.present
          ? data.dur15To30s.value
          : this.dur15To30s,
      dur30To60s: data.dur30To60s.present
          ? data.dur30To60s.value
          : this.dur30To60s,
      dur1To3m: data.dur1To3m.present ? data.dur1To3m.value : this.dur1To3m,
      durOver3m: data.durOver3m.present ? data.durOver3m.value : this.durOver3m,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStat(')
          ..write('date: $date, ')
          ..write('model: $model, ')
          ..write('isLocal: $isLocal, ')
          ..write('count: $count, ')
          ..write('totalDurationSec: $totalDurationSec, ')
          ..write('totalProcessingSec: $totalProcessingSec, ')
          ..write('totalWords: $totalWords, ')
          ..write('totalCostUsd: $totalCostUsd, ')
          ..write('durUnder15s: $durUnder15s, ')
          ..write('dur15To30s: $dur15To30s, ')
          ..write('dur30To60s: $dur30To60s, ')
          ..write('dur1To3m: $dur1To3m, ')
          ..write('durOver3m: $durOver3m')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    model,
    isLocal,
    count,
    totalDurationSec,
    totalProcessingSec,
    totalWords,
    totalCostUsd,
    durUnder15s,
    dur15To30s,
    dur30To60s,
    dur1To3m,
    durOver3m,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStat &&
          other.date == this.date &&
          other.model == this.model &&
          other.isLocal == this.isLocal &&
          other.count == this.count &&
          other.totalDurationSec == this.totalDurationSec &&
          other.totalProcessingSec == this.totalProcessingSec &&
          other.totalWords == this.totalWords &&
          other.totalCostUsd == this.totalCostUsd &&
          other.durUnder15s == this.durUnder15s &&
          other.dur15To30s == this.dur15To30s &&
          other.dur30To60s == this.dur30To60s &&
          other.dur1To3m == this.dur1To3m &&
          other.durOver3m == this.durOver3m);
}

class DailyStatsCompanion extends UpdateCompanion<DailyStat> {
  final Value<String> date;
  final Value<String> model;
  final Value<bool> isLocal;
  final Value<int> count;
  final Value<double> totalDurationSec;
  final Value<double> totalProcessingSec;
  final Value<int> totalWords;
  final Value<double> totalCostUsd;
  final Value<int> durUnder15s;
  final Value<int> dur15To30s;
  final Value<int> dur30To60s;
  final Value<int> dur1To3m;
  final Value<int> durOver3m;
  final Value<int> rowid;
  const DailyStatsCompanion({
    this.date = const Value.absent(),
    this.model = const Value.absent(),
    this.isLocal = const Value.absent(),
    this.count = const Value.absent(),
    this.totalDurationSec = const Value.absent(),
    this.totalProcessingSec = const Value.absent(),
    this.totalWords = const Value.absent(),
    this.totalCostUsd = const Value.absent(),
    this.durUnder15s = const Value.absent(),
    this.dur15To30s = const Value.absent(),
    this.dur30To60s = const Value.absent(),
    this.dur1To3m = const Value.absent(),
    this.durOver3m = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyStatsCompanion.insert({
    required String date,
    required String model,
    required bool isLocal,
    this.count = const Value.absent(),
    this.totalDurationSec = const Value.absent(),
    this.totalProcessingSec = const Value.absent(),
    this.totalWords = const Value.absent(),
    this.totalCostUsd = const Value.absent(),
    this.durUnder15s = const Value.absent(),
    this.dur15To30s = const Value.absent(),
    this.dur30To60s = const Value.absent(),
    this.dur1To3m = const Value.absent(),
    this.durOver3m = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       model = Value(model),
       isLocal = Value(isLocal);
  static Insertable<DailyStat> custom({
    Expression<String>? date,
    Expression<String>? model,
    Expression<bool>? isLocal,
    Expression<int>? count,
    Expression<double>? totalDurationSec,
    Expression<double>? totalProcessingSec,
    Expression<int>? totalWords,
    Expression<double>? totalCostUsd,
    Expression<int>? durUnder15s,
    Expression<int>? dur15To30s,
    Expression<int>? dur30To60s,
    Expression<int>? dur1To3m,
    Expression<int>? durOver3m,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (model != null) 'model': model,
      if (isLocal != null) 'is_local': isLocal,
      if (count != null) 'count': count,
      if (totalDurationSec != null) 'total_duration_sec': totalDurationSec,
      if (totalProcessingSec != null)
        'total_processing_sec': totalProcessingSec,
      if (totalWords != null) 'total_words': totalWords,
      if (totalCostUsd != null) 'total_cost_usd': totalCostUsd,
      if (durUnder15s != null) 'dur_under15s': durUnder15s,
      if (dur15To30s != null) 'dur15_to30s': dur15To30s,
      if (dur30To60s != null) 'dur30_to60s': dur30To60s,
      if (dur1To3m != null) 'dur1_to3m': dur1To3m,
      if (durOver3m != null) 'dur_over3m': durOver3m,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyStatsCompanion copyWith({
    Value<String>? date,
    Value<String>? model,
    Value<bool>? isLocal,
    Value<int>? count,
    Value<double>? totalDurationSec,
    Value<double>? totalProcessingSec,
    Value<int>? totalWords,
    Value<double>? totalCostUsd,
    Value<int>? durUnder15s,
    Value<int>? dur15To30s,
    Value<int>? dur30To60s,
    Value<int>? dur1To3m,
    Value<int>? durOver3m,
    Value<int>? rowid,
  }) {
    return DailyStatsCompanion(
      date: date ?? this.date,
      model: model ?? this.model,
      isLocal: isLocal ?? this.isLocal,
      count: count ?? this.count,
      totalDurationSec: totalDurationSec ?? this.totalDurationSec,
      totalProcessingSec: totalProcessingSec ?? this.totalProcessingSec,
      totalWords: totalWords ?? this.totalWords,
      totalCostUsd: totalCostUsd ?? this.totalCostUsd,
      durUnder15s: durUnder15s ?? this.durUnder15s,
      dur15To30s: dur15To30s ?? this.dur15To30s,
      dur30To60s: dur30To60s ?? this.dur30To60s,
      dur1To3m: dur1To3m ?? this.dur1To3m,
      durOver3m: durOver3m ?? this.durOver3m,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (isLocal.present) {
      map['is_local'] = Variable<bool>(isLocal.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (totalDurationSec.present) {
      map['total_duration_sec'] = Variable<double>(totalDurationSec.value);
    }
    if (totalProcessingSec.present) {
      map['total_processing_sec'] = Variable<double>(totalProcessingSec.value);
    }
    if (totalWords.present) {
      map['total_words'] = Variable<int>(totalWords.value);
    }
    if (totalCostUsd.present) {
      map['total_cost_usd'] = Variable<double>(totalCostUsd.value);
    }
    if (durUnder15s.present) {
      map['dur_under15s'] = Variable<int>(durUnder15s.value);
    }
    if (dur15To30s.present) {
      map['dur15_to30s'] = Variable<int>(dur15To30s.value);
    }
    if (dur30To60s.present) {
      map['dur30_to60s'] = Variable<int>(dur30To60s.value);
    }
    if (dur1To3m.present) {
      map['dur1_to3m'] = Variable<int>(dur1To3m.value);
    }
    if (durOver3m.present) {
      map['dur_over3m'] = Variable<int>(durOver3m.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyStatsCompanion(')
          ..write('date: $date, ')
          ..write('model: $model, ')
          ..write('isLocal: $isLocal, ')
          ..write('count: $count, ')
          ..write('totalDurationSec: $totalDurationSec, ')
          ..write('totalProcessingSec: $totalProcessingSec, ')
          ..write('totalWords: $totalWords, ')
          ..write('totalCostUsd: $totalCostUsd, ')
          ..write('durUnder15s: $durUnder15s, ')
          ..write('dur15To30s: $dur15To30s, ')
          ..write('dur30To60s: $dur30To60s, ')
          ..write('dur1To3m: $dur1To3m, ')
          ..write('durOver3m: $durOver3m, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryNotesTable extends EntryNotes
    with TableInfo<$EntryNotesTable, EntryNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES history_entries (id)',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    content,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntryNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EntryNotesTable createAlias(String alias) {
    return $EntryNotesTable(attachedDatabase, alias);
  }
}

class EntryNote extends DataClass implements Insertable<EntryNote> {
  final String id;
  final String entryId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  const EntryNote({
    required this.id,
    required this.entryId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EntryNotesCompanion toCompanion(bool nullToAbsent) {
    return EntryNotesCompanion(
      id: Value(id),
      entryId: Value(entryId),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory EntryNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryNote(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EntryNote copyWith({
    String? id,
    String? entryId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => EntryNote(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EntryNote copyWithCompanion(EntryNotesCompanion data) {
    return EntryNote(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryNote(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entryId, content, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryNote &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EntryNotesCompanion extends UpdateCompanion<EntryNote> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EntryNotesCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryNotesCompanion.insert({
    required String id,
    required String entryId,
    this.content = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<EntryNote> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EntryNotesCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryNotesCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryAttachmentsTable extends EntryAttachments
    with TableInfo<$EntryAttachmentsTable, EntryAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES history_entries (id)',
    ),
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filepathMeta = const VerificationMeta(
    'filepath',
  );
  @override
  late final GeneratedColumn<String> filepath = GeneratedColumn<String>(
    'filepath',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    filename,
    filepath,
    mimeType,
    sizeBytes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryAttachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('filepath')) {
      context.handle(
        _filepathMeta,
        filepath.isAcceptableOrUnknown(data['filepath']!, _filepathMeta),
      );
    } else if (isInserting) {
      context.missing(_filepathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntryAttachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryAttachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      filepath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filepath'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EntryAttachmentsTable createAlias(String alias) {
    return $EntryAttachmentsTable(attachedDatabase, alias);
  }
}

class EntryAttachment extends DataClass implements Insertable<EntryAttachment> {
  final String id;
  final String entryId;
  final String filename;
  final String filepath;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  const EntryAttachment({
    required this.id,
    required this.entryId,
    required this.filename,
    required this.filepath,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['filename'] = Variable<String>(filename);
    map['filepath'] = Variable<String>(filepath);
    map['mime_type'] = Variable<String>(mimeType);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EntryAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return EntryAttachmentsCompanion(
      id: Value(id),
      entryId: Value(entryId),
      filename: Value(filename),
      filepath: Value(filepath),
      mimeType: Value(mimeType),
      sizeBytes: Value(sizeBytes),
      createdAt: Value(createdAt),
    );
  }

  factory EntryAttachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryAttachment(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      filename: serializer.fromJson<String>(json['filename']),
      filepath: serializer.fromJson<String>(json['filepath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'filename': serializer.toJson<String>(filename),
      'filepath': serializer.toJson<String>(filepath),
      'mimeType': serializer.toJson<String>(mimeType),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  EntryAttachment copyWith({
    String? id,
    String? entryId,
    String? filename,
    String? filepath,
    String? mimeType,
    int? sizeBytes,
    DateTime? createdAt,
  }) => EntryAttachment(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    filename: filename ?? this.filename,
    filepath: filepath ?? this.filepath,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdAt: createdAt ?? this.createdAt,
  );
  EntryAttachment copyWithCompanion(EntryAttachmentsCompanion data) {
    return EntryAttachment(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      filename: data.filename.present ? data.filename.value : this.filename,
      filepath: data.filepath.present ? data.filepath.value : this.filepath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryAttachment(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('filename: $filename, ')
          ..write('filepath: $filepath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    filename,
    filepath,
    mimeType,
    sizeBytes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryAttachment &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.filename == this.filename &&
          other.filepath == this.filepath &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.createdAt == this.createdAt);
}

class EntryAttachmentsCompanion extends UpdateCompanion<EntryAttachment> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> filename;
  final Value<String> filepath;
  final Value<String> mimeType;
  final Value<int> sizeBytes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const EntryAttachmentsCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.filename = const Value.absent(),
    this.filepath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryAttachmentsCompanion.insert({
    required String id,
    required String entryId,
    required String filename,
    required String filepath,
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       filename = Value(filename),
       filepath = Value(filepath),
       createdAt = Value(createdAt);
  static Insertable<EntryAttachment> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? filename,
    Expression<String>? filepath,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (filename != null) 'filename': filename,
      if (filepath != null) 'filepath': filepath,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryAttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? filename,
    Value<String>? filepath,
    Value<String>? mimeType,
    Value<int>? sizeBytes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return EntryAttachmentsCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      filename: filename ?? this.filename,
      filepath: filepath ?? this.filepath,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (filepath.present) {
      map['filepath'] = Variable<String>(filepath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('filename: $filename, ')
          ..write('filepath: $filepath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TextReplacementsTable extends TextReplacements
    with TableInfo<$TextReplacementsTable, TextReplacement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TextReplacementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerMeta = const VerificationMeta(
    'trigger',
  );
  @override
  late final GeneratedColumn<String> trigger = GeneratedColumn<String>(
    'trigger',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replacementMeta = const VerificationMeta(
    'replacement',
  );
  @override
  late final GeneratedColumn<String> replacement = GeneratedColumn<String>(
    'replacement',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matchModeMeta = const VerificationMeta(
    'matchMode',
  );
  @override
  late final GeneratedColumn<String> matchMode = GeneratedColumn<String>(
    'match_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('exact'),
  );
  static const VerificationMeta _fuzzyThresholdMeta = const VerificationMeta(
    'fuzzyThreshold',
  );
  @override
  late final GeneratedColumn<double> fuzzyThreshold = GeneratedColumn<double>(
    'fuzzy_threshold',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _usageCountMeta = const VerificationMeta(
    'usageCount',
  );
  @override
  late final GeneratedColumn<int> usageCount = GeneratedColumn<int>(
    'usage_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trigger,
    replacement,
    createdAt,
    matchMode,
    fuzzyThreshold,
    origin,
    usageCount,
    isFavorite,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'text_replacements';
  @override
  VerificationContext validateIntegrity(
    Insertable<TextReplacement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('trigger')) {
      context.handle(
        _triggerMeta,
        trigger.isAcceptableOrUnknown(data['trigger']!, _triggerMeta),
      );
    } else if (isInserting) {
      context.missing(_triggerMeta);
    }
    if (data.containsKey('replacement')) {
      context.handle(
        _replacementMeta,
        replacement.isAcceptableOrUnknown(
          data['replacement']!,
          _replacementMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_replacementMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('match_mode')) {
      context.handle(
        _matchModeMeta,
        matchMode.isAcceptableOrUnknown(data['match_mode']!, _matchModeMeta),
      );
    }
    if (data.containsKey('fuzzy_threshold')) {
      context.handle(
        _fuzzyThresholdMeta,
        fuzzyThreshold.isAcceptableOrUnknown(
          data['fuzzy_threshold']!,
          _fuzzyThresholdMeta,
        ),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('usage_count')) {
      context.handle(
        _usageCountMeta,
        usageCount.isAcceptableOrUnknown(data['usage_count']!, _usageCountMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TextReplacement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TextReplacement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      trigger: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger'],
      )!,
      replacement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      matchMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_mode'],
      )!,
      fuzzyThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fuzzy_threshold'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      usageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usage_count'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
    );
  }

  @override
  $TextReplacementsTable createAlias(String alias) {
    return $TextReplacementsTable(attachedDatabase, alias);
  }
}

class TextReplacement extends DataClass implements Insertable<TextReplacement> {
  final String id;
  final String trigger;
  final String replacement;
  final DateTime createdAt;

  /// Match algorithm — `exact` (word-boundary regex, unchanged pre-v20
  /// behavior) or `fuzzy` (similarity scoring, vocabulary-fuzzy-replacements
  /// PRD, schema v20). Stored as text rather than an int enum so a raw
  /// `SELECT` stays human-readable in the DB browser, consistent with other
  /// text-backed enum-ish columns in this file (e.g. `source` on
  /// `HistoryEntries`).
  final String matchMode;

  /// Similarity threshold (0.0-1.0) for `matchMode == fuzzy`; unused and left
  /// `null` for `exact` rows. The UI only ever offers three named steps
  /// (Streng 0.92 / Standard 0.85 / Tolerant 0.75), not a free slider — see
  /// PRD.md.
  final double? fuzzyThreshold;

  /// `manual` (default, user-authored) or `imported` (vocabulary-import
  /// scan) — display-only distinction (PRD User Story 11), no behavioral
  /// difference in matching.
  final String origin;

  /// How often this entry changed a dictation (schema v26). Written after
  /// each save, off the matching path; matching never reads it.
  final int usageCount;

  /// Pinned as a favourite in the dictionary (schema v26). Display only.
  final bool isFavorite;
  const TextReplacement({
    required this.id,
    required this.trigger,
    required this.replacement,
    required this.createdAt,
    required this.matchMode,
    this.fuzzyThreshold,
    required this.origin,
    required this.usageCount,
    required this.isFavorite,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['trigger'] = Variable<String>(trigger);
    map['replacement'] = Variable<String>(replacement);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['match_mode'] = Variable<String>(matchMode);
    if (!nullToAbsent || fuzzyThreshold != null) {
      map['fuzzy_threshold'] = Variable<double>(fuzzyThreshold);
    }
    map['origin'] = Variable<String>(origin);
    map['usage_count'] = Variable<int>(usageCount);
    map['is_favorite'] = Variable<bool>(isFavorite);
    return map;
  }

  TextReplacementsCompanion toCompanion(bool nullToAbsent) {
    return TextReplacementsCompanion(
      id: Value(id),
      trigger: Value(trigger),
      replacement: Value(replacement),
      createdAt: Value(createdAt),
      matchMode: Value(matchMode),
      fuzzyThreshold: fuzzyThreshold == null && nullToAbsent
          ? const Value.absent()
          : Value(fuzzyThreshold),
      origin: Value(origin),
      usageCount: Value(usageCount),
      isFavorite: Value(isFavorite),
    );
  }

  factory TextReplacement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TextReplacement(
      id: serializer.fromJson<String>(json['id']),
      trigger: serializer.fromJson<String>(json['trigger']),
      replacement: serializer.fromJson<String>(json['replacement']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      matchMode: serializer.fromJson<String>(json['matchMode']),
      fuzzyThreshold: serializer.fromJson<double?>(json['fuzzyThreshold']),
      origin: serializer.fromJson<String>(json['origin']),
      usageCount: serializer.fromJson<int>(json['usageCount']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'trigger': serializer.toJson<String>(trigger),
      'replacement': serializer.toJson<String>(replacement),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'matchMode': serializer.toJson<String>(matchMode),
      'fuzzyThreshold': serializer.toJson<double?>(fuzzyThreshold),
      'origin': serializer.toJson<String>(origin),
      'usageCount': serializer.toJson<int>(usageCount),
      'isFavorite': serializer.toJson<bool>(isFavorite),
    };
  }

  TextReplacement copyWith({
    String? id,
    String? trigger,
    String? replacement,
    DateTime? createdAt,
    String? matchMode,
    Value<double?> fuzzyThreshold = const Value.absent(),
    String? origin,
    int? usageCount,
    bool? isFavorite,
  }) => TextReplacement(
    id: id ?? this.id,
    trigger: trigger ?? this.trigger,
    replacement: replacement ?? this.replacement,
    createdAt: createdAt ?? this.createdAt,
    matchMode: matchMode ?? this.matchMode,
    fuzzyThreshold: fuzzyThreshold.present
        ? fuzzyThreshold.value
        : this.fuzzyThreshold,
    origin: origin ?? this.origin,
    usageCount: usageCount ?? this.usageCount,
    isFavorite: isFavorite ?? this.isFavorite,
  );
  TextReplacement copyWithCompanion(TextReplacementsCompanion data) {
    return TextReplacement(
      id: data.id.present ? data.id.value : this.id,
      trigger: data.trigger.present ? data.trigger.value : this.trigger,
      replacement: data.replacement.present
          ? data.replacement.value
          : this.replacement,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      matchMode: data.matchMode.present ? data.matchMode.value : this.matchMode,
      fuzzyThreshold: data.fuzzyThreshold.present
          ? data.fuzzyThreshold.value
          : this.fuzzyThreshold,
      origin: data.origin.present ? data.origin.value : this.origin,
      usageCount: data.usageCount.present
          ? data.usageCount.value
          : this.usageCount,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TextReplacement(')
          ..write('id: $id, ')
          ..write('trigger: $trigger, ')
          ..write('replacement: $replacement, ')
          ..write('createdAt: $createdAt, ')
          ..write('matchMode: $matchMode, ')
          ..write('fuzzyThreshold: $fuzzyThreshold, ')
          ..write('origin: $origin, ')
          ..write('usageCount: $usageCount, ')
          ..write('isFavorite: $isFavorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trigger,
    replacement,
    createdAt,
    matchMode,
    fuzzyThreshold,
    origin,
    usageCount,
    isFavorite,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextReplacement &&
          other.id == this.id &&
          other.trigger == this.trigger &&
          other.replacement == this.replacement &&
          other.createdAt == this.createdAt &&
          other.matchMode == this.matchMode &&
          other.fuzzyThreshold == this.fuzzyThreshold &&
          other.origin == this.origin &&
          other.usageCount == this.usageCount &&
          other.isFavorite == this.isFavorite);
}

class TextReplacementsCompanion extends UpdateCompanion<TextReplacement> {
  final Value<String> id;
  final Value<String> trigger;
  final Value<String> replacement;
  final Value<DateTime> createdAt;
  final Value<String> matchMode;
  final Value<double?> fuzzyThreshold;
  final Value<String> origin;
  final Value<int> usageCount;
  final Value<bool> isFavorite;
  final Value<int> rowid;
  const TextReplacementsCompanion({
    this.id = const Value.absent(),
    this.trigger = const Value.absent(),
    this.replacement = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.matchMode = const Value.absent(),
    this.fuzzyThreshold = const Value.absent(),
    this.origin = const Value.absent(),
    this.usageCount = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TextReplacementsCompanion.insert({
    required String id,
    required String trigger,
    required String replacement,
    required DateTime createdAt,
    this.matchMode = const Value.absent(),
    this.fuzzyThreshold = const Value.absent(),
    this.origin = const Value.absent(),
    this.usageCount = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       trigger = Value(trigger),
       replacement = Value(replacement),
       createdAt = Value(createdAt);
  static Insertable<TextReplacement> custom({
    Expression<String>? id,
    Expression<String>? trigger,
    Expression<String>? replacement,
    Expression<DateTime>? createdAt,
    Expression<String>? matchMode,
    Expression<double>? fuzzyThreshold,
    Expression<String>? origin,
    Expression<int>? usageCount,
    Expression<bool>? isFavorite,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trigger != null) 'trigger': trigger,
      if (replacement != null) 'replacement': replacement,
      if (createdAt != null) 'created_at': createdAt,
      if (matchMode != null) 'match_mode': matchMode,
      if (fuzzyThreshold != null) 'fuzzy_threshold': fuzzyThreshold,
      if (origin != null) 'origin': origin,
      if (usageCount != null) 'usage_count': usageCount,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TextReplacementsCompanion copyWith({
    Value<String>? id,
    Value<String>? trigger,
    Value<String>? replacement,
    Value<DateTime>? createdAt,
    Value<String>? matchMode,
    Value<double?>? fuzzyThreshold,
    Value<String>? origin,
    Value<int>? usageCount,
    Value<bool>? isFavorite,
    Value<int>? rowid,
  }) {
    return TextReplacementsCompanion(
      id: id ?? this.id,
      trigger: trigger ?? this.trigger,
      replacement: replacement ?? this.replacement,
      createdAt: createdAt ?? this.createdAt,
      matchMode: matchMode ?? this.matchMode,
      fuzzyThreshold: fuzzyThreshold ?? this.fuzzyThreshold,
      origin: origin ?? this.origin,
      usageCount: usageCount ?? this.usageCount,
      isFavorite: isFavorite ?? this.isFavorite,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (trigger.present) {
      map['trigger'] = Variable<String>(trigger.value);
    }
    if (replacement.present) {
      map['replacement'] = Variable<String>(replacement.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (matchMode.present) {
      map['match_mode'] = Variable<String>(matchMode.value);
    }
    if (fuzzyThreshold.present) {
      map['fuzzy_threshold'] = Variable<double>(fuzzyThreshold.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (usageCount.present) {
      map['usage_count'] = Variable<int>(usageCount.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TextReplacementsCompanion(')
          ..write('id: $id, ')
          ..write('trigger: $trigger, ')
          ..write('replacement: $replacement, ')
          ..write('createdAt: $createdAt, ')
          ..write('matchMode: $matchMode, ')
          ..write('fuzzyThreshold: $fuzzyThreshold, ')
          ..write('origin: $origin, ')
          ..write('usageCount: $usageCount, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TextReplacementTriggersTable extends TextReplacementTriggers
    with TableInfo<$TextReplacementTriggersTable, TextReplacementTrigger> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TextReplacementTriggersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replacementIdMeta = const VerificationMeta(
    'replacementId',
  );
  @override
  late final GeneratedColumn<String> replacementId = GeneratedColumn<String>(
    'replacement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES text_replacements (id)',
    ),
  );
  static const VerificationMeta _triggerMeta = const VerificationMeta(
    'trigger',
  );
  @override
  late final GeneratedColumn<String> trigger = GeneratedColumn<String>(
    'trigger',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, replacementId, trigger];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'text_replacement_triggers';
  @override
  VerificationContext validateIntegrity(
    Insertable<TextReplacementTrigger> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('replacement_id')) {
      context.handle(
        _replacementIdMeta,
        replacementId.isAcceptableOrUnknown(
          data['replacement_id']!,
          _replacementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_replacementIdMeta);
    }
    if (data.containsKey('trigger')) {
      context.handle(
        _triggerMeta,
        trigger.isAcceptableOrUnknown(data['trigger']!, _triggerMeta),
      );
    } else if (isInserting) {
      context.missing(_triggerMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TextReplacementTrigger map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TextReplacementTrigger(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      replacementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement_id'],
      )!,
      trigger: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger'],
      )!,
    );
  }

  @override
  $TextReplacementTriggersTable createAlias(String alias) {
    return $TextReplacementTriggersTable(attachedDatabase, alias);
  }
}

class TextReplacementTrigger extends DataClass
    implements Insertable<TextReplacementTrigger> {
  final String id;
  final String replacementId;
  final String trigger;
  const TextReplacementTrigger({
    required this.id,
    required this.replacementId,
    required this.trigger,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['replacement_id'] = Variable<String>(replacementId);
    map['trigger'] = Variable<String>(trigger);
    return map;
  }

  TextReplacementTriggersCompanion toCompanion(bool nullToAbsent) {
    return TextReplacementTriggersCompanion(
      id: Value(id),
      replacementId: Value(replacementId),
      trigger: Value(trigger),
    );
  }

  factory TextReplacementTrigger.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TextReplacementTrigger(
      id: serializer.fromJson<String>(json['id']),
      replacementId: serializer.fromJson<String>(json['replacementId']),
      trigger: serializer.fromJson<String>(json['trigger']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'replacementId': serializer.toJson<String>(replacementId),
      'trigger': serializer.toJson<String>(trigger),
    };
  }

  TextReplacementTrigger copyWith({
    String? id,
    String? replacementId,
    String? trigger,
  }) => TextReplacementTrigger(
    id: id ?? this.id,
    replacementId: replacementId ?? this.replacementId,
    trigger: trigger ?? this.trigger,
  );
  TextReplacementTrigger copyWithCompanion(
    TextReplacementTriggersCompanion data,
  ) {
    return TextReplacementTrigger(
      id: data.id.present ? data.id.value : this.id,
      replacementId: data.replacementId.present
          ? data.replacementId.value
          : this.replacementId,
      trigger: data.trigger.present ? data.trigger.value : this.trigger,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TextReplacementTrigger(')
          ..write('id: $id, ')
          ..write('replacementId: $replacementId, ')
          ..write('trigger: $trigger')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, replacementId, trigger);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextReplacementTrigger &&
          other.id == this.id &&
          other.replacementId == this.replacementId &&
          other.trigger == this.trigger);
}

class TextReplacementTriggersCompanion
    extends UpdateCompanion<TextReplacementTrigger> {
  final Value<String> id;
  final Value<String> replacementId;
  final Value<String> trigger;
  final Value<int> rowid;
  const TextReplacementTriggersCompanion({
    this.id = const Value.absent(),
    this.replacementId = const Value.absent(),
    this.trigger = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TextReplacementTriggersCompanion.insert({
    required String id,
    required String replacementId,
    required String trigger,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       replacementId = Value(replacementId),
       trigger = Value(trigger);
  static Insertable<TextReplacementTrigger> custom({
    Expression<String>? id,
    Expression<String>? replacementId,
    Expression<String>? trigger,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (replacementId != null) 'replacement_id': replacementId,
      if (trigger != null) 'trigger': trigger,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TextReplacementTriggersCompanion copyWith({
    Value<String>? id,
    Value<String>? replacementId,
    Value<String>? trigger,
    Value<int>? rowid,
  }) {
    return TextReplacementTriggersCompanion(
      id: id ?? this.id,
      replacementId: replacementId ?? this.replacementId,
      trigger: trigger ?? this.trigger,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (replacementId.present) {
      map['replacement_id'] = Variable<String>(replacementId.value);
    }
    if (trigger.present) {
      map['trigger'] = Variable<String>(trigger.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TextReplacementTriggersCompanion(')
          ..write('id: $id, ')
          ..write('replacementId: $replacementId, ')
          ..write('trigger: $trigger, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final String id;
  final String name;
  final DateTime createdAt;
  const Tag({required this.id, required this.name, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Tag copyWith({String? id, String? name, DateTime? createdAt}) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Tag> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryTagsTable extends EntryTags
    with TableInfo<$EntryTagsTable, EntryTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES history_entries (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [entryId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, tagId};
  @override
  EntryTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryTag(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $EntryTagsTable createAlias(String alias) {
    return $EntryTagsTable(attachedDatabase, alias);
  }
}

class EntryTag extends DataClass implements Insertable<EntryTag> {
  final String entryId;
  final String tagId;
  const EntryTag({required this.entryId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  EntryTagsCompanion toCompanion(bool nullToAbsent) {
    return EntryTagsCompanion(entryId: Value(entryId), tagId: Value(tagId));
  }

  factory EntryTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryTag(
      entryId: serializer.fromJson<String>(json['entryId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<String>(entryId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  EntryTag copyWith({String? entryId, String? tagId}) =>
      EntryTag(entryId: entryId ?? this.entryId, tagId: tagId ?? this.tagId);
  EntryTag copyWithCompanion(EntryTagsCompanion data) {
    return EntryTag(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryTag(')
          ..write('entryId: $entryId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryTag &&
          other.entryId == this.entryId &&
          other.tagId == this.tagId);
}

class EntryTagsCompanion extends UpdateCompanion<EntryTag> {
  final Value<String> entryId;
  final Value<String> tagId;
  final Value<int> rowid;
  const EntryTagsCompanion({
    this.entryId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryTagsCompanion.insert({
    required String entryId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       tagId = Value(tagId);
  static Insertable<EntryTag> custom({
    Expression<String>? entryId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryTagsCompanion copyWith({
    Value<String>? entryId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return EntryTagsCompanion(
      entryId: entryId ?? this.entryId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryTagsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HotkeyLatencyEntriesTable extends HotkeyLatencyEntries
    with TableInfo<$HotkeyLatencyEntriesTable, HotkeyLatencyEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HotkeyLatencyEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stopToTextMsMeta = const VerificationMeta(
    'stopToTextMs',
  );
  @override
  late final GeneratedColumn<int> stopToTextMs = GeneratedColumn<int>(
    'stop_to_text_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recordedAt,
    latencyMs,
    stopToTextMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hotkey_latency_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HotkeyLatencyEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    } else if (isInserting) {
      context.missing(_latencyMsMeta);
    }
    if (data.containsKey('stop_to_text_ms')) {
      context.handle(
        _stopToTextMsMeta,
        stopToTextMs.isAcceptableOrUnknown(
          data['stop_to_text_ms']!,
          _stopToTextMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HotkeyLatencyEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HotkeyLatencyEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      )!,
      stopToTextMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stop_to_text_ms'],
      ),
    );
  }

  @override
  $HotkeyLatencyEntriesTable createAlias(String alias) {
    return $HotkeyLatencyEntriesTable(attachedDatabase, alias);
  }
}

class HotkeyLatencyEntry extends DataClass
    implements Insertable<HotkeyLatencyEntry> {
  final String id;
  final DateTime recordedAt;
  final int latencyMs;

  /// Recording stop → text delivered, without the speaking time (XP-6-09).
  /// `null` for samples recorded before schema v30.
  final int? stopToTextMs;
  const HotkeyLatencyEntry({
    required this.id,
    required this.recordedAt,
    required this.latencyMs,
    this.stopToTextMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    map['latency_ms'] = Variable<int>(latencyMs);
    if (!nullToAbsent || stopToTextMs != null) {
      map['stop_to_text_ms'] = Variable<int>(stopToTextMs);
    }
    return map;
  }

  HotkeyLatencyEntriesCompanion toCompanion(bool nullToAbsent) {
    return HotkeyLatencyEntriesCompanion(
      id: Value(id),
      recordedAt: Value(recordedAt),
      latencyMs: Value(latencyMs),
      stopToTextMs: stopToTextMs == null && nullToAbsent
          ? const Value.absent()
          : Value(stopToTextMs),
    );
  }

  factory HotkeyLatencyEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HotkeyLatencyEntry(
      id: serializer.fromJson<String>(json['id']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
      latencyMs: serializer.fromJson<int>(json['latencyMs']),
      stopToTextMs: serializer.fromJson<int?>(json['stopToTextMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
      'latencyMs': serializer.toJson<int>(latencyMs),
      'stopToTextMs': serializer.toJson<int?>(stopToTextMs),
    };
  }

  HotkeyLatencyEntry copyWith({
    String? id,
    DateTime? recordedAt,
    int? latencyMs,
    Value<int?> stopToTextMs = const Value.absent(),
  }) => HotkeyLatencyEntry(
    id: id ?? this.id,
    recordedAt: recordedAt ?? this.recordedAt,
    latencyMs: latencyMs ?? this.latencyMs,
    stopToTextMs: stopToTextMs.present ? stopToTextMs.value : this.stopToTextMs,
  );
  HotkeyLatencyEntry copyWithCompanion(HotkeyLatencyEntriesCompanion data) {
    return HotkeyLatencyEntry(
      id: data.id.present ? data.id.value : this.id,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      stopToTextMs: data.stopToTextMs.present
          ? data.stopToTextMs.value
          : this.stopToTextMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HotkeyLatencyEntry(')
          ..write('id: $id, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('stopToTextMs: $stopToTextMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, recordedAt, latencyMs, stopToTextMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HotkeyLatencyEntry &&
          other.id == this.id &&
          other.recordedAt == this.recordedAt &&
          other.latencyMs == this.latencyMs &&
          other.stopToTextMs == this.stopToTextMs);
}

class HotkeyLatencyEntriesCompanion
    extends UpdateCompanion<HotkeyLatencyEntry> {
  final Value<String> id;
  final Value<DateTime> recordedAt;
  final Value<int> latencyMs;
  final Value<int?> stopToTextMs;
  final Value<int> rowid;
  const HotkeyLatencyEntriesCompanion({
    this.id = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.stopToTextMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HotkeyLatencyEntriesCompanion.insert({
    required String id,
    required DateTime recordedAt,
    required int latencyMs,
    this.stopToTextMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recordedAt = Value(recordedAt),
       latencyMs = Value(latencyMs);
  static Insertable<HotkeyLatencyEntry> custom({
    Expression<String>? id,
    Expression<DateTime>? recordedAt,
    Expression<int>? latencyMs,
    Expression<int>? stopToTextMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (stopToTextMs != null) 'stop_to_text_ms': stopToTextMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HotkeyLatencyEntriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? recordedAt,
    Value<int>? latencyMs,
    Value<int?>? stopToTextMs,
    Value<int>? rowid,
  }) {
    return HotkeyLatencyEntriesCompanion(
      id: id ?? this.id,
      recordedAt: recordedAt ?? this.recordedAt,
      latencyMs: latencyMs ?? this.latencyMs,
      stopToTextMs: stopToTextMs ?? this.stopToTextMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (stopToTextMs.present) {
      map['stop_to_text_ms'] = Variable<int>(stopToTextMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HotkeyLatencyEntriesCompanion(')
          ..write('id: $id, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('stopToTextMs: $stopToTextMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnippetsTable extends Snippets with TableInfo<$SnippetsTable, Snippet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('static'),
  );
  static const VerificationMeta _sourceNoteIdMeta = const VerificationMeta(
    'sourceNoteId',
  );
  @override
  late final GeneratedColumn<String> sourceNoteId = GeneratedColumn<String>(
    'source_note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    createdAt,
    kind,
    sourceNoteId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Snippet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('source_note_id')) {
      context.handle(
        _sourceNoteIdMeta,
        sourceNoteId.isAcceptableOrUnknown(
          data['source_note_id']!,
          _sourceNoteIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Snippet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Snippet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sourceNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_note_id'],
      ),
    );
  }

  @override
  $SnippetsTable createAlias(String alias) {
    return $SnippetsTable(attachedDatabase, alias);
  }
}

class Snippet extends DataClass implements Insertable<Snippet> {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// `static` (default, today's only behavior — [body] is inserted verbatim)
  /// or `interactive` (schema v21, `interactive-snippets` PRD; template
  /// authoring added in schema v23): for `interactive`, [body] holds the
  /// user-authored template ([interactiveSnippetPlaceholder] tokens mark
  /// where each [SnippetFields] entry's dictated text is substituted at
  /// trigger time, see `interactive_snippet_composer.dart`) rather than
  /// text inserted verbatim.
  final String kind;

  /// The note this Textbaustein was created from ("Als Textbaustein", schema
  /// v29). Informational link back; NULL for snippets authored directly.
  final String? sourceNoteId;
  const Snippet({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.kind,
    this.sourceNoteId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || sourceNoteId != null) {
      map['source_note_id'] = Variable<String>(sourceNoteId);
    }
    return map;
  }

  SnippetsCompanion toCompanion(bool nullToAbsent) {
    return SnippetsCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      createdAt: Value(createdAt),
      kind: Value(kind),
      sourceNoteId: sourceNoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceNoteId),
    );
  }

  factory Snippet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Snippet(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      kind: serializer.fromJson<String>(json['kind']),
      sourceNoteId: serializer.fromJson<String?>(json['sourceNoteId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'kind': serializer.toJson<String>(kind),
      'sourceNoteId': serializer.toJson<String?>(sourceNoteId),
    };
  }

  Snippet copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    String? kind,
    Value<String?> sourceNoteId = const Value.absent(),
  }) => Snippet(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
    kind: kind ?? this.kind,
    sourceNoteId: sourceNoteId.present ? sourceNoteId.value : this.sourceNoteId,
  );
  Snippet copyWithCompanion(SnippetsCompanion data) {
    return Snippet(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      sourceNoteId: data.sourceNoteId.present
          ? data.sourceNoteId.value
          : this.sourceNoteId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Snippet(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('kind: $kind, ')
          ..write('sourceNoteId: $sourceNoteId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, body, createdAt, kind, sourceNoteId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Snippet &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.createdAt == this.createdAt &&
          other.kind == this.kind &&
          other.sourceNoteId == this.sourceNoteId);
}

class SnippetsCompanion extends UpdateCompanion<Snippet> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> body;
  final Value<DateTime> createdAt;
  final Value<String> kind;
  final Value<String?> sourceNoteId;
  final Value<int> rowid;
  const SnippetsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnippetsCompanion.insert({
    required String id,
    required String title,
    required String body,
    required DateTime createdAt,
    this.kind = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<Snippet> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<DateTime>? createdAt,
    Expression<String>? kind,
    Expression<String>? sourceNoteId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
      if (kind != null) 'kind': kind,
      if (sourceNoteId != null) 'source_note_id': sourceNoteId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnippetsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? body,
    Value<DateTime>? createdAt,
    Value<String>? kind,
    Value<String?>? sourceNoteId,
    Value<int>? rowid,
  }) {
    return SnippetsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sourceNoteId.present) {
      map['source_note_id'] = Variable<String>(sourceNoteId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('kind: $kind, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnippetFieldsTable extends SnippetFields
    with TableInfo<$SnippetFieldsTable, SnippetField> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetFieldsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snippetIdMeta = const VerificationMeta(
    'snippetId',
  );
  @override
  late final GeneratedColumn<String> snippetId = GeneratedColumn<String>(
    'snippet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES snippets (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snippetId, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippet_fields';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnippetField> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snippet_id')) {
      context.handle(
        _snippetIdMeta,
        snippetId.isAcceptableOrUnknown(data['snippet_id']!, _snippetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snippetIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SnippetField map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnippetField(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snippetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $SnippetFieldsTable createAlias(String alias) {
    return $SnippetFieldsTable(attachedDatabase, alias);
  }
}

class SnippetField extends DataClass implements Insertable<SnippetField> {
  final String id;
  final String snippetId;
  final String name;
  final int sortOrder;
  const SnippetField({
    required this.id,
    required this.snippetId,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snippet_id'] = Variable<String>(snippetId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SnippetFieldsCompanion toCompanion(bool nullToAbsent) {
    return SnippetFieldsCompanion(
      id: Value(id),
      snippetId: Value(snippetId),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory SnippetField.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnippetField(
      id: serializer.fromJson<String>(json['id']),
      snippetId: serializer.fromJson<String>(json['snippetId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snippetId': serializer.toJson<String>(snippetId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  SnippetField copyWith({
    String? id,
    String? snippetId,
    String? name,
    int? sortOrder,
  }) => SnippetField(
    id: id ?? this.id,
    snippetId: snippetId ?? this.snippetId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  SnippetField copyWithCompanion(SnippetFieldsCompanion data) {
    return SnippetField(
      id: data.id.present ? data.id.value : this.id,
      snippetId: data.snippetId.present ? data.snippetId.value : this.snippetId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnippetField(')
          ..write('id: $id, ')
          ..write('snippetId: $snippetId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snippetId, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnippetField &&
          other.id == this.id &&
          other.snippetId == this.snippetId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class SnippetFieldsCompanion extends UpdateCompanion<SnippetField> {
  final Value<String> id;
  final Value<String> snippetId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SnippetFieldsCompanion({
    this.id = const Value.absent(),
    this.snippetId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnippetFieldsCompanion.insert({
    required String id,
    required String snippetId,
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snippetId = Value(snippetId),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<SnippetField> custom({
    Expression<String>? id,
    Expression<String>? snippetId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snippetId != null) 'snippet_id': snippetId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnippetFieldsCompanion copyWith({
    Value<String>? id,
    Value<String>? snippetId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return SnippetFieldsCompanion(
      id: id ?? this.id,
      snippetId: snippetId ?? this.snippetId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snippetId.present) {
      map['snippet_id'] = Variable<String>(snippetId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetFieldsCompanion(')
          ..write('id: $id, ')
          ..write('snippetId: $snippetId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isQuickNoteMeta = const VerificationMeta(
    'isQuickNote',
  );
  @override
  late final GeneratedColumn<bool> isQuickNote = GeneratedColumn<bool>(
    'is_quick_note',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_quick_note" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    title,
    pinned,
    isQuickNote,
    deletedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('is_quick_note')) {
      context.handle(
        _isQuickNoteMeta,
        isQuickNote.isAcceptableOrUnknown(
          data['is_quick_note']!,
          _isQuickNoteMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      isQuickNote: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_quick_note'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final String id;
  final String content;
  final String? title;
  final bool pinned;
  final bool isQuickNote;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Note({
    required this.id,
    required this.content,
    this.title,
    required this.pinned,
    required this.isQuickNote,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['pinned'] = Variable<bool>(pinned);
    map['is_quick_note'] = Variable<bool>(isQuickNote);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      content: Value(content),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      pinned: Value(pinned),
      isQuickNote: Value(isQuickNote),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      title: serializer.fromJson<String?>(json['title']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      isQuickNote: serializer.fromJson<bool>(json['isQuickNote']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'title': serializer.toJson<String?>(title),
      'pinned': serializer.toJson<bool>(pinned),
      'isQuickNote': serializer.toJson<bool>(isQuickNote),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Note copyWith({
    String? id,
    String? content,
    Value<String?> title = const Value.absent(),
    bool? pinned,
    bool? isQuickNote,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Note(
    id: id ?? this.id,
    content: content ?? this.content,
    title: title.present ? title.value : this.title,
    pinned: pinned ?? this.pinned,
    isQuickNote: isQuickNote ?? this.isQuickNote,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      title: data.title.present ? data.title.value : this.title,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      isQuickNote: data.isQuickNote.present
          ? data.isQuickNote.value
          : this.isQuickNote,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('title: $title, ')
          ..write('pinned: $pinned, ')
          ..write('isQuickNote: $isQuickNote, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    title,
    pinned,
    isQuickNote,
    deletedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.content == this.content &&
          other.title == this.title &&
          other.pinned == this.pinned &&
          other.isQuickNote == this.isQuickNote &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String> content;
  final Value<String?> title;
  final Value<bool> pinned;
  final Value<bool> isQuickNote;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.title = const Value.absent(),
    this.pinned = const Value.absent(),
    this.isQuickNote = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    this.content = const Value.absent(),
    this.title = const Value.absent(),
    this.pinned = const Value.absent(),
    this.isQuickNote = const Value.absent(),
    this.deletedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? title,
    Expression<bool>? pinned,
    Expression<bool>? isQuickNote,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (title != null) 'title': title,
      if (pinned != null) 'pinned': pinned,
      if (isQuickNote != null) 'is_quick_note': isQuickNote,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<String?>? title,
    Value<bool>? pinned,
    Value<bool>? isQuickNote,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      title: title ?? this.title,
      pinned: pinned ?? this.pinned,
      isQuickNote: isQuickNote ?? this.isQuickNote,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (isQuickNote.present) {
      map['is_quick_note'] = Variable<bool>(isQuickNote.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('title: $title, ')
          ..write('pinned: $pinned, ')
          ..write('isQuickNote: $isQuickNote, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteTagsTable extends NoteTags with TableInfo<$NoteTagsTable, NoteTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [noteId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId, tagId};
  @override
  NoteTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteTag(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $NoteTagsTable createAlias(String alias) {
    return $NoteTagsTable(attachedDatabase, alias);
  }
}

class NoteTag extends DataClass implements Insertable<NoteTag> {
  final String noteId;
  final String tagId;
  const NoteTag({required this.noteId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  NoteTagsCompanion toCompanion(bool nullToAbsent) {
    return NoteTagsCompanion(noteId: Value(noteId), tagId: Value(tagId));
  }

  factory NoteTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteTag(
      noteId: serializer.fromJson<String>(json['noteId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  NoteTag copyWith({String? noteId, String? tagId}) =>
      NoteTag(noteId: noteId ?? this.noteId, tagId: tagId ?? this.tagId);
  NoteTag copyWithCompanion(NoteTagsCompanion data) {
    return NoteTag(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteTag(')
          ..write('noteId: $noteId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(noteId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteTag &&
          other.noteId == this.noteId &&
          other.tagId == this.tagId);
}

class NoteTagsCompanion extends UpdateCompanion<NoteTag> {
  final Value<String> noteId;
  final Value<String> tagId;
  final Value<int> rowid;
  const NoteTagsCompanion({
    this.noteId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteTagsCompanion.insert({
    required String noteId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       tagId = Value(tagId);
  static Insertable<NoteTag> custom({
    Expression<String>? noteId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteTagsCompanion copyWith({
    Value<String>? noteId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return NoteTagsCompanion(
      noteId: noteId ?? this.noteId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteTagsCompanion(')
          ..write('noteId: $noteId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteVersionsTable extends NoteVersions
    with TableInfo<$NoteVersionsTable, NoteVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    title,
    content,
    sizeBytes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteVersion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteVersionsTable createAlias(String alias) {
    return $NoteVersionsTable(attachedDatabase, alias);
  }
}

class NoteVersion extends DataClass implements Insertable<NoteVersion> {
  final String id;
  final String noteId;
  final String? title;
  final String content;
  final int sizeBytes;
  final DateTime createdAt;
  const NoteVersion({
    required this.id,
    required this.noteId,
    this.title,
    required this.content,
    required this.sizeBytes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['content'] = Variable<String>(content);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteVersionsCompanion toCompanion(bool nullToAbsent) {
    return NoteVersionsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      content: Value(content),
      sizeBytes: Value(sizeBytes),
      createdAt: Value(createdAt),
    );
  }

  factory NoteVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteVersion(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      title: serializer.fromJson<String?>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'title': serializer.toJson<String?>(title),
      'content': serializer.toJson<String>(content),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteVersion copyWith({
    String? id,
    String? noteId,
    Value<String?> title = const Value.absent(),
    String? content,
    int? sizeBytes,
    DateTime? createdAt,
  }) => NoteVersion(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    title: title.present ? title.value : this.title,
    content: content ?? this.content,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteVersion copyWithCompanion(NoteVersionsCompanion data) {
    return NoteVersion(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteVersion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, noteId, title, content, sizeBytes, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteVersion &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.title == this.title &&
          other.content == this.content &&
          other.sizeBytes == this.sizeBytes &&
          other.createdAt == this.createdAt);
}

class NoteVersionsCompanion extends UpdateCompanion<NoteVersion> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String?> title;
  final Value<String> content;
  final Value<int> sizeBytes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const NoteVersionsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteVersionsCompanion.insert({
    required String id,
    required String noteId,
    this.title = const Value.absent(),
    required String content,
    required int sizeBytes,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       content = Value(content),
       sizeBytes = Value(sizeBytes),
       createdAt = Value(createdAt);
  static Insertable<NoteVersion> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? title,
    Expression<String>? content,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteVersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String?>? title,
    Value<String>? content,
    Value<int>? sizeBytes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return NoteVersionsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      content: content ?? this.content,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteVersionsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteAssetsTable extends NoteAssets
    with TableInfo<$NoteAssetsTable, NoteAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    relativePath,
    mimeType,
    sizeBytes,
    width,
    height,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteAssetsTable createAlias(String alias) {
    return $NoteAssetsTable(attachedDatabase, alias);
  }
}

class NoteAsset extends DataClass implements Insertable<NoteAsset> {
  final String id;
  final String noteId;
  final String relativePath;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final DateTime createdAt;
  const NoteAsset({
    required this.id,
    required this.noteId,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['relative_path'] = Variable<String>(relativePath);
    map['mime_type'] = Variable<String>(mimeType);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteAssetsCompanion toCompanion(bool nullToAbsent) {
    return NoteAssetsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      relativePath: Value(relativePath),
      mimeType: Value(mimeType),
      sizeBytes: Value(sizeBytes),
      width: Value(width),
      height: Value(height),
      createdAt: Value(createdAt),
    );
  }

  factory NoteAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteAsset(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'relativePath': serializer.toJson<String>(relativePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteAsset copyWith({
    String? id,
    String? noteId,
    String? relativePath,
    String? mimeType,
    int? sizeBytes,
    int? width,
    int? height,
    DateTime? createdAt,
  }) => NoteAsset(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    relativePath: relativePath ?? this.relativePath,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    width: width ?? this.width,
    height: height ?? this.height,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteAsset copyWithCompanion(NoteAssetsCompanion data) {
    return NoteAsset(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteAsset(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    relativePath,
    mimeType,
    sizeBytes,
    width,
    height,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteAsset &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.relativePath == this.relativePath &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.width == this.width &&
          other.height == this.height &&
          other.createdAt == this.createdAt);
}

class NoteAssetsCompanion extends UpdateCompanion<NoteAsset> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> relativePath;
  final Value<String> mimeType;
  final Value<int> sizeBytes;
  final Value<int> width;
  final Value<int> height;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const NoteAssetsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteAssetsCompanion.insert({
    required String id,
    required String noteId,
    required String relativePath,
    required String mimeType,
    required int sizeBytes,
    required int width,
    required int height,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       relativePath = Value(relativePath),
       mimeType = Value(mimeType),
       sizeBytes = Value(sizeBytes),
       width = Value(width),
       height = Value(height),
       createdAt = Value(createdAt);
  static Insertable<NoteAsset> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? relativePath,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<int>? width,
    Expression<int>? height,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (relativePath != null) 'relative_path': relativePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? relativePath,
    Value<String>? mimeType,
    Value<int>? sizeBytes,
    Value<int>? width,
    Value<int>? height,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return NoteAssetsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteAssetsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CorrectionObservationsTable extends CorrectionObservations
    with TableInfo<$CorrectionObservationsTable, CorrectionObservationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CorrectionObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedKeyMeta = const VerificationMeta(
    'normalizedKey',
  );
  @override
  late final GeneratedColumn<String> normalizedKey = GeneratedColumn<String>(
    'normalized_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sourceTextMeta = const VerificationMeta(
    'sourceText',
  );
  @override
  late final GeneratedColumn<String> sourceText = GeneratedColumn<String>(
    'source_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTextMeta = const VerificationMeta(
    'targetText',
  );
  @override
  late final GeneratedColumn<String> targetText = GeneratedColumn<String>(
    'target_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceCountMeta = const VerificationMeta(
    'occurrenceCount',
  );
  @override
  late final GeneratedColumn<int> occurrenceCount = GeneratedColumn<int>(
    'occurrence_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstSeenAtMeta = const VerificationMeta(
    'firstSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeenAt = GeneratedColumn<DateTime>(
    'first_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    normalizedKey,
    sourceText,
    targetText,
    occurrenceCount,
    status,
    source,
    firstSeenAt,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'correction_observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CorrectionObservationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('normalized_key')) {
      context.handle(
        _normalizedKeyMeta,
        normalizedKey.isAcceptableOrUnknown(
          data['normalized_key']!,
          _normalizedKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedKeyMeta);
    }
    if (data.containsKey('source_text')) {
      context.handle(
        _sourceTextMeta,
        sourceText.isAcceptableOrUnknown(data['source_text']!, _sourceTextMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTextMeta);
    }
    if (data.containsKey('target_text')) {
      context.handle(
        _targetTextMeta,
        targetText.isAcceptableOrUnknown(data['target_text']!, _targetTextMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTextMeta);
    }
    if (data.containsKey('occurrence_count')) {
      context.handle(
        _occurrenceCountMeta,
        occurrenceCount.isAcceptableOrUnknown(
          data['occurrence_count']!,
          _occurrenceCountMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
        _firstSeenAtMeta,
        firstSeenAt.isAcceptableOrUnknown(
          data['first_seen_at']!,
          _firstSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CorrectionObservationRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CorrectionObservationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      normalizedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_key'],
      )!,
      sourceText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_text'],
      )!,
      targetText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_text'],
      )!,
      occurrenceCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurrence_count'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      firstSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
    );
  }

  @override
  $CorrectionObservationsTable createAlias(String alias) {
    return $CorrectionObservationsTable(attachedDatabase, alias);
  }
}

class CorrectionObservationRow extends DataClass
    implements Insertable<CorrectionObservationRow> {
  final String id;
  final String normalizedKey;
  final String sourceText;
  final String targetText;
  final int occurrenceCount;

  /// `pending` / `accepted` / `rejected` — see [CorrectionObservationStatus]
  /// in `correction_candidate_detector.dart`. Text-backed like other
  /// enum-ish columns in this file (e.g. `TextReplacements.origin`).
  final String status;

  /// `voiceCommand` / `manualEdit` — see `CorrectionSignalSource` in
  /// `correction_signal.dart`.
  final String source;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  const CorrectionObservationRow({
    required this.id,
    required this.normalizedKey,
    required this.sourceText,
    required this.targetText,
    required this.occurrenceCount,
    required this.status,
    required this.source,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['normalized_key'] = Variable<String>(normalizedKey);
    map['source_text'] = Variable<String>(sourceText);
    map['target_text'] = Variable<String>(targetText);
    map['occurrence_count'] = Variable<int>(occurrenceCount);
    map['status'] = Variable<String>(status);
    map['source'] = Variable<String>(source);
    map['first_seen_at'] = Variable<DateTime>(firstSeenAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    return map;
  }

  CorrectionObservationsCompanion toCompanion(bool nullToAbsent) {
    return CorrectionObservationsCompanion(
      id: Value(id),
      normalizedKey: Value(normalizedKey),
      sourceText: Value(sourceText),
      targetText: Value(targetText),
      occurrenceCount: Value(occurrenceCount),
      status: Value(status),
      source: Value(source),
      firstSeenAt: Value(firstSeenAt),
      lastSeenAt: Value(lastSeenAt),
    );
  }

  factory CorrectionObservationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CorrectionObservationRow(
      id: serializer.fromJson<String>(json['id']),
      normalizedKey: serializer.fromJson<String>(json['normalizedKey']),
      sourceText: serializer.fromJson<String>(json['sourceText']),
      targetText: serializer.fromJson<String>(json['targetText']),
      occurrenceCount: serializer.fromJson<int>(json['occurrenceCount']),
      status: serializer.fromJson<String>(json['status']),
      source: serializer.fromJson<String>(json['source']),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'normalizedKey': serializer.toJson<String>(normalizedKey),
      'sourceText': serializer.toJson<String>(sourceText),
      'targetText': serializer.toJson<String>(targetText),
      'occurrenceCount': serializer.toJson<int>(occurrenceCount),
      'status': serializer.toJson<String>(status),
      'source': serializer.toJson<String>(source),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
    };
  }

  CorrectionObservationRow copyWith({
    String? id,
    String? normalizedKey,
    String? sourceText,
    String? targetText,
    int? occurrenceCount,
    String? status,
    String? source,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
  }) => CorrectionObservationRow(
    id: id ?? this.id,
    normalizedKey: normalizedKey ?? this.normalizedKey,
    sourceText: sourceText ?? this.sourceText,
    targetText: targetText ?? this.targetText,
    occurrenceCount: occurrenceCount ?? this.occurrenceCount,
    status: status ?? this.status,
    source: source ?? this.source,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );
  CorrectionObservationRow copyWithCompanion(
    CorrectionObservationsCompanion data,
  ) {
    return CorrectionObservationRow(
      id: data.id.present ? data.id.value : this.id,
      normalizedKey: data.normalizedKey.present
          ? data.normalizedKey.value
          : this.normalizedKey,
      sourceText: data.sourceText.present
          ? data.sourceText.value
          : this.sourceText,
      targetText: data.targetText.present
          ? data.targetText.value
          : this.targetText,
      occurrenceCount: data.occurrenceCount.present
          ? data.occurrenceCount.value
          : this.occurrenceCount,
      status: data.status.present ? data.status.value : this.status,
      source: data.source.present ? data.source.value : this.source,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CorrectionObservationRow(')
          ..write('id: $id, ')
          ..write('normalizedKey: $normalizedKey, ')
          ..write('sourceText: $sourceText, ')
          ..write('targetText: $targetText, ')
          ..write('occurrenceCount: $occurrenceCount, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    normalizedKey,
    sourceText,
    targetText,
    occurrenceCount,
    status,
    source,
    firstSeenAt,
    lastSeenAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CorrectionObservationRow &&
          other.id == this.id &&
          other.normalizedKey == this.normalizedKey &&
          other.sourceText == this.sourceText &&
          other.targetText == this.targetText &&
          other.occurrenceCount == this.occurrenceCount &&
          other.status == this.status &&
          other.source == this.source &&
          other.firstSeenAt == this.firstSeenAt &&
          other.lastSeenAt == this.lastSeenAt);
}

class CorrectionObservationsCompanion
    extends UpdateCompanion<CorrectionObservationRow> {
  final Value<String> id;
  final Value<String> normalizedKey;
  final Value<String> sourceText;
  final Value<String> targetText;
  final Value<int> occurrenceCount;
  final Value<String> status;
  final Value<String> source;
  final Value<DateTime> firstSeenAt;
  final Value<DateTime> lastSeenAt;
  final Value<int> rowid;
  const CorrectionObservationsCompanion({
    this.id = const Value.absent(),
    this.normalizedKey = const Value.absent(),
    this.sourceText = const Value.absent(),
    this.targetText = const Value.absent(),
    this.occurrenceCount = const Value.absent(),
    this.status = const Value.absent(),
    this.source = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CorrectionObservationsCompanion.insert({
    required String id,
    required String normalizedKey,
    required String sourceText,
    required String targetText,
    this.occurrenceCount = const Value.absent(),
    this.status = const Value.absent(),
    required String source,
    required DateTime firstSeenAt,
    required DateTime lastSeenAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       normalizedKey = Value(normalizedKey),
       sourceText = Value(sourceText),
       targetText = Value(targetText),
       source = Value(source),
       firstSeenAt = Value(firstSeenAt),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<CorrectionObservationRow> custom({
    Expression<String>? id,
    Expression<String>? normalizedKey,
    Expression<String>? sourceText,
    Expression<String>? targetText,
    Expression<int>? occurrenceCount,
    Expression<String>? status,
    Expression<String>? source,
    Expression<DateTime>? firstSeenAt,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (normalizedKey != null) 'normalized_key': normalizedKey,
      if (sourceText != null) 'source_text': sourceText,
      if (targetText != null) 'target_text': targetText,
      if (occurrenceCount != null) 'occurrence_count': occurrenceCount,
      if (status != null) 'status': status,
      if (source != null) 'source': source,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CorrectionObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? normalizedKey,
    Value<String>? sourceText,
    Value<String>? targetText,
    Value<int>? occurrenceCount,
    Value<String>? status,
    Value<String>? source,
    Value<DateTime>? firstSeenAt,
    Value<DateTime>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return CorrectionObservationsCompanion(
      id: id ?? this.id,
      normalizedKey: normalizedKey ?? this.normalizedKey,
      sourceText: sourceText ?? this.sourceText,
      targetText: targetText ?? this.targetText,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      status: status ?? this.status,
      source: source ?? this.source,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (normalizedKey.present) {
      map['normalized_key'] = Variable<String>(normalizedKey.value);
    }
    if (sourceText.present) {
      map['source_text'] = Variable<String>(sourceText.value);
    }
    if (targetText.present) {
      map['target_text'] = Variable<String>(targetText.value);
    }
    if (occurrenceCount.present) {
      map['occurrence_count'] = Variable<int>(occurrenceCount.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<DateTime>(firstSeenAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CorrectionObservationsCompanion(')
          ..write('id: $id, ')
          ..write('normalizedKey: $normalizedKey, ')
          ..write('sourceText: $sourceText, ')
          ..write('targetText: $targetText, ')
          ..write('occurrenceCount: $occurrenceCount, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppProfilesTable extends AppProfiles
    with TableInfo<$AppProfilesTable, AppProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _smartModeMeta = const VerificationMeta(
    'smartMode',
  );
  @override
  late final GeneratedColumn<String> smartMode = GeneratedColumn<String>(
    'smart_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('standard'),
  );
  static const VerificationMeta _asrLanguageMeta = const VerificationMeta(
    'asrLanguage',
  );
  @override
  late final GeneratedColumn<String> asrLanguage = GeneratedColumn<String>(
    'asr_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contextSourceMeta = const VerificationMeta(
    'contextSource',
  );
  @override
  late final GeneratedColumn<String> contextSource = GeneratedColumn<String>(
    'context_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _hotkeyKeyMeta = const VerificationMeta(
    'hotkeyKey',
  );
  @override
  late final GeneratedColumn<String> hotkeyKey = GeneratedColumn<String>(
    'hotkey_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hotkeyModifiersMeta = const VerificationMeta(
    'hotkeyModifiers',
  );
  @override
  late final GeneratedColumn<String> hotkeyModifiers = GeneratedColumn<String>(
    'hotkey_modifiers',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _afterTranscriptionMeta =
      const VerificationMeta('afterTranscription');
  @override
  late final GeneratedColumn<String> afterTranscription =
      GeneratedColumn<String>(
        'after_transcription',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _microphoneMeta = const VerificationMeta(
    'microphone',
  );
  @override
  late final GeneratedColumn<String> microphone = GeneratedColumn<String>(
    'microphone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _consentProviderMeta = const VerificationMeta(
    'consentProvider',
  );
  @override
  late final GeneratedColumn<String> consentProvider = GeneratedColumn<String>(
    'consent_provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _consentSelectionMeta = const VerificationMeta(
    'consentSelection',
  );
  @override
  late final GeneratedColumn<bool> consentSelection = GeneratedColumn<bool>(
    'consent_selection',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("consent_selection" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _consentClipboardMeta = const VerificationMeta(
    'consentClipboard',
  );
  @override
  late final GeneratedColumn<bool> consentClipboard = GeneratedColumn<bool>(
    'consent_clipboard',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("consent_clipboard" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _consentTextVersionMeta =
      const VerificationMeta('consentTextVersion');
  @override
  late final GeneratedColumn<String> consentTextVersion =
      GeneratedColumn<String>(
        'consent_text_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _consentGivenAtMeta = const VerificationMeta(
    'consentGivenAt',
  );
  @override
  late final GeneratedColumn<DateTime> consentGivenAt =
      GeneratedColumn<DateTime>(
        'consent_given_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    position,
    smartMode,
    asrLanguage,
    modelId,
    contextSource,
    hotkeyKey,
    hotkeyModifiers,
    afterTranscription,
    microphone,
    consentProvider,
    consentSelection,
    consentClipboard,
    consentTextVersion,
    consentGivenAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('smart_mode')) {
      context.handle(
        _smartModeMeta,
        smartMode.isAcceptableOrUnknown(data['smart_mode']!, _smartModeMeta),
      );
    }
    if (data.containsKey('asr_language')) {
      context.handle(
        _asrLanguageMeta,
        asrLanguage.isAcceptableOrUnknown(
          data['asr_language']!,
          _asrLanguageMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('context_source')) {
      context.handle(
        _contextSourceMeta,
        contextSource.isAcceptableOrUnknown(
          data['context_source']!,
          _contextSourceMeta,
        ),
      );
    }
    if (data.containsKey('hotkey_key')) {
      context.handle(
        _hotkeyKeyMeta,
        hotkeyKey.isAcceptableOrUnknown(data['hotkey_key']!, _hotkeyKeyMeta),
      );
    }
    if (data.containsKey('hotkey_modifiers')) {
      context.handle(
        _hotkeyModifiersMeta,
        hotkeyModifiers.isAcceptableOrUnknown(
          data['hotkey_modifiers']!,
          _hotkeyModifiersMeta,
        ),
      );
    }
    if (data.containsKey('after_transcription')) {
      context.handle(
        _afterTranscriptionMeta,
        afterTranscription.isAcceptableOrUnknown(
          data['after_transcription']!,
          _afterTranscriptionMeta,
        ),
      );
    }
    if (data.containsKey('microphone')) {
      context.handle(
        _microphoneMeta,
        microphone.isAcceptableOrUnknown(data['microphone']!, _microphoneMeta),
      );
    }
    if (data.containsKey('consent_provider')) {
      context.handle(
        _consentProviderMeta,
        consentProvider.isAcceptableOrUnknown(
          data['consent_provider']!,
          _consentProviderMeta,
        ),
      );
    }
    if (data.containsKey('consent_selection')) {
      context.handle(
        _consentSelectionMeta,
        consentSelection.isAcceptableOrUnknown(
          data['consent_selection']!,
          _consentSelectionMeta,
        ),
      );
    }
    if (data.containsKey('consent_clipboard')) {
      context.handle(
        _consentClipboardMeta,
        consentClipboard.isAcceptableOrUnknown(
          data['consent_clipboard']!,
          _consentClipboardMeta,
        ),
      );
    }
    if (data.containsKey('consent_text_version')) {
      context.handle(
        _consentTextVersionMeta,
        consentTextVersion.isAcceptableOrUnknown(
          data['consent_text_version']!,
          _consentTextVersionMeta,
        ),
      );
    }
    if (data.containsKey('consent_given_at')) {
      context.handle(
        _consentGivenAtMeta,
        consentGivenAt.isAcceptableOrUnknown(
          data['consent_given_at']!,
          _consentGivenAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      smartMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smart_mode'],
      )!,
      asrLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asr_language'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      contextSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_source'],
      )!,
      hotkeyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hotkey_key'],
      ),
      hotkeyModifiers: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hotkey_modifiers'],
      ),
      afterTranscription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_transcription'],
      ),
      microphone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}microphone'],
      ),
      consentProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_provider'],
      ),
      consentSelection: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}consent_selection'],
      )!,
      consentClipboard: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}consent_clipboard'],
      )!,
      consentTextVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_text_version'],
      ),
      consentGivenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}consent_given_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppProfilesTable createAlias(String alias) {
    return $AppProfilesTable(attachedDatabase, alias);
  }
}

class AppProfileRow extends DataClass implements Insertable<AppProfileRow> {
  final String id;
  final String name;
  final int position;
  final String smartMode;
  final String? asrLanguage;
  final String? modelId;
  final String contextSource;
  final String? hotkeyKey;
  final String? hotkeyModifiers;
  final String? afterTranscription;
  final String? microphone;
  final String? consentProvider;
  final bool consentSelection;
  final bool consentClipboard;
  final String? consentTextVersion;
  final DateTime? consentGivenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AppProfileRow({
    required this.id,
    required this.name,
    required this.position,
    required this.smartMode,
    this.asrLanguage,
    this.modelId,
    required this.contextSource,
    this.hotkeyKey,
    this.hotkeyModifiers,
    this.afterTranscription,
    this.microphone,
    this.consentProvider,
    required this.consentSelection,
    required this.consentClipboard,
    this.consentTextVersion,
    this.consentGivenAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    map['smart_mode'] = Variable<String>(smartMode);
    if (!nullToAbsent || asrLanguage != null) {
      map['asr_language'] = Variable<String>(asrLanguage);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    map['context_source'] = Variable<String>(contextSource);
    if (!nullToAbsent || hotkeyKey != null) {
      map['hotkey_key'] = Variable<String>(hotkeyKey);
    }
    if (!nullToAbsent || hotkeyModifiers != null) {
      map['hotkey_modifiers'] = Variable<String>(hotkeyModifiers);
    }
    if (!nullToAbsent || afterTranscription != null) {
      map['after_transcription'] = Variable<String>(afterTranscription);
    }
    if (!nullToAbsent || microphone != null) {
      map['microphone'] = Variable<String>(microphone);
    }
    if (!nullToAbsent || consentProvider != null) {
      map['consent_provider'] = Variable<String>(consentProvider);
    }
    map['consent_selection'] = Variable<bool>(consentSelection);
    map['consent_clipboard'] = Variable<bool>(consentClipboard);
    if (!nullToAbsent || consentTextVersion != null) {
      map['consent_text_version'] = Variable<String>(consentTextVersion);
    }
    if (!nullToAbsent || consentGivenAt != null) {
      map['consent_given_at'] = Variable<DateTime>(consentGivenAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppProfilesCompanion toCompanion(bool nullToAbsent) {
    return AppProfilesCompanion(
      id: Value(id),
      name: Value(name),
      position: Value(position),
      smartMode: Value(smartMode),
      asrLanguage: asrLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(asrLanguage),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      contextSource: Value(contextSource),
      hotkeyKey: hotkeyKey == null && nullToAbsent
          ? const Value.absent()
          : Value(hotkeyKey),
      hotkeyModifiers: hotkeyModifiers == null && nullToAbsent
          ? const Value.absent()
          : Value(hotkeyModifiers),
      afterTranscription: afterTranscription == null && nullToAbsent
          ? const Value.absent()
          : Value(afterTranscription),
      microphone: microphone == null && nullToAbsent
          ? const Value.absent()
          : Value(microphone),
      consentProvider: consentProvider == null && nullToAbsent
          ? const Value.absent()
          : Value(consentProvider),
      consentSelection: Value(consentSelection),
      consentClipboard: Value(consentClipboard),
      consentTextVersion: consentTextVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(consentTextVersion),
      consentGivenAt: consentGivenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(consentGivenAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppProfileRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      smartMode: serializer.fromJson<String>(json['smartMode']),
      asrLanguage: serializer.fromJson<String?>(json['asrLanguage']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      contextSource: serializer.fromJson<String>(json['contextSource']),
      hotkeyKey: serializer.fromJson<String?>(json['hotkeyKey']),
      hotkeyModifiers: serializer.fromJson<String?>(json['hotkeyModifiers']),
      afterTranscription: serializer.fromJson<String?>(
        json['afterTranscription'],
      ),
      microphone: serializer.fromJson<String?>(json['microphone']),
      consentProvider: serializer.fromJson<String?>(json['consentProvider']),
      consentSelection: serializer.fromJson<bool>(json['consentSelection']),
      consentClipboard: serializer.fromJson<bool>(json['consentClipboard']),
      consentTextVersion: serializer.fromJson<String?>(
        json['consentTextVersion'],
      ),
      consentGivenAt: serializer.fromJson<DateTime?>(json['consentGivenAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'smartMode': serializer.toJson<String>(smartMode),
      'asrLanguage': serializer.toJson<String?>(asrLanguage),
      'modelId': serializer.toJson<String?>(modelId),
      'contextSource': serializer.toJson<String>(contextSource),
      'hotkeyKey': serializer.toJson<String?>(hotkeyKey),
      'hotkeyModifiers': serializer.toJson<String?>(hotkeyModifiers),
      'afterTranscription': serializer.toJson<String?>(afterTranscription),
      'microphone': serializer.toJson<String?>(microphone),
      'consentProvider': serializer.toJson<String?>(consentProvider),
      'consentSelection': serializer.toJson<bool>(consentSelection),
      'consentClipboard': serializer.toJson<bool>(consentClipboard),
      'consentTextVersion': serializer.toJson<String?>(consentTextVersion),
      'consentGivenAt': serializer.toJson<DateTime?>(consentGivenAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppProfileRow copyWith({
    String? id,
    String? name,
    int? position,
    String? smartMode,
    Value<String?> asrLanguage = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
    String? contextSource,
    Value<String?> hotkeyKey = const Value.absent(),
    Value<String?> hotkeyModifiers = const Value.absent(),
    Value<String?> afterTranscription = const Value.absent(),
    Value<String?> microphone = const Value.absent(),
    Value<String?> consentProvider = const Value.absent(),
    bool? consentSelection,
    bool? consentClipboard,
    Value<String?> consentTextVersion = const Value.absent(),
    Value<DateTime?> consentGivenAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AppProfileRow(
    id: id ?? this.id,
    name: name ?? this.name,
    position: position ?? this.position,
    smartMode: smartMode ?? this.smartMode,
    asrLanguage: asrLanguage.present ? asrLanguage.value : this.asrLanguage,
    modelId: modelId.present ? modelId.value : this.modelId,
    contextSource: contextSource ?? this.contextSource,
    hotkeyKey: hotkeyKey.present ? hotkeyKey.value : this.hotkeyKey,
    hotkeyModifiers: hotkeyModifiers.present
        ? hotkeyModifiers.value
        : this.hotkeyModifiers,
    afterTranscription: afterTranscription.present
        ? afterTranscription.value
        : this.afterTranscription,
    microphone: microphone.present ? microphone.value : this.microphone,
    consentProvider: consentProvider.present
        ? consentProvider.value
        : this.consentProvider,
    consentSelection: consentSelection ?? this.consentSelection,
    consentClipboard: consentClipboard ?? this.consentClipboard,
    consentTextVersion: consentTextVersion.present
        ? consentTextVersion.value
        : this.consentTextVersion,
    consentGivenAt: consentGivenAt.present
        ? consentGivenAt.value
        : this.consentGivenAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppProfileRow copyWithCompanion(AppProfilesCompanion data) {
    return AppProfileRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      smartMode: data.smartMode.present ? data.smartMode.value : this.smartMode,
      asrLanguage: data.asrLanguage.present
          ? data.asrLanguage.value
          : this.asrLanguage,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      contextSource: data.contextSource.present
          ? data.contextSource.value
          : this.contextSource,
      hotkeyKey: data.hotkeyKey.present ? data.hotkeyKey.value : this.hotkeyKey,
      hotkeyModifiers: data.hotkeyModifiers.present
          ? data.hotkeyModifiers.value
          : this.hotkeyModifiers,
      afterTranscription: data.afterTranscription.present
          ? data.afterTranscription.value
          : this.afterTranscription,
      microphone: data.microphone.present
          ? data.microphone.value
          : this.microphone,
      consentProvider: data.consentProvider.present
          ? data.consentProvider.value
          : this.consentProvider,
      consentSelection: data.consentSelection.present
          ? data.consentSelection.value
          : this.consentSelection,
      consentClipboard: data.consentClipboard.present
          ? data.consentClipboard.value
          : this.consentClipboard,
      consentTextVersion: data.consentTextVersion.present
          ? data.consentTextVersion.value
          : this.consentTextVersion,
      consentGivenAt: data.consentGivenAt.present
          ? data.consentGivenAt.value
          : this.consentGivenAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppProfileRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('smartMode: $smartMode, ')
          ..write('asrLanguage: $asrLanguage, ')
          ..write('modelId: $modelId, ')
          ..write('contextSource: $contextSource, ')
          ..write('hotkeyKey: $hotkeyKey, ')
          ..write('hotkeyModifiers: $hotkeyModifiers, ')
          ..write('afterTranscription: $afterTranscription, ')
          ..write('microphone: $microphone, ')
          ..write('consentProvider: $consentProvider, ')
          ..write('consentSelection: $consentSelection, ')
          ..write('consentClipboard: $consentClipboard, ')
          ..write('consentTextVersion: $consentTextVersion, ')
          ..write('consentGivenAt: $consentGivenAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    position,
    smartMode,
    asrLanguage,
    modelId,
    contextSource,
    hotkeyKey,
    hotkeyModifiers,
    afterTranscription,
    microphone,
    consentProvider,
    consentSelection,
    consentClipboard,
    consentTextVersion,
    consentGivenAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppProfileRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.position == this.position &&
          other.smartMode == this.smartMode &&
          other.asrLanguage == this.asrLanguage &&
          other.modelId == this.modelId &&
          other.contextSource == this.contextSource &&
          other.hotkeyKey == this.hotkeyKey &&
          other.hotkeyModifiers == this.hotkeyModifiers &&
          other.afterTranscription == this.afterTranscription &&
          other.microphone == this.microphone &&
          other.consentProvider == this.consentProvider &&
          other.consentSelection == this.consentSelection &&
          other.consentClipboard == this.consentClipboard &&
          other.consentTextVersion == this.consentTextVersion &&
          other.consentGivenAt == this.consentGivenAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AppProfilesCompanion extends UpdateCompanion<AppProfileRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> position;
  final Value<String> smartMode;
  final Value<String?> asrLanguage;
  final Value<String?> modelId;
  final Value<String> contextSource;
  final Value<String?> hotkeyKey;
  final Value<String?> hotkeyModifiers;
  final Value<String?> afterTranscription;
  final Value<String?> microphone;
  final Value<String?> consentProvider;
  final Value<bool> consentSelection;
  final Value<bool> consentClipboard;
  final Value<String?> consentTextVersion;
  final Value<DateTime?> consentGivenAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.smartMode = const Value.absent(),
    this.asrLanguage = const Value.absent(),
    this.modelId = const Value.absent(),
    this.contextSource = const Value.absent(),
    this.hotkeyKey = const Value.absent(),
    this.hotkeyModifiers = const Value.absent(),
    this.afterTranscription = const Value.absent(),
    this.microphone = const Value.absent(),
    this.consentProvider = const Value.absent(),
    this.consentSelection = const Value.absent(),
    this.consentClipboard = const Value.absent(),
    this.consentTextVersion = const Value.absent(),
    this.consentGivenAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppProfilesCompanion.insert({
    required String id,
    required String name,
    this.position = const Value.absent(),
    this.smartMode = const Value.absent(),
    this.asrLanguage = const Value.absent(),
    this.modelId = const Value.absent(),
    this.contextSource = const Value.absent(),
    this.hotkeyKey = const Value.absent(),
    this.hotkeyModifiers = const Value.absent(),
    this.afterTranscription = const Value.absent(),
    this.microphone = const Value.absent(),
    this.consentProvider = const Value.absent(),
    this.consentSelection = const Value.absent(),
    this.consentClipboard = const Value.absent(),
    this.consentTextVersion = const Value.absent(),
    this.consentGivenAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AppProfileRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? position,
    Expression<String>? smartMode,
    Expression<String>? asrLanguage,
    Expression<String>? modelId,
    Expression<String>? contextSource,
    Expression<String>? hotkeyKey,
    Expression<String>? hotkeyModifiers,
    Expression<String>? afterTranscription,
    Expression<String>? microphone,
    Expression<String>? consentProvider,
    Expression<bool>? consentSelection,
    Expression<bool>? consentClipboard,
    Expression<String>? consentTextVersion,
    Expression<DateTime>? consentGivenAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (smartMode != null) 'smart_mode': smartMode,
      if (asrLanguage != null) 'asr_language': asrLanguage,
      if (modelId != null) 'model_id': modelId,
      if (contextSource != null) 'context_source': contextSource,
      if (hotkeyKey != null) 'hotkey_key': hotkeyKey,
      if (hotkeyModifiers != null) 'hotkey_modifiers': hotkeyModifiers,
      if (afterTranscription != null) 'after_transcription': afterTranscription,
      if (microphone != null) 'microphone': microphone,
      if (consentProvider != null) 'consent_provider': consentProvider,
      if (consentSelection != null) 'consent_selection': consentSelection,
      if (consentClipboard != null) 'consent_clipboard': consentClipboard,
      if (consentTextVersion != null)
        'consent_text_version': consentTextVersion,
      if (consentGivenAt != null) 'consent_given_at': consentGivenAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? position,
    Value<String>? smartMode,
    Value<String?>? asrLanguage,
    Value<String?>? modelId,
    Value<String>? contextSource,
    Value<String?>? hotkeyKey,
    Value<String?>? hotkeyModifiers,
    Value<String?>? afterTranscription,
    Value<String?>? microphone,
    Value<String?>? consentProvider,
    Value<bool>? consentSelection,
    Value<bool>? consentClipboard,
    Value<String?>? consentTextVersion,
    Value<DateTime?>? consentGivenAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      smartMode: smartMode ?? this.smartMode,
      asrLanguage: asrLanguage ?? this.asrLanguage,
      modelId: modelId ?? this.modelId,
      contextSource: contextSource ?? this.contextSource,
      hotkeyKey: hotkeyKey ?? this.hotkeyKey,
      hotkeyModifiers: hotkeyModifiers ?? this.hotkeyModifiers,
      afterTranscription: afterTranscription ?? this.afterTranscription,
      microphone: microphone ?? this.microphone,
      consentProvider: consentProvider ?? this.consentProvider,
      consentSelection: consentSelection ?? this.consentSelection,
      consentClipboard: consentClipboard ?? this.consentClipboard,
      consentTextVersion: consentTextVersion ?? this.consentTextVersion,
      consentGivenAt: consentGivenAt ?? this.consentGivenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (smartMode.present) {
      map['smart_mode'] = Variable<String>(smartMode.value);
    }
    if (asrLanguage.present) {
      map['asr_language'] = Variable<String>(asrLanguage.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (contextSource.present) {
      map['context_source'] = Variable<String>(contextSource.value);
    }
    if (hotkeyKey.present) {
      map['hotkey_key'] = Variable<String>(hotkeyKey.value);
    }
    if (hotkeyModifiers.present) {
      map['hotkey_modifiers'] = Variable<String>(hotkeyModifiers.value);
    }
    if (afterTranscription.present) {
      map['after_transcription'] = Variable<String>(afterTranscription.value);
    }
    if (microphone.present) {
      map['microphone'] = Variable<String>(microphone.value);
    }
    if (consentProvider.present) {
      map['consent_provider'] = Variable<String>(consentProvider.value);
    }
    if (consentSelection.present) {
      map['consent_selection'] = Variable<bool>(consentSelection.value);
    }
    if (consentClipboard.present) {
      map['consent_clipboard'] = Variable<bool>(consentClipboard.value);
    }
    if (consentTextVersion.present) {
      map['consent_text_version'] = Variable<String>(consentTextVersion.value);
    }
    if (consentGivenAt.present) {
      map['consent_given_at'] = Variable<DateTime>(consentGivenAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('smartMode: $smartMode, ')
          ..write('asrLanguage: $asrLanguage, ')
          ..write('modelId: $modelId, ')
          ..write('contextSource: $contextSource, ')
          ..write('hotkeyKey: $hotkeyKey, ')
          ..write('hotkeyModifiers: $hotkeyModifiers, ')
          ..write('afterTranscription: $afterTranscription, ')
          ..write('microphone: $microphone, ')
          ..write('consentProvider: $consentProvider, ')
          ..write('consentSelection: $consentSelection, ')
          ..write('consentClipboard: $consentClipboard, ')
          ..write('consentTextVersion: $consentTextVersion, ')
          ..write('consentGivenAt: $consentGivenAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppProfileRulesTable extends AppProfileRules
    with TableInfo<$AppProfileRulesTable, AppProfileRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppProfileRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _identifierMeta = const VerificationMeta(
    'identifier',
  );
  @override
  late final GeneratedColumn<String> identifier = GeneratedColumn<String>(
    'identifier',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teamIdMeta = const VerificationMeta('teamId');
  @override
  late final GeneratedColumn<String> teamId = GeneratedColumn<String>(
    'team_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    position,
    identifier,
    teamId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_profile_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppProfileRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('identifier')) {
      context.handle(
        _identifierMeta,
        identifier.isAcceptableOrUnknown(data['identifier']!, _identifierMeta),
      );
    } else if (isInserting) {
      context.missing(_identifierMeta);
    }
    if (data.containsKey('team_id')) {
      context.handle(
        _teamIdMeta,
        teamId.isAcceptableOrUnknown(data['team_id']!, _teamIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppProfileRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppProfileRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      identifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identifier'],
      )!,
      teamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_id'],
      ),
    );
  }

  @override
  $AppProfileRulesTable createAlias(String alias) {
    return $AppProfileRulesTable(attachedDatabase, alias);
  }
}

class AppProfileRuleRow extends DataClass
    implements Insertable<AppProfileRuleRow> {
  final String id;
  final String profileId;
  final int position;
  final String identifier;

  /// macOS code-signing team identifier; null when not recorded.
  final String? teamId;
  const AppProfileRuleRow({
    required this.id,
    required this.profileId,
    required this.position,
    required this.identifier,
    this.teamId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['position'] = Variable<int>(position);
    map['identifier'] = Variable<String>(identifier);
    if (!nullToAbsent || teamId != null) {
      map['team_id'] = Variable<String>(teamId);
    }
    return map;
  }

  AppProfileRulesCompanion toCompanion(bool nullToAbsent) {
    return AppProfileRulesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      position: Value(position),
      identifier: Value(identifier),
      teamId: teamId == null && nullToAbsent
          ? const Value.absent()
          : Value(teamId),
    );
  }

  factory AppProfileRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppProfileRuleRow(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      position: serializer.fromJson<int>(json['position']),
      identifier: serializer.fromJson<String>(json['identifier']),
      teamId: serializer.fromJson<String?>(json['teamId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'position': serializer.toJson<int>(position),
      'identifier': serializer.toJson<String>(identifier),
      'teamId': serializer.toJson<String?>(teamId),
    };
  }

  AppProfileRuleRow copyWith({
    String? id,
    String? profileId,
    int? position,
    String? identifier,
    Value<String?> teamId = const Value.absent(),
  }) => AppProfileRuleRow(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    position: position ?? this.position,
    identifier: identifier ?? this.identifier,
    teamId: teamId.present ? teamId.value : this.teamId,
  );
  AppProfileRuleRow copyWithCompanion(AppProfileRulesCompanion data) {
    return AppProfileRuleRow(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      position: data.position.present ? data.position.value : this.position,
      identifier: data.identifier.present
          ? data.identifier.value
          : this.identifier,
      teamId: data.teamId.present ? data.teamId.value : this.teamId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppProfileRuleRow(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('position: $position, ')
          ..write('identifier: $identifier, ')
          ..write('teamId: $teamId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, profileId, position, identifier, teamId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppProfileRuleRow &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.position == this.position &&
          other.identifier == this.identifier &&
          other.teamId == this.teamId);
}

class AppProfileRulesCompanion extends UpdateCompanion<AppProfileRuleRow> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<int> position;
  final Value<String> identifier;
  final Value<String?> teamId;
  final Value<int> rowid;
  const AppProfileRulesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.position = const Value.absent(),
    this.identifier = const Value.absent(),
    this.teamId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppProfileRulesCompanion.insert({
    required String id,
    required String profileId,
    this.position = const Value.absent(),
    required String identifier,
    this.teamId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       identifier = Value(identifier);
  static Insertable<AppProfileRuleRow> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<int>? position,
    Expression<String>? identifier,
    Expression<String>? teamId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (position != null) 'position': position,
      if (identifier != null) 'identifier': identifier,
      if (teamId != null) 'team_id': teamId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppProfileRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<int>? position,
    Value<String>? identifier,
    Value<String?>? teamId,
    Value<int>? rowid,
  }) {
    return AppProfileRulesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      position: position ?? this.position,
      identifier: identifier ?? this.identifier,
      teamId: teamId ?? this.teamId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (identifier.present) {
      map['identifier'] = Variable<String>(identifier.value);
    }
    if (teamId.present) {
      map['team_id'] = Variable<String>(teamId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppProfileRulesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('position: $position, ')
          ..write('identifier: $identifier, ')
          ..write('teamId: $teamId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HistoryDatabase extends GeneratedDatabase {
  _$HistoryDatabase(QueryExecutor e) : super(e);
  $HistoryDatabaseManager get managers => $HistoryDatabaseManager(this);
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  late final $DailyStatsTable dailyStats = $DailyStatsTable(this);
  late final $EntryNotesTable entryNotes = $EntryNotesTable(this);
  late final $EntryAttachmentsTable entryAttachments = $EntryAttachmentsTable(
    this,
  );
  late final $TextReplacementsTable textReplacements = $TextReplacementsTable(
    this,
  );
  late final $TextReplacementTriggersTable textReplacementTriggers =
      $TextReplacementTriggersTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $EntryTagsTable entryTags = $EntryTagsTable(this);
  late final $HotkeyLatencyEntriesTable hotkeyLatencyEntries =
      $HotkeyLatencyEntriesTable(this);
  late final $SnippetsTable snippets = $SnippetsTable(this);
  late final $SnippetFieldsTable snippetFields = $SnippetFieldsTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $NoteTagsTable noteTags = $NoteTagsTable(this);
  late final $NoteVersionsTable noteVersions = $NoteVersionsTable(this);
  late final $NoteAssetsTable noteAssets = $NoteAssetsTable(this);
  late final $CorrectionObservationsTable correctionObservations =
      $CorrectionObservationsTable(this);
  late final $AppProfilesTable appProfiles = $AppProfilesTable(this);
  late final $AppProfileRulesTable appProfileRules = $AppProfileRulesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    historyEntries,
    dailyStats,
    entryNotes,
    entryAttachments,
    textReplacements,
    textReplacementTriggers,
    tags,
    entryTags,
    hotkeyLatencyEntries,
    snippets,
    snippetFields,
    notes,
    noteTags,
    noteVersions,
    noteAssets,
    correctionObservations,
    appProfiles,
    appProfileRules,
  ];
}

typedef $$HistoryEntriesTableCreateCompanionBuilder =
    HistoryEntriesCompanion Function({
      required String id,
      Value<String> content,
      Value<String> title,
      required DateTime timestamp,
      Value<double> durationSec,
      Value<double> processingDurationSec,
      Value<String> language,
      Value<String> languageHint,
      Value<String> tags,
      Value<bool> pinned,
      Value<String> source,
      Value<String> model,
      Value<bool> isLocal,
      Value<double> costUsd,
      Value<bool> archived,
      Value<bool> titleEdited,
      Value<DateTime?> deletedAt,
      Value<int> colorSlot,
      Value<String?> smartModeEditedContent,
      Value<String?> originalTranscript,
      Value<String?> targetApp,
      Value<String?> smartModeInput,
      Value<String?> smartModeOutput,
      Value<bool?> smartModeApplied,
      Value<int> rowid,
    });
typedef $$HistoryEntriesTableUpdateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<String> id,
      Value<String> content,
      Value<String> title,
      Value<DateTime> timestamp,
      Value<double> durationSec,
      Value<double> processingDurationSec,
      Value<String> language,
      Value<String> languageHint,
      Value<String> tags,
      Value<bool> pinned,
      Value<String> source,
      Value<String> model,
      Value<bool> isLocal,
      Value<double> costUsd,
      Value<bool> archived,
      Value<bool> titleEdited,
      Value<DateTime?> deletedAt,
      Value<int> colorSlot,
      Value<String?> smartModeEditedContent,
      Value<String?> originalTranscript,
      Value<String?> targetApp,
      Value<String?> smartModeInput,
      Value<String?> smartModeOutput,
      Value<bool?> smartModeApplied,
      Value<int> rowid,
    });

final class $$HistoryEntriesTableReferences
    extends
        BaseReferences<_$HistoryDatabase, $HistoryEntriesTable, HistoryEntry> {
  $$HistoryEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$EntryNotesTable, List<EntryNote>>
  _entryNotesRefsTable(_$HistoryDatabase db) => MultiTypedResultKey.fromTable(
    db.entryNotes,
    aliasName: 'history_entries__id__entry_notes__entry_id',
  );

  $$EntryNotesTableProcessedTableManager get entryNotesRefs {
    final manager = $$EntryNotesTableTableManager(
      $_db,
      $_db.entryNotes,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EntryAttachmentsTable, List<EntryAttachment>>
  _entryAttachmentsRefsTable(_$HistoryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.entryAttachments,
        aliasName: 'history_entries__id__entry_attachments__entry_id',
      );

  $$EntryAttachmentsTableProcessedTableManager get entryAttachmentsRefs {
    final manager = $$EntryAttachmentsTableTableManager(
      $_db,
      $_db.entryAttachments,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _entryAttachmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EntryTagsTable, List<EntryTag>>
  _entryTagsRefsTable(_$HistoryDatabase db) => MultiTypedResultKey.fromTable(
    db.entryTags,
    aliasName: 'history_entries__id__entry_tags__entry_id',
  );

  $$EntryTagsTableProcessedTableManager get entryTagsRefs {
    final manager = $$EntryTagsTableTableManager(
      $_db,
      $_db.entryTags,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HistoryEntriesTableFilterComposer
    extends Composer<_$HistoryDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get processingDurationSec => $composableBuilder(
    column: $table.processingDurationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get languageHint => $composableBuilder(
    column: $table.languageHint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocal => $composableBuilder(
    column: $table.isLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get titleEdited => $composableBuilder(
    column: $table.titleEdited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorSlot => $composableBuilder(
    column: $table.colorSlot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smartModeEditedContent => $composableBuilder(
    column: $table.smartModeEditedContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalTranscript => $composableBuilder(
    column: $table.originalTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetApp => $composableBuilder(
    column: $table.targetApp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smartModeInput => $composableBuilder(
    column: $table.smartModeInput,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smartModeOutput => $composableBuilder(
    column: $table.smartModeOutput,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get smartModeApplied => $composableBuilder(
    column: $table.smartModeApplied,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> entryNotesRefs(
    Expression<bool> Function($$EntryNotesTableFilterComposer f) f,
  ) {
    final $$EntryNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryNotes,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryNotesTableFilterComposer(
            $db: $db,
            $table: $db.entryNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> entryAttachmentsRefs(
    Expression<bool> Function($$EntryAttachmentsTableFilterComposer f) f,
  ) {
    final $$EntryAttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryAttachments,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryAttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.entryAttachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> entryTagsRefs(
    Expression<bool> Function($$EntryTagsTableFilterComposer f) f,
  ) {
    final $$EntryTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryTags,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryTagsTableFilterComposer(
            $db: $db,
            $table: $db.entryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HistoryEntriesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get processingDurationSec => $composableBuilder(
    column: $table.processingDurationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get languageHint => $composableBuilder(
    column: $table.languageHint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocal => $composableBuilder(
    column: $table.isLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get titleEdited => $composableBuilder(
    column: $table.titleEdited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorSlot => $composableBuilder(
    column: $table.colorSlot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smartModeEditedContent => $composableBuilder(
    column: $table.smartModeEditedContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalTranscript => $composableBuilder(
    column: $table.originalTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetApp => $composableBuilder(
    column: $table.targetApp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smartModeInput => $composableBuilder(
    column: $table.smartModeInput,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smartModeOutput => $composableBuilder(
    column: $table.smartModeOutput,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get smartModeApplied => $composableBuilder(
    column: $table.smartModeApplied,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryEntriesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<double> get processingDurationSec => $composableBuilder(
    column: $table.processingDurationSec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get languageHint => $composableBuilder(
    column: $table.languageHint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<bool> get isLocal =>
      $composableBuilder(column: $table.isLocal, builder: (column) => column);

  GeneratedColumn<double> get costUsd =>
      $composableBuilder(column: $table.costUsd, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<bool> get titleEdited => $composableBuilder(
    column: $table.titleEdited,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get colorSlot =>
      $composableBuilder(column: $table.colorSlot, builder: (column) => column);

  GeneratedColumn<String> get smartModeEditedContent => $composableBuilder(
    column: $table.smartModeEditedContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalTranscript => $composableBuilder(
    column: $table.originalTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetApp =>
      $composableBuilder(column: $table.targetApp, builder: (column) => column);

  GeneratedColumn<String> get smartModeInput => $composableBuilder(
    column: $table.smartModeInput,
    builder: (column) => column,
  );

  GeneratedColumn<String> get smartModeOutput => $composableBuilder(
    column: $table.smartModeOutput,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get smartModeApplied => $composableBuilder(
    column: $table.smartModeApplied,
    builder: (column) => column,
  );

  Expression<T> entryNotesRefs<T extends Object>(
    Expression<T> Function($$EntryNotesTableAnnotationComposer a) f,
  ) {
    final $$EntryNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryNotes,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.entryNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> entryAttachmentsRefs<T extends Object>(
    Expression<T> Function($$EntryAttachmentsTableAnnotationComposer a) f,
  ) {
    final $$EntryAttachmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryAttachments,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryAttachmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.entryAttachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> entryTagsRefs<T extends Object>(
    Expression<T> Function($$EntryTagsTableAnnotationComposer a) f,
  ) {
    final $$EntryTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryTags,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.entryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $HistoryEntriesTable,
          HistoryEntry,
          $$HistoryEntriesTableFilterComposer,
          $$HistoryEntriesTableOrderingComposer,
          $$HistoryEntriesTableAnnotationComposer,
          $$HistoryEntriesTableCreateCompanionBuilder,
          $$HistoryEntriesTableUpdateCompanionBuilder,
          (HistoryEntry, $$HistoryEntriesTableReferences),
          HistoryEntry,
          PrefetchHooks Function({
            bool entryNotesRefs,
            bool entryAttachmentsRefs,
            bool entryTagsRefs,
          })
        > {
  $$HistoryEntriesTableTableManager(
    _$HistoryDatabase db,
    $HistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double> durationSec = const Value.absent(),
                Value<double> processingDurationSec = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> languageHint = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<bool> isLocal = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> titleEdited = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> colorSlot = const Value.absent(),
                Value<String?> smartModeEditedContent = const Value.absent(),
                Value<String?> originalTranscript = const Value.absent(),
                Value<String?> targetApp = const Value.absent(),
                Value<String?> smartModeInput = const Value.absent(),
                Value<String?> smartModeOutput = const Value.absent(),
                Value<bool?> smartModeApplied = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryEntriesCompanion(
                id: id,
                content: content,
                title: title,
                timestamp: timestamp,
                durationSec: durationSec,
                processingDurationSec: processingDurationSec,
                language: language,
                languageHint: languageHint,
                tags: tags,
                pinned: pinned,
                source: source,
                model: model,
                isLocal: isLocal,
                costUsd: costUsd,
                archived: archived,
                titleEdited: titleEdited,
                deletedAt: deletedAt,
                colorSlot: colorSlot,
                smartModeEditedContent: smartModeEditedContent,
                originalTranscript: originalTranscript,
                targetApp: targetApp,
                smartModeInput: smartModeInput,
                smartModeOutput: smartModeOutput,
                smartModeApplied: smartModeApplied,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> content = const Value.absent(),
                Value<String> title = const Value.absent(),
                required DateTime timestamp,
                Value<double> durationSec = const Value.absent(),
                Value<double> processingDurationSec = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> languageHint = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<bool> isLocal = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> titleEdited = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> colorSlot = const Value.absent(),
                Value<String?> smartModeEditedContent = const Value.absent(),
                Value<String?> originalTranscript = const Value.absent(),
                Value<String?> targetApp = const Value.absent(),
                Value<String?> smartModeInput = const Value.absent(),
                Value<String?> smartModeOutput = const Value.absent(),
                Value<bool?> smartModeApplied = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryEntriesCompanion.insert(
                id: id,
                content: content,
                title: title,
                timestamp: timestamp,
                durationSec: durationSec,
                processingDurationSec: processingDurationSec,
                language: language,
                languageHint: languageHint,
                tags: tags,
                pinned: pinned,
                source: source,
                model: model,
                isLocal: isLocal,
                costUsd: costUsd,
                archived: archived,
                titleEdited: titleEdited,
                deletedAt: deletedAt,
                colorSlot: colorSlot,
                smartModeEditedContent: smartModeEditedContent,
                originalTranscript: originalTranscript,
                targetApp: targetApp,
                smartModeInput: smartModeInput,
                smartModeOutput: smartModeOutput,
                smartModeApplied: smartModeApplied,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HistoryEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                entryNotesRefs = false,
                entryAttachmentsRefs = false,
                entryTagsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (entryNotesRefs) db.entryNotes,
                    if (entryAttachmentsRefs) db.entryAttachments,
                    if (entryTagsRefs) db.entryTags,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (entryNotesRefs)
                        await $_getPrefetchedData<
                          HistoryEntry,
                          $HistoryEntriesTable,
                          EntryNote
                        >(
                          currentTable: table,
                          referencedTable: $$HistoryEntriesTableReferences
                              ._entryNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HistoryEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).entryNotesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (entryAttachmentsRefs)
                        await $_getPrefetchedData<
                          HistoryEntry,
                          $HistoryEntriesTable,
                          EntryAttachment
                        >(
                          currentTable: table,
                          referencedTable: $$HistoryEntriesTableReferences
                              ._entryAttachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HistoryEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).entryAttachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (entryTagsRefs)
                        await $_getPrefetchedData<
                          HistoryEntry,
                          $HistoryEntriesTable,
                          EntryTag
                        >(
                          currentTable: table,
                          referencedTable: $$HistoryEntriesTableReferences
                              ._entryTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HistoryEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).entryTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$HistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $HistoryEntriesTable,
      HistoryEntry,
      $$HistoryEntriesTableFilterComposer,
      $$HistoryEntriesTableOrderingComposer,
      $$HistoryEntriesTableAnnotationComposer,
      $$HistoryEntriesTableCreateCompanionBuilder,
      $$HistoryEntriesTableUpdateCompanionBuilder,
      (HistoryEntry, $$HistoryEntriesTableReferences),
      HistoryEntry,
      PrefetchHooks Function({
        bool entryNotesRefs,
        bool entryAttachmentsRefs,
        bool entryTagsRefs,
      })
    >;
typedef $$DailyStatsTableCreateCompanionBuilder =
    DailyStatsCompanion Function({
      required String date,
      required String model,
      required bool isLocal,
      Value<int> count,
      Value<double> totalDurationSec,
      Value<double> totalProcessingSec,
      Value<int> totalWords,
      Value<double> totalCostUsd,
      Value<int> durUnder15s,
      Value<int> dur15To30s,
      Value<int> dur30To60s,
      Value<int> dur1To3m,
      Value<int> durOver3m,
      Value<int> rowid,
    });
typedef $$DailyStatsTableUpdateCompanionBuilder =
    DailyStatsCompanion Function({
      Value<String> date,
      Value<String> model,
      Value<bool> isLocal,
      Value<int> count,
      Value<double> totalDurationSec,
      Value<double> totalProcessingSec,
      Value<int> totalWords,
      Value<double> totalCostUsd,
      Value<int> durUnder15s,
      Value<int> dur15To30s,
      Value<int> dur30To60s,
      Value<int> dur1To3m,
      Value<int> durOver3m,
      Value<int> rowid,
    });

class $$DailyStatsTableFilterComposer
    extends Composer<_$HistoryDatabase, $DailyStatsTable> {
  $$DailyStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocal => $composableBuilder(
    column: $table.isLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalDurationSec => $composableBuilder(
    column: $table.totalDurationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalProcessingSec => $composableBuilder(
    column: $table.totalProcessingSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalCostUsd => $composableBuilder(
    column: $table.totalCostUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durUnder15s => $composableBuilder(
    column: $table.durUnder15s,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dur15To30s => $composableBuilder(
    column: $table.dur15To30s,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dur30To60s => $composableBuilder(
    column: $table.dur30To60s,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dur1To3m => $composableBuilder(
    column: $table.dur1To3m,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durOver3m => $composableBuilder(
    column: $table.durOver3m,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyStatsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $DailyStatsTable> {
  $$DailyStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocal => $composableBuilder(
    column: $table.isLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalDurationSec => $composableBuilder(
    column: $table.totalDurationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalProcessingSec => $composableBuilder(
    column: $table.totalProcessingSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalCostUsd => $composableBuilder(
    column: $table.totalCostUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durUnder15s => $composableBuilder(
    column: $table.durUnder15s,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dur15To30s => $composableBuilder(
    column: $table.dur15To30s,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dur30To60s => $composableBuilder(
    column: $table.dur30To60s,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dur1To3m => $composableBuilder(
    column: $table.dur1To3m,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durOver3m => $composableBuilder(
    column: $table.durOver3m,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyStatsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $DailyStatsTable> {
  $$DailyStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<bool> get isLocal =>
      $composableBuilder(column: $table.isLocal, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<double> get totalDurationSec => $composableBuilder(
    column: $table.totalDurationSec,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalProcessingSec => $composableBuilder(
    column: $table.totalProcessingSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalCostUsd => $composableBuilder(
    column: $table.totalCostUsd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durUnder15s => $composableBuilder(
    column: $table.durUnder15s,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dur15To30s => $composableBuilder(
    column: $table.dur15To30s,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dur30To60s => $composableBuilder(
    column: $table.dur30To60s,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dur1To3m =>
      $composableBuilder(column: $table.dur1To3m, builder: (column) => column);

  GeneratedColumn<int> get durOver3m =>
      $composableBuilder(column: $table.durOver3m, builder: (column) => column);
}

class $$DailyStatsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $DailyStatsTable,
          DailyStat,
          $$DailyStatsTableFilterComposer,
          $$DailyStatsTableOrderingComposer,
          $$DailyStatsTableAnnotationComposer,
          $$DailyStatsTableCreateCompanionBuilder,
          $$DailyStatsTableUpdateCompanionBuilder,
          (
            DailyStat,
            BaseReferences<_$HistoryDatabase, $DailyStatsTable, DailyStat>,
          ),
          DailyStat,
          PrefetchHooks Function()
        > {
  $$DailyStatsTableTableManager(_$HistoryDatabase db, $DailyStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<bool> isLocal = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<double> totalDurationSec = const Value.absent(),
                Value<double> totalProcessingSec = const Value.absent(),
                Value<int> totalWords = const Value.absent(),
                Value<double> totalCostUsd = const Value.absent(),
                Value<int> durUnder15s = const Value.absent(),
                Value<int> dur15To30s = const Value.absent(),
                Value<int> dur30To60s = const Value.absent(),
                Value<int> dur1To3m = const Value.absent(),
                Value<int> durOver3m = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCompanion(
                date: date,
                model: model,
                isLocal: isLocal,
                count: count,
                totalDurationSec: totalDurationSec,
                totalProcessingSec: totalProcessingSec,
                totalWords: totalWords,
                totalCostUsd: totalCostUsd,
                durUnder15s: durUnder15s,
                dur15To30s: dur15To30s,
                dur30To60s: dur30To60s,
                dur1To3m: dur1To3m,
                durOver3m: durOver3m,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required String model,
                required bool isLocal,
                Value<int> count = const Value.absent(),
                Value<double> totalDurationSec = const Value.absent(),
                Value<double> totalProcessingSec = const Value.absent(),
                Value<int> totalWords = const Value.absent(),
                Value<double> totalCostUsd = const Value.absent(),
                Value<int> durUnder15s = const Value.absent(),
                Value<int> dur15To30s = const Value.absent(),
                Value<int> dur30To60s = const Value.absent(),
                Value<int> dur1To3m = const Value.absent(),
                Value<int> durOver3m = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCompanion.insert(
                date: date,
                model: model,
                isLocal: isLocal,
                count: count,
                totalDurationSec: totalDurationSec,
                totalProcessingSec: totalProcessingSec,
                totalWords: totalWords,
                totalCostUsd: totalCostUsd,
                durUnder15s: durUnder15s,
                dur15To30s: dur15To30s,
                dur30To60s: dur30To60s,
                dur1To3m: dur1To3m,
                durOver3m: durOver3m,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $DailyStatsTable,
      DailyStat,
      $$DailyStatsTableFilterComposer,
      $$DailyStatsTableOrderingComposer,
      $$DailyStatsTableAnnotationComposer,
      $$DailyStatsTableCreateCompanionBuilder,
      $$DailyStatsTableUpdateCompanionBuilder,
      (
        DailyStat,
        BaseReferences<_$HistoryDatabase, $DailyStatsTable, DailyStat>,
      ),
      DailyStat,
      PrefetchHooks Function()
    >;
typedef $$EntryNotesTableCreateCompanionBuilder =
    EntryNotesCompanion Function({
      required String id,
      required String entryId,
      Value<String> content,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$EntryNotesTableUpdateCompanionBuilder =
    EntryNotesCompanion Function({
      Value<String> id,
      Value<String> entryId,
      Value<String> content,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$EntryNotesTableReferences
    extends BaseReferences<_$HistoryDatabase, $EntryNotesTable, EntryNote> {
  $$EntryNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) => db
      .historyEntries
      .createAlias('entry_notes__entry_id__history_entries__id');

  $$HistoryEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<String>('entry_id')!;

    final manager = $$HistoryEntriesTableTableManager(
      $_db,
      $_db.historyEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntryNotesTableFilterComposer
    extends Composer<_$HistoryDatabase, $EntryNotesTable> {
  $$EntryNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HistoryEntriesTableFilterComposer get entryId {
    final $$HistoryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryNotesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $EntryNotesTable> {
  $$EntryNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HistoryEntriesTableOrderingComposer get entryId {
    final $$HistoryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryNotesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $EntryNotesTable> {
  $$EntryNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$HistoryEntriesTableAnnotationComposer get entryId {
    final $$HistoryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryNotesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $EntryNotesTable,
          EntryNote,
          $$EntryNotesTableFilterComposer,
          $$EntryNotesTableOrderingComposer,
          $$EntryNotesTableAnnotationComposer,
          $$EntryNotesTableCreateCompanionBuilder,
          $$EntryNotesTableUpdateCompanionBuilder,
          (EntryNote, $$EntryNotesTableReferences),
          EntryNote,
          PrefetchHooks Function({bool entryId})
        > {
  $$EntryNotesTableTableManager(_$HistoryDatabase db, $EntryNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryNotesCompanion(
                id: id,
                entryId: entryId,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entryId,
                Value<String> content = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EntryNotesCompanion.insert(
                id: id,
                entryId: entryId,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntryNotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable: $$EntryNotesTableReferences
                                    ._entryIdTable(db),
                                referencedColumn: $$EntryNotesTableReferences
                                    ._entryIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntryNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $EntryNotesTable,
      EntryNote,
      $$EntryNotesTableFilterComposer,
      $$EntryNotesTableOrderingComposer,
      $$EntryNotesTableAnnotationComposer,
      $$EntryNotesTableCreateCompanionBuilder,
      $$EntryNotesTableUpdateCompanionBuilder,
      (EntryNote, $$EntryNotesTableReferences),
      EntryNote,
      PrefetchHooks Function({bool entryId})
    >;
typedef $$EntryAttachmentsTableCreateCompanionBuilder =
    EntryAttachmentsCompanion Function({
      required String id,
      required String entryId,
      required String filename,
      required String filepath,
      Value<String> mimeType,
      Value<int> sizeBytes,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$EntryAttachmentsTableUpdateCompanionBuilder =
    EntryAttachmentsCompanion Function({
      Value<String> id,
      Value<String> entryId,
      Value<String> filename,
      Value<String> filepath,
      Value<String> mimeType,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$EntryAttachmentsTableReferences
    extends
        BaseReferences<
          _$HistoryDatabase,
          $EntryAttachmentsTable,
          EntryAttachment
        > {
  $$EntryAttachmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) => db
      .historyEntries
      .createAlias('entry_attachments__entry_id__history_entries__id');

  $$HistoryEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<String>('entry_id')!;

    final manager = $$HistoryEntriesTableTableManager(
      $_db,
      $_db.historyEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntryAttachmentsTableFilterComposer
    extends Composer<_$HistoryDatabase, $EntryAttachmentsTable> {
  $$EntryAttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HistoryEntriesTableFilterComposer get entryId {
    final $$HistoryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryAttachmentsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $EntryAttachmentsTable> {
  $$EntryAttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HistoryEntriesTableOrderingComposer get entryId {
    final $$HistoryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryAttachmentsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $EntryAttachmentsTable> {
  $$EntryAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get filepath =>
      $composableBuilder(column: $table.filepath, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$HistoryEntriesTableAnnotationComposer get entryId {
    final $$HistoryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryAttachmentsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $EntryAttachmentsTable,
          EntryAttachment,
          $$EntryAttachmentsTableFilterComposer,
          $$EntryAttachmentsTableOrderingComposer,
          $$EntryAttachmentsTableAnnotationComposer,
          $$EntryAttachmentsTableCreateCompanionBuilder,
          $$EntryAttachmentsTableUpdateCompanionBuilder,
          (EntryAttachment, $$EntryAttachmentsTableReferences),
          EntryAttachment,
          PrefetchHooks Function({bool entryId})
        > {
  $$EntryAttachmentsTableTableManager(
    _$HistoryDatabase db,
    $EntryAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryAttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryAttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryAttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<String> filepath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryAttachmentsCompanion(
                id: id,
                entryId: entryId,
                filename: filename,
                filepath: filepath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entryId,
                required String filename,
                required String filepath,
                Value<String> mimeType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => EntryAttachmentsCompanion.insert(
                id: id,
                entryId: entryId,
                filename: filename,
                filepath: filepath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntryAttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable:
                                    $$EntryAttachmentsTableReferences
                                        ._entryIdTable(db),
                                referencedColumn:
                                    $$EntryAttachmentsTableReferences
                                        ._entryIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntryAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $EntryAttachmentsTable,
      EntryAttachment,
      $$EntryAttachmentsTableFilterComposer,
      $$EntryAttachmentsTableOrderingComposer,
      $$EntryAttachmentsTableAnnotationComposer,
      $$EntryAttachmentsTableCreateCompanionBuilder,
      $$EntryAttachmentsTableUpdateCompanionBuilder,
      (EntryAttachment, $$EntryAttachmentsTableReferences),
      EntryAttachment,
      PrefetchHooks Function({bool entryId})
    >;
typedef $$TextReplacementsTableCreateCompanionBuilder =
    TextReplacementsCompanion Function({
      required String id,
      required String trigger,
      required String replacement,
      required DateTime createdAt,
      Value<String> matchMode,
      Value<double?> fuzzyThreshold,
      Value<String> origin,
      Value<int> usageCount,
      Value<bool> isFavorite,
      Value<int> rowid,
    });
typedef $$TextReplacementsTableUpdateCompanionBuilder =
    TextReplacementsCompanion Function({
      Value<String> id,
      Value<String> trigger,
      Value<String> replacement,
      Value<DateTime> createdAt,
      Value<String> matchMode,
      Value<double?> fuzzyThreshold,
      Value<String> origin,
      Value<int> usageCount,
      Value<bool> isFavorite,
      Value<int> rowid,
    });

final class $$TextReplacementsTableReferences
    extends
        BaseReferences<
          _$HistoryDatabase,
          $TextReplacementsTable,
          TextReplacement
        > {
  $$TextReplacementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $TextReplacementTriggersTable,
    List<TextReplacementTrigger>
  >
  _textReplacementTriggersRefsTable(_$HistoryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.textReplacementTriggers,
        aliasName:
            'text_replacements__id__text_replacement_triggers__replacement_id',
      );

  $$TextReplacementTriggersTableProcessedTableManager
  get textReplacementTriggersRefs {
    final manager = $$TextReplacementTriggersTableTableManager(
      $_db,
      $_db.textReplacementTriggers,
    ).filter((f) => f.replacementId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _textReplacementTriggersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TextReplacementsTableFilterComposer
    extends Composer<_$HistoryDatabase, $TextReplacementsTable> {
  $$TextReplacementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchMode => $composableBuilder(
    column: $table.matchMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fuzzyThreshold => $composableBuilder(
    column: $table.fuzzyThreshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> textReplacementTriggersRefs(
    Expression<bool> Function($$TextReplacementTriggersTableFilterComposer f) f,
  ) {
    final $$TextReplacementTriggersTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.textReplacementTriggers,
          getReferencedColumn: (t) => t.replacementId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TextReplacementTriggersTableFilterComposer(
                $db: $db,
                $table: $db.textReplacementTriggers,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TextReplacementsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $TextReplacementsTable> {
  $$TextReplacementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchMode => $composableBuilder(
    column: $table.matchMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fuzzyThreshold => $composableBuilder(
    column: $table.fuzzyThreshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TextReplacementsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $TextReplacementsTable> {
  $$TextReplacementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trigger =>
      $composableBuilder(column: $table.trigger, builder: (column) => column);

  GeneratedColumn<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get matchMode =>
      $composableBuilder(column: $table.matchMode, builder: (column) => column);

  GeneratedColumn<double> get fuzzyThreshold => $composableBuilder(
    column: $table.fuzzyThreshold,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get usageCount => $composableBuilder(
    column: $table.usageCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  Expression<T> textReplacementTriggersRefs<T extends Object>(
    Expression<T> Function($$TextReplacementTriggersTableAnnotationComposer a)
    f,
  ) {
    final $$TextReplacementTriggersTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.textReplacementTriggers,
          getReferencedColumn: (t) => t.replacementId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TextReplacementTriggersTableAnnotationComposer(
                $db: $db,
                $table: $db.textReplacementTriggers,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TextReplacementsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $TextReplacementsTable,
          TextReplacement,
          $$TextReplacementsTableFilterComposer,
          $$TextReplacementsTableOrderingComposer,
          $$TextReplacementsTableAnnotationComposer,
          $$TextReplacementsTableCreateCompanionBuilder,
          $$TextReplacementsTableUpdateCompanionBuilder,
          (TextReplacement, $$TextReplacementsTableReferences),
          TextReplacement,
          PrefetchHooks Function({bool textReplacementTriggersRefs})
        > {
  $$TextReplacementsTableTableManager(
    _$HistoryDatabase db,
    $TextReplacementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TextReplacementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TextReplacementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TextReplacementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> trigger = const Value.absent(),
                Value<String> replacement = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> matchMode = const Value.absent(),
                Value<double?> fuzzyThreshold = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> usageCount = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementsCompanion(
                id: id,
                trigger: trigger,
                replacement: replacement,
                createdAt: createdAt,
                matchMode: matchMode,
                fuzzyThreshold: fuzzyThreshold,
                origin: origin,
                usageCount: usageCount,
                isFavorite: isFavorite,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String trigger,
                required String replacement,
                required DateTime createdAt,
                Value<String> matchMode = const Value.absent(),
                Value<double?> fuzzyThreshold = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> usageCount = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementsCompanion.insert(
                id: id,
                trigger: trigger,
                replacement: replacement,
                createdAt: createdAt,
                matchMode: matchMode,
                fuzzyThreshold: fuzzyThreshold,
                origin: origin,
                usageCount: usageCount,
                isFavorite: isFavorite,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TextReplacementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({textReplacementTriggersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (textReplacementTriggersRefs) db.textReplacementTriggers,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (textReplacementTriggersRefs)
                    await $_getPrefetchedData<
                      TextReplacement,
                      $TextReplacementsTable,
                      TextReplacementTrigger
                    >(
                      currentTable: table,
                      referencedTable: $$TextReplacementsTableReferences
                          ._textReplacementTriggersRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TextReplacementsTableReferences(
                            db,
                            table,
                            p0,
                          ).textReplacementTriggersRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.replacementId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TextReplacementsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $TextReplacementsTable,
      TextReplacement,
      $$TextReplacementsTableFilterComposer,
      $$TextReplacementsTableOrderingComposer,
      $$TextReplacementsTableAnnotationComposer,
      $$TextReplacementsTableCreateCompanionBuilder,
      $$TextReplacementsTableUpdateCompanionBuilder,
      (TextReplacement, $$TextReplacementsTableReferences),
      TextReplacement,
      PrefetchHooks Function({bool textReplacementTriggersRefs})
    >;
typedef $$TextReplacementTriggersTableCreateCompanionBuilder =
    TextReplacementTriggersCompanion Function({
      required String id,
      required String replacementId,
      required String trigger,
      Value<int> rowid,
    });
typedef $$TextReplacementTriggersTableUpdateCompanionBuilder =
    TextReplacementTriggersCompanion Function({
      Value<String> id,
      Value<String> replacementId,
      Value<String> trigger,
      Value<int> rowid,
    });

final class $$TextReplacementTriggersTableReferences
    extends
        BaseReferences<
          _$HistoryDatabase,
          $TextReplacementTriggersTable,
          TextReplacementTrigger
        > {
  $$TextReplacementTriggersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TextReplacementsTable _replacementIdTable(_$HistoryDatabase db) =>
      db.textReplacements.createAlias(
        'text_replacement_triggers__replacement_id__text_replacements__id',
      );

  $$TextReplacementsTableProcessedTableManager get replacementId {
    final $_column = $_itemColumn<String>('replacement_id')!;

    final manager = $$TextReplacementsTableTableManager(
      $_db,
      $_db.textReplacements,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_replacementIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TextReplacementTriggersTableFilterComposer
    extends Composer<_$HistoryDatabase, $TextReplacementTriggersTable> {
  $$TextReplacementTriggersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnFilters(column),
  );

  $$TextReplacementsTableFilterComposer get replacementId {
    final $$TextReplacementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementId,
      referencedTable: $db.textReplacements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TextReplacementsTableFilterComposer(
            $db: $db,
            $table: $db.textReplacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TextReplacementTriggersTableOrderingComposer
    extends Composer<_$HistoryDatabase, $TextReplacementTriggersTable> {
  $$TextReplacementTriggersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnOrderings(column),
  );

  $$TextReplacementsTableOrderingComposer get replacementId {
    final $$TextReplacementsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementId,
      referencedTable: $db.textReplacements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TextReplacementsTableOrderingComposer(
            $db: $db,
            $table: $db.textReplacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TextReplacementTriggersTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $TextReplacementTriggersTable> {
  $$TextReplacementTriggersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trigger =>
      $composableBuilder(column: $table.trigger, builder: (column) => column);

  $$TextReplacementsTableAnnotationComposer get replacementId {
    final $$TextReplacementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementId,
      referencedTable: $db.textReplacements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TextReplacementsTableAnnotationComposer(
            $db: $db,
            $table: $db.textReplacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TextReplacementTriggersTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $TextReplacementTriggersTable,
          TextReplacementTrigger,
          $$TextReplacementTriggersTableFilterComposer,
          $$TextReplacementTriggersTableOrderingComposer,
          $$TextReplacementTriggersTableAnnotationComposer,
          $$TextReplacementTriggersTableCreateCompanionBuilder,
          $$TextReplacementTriggersTableUpdateCompanionBuilder,
          (TextReplacementTrigger, $$TextReplacementTriggersTableReferences),
          TextReplacementTrigger,
          PrefetchHooks Function({bool replacementId})
        > {
  $$TextReplacementTriggersTableTableManager(
    _$HistoryDatabase db,
    $TextReplacementTriggersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TextReplacementTriggersTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TextReplacementTriggersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TextReplacementTriggersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> replacementId = const Value.absent(),
                Value<String> trigger = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementTriggersCompanion(
                id: id,
                replacementId: replacementId,
                trigger: trigger,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String replacementId,
                required String trigger,
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementTriggersCompanion.insert(
                id: id,
                replacementId: replacementId,
                trigger: trigger,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TextReplacementTriggersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({replacementId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (replacementId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.replacementId,
                                referencedTable:
                                    $$TextReplacementTriggersTableReferences
                                        ._replacementIdTable(db),
                                referencedColumn:
                                    $$TextReplacementTriggersTableReferences
                                        ._replacementIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TextReplacementTriggersTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $TextReplacementTriggersTable,
      TextReplacementTrigger,
      $$TextReplacementTriggersTableFilterComposer,
      $$TextReplacementTriggersTableOrderingComposer,
      $$TextReplacementTriggersTableAnnotationComposer,
      $$TextReplacementTriggersTableCreateCompanionBuilder,
      $$TextReplacementTriggersTableUpdateCompanionBuilder,
      (TextReplacementTrigger, $$TextReplacementTriggersTableReferences),
      TextReplacementTrigger,
      PrefetchHooks Function({bool replacementId})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$HistoryDatabase, $TagsTable, Tag> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EntryTagsTable, List<EntryTag>>
  _entryTagsRefsTable(_$HistoryDatabase db) => MultiTypedResultKey.fromTable(
    db.entryTags,
    aliasName: 'tags__id__entry_tags__tag_id',
  );

  $$EntryTagsTableProcessedTableManager get entryTagsRefs {
    final manager = $$EntryTagsTableTableManager(
      $_db,
      $_db.entryTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NoteTagsTable, List<NoteTag>> _noteTagsRefsTable(
    _$HistoryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.noteTags,
    aliasName: 'tags__id__note_tags__tag_id',
  );

  $$NoteTagsTableProcessedTableManager get noteTagsRefs {
    final manager = $$NoteTagsTableTableManager(
      $_db,
      $_db.noteTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer
    extends Composer<_$HistoryDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> entryTagsRefs(
    Expression<bool> Function($$EntryTagsTableFilterComposer f) f,
  ) {
    final $$EntryTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryTagsTableFilterComposer(
            $db: $db,
            $table: $db.entryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> noteTagsRefs(
    Expression<bool> Function($$NoteTagsTableFilterComposer f) f,
  ) {
    final $$NoteTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableFilterComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> entryTagsRefs<T extends Object>(
    Expression<T> Function($$EntryTagsTableAnnotationComposer a) f,
  ) {
    final $$EntryTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.entryTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> noteTagsRefs<T extends Object>(
    Expression<T> Function($$NoteTagsTableAnnotationComposer a) f,
  ) {
    final $$NoteTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, $$TagsTableReferences),
          Tag,
          PrefetchHooks Function({bool entryTagsRefs, bool noteTagsRefs})
        > {
  $$TagsTableTableManager(_$HistoryDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({entryTagsRefs = false, noteTagsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (entryTagsRefs) db.entryTags,
                    if (noteTagsRefs) db.noteTags,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (entryTagsRefs)
                        await $_getPrefetchedData<Tag, $TagsTable, EntryTag>(
                          currentTable: table,
                          referencedTable: $$TagsTableReferences
                              ._entryTagsRefsTable(db),
                          managerFromTypedResult: (p0) => $$TagsTableReferences(
                            db,
                            table,
                            p0,
                          ).entryTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tagId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (noteTagsRefs)
                        await $_getPrefetchedData<Tag, $TagsTable, NoteTag>(
                          currentTable: table,
                          referencedTable: $$TagsTableReferences
                              ._noteTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TagsTableReferences(db, table, p0).noteTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tagId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, $$TagsTableReferences),
      Tag,
      PrefetchHooks Function({bool entryTagsRefs, bool noteTagsRefs})
    >;
typedef $$EntryTagsTableCreateCompanionBuilder =
    EntryTagsCompanion Function({
      required String entryId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$EntryTagsTableUpdateCompanionBuilder =
    EntryTagsCompanion Function({
      Value<String> entryId,
      Value<String> tagId,
      Value<int> rowid,
    });

final class $$EntryTagsTableReferences
    extends BaseReferences<_$HistoryDatabase, $EntryTagsTable, EntryTag> {
  $$EntryTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) => db
      .historyEntries
      .createAlias('entry_tags__entry_id__history_entries__id');

  $$HistoryEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<String>('entry_id')!;

    final manager = $$HistoryEntriesTableTableManager(
      $_db,
      $_db.historyEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$HistoryDatabase db) =>
      db.tags.createAlias('entry_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntryTagsTableFilterComposer
    extends Composer<_$HistoryDatabase, $EntryTagsTable> {
  $$EntryTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$HistoryEntriesTableFilterComposer get entryId {
    final $$HistoryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryTagsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $EntryTagsTable> {
  $$EntryTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$HistoryEntriesTableOrderingComposer get entryId {
    final $$HistoryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryTagsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $EntryTagsTable> {
  $$EntryTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$HistoryEntriesTableAnnotationComposer get entryId {
    final $$HistoryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryTagsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $EntryTagsTable,
          EntryTag,
          $$EntryTagsTableFilterComposer,
          $$EntryTagsTableOrderingComposer,
          $$EntryTagsTableAnnotationComposer,
          $$EntryTagsTableCreateCompanionBuilder,
          $$EntryTagsTableUpdateCompanionBuilder,
          (EntryTag, $$EntryTagsTableReferences),
          EntryTag,
          PrefetchHooks Function({bool entryId, bool tagId})
        > {
  $$EntryTagsTableTableManager(_$HistoryDatabase db, $EntryTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entryId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryTagsCompanion(
                entryId: entryId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entryId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => EntryTagsCompanion.insert(
                entryId: entryId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntryTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable: $$EntryTagsTableReferences
                                    ._entryIdTable(db),
                                referencedColumn: $$EntryTagsTableReferences
                                    ._entryIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$EntryTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$EntryTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntryTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $EntryTagsTable,
      EntryTag,
      $$EntryTagsTableFilterComposer,
      $$EntryTagsTableOrderingComposer,
      $$EntryTagsTableAnnotationComposer,
      $$EntryTagsTableCreateCompanionBuilder,
      $$EntryTagsTableUpdateCompanionBuilder,
      (EntryTag, $$EntryTagsTableReferences),
      EntryTag,
      PrefetchHooks Function({bool entryId, bool tagId})
    >;
typedef $$HotkeyLatencyEntriesTableCreateCompanionBuilder =
    HotkeyLatencyEntriesCompanion Function({
      required String id,
      required DateTime recordedAt,
      required int latencyMs,
      Value<int?> stopToTextMs,
      Value<int> rowid,
    });
typedef $$HotkeyLatencyEntriesTableUpdateCompanionBuilder =
    HotkeyLatencyEntriesCompanion Function({
      Value<String> id,
      Value<DateTime> recordedAt,
      Value<int> latencyMs,
      Value<int?> stopToTextMs,
      Value<int> rowid,
    });

class $$HotkeyLatencyEntriesTableFilterComposer
    extends Composer<_$HistoryDatabase, $HotkeyLatencyEntriesTable> {
  $$HotkeyLatencyEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stopToTextMs => $composableBuilder(
    column: $table.stopToTextMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HotkeyLatencyEntriesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $HotkeyLatencyEntriesTable> {
  $$HotkeyLatencyEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stopToTextMs => $composableBuilder(
    column: $table.stopToTextMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HotkeyLatencyEntriesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $HotkeyLatencyEntriesTable> {
  $$HotkeyLatencyEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<int> get stopToTextMs => $composableBuilder(
    column: $table.stopToTextMs,
    builder: (column) => column,
  );
}

class $$HotkeyLatencyEntriesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $HotkeyLatencyEntriesTable,
          HotkeyLatencyEntry,
          $$HotkeyLatencyEntriesTableFilterComposer,
          $$HotkeyLatencyEntriesTableOrderingComposer,
          $$HotkeyLatencyEntriesTableAnnotationComposer,
          $$HotkeyLatencyEntriesTableCreateCompanionBuilder,
          $$HotkeyLatencyEntriesTableUpdateCompanionBuilder,
          (
            HotkeyLatencyEntry,
            BaseReferences<
              _$HistoryDatabase,
              $HotkeyLatencyEntriesTable,
              HotkeyLatencyEntry
            >,
          ),
          HotkeyLatencyEntry,
          PrefetchHooks Function()
        > {
  $$HotkeyLatencyEntriesTableTableManager(
    _$HistoryDatabase db,
    $HotkeyLatencyEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HotkeyLatencyEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HotkeyLatencyEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$HotkeyLatencyEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
                Value<int> latencyMs = const Value.absent(),
                Value<int?> stopToTextMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HotkeyLatencyEntriesCompanion(
                id: id,
                recordedAt: recordedAt,
                latencyMs: latencyMs,
                stopToTextMs: stopToTextMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime recordedAt,
                required int latencyMs,
                Value<int?> stopToTextMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HotkeyLatencyEntriesCompanion.insert(
                id: id,
                recordedAt: recordedAt,
                latencyMs: latencyMs,
                stopToTextMs: stopToTextMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HotkeyLatencyEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $HotkeyLatencyEntriesTable,
      HotkeyLatencyEntry,
      $$HotkeyLatencyEntriesTableFilterComposer,
      $$HotkeyLatencyEntriesTableOrderingComposer,
      $$HotkeyLatencyEntriesTableAnnotationComposer,
      $$HotkeyLatencyEntriesTableCreateCompanionBuilder,
      $$HotkeyLatencyEntriesTableUpdateCompanionBuilder,
      (
        HotkeyLatencyEntry,
        BaseReferences<
          _$HistoryDatabase,
          $HotkeyLatencyEntriesTable,
          HotkeyLatencyEntry
        >,
      ),
      HotkeyLatencyEntry,
      PrefetchHooks Function()
    >;
typedef $$SnippetsTableCreateCompanionBuilder =
    SnippetsCompanion Function({
      required String id,
      required String title,
      required String body,
      required DateTime createdAt,
      Value<String> kind,
      Value<String?> sourceNoteId,
      Value<int> rowid,
    });
typedef $$SnippetsTableUpdateCompanionBuilder =
    SnippetsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> body,
      Value<DateTime> createdAt,
      Value<String> kind,
      Value<String?> sourceNoteId,
      Value<int> rowid,
    });

final class $$SnippetsTableReferences
    extends BaseReferences<_$HistoryDatabase, $SnippetsTable, Snippet> {
  $$SnippetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SnippetFieldsTable, List<SnippetField>>
  _snippetFieldsRefsTable(_$HistoryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.snippetFields,
        aliasName: 'snippets__id__snippet_fields__snippet_id',
      );

  $$SnippetFieldsTableProcessedTableManager get snippetFieldsRefs {
    final manager = $$SnippetFieldsTableTableManager(
      $_db,
      $_db.snippetFields,
    ).filter((f) => f.snippetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_snippetFieldsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SnippetsTableFilterComposer
    extends Composer<_$HistoryDatabase, $SnippetsTable> {
  $$SnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> snippetFieldsRefs(
    Expression<bool> Function($$SnippetFieldsTableFilterComposer f) f,
  ) {
    final $$SnippetFieldsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.snippetFields,
      getReferencedColumn: (t) => t.snippetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetFieldsTableFilterComposer(
            $db: $db,
            $table: $db.snippetFields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SnippetsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $SnippetsTable> {
  $$SnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnippetsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $SnippetsTable> {
  $$SnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => column,
  );

  Expression<T> snippetFieldsRefs<T extends Object>(
    Expression<T> Function($$SnippetFieldsTableAnnotationComposer a) f,
  ) {
    final $$SnippetFieldsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.snippetFields,
      getReferencedColumn: (t) => t.snippetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetFieldsTableAnnotationComposer(
            $db: $db,
            $table: $db.snippetFields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SnippetsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $SnippetsTable,
          Snippet,
          $$SnippetsTableFilterComposer,
          $$SnippetsTableOrderingComposer,
          $$SnippetsTableAnnotationComposer,
          $$SnippetsTableCreateCompanionBuilder,
          $$SnippetsTableUpdateCompanionBuilder,
          (Snippet, $$SnippetsTableReferences),
          Snippet,
          PrefetchHooks Function({bool snippetFieldsRefs})
        > {
  $$SnippetsTableTableManager(_$HistoryDatabase db, $SnippetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> sourceNoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion(
                id: id,
                title: title,
                body: body,
                createdAt: createdAt,
                kind: kind,
                sourceNoteId: sourceNoteId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String body,
                required DateTime createdAt,
                Value<String> kind = const Value.absent(),
                Value<String?> sourceNoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion.insert(
                id: id,
                title: title,
                body: body,
                createdAt: createdAt,
                kind: kind,
                sourceNoteId: sourceNoteId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SnippetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snippetFieldsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (snippetFieldsRefs) db.snippetFields,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (snippetFieldsRefs)
                    await $_getPrefetchedData<
                      Snippet,
                      $SnippetsTable,
                      SnippetField
                    >(
                      currentTable: table,
                      referencedTable: $$SnippetsTableReferences
                          ._snippetFieldsRefsTable(db),
                      managerFromTypedResult: (p0) => $$SnippetsTableReferences(
                        db,
                        table,
                        p0,
                      ).snippetFieldsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.snippetId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $SnippetsTable,
      Snippet,
      $$SnippetsTableFilterComposer,
      $$SnippetsTableOrderingComposer,
      $$SnippetsTableAnnotationComposer,
      $$SnippetsTableCreateCompanionBuilder,
      $$SnippetsTableUpdateCompanionBuilder,
      (Snippet, $$SnippetsTableReferences),
      Snippet,
      PrefetchHooks Function({bool snippetFieldsRefs})
    >;
typedef $$SnippetFieldsTableCreateCompanionBuilder =
    SnippetFieldsCompanion Function({
      required String id,
      required String snippetId,
      required String name,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$SnippetFieldsTableUpdateCompanionBuilder =
    SnippetFieldsCompanion Function({
      Value<String> id,
      Value<String> snippetId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$SnippetFieldsTableReferences
    extends
        BaseReferences<_$HistoryDatabase, $SnippetFieldsTable, SnippetField> {
  $$SnippetFieldsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SnippetsTable _snippetIdTable(_$HistoryDatabase db) =>
      db.snippets.createAlias('snippet_fields__snippet_id__snippets__id');

  $$SnippetsTableProcessedTableManager get snippetId {
    final $_column = $_itemColumn<String>('snippet_id')!;

    final manager = $$SnippetsTableTableManager(
      $_db,
      $_db.snippets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snippetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SnippetFieldsTableFilterComposer
    extends Composer<_$HistoryDatabase, $SnippetFieldsTable> {
  $$SnippetFieldsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$SnippetsTableFilterComposer get snippetId {
    final $$SnippetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snippetId,
      referencedTable: $db.snippets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetsTableFilterComposer(
            $db: $db,
            $table: $db.snippets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetFieldsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $SnippetFieldsTable> {
  $$SnippetFieldsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$SnippetsTableOrderingComposer get snippetId {
    final $$SnippetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snippetId,
      referencedTable: $db.snippets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetsTableOrderingComposer(
            $db: $db,
            $table: $db.snippets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetFieldsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $SnippetFieldsTable> {
  $$SnippetFieldsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$SnippetsTableAnnotationComposer get snippetId {
    final $$SnippetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snippetId,
      referencedTable: $db.snippets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetsTableAnnotationComposer(
            $db: $db,
            $table: $db.snippets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetFieldsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $SnippetFieldsTable,
          SnippetField,
          $$SnippetFieldsTableFilterComposer,
          $$SnippetFieldsTableOrderingComposer,
          $$SnippetFieldsTableAnnotationComposer,
          $$SnippetFieldsTableCreateCompanionBuilder,
          $$SnippetFieldsTableUpdateCompanionBuilder,
          (SnippetField, $$SnippetFieldsTableReferences),
          SnippetField,
          PrefetchHooks Function({bool snippetId})
        > {
  $$SnippetFieldsTableTableManager(
    _$HistoryDatabase db,
    $SnippetFieldsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetFieldsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetFieldsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetFieldsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snippetId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetFieldsCompanion(
                id: id,
                snippetId: snippetId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snippetId,
                required String name,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => SnippetFieldsCompanion.insert(
                id: id,
                snippetId: snippetId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SnippetFieldsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snippetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (snippetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.snippetId,
                                referencedTable: $$SnippetFieldsTableReferences
                                    ._snippetIdTable(db),
                                referencedColumn: $$SnippetFieldsTableReferences
                                    ._snippetIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SnippetFieldsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $SnippetFieldsTable,
      SnippetField,
      $$SnippetFieldsTableFilterComposer,
      $$SnippetFieldsTableOrderingComposer,
      $$SnippetFieldsTableAnnotationComposer,
      $$SnippetFieldsTableCreateCompanionBuilder,
      $$SnippetFieldsTableUpdateCompanionBuilder,
      (SnippetField, $$SnippetFieldsTableReferences),
      SnippetField,
      PrefetchHooks Function({bool snippetId})
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      Value<String> content,
      Value<String?> title,
      Value<bool> pinned,
      Value<bool> isQuickNote,
      Value<DateTime?> deletedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String> content,
      Value<String?> title,
      Value<bool> pinned,
      Value<bool> isQuickNote,
      Value<DateTime?> deletedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$NotesTableReferences
    extends BaseReferences<_$HistoryDatabase, $NotesTable, Note> {
  $$NotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$NoteTagsTable, List<NoteTag>> _noteTagsRefsTable(
    _$HistoryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.noteTags,
    aliasName: 'notes__id__note_tags__note_id',
  );

  $$NoteTagsTableProcessedTableManager get noteTagsRefs {
    final manager = $$NoteTagsTableTableManager(
      $_db,
      $_db.noteTags,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NotesTableFilterComposer
    extends Composer<_$HistoryDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isQuickNote => $composableBuilder(
    column: $table.isQuickNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> noteTagsRefs(
    Expression<bool> Function($$NoteTagsTableFilterComposer f) f,
  ) {
    final $$NoteTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableFilterComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isQuickNote => $composableBuilder(
    column: $table.isQuickNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get isQuickNote => $composableBuilder(
    column: $table.isQuickNote,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> noteTagsRefs<T extends Object>(
    Expression<T> Function($$NoteTagsTableAnnotationComposer a) f,
  ) {
    final $$NoteTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTags,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, $$NotesTableReferences),
          Note,
          PrefetchHooks Function({bool noteTagsRefs})
        > {
  $$NotesTableTableManager(_$HistoryDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> isQuickNote = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                content: content,
                title: title,
                pinned: pinned,
                isQuickNote: isQuickNote,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> content = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> isQuickNote = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                content: content,
                title: title,
                pinned: pinned,
                isQuickNote: isQuickNote,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NotesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({noteTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (noteTagsRefs) db.noteTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (noteTagsRefs)
                    await $_getPrefetchedData<Note, $NotesTable, NoteTag>(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._noteTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$NotesTableReferences(db, table, p0).noteTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, $$NotesTableReferences),
      Note,
      PrefetchHooks Function({bool noteTagsRefs})
    >;
typedef $$NoteTagsTableCreateCompanionBuilder =
    NoteTagsCompanion Function({
      required String noteId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$NoteTagsTableUpdateCompanionBuilder =
    NoteTagsCompanion Function({
      Value<String> noteId,
      Value<String> tagId,
      Value<int> rowid,
    });

final class $$NoteTagsTableReferences
    extends BaseReferences<_$HistoryDatabase, $NoteTagsTable, NoteTag> {
  $$NoteTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _noteIdTable(_$HistoryDatabase db) =>
      db.notes.createAlias('note_tags__note_id__notes__id');

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<String>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$HistoryDatabase db) =>
      db.tags.createAlias('note_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteTagsTableFilterComposer
    extends Composer<_$HistoryDatabase, $NoteTagsTable> {
  $$NoteTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTagsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $NoteTagsTable> {
  $$NoteTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTagsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $NoteTagsTable> {
  $$NoteTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTagsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $NoteTagsTable,
          NoteTag,
          $$NoteTagsTableFilterComposer,
          $$NoteTagsTableOrderingComposer,
          $$NoteTagsTableAnnotationComposer,
          $$NoteTagsTableCreateCompanionBuilder,
          $$NoteTagsTableUpdateCompanionBuilder,
          (NoteTag, $$NoteTagsTableReferences),
          NoteTag,
          PrefetchHooks Function({bool noteId, bool tagId})
        > {
  $$NoteTagsTableTableManager(_$HistoryDatabase db, $NoteTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  NoteTagsCompanion(noteId: noteId, tagId: tagId, rowid: rowid),
          createCompanionCallback:
              ({
                required String noteId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => NoteTagsCompanion.insert(
                noteId: noteId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$NoteTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({noteId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (noteId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.noteId,
                                referencedTable: $$NoteTagsTableReferences
                                    ._noteIdTable(db),
                                referencedColumn: $$NoteTagsTableReferences
                                    ._noteIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$NoteTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$NoteTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$NoteTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $NoteTagsTable,
      NoteTag,
      $$NoteTagsTableFilterComposer,
      $$NoteTagsTableOrderingComposer,
      $$NoteTagsTableAnnotationComposer,
      $$NoteTagsTableCreateCompanionBuilder,
      $$NoteTagsTableUpdateCompanionBuilder,
      (NoteTag, $$NoteTagsTableReferences),
      NoteTag,
      PrefetchHooks Function({bool noteId, bool tagId})
    >;
typedef $$NoteVersionsTableCreateCompanionBuilder =
    NoteVersionsCompanion Function({
      required String id,
      required String noteId,
      Value<String?> title,
      required String content,
      required int sizeBytes,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$NoteVersionsTableUpdateCompanionBuilder =
    NoteVersionsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String?> title,
      Value<String> content,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$NoteVersionsTableFilterComposer
    extends Composer<_$HistoryDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteVersionsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteVersionsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NoteVersionsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $NoteVersionsTable,
          NoteVersion,
          $$NoteVersionsTableFilterComposer,
          $$NoteVersionsTableOrderingComposer,
          $$NoteVersionsTableAnnotationComposer,
          $$NoteVersionsTableCreateCompanionBuilder,
          $$NoteVersionsTableUpdateCompanionBuilder,
          (
            NoteVersion,
            BaseReferences<_$HistoryDatabase, $NoteVersionsTable, NoteVersion>,
          ),
          NoteVersion,
          PrefetchHooks Function()
        > {
  $$NoteVersionsTableTableManager(
    _$HistoryDatabase db,
    $NoteVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteVersionsCompanion(
                id: id,
                noteId: noteId,
                title: title,
                content: content,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String?> title = const Value.absent(),
                required String content,
                required int sizeBytes,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteVersionsCompanion.insert(
                id: id,
                noteId: noteId,
                title: title,
                content: content,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $NoteVersionsTable,
      NoteVersion,
      $$NoteVersionsTableFilterComposer,
      $$NoteVersionsTableOrderingComposer,
      $$NoteVersionsTableAnnotationComposer,
      $$NoteVersionsTableCreateCompanionBuilder,
      $$NoteVersionsTableUpdateCompanionBuilder,
      (
        NoteVersion,
        BaseReferences<_$HistoryDatabase, $NoteVersionsTable, NoteVersion>,
      ),
      NoteVersion,
      PrefetchHooks Function()
    >;
typedef $$NoteAssetsTableCreateCompanionBuilder =
    NoteAssetsCompanion Function({
      required String id,
      required String noteId,
      required String relativePath,
      required String mimeType,
      required int sizeBytes,
      required int width,
      required int height,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$NoteAssetsTableUpdateCompanionBuilder =
    NoteAssetsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String> relativePath,
      Value<String> mimeType,
      Value<int> sizeBytes,
      Value<int> width,
      Value<int> height,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$NoteAssetsTableFilterComposer
    extends Composer<_$HistoryDatabase, $NoteAssetsTable> {
  $$NoteAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteAssetsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $NoteAssetsTable> {
  $$NoteAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteAssetsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $NoteAssetsTable> {
  $$NoteAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NoteAssetsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $NoteAssetsTable,
          NoteAsset,
          $$NoteAssetsTableFilterComposer,
          $$NoteAssetsTableOrderingComposer,
          $$NoteAssetsTableAnnotationComposer,
          $$NoteAssetsTableCreateCompanionBuilder,
          $$NoteAssetsTableUpdateCompanionBuilder,
          (
            NoteAsset,
            BaseReferences<_$HistoryDatabase, $NoteAssetsTable, NoteAsset>,
          ),
          NoteAsset,
          PrefetchHooks Function()
        > {
  $$NoteAssetsTableTableManager(_$HistoryDatabase db, $NoteAssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteAssetsCompanion(
                id: id,
                noteId: noteId,
                relativePath: relativePath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String relativePath,
                required String mimeType,
                required int sizeBytes,
                required int width,
                required int height,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteAssetsCompanion.insert(
                id: id,
                noteId: noteId,
                relativePath: relativePath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $NoteAssetsTable,
      NoteAsset,
      $$NoteAssetsTableFilterComposer,
      $$NoteAssetsTableOrderingComposer,
      $$NoteAssetsTableAnnotationComposer,
      $$NoteAssetsTableCreateCompanionBuilder,
      $$NoteAssetsTableUpdateCompanionBuilder,
      (
        NoteAsset,
        BaseReferences<_$HistoryDatabase, $NoteAssetsTable, NoteAsset>,
      ),
      NoteAsset,
      PrefetchHooks Function()
    >;
typedef $$CorrectionObservationsTableCreateCompanionBuilder =
    CorrectionObservationsCompanion Function({
      required String id,
      required String normalizedKey,
      required String sourceText,
      required String targetText,
      Value<int> occurrenceCount,
      Value<String> status,
      required String source,
      required DateTime firstSeenAt,
      required DateTime lastSeenAt,
      Value<int> rowid,
    });
typedef $$CorrectionObservationsTableUpdateCompanionBuilder =
    CorrectionObservationsCompanion Function({
      Value<String> id,
      Value<String> normalizedKey,
      Value<String> sourceText,
      Value<String> targetText,
      Value<int> occurrenceCount,
      Value<String> status,
      Value<String> source,
      Value<DateTime> firstSeenAt,
      Value<DateTime> lastSeenAt,
      Value<int> rowid,
    });

class $$CorrectionObservationsTableFilterComposer
    extends Composer<_$HistoryDatabase, $CorrectionObservationsTable> {
  $$CorrectionObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetText => $composableBuilder(
    column: $table.targetText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CorrectionObservationsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $CorrectionObservationsTable> {
  $$CorrectionObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetText => $composableBuilder(
    column: $table.targetText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CorrectionObservationsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $CorrectionObservationsTable> {
  $$CorrectionObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetText => $composableBuilder(
    column: $table.targetText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurrenceCount => $composableBuilder(
    column: $table.occurrenceCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$CorrectionObservationsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $CorrectionObservationsTable,
          CorrectionObservationRow,
          $$CorrectionObservationsTableFilterComposer,
          $$CorrectionObservationsTableOrderingComposer,
          $$CorrectionObservationsTableAnnotationComposer,
          $$CorrectionObservationsTableCreateCompanionBuilder,
          $$CorrectionObservationsTableUpdateCompanionBuilder,
          (
            CorrectionObservationRow,
            BaseReferences<
              _$HistoryDatabase,
              $CorrectionObservationsTable,
              CorrectionObservationRow
            >,
          ),
          CorrectionObservationRow,
          PrefetchHooks Function()
        > {
  $$CorrectionObservationsTableTableManager(
    _$HistoryDatabase db,
    $CorrectionObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CorrectionObservationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CorrectionObservationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CorrectionObservationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> normalizedKey = const Value.absent(),
                Value<String> sourceText = const Value.absent(),
                Value<String> targetText = const Value.absent(),
                Value<int> occurrenceCount = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> firstSeenAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CorrectionObservationsCompanion(
                id: id,
                normalizedKey: normalizedKey,
                sourceText: sourceText,
                targetText: targetText,
                occurrenceCount: occurrenceCount,
                status: status,
                source: source,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String normalizedKey,
                required String sourceText,
                required String targetText,
                Value<int> occurrenceCount = const Value.absent(),
                Value<String> status = const Value.absent(),
                required String source,
                required DateTime firstSeenAt,
                required DateTime lastSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => CorrectionObservationsCompanion.insert(
                id: id,
                normalizedKey: normalizedKey,
                sourceText: sourceText,
                targetText: targetText,
                occurrenceCount: occurrenceCount,
                status: status,
                source: source,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CorrectionObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $CorrectionObservationsTable,
      CorrectionObservationRow,
      $$CorrectionObservationsTableFilterComposer,
      $$CorrectionObservationsTableOrderingComposer,
      $$CorrectionObservationsTableAnnotationComposer,
      $$CorrectionObservationsTableCreateCompanionBuilder,
      $$CorrectionObservationsTableUpdateCompanionBuilder,
      (
        CorrectionObservationRow,
        BaseReferences<
          _$HistoryDatabase,
          $CorrectionObservationsTable,
          CorrectionObservationRow
        >,
      ),
      CorrectionObservationRow,
      PrefetchHooks Function()
    >;
typedef $$AppProfilesTableCreateCompanionBuilder =
    AppProfilesCompanion Function({
      required String id,
      required String name,
      Value<int> position,
      Value<String> smartMode,
      Value<String?> asrLanguage,
      Value<String?> modelId,
      Value<String> contextSource,
      Value<String?> hotkeyKey,
      Value<String?> hotkeyModifiers,
      Value<String?> afterTranscription,
      Value<String?> microphone,
      Value<String?> consentProvider,
      Value<bool> consentSelection,
      Value<bool> consentClipboard,
      Value<String?> consentTextVersion,
      Value<DateTime?> consentGivenAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppProfilesTableUpdateCompanionBuilder =
    AppProfilesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> position,
      Value<String> smartMode,
      Value<String?> asrLanguage,
      Value<String?> modelId,
      Value<String> contextSource,
      Value<String?> hotkeyKey,
      Value<String?> hotkeyModifiers,
      Value<String?> afterTranscription,
      Value<String?> microphone,
      Value<String?> consentProvider,
      Value<bool> consentSelection,
      Value<bool> consentClipboard,
      Value<String?> consentTextVersion,
      Value<DateTime?> consentGivenAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppProfilesTableFilterComposer
    extends Composer<_$HistoryDatabase, $AppProfilesTable> {
  $$AppProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smartMode => $composableBuilder(
    column: $table.smartMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get asrLanguage => $composableBuilder(
    column: $table.asrLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextSource => $composableBuilder(
    column: $table.contextSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hotkeyKey => $composableBuilder(
    column: $table.hotkeyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hotkeyModifiers => $composableBuilder(
    column: $table.hotkeyModifiers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterTranscription => $composableBuilder(
    column: $table.afterTranscription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get microphone => $composableBuilder(
    column: $table.microphone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consentProvider => $composableBuilder(
    column: $table.consentProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get consentSelection => $composableBuilder(
    column: $table.consentSelection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get consentClipboard => $composableBuilder(
    column: $table.consentClipboard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consentTextVersion => $composableBuilder(
    column: $table.consentTextVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get consentGivenAt => $composableBuilder(
    column: $table.consentGivenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppProfilesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $AppProfilesTable> {
  $$AppProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smartMode => $composableBuilder(
    column: $table.smartMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get asrLanguage => $composableBuilder(
    column: $table.asrLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextSource => $composableBuilder(
    column: $table.contextSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hotkeyKey => $composableBuilder(
    column: $table.hotkeyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hotkeyModifiers => $composableBuilder(
    column: $table.hotkeyModifiers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterTranscription => $composableBuilder(
    column: $table.afterTranscription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get microphone => $composableBuilder(
    column: $table.microphone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consentProvider => $composableBuilder(
    column: $table.consentProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get consentSelection => $composableBuilder(
    column: $table.consentSelection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get consentClipboard => $composableBuilder(
    column: $table.consentClipboard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consentTextVersion => $composableBuilder(
    column: $table.consentTextVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get consentGivenAt => $composableBuilder(
    column: $table.consentGivenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppProfilesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $AppProfilesTable> {
  $$AppProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get smartMode =>
      $composableBuilder(column: $table.smartMode, builder: (column) => column);

  GeneratedColumn<String> get asrLanguage => $composableBuilder(
    column: $table.asrLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get contextSource => $composableBuilder(
    column: $table.contextSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hotkeyKey =>
      $composableBuilder(column: $table.hotkeyKey, builder: (column) => column);

  GeneratedColumn<String> get hotkeyModifiers => $composableBuilder(
    column: $table.hotkeyModifiers,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterTranscription => $composableBuilder(
    column: $table.afterTranscription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get microphone => $composableBuilder(
    column: $table.microphone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get consentProvider => $composableBuilder(
    column: $table.consentProvider,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get consentSelection => $composableBuilder(
    column: $table.consentSelection,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get consentClipboard => $composableBuilder(
    column: $table.consentClipboard,
    builder: (column) => column,
  );

  GeneratedColumn<String> get consentTextVersion => $composableBuilder(
    column: $table.consentTextVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get consentGivenAt => $composableBuilder(
    column: $table.consentGivenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppProfilesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $AppProfilesTable,
          AppProfileRow,
          $$AppProfilesTableFilterComposer,
          $$AppProfilesTableOrderingComposer,
          $$AppProfilesTableAnnotationComposer,
          $$AppProfilesTableCreateCompanionBuilder,
          $$AppProfilesTableUpdateCompanionBuilder,
          (
            AppProfileRow,
            BaseReferences<_$HistoryDatabase, $AppProfilesTable, AppProfileRow>,
          ),
          AppProfileRow,
          PrefetchHooks Function()
        > {
  $$AppProfilesTableTableManager(_$HistoryDatabase db, $AppProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> smartMode = const Value.absent(),
                Value<String?> asrLanguage = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String> contextSource = const Value.absent(),
                Value<String?> hotkeyKey = const Value.absent(),
                Value<String?> hotkeyModifiers = const Value.absent(),
                Value<String?> afterTranscription = const Value.absent(),
                Value<String?> microphone = const Value.absent(),
                Value<String?> consentProvider = const Value.absent(),
                Value<bool> consentSelection = const Value.absent(),
                Value<bool> consentClipboard = const Value.absent(),
                Value<String?> consentTextVersion = const Value.absent(),
                Value<DateTime?> consentGivenAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppProfilesCompanion(
                id: id,
                name: name,
                position: position,
                smartMode: smartMode,
                asrLanguage: asrLanguage,
                modelId: modelId,
                contextSource: contextSource,
                hotkeyKey: hotkeyKey,
                hotkeyModifiers: hotkeyModifiers,
                afterTranscription: afterTranscription,
                microphone: microphone,
                consentProvider: consentProvider,
                consentSelection: consentSelection,
                consentClipboard: consentClipboard,
                consentTextVersion: consentTextVersion,
                consentGivenAt: consentGivenAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> position = const Value.absent(),
                Value<String> smartMode = const Value.absent(),
                Value<String?> asrLanguage = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String> contextSource = const Value.absent(),
                Value<String?> hotkeyKey = const Value.absent(),
                Value<String?> hotkeyModifiers = const Value.absent(),
                Value<String?> afterTranscription = const Value.absent(),
                Value<String?> microphone = const Value.absent(),
                Value<String?> consentProvider = const Value.absent(),
                Value<bool> consentSelection = const Value.absent(),
                Value<bool> consentClipboard = const Value.absent(),
                Value<String?> consentTextVersion = const Value.absent(),
                Value<DateTime?> consentGivenAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppProfilesCompanion.insert(
                id: id,
                name: name,
                position: position,
                smartMode: smartMode,
                asrLanguage: asrLanguage,
                modelId: modelId,
                contextSource: contextSource,
                hotkeyKey: hotkeyKey,
                hotkeyModifiers: hotkeyModifiers,
                afterTranscription: afterTranscription,
                microphone: microphone,
                consentProvider: consentProvider,
                consentSelection: consentSelection,
                consentClipboard: consentClipboard,
                consentTextVersion: consentTextVersion,
                consentGivenAt: consentGivenAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $AppProfilesTable,
      AppProfileRow,
      $$AppProfilesTableFilterComposer,
      $$AppProfilesTableOrderingComposer,
      $$AppProfilesTableAnnotationComposer,
      $$AppProfilesTableCreateCompanionBuilder,
      $$AppProfilesTableUpdateCompanionBuilder,
      (
        AppProfileRow,
        BaseReferences<_$HistoryDatabase, $AppProfilesTable, AppProfileRow>,
      ),
      AppProfileRow,
      PrefetchHooks Function()
    >;
typedef $$AppProfileRulesTableCreateCompanionBuilder =
    AppProfileRulesCompanion Function({
      required String id,
      required String profileId,
      Value<int> position,
      required String identifier,
      Value<String?> teamId,
      Value<int> rowid,
    });
typedef $$AppProfileRulesTableUpdateCompanionBuilder =
    AppProfileRulesCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<int> position,
      Value<String> identifier,
      Value<String?> teamId,
      Value<int> rowid,
    });

class $$AppProfileRulesTableFilterComposer
    extends Composer<_$HistoryDatabase, $AppProfileRulesTable> {
  $$AppProfileRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identifier => $composableBuilder(
    column: $table.identifier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamId => $composableBuilder(
    column: $table.teamId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppProfileRulesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $AppProfileRulesTable> {
  $$AppProfileRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identifier => $composableBuilder(
    column: $table.identifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamId => $composableBuilder(
    column: $table.teamId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppProfileRulesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $AppProfileRulesTable> {
  $$AppProfileRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get identifier => $composableBuilder(
    column: $table.identifier,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamId =>
      $composableBuilder(column: $table.teamId, builder: (column) => column);
}

class $$AppProfileRulesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $AppProfileRulesTable,
          AppProfileRuleRow,
          $$AppProfileRulesTableFilterComposer,
          $$AppProfileRulesTableOrderingComposer,
          $$AppProfileRulesTableAnnotationComposer,
          $$AppProfileRulesTableCreateCompanionBuilder,
          $$AppProfileRulesTableUpdateCompanionBuilder,
          (
            AppProfileRuleRow,
            BaseReferences<
              _$HistoryDatabase,
              $AppProfileRulesTable,
              AppProfileRuleRow
            >,
          ),
          AppProfileRuleRow,
          PrefetchHooks Function()
        > {
  $$AppProfileRulesTableTableManager(
    _$HistoryDatabase db,
    $AppProfileRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppProfileRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppProfileRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppProfileRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> identifier = const Value.absent(),
                Value<String?> teamId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppProfileRulesCompanion(
                id: id,
                profileId: profileId,
                position: position,
                identifier: identifier,
                teamId: teamId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                Value<int> position = const Value.absent(),
                required String identifier,
                Value<String?> teamId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppProfileRulesCompanion.insert(
                id: id,
                profileId: profileId,
                position: position,
                identifier: identifier,
                teamId: teamId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppProfileRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $AppProfileRulesTable,
      AppProfileRuleRow,
      $$AppProfileRulesTableFilterComposer,
      $$AppProfileRulesTableOrderingComposer,
      $$AppProfileRulesTableAnnotationComposer,
      $$AppProfileRulesTableCreateCompanionBuilder,
      $$AppProfileRulesTableUpdateCompanionBuilder,
      (
        AppProfileRuleRow,
        BaseReferences<
          _$HistoryDatabase,
          $AppProfileRulesTable,
          AppProfileRuleRow
        >,
      ),
      AppProfileRuleRow,
      PrefetchHooks Function()
    >;

class $HistoryDatabaseManager {
  final _$HistoryDatabase _db;
  $HistoryDatabaseManager(this._db);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(_db, _db.historyEntries);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db, _db.dailyStats);
  $$EntryNotesTableTableManager get entryNotes =>
      $$EntryNotesTableTableManager(_db, _db.entryNotes);
  $$EntryAttachmentsTableTableManager get entryAttachments =>
      $$EntryAttachmentsTableTableManager(_db, _db.entryAttachments);
  $$TextReplacementsTableTableManager get textReplacements =>
      $$TextReplacementsTableTableManager(_db, _db.textReplacements);
  $$TextReplacementTriggersTableTableManager get textReplacementTriggers =>
      $$TextReplacementTriggersTableTableManager(
        _db,
        _db.textReplacementTriggers,
      );
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$EntryTagsTableTableManager get entryTags =>
      $$EntryTagsTableTableManager(_db, _db.entryTags);
  $$HotkeyLatencyEntriesTableTableManager get hotkeyLatencyEntries =>
      $$HotkeyLatencyEntriesTableTableManager(_db, _db.hotkeyLatencyEntries);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db, _db.snippets);
  $$SnippetFieldsTableTableManager get snippetFields =>
      $$SnippetFieldsTableTableManager(_db, _db.snippetFields);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$NoteTagsTableTableManager get noteTags =>
      $$NoteTagsTableTableManager(_db, _db.noteTags);
  $$NoteVersionsTableTableManager get noteVersions =>
      $$NoteVersionsTableTableManager(_db, _db.noteVersions);
  $$NoteAssetsTableTableManager get noteAssets =>
      $$NoteAssetsTableTableManager(_db, _db.noteAssets);
  $$CorrectionObservationsTableTableManager get correctionObservations =>
      $$CorrectionObservationsTableTableManager(
        _db,
        _db.correctionObservations,
      );
  $$AppProfilesTableTableManager get appProfiles =>
      $$AppProfilesTableTableManager(_db, _db.appProfiles);
  $$AppProfileRulesTableTableManager get appProfileRules =>
      $$AppProfileRulesTableTableManager(_db, _db.appProfileRules);
}
