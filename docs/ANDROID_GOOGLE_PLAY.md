# Publicação Android no Google Play

O workflow `.github/workflows/android-google-play.yml` gera um Android App
Bundle assinado e o envia para o pacote `br.com.newhope.hopecash` no Google
Play. Ele é executado manualmente em **Actions > Android Google Play > Run
workflow**.

## Segredos necessários

Configure estes GitHub Actions secrets no repositório ou nos environments
`google-play-internal`, `google-play-alpha`, `google-play-beta` e
`google-play-production`:

- `ANDROID_KEYSTORE_BASE64`: conteúdo Base64 do arquivo `.jks` da chave de upload.
- `ANDROID_KEYSTORE_PASSWORD`: senha do keystore.
- `ANDROID_KEY_ALIAS`: alias da chave.
- `ANDROID_KEY_PASSWORD`: senha da chave.
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: JSON completo da conta de serviço.

No PowerShell, gere o conteúdo Base64 do keystore com:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\caminho\upload-key.jks"))
```

Base64 apenas transforma o arquivo em texto; a proteção vem do GitHub Actions
secret. Nunca faça commit do keystore ou do JSON da conta de serviço.

## Conta de serviço

1. Ative a Google Play Android Developer API no projeto do Google Cloud.
2. Crie uma conta de serviço e uma chave JSON.
3. Em **Play Console > Usuários e permissões**, convide o e-mail da conta de
   serviço e conceda ao app HopeCash permissão para gerenciar versões nas faixas
   que o workflow usará.
4. Salve o JSON completo em `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.

Se a API responder `Package not found` no primeiro envio, envie manualmente um
primeiro AAB no Play Console e execute o workflow novamente.

## Faixas e status

O padrão é `internal` com status `completed`. Também é possível escolher
`alpha` (teste fechado), `beta` (teste aberto) ou `production`, além de criar
somente um `draft`.

No estado atual do app no Play Console, produção ainda não está disponível: é
necessário concluir a configuração e cumprir o teste fechado exigido pelo
Google Play. Use primeiro a faixa interna e depois a faixa fechada.

O version code é calculado como `run_number * 100 + run_attempt`, evitando
duplicidade em uma nova tentativa do mesmo workflow.
