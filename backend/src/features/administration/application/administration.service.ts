import bcrypt from 'bcrypt';
import { env } from '@core/config';
import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ConflictError, DatabaseError, NotFoundError, ValidationError } from '@core/errors';
import { writeAudit, type AuditEvent } from '@shared/audit/audit';
import type { AuthenticatedUser, UserRole } from '@shared/types';
import { instrumentsService } from '@features/instruments/application/instruments.service';

type Row = Record<string, unknown>;

function normalized(value: string): string {
  return value.normalize('NFKC').trim().toUpperCase();
}

export class AdministrationService {
  async listClients(): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().query(`
      SELECT CONVERT(nvarchar(50),cliente_id) AS id,CONVERT(nvarchar(100),codigo_cliente) AS code,
        COALESCE(CONVERT(nvarchar(250),cliente),CONVERT(nvarchar(250),razonsocial),CONVERT(nvarchar(50),cliente_id)) AS name
      FROM dbo.DATA_CLIENTES ORDER BY name
    `);
    return result.recordset as Row[];
  }

  async listPlants(clientId: string): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().input('clientId', sql.NVarChar(50), clientId).query(`
      SELECT CONVERT(nvarchar(50),planta_id) AS id,CONVERT(nvarchar(100),codigo_planta) AS code,
        COALESCE(CONVERT(nvarchar(200),planta),CONVERT(nvarchar(50),planta_id)) AS name,
        CONVERT(nvarchar(500),dir) AS address
      FROM dbo.DATA_PLANTAS WHERE CONVERT(nvarchar(50),cliente_id)=@clientId ORDER BY name
    `);
    return result.recordset as Row[];
  }

  async listAreas(filters: { clientId?: string; plantId?: string }): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().input('clientId', sql.NVarChar(50), filters.clientId ?? null)
      .input('plantId', sql.NVarChar(50), filters.plantId ?? null).query(`
        SELECT area_id AS id,cliente_id AS clientId,planta_id AS plantId,nombre AS name,activa AS active,
          creado_at AS createdAt,actualizado_at AS updatedAt FROM ivmet.areas
        WHERE (@clientId IS NULL OR cliente_id=@clientId) AND (@plantId IS NULL OR planta_id=@plantId)
        ORDER BY cliente_id,planta_id,nombre
      `);
    return result.recordset as Row[];
  }

  async listInstruments(filters: { clientId?: string; plantId?: string }): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().input('clientId', sql.NVarChar(50), filters.clientId ?? null)
      .input('plantId', sql.NVarChar(50), filters.plantId ?? null).query(`
        SELECT e.cod_metrica AS code,e.cliente_id AS clientId,e.planta_id AS plantId,e.area_id AS areaId,
          a.nombre AS areaName,e.estado_configuracion AS configurationStatus,e.habilitado AS enabled,
          ep.plan_version_id AS activePlanVersionId,e.creado_at AS createdAt,e.actualizado_at AS updatedAt
        FROM ivmet.equipos e LEFT JOIN ivmet.areas a ON a.area_id=e.area_id
        OUTER APPLY (SELECT TOP 1 plan_version_id FROM ivmet.equipo_planes WHERE cod_metrica=e.cod_metrica AND vigente_hasta IS NULL ORDER BY vigente_desde DESC) ep
        WHERE (@clientId IS NULL OR e.cliente_id=@clientId) AND (@plantId IS NULL OR e.planta_id=@plantId)
        ORDER BY e.cliente_id,e.planta_id,e.cod_metrica
      `);
    return result.recordset as Row[];
  }

  async listPatterns(filters: { clientId?: string; plantId?: string }): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().input('clientId', sql.NVarChar(50), filters.clientId ?? null)
      .input('plantId', sql.NVarChar(50), filters.plantId ?? null).query(`
        SELECT p.patron_id AS id,p.cliente_id AS clientId,p.codigo AS code,p.descripcion AS description,
          p.tipo AS type,p.clase AS class,p.unidad AS unit,CONVERT(varchar(50),p.capacidad) AS capacity,p.activo AS active,
          (SELECT pp.planta_id AS id FROM ivmet.patron_plantas pp WHERE pp.patron_id=p.patron_id FOR JSON PATH) AS plants,
          (SELECT c.certificado_id AS id,c.numero AS number,c.laboratorio AS laboratory,
             CONVERT(char(10),c.calibrado_el,23) AS calibratedOn,CONVERT(char(10),c.vence_el,23) AS expiresOn,
             c.estado AS status,c.documento_referencia AS documentReference
           FROM ivmet.patron_certificados c WHERE c.patron_id=p.patron_id ORDER BY c.vence_el DESC FOR JSON PATH) AS certificates
        FROM ivmet.patrones p WHERE (@clientId IS NULL OR p.cliente_id=@clientId)
          AND (@plantId IS NULL OR EXISTS (SELECT 1 FROM ivmet.patron_plantas pp WHERE pp.patron_id=p.patron_id AND pp.planta_id=@plantId))
        ORDER BY p.cliente_id,p.codigo
      `);
    return (result.recordset as Row[]).map((row) => ({ ...row, plants: JSON.parse(String(row.plants || '[]')), certificates: JSON.parse(String(row.certificates || '[]')) }));
  }

  async listPlans(): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().query(`
      SELECT p.plan_id AS id,p.nombre AS name,p.descripcion AS description,p.activo AS active,
        pv.plan_version_id AS versionId,pv.version,pv.estado AS status,pv.procedimiento_referencia AS procedureReference,
        pv.creado_at AS createdAt,pv.publicado_at AS publishedAt,
        (SELECT COUNT(*) FROM ivmet.plan_pruebas t WHERE t.plan_version_id=pv.plan_version_id) AS testCount,
        (SELECT COUNT(*) FROM ivmet.plan_pruebas t JOIN ivmet.plan_puntos point ON point.plan_prueba_id=t.plan_prueba_id WHERE t.plan_version_id=pv.plan_version_id) AS pointCount
      FROM ivmet.planes p LEFT JOIN ivmet.plan_versiones pv ON pv.plan_id=p.plan_id ORDER BY p.nombre,pv.version DESC
    `);
    return result.recordset as Row[];
  }

  async getPlanVersion(versionId: string): Promise<Row> {
    const version = await instrumentsService.getPlanSnapshot(versionId);
    if (!version) throw new NotFoundError('Version del plan no encontrada');
    return version;
  }

  async listAssignments(filters: { clientId?: string; plantId?: string }): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request().input('clientId', sql.NVarChar(50), filters.clientId ?? null)
      .input('plantId', sql.NVarChar(50), filters.plantId ?? null).query(`
        SELECT ep.equipo_plan_id AS id,ep.cod_metrica AS equipmentCode,e.cliente_id AS clientId,e.planta_id AS plantId,
          ep.plan_version_id AS planVersionId,p.nombre AS planName,pv.version,
          ep.vigente_desde AS effectiveFrom,ep.vigente_hasta AS effectiveUntil,ep.creado_at AS createdAt
        FROM ivmet.equipo_planes ep JOIN ivmet.equipos e ON e.cod_metrica=ep.cod_metrica
        JOIN ivmet.plan_versiones pv ON pv.plan_version_id=ep.plan_version_id JOIN ivmet.planes p ON p.plan_id=pv.plan_id
        WHERE (@clientId IS NULL OR e.cliente_id=@clientId) AND (@plantId IS NULL OR e.planta_id=@plantId)
        ORDER BY ep.vigente_desde DESC
      `);
    return result.recordset as Row[];
  }

  async listUsers(filters: { clientId?: string; status?: string }): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await pool.request()
      .input('clientId', sql.NVarChar(50), filters.clientId ?? null)
      .input('status', sql.NVarChar(20), filters.status ?? null)
      .query(`
        SELECT usuario_id AS id, usuario AS username, nombre AS name, email,
          rol AS role, cliente_id AS clientId, estado AS status,
          debe_cambiar_password AS mustChangePassword, ultimo_acceso_at AS lastAccessAt,
          creado_at AS createdAt
        FROM ivmet.usuarios
        WHERE (@clientId IS NULL OR cliente_id = @clientId)
          AND (@status IS NULL OR estado = @status)
        ORDER BY nombre
      `);
    return result.recordset as Row[];
  }

  async createUser(input: {
    username: string; name: string; email?: string; temporaryPassword: string;
    role: UserRole; clientId?: string; plantIds: string[];
  }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      if (input.clientId) await this.assertLegacyPlants(transaction, input.clientId, input.plantIds);
      const passwordHash = await bcrypt.hash(input.temporaryPassword, env.BCRYPT_SALT_ROUNDS);
      const inserted = await transaction.request()
        .input('username', sql.NVarChar(100), input.username)
        .input('normalized', sql.NVarChar(100), normalized(input.username))
        .input('name', sql.NVarChar(200), input.name)
        .input('email', sql.NVarChar(254), input.email ?? null)
        .input('hash', sql.NVarChar(255), passwordHash)
        .input('role', sql.NVarChar(40), input.role)
        .input('clientId', sql.NVarChar(50), input.clientId ?? null)
        .input('actor', sql.UniqueIdentifier, actor.id)
        .query(`
          INSERT INTO ivmet.usuarios
            (usuario, usuario_normalizado, nombre, email, password_hash, rol,
             cliente_id, debe_cambiar_password, creado_por)
          OUTPUT INSERTED.usuario_id
          VALUES (@username, @normalized, @name, @email, @hash, @role,
                  @clientId, 1, @actor)
        `);
      const userId = String(inserted.recordset[0]?.usuario_id);
      for (const plantId of [...new Set(input.plantIds)]) {
        await transaction.request()
          .input('userId', sql.UniqueIdentifier, userId)
          .input('clientId', sql.NVarChar(50), input.clientId ?? null)
          .input('plantId', sql.NVarChar(50), plantId)
          .query(`INSERT INTO ivmet.usuario_plantas (usuario_id, cliente_id, planta_id) VALUES (@userId, @clientId, @plantId)`);
      }
      await writeAudit(transaction.request(), {
        ...metadata, actor, entity: 'usuario', entityId: userId, action: 'create',
        after: { username: input.username, role: input.role, clientId: input.clientId ?? null, plantIds: input.plantIds },
      });
      await transaction.commit();
      return userId;
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError) throw error;
      if ((error as { number?: number }).number === 2627 || (error as { number?: number }).number === 2601) {
        throw new ConflictError('El usuario ya existe');
      }
      throw new DatabaseError('No se pudo crear el usuario', error);
    }
  }

  async updateUserStatus(userId: string, status: 'ACTIVO' | 'INACTIVO', actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    if (userId === actor.id && status === 'INACTIVO') throw new ValidationError('No puede desactivar su propia cuenta');
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      const changed = await transaction.request()
        .input('id', sql.UniqueIdentifier, userId)
        .input('status', sql.NVarChar(20), status)
        .query(`
          UPDATE ivmet.usuarios SET estado = @status, token_version = token_version + 1,
            actualizado_at = SYSUTCDATETIME() WHERE usuario_id = @id;
          SELECT @@ROWCOUNT AS affected;
        `);
      if (!Number(changed.recordset[0]?.affected)) throw new NotFoundError('Usuario no encontrado');
      if (status === 'INACTIVO') {
        await transaction.request().input('id', sql.UniqueIdentifier, userId).query(`
          UPDATE ivmet.sesiones_refresh SET revocado_at = COALESCE(revocado_at, SYSUTCDATETIME()) WHERE usuario_id = @id
        `);
      }
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'usuario', entityId: userId, action: 'status_change', after: { status } });
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError || error instanceof NotFoundError) throw error;
      throw new DatabaseError('No se pudo actualizar el usuario', error);
    }
  }

  async resetPassword(userId: string, password: string, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const hash = await bcrypt.hash(password, env.BCRYPT_SALT_ROUNDS);
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      const changed = await transaction.request()
        .input('id', sql.UniqueIdentifier, userId)
        .input('hash', sql.NVarChar(255), hash)
        .query(`
          UPDATE ivmet.usuarios SET password_hash = @hash, debe_cambiar_password = 1,
            token_version = token_version + 1, intentos_fallidos = 0,
            bloqueado_hasta = NULL, actualizado_at = SYSUTCDATETIME()
          WHERE usuario_id = @id;
          SELECT @@ROWCOUNT AS affected;
        `);
      if (!Number(changed.recordset[0]?.affected)) throw new NotFoundError('Usuario no encontrado');
      await transaction.request().input('id', sql.UniqueIdentifier, userId).query(`
        UPDATE ivmet.sesiones_refresh SET revocado_at = COALESCE(revocado_at, SYSUTCDATETIME()) WHERE usuario_id = @id
      `);
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'usuario', entityId: userId, action: 'password_reset' });
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      if (error instanceof NotFoundError) throw error;
      throw new DatabaseError('No se pudo restablecer la contrasena', error);
    }
  }

  async assignUserPlants(userId: string, plantIds: string[], actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      const found = await transaction.request().input('id', sql.UniqueIdentifier, userId).query(`
        SELECT cliente_id, rol FROM ivmet.usuarios WHERE usuario_id = @id
      `);
      const row = found.recordset[0] as Row | undefined;
      if (!row) throw new NotFoundError('Usuario no encontrado');
      const clientId = row.cliente_id === null ? null : String(row.cliente_id);
      if (!clientId || !String(row.rol).startsWith('cliente_')) throw new ValidationError('Solo los usuarios de cliente reciben plantas');
      await this.assertLegacyPlants(transaction, clientId, plantIds);
      await transaction.request().input('id', sql.UniqueIdentifier, userId).query(`
        UPDATE ivmet.usuario_plantas SET activa=0 WHERE usuario_id=@id AND activa=1
      `);
      for (const plantId of [...new Set(plantIds)]) {
        await transaction.request().input('id', sql.UniqueIdentifier, userId)
          .input('clientId', sql.NVarChar(50), clientId).input('plantId', sql.NVarChar(50), plantId)
          .query(`
            MERGE ivmet.usuario_plantas AS target
            USING (SELECT @id AS usuario_id,@plantId AS planta_id) AS source
              ON target.usuario_id=source.usuario_id AND target.planta_id=source.planta_id
            WHEN MATCHED THEN UPDATE SET activa=1,cliente_id=@clientId
            WHEN NOT MATCHED THEN INSERT (usuario_id,cliente_id,planta_id,activa) VALUES (@id,@clientId,@plantId,1);
          `);
      }
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'usuario', entityId: userId, action: 'assign_plants', after: { plantIds } });
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError || error instanceof NotFoundError) throw error;
      throw new DatabaseError('No se pudieron asignar las plantas', error);
    }
  }

  async createArea(input: { clientId: string; plantId: string; name: string }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    await this.assertLegacyPlant(pool, input.clientId, input.plantId);
    const result = await pool.request().input('clientId', sql.NVarChar(50), input.clientId)
      .input('plantId', sql.NVarChar(50), input.plantId).input('name', sql.NVarChar(150), input.name)
      .input('normalized', sql.NVarChar(150), normalized(input.name)).query(`
        INSERT INTO ivmet.areas (cliente_id, planta_id, nombre, nombre_normalizado)
        OUTPUT INSERTED.area_id VALUES (@clientId, @plantId, @name, @normalized)
      `);
    const areaId = String(result.recordset[0]?.area_id);
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'area', entityId: areaId, action: 'create', after: input });
    return areaId;
  }

  async enableInstrument(input: { equipmentCode: string; clientId: string; plantId: string; areaId?: string; enabled: boolean }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    await this.assertLegacyPlant(pool, input.clientId, input.plantId);
    const legacy = await pool.request().input('code', sql.NVarChar(100), input.equipmentCode).query(`
      SELECT TOP 1 general.cod_metrica
      FROM dbo.DATA_EQUIPOS general JOIN dbo.DATA_EQUIPOS_BALANZAS balance
        ON CONVERT(nvarchar(100),balance.cod_metrica)=CONVERT(nvarchar(100),general.cod_metrica)
      WHERE CONVERT(nvarchar(100),general.cod_metrica)=@code
    `);
    if (!legacy.recordset[0]) throw new ValidationError('El equipo no tiene ficha general y metrologica completas en los catalogos legados');
    if (input.areaId) await this.assertArea(pool, input.areaId, input.clientId, input.plantId);
    await pool.request().input('code', sql.NVarChar(100), input.equipmentCode)
      .input('clientId', sql.NVarChar(50), input.clientId).input('plantId', sql.NVarChar(50), input.plantId)
      .input('areaId', sql.UniqueIdentifier, input.areaId ?? null).input('enabled', sql.Bit, input.enabled)
      .input('actor', sql.UniqueIdentifier, actor.id).query(`
        MERGE ivmet.equipos AS target
        USING (SELECT @code AS cod_metrica) AS source ON target.cod_metrica = source.cod_metrica
        WHEN MATCHED THEN UPDATE SET cliente_id=@clientId, planta_id=@plantId, area_id=@areaId,
          habilitado=@enabled, actualizado_at=SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (cod_metrica, cliente_id, planta_id, area_id, habilitado, creado_por)
          VALUES (@code, @clientId, @plantId, @areaId, @enabled, @actor);
      `);
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'equipo', entityId: input.equipmentCode, action: 'enable', after: input });
  }

  async updateInstrument(code: string, input: { areaId?: string | null; enabled?: boolean }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const found = await pool.request().input('code', sql.NVarChar(100), code).query(`SELECT cliente_id, planta_id FROM ivmet.equipos WHERE cod_metrica=@code`);
    const row = found.recordset[0] as Row | undefined;
    if (!row) throw new NotFoundError('Equipo IvMET no encontrado');
    if (input.areaId) await this.assertArea(pool, input.areaId, String(row.cliente_id), String(row.planta_id));
    await pool.request().input('code', sql.NVarChar(100), code)
      .input('areaId', sql.UniqueIdentifier, input.areaId ?? null).input('setArea', sql.Bit, input.areaId !== undefined)
      .input('enabled', sql.Bit, input.enabled ?? false).input('setEnabled', sql.Bit, input.enabled !== undefined).query(`
        UPDATE ivmet.equipos SET area_id=CASE WHEN @setArea=1 THEN @areaId ELSE area_id END,
          habilitado=CASE WHEN @setEnabled=1 THEN @enabled ELSE habilitado END,
          actualizado_at=SYSUTCDATETIME() WHERE cod_metrica=@code
      `);
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'equipo', entityId: code, action: 'update', after: input });
  }

  async createPattern(input: { clientId: string; code: string; description: string; type: string; class?: string; unit?: string; capacity?: string; plantIds: string[] }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      await this.assertLegacyPlants(transaction, input.clientId, input.plantIds);
      const result = await transaction.request().input('clientId', sql.NVarChar(50), input.clientId)
        .input('code', sql.NVarChar(100), input.code).input('description', sql.NVarChar(300), input.description)
        .input('type', sql.NVarChar(50), input.type).input('class', sql.NVarChar(50), input.class ?? null)
        .input('unit', sql.NVarChar(20), input.unit ?? null).input('capacity', sql.NVarChar(50), input.capacity ?? null)
        .input('actor', sql.UniqueIdentifier, actor.id).query(`
          INSERT INTO ivmet.patrones (cliente_id,codigo,descripcion,tipo,clase,unidad,capacidad,creado_por)
          OUTPUT INSERTED.patron_id VALUES (@clientId,@code,@description,@type,@class,@unit,CONVERT(decimal(19,9),@capacity),@actor)
        `);
      const patternId = String(result.recordset[0]?.patron_id);
      for (const plantId of [...new Set(input.plantIds)]) {
        await transaction.request().input('id', sql.UniqueIdentifier, patternId).input('plant', sql.NVarChar(50), plantId)
          .query(`INSERT INTO ivmet.patron_plantas (patron_id, planta_id) VALUES (@id,@plant)`);
      }
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'patron', entityId: patternId, action: 'create', after: input });
      await transaction.commit();
      return patternId;
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError) throw error;
      throw new DatabaseError('No se pudo crear el patron', error);
    }
  }

  async createCertificate(patternId: string, input: { number: string; laboratory: string; calibratedOn: string; expiresOn: string; documentReference?: string }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    const result = await pool.request().input('patternId', sql.UniqueIdentifier, patternId)
      .input('number', sql.NVarChar(150), input.number).input('lab', sql.NVarChar(250), input.laboratory)
      .input('calibrated', sql.Date, new Date(`${input.calibratedOn}T00:00:00.000Z`)).input('expires', sql.Date, new Date(`${input.expiresOn}T00:00:00.000Z`))
      .input('document', sql.NVarChar(500), input.documentReference ?? null).input('actor', sql.UniqueIdentifier, actor.id).query(`
        INSERT INTO ivmet.patron_certificados
          (patron_id,numero,laboratorio,calibrado_el,vence_el,documento_referencia,creado_por)
        OUTPUT INSERTED.certificado_id
        SELECT @patternId,@number,@lab,@calibrated,@expires,@document,@actor
        WHERE EXISTS (SELECT 1 FROM ivmet.patrones WHERE patron_id=@patternId AND activo=1)
      `);
    const certificateId = result.recordset[0]?.certificado_id;
    if (!certificateId) throw new NotFoundError('Patron activo no encontrado');
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'certificado', entityId: String(certificateId), action: 'create', after: input });
    return String(certificateId);
  }

  async createPlan(input: { name: string; description?: string }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    const result = await pool.request().input('name', sql.NVarChar(200), input.name)
      .input('description', sql.NVarChar(1000), input.description ?? null).input('actor', sql.UniqueIdentifier, actor.id).query(`
        INSERT INTO ivmet.planes (nombre,descripcion,creado_por) OUTPUT INSERTED.plan_id VALUES (@name,@description,@actor)
      `);
    const planId = String(result.recordset[0]?.plan_id);
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'plan', entityId: planId, action: 'create', after: input });
    return planId;
  }

  async createPlanVersion(planId: string, input: { procedureReference: string; notes?: string; tests: Array<{ type: string; evaluationMethod: string; unit: string; frequencyDays: number; warningDays: number; metadata?: unknown; points: Array<{ group: number; order: number; code: string; label: string; nominalLoad: string; tolerance: string; position?: string; direction?: string; metadata?: unknown }> }> }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const types = input.tests.map((test) => test.type);
    if (new Set(types).size !== types.length) throw new ValidationError('No se puede repetir un tipo de prueba');
    for (const test of input.tests) {
      const orders = test.points.map((point) => point.order);
      const codes = test.points.map((point) => normalized(point.code));
      if (new Set(orders).size !== orders.length || new Set(codes).size !== codes.length) {
        throw new ValidationError(`Ordenes y codigos deben ser unicos en ${test.type}`);
      }
    }
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
    try {
      const inserted = await transaction.request().input('planId', sql.UniqueIdentifier, planId)
        .input('procedure', sql.NVarChar(300), input.procedureReference).input('notes', sql.NVarChar(1000), input.notes ?? null)
        .input('actor', sql.UniqueIdentifier, actor.id).query(`
          DECLARE @next int = (SELECT ISNULL(MAX(version),0)+1 FROM ivmet.plan_versiones WITH (UPDLOCK,HOLDLOCK) WHERE plan_id=@planId);
          INSERT INTO ivmet.plan_versiones (plan_id,version,procedimiento_referencia,notas,creado_por)
          OUTPUT INSERTED.plan_version_id VALUES (@planId,@next,@procedure,@notes,@actor)
        `);
      const versionId = String(inserted.recordset[0]?.plan_version_id);
      for (const test of input.tests) {
        const testResult = await transaction.request().input('versionId', sql.UniqueIdentifier, versionId)
          .input('type', sql.NVarChar(30), test.type).input('method', sql.NVarChar(60), test.evaluationMethod)
          .input('unit', sql.NVarChar(20), test.unit).input('frequency', sql.Int, test.frequencyDays)
          .input('warning', sql.Int, test.warningDays).input('metadata', sql.NVarChar(sql.MAX), test.metadata ? JSON.stringify(test.metadata) : null).query(`
            INSERT INTO ivmet.plan_pruebas (plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,aviso_dias,metadata_json)
            OUTPUT INSERTED.plan_prueba_id VALUES (@versionId,@type,@method,@unit,@frequency,@warning,@metadata)
          `);
        const testId = String(testResult.recordset[0]?.plan_prueba_id);
        for (const point of test.points) {
          await transaction.request().input('testId', sql.UniqueIdentifier, testId).input('group', sql.Int, point.group)
            .input('order', sql.Int, point.order).input('code', sql.NVarChar(100), point.code)
            .input('label', sql.NVarChar(200), point.label).input('load', sql.NVarChar(50), point.nominalLoad)
            .input('tolerance', sql.NVarChar(50), point.tolerance).input('position', sql.NVarChar(100), point.position ?? null)
            .input('direction', sql.NVarChar(30), point.direction ?? null)
            .input('metadata', sql.NVarChar(sql.MAX), point.metadata ? JSON.stringify(point.metadata) : null).query(`
              INSERT INTO ivmet.plan_puntos
                (plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,tolerancia,posicion,direccion,metadata_json)
              VALUES (@testId,@group,@order,@code,@label,CONVERT(decimal(19,9),@load),CONVERT(decimal(19,9),@tolerance),@position,@direction,@metadata)
            `);
        }
      }
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'plan_version', entityId: versionId, action: 'create', after: input });
      await transaction.commit();
      return versionId;
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError) throw error;
      if ((error as { number?: number }).number === 547) throw new NotFoundError('Plan no encontrado');
      throw new DatabaseError('No se pudo crear la version del plan', error);
    }
  }

  async publishPlanVersion(versionId: string, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      const result = await transaction.request().input('id', sql.UniqueIdentifier, versionId)
        .input('actor', sql.UniqueIdentifier, actor.id).query(`
          UPDATE pv SET estado=N'PUBLICADO', publicado_at=SYSUTCDATETIME(), publicado_por=@actor
          FROM ivmet.plan_versiones pv
          WHERE pv.plan_version_id=@id AND pv.estado=N'BORRADOR'
            AND NULLIF(LTRIM(RTRIM(pv.procedimiento_referencia)),N'') IS NOT NULL
            AND EXISTS (SELECT 1 FROM ivmet.plan_pruebas pp WHERE pp.plan_version_id=pv.plan_version_id)
            AND NOT EXISTS (
              SELECT 1 FROM ivmet.plan_pruebas pp WHERE pp.plan_version_id=pv.plan_version_id
                AND NOT EXISTS (SELECT 1 FROM ivmet.plan_puntos p WHERE p.plan_prueba_id=pp.plan_prueba_id)
            );
          SELECT @@ROWCOUNT AS affected;
        `);
      if (!Number(result.recordset[0]?.affected)) throw new ConflictError('La version no existe, ya no es borrador o esta incompleta');
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'plan_version', entityId: versionId, action: 'publish' });
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ConflictError) throw error;
      throw new DatabaseError('No se pudo publicar la version', error);
    }
  }

  async retirePlanVersion(versionId: string, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const result = await pool.request().input('id', sql.UniqueIdentifier, versionId).query(`
      UPDATE ivmet.plan_versiones SET estado=N'RETIRADO' WHERE plan_version_id=@id AND estado=N'PUBLICADO';
      SELECT @@ROWCOUNT AS affected;
    `);
    if (!Number(result.recordset[0]?.affected)) throw new ConflictError('Solo se puede retirar una version publicada');
    await writeAudit(pool.request(), { ...metadata, actor, entity: 'plan_version', entityId: versionId, action: 'retire' });
  }

  async assignPlan(input: { equipmentCode: string; planVersionId: string; effectiveFrom: string }, actor: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<string> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
    try {
      const valid = await transaction.request().input('code', sql.NVarChar(100), input.equipmentCode)
        .input('version', sql.UniqueIdentifier, input.planVersionId).query(`
          SELECT 1 AS valid FROM ivmet.equipos e CROSS JOIN ivmet.plan_versiones pv
          WHERE e.cod_metrica=@code AND e.habilitado=1 AND pv.plan_version_id=@version AND pv.estado=N'PUBLICADO'
        `);
      if (!valid.recordset[0]) throw new ValidationError('Equipo habilitado o version publicada no encontrados');
      await transaction.request().input('code', sql.NVarChar(100), input.equipmentCode)
        .input('from', sql.DateTime2(3), new Date(input.effectiveFrom)).query(`
          UPDATE ivmet.equipo_planes SET vigente_hasta=@from
          WHERE cod_metrica=@code AND vigente_hasta IS NULL AND vigente_desde < @from
        `);
      const result = await transaction.request().input('code', sql.NVarChar(100), input.equipmentCode)
        .input('version', sql.UniqueIdentifier, input.planVersionId).input('from', sql.DateTime2(3), new Date(input.effectiveFrom))
        .input('actor', sql.UniqueIdentifier, actor.id).query(`
          INSERT INTO ivmet.equipo_planes (cod_metrica,plan_version_id,vigente_desde,creado_por)
          OUTPUT INSERTED.equipo_plan_id VALUES (@code,@version,@from,@actor)
        `);
      const assignmentId = String(result.recordset[0]?.equipo_plan_id);
      await transaction.request().input('code', sql.NVarChar(100), input.equipmentCode).query(`
        UPDATE ivmet.equipos SET estado_configuracion=N'LISTO',actualizado_at=SYSUTCDATETIME() WHERE cod_metrica=@code
      `);
      await writeAudit(transaction.request(), { ...metadata, actor, entity: 'equipo_plan', entityId: assignmentId, action: 'assign', after: input });
      await transaction.commit();
      return assignmentId;
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ValidationError) throw error;
      throw new DatabaseError('No se pudo asignar el plan', error);
    }
  }

  private async assertLegacyPlants(transaction: sql.Transaction, clientId: string, plantIds: string[]): Promise<void> {
    for (const plantId of [...new Set(plantIds)]) await this.assertLegacyPlant(transaction, clientId, plantId);
  }

  private async assertLegacyPlant(executor: sql.ConnectionPool | sql.Transaction, clientId: string, plantId: string): Promise<void> {
    const result = await executor.request().input('clientId', sql.NVarChar(50), clientId)
      .input('plantId', sql.NVarChar(50), plantId).query(`
        SELECT TOP 1 1 AS valid FROM dbo.DATA_PLANTAS
        WHERE CONVERT(nvarchar(50), cliente_id)=@clientId AND CONVERT(nvarchar(50), planta_id)=@plantId
      `);
    if (!result.recordset[0]) throw new ValidationError(`La planta ${plantId} no pertenece al cliente ${clientId}`);
  }

  private async assertArea(pool: sql.ConnectionPool, areaId: string, clientId: string, plantId: string): Promise<void> {
    const result = await pool.request().input('area', sql.UniqueIdentifier, areaId)
      .input('client', sql.NVarChar(50), clientId).input('plant', sql.NVarChar(50), plantId).query(`
        SELECT TOP 1 1 AS valid FROM ivmet.areas WHERE area_id=@area AND cliente_id=@client AND planta_id=@plant AND activa=1
      `);
    if (!result.recordset[0]) throw new ValidationError('El area no pertenece al cliente y planta indicados');
  }
}

export const administrationService = new AdministrationService();
