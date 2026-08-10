# Deploy em produção

O deploy é feito por um único script, [`scripts/deploy.sh`](../scripts/deploy.sh), que roda **no servidor de produção** a partir de um checkout do repositório: grava/preserva o `.env` persistente (padrão `/opt/hopecash/.env`), derruba os containers e os republica com o [`docker-compose.yml`](../docker-compose.yml) da raiz, aguardando o healthcheck da API e do Web.

Há dois caminhos para acioná-lo:

| Caminho | Quando usar |
|---|---|
| **GitHub Actions** (push na `main` ou disparo manual) | Fluxo padrão — funciona de qualquer lugar, inclusive pelo celular |
| **`deploy.bat`** (SSH a partir do PC) | Alternativa quando o runner estiver fora do ar |

## GitHub Actions (recomendado)

O workflow [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) roda em um **runner self-hosted instalado no servidor** e dispara:

- automaticamente a cada push na `main` (mudanças só em `docs/` ou `*.md` não disparam);
- manualmente pelo app/site do GitHub: **Actions → Deploy produção → Run workflow**, com opções de rebuild sem cache, `--pull` das imagens base e prune de imagens.

Deploys nunca rodam em paralelo (grupo de concorrência `production-deploy`); pushes em sequência ficam em fila.

### Fluxo pelo celular

1. Code e faça merge/push na `main` (Claude Code web, GitHub mobile, Codespaces…).
2. O push dispara o deploy sozinho.
3. Acompanhe os logs em tempo real no app do GitHub, em **Actions**.

### Instalação do runner (uma vez, no servidor)

Pré-requisitos no servidor: `git`, `curl`, `iproute2` (`ss`) e o usuário do runner no grupo `docker` (`sudo usermod -aG docker <usuario>`).

1. No GitHub: **Settings → Actions → Runners → New self-hosted runner → Linux x64** e execute no servidor os comandos de download e `./config.sh` que a página gera.
2. Instale como serviço para sobreviver a reboots:

   ```bash
   cd ~/actions-runner
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

3. Confirme que o runner aparece como **Idle** na página de Runners e dispare um **Run workflow** de teste.

O runner faz o checkout do código sozinho — não é preciso `GIT_TOKEN` nem repositório clonado em `/opt/hopecash` para esse caminho (apenas o `.env` persiste lá).

## `deploy.bat` (SSH a partir do PC)

```bat
deploy.bat                     :: portas padrão 8092/3001/3306
deploy.bat -NoCache -Pull
deploy.bat -ResetDatabase      :: CUIDADO: apaga o volume do MySQL
```

Lê as credenciais de `C:\app\hopecash_private\deploy_credencial.txt` (`SERVER`, `SSH_USER`, `GIT_USERNAME`, `GIT_TOKEN`…), atualiza o clone em `/opt/hopecash` via SSH e executa o mesmo `scripts/deploy.sh` lá. Detalhes em [`scripts/deploy-server.ps1`](../scripts/deploy-server.ps1).

## Configuração persistente

O `.env` do servidor guarda portas, URLs e segredos gerados no primeiro deploy (`MYSQL_PASSWORD`, `JWT_SECRET`…). Ele é reescrito a cada deploy **preservando os valores existentes**; para trocar um valor, edite o arquivo no servidor antes do próximo deploy ou passe a variável correspondente (`WEB_PORT`, `API_BASE_URL`, `CORS_ALLOWED_ORIGINS`…) ao `deploy.sh`. `RESET_DB=1` (ou `-ResetDatabase` no `deploy.bat`) apaga o volume do MySQL — não está exposto no workflow por segurança.
