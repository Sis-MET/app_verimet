import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tile_grid.dart';
import 'customer_configuration.dart';
import 'draft_screen.dart';
import 'equipment_check_configuration.dart';
import 'equipment_registration.dart';
import 'equipment_validation.dart';
import 'history_screen.dart';
import 'measurement_suggestions.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Ficha de una balanza: sus datos, su plan de verificacion y la vigencia de
/// cada prueba.
///
/// Es el segundo nivel del catalogo y desde aqui arrancan la captura, el
/// historial y la configuracion del equipo. Vivia dentro de
/// `catalog_screen.dart`, que asi juntaba dos pantallas distintas en el mismo
/// archivo.

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  int revision = 0;
  MobileSession get session => widget.session;
  String get equipmentId => widget.equipmentId;
  Future<void> configure(Widget page) async {
    await openPage(context, page);
    if (mounted) setState(() => revision++);
  }

  /// Tras la baja la balanza ya no es accesible: la ficha se cierra.
  Future<void> retire(Json equipment) async {
    final retired = await openPage<bool>(
      context,
      RetireRegisteredEquipment(session: session, equipment: equipment),
    );
    if (!mounted) return;
    if (retired == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => revision++);
    }
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Ficha de la balanza',
    child: RemotePanel(
      dataKey: '$revision',
      load: () => session.api.read('equipment', {'equipmentId': equipmentId}),
      builder: (data) {
        final palette = IndustryPalette.of(context);
        final equipment = object(data['equipment']);
        final plan = data['plan'] == null ? null : object(data['plan']);
        final ranges = objects(data['ranges']);
        final validated = data['customerValidated'] == true;
        final sharePending = data['customerUpdatePending'] == true;
        final canStart = validated && plan?['finalizationEnabled'] == true;
        final registered = data['registeredByCustomer'] == true;
        final registrationShared = data['registrationShared'] == true;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Kicker('Código interno de la empresa'),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    customerEquipmentCode(equipment),
                    style: AppTextStyles.figure(context, size: 32),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: StatusTag(
                    registered
                        ? registeredEquipmentLabel
                        : validated
                        ? 'Ficha validada'
                        : 'Sin validar',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!registered)
                    DetailField('Código Métrica', equipment['cod_metrica']),
                  DetailField(
                    'Marca y modelo',
                    '${valueLabel(equipment['marca'])} · ${valueLabel(equipment['modelo'])}',
                  ),
                  DetailField('Serie', equipment['serie']),
                  DetailField('Ubicación', equipment['ubicacion']),
                  if (registered) ...[
                    DetailField('Tipo', equipment['tipo_balanza']),
                    DetailField('Clase', equipment['clase']),
                  ],
                  for (final range in ranges)
                    DetailField(
                      'Rango ${range['numero_rango']}',
                      registered
                          ? registeredRangeLabel({
                              'capacity': range['capacidad_max'],
                              'division': range['division_escala'],
                              'interval': range['intervalo_verificacion'],
                            }, valueLabel(range['unidad']))
                          : '${rangeCapacityLabel(range)} ${range['unidad']}'
                                ' · división ${rangeDivisionLabel(range)} ${range['unidad']}',
                    ),
                ],
              ),
            ),
            const SectionLabel('Verificación'),
            TileGrid(
              cells: [
                TileCell.wide(
                  ActionTile(
                    icon: Icons.play_arrow,
                    label: 'Iniciar verificación',
                    caption: canStart
                        ? 'Capturar lecturas con la configuración activa'
                        : validated
                        ? 'La configuración todavía no habilita el cálculo de resultados'
                        : 'Valida antes la ficha de la balanza',
                    primary: canStart,
                    onTap: canStart
                        ? () => openPage(
                            context,
                            DraftScreen(session: session, bundle: data),
                          )
                        : null,
                  ),
                ),
                // La ficha de una balanza registrada nace validada: no hay
                // catálogo contra el que revisarla, se corrige al editarla.
                if (!registered)
                  TileCell(
                    ActionTile(
                      icon: Icons.fact_check_outlined,
                      label: validated ? 'Revisar ficha' : 'Validar ficha',
                      caption: validated
                          ? 'Corrige datos privados del equipo'
                          : 'Confirma los datos antes de capturar',
                      onTap: () => configure(
                        EquipmentValidation(
                          session: session,
                          equipmentId: equipmentId,
                        ),
                      ),
                    ),
                  ),
                if (registered && session.quality)
                  TileCell(
                    ActionTile(
                      icon: Icons.edit_outlined,
                      label: 'Editar balanza',
                      caption: data['registrationInUse'] == true
                          ? 'Identificación y área'
                          : 'Datos, área y rangos',
                      onTap: () => configure(
                        EquipmentRegistrationScreen.edit(
                          session: session,
                          equipmentId: equipmentId,
                        ),
                      ),
                    ),
                  ),
                if (session.quality)
                  TileCell(
                    ActionTile(
                      icon: Icons.tune_outlined,
                      label: plan == null
                          ? 'Configurar pruebas'
                          : 'Actualizar pruebas',
                      caption: ranges.isEmpty
                          ? 'Falta capacidad y división'
                          : validated
                          ? 'Puntos, tolerancias y frecuencia'
                          : 'Valida la ficha primero',
                      onTap: validated && ranges.isNotEmpty
                          ? () => configure(
                              EquipmentCheckConfigurationScreen(
                                session: session,
                                bundle: data,
                              ),
                            )
                          : null,
                    ),
                  ),
                TileCell(
                  ActionTile(
                    icon: Icons.history,
                    label: 'Historial',
                    caption: 'Resultados privados del equipo',
                    onTap: () => openPage(
                      context,
                      HistoryScreen(session: session, equipmentId: equipmentId),
                    ),
                  ),
                ),
                TileCell(
                  ActionTile(
                    icon: Icons.edit_note,
                    label: 'Borradores',
                    caption: 'Capturas sin finalizar',
                    onTap: () => openPage(
                      context,
                      HistoryScreen(
                        session: session,
                        equipmentId: equipmentId,
                        drafts: true,
                      ),
                    ),
                  ),
                ),
                if (session.quality && sharePending && !registered)
                  TileCell(
                    ActionTile(
                      icon: Icons.share_outlined,
                      label: 'Compartir con Métrica',
                      caption: 'Enviar la corrección de la ficha',
                      onTap: () => configure(
                        ShareEquipmentUpdate(
                          session: session,
                          equipmentId: equipmentId,
                        ),
                      ),
                    ),
                  ),
                if (session.quality &&
                    registered &&
                    data['registrationSharePending'] == true)
                  TileCell(
                    ActionTile(
                      icon: Icons.send_outlined,
                      label: 'Enviar a Métrica',
                      caption: registrationShared
                          ? 'Autoriza enviar los datos actualizados'
                          : 'Autoriza compartir los datos de esta balanza',
                      onTap: () => configure(
                        ShareEquipmentRegistration(
                          session: session,
                          equipmentId: equipmentId,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (registered) ...[
              Notice(
                registrationShared
                    ? 'Balanza registrada por tu empresa. Métrica recibió sus datos con tu autorización.'
                    : 'Balanza registrada por tu empresa. Es privada: Métrica no la ve salvo que el jefe de calidad autorice enviarla.',
                icon: Icons.shield_outlined,
              ),
              if (session.quality && registrationShared)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => configure(
                      CustomerSetupScreen(
                        session: session,
                        initialSection: 'updates',
                        equipmentId: equipmentId,
                      ),
                    ),
                    child: const Text('Ver envíos a Métrica'),
                  ),
                ),
            ],
            if (session.quality && ranges.isEmpty)
              const Notice(
                'Faltan la capacidad y la división de escala. Solicita a Métrica revisar el catálogo antes de configurar las verificaciones.',
                icon: Icons.warning_amber_outlined,
                alert: true,
              ),
            if (plan == null)
              Notice(
                !session.quality
                    ? 'El jefe de calidad todavía no configuró las verificaciones de esta balanza.'
                    : registered
                    ? 'Configura las verificaciones de esta balanza.'
                    : 'Valida primero la ficha y configura las verificaciones de esta balanza.',
              )
            else ...[
              const SectionLabel('Verificaciones activas'),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final test in objects(plan['tests']))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              testLabel(test['type']),
                              style: AppTextStyles.figure(context, size: 17),
                            ),
                            Text(
                              'Cada ${test['frequencyDays']} días · ${objects(test['points']).length} puntos · ${test['unit']}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (objects(data['schedule']).isNotEmpty) ...[
                const SectionLabel('Vigencia por prueba'),
                SurfaceList(
                  children: [
                    for (final due in objects(data['schedule']))
                      _ScheduleRow(due: due),
                  ],
                ),
              ],
              const Notice(
                'Control interno privado. IvMET recalcula el resultado en Supabase al finalizar y deriva el próximo vencimiento de cada prueba trazable.',
              ),
            ],
            // Acción destructiva y poco frecuente: un enlace al pie, no un
            // módulo más del mosaico.
            if (registered && session.quality)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: palette.fail),
                    onPressed: () => retire(equipment),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Dar de baja esta balanza'),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Fila de vigencia: la prueba, cuando vence y con que urgencia.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.due});
  final Json due;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final overdue = due['state'] == 'OVERDUE';
    final soon = due['state'] == 'DUE_SOON';
    final color = overdue
        ? palette.fail
        : soon
        ? palette.accentInk
        : palette.muted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Icon(
            overdue
                ? Icons.error_outline
                : soon
                ? Icons.schedule
                : Icons.check_circle_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  testLabel(due['type']),
                  style: AppTextStyles.figure(context, size: 16),
                ),
                Text(
                  'Próxima: ${dateLabel(due['dueAt'])}'
                  '${due['lastTraceableAt'] == null ? ' · sin ejecución trazable previa' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
