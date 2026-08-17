# Deploy no VPS

O fluxo padrão publica o commit da `main` no VPS `179.198.127.58` por SSH. O
runner é hospedado pelo GitHub; não existe mais runner self-hosted no servidor.

## Fluxo

O workflow [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml):

1. valida o shell e a configuração combinada dos dois arquivos Compose;
2. autentica o host por uma chave pública SSH fixada no workflow;
3. sincroniza somente os arquivos versionados para `/opt/hopecash` via rsync;
4. preserva `.env`, backups, uploads e demais dados exclusivos do VPS;
5. executa [`scripts/deploy.sh`](../scripts/deploy.sh) sob um lock exclusivo;
6. valida API, app e administração pelos domínios HTTPS públicos.

O deploy dispara em todo push na `main`, exceto alterações apenas em documentação,
e também pode ser iniciado manualmente em **Actions → Deploy VPS → Run workflow**.
Execuções nunca rodam em paralelo.

## Secret obrigatório

Cadastre em **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Conteúdo |
|---|---|
| `VPS_SSH_PRIVATE_KEY` | Chave privada SSH sem passphrase, cuja chave pública esteja autorizada para `root` no VPS |

A chave privada nunca entra no repositório nem é enviada por rsync. A chave pública
do host (`ssh-ed25519`) está fixada no workflow para impedir conexão silenciosa a
outro servidor. Se o VPS for reinstalado e sua host key mudar, valide a nova chave
fora do GitHub antes de atualizar o workflow.

O job usa o GitHub Environment `production`; regras de aprovação podem ser
configuradas em **Settings → Environments → production**.

## Segurança e rollback

Antes de trocar os containers, o script:

- cria um dump transacional compactado do MySQL em
  `/opt/hopecash/backups/deploy/` e conserva os dez mais recentes;
- registra as imagens atuais de `api`, `web` e `retaguarda`;
- constrói todas as novas imagens enquanto a versão anterior segue no ar;
- restaura automaticamente as imagens anteriores se a troca ou os healthchecks
  locais falharem.

O rollback de imagens não desfaz automaticamente migrations SQL. O dump
pré-deploy é a proteção para uma restauração deliberada do banco.

O script sempre combina `docker-compose.yml` com `docker-compose.vps.yml`. Isso
mantém o Nginx Proxy Manager e o Portainer no projeto Compose e impede que sejam
removidos como órfãos. Mesmo no modo `RESET_DB=1`, somente o volume MySQL é
removido; certificados, configurações do proxy e dados do Portainer não são
apagados.

## Estado persistente

O `/opt/hopecash/.env` pertence ao VPS, tem permissão `0600` e é excluído da
sincronização. O script preserva credenciais do MySQL, JWT, Groq, Azure Speech e
demais integrações. Por padrão, as portas internas de MySQL, API, app e retaguarda
ficam vinculadas a `127.0.0.1`; somente o Nginx Proxy Manager publica 80/443.
Nos Proxy Hosts, os upstreams devem ser os nomes exclusivos
`hopecash-web:80`, `hopecash-api:3000` e `hopecash-retaguarda:80`. Não use os
aliases genéricos `web`, `api` ou `retaguarda`, pois eles podem colidir quando
outra aplicação participa da rede `hopecash_proxy`.

As opções manuais disponíveis no workflow são:

- `no_cache`: reconstrói sem cache;
- `pull`: atualiza imagens base;
- `prune`: remove imagens Docker sem uso depois de um deploy bem-sucedido.

`RESET_DB` não é exposto no GitHub Actions.

## Alternativa local

[`scripts/deploy-server.ps1`](../scripts/deploy-server.ps1) continua disponível
para operação manual via SSH. Ele termina chamando o mesmo `scripts/deploy.sh`,
portanto usa os mesmos backups, Compose do VPS e healthchecks.

## Endpoints publicados

- App: `https://app.hopecash.tech`
- API: `https://api.hopecash.tech`
- Administração: `https://adm.hopecash.tech`
- Portainer: `https://adm2.hopecash.tech`
- Proxy: `https://proxy.hopecash.tech`
