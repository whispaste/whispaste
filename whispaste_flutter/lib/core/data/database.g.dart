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
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    projectId,
    archived,
    titleEdited,
    deletedAt,
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
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
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
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
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
  final String languageHint;
  final String tags;
  final bool pinned;
  final String source;
  final String model;
  final bool isLocal;
  final double costUsd;
  final String projectId;
  final bool archived;
  final bool titleEdited;
  final DateTime? deletedAt;
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
    required this.projectId,
    required this.archived,
    required this.titleEdited,
    this.deletedAt,
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
    map['project_id'] = Variable<String>(projectId);
    map['archived'] = Variable<bool>(archived);
    map['title_edited'] = Variable<bool>(titleEdited);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
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
      projectId: Value(projectId),
      archived: Value(archived),
      titleEdited: Value(titleEdited),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
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
      projectId: serializer.fromJson<String>(json['projectId']),
      archived: serializer.fromJson<bool>(json['archived']),
      titleEdited: serializer.fromJson<bool>(json['titleEdited']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
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
      'projectId': serializer.toJson<String>(projectId),
      'archived': serializer.toJson<bool>(archived),
      'titleEdited': serializer.toJson<bool>(titleEdited),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
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
    String? projectId,
    bool? archived,
    bool? titleEdited,
    Value<DateTime?> deletedAt = const Value.absent(),
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
    projectId: projectId ?? this.projectId,
    archived: archived ?? this.archived,
    titleEdited: titleEdited ?? this.titleEdited,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
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
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      archived: data.archived.present ? data.archived.value : this.archived,
      titleEdited: data.titleEdited.present
          ? data.titleEdited.value
          : this.titleEdited,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
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
          ..write('projectId: $projectId, ')
          ..write('archived: $archived, ')
          ..write('titleEdited: $titleEdited, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
    projectId,
    archived,
    titleEdited,
    deletedAt,
  );
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
          other.projectId == this.projectId &&
          other.archived == this.archived &&
          other.titleEdited == this.titleEdited &&
          other.deletedAt == this.deletedAt);
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
  final Value<String> projectId;
  final Value<bool> archived;
  final Value<bool> titleEdited;
  final Value<DateTime?> deletedAt;
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
    this.projectId = const Value.absent(),
    this.archived = const Value.absent(),
    this.titleEdited = const Value.absent(),
    this.deletedAt = const Value.absent(),
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
    this.projectId = const Value.absent(),
    this.archived = const Value.absent(),
    this.titleEdited = const Value.absent(),
    this.deletedAt = const Value.absent(),
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
    Expression<String>? projectId,
    Expression<bool>? archived,
    Expression<bool>? titleEdited,
    Expression<DateTime>? deletedAt,
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
      if (projectId != null) 'project_id': projectId,
      if (archived != null) 'archived': archived,
      if (titleEdited != null) 'title_edited': titleEdited,
      if (deletedAt != null) 'deleted_at': deletedAt,
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
    Value<String>? projectId,
    Value<bool>? archived,
    Value<bool>? titleEdited,
    Value<DateTime?>? deletedAt,
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
      projectId: projectId ?? this.projectId,
      archived: archived ?? this.archived,
      titleEdited: titleEdited ?? this.titleEdited,
      deletedAt: deletedAt ?? this.deletedAt,
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
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
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
          ..write('projectId: $projectId, ')
          ..write('archived: $archived, ')
          ..write('titleEdited: $titleEdited, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Project> instance, {
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
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
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
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String name;
  final DateTime createdAt;
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Project.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
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

  Project copyWith({String? id, String? name, DateTime? createdAt}) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
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
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Project> custom({
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

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
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
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
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
  @override
  List<GeneratedColumn> get $columns => [id, trigger, replacement, createdAt];
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
  const TextReplacement({
    required this.id,
    required this.trigger,
    required this.replacement,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['trigger'] = Variable<String>(trigger);
    map['replacement'] = Variable<String>(replacement);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TextReplacementsCompanion toCompanion(bool nullToAbsent) {
    return TextReplacementsCompanion(
      id: Value(id),
      trigger: Value(trigger),
      replacement: Value(replacement),
      createdAt: Value(createdAt),
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
    };
  }

  TextReplacement copyWith({
    String? id,
    String? trigger,
    String? replacement,
    DateTime? createdAt,
  }) => TextReplacement(
    id: id ?? this.id,
    trigger: trigger ?? this.trigger,
    replacement: replacement ?? this.replacement,
    createdAt: createdAt ?? this.createdAt,
  );
  TextReplacement copyWithCompanion(TextReplacementsCompanion data) {
    return TextReplacement(
      id: data.id.present ? data.id.value : this.id,
      trigger: data.trigger.present ? data.trigger.value : this.trigger,
      replacement: data.replacement.present
          ? data.replacement.value
          : this.replacement,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TextReplacement(')
          ..write('id: $id, ')
          ..write('trigger: $trigger, ')
          ..write('replacement: $replacement, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trigger, replacement, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextReplacement &&
          other.id == this.id &&
          other.trigger == this.trigger &&
          other.replacement == this.replacement &&
          other.createdAt == this.createdAt);
}

class TextReplacementsCompanion extends UpdateCompanion<TextReplacement> {
  final Value<String> id;
  final Value<String> trigger;
  final Value<String> replacement;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TextReplacementsCompanion({
    this.id = const Value.absent(),
    this.trigger = const Value.absent(),
    this.replacement = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TextReplacementsCompanion.insert({
    required String id,
    required String trigger,
    required String replacement,
    required DateTime createdAt,
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trigger != null) 'trigger': trigger,
      if (replacement != null) 'replacement': replacement,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TextReplacementsCompanion copyWith({
    Value<String>? id,
    Value<String>? trigger,
    Value<String>? replacement,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TextReplacementsCompanion(
      id: id ?? this.id,
      trigger: trigger ?? this.trigger,
      replacement: replacement ?? this.replacement,
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
    if (trigger.present) {
      map['trigger'] = Variable<String>(trigger.value);
    }
    if (replacement.present) {
      map['replacement'] = Variable<String>(replacement.value);
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
    return (StringBuffer('TextReplacementsCompanion(')
          ..write('id: $id, ')
          ..write('trigger: $trigger, ')
          ..write('replacement: $replacement, ')
          ..write('createdAt: $createdAt, ')
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

abstract class _$HistoryDatabase extends GeneratedDatabase {
  _$HistoryDatabase(QueryExecutor e) : super(e);
  $HistoryDatabaseManager get managers => $HistoryDatabaseManager(this);
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $DailyStatsTable dailyStats = $DailyStatsTable(this);
  late final $EntryNotesTable entryNotes = $EntryNotesTable(this);
  late final $EntryAttachmentsTable entryAttachments = $EntryAttachmentsTable(
    this,
  );
  late final $TextReplacementsTable textReplacements = $TextReplacementsTable(
    this,
  );
  late final $TagsTable tags = $TagsTable(this);
  late final $EntryTagsTable entryTags = $EntryTagsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    historyEntries,
    projects,
    dailyStats,
    entryNotes,
    entryAttachments,
    textReplacements,
    tags,
    entryTags,
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
      Value<String> projectId,
      Value<bool> archived,
      Value<bool> titleEdited,
      Value<DateTime?> deletedAt,
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
      Value<String> projectId,
      Value<bool> archived,
      Value<bool> titleEdited,
      Value<DateTime?> deletedAt,
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
    aliasName: $_aliasNameGenerator(
      db.historyEntries.id,
      db.entryNotes.entryId,
    ),
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
        aliasName: $_aliasNameGenerator(
          db.historyEntries.id,
          db.entryAttachments.entryId,
        ),
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
    aliasName: $_aliasNameGenerator(db.historyEntries.id, db.entryTags.entryId),
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

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
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

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
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

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<bool> get titleEdited => $composableBuilder(
    column: $table.titleEdited,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

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
                Value<String> projectId = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> titleEdited = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
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
                projectId: projectId,
                archived: archived,
                titleEdited: titleEdited,
                deletedAt: deletedAt,
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
                Value<String> projectId = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> titleEdited = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
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
                projectId: projectId,
                archived: archived,
                titleEdited: titleEdited,
                deletedAt: deletedAt,
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
typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ProjectsTableFilterComposer
    extends Composer<_$HistoryDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
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
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$HistoryDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
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

class $$ProjectsTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
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
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $ProjectsTable,
          Project,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (Project, BaseReferences<_$HistoryDatabase, $ProjectsTable, Project>),
          Project,
          PrefetchHooks Function()
        > {
  $$ProjectsTableTableManager(_$HistoryDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
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
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
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

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $ProjectsTable,
      Project,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (Project, BaseReferences<_$HistoryDatabase, $ProjectsTable, Project>),
      Project,
      PrefetchHooks Function()
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

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) =>
      db.historyEntries.createAlias(
        $_aliasNameGenerator(db.entryNotes.entryId, db.historyEntries.id),
      );

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

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) =>
      db.historyEntries.createAlias(
        $_aliasNameGenerator(db.entryAttachments.entryId, db.historyEntries.id),
      );

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
      Value<int> rowid,
    });
typedef $$TextReplacementsTableUpdateCompanionBuilder =
    TextReplacementsCompanion Function({
      Value<String> id,
      Value<String> trigger,
      Value<String> replacement,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

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
          (
            TextReplacement,
            BaseReferences<
              _$HistoryDatabase,
              $TextReplacementsTable,
              TextReplacement
            >,
          ),
          TextReplacement,
          PrefetchHooks Function()
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
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementsCompanion(
                id: id,
                trigger: trigger,
                replacement: replacement,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String trigger,
                required String replacement,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TextReplacementsCompanion.insert(
                id: id,
                trigger: trigger,
                replacement: replacement,
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
      (
        TextReplacement,
        BaseReferences<
          _$HistoryDatabase,
          $TextReplacementsTable,
          TextReplacement
        >,
      ),
      TextReplacement,
      PrefetchHooks Function()
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
    aliasName: $_aliasNameGenerator(db.tags.id, db.entryTags.tagId),
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
          PrefetchHooks Function({bool entryTagsRefs})
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
          prefetchHooksCallback: ({entryTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (entryTagsRefs) db.entryTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (entryTagsRefs)
                    await $_getPrefetchedData<Tag, $TagsTable, EntryTag>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._entryTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).entryTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
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
      PrefetchHooks Function({bool entryTagsRefs})
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

  static $HistoryEntriesTable _entryIdTable(_$HistoryDatabase db) =>
      db.historyEntries.createAlias(
        $_aliasNameGenerator(db.entryTags.entryId, db.historyEntries.id),
      );

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
      db.tags.createAlias($_aliasNameGenerator(db.entryTags.tagId, db.tags.id));

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

class $HistoryDatabaseManager {
  final _$HistoryDatabase _db;
  $HistoryDatabaseManager(this._db);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(_db, _db.historyEntries);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db, _db.dailyStats);
  $$EntryNotesTableTableManager get entryNotes =>
      $$EntryNotesTableTableManager(_db, _db.entryNotes);
  $$EntryAttachmentsTableTableManager get entryAttachments =>
      $$EntryAttachmentsTableTableManager(_db, _db.entryAttachments);
  $$TextReplacementsTableTableManager get textReplacements =>
      $$TextReplacementsTableTableManager(_db, _db.textReplacements);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$EntryTagsTableTableManager get entryTags =>
      $$EntryTagsTableTableManager(_db, _db.entryTags);
}
