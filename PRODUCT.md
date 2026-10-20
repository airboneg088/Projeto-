# Éde Gestão — Contexto de produto

> Fonte de verdade do **porquê** e **para quem**. Decisões visuais ficam em `DESIGN.md` (Fase 2).
> Decisões técnicas reversíveis ficam em `docs/decisoes.md`.

## 1. O que é

Plataforma interna da **Éde Utilidades** (rede de 3 lojas de utilidades domésticas: **Primavera**, **Castro Alves** e **Parque América**; fuso `America/Sao_Paulo`) para controlar a execução das tarefas operacionais das lojas: abertura, salão, precificação, reposição, estoque, caixa, limpeza e fechamento.

**Princípio central:** uma tarefa só está concluída quando cumpre os critérios definidos para ela, inclusive a aprovação do gerente quando exigida. `Aguardando aprovação` nunca conta como concluída.

## 2. Problema que resolve

| Hoje | Com o Éde Gestão |
|---|---|
| Cobrança por WhatsApp, perdida no meio de conversas | Tarefa com responsável, janela e prazo; o sistema avisa e escala sozinho |
| Planilhas preenchidas depois, de memória | Execução registrada na hora, item a item |
| Tarefa "feita" sem prova | Foto tirada ao vivo, com horário do servidor, GPS quando permitido e marca d'água |
| Nenhuma visão consolidada das 3 lojas | Painel da proprietária com indicadores ponderados e drill-down até a foto |

## 3. Usuários e cenas de uso

~20–40 pessoas.

| Papel | Quem | Onde e como usa | O que precisa resolver em segundos |
|---|---|---|---|
| `staff` (colaborador) | Equipe de loja | **Celular**, PWA instalado. Em pé no corredor ou no estoque, uma mão ocupada, luz forte, pressa, **internet ruim ou ausente** | "O que eu tenho que fazer agora?" e "Enviei? Foi aceito?" |
| `manager` (gerente) | 1 por loja | Celular durante o expediente; computador às vezes | Aprovar ou reprovar rápido, com a foto grande ao lado da imagem de referência. Ver o dia da loja por setor |
| `owner` (proprietária) | Dona da rede | Computador e celular | Comparar as 3 lojas com justiça, achar falhas recorrentes, descer até a tarefa e a foto |
| `admin` | Suporte técnico | Computador | Configurar lojas, setores, usuários, vínculos, retenção. Lê dados operacionais apenas em modo leitura, com registro em auditoria |

## 4. Diferenciais obrigatórios

Pesquisa com 13 concorrentes (SULTS, Checkey, Forhold, Tasa, Vitrine etc.) mostrou que o mercado entrega mal:

1. **Evidência confiável** — foto ao vivo, carimbo de data/hora do **servidor**, GPS registrado, marca d'água, bloqueio de foto repetida (sha256) e alerta de foto parecida (phash).
2. **Ciclo explícito** — aprovar → reprovar com justificativa → reexecutar, com histórico de cada tentativa.
3. **Indicadores justos** — aprovação na 1ª tentativa, tempo até aprovação, falhas recorrentes e comparação entre lojas **ponderada por peso/complexidade**, sempre ao lado do volume. Nunca ranking por contagem bruta.
4. **Janela de execução** — "abertura entre 07:30 e 08:15", não só um prazo final.

## 5. Princípios de produto

1. **O banco protege, não a interface.** RLS em todas as tabelas antes de qualquer tela. Uma loja não enxerga a outra.
2. **Concluída é concluída.** Só `approved` conta como concluída. `submitted` aparece como "Aguardando aprovação".
3. **Histórico nunca se perde.** Evidências, revisões e auditoria são imutáveis. Transferência entre lojas encerra um vínculo e abre outro.
4. **O sistema registra, não pune.** Não há medida disciplinar automática. Os textos não tratam o registro como prova incontestável.
5. **Justiça nos números.** Toda comparação é ponderada e mostrada junto do volume atribuído.
6. **Offline é o caso normal, não a exceção**, para quem executa.
7. **Menos motion.** Uso diário e repetitivo pede menos animação, não mais.

