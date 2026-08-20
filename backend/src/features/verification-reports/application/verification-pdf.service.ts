import PDFDocument from 'pdfkit';
import type { VerificationDetail } from './verification-reports.service';

type Row = Record<string, unknown>;

function value(input: unknown): string {
  if (input === null || input === undefined || input === '') return '—';
  if (input instanceof Date) return input.toISOString();
  return String(input);
}

function verdict(input: unknown): string {
  return input === 'pass' ? 'CONFORME' : input === 'fail' ? 'NO CONFORME' : value(input).toUpperCase();
}

export class VerificationPdfService {
  async generate(detail: VerificationDetail): Promise<Buffer> {
    const doc = new PDFDocument({ size: 'A4', margin: 42, info: { Title: `Informe IvMET ${value(detail.id)}`, Author: 'Metrica' } });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    const completed = new Promise<Buffer>((resolve, reject) => {
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);
    });

    const heading = (title: string) => {
      if (doc.y > 720) doc.addPage();
      doc.moveDown(0.5).font('Helvetica-Bold').fontSize(12).fillColor('#123B5D').text(title);
      doc.moveDown(0.25).fillColor('#000000').font('Helvetica').fontSize(9);
    };
    const line = (label: string, content: unknown) => doc.font('Helvetica-Bold').text(`${label}: `, { continued: true }).font('Helvetica').text(value(content));

    doc.font('Helvetica-Bold').fontSize(18).fillColor('#123B5D').text('INFORME DE VERIFICACIÓN INTERMEDIA');
    doc.font('Helvetica').fontSize(9).fillColor('#000000').text(`IvMET · Identificador ${value(detail.id)}`);
    heading('Identificación y resultado');
    line('Equipo', detail.equipmentCode); line('Cliente', detail.clientId); line('Planta', detail.plantId);
    line('Fecha de medición (UTC)', detail.performedAt); line('Fecha de recepción (UTC)', detail.receivedAt);
    line('Alcance', detail.scope === 'complete' ? 'Completo' : 'Parcial');
    line('Resultado', verdict(detail.verdict)); line('Trazabilidad', detail.traceability === 'traceable' ? 'Trazable' : 'No trazable');
    line('Estado del registro', detail.status); line('Plan / versión', detail.planVersionId);

    heading('Equipo y plan capturados');
    doc.text(JSON.stringify(detail.equipmentSnapshot, null, 2), { width: 510 });
    doc.text(JSON.stringify(detail.planSnapshot, null, 2), { width: 510 });

    heading('Condiciones y responsables');
    line('Temperatura', detail.temperatureC ? `${value(detail.temperatureC)} °C` : null);
    line('Humedad relativa', detail.relativeHumidityPct ? `${value(detail.relativeHumidityPct)} %` : null);
    line('Capturado por', `${value(detail.capturedBy)} (${value(detail.capturedById)})`);
    line('Subido por', `${value(detail.uploadedBy)} (${value(detail.uploadedById)})`);
    line('Aplicación / dispositivo', `${value(detail.appVersion)} / ${value(detail.deviceId)}`);
    line('Observaciones', detail.observations);

    heading('Patrones y certificados');
    for (const standard of detail.standards) {
      const snapshot = standard.snapshot as Row;
      doc.font('Helvetica-Bold').text(`${value(snapshot.codigo)} · ${value(snapshot.descripcion)}`);
      doc.font('Helvetica').text(`Rol: ${value(standard.role)} | Certificado: ${value(snapshot.numero)} | Laboratorio: ${value(snapshot.laboratorio)}`);
      doc.text(`Calibración: ${value(snapshot.calibrado_el)} | Vencimiento: ${value(snapshot.vence_el)}`);
    }

    heading('Pruebas, omisiones y lecturas');
    for (const test of detail.tests) {
      if (doc.y > 690) doc.addPage();
      doc.font('Helvetica-Bold').fontSize(10).text(`${value(test.type).toUpperCase()} · ${value(test.executionStatus)}`);
      doc.font('Helvetica').fontSize(8.5).text(`Método: ${value(test.evaluationMethod)} | Veredicto: ${verdict(test.verdict)} | Omisión: ${value(test.omissionReason)}`);
      const metrics = test.metrics as Row;
      doc.text(`Tolerancia: ${value(metrics.acceptanceLimit)} | Error máx.: ${value(metrics.maximumAbsoluteError)} | Media: ${value(metrics.mean)} | Desv. estándar: ${value(metrics.sampleStandardDeviation)} | Rango: ${value(metrics.range)}`);
      for (const reading of test.readings as Row[]) {
        if (doc.y > 745) doc.addPage();
        doc.text(`${value(reading.order)}. ${value(reading.label)} | Carga ${value(reading.nominalLoad)} | Indicación ${value(reading.indication)} | Error ${value(reading.error)} | Tol. ${value(reading.tolerance)} | ${verdict(reading.verdict)}`);
      }
      doc.moveDown(0.35);
    }

    if (detail.status === 'ANULADA') {
      heading('Anulación'); line('Fecha', detail.annulledAt); line('Responsable', detail.annulledBy); line('Motivo', detail.annulmentReason);
    }
    doc.moveDown().fontSize(8).fillColor('#555555').text('Documento generado bajo demanda por IvMET. No contiene firma manuscrita ni fotografías.');
    doc.end();
    return completed;
  }
}

export const verificationPdfService = new VerificationPdfService();
