import 'package:flutter/material.dart';
import 'customer_form.dart';
import 'equipment_registration.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Validacion de la ficha de una balanza y su envio a Metrica.
///
/// Son los dos formularios que abre el catalogo sobre un equipo concreto, mas
/// la vista de lo que se autoriza a compartir.

class EquipmentValidation extends StatelessWidget {
  const EquipmentValidation({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Validar ficha de la balanza',
    load: () => customerRead(session, 'equipment', {'id': equipmentId}),
    builder: (bundle) {
      final master = object(bundle['master']),
          existing = bundle['customer'] == null
              ? <String, dynamic>{}
              : object(bundle['customer']);
      final effective = {...master, ...object(existing['datos'] ?? {})};
      return CustomerForm(
        session: session,
        title: 'Validar ficha de la balanza',
        action: 'equipment.validate',
        notice:
            'Comprueba los datos del catálogo. Las capacidades y divisiones se conservan como datos técnicos de DataMET. Tus correcciones quedan privadas hasta que el jefe de calidad autorice compartirlas.',
        preview: Notice(
          'Ubicación del catálogo: ${valueLabel(master['ubicacion'])}. Si hay una coincidencia, sugerimos el área existente. También puedes confirmar un nombre nuevo.',
        ),
        initial: {
          'id': equipmentId,
          'catalogHash': master['source_hash'],
          'version': existing['row_version'] ?? '0',
          for (final key in [
            'ubicacion',
            'cod_interno',
            'marca',
            'modelo',
            'serie',
          ])
            key: effective[key] ?? '',
          'areaId': bundle['areaId'] ?? bundle['suggestedAreaId'] ?? '',
          'areaName':
              bundle['areaId'] == null && bundle['suggestedAreaId'] == null
              ? bundle['suggestedArea'] ?? ''
              : '',
          'confirmed': false,
        },
        fields: [
          const CustomerField('ubicacion', 'Ubicación actual', required: false),
          const CustomerField('cod_interno', 'Código interno', required: false),
          const CustomerField('marca', 'Marca', required: false),
          const CustomerField('modelo', 'Modelo', required: false),
          const CustomerField('serie', 'Serie', required: false),
          CustomerField(
            'areaId',
            'Área de esta planta',
            kind: 'select',
            required: false,
            options: {
              '': 'Sin área',
              for (final a in objects(bundle['areas']))
                a['id'] as String: a['name'] as String,
            },
          ),
          const CustomerField(
            'areaName',
            'Nombre de área nueva (reemplaza la selección)',
            required: false,
          ),
          const CustomerField(
            'confirmed',
            'He revisado la información de esta balanza',
            kind: 'bool',
          ),
        ],
        payload: (v) => {
          'id': equipmentId,
          'catalogHash': master['source_hash'],
          'version': existing['row_version'] ?? '0',
          'areaId': (v['areaName'] as String? ?? '').trim().isEmpty
              ? v['areaId']
              : '',
          'areaName': v['areaName'] ?? '',
          'data': {
            for (final key in [
              'ubicacion',
              'cod_interno',
              'marca',
              'modelo',
              'serie',
            ])
              key: v[key],
          },
        },
        submitLabel: 'Guardar validación privada',
      );
    },
  );
}

class EquipmentUpdatePreview extends StatelessWidget {
  const EquipmentUpdatePreview({required this.snapshot, super.key});
  final Json snapshot;
  @override
  Widget build(BuildContext context) => snapshot['kind'] == 'registration'
      ? EquipmentRegistrationPreview(snapshot: snapshot)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailField(
              'Balanza / planta',
              '${snapshot['code']} · ${snapshot['plantCode']}',
            ),
            for (final field in const {
              'ubicacion': 'Ubicación',
              'cod_interno': 'Código interno',
              'marca': 'Marca',
              'modelo': 'Modelo',
              'serie': 'Serie',
            }.entries)
              DetailField(
                field.value,
                '${valueLabel(object(snapshot['catalog'])[field.key])} → ${valueLabel(object(snapshot['customer'])[field.key])}',
              ),
            DetailField('Área confirmada', snapshot['area']),
          ],
        );
}

class ShareEquipmentUpdate extends StatelessWidget {
  const ShareEquipmentUpdate({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Compartir actualización con Métrica',
    load: () => customerRead(session, 'share-preview', {'id': equipmentId}),
    builder: (preview) => CustomerForm(
      session: session,
      title: 'Compartir actualización con Métrica',
      action: 'update.share',
      notice: preview['notice'] as String,
      preview: EquipmentUpdatePreview(snapshot: object(preview['snapshot'])),
      initial: {
        'id': equipmentId,
        'hash': preview['hash'],
        'consentVersion': preview['consentVersion'],
        'consent': false,
      },
      fields: const [
        CustomerField('message', 'Mensaje para Métrica', max: 2000),
        CustomerField(
          'consent',
          'Autorizo enviar únicamente la información mostrada para preparar próximas calibraciones.',
          kind: 'bool',
        ),
      ],
      submitLabel: 'Autorizar y enviar actualización',
    ),
  );
}
