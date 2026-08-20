export type TraceabilityStatus = 'traceable' | 'non_traceable';

export function deriveScope(statuses: Array<'performed' | 'omitted'>): 'complete' | 'partial' {
  return statuses.every((status) => status === 'performed') ? 'complete' : 'partial';
}

export function certificateIsTraceable(performedAt: Date, calibratedOn: string, expiresOn: string): boolean {
  const calibrated = new Date(`${calibratedOn}T00:00:00.000Z`);
  const expires = new Date(`${expiresOn}T23:59:59.999Z`);
  return performedAt >= calibrated && performedAt <= expires;
}

export function nextDueAt(lastTraceablePerformedAt: Date | null, frequencyDays: number): Date | null {
  if (!lastTraceablePerformedAt) return null;
  return new Date(lastTraceablePerformedAt.getTime() + frequencyDays * 86_400_000);
}
