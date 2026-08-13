FROM node:24-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY knexfile.js ./
COPY src ./src

ENV NODE_ENV=production
EXPOSE 3000

# Aplica migrations pendentes e inicia a API. O loop tolera o MySQL ainda
# nao aceitar conexoes logo apos o healthcheck, mas nao roda para sempre: uma
# migration realmente quebrada (SQL invalido, tabela em estado inconsistente)
# falha apos ~1min em vez de mascarar o erro real com "Aguardando MySQL..."
# repetido infinitamente.
CMD ["sh", "-c", "n=0; until npx knex migrate:latest; do n=$((n+1)); if [ \"$n\" -ge 20 ]; then echo 'Migration falhou repetidamente - abortando (nao e mais espera de MySQL).' >&2; exit 1; fi; echo \"Aguardando MySQL... (tentativa $n/20)\"; sleep 3; done; node src/server.js"]
