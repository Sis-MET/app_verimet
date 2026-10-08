import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/measurement_format.dart';

typedef ReportJson = Map<String, dynamic>;

final _navy = PdfColor.fromHex('#153447');
final _blue = PdfColor.fromHex('#247BA0');
final _paleBlue = PdfColor.fromHex('#EAF4F8');
final _green = PdfColor.fromHex('#2E7D5B');
final _red = PdfColor.fromHex('#B53A3A');
final _amber = PdfColor.fromHex('#9A6700');
final _ink = PdfColor.fromHex('#24313A');
final _muted = PdfColor.fromHex('#667782');
final _line = PdfColor.fromHex('#D8E1E6');
final _paleRed = PdfColor.fromHex('#FBEAEA');
final _paleAmber = PdfColor.fromHex('#FBF3E2');
final _paper = PdfColor.fromHex('#F7F9FA');

ReportJson _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<ReportJson> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((item) => _map(item)).toList()
    : <ReportJson>[];

String _value(Object? value, {String fallback = 'No informado'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double? _number(Object? value) =>
    double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '');

/// Numero para el informe: sin los ceros de relleno que arrastra el `numeric`
/// de Postgres y con coma decimal, como el resto de la app.
///
/// El servidor guarda los decimales con punto —es lo que
/// `normalizedDecimal` envia— pero el informe lo lee un cliente en Bolivia.
String _decimal(Object? value) {
  final text = _value(value, fallback: '-');
  return text == '-' ? text : MeasurementFormat.display(text);
}

String _date(Object? value, {bool time = true}) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return _value(value);
  return DateFormat(
    time ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy',
  ).format(parsed.toLocal());
}

String _verdict(Object? value) => switch (value?.toString()) {
  'pass' => 'Conforme',
  'fail' => 'No conforme',
  'inconclusive' => 'No concluyente',
  _ => _value(value, fallback: 'Sin resultado'),
};

PdfColor _verdictColor(Object? value) => switch (value?.toString()) {
  'pass' => _green,
  'fail' => _red,
  _ => _amber,
};

String _testName(Object? value) => switch (value?.toString()) {
  'eccentricity' => 'Excentricidad',
  'repeatability' => 'Repetibilidad',
  'linearity' => 'Linealidad',
  _ => _value(value),
};

String _safeFilePart(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return normalized.isEmpty ? 'balanza' : normalized;
}

String verificationReportFilename(ReportJson data) {
  final verification = _map(data['verification']);
  final snapshot = _map(verification['equipo_snapshot']);
  final equipment = _map(snapshot['equipment']);
  final code = _value(
    equipment['cod_interno'] ?? equipment['cod_metrica'],
    fallback: 'balanza',
  );
  final measured = DateTime.tryParse(
    verification['realizado_at']?.toString() ?? '',
  );
  final date = measured == null
      ? 'sin_fecha'
      : DateFormat('yyyyMMdd').format(measured.toLocal());
  return 'verificacion_${_safeFilePart(code)}_$date.pdf';
}

