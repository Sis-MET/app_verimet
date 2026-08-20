import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { bindTenantAccess, clientTenant } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';
import { instrumentsService } from '@features/instruments/application/instruments.service';

type Row = Record<string, unknown>;

export class BootstrapService {
  async get(user: AuthenticatedUser): Promise<Row> {
    const pool = await getSqlPool();
    const tenant = clientTenant(user);
    const plants = await pool.request().input('userId', sql.UniqueIdentifier, user.id).input('tenant', sql.NVarChar(50), tenant).query(`
      SELECT up.planta_id AS id,CONVERT(nvarchar(100),p.codigo_planta) AS code,
        COALESCE(CONVERT(nvarchar(200),p.planta),up.planta_id) AS name,CONVERT(nvarchar(500),p.dir) AS address
      FROM ivmet.usuario_plantas up LEFT JOIN dbo.DATA_PLANTAS p ON CONVERT(nvarchar(50),p.planta_id)=up.planta_id
      WHERE up.usuario_id=@userId AND up.cliente_id=@tenant AND up.activa=1 ORDER BY name
    `);
    const instruments = await instrumentsService.list(user, { page: 1, pageSize: 100 });
    const assignments = await bindTenantAccess(pool.request(), user).query(`
      SELECT DISTINCT ep.plan_version_id AS id FROM ivmet.equipos e
      JOIN ivmet.equipo_planes ep ON ep.cod_metrica=e.cod_metrica
      WHERE e.habilitado=1 AND ${'e.cliente_id = @tenant AND EXISTS (SELECT 1 FROM ivmet.usuario_plantas access WHERE access.usuario_id=@userId AND access.cliente_id=e.cliente_id AND access.planta_id=e.planta_id AND access.activa=1)'}
        AND ep.vigente_desde<=SYSUTCDATETIME() AND (ep.vigente_hasta IS NULL OR ep.vigente_hasta>SYSUTCDATETIME())
        AND EXISTS (SELECT 1 FROM ivmet.plan_versiones pv WHERE pv.plan_version_id=ep.plan_version_id AND pv.estado IN (N'PUBLICADO',N'RETIRADO'))
    `);
    const plans = [];
    for (const row of assignments.recordset as Row[]) {
      const plan = await instrumentsService.getPlanSnapshot(String(row.id));
      if (plan) plans.push(plan);
    }
    const patterns = await bindTenantAccess(pool.request(), user).query(`
      SELECT p.patron_id AS id,p.codigo AS code,p.descripcion AS description,p.tipo AS type,
        p.clase AS class,p.unidad AS unit,CONVERT(varchar(50),p.capacidad) AS capacity,
        pp.planta_id AS plantId,c.certificado_id AS certificateId,c.numero AS certificateNumber,
        c.laboratorio AS laboratory,CONVERT(char(10),c.calibrado_el,23) AS calibratedOn,
        CONVERT(char(10),c.vence_el,23) AS expiresOn,c.documento_referencia AS documentReference
      FROM ivmet.patrones p JOIN ivmet.patron_plantas pp ON pp.patron_id=p.patron_id
      JOIN ivmet.patron_certificados c ON c.patron_id=p.patron_id AND c.estado=N'ACTIVO'
      WHERE p.cliente_id=@tenant AND p.activo=1 AND c.vence_el>=CONVERT(date,SYSUTCDATETIME())
        AND EXISTS (SELECT 1 FROM ivmet.usuario_plantas access WHERE access.usuario_id=@userId AND access.cliente_id=p.cliente_id AND access.planta_id=pp.planta_id AND access.activa=1)
      ORDER BY p.codigo,c.vence_el DESC
    `);
    return {
      generatedAt: new Date().toISOString(), user: { id: user.id, role: user.role, clientId: tenant },
      plants: plants.recordset, instruments: instruments.items, plans, patterns: patterns.recordset,
    };
  }
}

export const bootstrapService = new BootstrapService();
