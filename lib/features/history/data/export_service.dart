import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Supported export formats.
enum ExportFormat { txt, md, json, csv, docx }

/// Lightweight DTO mirroring the fields needed for export.
class ExportEntry {
  const ExportEntry({
    required this.id,
    required this.title,
    required this.text,
    required this.timestamp,
    this.duration = 0,
    this.language = '',
    this.tags = const [],
    this.pinned = false,
    this.model = '',
    this.isLocal = true,
    this.costUsd = 0,
    this.projectName = '',
  });

  final String id;
  final String title;
  final String text;
  final String timestamp;
  final double duration;
  final String language;
  final List<String> tags;
  final bool pinned;
  final String model;
  final bool isLocal;
  final double costUsd;
  final String projectName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'title': title,
    'timestamp': timestamp,
    'duration_sec': duration,
    'language': language,
    if (tags.isNotEmpty) 'tags': tags,
    if (pinned) 'pinned': pinned,
    if (model.isNotEmpty) 'model': model,
    if (isLocal) 'is_local': isLocal,
    if (costUsd > 0) 'cost_usd': costUsd,
    if (projectName.isNotEmpty) 'project_name': projectName,
  };
}

/// Pure-Dart export service — formats entries and writes to disk.
class ExportService {
  // ── Public API ──────────────────────────────────────────────────────────

  /// Format [entries] in [format] and write to [path].
  /// Returns the number of bytes written.
  static Future<int> export(
    List<ExportEntry> entries,
    ExportFormat format,
    String path,
  ) async {
    if (entries.isEmpty) return 0;

    final Uint8List data;
    switch (format) {
      case ExportFormat.json:
        data = _formatJson(entries);
      case ExportFormat.csv:
        data = _formatCsv(entries);
      case ExportFormat.docx:
        data = _generateDocx(entries);
      case ExportFormat.md:
        data = _formatMulti(entries, _formatMd);
      case ExportFormat.txt:
        data = _formatMulti(entries, _formatTxt);
    }

    final file = File(path);
    await file.writeAsBytes(data);
    return data.length;
  }

  /// Suggest a default filename for the given entries and format.
  static String defaultFilename(
    List<ExportEntry> entries,
    ExportFormat format,
  ) {
    final ext = '.${format.name}';
    if (entries.length == 1) {
      final safe = _sanitizeFilename(entries.first.title);
      if (safe.isNotEmpty) return '$safe$ext';
    }
    return 'whispaste-export$ext';
  }

  // ── Text ────────────────────────────────────────────────────────────────

  static String _formatTxt(ExportEntry e) {
    final b = StringBuffer()
      ..writeln(e.title)
      ..writeln('Date: ${e.timestamp}');
    if (e.language.isNotEmpty) b.writeln('Language: ${e.language}');
    if (e.tags.isNotEmpty) b.writeln('Tags: ${e.tags.join(', ')}');
    if (e.projectName.isNotEmpty) b.writeln('Project: ${e.projectName}');
    b
      ..writeln()
      ..writeln(e.text);
    return b.toString();
  }

  // ── Markdown ────────────────────────────────────────────────────────────

  static String _formatMd(ExportEntry e) {
    final b = StringBuffer()
      ..writeln('# ${e.title}')
      ..writeln()
      ..writeln('- **Date:** ${e.timestamp}');
    if (e.language.isNotEmpty) {
      b.writeln('- **Language:** ${e.language.toUpperCase()}');
    }
    if (e.duration > 0) {
      b.writeln('- **Duration:** ${e.duration.toStringAsFixed(1)}s');
    }
    if (e.tags.isNotEmpty) {
      b.writeln('- **Tags:** ${e.tags.map((t) => '`$t`').join(', ')}');
    }
    if (e.projectName.isNotEmpty) {
      b.writeln('- **Project:** ${e.projectName}');
    }
    b
      ..writeln()
      ..writeln(e.text);
    return b.toString();
  }

  // ── JSON ────────────────────────────────────────────────────────────────

