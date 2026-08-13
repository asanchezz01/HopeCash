# Novo VPS — staging e corte definitivo

O novo ambiente usa os arquivos `docker-compose.yml` e
`docker-compose.vps.yml` em conjunto. A topologia mantém MySQL, API, app e
retaguarda em portas locais e publica apenas o Nginx Proxy Manager em 80/443.

| Domínio | Destino Docker |
|---|---|
| `app.hopecash.tech` | `web:80` |
| `api.hopecash.tech` | `api:3000` |
| `adm.hopecash.tech` | `retaguarda:80` |

O painel do Nginx Proxy Manager escuta somente em `127.0.0.1:81`. Para
administrá-lo, abra um túnel e acesse `http://127.0.0.1:8181`:

```bash
ssh -L 8181:127.0.0.1:81 root@179.198.127.58
```

As credenciais iniciais ficam no VPS, com permissão somente para root, em
`/root/.config/hopecash/npm-admin.env`.

## Operação do staging

O arquivo `/opt/hopecash/.env` deve manter estas chaves enquanto a Hope e os
efeitos externos estiverem desabilitados:

```dotenv
AI_ENABLED=false
TTS_ENABLED=false
MAIL_ENABLED=false
FIREBASE_ENABLED=false
PUSH_SCHEDULER_ENABLED=false
```

Suba a stack sempre com os dois arquivos Compose:

```bash
cd /opt/hopecash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.vps.yml up -d
```

`AI_ENABLED=false` é um bloqueio do backend: o cliente Groq recusa chat,
interpretação e geração de dicas sem fazer requisição de rede. O
TTS tem bloqueio equivalente e os endpoints de health devolvem
`disabled: true`.

### Estado após a migração de IA (2026-08-13)

Groq e Azure Speech foram validados e habilitados no VPS. Os efeitos externos
que ainda não fazem parte deste corte permanecem bloqueados:

```dotenv
AI_ENABLED=true
AI_PROVIDER=groq
TTS_ENABLED=true
TTS_PROVIDER=azure
MAIL_ENABLED=false
FIREBASE_ENABLED=false
PUSH_SCHEDULER_ENABLED=false
```

As referências operacionais a Ollama, Kokoro e Coqui foram removidas do `.env`.
As credenciais dos provedores permanecem somente no VPS, com permissão `0600`.

## Corte definitivo

1. Validar app, API e retaguarda no staging, mantendo a Hope desabilitada.
2. Integrar e testar o Groq e Azure Speech no backend sem ainda habilitar o ambiente público.
3. Definir uma janela curta de escrita ou modo de manutenção na produção.
4. Gerar um segundo dump com `--single-transaction`, transferir, validar o
   SHA-256 e restaurar no VPS.
5. Comparar tabelas, migrações e contagens críticas entre origem e destino.
6. Habilitar `AI_ENABLED`, TTS/push/e-mail apenas para os serviços efetivamente
   aprovados e recriar a API.
7. Executar testes finais e manter o servidor antigo disponível para rollback
   durante a janela acordada.

O snapshot inicial fica em `/opt/hopecash/backups/initial/`, protegido para
leitura apenas por root. Ele serve somente para validação; não substitui o dump
feito imediatamente antes do corte.
