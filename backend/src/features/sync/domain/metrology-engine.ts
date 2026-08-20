import Decimal from 'decimal.js';

Decimal.set({ precision: 40, rounding: Decimal.ROUND_HALF_UP });

export type EvaluationMethod = 'absolute_error' | 'range' | 'sample_standard_deviation';

export interface EngineReading {
  pointId: string;
  group: number;
  order: number;
  code: string;
  label: string;
  nominalLoad: string;
  indication: string;
  zeroReturn?: string;
  tolerance: string;
  metadata?: unknown;
}

export interface CalculatedReading extends EngineReading {
  error: string;
  verdict: 'pass' | 'fail';
}

export interface TestCalculation {
  verdict: 'pass' | 'fail';
  readings: CalculatedReading[];
  metrics: {
    maximumAbsoluteError: string;
    mean: string;
    sampleStandardDeviation: string;
    range: string;
    acceptanceLimit: string;
  };
}

function fixed(value: Decimal): string {
  const output = value.toDecimalPlaces(9).toFixed(9);
  if (!/^-?\d{1,10}\.\d{9}$/.test(output)) throw new RangeError('El resultado excede decimal(19,9)');
  return output;
}

function min(values: Decimal[]): Decimal {
  return Decimal.min(...values);
}

export function evaluateTest(method: EvaluationMethod, input: EngineReading[]): TestCalculation {
  if (input.length === 0) throw new Error('Una prueba ejecutada requiere lecturas');
  let readings: CalculatedReading[] = input.map((reading) => {
    const error = new Decimal(reading.indication).minus(reading.nominalLoad);
    return { ...reading, error: fixed(error), verdict: error.abs().lte(reading.tolerance) ? 'pass' : 'fail' };
  });
  const indications = readings.map((reading) => new Decimal(reading.indication));
  const errors = readings.map((reading) => new Decimal(reading.error));
  const mean = Decimal.sum(...indications).div(indications.length);
  const groups = new Map<number, CalculatedReading[]>();
  for (const reading of readings) groups.set(reading.group, [...(groups.get(reading.group) ?? []), reading]);
  const groupMetrics = [...groups.values()].map((group) => {
    const values = group.map((reading) => new Decimal(reading.indication));
    const groupMean = Decimal.sum(...values).div(values.length);
    const variance = values.length < 2
      ? new Decimal(0)
      : Decimal.sum(...values.map((value) => value.minus(groupMean).pow(2))).div(values.length - 1);
    return {
      group: group[0]!.group,
      range: Decimal.max(...values).minus(Decimal.min(...values)),
      standardDeviation: variance.sqrt(),
      limit: min(group.map((reading) => new Decimal(reading.tolerance))),
    };
  });
  const range = Decimal.max(...groupMetrics.map((metric) => metric.range));
  const standardDeviation = Decimal.max(...groupMetrics.map((metric) => metric.standardDeviation));
  const maximumAbsoluteError = Decimal.max(...errors.map((value) => value.abs()));
  const acceptanceLimit = min(readings.map((reading) => new Decimal(reading.tolerance)));
  let verdict: 'pass' | 'fail';
  switch (method) {
    case 'absolute_error':
      verdict = readings.every((reading) => reading.verdict === 'pass') ? 'pass' : 'fail';
      break;
    case 'range':
      verdict = groupMetrics.every((metric) => metric.range.lte(metric.limit)) ? 'pass' : 'fail';
      readings = readings.map((reading) => ({ ...reading,
        verdict: groupMetrics.find((metric) => metric.group === reading.group)!.range.lte(
          groupMetrics.find((metric) => metric.group === reading.group)!.limit,
        ) ? 'pass' : 'fail' }));
      break;
    case 'sample_standard_deviation':
      verdict = groupMetrics.every((metric) => metric.standardDeviation.lte(metric.limit)) ? 'pass' : 'fail';
      readings = readings.map((reading) => ({ ...reading,
        verdict: groupMetrics.find((metric) => metric.group === reading.group)!.standardDeviation.lte(
          groupMetrics.find((metric) => metric.group === reading.group)!.limit,
        ) ? 'pass' : 'fail' }));
      break;
  }
  return {
    verdict, readings,
    metrics: {
      maximumAbsoluteError: fixed(maximumAbsoluteError), mean: fixed(mean),
      sampleStandardDeviation: fixed(standardDeviation), range: fixed(range),
      acceptanceLimit: fixed(acceptanceLimit),
    },
  };
}
