import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'commercial_plan.dart';
import 'customer_form.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'plan_screen.dart';

const _roles = {
  'cliente_operador': 'Operador',
  'cliente_jefe_calidad': 'Jefe de calidad',
};

/// Contraseña temporal legible para dictar o copiar: sin letras que se
/// confunden (0/O, 1/l/I).
String temporaryPassword([Random? random]) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final source = random ?? Random.secure();
  String block() =>
      List.generate(4, (_) => alphabet[source.nextInt(alphabet.length)]).join();
  return 'Iv-${block()}-${block()}-${block()}';
}

/// Usuarios de una empresa que se registró desde la app. El jefe de calidad
/// los crea dentro de los cupos de su plan, les asigna plantas y les pone una
/// contraseña temporal. En las empresas que incorporó Métrica esto se hace en
/// RimMET.
class CompanyUsersScreen extends StatefulWidget {
  const CompanyUsersScreen({required this.session, super.key});
  final MobileSession session;
  @override
  State<CompanyUsersScreen> createState() => _CompanyUsersScreenState();
}

class _CompanyUsersScreenState extends State<CompanyUsersScreen> {
  int revision = 0;
  MobileSession get session => widget.session;

  Map<String, String> _plants(Json data) => {
    for (final plant in objects(data['plants']))
      plant['id'] as String: valueLabel(plant['name']),
  };

  Future<void> _afterChange(bool? saved) async {
    if (saved == true) unawaited(session.refresh());
    if (mounted) setState(() => revision++);
  }

  Future<void> _create(Json data) async {
    final seats = (data['seats'] as num? ?? 0).toInt();
    final used = (data['used'] as num? ?? 0).toInt();
    if (used >= seats) {
      await showPlanLimit(
        context,
        session,
        const PlanLimit(resource: PlanResource.users),
      );
      return;
    }
    final plants = _plants(data);
    Json? sent;
    final saved = await openPage<bool>(
      context,
      CustomerForm(
        session: session,
        title: 'Nuevo usuario',
        action: 'team.create',
        submitLabel: 'Crear usuario',
        notice:
            'La persona entra con este usuario y la contraseña temporal, y la cambia en su primer acceso. El usuario es único en IvMET: agrégale algo de tu empresa, como jperez.acme. Usa un cupo de tu plan.',
        initial: {
          'name': '',
          'username': '',
          'role': 'cliente_operador',
          'plantIds': plants.length == 1 ? [plants.keys.first] : <String>[],
          'password': temporaryPassword(),
        },
        fields: [
          const CustomerField('name', 'Nombre y apellido', min: 2, max: 200),
          const CustomerField(
            'username',
            'Usuario para ingresar',
            min: 3,
            max: 50,
          ),
          const CustomerField('role', 'Rol', kind: 'select', options: _roles),
          CustomerField(
            'plantIds',
            'Plantas donde trabaja',
            kind: 'multi',
            options: plants,
          ),
          const CustomerField(
            'password',
            'Contraseña temporal',
            min: 12,
            max: 200,
          ),
        ],
        send: (payload, requestId) async {
          final result = await session.api.teamAccount({
            'action': 'create',
            'requestId': requestId,
            'name': payload['name'],
            'username': (payload['username'] as String).trim().toLowerCase(),
            'role': payload['role'],
            'plantIds': payload['plantIds'],
            'password': payload['password'],
          });
          sent = payload;
          return result;
        },
      ),
    );
    if (saved == true && sent != null && mounted) {
      await _showCredentials(
        (sent!['username'] as String).trim().toLowerCase(),
        sent!['password'] as String,
      );
    }
    await _afterChange(saved);
  }

  Future<void> _edit(Json member, Json data) async {
    final self = member['self'] == true;
    final saved = await openPage<bool>(
      context,
      CustomerForm(
        session: session,
        title: 'Editar usuario',
        action: 'member.update',
        notice: self
            ? 'Es tu cuenta: puedes cambiar tu nombre y tus plantas. Tu rol y tu acceso no se cambian desde aquí.'
            : 'Desactivar una cuenta libera su cupo y conserva su historial. Para volver a activarla hace falta un cupo libre.',
        initial: {
          'id': member['id'],
          'version': member['version'],
          'name': member['name'] ?? '',
          'role': member['role'],
          'plantIds': List<String>.from(member['plantIds'] as List? ?? []),
          'active': member['active'] == true,
          'reason': '',
        },
        fields: [
          const CustomerField('name', 'Nombre y apellido', min: 2, max: 200),
          if (!self)
            const CustomerField('role', 'Rol', kind: 'select', options: _roles),
          CustomerField(
            'plantIds',
            'Plantas donde trabaja',
            kind: 'multi',
            options: _plants(data),
          ),
          if (!self) ...[
            const CustomerField(
              'active',
              'Cuenta activa',
              kind: 'bool',
              required: false,
            ),
            const CustomerField(
              'reason',
              'Motivo, si la desactivas',
              required: false,
              max: 500,
            ),
          ],
        ],
      ),
    );
    await _afterChange(saved);
  }

