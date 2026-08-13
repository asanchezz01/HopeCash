# HopeCash — Gestão Financeira Pessoal e Familiar

Plataforma da **NewHope** para controle completo da vida financeira: receitas, despesas, contas, cartões, orçamentos, metas, fluxo de caixa, dívidas e investimentos. Offline-first, multiplataforma (Android, iOS, Web) e preparada para SaaS multiusuário.

## Estrutura do repositório

```
HopeCash/
├── backend/     # API Node.js (Express 5 + Knex + MySQL) — compartilhada por app e retaguarda
├── app/         # Aplicativo Flutter (Android/iOS/Web)
├── retaguarda/  # Painel administrativo Flutter (backoffice, otimizado para desktop)
├── docs/        # Documentação de arquitetura, dados, sync e API
└── docker-compose.yml
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Arquitetura, módulos, sincronização offline-first, segurança |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | Modelo de dados completo (MySQL + SQLite local) |
| [docs/API.md](docs/API.md) | Visão geral da API REST (Swagger em `/api/docs`) |
| [docs/DEPLOY.md](docs/DEPLOY.md) | Deploy no VPS via GitHub Actions/SSH + alternativa local |
| [docs/VPS_STAGING.md](docs/VPS_STAGING.md) | Stack do novo VPS, Nginx Proxy Manager e procedimento do corte em duas etapas |
| [docs/FLUTTERFIRE.md](docs/FLUTTERFIRE.md) | Notificações push (Firebase Cloud Messaging): Android/iOS/Web, VAPID, rotação de credencial, pendência de APNs |

## Início rápido (ambiente local)

Pré-requisitos: Docker + Docker Compose, Node.js ≥ 20, Flutter ≥ 3.35.

### 1. Backend + MySQL

```bash
docker compose up -d mysql          # sobe o MySQL 8
cd backend
cp .env.example .env
npm install
npm run migrate                     # cria o schema
npm run seed                        # dados de demonstração
npm run dev                         # API em http://localhost:3000
```

Ou tudo via Docker: `docker compose up --build` (API + MySQL + migrations automáticas).

- Swagger UI: <http://localhost:3000/api/docs>
- Healthcheck: <http://localhost:3000/api/v1/health>
- Usuário demo: `demo@hopecash.app` / `Demo123!`

### 2. Aplicativo Flutter

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # codegen do Drift
flutter run -d chrome        # Web
flutter run                  # Android/iOS (emulador/dispositivo conectado)
```

A URL da API é configurável em `app/lib/core/config/app_config.dart` (padrão `http://localhost:3000`; no emulador Android use `http://10.0.2.2:3000`).

### 3. Retaguarda (painel administrativo)

Backoffice em Flutter otimizado para desktop, sobre o mesmo backend. Um superusuário é
provisionado na inicialização da API a partir de `SUPERUSER_EMAIL`/`SUPERUSER_PASSWORD`
do `backend/.env`.

```bash
cd retaguarda
flutter pub get
flutter run -d chrome        # Web
```

Login inicial: `admin@hopecash.app` / `newhope` (padrão do `.env`). Funcionalidades:
gestão de usuários do app (bloqueio e reset de senha com código provisório por e-mail),
gestão da equipe da retaguarda e troca de senha. Veja [retaguarda/README.md](retaguarda/README.md).

### 4. Testes

```bash
cd backend && npm test       # API (Vitest + Supertest, banco SQLite em memória)
cd app && flutter test       # unitários e widget
```

## Licença

Proprietário — NewHope. Todos os direitos reservados.