/// Con [full] en false (el plan gratuito) el informe es resumido: conserva la
/// identificacion, las condiciones, el resumen de resultados y los avisos
/// legales, y deja fuera las lecturas de cada prueba y la trazabilidad de los
/// patrones.
Future<Uint8List> buildVerificationReport(
  ReportJson data, {
  DateTime? generatedAt,
  String? generatedBy,
  bool full = true,
}) async {
  final verification = _map(data['verification']);
  final users = _map(data['users']);
  final equipmentSnapshot = _map(verification['equipo_snapshot']);
  final equipment = _map(equipmentSnapshot['equipment']);
  final ranges = _maps(equipmentSnapshot['ranges']);
  final plan = _map(verification['plan_snapshot']);
  final tests = _maps(data['tests']);
  final patterns = _maps(data['patterns']);
  final reportId = _value(verification['id']);
  final generated = generatedAt ?? DateTime.now();
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final italicFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
  );
  final document = pw.Document(
    title: 'Informe de verificación intermedia - $reportId',
    author: 'IvMET',
    creator: 'IvMET',
    subject: 'Resultado histórico de verificación metrológica intermedia',
    keywords: 'IvMET, verificación intermedia, balanza, metrología',
  );

  final widgets = <pw.Widget>[
    _reportTitle(verification, equipment, reportId),
    pw.SizedBox(height: 14),
    _notice(
      'Este documento NO tiene validez legal. Es un informe de verificación '
      'intermedia: un control interno que la propia empresa ejecuta entre '
      'calibraciones formales, con la configuración que ella misma definió.'
      '\n'
      'No procede de un laboratorio acreditado, no es un certificado de '
      'calibración y no acredita que la balanza funcione correctamente. No '
      'sirve para demostrar conformidad ante IBMETRO ni ante ninguna otra '
      'autoridad metrológica, ni sustituye la verificación reglamentaria ni la '
      'calibración que esas instancias exijan.',
      color: _red,
      background: _paleRed,
    ),
    pw.SizedBox(height: 14),
    _statusSummary(verification),
    _section('Identificación de la balanza'),
    _detailGrid([
      (
        'Código Métrica',
        equipment['cod_metrica'] ??
            (equipment['origen'] == 'CLIENTE'
                ? 'Registrada por la empresa'
                : null),
      ),
      ('Código interno', equipment['cod_interno']),
      (
        'Instrumento',
        equipment['instrumento'] ?? equipment['tipo_instrumento'],
      ),
      ('Tipo de balanza', equipment['tipo_balanza']),
      ('Marca', equipment['marca']),
      ('Modelo', equipment['modelo']),
      ('Serie', equipment['serie']),
      ('Ubicación', equipment['ubicacion']),
      ('Clase', equipment['clase']),
      ('Plataforma', equipment['plataforma']),
    ]),
    if (ranges.isNotEmpty) ...[
      pw.SizedBox(height: 10),
      _subheading('Rangos metrológicos históricos'),
      _rangesTable(ranges),
    ],
    _section('Ejecución y condiciones'),
    _detailGrid([
      ('Fecha de medición', _date(verification['realizado_at'])),
      ('Fecha de recepción', _date(verification['recibido_at'])),
      ('Capturado por', users['capture']),
      ('Finalizado por', users['finalization']),
      ('Temperatura', _withUnit(verification['temperatura_c'], '°C')),
      (
        'Humedad relativa',
        _withUnit(verification['humedad_relativa_pct'], '%'),
      ),
      ('Plan', plan['name'] ?? plan['nombre']),
      ('Versión del plan', plan['version'] ?? plan['version_number']),
      ('Procedimiento', plan['procedure'] ?? plan['procedimiento']),
      ('Motor de evaluación', verification['motor_version']),
      ('Regla de decisión', verification['regla_decision_resumen']),
      ('Aplicación', verification['app_version']),
    ]),
    pw.SizedBox(height: 8),
    _labeledText('Observaciones generales', verification['observaciones']),
    if (full) ...[
      _section('Trazabilidad de los patrones'),
      if (patterns.isEmpty)
        _empty('No se registraron certificados de pesas patrón.')
      else
        _patternsTable(patterns),
    ],
    _section('Resumen de resultados'),
    _testsSummary(tests),
    if (!full) ...[
      pw.SizedBox(height: 12),
      _notice(
        'Informe resumido. El informe completo agrega las lecturas de cada '
        'prueba, el croquis de excentricidad, los gráficos y la trazabilidad '
        'de las pesas patrón. Está disponible en los planes superiores de IvMET.',
      ),
    ],
  ];

  if (full) {
    for (final test in tests) {
      widgets.add(pw.NewPage());
      widgets.addAll(_testSection(test, regularFont));
    }
  }

  widgets.addAll([
    pw.NewPage(),
    _section('Trazabilidad documental'),
    _detailGrid([
      ('Identificador de la verificación', verification['id']),
      ('Estado del registro', verification['estado']),
      (
        'Documento generado el',
        DateFormat("dd/MM/yyyy 'a las' HH:mm").format(generated.toLocal()),
      ),
      ('Documento generado por', generatedBy),
      ('Alcance declarado', verification['alcance_declaracion']),
    ]),
    if (verification['estado'] == 'ANNULLED') ...[
      pw.SizedBox(height: 8),
      _notice(
        'Registro anulado. Motivo: ${_value(verification['motivo_anulacion'])}',
        color: _red,
      ),
    ],
    pw.SizedBox(height: 12),
    pw.Text(
      'El informe fue generado a partir del registro histórico inmutable de la '
      'verificación. Los resultados, lecturas, tolerancias y snapshots '
      'corresponden al momento de la medición.',
      style: pw.TextStyle(fontSize: 9, color: _muted, lineSpacing: 2),
    ),
    _section('Propiedad de la información'),
    pw.Text(
      'Las mediciones de esta verificación —lecturas, condiciones ambientales y '
      'observaciones— fueron capturadas por el personal de la empresa titular '
      'de la balanza y le pertenecen. IvMET las conserva por cuenta de esa '
      'empresa y no las comparte con Métrica Ltda. salvo que su jefe de calidad '
      'lo autorice de forma expresa para un caso concreto.',
      style: pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2),
    ),
    pw.SizedBox(height: 6),
    pw.Text(
      'Los datos técnicos de referencia sobre los que se apoya la verificación '
      '—identificación de la balanza, rangos metrológicos, división de escala y '
      'los certificados de las pesas patrón— provienen del catálogo levantado '
      'por Métrica Ltda. en trabajos previos sobre este equipo, y su origen y '
      'trazabilidad corresponden a Métrica Ltda.',
      style: pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2),
    ),
  ]);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(34, 44, 34, 58),
      maxPages: 80,
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
        italic: italicFont,
      ),
      header: (context) => _pageHeader(context, equipment),
      footer: (context) => _pageFooter(
        context,
        reportId: reportId,
        equipmentCode: _value(
          equipment['cod_interno'] ?? equipment['cod_metrica'],
          fallback: 'sin código',
        ),
        generated: generated,
        measuredAt: verification['realizado_at'],
        generatedBy: generatedBy,
      ),
      build: (_) => widgets,
    ),
  );
  return document.save();
}

