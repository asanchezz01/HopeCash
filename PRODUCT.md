# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Pessoas e famílias que precisam registrar, compreender e planejar a própria vida financeira no celular, tablet ou navegador. A página pública também atende visitantes da App Store avaliando o produto e usuários que precisam de suporte.

## Product Purpose

O HopeCash reúne receitas, despesas, contas, cartões, orçamentos, metas, dívidas e investimentos em uma visão financeira coerente. Sucesso significa reduzir a dispersão de informações e ajudar o usuário a registrar a rotina, entender o presente e planejar os próximos compromissos.

## Positioning

Além do controle financeiro estruturado e offline-first, a assistente Hope consulta os dados do usuário e prepara ações por texto ou voz, sempre pedindo confirmação antes de gravar alterações.

## Operating Context

O uso combina lançamentos cotidianos, conferência mensal, planejamento por categoria, acompanhamento de faturas e compromissos, importação de extratos e consultas rápidas à Hope. O app sincroniza dados com a API quando há conexão e mantém uma base local por usuário.

## Capabilities and Constraints

- Dashboard mensal com saldos, receitas, despesas, previsões, agenda e fluxo de caixa.
- Lançamentos realizados ou previstos, recorrência, parcelamento, categorias e divisões por categoria.
- Contas, cartões e faturas; orçamento por categoria; metas; dívidas; investimentos.
- Importação e conciliação de extratos.
- Assistente Hope por texto e voz, com propostas de escrita confirmadas pelo usuário.
- Compartilhamento de conta com permissões e conexões externas via MCP.
- Modo claro e escuro, armazenamento local offline-first, sincronização e bloqueio biométrico quando suportado.
- Aplicativo Flutter para iOS, Android e Web, com API Node.js/Express e MySQL em produção.
- Páginas públicas de marketing e suporte devem funcionar sem autenticação no mesmo domínio da versão Web.
- Solicitações públicas de suporte são enviadas pela API e dependem da configuração SMTP e de destinatário no ambiente do servidor.

## Brand Commitments

O nome é HopeCash, produto da NewHope. A voz é clara, acolhedora e responsável, sem promessas financeiras exageradas. A identidade existente usa azul-petróleo profundo, verde-esperança, superfícies legíveis e linguagem visual de acompanhamento financeiro. A assinatura confirmada é “Organize hoje. Conquiste amanhã.”

## Evidence on Hand

- Interface e componentes reais em `app/lib/presentation/`.
- Tokens e temas em `app/lib/core/design_system/design_tokens.dart` e `app/lib/core/theme/app_theme.dart`.
- Ícones públicos em `app/web/icons/`.
- Capturas reais do app com dados demonstrativos em `store-assets/app-store-connect/`.
- Documentação técnica e de produto em `README.md` e `docs/`.
- Não há depoimentos, números de clientes, prêmios, preços ou métricas comerciais confirmadas; páginas públicas não devem inventá-los.

## Product Principles

- Mostrar a situação financeira com clareza antes de pedir ação.
- Transformar registro cotidiano em planejamento útil.
- Manter o usuário no controle de qualquer alteração sugerida por IA.
- Continuar útil com conexão instável e sincronizar com segurança depois.
- Explicar recursos financeiros em linguagem direta e acessível.

## Accessibility & Inclusion

As interfaces devem preservar contraste de texto, foco visível, navegação por teclado, alvos de toque adequados, redução de movimento e composição responsiva para telefone, tablet e desktop.