  Future<void> _reset(Json member) async {
    Json? sent;
    final saved = await openPage<bool>(
      context,
      CustomerForm(
        session: session,
        title: 'Contraseña temporal',
        action: 'team.reset',
        submitLabel: 'Guardar contraseña',
        notice:
            '${valueLabel(member['name'])} deberá cambiarla en su próximo acceso. La anterior deja de servir.',
        initial: {'password': temporaryPassword()},
        fields: const [
          CustomerField('password', 'Contraseña temporal', min: 12, max: 200),
        ],
        send: (payload, requestId) async {
          final result = await session.api.teamAccount({
            'action': 'reset',
            'requestId': requestId,
            'userId': member['id'],
            'password': payload['password'],
          });
          sent = payload;
          return result;
        },
      ),
    );
    if (saved == true && sent != null && mounted) {
      await _showCredentials(
        member['username'] as String,
        sent!['password'] as String,
      );
    }
    await _afterChange(saved);
  }

  /// Los datos que el jefe entrega a la persona. Solo se ven aquí: la app no
  /// los guarda.
  Future<void> _showCredentials(
    String username,
    String password,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Entrega estos datos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailField('Usuario', username),
          DetailField('Contraseña temporal', password),
          const SizedBox(height: 12),
          const Text(
            'Compártelos por un canal privado. La app no los vuelve a mostrar.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: 'Usuario: $username\nContraseña temporal: $password',
            ),
          ),
          child: const Text('Copiar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => RemotePage(
    title: 'Usuarios',
    dataKey: '$revision',
    load: () => customerRead(session, 'members'),
    floating: (data) => WizardNavPill.action(
      key: const ValueKey('users-create'),
      label: 'Nuevo usuario',
      icon: Icons.person_add_alt_1_outlined,
      onNext: () => _create(data),
    ),
    builder: (data) {
      final palette = IndustryPalette.of(context);
      final seats = (data['seats'] as num? ?? 0).toInt();
      final used = (data['used'] as num? ?? 0).toInt();
      final members = objects(data['items']);
      final plants = _plants(data);
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          WizardNavPill.contentPadding,
        ),
        children: [
          Kicker(valueLabel(object(session.bootstrap['client'])['name'])),
          const SizedBox(height: 2),
          Text('Usuarios', style: AppTextStyles.figure(context, size: 29)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$used de $seats ${seats == 1 ? 'cupo' : 'cupos'} en uso · plan ${session.plan.name}',
              style: TextStyle(
                fontSize: 12.5,
                color: used >= seats ? palette.fail : palette.muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SurfaceList(
            children: [
              for (final member in members)
                _MemberRow(
                  member: member,
                  plants: plants,
                  onEdit: () => _edit(member, data),
                  onReset: member['self'] == true || member['active'] != true
                      ? null
                      : () => _reset(member),
                ),
            ],
          ),
          const Notice(
            'El operador ve y verifica solo las balanzas que le asignes en Plantas › Operadores. El jefe de calidad ve todas las de sus plantas.',
            icon: Icons.groups_outlined,
          ),
        ],
      );
    },
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.plants,
    required this.onEdit,
    this.onReset,
  });
  final Json member;
  final Map<String, String> plants;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final active = member['active'] == true;
    final plantNames = [
      for (final id in member['plantIds'] as List? ?? [])
        if (plants[id] != null) plants[id]!,
    ];
    final notes = [
      if (!active)
        'Inactivo'
      else if (member['licensed'] != true)
        'Sin cupo: no puede ingresar'
      else if (member['mustChangePassword'] == true)
        'Debe cambiar su contraseña',
    ];
    final menu = pageMenu([
      wizardMenuItem<VoidCallback>(onEdit, Icons.edit_outlined, 'Editar'),
      if (onReset != null)
        wizardMenuItem<VoidCallback>(
          onReset!,
          Icons.password_outlined,
          'Contraseña temporal',
        ),
    ]);
    return InkWell(
      key: ValueKey('member-${member['username']}'),
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member['self'] == true
                        ? '${valueLabel(member['name'])} (tú)'
                        : valueLabel(member['name']),
                    style: AppTextStyles.figure(
                      context,
                      size: 17,
                      color: active ? null : palette.muted,
                    ),
                  ),
                  Text(
                    [
                      valueLabel(member['username']),
                      _roles[member['role']] ?? valueLabel(member['role']),
                      if (plantNames.isNotEmpty) plantNames.join(', '),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      notes.first,
                      style: TextStyle(
                        fontSize: 12,
                        color: active ? palette.fail : palette.muted,
                      ),
                    ),
                ],
              ),
            ),
            ?menu,
          ],
        ),
      ),
    );
  }
}