String _withUnit(Object? value, String unit) {
  final text = _value(value, fallback: 'No informado');
  return text == 'No informado' ? text : '${_decimal(text)} $unit';
}

/// Croquis de la plataforma con las posiciones de ensayo y donde queda el
/// indicador.
///
/// Reproduce el mismo dibujo que el operario vio al capturar. En un informe que
/// se lee meses despues, "Posicion 3" no dice nada por si sola: hace falta ver
/// donde se aplico la carga y desde donde se leia.
///
/// El lienzo del PDF tiene el origen abajo a la izquierda y la Y hacia arriba,
/// al reves que la pantalla: las posiciones se declaran medidas desde arriba,
/// como en la app, y se voltean al pintar.
pw.Widget _eccentricityDiagram(ReportJson setup) {
  const boxWidth = 250.0;
  const boxHeight = 176.0;
  final platform = _value(setup['platform'], fallback: 'square');
  final indicator = _value(setup['indicatorPosition'], fallback: 'front');
  final count = (setup['pointCount'] as num?)?.toInt() ?? 5;

  final rectangular = platform == 'rectangular';
  final width = rectangular ? 196.0 : 130.0;
  final height = rectangular ? 98.0 : 130.0;
  final left = (boxWidth - width) / 2;
  final top = (boxHeight - height) / 2;

  final positions = platform == 'triangular'
      ? const [(0.5, 0.53), (0.5, 0.30), (0.66, 0.66), (0.34, 0.66)]
      : count == 3
      ? const [(0.5, 0.5), (0.22, 0.5), (0.78, 0.5)]
      : count == 4
      ? const [(0.5, 0.5), (0.69, 0.31), (0.5, 0.77), (0.31, 0.31)]
      : const [
          (0.5, 0.5),
          (0.73, 0.27),
          (0.73, 0.73),
          (0.27, 0.73),
          (0.27, 0.27),
        ];

  return pw.SizedBox(
    width: boxWidth,
    height: boxHeight,
    child: pw.Stack(
      children: [
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (canvas, size) {
              final bottom = size.y - top - height;
              canvas
                ..setStrokeColor(_blue)
                ..setLineWidth(1.4);
              if (platform == 'circular') {
                canvas.drawEllipse(
                  left + width / 2,
                  bottom + height / 2,
                  width / 2,
                  height / 2,
                );
              } else if (platform == 'triangular') {
                canvas
                  ..moveTo(left + width / 2, bottom + height)
                  ..lineTo(left + width, bottom)
                  ..lineTo(left, bottom)
                  ..closePath();
              } else {
                canvas.drawRRect(left, bottom, width, height, 6, 6);
              }
              canvas.strokePath();

              // Donde se para quien lee la balanza.
              final horizontal = indicator == 'left' || indicator == 'right';
              final markerWidth = horizontal ? 6.0 : 34.0;
              final markerHeight = horizontal ? 34.0 : 6.0;
              final centerX = switch (indicator) {
                'left' => left - 11,
                'right' => left + width + 11,
                _ => left + width / 2,
              };
              final centerY = switch (indicator) {
                'back' => bottom + height + 11,
                'front' => bottom - 11,
                _ => bottom + height / 2,
              };
              canvas
                ..setFillColor(_navy)
                ..drawRRect(
                  centerX - markerWidth / 2,
                  centerY - markerHeight / 2,
                  markerWidth,
                  markerHeight,
                  2,
                  2,
                )
                ..fillPath();
            },
          ),
        ),
        for (var i = 0; i < positions.length; i++)
          pw.Positioned(
            left: left + positions[i].$1 * width - 10,
            top: top + positions[i].$2 * height - 10,
            child: pw.Container(
              width: 20,
              height: 20,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: i == 0 ? _navy : _paleBlue,
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: _blue, width: 0.8),
              ),
              child: pw.Text(
                '${i + 1}',
                style: pw.TextStyle(
                  color: i == 0 ? PdfColors.white : _navy,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _pageHeader(pw.Context context, ReportJson equipment) => pw.Column(
  children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'IvMET',
          style: pw.TextStyle(
            color: _navy,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Informe de verificación intermedia - ${_value(equipment['cod_interno'] ?? equipment['cod_metrica'])}',
          style: pw.TextStyle(color: _muted, fontSize: 8),
        ),
      ],
    ),
    pw.SizedBox(height: 5),
    pw.Divider(height: 1, color: _line),
  ],
);

/// Pie de pagina: lo que hay que saber si esta hoja se separa del resto.
///
/// Un informe impreso se fotocopia, se escanea suelto y se adjunta a un correo
/// por paginas. Cada una tiene que poder responder sola tres preguntas: que
/// vale este papel, de que verificacion sale y quien lo saco.
///
/// Por eso la advertencia legal se repite en todas y no solo en la portada:
/// una hoja intermedia, con su tabla de lecturas y su grafico, es justo la que
/// se puede confundir con un certificado.
pw.Widget _pageFooter(
  pw.Context context, {
  required String reportId,
  required String equipmentCode,
  required DateTime generated,
  required Object? measuredAt,
  String? generatedBy,
}) {
  final origin = [
    'Verificación $reportId',
    'Balanza $equipmentCode',
    'Medición ${_date(measuredAt, time: false)}',
    'Documento generado el '
        '${DateFormat("dd/MM/yyyy 'a las' HH:mm").format(generated.toLocal())}',
    if (generatedBy != null && generatedBy.trim().isNotEmpty)
      'por $generatedBy',
  ].join(' · ');

  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Divider(height: 1, color: _line),
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              'Sin validez legal. No es un certificado de calibración ni una '
              'verificación reglamentaria, y no acredita el funcionamiento de '
              'la balanza ante IBMETRO.',
              style: pw.TextStyle(color: _red, fontSize: 7, lineSpacing: 1),
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(color: _ink, fontSize: 7.5),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        origin,
        maxLines: 2,
        style: pw.TextStyle(color: _muted, fontSize: 6.5, lineSpacing: 1),
      ),
    ],
  );
}

