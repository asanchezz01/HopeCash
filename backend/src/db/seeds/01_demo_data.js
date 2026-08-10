/**
 * Seeds de demonstração: categorias padrão do sistema + usuário demo
 * (demo@hopecash.app / Demo123!) com contas, cartão, transações, orçamento,
 * meta, dívida e investimento — o suficiente para o app "nascer" populado.
 */
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { insertDefaultCategories } from '../../modules/categories/categories.service.js';

const now = () => new Date().toISOString().slice(0, 23).replace('T', ' ');
const uuid = () => crypto.randomUUID();
const iso = (d) => d.toISOString().slice(0, 10);
const monthShift = (months, day = 1) => {
  const d = new Date();
  d.setUTCMonth(d.getUTCMonth() + months, day);
  return iso(d);
};

const sync = (userId) => ({
  user_id: userId, created_at: now(), updated_at: now(), deleted_at: null, version: 1,
});

export async function seed(knex) {
  const existing = await knex('users').where({ email: 'demo@hopecash.app' }).first();
  if (existing) return; // seeds são idempotentes

  // ----- Usuário demo -----
  const userId = uuid();
  await knex('users').insert({
    id: userId,
    name: 'Ana Demonstração',
    email: 'demo@hopecash.app',
    password_hash: await bcrypt.hash('Demo123!', 12),
    locale: 'pt-BR',
    currency: 'BRL',
    status: 'active',
    created_at: now(),
    updated_at: now(),
    version: 1,
  });

  // ----- Categorias padrão (cópias do próprio usuário demo) -----
  const catIds = await insertDefaultCategories(knex, userId);

  // ----- Família -----
  const familyId = uuid();
  await knex('families').insert({
    id: familyId, ...sync(userId), name: 'Família Demonstração', owner_id: userId,
  });
  await knex('family_members').insert({
    id: uuid(), ...sync(userId), family_id: familyId, member_user_id: userId,
    role: 'owner', status: 'active',
  });

  // ----- Contas -----
  const checkingId = uuid();
  const walletId = uuid();
  const savingsId = uuid();
  await knex('bank_accounts').insert([
    {
      id: checkingId, ...sync(userId), name: 'Conta Corrente', bank_name: 'Banco Hope',
      bank_code: '001', agency: '1234', account_number: '56789-0', type: 'checking',
      initial_balance: 2500, initial_balance_date: monthShift(-6), color: '#1565C0',
      icon: 'account_balance', is_active: true, include_in_total: true,
    },
    {
      id: walletId, ...sync(userId), name: 'Carteira', type: 'cash',
      initial_balance: 150, initial_balance_date: monthShift(-6), color: '#2E7D32',
      icon: 'wallet', is_active: true, include_in_total: true,
    },
    {
      id: savingsId, ...sync(userId), name: 'Poupança', bank_name: 'Banco Hope', type: 'savings',
      initial_balance: 8000, initial_balance_date: monthShift(-6), color: '#6A1B9A',
      icon: 'savings', is_active: true, include_in_total: true,
    },
  ]);

  // ----- Cartão + fatura aberta -----
  const cardId = uuid();
  const invoiceId = uuid();
  await knex('credit_cards').insert({
    id: cardId, ...sync(userId), name: 'Cartão Hope Platinum', issuer: 'Banco Hope',
    limit_amount: 8000, closing_day: 28, due_day: 8, color: '#37474F', icon: 'credit_card',
    is_active: true, default_account_id: checkingId,
  });
  await knex('credit_card_invoices').insert({
    id: invoiceId, ...sync(userId), card_id: cardId,
    reference_month: monthShift(0), closing_date: monthShift(0, 28), due_date: monthShift(1, 8),
    status: 'open', total_amount: 0, paid_amount: 0,
  });

  // ----- Transações (últimos 3 meses + próximas contas) -----
  const tx = (data) => ({ id: uuid(), ...sync(userId), created_by: userId, updated_by: userId, ...data });
  const rows = [];
  for (let m = -3; m <= 0; m++) {
    rows.push(tx({
      type: 'income', description: 'Salário', amount: 7500, amount_planned: 7500,
      competence_date: monthShift(m, 5), due_date: monthShift(m, 5),
      payment_date: m < 0 ? monthShift(m, 5) : null,
      status: m < 0 ? 'paid' : 'planned',
      account_id: checkingId, category_id: catIds['Salário'],
    }));
    rows.push(tx({
      type: 'expense', description: 'Aluguel', amount: m < 0 ? 2200 : null, amount_planned: 2200,
      competence_date: monthShift(m, 10), due_date: monthShift(m, 10),
      payment_date: m < 0 ? monthShift(m, 10) : null,
      status: m < 0 ? 'paid' : 'planned',
      account_id: checkingId, category_id: catIds['Moradia'],
    }));
    rows.push(tx({
      type: 'expense', description: 'Supermercado Bom Preço', amount: m < 0 ? 850 + m * 30 : null,
      amount_planned: 850, competence_date: monthShift(m, 12), due_date: monthShift(m, 12),
      payment_date: m < 0 ? monthShift(m, 12) : null,
      status: m < 0 ? 'paid' : 'planned',
      account_id: checkingId, category_id: catIds['Mercado'],
    }));
    if (m < 0) {
      rows.push(tx({
        type: 'expense', description: 'Restaurante Sabor & Arte', amount: 180, amount_planned: 180,
        competence_date: monthShift(m, 15), payment_date: monthShift(m, 15), status: 'paid',
        account_id: walletId, category_id: catIds['Alimentação'],
      }));
      rows.push(tx({
        type: 'expense', description: 'Combustível Posto Shell', amount: 320, amount_planned: 320,
        competence_date: monthShift(m, 18), payment_date: monthShift(m, 18), status: 'paid',
        account_id: checkingId, category_id: catIds['Transporte'],
      }));
      rows.push(tx({
        type: 'expense', description: 'Streaming HopeFlix', amount: 55.9, amount_planned: 55.9,
        competence_date: monthShift(m, 20), payment_date: monthShift(m, 20), status: 'paid',
        account_id: checkingId, category_id: catIds['Assinaturas'],
      }));
    }
  }
  // Compra parcelada no cartão (3x) na fatura atual.
  const groupId = uuid();
  for (let i = 0; i < 3; i++) {
    rows.push(tx({
      type: 'expense', description: `Notebook Dell (${i + 1}/3)`, amount_planned: 1200,
      competence_date: monthShift(i, 25), due_date: monthShift(i + 1, 8),
      status: 'planned', card_id: cardId, invoice_id: i === 0 ? invoiceId : null,
      category_id: catIds['Outros'], installment_group_id: groupId,
      installment_number: i + 1, installment_total: 3,
    }));
  }
  await knex('transactions').insert(rows);

  // ----- Orçamento do mês atual -----
  const budgetId = uuid();
  await knex('budgets').insert({
    id: budgetId, ...sync(userId), reference_month: monthShift(0), scope: 'personal',
    notes: 'Orçamento de demonstração',
  });
  const budgetItems = [
    ['Moradia', 2300, true], ['Mercado', 900, false], ['Alimentação', 400, false],
    ['Transporte', 450, false], ['Assinaturas', 120, true], ['Lazer', 300, false],
  ];
  await knex('budget_items').insert(budgetItems.map(([cat, value, fixed]) => ({
    id: uuid(), ...sync(userId), budget_id: budgetId,
    category_id: catIds[cat], planned_amount: value, is_fixed: fixed,
  })));

  // ----- Meta, dívida, investimento -----
  await knex('goals').insert({
    id: uuid(), ...sync(userId), name: 'Reserva de emergência', target_amount: 30000,
    target_date: monthShift(18), accumulated_amount: 8000, linked_account_id: savingsId,
    icon: 'shield', color: '#2E7D32', status: 'active',
  });
  await knex('debts').insert({
    id: uuid(), ...sync(userId), name: 'Financiamento do carro', type: 'financing',
    institution: 'Banco Hope', original_amount: 45000, outstanding_balance: 27000,
    interest_rate_monthly: 1.29, total_installments: 48, paid_installments: 20,
    installment_amount: 1150, first_due_date: monthShift(-20, 15), due_day: 15, status: 'active',
  });
  const investmentId = uuid();
  await knex('investments').insert({
    id: investmentId, ...sync(userId), name: 'CDB 110% CDI', type: 'fixed_income',
    institution: 'Banco Hope', applied_amount: 15000, current_amount: 16240,
    last_quote_date: monthShift(0, 1),
  });
  await knex('investment_movements').insert([
    { id: uuid(), ...sync(userId), investment_id: investmentId, type: 'deposit', amount: 15000, movement_date: monthShift(-10, 3) },
    { id: uuid(), ...sync(userId), investment_id: investmentId, type: 'yield', amount: 1240, movement_date: monthShift(0, 1) },
  ]);

  // ----- Regras de exemplo -----
  await knex('categorization_rules').insert([
    {
      id: uuid(), ...sync(userId), name: 'Supermercados', match_field: 'description',
      operator: 'contains', match_value: 'supermercado', category_id: catIds['Mercado'], priority: 10, is_active: true,
    },
    {
      id: uuid(), ...sync(userId), name: 'Combustível', match_field: 'description',
      operator: 'contains', match_value: 'posto', category_id: catIds['Transporte'], priority: 20, is_active: true,
    },
  ]);
  await knex('notification_rules').insert({
    id: uuid(), ...sync(userId), bank_package: 'com.nu.production', bank_name: 'Nubank',
    event_type: 'pix_out',
    pattern: 'Você enviou um Pix de R\\$\\s?(?<valor>[\\d.,]+) para (?<estabelecimento>.+)',
    is_active: true,
  });
}
