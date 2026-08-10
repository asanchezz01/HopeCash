/**
 * Carimbo de tempo canônico: 'YYYY-MM-DD HH:MM:SS.mmm' em UTC.
 * O mesmo formato é usado no MySQL (DATETIME(3)) e no SQLite (texto),
 * o que mantém comparações de cursor de sincronização consistentes.
 */
export const now = () => new Date().toISOString().slice(0, 23).replace('T', ' ');

export const today = () => new Date().toISOString().slice(0, 10);

export const addDays = (isoDate, days) => {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

export const addMonths = (isoDate, months) => {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + months);
  return d.toISOString().slice(0, 10);
};

export const monthStart = (isoDate) => `${isoDate.slice(0, 7)}-01`;