pw.Widget _reportTitle(
  ReportJson verification,
  ReportJson equipment,
  String reportId,
) => pw.Container(
  padding: const pw.EdgeInsets.all(18),
  decoration: pw.BoxDecoration(
    color: _navy,
    borderRadius: pw.BorderRadius.circular(8),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'INFORME DE VERIFICACIÓN INTERMEDIA',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              _value(
                equipment['cod_interno'] ?? equipment['cod_metrica'],
                fallback: 'Balanza sin código',
              ),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Medición: ${_date(verification['realizado_at'])}',
              style: pw.TextStyle(color: _paleBlue, fontSize: 9),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _paleBlue, width: .6),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Text(
          reportId.length > 18 ? reportId.substring(0, 18) : reportId,
          style: pw.TextStyle(color: _paleBlue, fontSize: 7.5),
        ),
      ),
    ],
  ),
);

/// Aviso destacado: regla de color a la izquierda sobre un fondo palido.
///
/// El fondo se pasa entero y no como el color de la regla con alfa: el visor de
/// PDF no respeta la transparencia de un relleno y lo pintaba macizo, con lo
/// que un parrafo largo quedaba en texto oscuro sobre rojo saturado.
pw.Widget _notice(String text, {PdfColor? color, PdfColor? background}) {
  final ink = color ?? _blue;
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: background ?? (color == null ? _paleBlue : _paleAmber),
      border: pw.Border(left: pw.BorderSide(color: ink, width: 3)),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8.5, color: _ink, lineSpacing: 2),
    ),
  );
}

