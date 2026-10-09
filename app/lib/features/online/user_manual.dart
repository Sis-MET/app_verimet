import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/app_config.dart';
import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'online_widgets.dart';
import 'user_manual_content.dart';

/// Manual de uso de IvMET como documento controlado (NB/ISO/IEC 17025 7.11.5
/// y 8.3): el contenido vive en `user_manual_content.dart`, la app lo muestra
/// sin conexión con búsqueda y lo exporta en PDF como copia controlada.

/// Datos de control del documento. Lo que asigna Calidad queda pendiente
/// hasta que se apruebe.
class ManualControl {
  const ManualControl({
    required this.code,
    required this.title,
    required this.revision,
    required this.issuedOn,
    required this.appliesTo,
    required this.preparedBy,
    required this.reviewedBy,
    required this.approvedBy,
    required this.history,
  });
  final String code, title, revision, issuedOn, preparedBy, reviewedBy;
  final String approvedBy;

  /// Versión menor de la app que describe, por ejemplo «1.0.x».
  final String appliesTo;
  final List<ManualRevision> history;

  bool get approved => !approvedBy.startsWith('PENDIENTE');
}

class ManualRevision {
  const ManualRevision(this.revision, this.date, this.description);
  final String revision, date, description;
}

sealed class ManualBlock {
  const ManualBlock();

  /// Texto plano, para buscar y exportar.
  String get text;
}

class ManualParagraph extends ManualBlock {
  const ManualParagraph(this.content);
  final String content;
  @override
  String get text => content;
}

/// Pasos numerados, en el orden en que se hacen.
class ManualSteps extends ManualBlock {
  const ManualSteps(this.title, this.steps);
  final String? title;
  final List<ManualStep> steps;
  @override
  String get text => [
    title ?? '',
    for (final step in steps) '${step.action} ${step.detail ?? ''}',
  ].join(' ');
}

class ManualStep {
  const ManualStep(this.action, [this.detail]);

  /// Qué hacer, empezando por el verbo y con el texto exacto del botón.
  final String action;
  final String? detail;
}

class ManualList extends ManualBlock {
  const ManualList(this.title, this.items);
  final String? title;
  final List<String> items;
  @override
  String get text => [title ?? '', ...items].join(' ');
}

enum ManualNoteKind {
  tip('Consejo', Icons.lightbulb_outline),
  important('Importante', Icons.warning_amber_outlined),
  norm('NB/ISO/IEC 17025', Icons.verified_outlined);

  const ManualNoteKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ManualNote extends ManualBlock {
  const ManualNote(this.kind, this.content, {this.reference});
  final ManualNoteKind kind;
  final String content;

  /// Cláusula relacionada, en las notas de la norma.
  final String? reference;
  @override
  String get text => content;
}

enum ManualGroup {
  start('Primeros pasos'),
  setup('Configurar · jefe de calidad'),
  verify('Verificar'),
  records('Registros y datos'),
  account('Cuenta y plan'),
  help('Ayuda');

  const ManualGroup(this.label);
  final String label;
}

class ManualSection {
  const ManualSection({
    required this.id,
    required this.group,
    required this.title,
    required this.icon,
    required this.summary,
    required this.blocks,
    this.audience = 'Todos',
  });
  final String id, title, summary;
  final ManualGroup group;
  final IconData icon;
  final List<ManualBlock> blocks;

  /// Quién lo usa: «Todos», «Jefe de calidad», «Operador».
  final String audience;

  bool matches(String query) {
    final q = _fold(query.trim());
    if (q.isEmpty) return true;
    return _fold(title).contains(q) ||
        _fold(summary).contains(q) ||
        blocks.any((block) => _fold(block.text).contains(q));
  }
}

class UserManual {
  const UserManual({required this.control, required this.sections});
  final ManualControl control;
  final List<ManualSection> sections;
}

/// Minúsculas y sin acentos: «balanza» encuentra «Balanza» y «medicion»,
/// «medición».
String _fold(String value) => value.toLowerCase().replaceAllMapped(
  RegExp('[áéíóúü]'),
  (m) =>
      const {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'}[m[0]]!,
);

/// Texto con la búsqueda resaltada.
TextSpan _highlighted(String text, String query, TextStyle base, Color mark) {
  final q = _fold(query.trim());
  if (q.isEmpty) return TextSpan(text: text, style: base);
  final folded = _fold(text);
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final at = folded.indexOf(q, start);
    if (at < 0) break;
    if (at > start) spans.add(TextSpan(text: text.substring(start, at)));
    spans.add(
      TextSpan(
        text: text.substring(at, at + q.length),
        style: TextStyle(backgroundColor: mark),
      ),
    );
    start = at + q.length;
  }
  spans.add(TextSpan(text: text.substring(start)));
  return TextSpan(style: base, children: spans);
}

/// Genera la copia controlada en PDF y la comparte.
Future<void> exportUserManual(BuildContext context) async {
  try {
    final bytes = await buildUserManualPdf(ivmetUserManual);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'manual_ivmet_rev${ivmetUserManual.control.revision.split(' ').first}.pdf',
      subject: ivmetUserManual.control.title,
    );
  } catch (_) {
    if (context.mounted) {
      showWizardMessage(context, 'No se pudo generar el PDF del manual.');
    }
  }
}

