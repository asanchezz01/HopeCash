/**
 * Trilha persistente das chamadas JSON-RPC recebidas pelo servidor MCP.
 *
 * Motivação (2026-08-08): investigar uma falha relatada de ChatGPT exigiu
 * garimpar `docker logs` do container e inferir o nome da tool que falhava a
 * partir do `content-length` da resposta — o corpo JSON-RPC nunca é logado.
 * Pior: o log do container é volátil (some quando o container é recriado no
 * deploy) e não permite atribuir uma requisição a um usuário sem casar hash de
 * token na mão. Esta tabela resolve os três problemas de uma vez.
 *
 * Guardamos os ARGUMENTOS enviados pelo host, nunca o RESULTADO — o resultado
 * é o dado financeiro do usuário em si, e reproduzi-lo aqui multiplicaria a
 * superfície LGPD sem ajudar no diagnóstico. Os argumentos de uma tool de
 * escrita já são persistidos em `ai_actions.payload` de qualquer forma.
 */
export async function up(knex) {
  if (await knex.schema.hasTable('mcp_logs')) return;

  await knex.schema.createTable('mcp_logs', (t) => {
    t.uuid('id').primary();
    // Nulo quando a chamada nem chegou a autenticar (401 de descoberta, que é
    // um passo normal do RFC 9728 — o host sonda sem token de propósito).
    t.uuid('user_id').index();
    // Nome do PAT ("OAuth: ChatGPT", "Claude", ...) — na prática identifica o
    // host que fez a chamada, já que cada host tem seu próprio token.
    t.string('client_name', 120);
    t.string('pat_kind', 20);
    t.string('method', 40).index();
    // Preenchido só em tools/call. Indexado porque a pergunta mais frequente é
    // "qual tool está falhando" — inclusive tools que NÃO existem (o 404 de
    // tool desconhecida é justamente o caso que motivou esta tabela).
    t.string('tool_name', 60).index();
    t.boolean('ok').notNullable();
    t.smallint('status_code').notNullable();
    t.integer('error_code');
    t.text('error_message');
    t.text('arguments');
    t.integer('duration_ms');
    t.string('ip', 45);
    t.string('user_agent', 300);
    t.datetime('created_at', { precision: 3 }).notNullable().index();
  });
}

export async function down(knex) {
  await knex.schema.dropTable('mcp_logs');
}