pw.Widget _statusSummary(ReportJson verification) {
  final status = verification['estado'] == 'ANNULLED' ? 'Anulada' : 'Activa';
  return pw.Row(
    children: [
      _statusBox(
        'Resultado',
        _verdict(verification['veredicto_global']),
        _verdictColor(verification['veredicto_global']),
      ),
      pw.SizedBox(width: 7),
      _statusBox(
        'Alcance',
        verification['alcance'] == 'partial' ? 'Parcial' : 'Completa',
        _navy,
      ),
      pw.SizedBox(width: 7),
      _statusBox(
        'Trazabilidad',
        verification['trazabilidad'] == 'traceable'
            ? 'Trazable'
            : 'No trazable',
        verification['trazabilidad'] == 'traceable' ? _green : _amber,
      ),
      pw.SizedBox(width: 7),
      _statusBox('Estado', status, status == 'Activa' ? _green : _red),
    ],
  );
}

pw.Widget _statusBox(String label, String value, PdfColor color) => pw.Expanded(
  child: pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: pw.BoxDecoration(
      color: _paper,
      border: pw.Border(bottom: pw.BorderSide(color: color, width: 2)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, color: _muted)),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  ),
);

pw.Widget _section(String title) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 18, bottom: 8),
  padding: const pw.EdgeInsets.only(bottom: 5),
  decoration: pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 1.2)),
  ),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      color: _navy,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    ),
  ),
);

pw.Widget _subheading(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      color: _navy,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    ),
  ),
);

pw.Widget _detailGrid(List<(String, Object?)> values) {
  final rows = <pw.TableRow>[];
  for (var index = 0; index < values.length; index += 2) {
    final left = values[index];
    final right = index + 1 < values.length ? values[index + 1] : ('', null);
    rows.add(
      pw.TableRow(
        children: [
          _detailCell(left.$1, left.$2),
          _detailCell(right.$1, right.$2),
        ],
      ),
    );
  }
  return pw.Table(
    border: pw.TableBorder.all(color: _line, width: .5),
    children: rows,
  );
}

pw.Widget _detailCell(String label, Object? value) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  child: label.isEmpty
      ? pw.SizedBox()
      : pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 6.8, color: _muted)),
            pw.SizedBox(height: 2),
            pw.Text(
              _value(value),
              style: pw.TextStyle(fontSize: 8.2, color: _ink),
            ),
          ],
        ),
);

pw.Widget _labeledText(String label, Object? value) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(8),
  decoration: pw.BoxDecoration(color: _paper),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7, color: _muted)),
      pw.SizedBox(height: 3),
      pw.Text(_value(value), style: pw.TextStyle(fontSize: 8.5, color: _ink)),
    ],
  ),
);

