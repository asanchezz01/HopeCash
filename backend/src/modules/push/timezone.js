/**
 * Conversão de "data/hora local em um fuso IANA" para um instante UTC, sem
 * depender de uma biblioteca externa de fusos horários — usa apenas o
 * `Intl.DateTimeFormat` do próprio Node (tz database do sistema).
 * Usada para agendar campanhas: o operador escolhe data/horário/fuso na
 * retaguarda, e a campanha é persistida em UTC.
 */

/** Deslocamento (em minutos, a leste de UTC) de um fuso num instante UTC dado. */
function tzOffsetMinutes(utcMillis, timeZone) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const parts = Object.fromEntries(dtf.formatToParts(new Date(utcMillis)).map((p) => [p.type, p.value]));
  const asUtc = Date.UTC(
    Number(parts.year), Number(parts.month) - 1, Number(parts.day),
    Number(parts.hour), Number(parts.minute), Number(parts.second),
  );
  return (asUtc - utcMillis) / 60_000;
}

/**
 * `dateTimeLocal` no formato 'YYYY-MM-DD HH:MM' (ou com 'T'), interpretado como
 * horário local do fuso `timeZone`. Retorna um `Date` UTC equivalente.
 * Converge em duas iterações (técnica padrão) — em instantes dentro de um
 * "salto" de DST (raríssimo, poucas vezes ao ano em alguns fusos) o resultado
 * pode ficar até 1h fora, o que é aceitável para agendamento de campanhas.
 */
export function zonedTimeToUtc(dateTimeLocal, timeZone) {
  const [datePart, timePart = '00:00'] = dateTimeLocal.trim().split(/[ T]/);
  const [y, mo, d] = datePart.split('-').map(Number);
  const [h, mi] = timePart.split(':').map(Number);
  const naiveUtcMs = Date.UTC(y, mo - 1, d, h, mi, 0);

  let guess = naiveUtcMs;
  for (let i = 0; i < 2; i += 1) {
    const offsetMinutes = tzOffsetMinutes(guess, timeZone);
    guess = naiveUtcMs - offsetMinutes * 60_000;
  }
  return new Date(guess);
}

/** Formato canônico usado nas colunas datetime do app: 'YYYY-MM-DD HH:MM:SS.mmm' em UTC. */
export function toCanonicalUtc(date) {
  return date.toISOString().slice(0, 23).replace('T', ' ');
}