## 6. Modos de interface

| Superfície | Modo | Implicação |
|---|---|---|
| App (colaborador, gerente, proprietária, admin, relatórios) | **Operate** | Escaneabilidade, consistência e o cenário real vencem a expressão. A marca vive nos detalhes precisos |
| Páginas públicas (login, recuperação de senha, política de privacidade, termos) | **Read**, com cuidado de apresentação | Únicas superfícies onde vale `/design-taste-frontend` |

## 7. Vocabulário (interface ↔ banco)

| Interface (pt-BR) | Status no banco | Significado |
|---|---|---|
| Pendente | `pending` | Gerada, ainda não iniciada |
| Em andamento | `in_progress` | Tentativa aberta |
| Aguardando aprovação | `submitted` | Enviada; **não** está concluída |
| Aprovada | `approved` | Concluída (manual ou auto-aprovada) |
| Correção solicitada | `rejected` | Reprovada com motivo; espera nova tentativa |
| Atrasada | `overdue` | Venceu sem envio; ainda pode ser executada |
| Cancelada | `cancelled` | Cancelada por gerente/proprietária, com motivo |

Status sempre com **cor + ícone + texto**, nunca só cor.

Outros termos: **rotina** = modelo (`task_templates`); **agendamento** = recorrência (`schedules`); **tentativa** = cada execução enviada (`task_attempts`); **evidência** = foto (`evidences`); **janela** = intervalo permitido de execução.

## 8. Escopo do MVP

Dentro: login e recuperação de senha; "Hoje" do colaborador com execução, câmera e envio offline; fila de aprovação do gerente; tarefas avulsas, rotinas e agendamentos; painel da proprietária com indicadores e drill-down; relatórios diário, semanal e mensal com exportação CSV e Excel; notificações in-app e e-mail; administração (lojas, setores, usuários, vínculos/transferências, retenção, LGPD).

Fora desta versão: push, WhatsApp (interface de canal pronta, sem implementar), IA de imagem, BI customizável, chat interno, universidade corporativa, bloqueio por raio de GPS.

## 9. Restrições

- **Plataforma:** web, PWA instalável. Mobile first em 390px; desktop validado em 1440px.
- **Rede:** o fluxo do colaborador funciona sem internet e sincroniza sem duplicar.
- **Tempo:** banco em `timestamptz` (UTC); exibição no fuso da loja. O horário do servidor é a verdade.
- **LGPD:** coletar só o necessário; retenção de fotos configurável (padrão 180 dias); canal do titular; auditoria de ações sensíveis.
- **Segurança:** `service_role` nunca no cliente; signed URLs de no máximo 5 minutos; headers de segurança; rate limit no login.

## 10. Anti-referências

- **De processo:** cobrança no WhatsApp, planilha preenchida no fim do dia, "feito" sem prova, ranking de quem fez mais.
- **Visuais:** gradientes decorativos, glassmorphism, cards idênticos com ícone no topo, emoji na interface, sombra em elemento em repouso, rótulos minúsculos em caixa-alta espaçada, spinner de página inteira, animação de entrada em gráfico.

## 11. Identidade visual

**Pendente.** Aguardando logo, cores e fonte oficiais da Éde Utilidades. Sem material oficial, serão propostas de 2 a 3 direções de tokens para escolha antes de definir cores e tipografia (registro em `DESIGN.md`).

## 12. Como saberemos que deu certo

- **Adoção:** % das tarefas operadas pela plataforma (meta do piloto na Primavera a definir com a proprietária).
- **Qualidade:** % aprovadas na 1ª tentativa subindo; itens críticos reprovados caindo.
- **Agilidade:** tempo médio entre envio e revisão do gerente.
- **Fim da cobrança informal:** gerentes deixam de cobrar tarefas pelo WhatsApp.