pw.Widget _rangesTable(List<ReportJson> ranges) => _table(
  headers: const [
    'Rango',
    'Capacidad máxima',
    'División d',
    'Intervalo e',
    'Decimales',
  ],
  rows: [
    for (final range in ranges)
      [
        _value(range['numero_rango']),
        '${_decimal(range['capacidad_max'])} ${_value(range['unidad'], fallback: '')}',
        _decimal(range['division_escala']),
        _decimal(range['intervalo_verificacion']),
        _value(range['cantidad_decimales'], fallback: '-'),
      ],
  ],
);

pw.Widget _patternsTable(List<ReportJson> rows) => _table(
  headers: const [
    'Patrón',
    'Certificado',
    'Laboratorio',
    'Calibración',
    'Vencimiento',
    'Vigente',
  ],
  rows: [
    for (final row in rows)
      () {
        final snapshot = _map(row['snapshot']);
        final pattern = _map(snapshot['pattern']);
        final certificate = _map(snapshot['certificate']);
        return [
          _value(
            pattern['codigo'] ?? pattern['code'] ?? pattern['descripcion'],
          ),
          _value(certificate['numero'] ?? certificate['number']),
          _value(certificate['laboratorio'] ?? certificate['laboratory']),
          _date(
            certificate['calibrado_el'] ?? certificate['calibratedOn'],
            time: false,
          ),
          _date(
            certificate['vence_el'] ?? certificate['expiresOn'],
            time: false,
          ),
          snapshot['validAtMeasurement'] == true ? 'Sí' : 'No',
        ];
      }(),
  ],
  fontSize: 6.8,
);

pw.Widget _testsSummary(List<ReportJson> tests) => _table(
  headers: const [
    'Prueba',
    'Ejecución',
    'Resultado',
    'Métrica',
    'Tolerancia',
    'Unidad',
  ],
  rows: [
    for (final test in tests)
      [
        _testName(test['tipo']),
        test['estado_ejecucion'] == 'omitted' ? 'Omitida' : 'Ejecutada',
        test['estado_ejecucion'] == 'omitted'
            ? _value(test['motivo_omision'])
            : _verdict(test['veredicto']),
        _decimal(test['valor_metrica']),
        _decimal(test['tolerancia']),
        _value(test['unidad'], fallback: '-'),
      ],
  ],
);

List<pw.Widget> _testSection(ReportJson test, pw.Font chartFont) {
  final omitted = test['estado_ejecucion'] == 'omitted';
  final readings = _maps(test['readings']);
  final unit = _value(test['unidad'], fallback: '');
  // Supabase guarda el montaje dentro de la evaluacion congelada, junto a la
  // version del motor; la fila de la prueba no lo trae suelto.
  final setup = _map(_map(test['evaluacion_snapshot'])['setup']);
  final result = <pw.Widget>[
    _section(_testName(test['tipo'])),
    if (omitted)
      _notice(
        'Prueba omitida. Motivo: ${_value(test['motivo_omision'])}',
        color: _amber,
      )
    else ...[
      _detailGrid([
        ('Resultado', _verdict(test['veredicto'])),
        ('Unidad', unit),
        ('Método', test['metodo_evaluacion']),
        ('Código del método', test['metodo_codigo']),
        ('Regla de decisión', test['regla_decision']),
        ('Fuente de tolerancia', test['fuente_tolerancia']),
        ('Tolerancia', _decimal(test['tolerancia'])),
        ('Métrica evaluada', _decimal(test['valor_metrica'])),
        ('Error máximo absoluto', _decimal(test['error_max_abs'])),
        ('Media', _decimal(test['media'])),
        ('Desviación estándar', _decimal(test['desviacion_estandar'])),
        ('Rango', _decimal(test['rango'])),
      ]),
      // El croquis solo aparece si el registro guarda como se monto la prueba.
      // Un expediente antiguo, anterior a la captura flexible, no lo trae: se
      // omite en vez de dibujar una plataforma inventada.
      if (test['tipo'] == 'eccentricity' && setup.isNotEmpty) ...[
        pw.SizedBox(height: 13),
        _subheading('Plataforma y posiciones de ensayo'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _eccentricityDiagram(setup),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _diagramFact(
                    'Forma de la plataforma',
                    _platformLabel(setup['platform']),
                  ),
                  _diagramFact(
                    'Posiciones de ensayo',
                    _value(setup['pointCount']),
                  ),
                  _diagramFact(
                    'Ubicación del indicador',
                    _indicatorLabel(setup['indicatorPosition']),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'La posición 1 es la referencia central. La barra marca '
                    'desde donde se lee el indicador.',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      color: _muted,
                      lineSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      if (readings.isNotEmpty) ...[
        pw.SizedBox(height: 13),
        _subheading(_chartTitle(test['tipo'])),
        _deviationChart(test, readings, chartFont),
        pw.SizedBox(height: 4),
        pw.Text(
          _chartCaption(test['tipo'], unit),
          style: pw.TextStyle(fontSize: 7, color: _muted),
        ),
        pw.SizedBox(height: 13),
        _subheading('Lecturas registradas'),
        _readingsTable(readings, unit),
      ] else
        _empty('No existen lecturas asociadas a esta prueba.'),
    ],
  ];
  return result;
}

/// Dato del croquis: rotulo pequeno encima del valor. En la columna estrecha
/// que acompana al dibujo, la rejilla de dos columnas del resto del informe
/// quedaria apretada.
pw.Widget _diagramFact(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 7),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(fontSize: 6.5, color: _muted, letterSpacing: .4),
      ),
      pw.SizedBox(height: 1),
      pw.Text(value, style: pw.TextStyle(fontSize: 9.5, color: _ink)),
    ],
  ),
);

