# Instalação de teste no iPhone (TestFlight)

O HopeCash para iPhone é distribuído pelo TestFlight. 

## Configuração inicial da Apple

1. Tenha uma inscrição ativa no Apple Developer Program.
2. No Apple Developer, registre o App ID explícito `br.com.newhope.hopecash` e
   habilite as capacidades necessárias, incluindo **Push Notifications**.
3. No App Store Connect, crie o app HopeCash para iOS com esse mesmo Bundle ID.
4. Crie uma chave de API do App Store Connect com acesso **App Manager** e guarde
   o arquivo `.p8` com segurança: ele só pode ser baixado uma vez.

## Secrets do GitHub

No repositório, abra **Settings → Environments → New environment** e crie
`testflight`. Em seguida, nessa environment, adicione estes secrets:

| Secret                             | Valor                                                                      |
| ---------------------------------- | -------------------------------------------------------------------------- |
| `APP_STORE_CONNECT_ISSUER_ID`      | Issuer ID da chave de API do App Store Connect                             |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID da chave de API                                                     |
| `APP_STORE_CONNECT_PRIVATE_KEY`    | Conteúdo completo do arquivo `.p8`                                         |
| `IOS_CERTIFICATE_PRIVATE_KEY`      | Chave privada RSA usada para criar/recuperar o certificado de distribuição |

Para gerar a última chave no Windows, se tiver o OpenSSL instalado:

```powershell
openssl genrsa -out ios_certificate_key.pem 2048
```

Copie o conteúdo inteiro de `ios_certificate_key.pem` para o secret
`IOS_CERTIFICATE_PRIVATE_KEY`. Não envie essa chave, o `.p8`, certificados ou
perfis de provisionamento para o Git.

## Gerar e instalar

1. Abra **Actions → iOS TestFlight → Run workflow** no GitHub.
2. Aguarde o envio e o processamento da Apple. O primeiro envio pode levar cerca
   de 30 minutos para aparecer no TestFlight.
3. No App Store Connect, abra o app → **TestFlight** → **Internal Testing** e
   adicione o seu Apple ID como testador interno.
4. No iPhone, instale o app **TestFlight** da App Store, aceite o convite e toque
   em **Instalar** no HopeCash.

O workflow sempre compila com
`https://api.hopecash.tech` como `API_BASE_URL`.
