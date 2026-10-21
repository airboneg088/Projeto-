# Éde Gestão

Plataforma interna da Éde Utilidades para controlar a execução das tarefas operacionais das lojas Primavera, Castro Alves e Parque América.

Status: **Fase 1 — Fundação** (entregue, aguardando aprovação).

A Fase 1 entrega o critério C1 da base: banco completo (migrations com RLS em todas as tabelas, máquina de estados, auditoria append-only, storage privado, indicadores, seed com as 3 lojas e 8 rotinas), testes pgTAP de isolamento e regras, login e recuperação de senha, sessão em cookie HttpOnly, layout por papel e cabeçalhos de segurança (CSP, HSTS). As áreas `/hoje`, `/gerente`, `/painel` e `/admin` ainda são telas provisórias: o conteúdo entra a partir da Fase 2.

## Como rodar

```bash
pnpm install
pnpm stack:up        # Supabase local sem Docker; gera o .env.local
pnpm dev             # app em http://localhost:3000 (usuários do seed em docs/dev-local.md)
pnpm verify          # lint + typecheck + testes + check:secrets + testes do banco
pnpm build && pnpm test:e2e   # E2E (Playwright) contra o build de produção
ENABLE_PROTOTYPES=1 pnpm dev  # catálogo de componentes em /prototipo/componentes
```

Detalhes (stack local, comandos do banco, usuários de exemplo, diferenças para o hospedado) em [docs/dev-local.md](docs/dev-local.md).

| Documento | Conteúdo |
|---|---|
| [PRODUCT.md](PRODUCT.md) | Contexto de produto: usuários, problema, princípios, escopo |
| [DESIGN.md](DESIGN.md) | Design system do app: marca, tokens, status, tipografia, motion, componentes, voz |
| [docs/plano-de-fases.md](docs/plano-de-fases.md) | Fases 0–8 com critérios de aceite |
| [docs/modelo-de-dados.md](docs/modelo-de-dados.md) | Diagrama ER, máquina de estados, RLS, indicadores |
| [docs/decisoes.md](docs/decisoes.md) | Decisões tomadas e pendentes; riscos aceitos e adiados |
| [docs/dev-local.md](docs/dev-local.md) | Como rodar o projeto localmente e testar |
| [AGENTS.md](AGENTS.md) | Regras de segurança do código (para pessoas e agentes) |
| [docs/diagramas/](docs/diagramas/) | Diagramas renderizados em PNG |
