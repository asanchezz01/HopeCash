# HopeCash Retaguarda

Painel administrativo (backoffice) do HopeCash — SaaS de gestão financeira da **NewHope**.
Aplicação Flutter otimizada para desktop, com a mesma identidade visual do app e
consumindo **o mesmo backend** (`/api/v1/retaguarda/*`).

## Funcionalidades

- **Gestão de usuários do app** — busca, filtro por status, bloqueio/desbloqueio e
  **reset de senha** (gera uma senha provisória e envia por e-mail ao usuário; com o
  envio desabilitado, o código é exibido no painel para repasse manual).
- **Gestão da equipe da retaguarda** — CRUD de administradores, com papéis
  `superuser` e `admin`.
- **Perfil** — troca da própria senha.
- **Painel inicial** — indicadores de usuários do app e da equipe.

Um **superusuário** é provisionado automaticamente pelo backend na inicialização,
a partir das variáveis `SUPERUSER_EMAIL` / `SUPERUSER_PASSWORD` do `.env` do backend.

## Desenvolvimento

Pré-requisitos: Flutter ≥ 3.44 e o backend do HopeCash em execução.

```bash
cd retaguarda
flutter pub get
flutter run -d chrome        # Web (alvo principal; roda em qualquer navegador desktop)
```

O projeto vem com o alvo **web** pronto. Para gerar um executável desktop nativo,
adicione a plataforma antes: `flutter create . --platforms=windows` (ou `macos`/`linux`)
e então `flutter run -d windows`.

A URL da API é configurável em `lib/core/config/app_config.dart` (padrão
`http://localhost:3000`) ou via `--dart-define=API_BASE_URL=https://api.hopecash.app`.

> A origem web da retaguarda precisa estar em `CORS_ALLOWED_ORIGINS` no backend.

### Login inicial

Use o superusuário definido no `.env` do backend (padrão: `admin@hopecash.app` /
`newhope`). Troque a senha em **Perfil** após o primeiro acesso e cadastre os
demais administradores em **Retaguarda**.

## Build de produção

```bash
flutter build web --release --dart-define=API_BASE_URL=https://hopecash-api.coagru.com.br
```

O deploy em produção é feito via Docker (`retaguarda/Dockerfile`) e orquestrado
pelo `docker-compose.yml` na raiz (serviço `retaguarda`), na **porta fixa 8085**
(`RETAGUARDA_PORT`, ajustável). O `scripts/deploy.sh` garante que a origem
`http://<host>:8085` esteja em `CORS_ALLOWED_ORIGINS` da API automaticamente.

## Estrutura

```
lib/
├── core/           # config, tema (idêntico ao app), design tokens, providers
├── data/           # api client, modelos e repositórios (auth, usuários, app-users)
└── presentation/   # login, casca (nav lateral), painel e telas de gestão
```
