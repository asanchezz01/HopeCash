// Investigação autorizada pelo usuário: buscar em produção o lançamento
// "Saúde · Unimed" que vence hoje (R$ 3.152,63) e entender por que a Hope
// não o retornou como "vencendo esta semana".
import mysql from 'mysql2/promise';

const conn = await mysql.createConnection({
  host: '10.1.4.82',
  port: 3306,
  user: 'hopecash',
  password: 'hopecash',
  database: 'hopecash',
});

const [rows] = await conn.execute(`
  SELECT t.id, t.user_id, t.type, t.description, t.amount_planned, t.amount,
         t.competence_date, t.due_date, t.payment_date, t.status,
         t.account_id, t.card_id, t.invoice_id, t.category_id, t.deleted_at,
         c.name AS category_name
  FROM transactions t
  LEFT JOIN categories c ON c.id = t.category_id
  WHERE t.description LIKE '%Unimed%' OR c.name LIKE '%Sa%de%'
  ORDER BY t.due_date DESC
  LIMIT 20
`);
console.log('Lançamentos candidatos:');
console.table(rows.map((r) => ({
  ...r,
  due_date: String(r.due_date), competence_date: String(r.competence_date),
})));

if (rows.length) {
  const todayRow = rows.find((r) => String(r.due_date) === new Date().toISOString().slice(0, 10)) ?? rows[0];
  console.log('\nDetalhe do lançamento de hoje / mais recente:', JSON.stringify(todayRow, null, 2));
}

await conn.end();