String _platformLabel(Object? value) => switch (value?.toString()) {
  'square' => 'Cuadrada',
  'rectangular' => 'Rectangular',
  'circular' => 'Circular',
  'triangular' => 'Triangular',
  _ => _value(value),
};

String _indicatorLabel(Object? value) => switch (value?.toString()) {
  'front' => 'Al frente',
  'back' => 'Atrás',
  'left' => 'A la izquierda',
  'right' => 'A la derecha',
  _ => _value(value),
};

String _chartTitle(Object? type) => type == 'repeatability'
    ? 'Desviación de cada indicación respecto de la media'
    : 'Desviación de la indicación respecto de la carga';

String _chartCaption(Object? type, String unit) => type == 'repeatability'
    ? 'Eje vertical: indicación menos media ($unit). La conformidad se determina con la desviación estándar de la serie.'
    : 'Eje vertical: error de indicación ($unit). Las líneas rojas representan los límites de tolerancia de cada punto.';

pw.Widget _readingsTable(List<ReportJson> readings, String unit) => _table(
  headers: const [
    '#',
    'Punto',
    'Carga',
    'Indicación',
    'Ret. cero',
    'Error',
    'Tolerancia',
    'Resultado',
  ],
  rows: [
    for (final reading in readings)
      [
        _value(reading['orden']),
        _readingLabel(reading),
        _decimal(reading['carga_nominal']),
        _decimal(reading['indicacion']),
        _decimal(reading['retorno_cero']),
        _decimal(reading['error']),
        _decimal(reading['tolerancia']),
        _verdict(reading['veredicto']),
      ],
  ],
  fontSize: 6.4,
);

String _readingLabel(ReportJson reading) {
  final label = _value(reading['etiqueta'], fallback: 'Punto');
  final group = int.tryParse(reading['grupo']?.toString() ?? '') ?? 1;
  return group > 1 ? 'G$group - $label' : label;
}

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  double fontSize = 7.2,
}) => pw.TableHelper.fromTextArray(
  headers: headers,
  data: rows,
  border: pw.TableBorder.all(color: _line, width: .45),
  headerDecoration: pw.BoxDecoration(color: _navy),
  headerStyle: pw.TextStyle(
    color: PdfColors.white,
    fontSize: fontSize,
    fontWeight: pw.FontWeight.bold,
  ),
  cellStyle: pw.TextStyle(color: _ink, fontSize: fontSize),
  oddRowDecoration: pw.BoxDecoration(color: _paper),
  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
  cellAlignment: pw.Alignment.centerLeft,
  headerAlignment: pw.Alignment.centerLeft,
);

pw.Widget _empty(String text) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  color: _paper,
  child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _muted)),
);

