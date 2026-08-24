import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/instruments_demo_data.dart';
import '../../domain/entities/area.dart';
import '../../domain/entities/instrument.dart';
import '../../domain/entities/verification_history_entry.dart';

/// Areas del cliente con sesion abierta.
///
/// DEMO: lee de [InstrumentsDemoData]. El repositorio real hara
/// `GET /api/v1/clients/:id/areas` con cache local, porque esta pantalla
/// tiene que abrir tambien sin VPN.
final areasProvider = Provider<List<Area>>((ref) => InstrumentsDemoData.areas);

/// Equipos de un area. Devuelve lista vacia si el area no existe: la pantalla
/// puede llegar por deep link con un nombre que ya no esta.
final areaInstrumentsProvider = Provider.family<List<Instrument>, String>((ref, area) {
  return InstrumentsDemoData.porArea[area] ?? const <Instrument>[];
});

final areaByNameProvider = Provider.family<Area?, String>((ref, nombre) {
  for (final area in ref.watch(areasProvider)) {
    if (area.nombre == nombre) return area;
  }
  return null;
});

/// Un equipo por su codigo de placa, que es como lo identifica el operario.
final instrumentByCodeProvider = Provider.family<Instrument?, String>((ref, codigo) {
  for (final instrument in InstrumentsDemoData.todos) {
    if (instrument.codigo == codigo) return instrument;
  }
  return null;
});

/// Historico de verificaciones de un equipo, de la mas reciente a la mas
/// antigua.
final instrumentHistoryProvider = Provider.family<List<VerificationHistoryEntry>, String>((
  ref,
  codigo,
) {
  return InstrumentsDemoData.historico;
});