/// Manual de uso: búsqueda, datos de control y secciones por grupo.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key, this.manual = ivmetUserManual});
  final UserManual manual;
  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final manual = widget.manual;
    final control = manual.control;
    final visible = manual.sections.where((s) => s.matches(query)).toList();
    final menu = pageMenu([
      wizardMenuItem<VoidCallback>(
        () => exportUserManual(context),
        Icons.picture_as_pdf_outlined,
        'Exportar PDF',
      ),
    ]);
    return OnlinePage(
      title: 'Manual de uso',
      actions: [?menu],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
        children: [
          TextField(
            key: const ValueKey('manual-search'),
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar en el manual',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        search.clear();
                        query = '';
                      }),
                    ),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          if (query.isEmpty) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              key: const ValueKey('manual-control'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    control.title,
                    style: AppTextStyles.figure(context, size: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Revisión ${control.revision} · ${control.issuedOn} · '
                    'aplica a la versión ${control.appliesTo} '
                    '(instalada: ${AppConfig.version})',
                    style: TextStyle(fontSize: 12.5, color: palette.muted),
                  ),
                  if (!control.approved)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Pendiente de aprobación',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.fail,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (visible.isEmpty)
            Notice('Nada coincide con «$query».', icon: Icons.search_off),
          for (final group in ManualGroup.values)
            if (visible.any((s) => s.group == group)) ...[
              SectionLabel(group.label),
              SurfaceList(
                children: [
                  for (final section in visible.where((s) => s.group == group))
                    _SectionRow(
                      section: section,
                      query: query,
                      onTap: () => openPage<void>(
                        context,
                        ManualSectionScreen(
                          manual: manual,
                          section: section,
                          query: query,
                        ),
                      ),
                    ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.query,
    required this.onTap,
  });
  final ManualSection section;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return InkWell(
      key: ValueKey('manual-section-${section.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Icon(section.icon, color: palette.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    _highlighted(
                      section.title,
                      query,
                      AppTextStyles.figure(context, size: 16),
                      palette.accentSoft,
                    ),
                  ),
                  Text(
                    section.summary,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Una sección del manual. Los pasos se marcan al hacerlos y la píldora lleva
/// a la siguiente sección.
class ManualSectionScreen extends StatefulWidget {
  const ManualSectionScreen({
    required this.manual,
    required this.section,
    this.query = '',
    super.key,
  });
  final UserManual manual;
  final ManualSection section;
  final String query;
  @override
  State<ManualSectionScreen> createState() => _ManualSectionScreenState();
}

class _ManualSectionScreenState extends State<ManualSectionScreen> {
  final done = <String>{};

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final section = widget.section;
    final sections = widget.manual.sections;
    final index = sections.indexOf(section);
    final next = index >= 0 && index < sections.length - 1
        ? sections[index + 1]
        : null;
    final body = TextStyle(fontSize: 14, height: 1.5, color: palette.text);
    TextSpan rich(String text, [TextStyle? style]) =>
        _highlighted(text, widget.query, style ?? body, palette.accentSoft);

    return OnlinePage(
      title: section.title,
      floating: next == null
          ? null
          : WizardNavPill.action(
              key: const ValueKey('manual-next'),
              label: 'Siguiente: ${next.title}',
              icon: Icons.arrow_forward_rounded,
              onNext: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ManualSectionScreen(manual: widget.manual, section: next),
                ),
              ),
            ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          16,
          20,
          WizardNavPill.contentPadding,
        ),
        children: [
          Kicker('${section.group.label} · ${section.audience}'),
          const SizedBox(height: 4),
          Text(
            section.summary,
            style: TextStyle(fontSize: 13, color: palette.muted),
          ),
          const SizedBox(height: 8),
          for (final (i, block) in section.blocks.indexed)
            switch (block) {
              ManualParagraph(:final content) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text.rich(rich(content)),
              ),
              ManualList(:final title, :final items) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) SectionLabel(title),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, right: 10),
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(child: Text.rich(rich(item))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              ManualSteps(:final title, :final steps) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      SectionLabel(
                        '$title · ${steps.where((s) => done.contains('$i:${steps.indexOf(s)}')).length} de ${steps.length}',
                      ),
                    SurfaceList(
                      children: [
                        for (final (j, step) in steps.indexed)
                          _StepRow(
                            number: j + 1,
                            done: done.contains('$i:$j'),
                            action: rich(
                              step.action,
                              body.copyWith(fontWeight: FontWeight.w600),
                            ),
                            detail: step.detail == null
                                ? null
                                : rich(
                                    step.detail!,
                                    TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: palette.muted,
                                    ),
                                  ),
                            onTap: () => setState(
                              () => done.contains('$i:$j')
                                  ? done.remove('$i:$j')
                                  : done.add('$i:$j'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              ManualNote(:final kind, :final content, :final reference) => Notice(
                '${kind.label}${reference == null ? '' : ' · $reference'}: $content',
                icon: kind.icon,
                alert: kind == ManualNoteKind.important,
              ),
            },
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.done,
    required this.action,
    required this.detail,
    required this.onTap,
  });
  final int number;
  final bool done;
  final TextSpan action;
  final TextSpan? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? palette.success : palette.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: done
                  ? Icon(Icons.check, size: 16, color: palette.card)
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.accentDeep,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(action),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(detail!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copia controlada del manual: datos de control, historial y secciones.
Future<Uint8List> buildUserManualPdf(UserManual manual) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final italic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
  );
  const ink = PdfColor.fromInt(0xFF1D2228);
  const muted = PdfColor.fromInt(0xFF5D6670);
  const accent = PdfColor.fromInt(0xFF3F6489);
  final control = manual.control;
  final document = pw.Document(
    title: control.title,
    author: 'Métrica Ltda.',
    creator: 'IvMET ${AppConfig.version}',
  );
  pw.Widget cell(String text, {bool header = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
  pw.Widget table(List<List<String>> rows, {bool header = false}) => pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    children: [
      for (final (i, row) in rows.indexed)
        pw.TableRow(
          children: [for (final c in row) cell(c, header: header && i == 0)],
        ),
    ],
  );
  final content = <pw.Widget>[
    pw.Text(
      control.title,
      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 10),
    table([
      ['Código', control.code],
      ['Revisión', control.revision],
      ['Fecha de emisión', control.issuedOn],
      ['Aplica a la versión de la app', control.appliesTo],
      ['Elaboró', control.preparedBy],
      ['Revisó', control.reviewedBy],
      ['Aprobó', control.approvedBy],
    ]),
    pw.SizedBox(height: 10),
    pw.Text(
      'Historial de revisiones',
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    table([
      ['Rev.', 'Fecha', 'Descripción'],
      for (final r in control.history) [r.revision, r.date, r.description],
    ], header: true),
    pw.SizedBox(height: 14),
    pw.Text('Contenido', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    for (final (i, s) in manual.sections.indexed)
      pw.Text('${i + 1}. ${s.title}', style: const pw.TextStyle(fontSize: 10)),
  ];
  for (final (i, section) in manual.sections.indexed) {
    content.add(pw.NewPage());
    content.addAll([
      pw.Text(
        '${section.group.label} · ${section.audience}'.toUpperCase(),
        style: const pw.TextStyle(fontSize: 8, color: accent),
      ),
      pw.Text(
        '${i + 1}. ${section.title}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(section.summary, style: const pw.TextStyle(color: muted)),
      pw.SizedBox(height: 8),
    ]);
    for (final block in section.blocks) {
      content.add(switch (block) {
        ManualParagraph(:final content) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(content, style: const pw.TextStyle(lineSpacing: 2)),
        ),
        ManualList(:final title, :final items) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (title != null)
              pw.Text(
                title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            for (final item in items) pw.Bullet(text: item),
            pw.SizedBox(height: 4),
          ],
        ),
        ManualSteps(:final title, :final steps) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (title != null)
              pw.Text(
                title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            for (final (j, step) in steps.indexed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  '${j + 1}. ${step.action}${step.detail == null ? '' : ' — ${step.detail}'}',
                ),
              ),
            pw.SizedBox(height: 6),
          ],
        ),
        ManualNote(:final kind, :final content, :final reference) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.only(left: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: accent, width: 2)),
          ),
          child: pw.Text(
            '${kind.label}${reference == null ? '' : ' · $reference'}: $content',
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: ink),
          ),
        ),
      });
    }
  }
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 50),
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${control.code} · Rev. ${control.revision} · ${control.approved ? 'Aprobado' : 'Pendiente de aprobación'}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
      build: (_) => content,
    ),
  );
  return document.save();
}
