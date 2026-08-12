# HopeCash — ativos para App Store Connect

Arquivos finais prontos para upload:

- `app-store-connect/iphone-6.5/screenshots/`: 10 PNGs em 1242 x 2688 px.
- `app-store-connect/iphone-6.5/previews/`: 3 MP4s em 886 x 1920 px.
- `app-store-connect/ipad-13/screenshots/`: 10 PNGs em 2064 x 2752 px.
- `app-store-connect/ipad-13/previews/`: 3 MP4s em 1200 x 1600 px.

As capturas usam exclusivamente a interface real do HopeCash e dados locais de
demonstração. Os vídeos têm 15,5 segundos, 30 fps, H.264 High Profile Level 4.0,
bitrate alvo de 11 Mbps, varredura progressiva e não possuem trilha de áudio.

O App Store Connect aceita de 1 a 10 screenshots. App previews são opcionais e
aceitam até 3 vídeos por tamanho de tela e idioma.

## Ordem sugerida

1. Dashboard
2. Lançamentos
3. Contas
4. Cartões
5. Orçamento
6. Metas
7. Dívidas
8. Investimentos
9. Hope
10. Mais recursos

## Regeneração

1. Atualize as capturas em `raw/iphone` (414 x 896) e `raw/ipad` (1032 x 1376).
2. Execute `python scripts/app-store/generate_assets.py` na raiz do projeto.
