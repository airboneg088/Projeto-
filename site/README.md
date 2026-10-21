# Éde Gestão — site

Versão em site (link do claude.ai) do Éde Gestão. Cada loja (Primavera, Castro Alves, Parque América) tem o seu portal: a equipe da loja, o quadro de tarefas e as aprovações. Os dados ficam no banco do próprio artifact e são compartilhados por todos que abrem o link (pessoas da organização no claude.ai com acesso de Contribuidor ou mais).

- Publicado em: https://claude.ai/artifact/CmvnWFnFwwWfmN36J6iSeL
- `index.html`: o site inteiro (HTML, CSS e JavaScript, sem build).
- `img/`: logo da Éde (brand book).
- `seed/`: configuração inicial gravada no banco — `org.json` (`config/org`), `rotinas.json` (`config/rotinas`: 8 diárias e 4 do mês) e `portais.json` (`portais/<loja>`: funcionários de exemplo e quem faz cada rotina por padrão). Nomes com “(exemplo)” são fictícios.
- `teste/run.mjs`: teste ponta a ponta com uma simulação local da plataforma (`node site/teste/run.mjs`; precisa do ffmpeg; `CHROME_PATH` se o Playwright não achar o navegador).

## Como funciona

1. Escolhe o portal da loja e depois “Quem está usando?” (o nome do funcionário ou Gerência).
2. Gerência: no **Quadro**, cada coluna é uma pessoa; arrasta o cartão para quem vai fazer (no celular, segura o cartão um instante e arrasta) ou toca no cartão e escolhe. Alterna entre **Diárias de hoje** e **Do mês**. **Nova tarefa** cria uma avulsa. **Aprovar** mostra fotos e vídeos enviados; aprova ou pede correção com motivo. **Equipe** cadastra funcionários e o PIN da gerência. **Mais › Rotinas** define quem faz cada rotina por padrão.
3. Funcionário: vê as tarefas dele (hoje e do mês), começa, marca os itens, tira foto ou grava vídeo e envia para aprovação.

## Dados no banco

| Caminho | O que guarda |
|---|---|
| `config/org`, `config/rotinas` | lojas, setores e rotinas (só a proprietária altera) |
| `portais/<loja>` | funcionários, responsável padrão por rotina e o hash do PIN |
| `diarias/<loja>_<AAAA-MM-DD>` | tarefas do dia (criadas sozinhas a partir das rotinas) |
| `mensais/<loja>_<AAAA-MM>` | tarefas do mês |
| `midias/<id>` (+ `partes/<n>`) | foto ou vídeo de cada envio; o arquivo vai para o armazenamento do site quando a conta pode enviar, senão fica no banco (vídeo reduzido e em partes) |

Limites conhecidos: o PIN evita engano no aparelho da loja, mas não é senha forte (quem tem acesso ao link consegue ler o banco). O banco aceita até 25 mil documentos; com o uso diário, as mídias antigas vão precisar de limpeza periódica.

O sistema completo (Next.js + Supabase, com RLS e testes) continua neste repositório para quando a operação precisar de produção própria.