pw.Widget _deviationChart(
  ReportJson test,
  List<ReportJson> readings,
  pw.Font chartFont,
) {
  final repeatability = test['tipo'] == 'repeatability';
  final mean = _number(test['media']);
  final values = <double>[];
  final tolerances = <double>[];
  for (final reading in readings) {
    final value = repeatability
        ? (_number(reading['indicacion']) != null && mean != null
              ? _number(reading['indicacion'])! - mean
              : 0.0)
        : _number(reading['error']) ?? 0.0;
    values.add(value);
    tolerances.add((_number(reading['tolerancia']) ?? 0).abs());
  }
  var extent = values.fold<double>(0, (max, item) => math.max(max, item.abs()));
  if (!repeatability) {
    extent = tolerances.fold<double>(
      extent,
      (max, item) => math.max(max, item),
    );
  }
  if (extent == 0) extent = 1;
  extent *= 1.18;
  return pw.Container(
    height: 185,
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: _line, width: .6),
    ),
    child: pw.SvgImage(
      svg: _chartSvg(values, tolerances, extent, showTolerance: !repeatability),
      fit: pw.BoxFit.fill,
      customFontLookup: (_, _, _) => chartFont,
    ),
  );
}

String _chartSvg(
  List<double> values,
  List<double> tolerances,
  double extent, {
  required bool showTolerance,
}) {
  const width = 720.0, height = 250.0;
  const left = 74.0, right = 18.0, top = 18.0, bottom = 48.0;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  double x(int index) => values.length <= 1
      ? left + plotWidth / 2
      : left + plotWidth * index / (values.length - 1);
  double y(double value) => top + (extent - value) * plotHeight / (extent * 2);
  String n(double value) {
    final abs = value.abs();
    final digits = abs >= 10
        ? 1
        : abs >= 1
        ? 2
        : abs >= .01
        ? 3
        : 6;
    return value
        .toStringAsFixed(digits)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  final buffer = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">',
  );
  buffer.write(
    '<rect x="$left" y="$top" width="$plotWidth" height="$plotHeight" fill="#F7F9FA" stroke="#D8E1E6"/>',
  );
  for (final tick in [-extent, -extent / 2, 0.0, extent / 2, extent]) {
    final py = y(tick);
    buffer.write(
      '<line x1="$left" y1="$py" x2="${left + plotWidth}" y2="$py" stroke="${tick == 0 ? '#667782' : '#D8E1E6'}" stroke-width="${tick == 0 ? 1.4 : .7}"/>',
    );
    buffer.write(
      '<text x="${left - 8}" y="${py + 3}" text-anchor="end" font-family="Helvetica" font-size="10" fill="#667782">${n(tick)}</text>',
    );
  }
  if (showTolerance && tolerances.length == values.length) {
    for (final sign in [-1.0, 1.0]) {
      final points = [
        for (var index = 0; index < tolerances.length; index++)
          '${x(index)},${y(tolerances[index] * sign)}',
      ].join(' ');
      buffer.write(
        '<polyline points="$points" fill="none" stroke="#B53A3A" stroke-width="1.3" stroke-dasharray="5,4"/>',
      );
    }
  }
  final valuePoints = [
    for (var index = 0; index < values.length; index++)
      '${x(index)},${y(values[index])}',
  ].join(' ');
  buffer.write(
    '<polyline points="$valuePoints" fill="none" stroke="#247BA0" stroke-width="2.2"/>',
  );
  for (var index = 0; index < values.length; index++) {
    final outside = showTolerance && values[index].abs() > tolerances[index];
    buffer.write(
      '<circle cx="${x(index)}" cy="${y(values[index])}" r="4" fill="${outside ? '#B53A3A' : '#247BA0'}"/>',
    );
    buffer.write(
      '<text x="${x(index)}" y="${top + plotHeight + 18}" text-anchor="middle" font-family="Helvetica" font-size="9" fill="#667782">${index + 1}</text>',
    );
  }
  buffer.write(
    '<text x="${left + plotWidth / 2}" y="${height - 5}" text-anchor="middle" font-family="Helvetica" font-size="10" fill="#667782">Lectura</text>',
  );
  buffer.write('</svg>');
  return buffer.toString();
}
