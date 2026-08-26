import type { DataMetRepository } from '../infrastructure/datamet.repository';
import type { IvmetRepository } from '../infrastructure/ivmet.repository';
import type { SupabaseGateway } from '../infrastructure/supabase.gateway';

export class HealthService {
  constructor(
    private readonly dataMet: DataMetRepository,
    private readonly ivmet: IvmetRepository,
    private readonly supabase: SupabaseGateway,
  ) {}

  async check(): Promise<Record<string, unknown>> {
    const [dataMet, ivmet, supabase] = await Promise.all([
      this.dataMet.healthCheck(),
      this.ivmet.healthCheck(),
      this.supabase.healthCheck(),
    ]);

    if (dataMet.database !== 'DataMET' || !dataMet.canSelect || dataMet.canUpdate) {
      throw new Error('Permisos inseguros o incompletos sobre DataMET');
    }
    if (
      ivmet.database !== 'IvMET' ||
      ivmet.versions !== 6 ||
      !ivmet.canSelectMirror ||
      !ivmet.canInsertMirror ||
      ivmet.canDeleteVerification
    ) {
      throw new Error('La base IvMET no cumple el contrato de esquema/permisos');
    }

    return {
      status: 'ok',
      dataMet,
      ivmet,
      supabase,
    };
  }
}
