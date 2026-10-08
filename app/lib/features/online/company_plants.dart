import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/wizard_chrome.dart';
import 'commercial_plan.dart';
import 'customer_form.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'plan_screen.dart';

/// El jefe de calidad de una empresa autoregistrada gestiona sus plantas aquí.
/// En las empresas que incorporó Métrica, las plantas vienen de DataMET.
bool managesPlants(MobileSession session) =>
    session.quality && session.plan.selfService;

const _plantFields = [
  CustomerField('name', 'Nombre de la planta', max: 100),
  CustomerField('city', 'Ciudad', required: false, max: 100),
  CustomerField('address', 'Dirección', required: false, max: 250),
];

/// Nueva planta, si el plan admite otra. Quien la crea queda asignado a ella.
Future<void> createPlant(BuildContext context, MobileSession session) async {
  if (session.plan.full(PlanResource.plants)) {
    await showPlanLimit(
      context,
      session,
      const PlanLimit(resource: PlanResource.plants),
    );
    return;
  }
  final saved = await openPage<bool>(
    context,
    CustomerForm(
      session: session,
      title: 'Nueva planta',
      action: 'plant.save',
      submitLabel: 'Crear planta',
      notice:
          'Quedas asignado a esta planta. Asigna a tu equipo desde Ajustes › Usuarios.',
      initial: const {'name': '', 'city': '', 'address': '', 'active': true},
      fields: _plantFields,
    ),
  );
  // La planta nueva aparece en las listas cuando vuelve el bootstrap.
  if (saved == true) await session.refresh();
}

/// Editar o desactivar una planta. Lee su versión y sus datos antes de abrir
/// el formulario: el bootstrap solo trae nombre y código.
Future<bool> editPlant(
  BuildContext context,
  MobileSession session,
  String plantId,
) async {
  Json? plant;
  try {
    plant = objects(
      (await customerRead(session, 'plants'))['items'],
    ).where((item) => item['id'] == plantId).firstOrNull;
  } on MobileFailure catch (failure) {
    if (context.mounted) showWizardMessage(context, failure.message);
    return false;
  }
  if (plant == null || !context.mounted) return false;
  final equipment = (plant['equipmentCount'] as num? ?? 0).toInt();
  final saved = await openPage<bool>(
    context,
    CustomerForm(
      session: session,
      title: 'Editar planta',
      action: 'plant.save',
      notice: equipment > 0
          ? 'Tiene $equipment ${equipment == 1 ? 'balanza activa' : 'balanzas activas'}: para desactivarla, dalas de baja antes.'
          : 'Desactivarla la quita de las listas y libera su lugar en tu plan. Su historial se conserva.',
      initial: {
        'id': plant['id'],
        'version': plant['version'],
        'name': plant['name'] ?? '',
        'city': plant['city'] ?? '',
        'address': plant['address'] ?? '',
        'active': true,
      },
      fields: [
        ..._plantFields,
        const CustomerField(
          'active',
          'Planta activa',
          kind: 'bool',
          required: false,
        ),
      ],
    ),
  );
  if (saved == true) unawaited(session.refresh());
  return saved == true;
}
