# Éde Gestão — site

Versão em site (link do claude.ai) do Éde Gestão: tarefas do dia com checklist e foto, aprovação do gerente e painel das 3 lojas. Os dados ficam no banco do próprio artifact e são compartilhados por todos que abrem o link (pessoas da organização no claude.ai).

- Publicado em: https://claude.ai/artifact/CmvnWFnFwwWfmN36J6iSeL
- `index.html`: o site inteiro (HTML, CSS e JavaScript, sem build).
- `img/`: logo da Éde (brand book).
- `seed/`: configuração inicial gravada no banco (`config/org`, `config/rotinas`, `config/pessoas`). Rotinas e setores são os provisórios do projeto; pessoas `demo-*` são só para demonstração.
- `teste/run.mjs`: teste ponta a ponta com uma simulação local da plataforma (`node site/teste/run.mjs`, com `CHROME_PATH` se precisar).

O sistema completo (Next.js + Supabase, com RLS e testes) continua neste repositório para quando a operação precisar de produção própria.
