import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/domain/compliance_status.dart';
import 'package:ivmet/core/domain/test_verdict.dart';
import 'package:ivmet/features/online/online_widgets.dart';
import 'package:ivmet/shared/widgets/app_shell.dart';
import 'package:ivmet/shared/widgets/labeled_field.dart';
import 'package:ivmet/shared/widgets/section_label.dart';
import 'package:ivmet/shared/widgets/segmented_pills.dart';
import 'package:ivmet/shared/widgets/status_tag.dart';
import 'package:ivmet/shared/widgets/surface_card.dart';
import 'package:ivmet/shared/widgets/tile_grid.dart';

import 'golden_harness.dart';

/// Fotografias del sistema visual.
///
/// No comprueban comportamiento —de eso se ocupa `test/online/`— sino como se
/// ve cada pieza. Existen porque el sistema se rompio dos veces por cambios
/// puramente esteticos que ningun test veia: un modulo que desbordaba y unos
/// apartados plegables que quedaban pegados.
///
/// Un desbordamiento ademas hace fallar el test aunque la imagen no se mire:
/// `RenderFlex overflowed` levanta una excepcion que `testWidgets` recoge.
///
/// Cuando un cambio de diseno sea intencionado, regenerar con
/// `flutter test --update-goldens` y revisar el diff de las imagenes antes de
/// comitearlas.
void main() {
  testWidgets('modulos del mosaico', (tester) async {
    await expectSpecimen(
      tester,
      name: 'modulos',
      size: const Size(400, 620),
      child: TileGrid(
        cells: [
          TileCell(
            ActionTile(
              icon: Icons.play_arrow_rounded,
              label: 'Nueva\nverificación',
              caption: 'Excentricidad, repetibilidad y linealidad',
              primary: true,
              onTap: () {},
            ),
          ),
          const TileCell(
            MetricTile(label: 'Balanzas', value: '48', caption: 'en 4 áreas'),
          ),
          TileCell(
            ActionTile(
              icon: Icons.inventory_2_outlined,
              label: 'Catálogo',
              caption: '48 balanzas',
              onTap: () {},
              // Etiqueta larga a proposito: con el chip del icono delante,
              // este es el caso que desbordaba el modulo.
              badge: const StatusTag('3 por sincronizar'),
            ),
          ),
          const TileCell(
            ActionTile(
              icon: Icons.history,
              label: 'Histórico',
              caption: 'Sin conexión',
            ),
          ),
        ],
      ),
    );
  });

  testWidgets('superficies y listas agrupadas', (tester) async {
    await expectSpecimen(
      tester,
      name: 'superficies',
      size: const Size(400, 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            cells: const [
              StatCell(value: '41', label: 'Conformes'),
              StatCell(value: '5', label: 'Observados'),
              StatCell(value: '2', label: 'No conf.'),
            ],
          ),
          const SectionLabel('Equipos del área'),
          SurfaceList(
            children: [
              for (final row in const <(String, String, ComplianceStatus)>[
                ('BAL-014', '600 kg · d = 0,1 kg', ComplianceStatus.conforme),
                ('BAL-027', '220 g · d = 0,0001 g', ComplianceStatus.observado),
                (
                  'BAL-031',
                  '1500 kg · d = 0,5 kg',
                  ComplianceStatus.noConforme,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.$1)),
                      Expanded(flex: 2, child: Text(row.$2)),
                      StatusTag.of(row.$3),
                    ],
                  ),
                ),
            ],
          ),
          const SectionLabel('Tarjeta suelta'),
          const SurfaceCard(
            elevated: true,
            child: Text('Una tarjeta despegada del fondo por su sombra.'),
          ),
        ],
      ),
    );
  });

  testWidgets('indicadores y avisos', (tester) async {
    await expectSpecimen(
      tester,
      name: 'indicadores',
      size: const Size(400, 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Kicker('EMBOL S.A. · PLANTA COCHABAMBA'),
          const SectionLabel('Etiquetas de estado'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusTag.of(ComplianceStatus.conforme),
              StatusTag.of(ComplianceStatus.observado),
              StatusTag.of(ComplianceStatus.noConforme),
              const StatusTag('3 por sincronizar'),
            ],
          ),
          const SectionLabel('Veredictos'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VerdictBadge(verdict: TestVerdict.pass),
              VerdictBadge(verdict: TestVerdict.fail),
              VerdictBadge(verdict: TestVerdict.pending),
            ],
          ),
          const SectionLabel('Avisos'),
          const Notice(
            'Control interno privado. IvMET recalcula el resultado en Supabase al finalizar.',
          ),
          const Notice(
            'Falta seleccionar un área antes de guardar.',
            icon: Icons.error_outline,
            alert: true,
          ),
        ],
      ),
    );
  });

  testWidgets('formulario', (tester) async {
    await expectSpecimen(
      tester,
      name: 'formulario',
      size: const Size(400, 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledInput(
            label: 'Área',
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(initialValue: 'LABORATORIO LÍNEA 4'),
          ),
          LabeledInput(
            label: 'Marca',
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              initialValue: 'ohaus',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'ohaus', child: Text('OHAUS')),
              ],
              onChanged: (_) {},
            ),
          ),
          LabeledInput(
            label: 'Error permisible (kg)',
            padding: const EdgeInsets.only(bottom: 20),
            child: TextFormField(
              initialValue: '0,05',
              decoration: const InputDecoration(
                helperText: 'Se aplicará a todos los puntos de esta prueba.',
              ),
            ),
          ),
          FilledButton(onPressed: () {}, child: const Text('Guardar')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () {}, child: const Text('Descartar')),
          TextButton(onPressed: () {}, child: const Text('Ver expediente')),
        ],
      ),
    );
  });

  testWidgets('selector de vista', (tester) async {
    await expectSpecimen(
      tester,
      name: 'selector',
      size: const Size(400, 100),
      child: Align(
        alignment: Alignment.center,
        child: SegmentedPills<int>(
          selected: 0,
          onSelect: (_) {},
          segments: const [
            PillSegment(0, 'Por planta'),
            PillSegment(1, 'Lista completa'),
          ],
        ),
      ),
    );
  });

  testWidgets('barra de navegación', (tester) async {
    await expectSpecimen(
      tester,
      name: 'navegacion',
      size: const Size(400, 120),
      child: Align(
        alignment: Alignment.center,
        child: FloatingNavBar(current: AppSection.inicio, onSelect: (_) {}),
      ),
    );
  });
}