  static Uint8List _formatJson(List<ExportEntry> entries) {
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(entries.map((e) => e.toJson()).toList());
    return Uint8List.fromList(utf8.encode('$json\n'));
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  static Uint8List _formatCsv(List<ExportEntry> entries) {
    final b = StringBuffer();
    const header =
        'ID,Title,Text,Timestamp,Duration,Language,Tags,Pinned,Model,IsLocal,CostUSD,Project';
    b.writeln(header);

    for (final e in entries) {
      final row = [
        e.id,
        _csvSafe(e.title),
        _csvSafe(e.text),
        e.timestamp,
        e.duration.toStringAsFixed(1),
        e.language,
        e.tags.join('|'),
        '${e.pinned}',
        e.model,
        '${e.isLocal}',
        e.costUsd.toStringAsFixed(6),
        _csvSafe(e.projectName),
      ];
      b.writeln(row.map(_csvEscape).join(','));
    }
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  /// Prevents CSV formula injection.
  static String _csvSafe(String s) {
    if (s.isNotEmpty && '=+-@'.contains(s[0])) return '\t$s';
    return s;
  }

  /// Quotes and escapes a CSV field.
  static String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  // ── DOCX (minimal OpenXML) ──────────────────────────────────────────────

  static Uint8List _generateDocx(List<ExportEntry> entries) {
    final body = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (i > 0) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }

      // Title (Heading1)
      body.write('<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>');
      body.write('<w:r><w:t xml:space="preserve">');
      body.write(_xmlEscape(e.title));
      body.write('</w:t></w:r></w:p>');

      // Metadata
      final meta = StringBuffer('Date: ${e.timestamp}');
      if (e.language.isNotEmpty) {
        meta.write('  |  Language: ${e.language.toUpperCase()}');
      }
      if (e.duration > 0) {
        meta.write('  |  Duration: ${e.duration.toStringAsFixed(1)}s');
      }
      if (e.model.isNotEmpty) meta.write('  |  Model: ${e.model}');
      body.write('<w:p><w:pPr><w:pStyle w:val="Meta"/></w:pPr>');
      body.write('<w:r><w:t xml:space="preserve">');
      body.write(_xmlEscape(meta.toString()));
      body.write('</w:t></w:r></w:p>');

      // Tags
      if (e.tags.isNotEmpty) {
        body.write('<w:p><w:pPr><w:pStyle w:val="Meta"/></w:pPr>');
        body.write('<w:r><w:t xml:space="preserve">Tags: ');
        body.write(_xmlEscape(e.tags.join(', ')));
        body.write('</w:t></w:r></w:p>');
      }

      // Project
      if (e.projectName.isNotEmpty) {
        body.write('<w:p><w:pPr><w:pStyle w:val="Meta"/></w:pPr>');
        body.write('<w:r><w:t xml:space="preserve">Project: ');
        body.write(_xmlEscape(e.projectName));
        body.write('</w:t></w:r></w:p>');
      }

      // Spacer + body text
      body.write('<w:p/>');
      for (final line in e.text.split('\n')) {
        body.write('<w:p><w:r><w:t xml:space="preserve">');
        body.write(_xmlEscape(line));
        body.write('</w:t></w:r></w:p>');
      }
    }

    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>${body.toString()}</w:body>'
        '</w:document>';

    final ctBytes = utf8.encode(_contentTypes);
    final relsBytes = utf8.encode(_relsXml);
    final wordRelsBytes = utf8.encode(_wordRels);
    final stylesBytes = utf8.encode(_stylesXml);
    final docBytes = utf8.encode(document);

    final archive = Archive()
      ..addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes))
      ..addFile(ArchiveFile('_rels/.rels', relsBytes.length, relsBytes))
      ..addFile(
        ArchiveFile(
          'word/_rels/document.xml.rels',
          wordRelsBytes.length,
          wordRelsBytes,
        ),
      )
      ..addFile(ArchiveFile('word/styles.xml', stylesBytes.length, stylesBytes))
      ..addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static String _xmlEscape(String s) {
    // Use XmlBuilder's text escaping
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static const _relsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static const _wordRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static const _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:style w:type="paragraph" w:styleId="Heading1">'
      '<w:name w:val="heading 1"/>'
      '<w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1A1A2E"/></w:rPr>'
      '</w:style>'
      '<w:style w:type="paragraph" w:styleId="Meta">'
      '<w:name w:val="Meta"/>'
      '<w:pPr><w:spacing w:after="40"/></w:pPr>'
      '<w:rPr><w:sz w:val="18"/><w:color w:val="666666"/></w:rPr>'
      '</w:style>'
      '</w:styles>';

  // ── Helpers ─────────────────────────────────────────────────────────────

  static Uint8List _formatMulti(
    List<ExportEntry> entries,
    String Function(ExportEntry) formatter,
  ) {
    final b = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      b.write(formatter(entries[i]));
      if (i < entries.length - 1) b.write('\n---\n\n');
    }
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  static String _sanitizeFilename(String name) {
    var safe = name.trim();
    if (safe.length > 50) safe = safe.substring(0, 50);
    safe = safe.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '');
    return safe.trim();
  }
}
