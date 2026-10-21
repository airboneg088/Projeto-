import type { Metadata } from "next";
import type { ReactNode } from "react";

import { AppHeader } from "@/components/app-shell";
import { LogoHorizontal } from "@/components/brand/logo";
import {
  IconCamera,
  IconCloudUpload,
  IconListChecks,
  IconNote,
  IconRetry,
} from "@/components/icons";
import { ThemeToggle } from "@/components/theme-toggle";
import { BottomActionBar } from "@/components/ui/bottom-action-bar";
import { Button } from "@/components/ui/button";
import { ChecklistItem } from "@/components/ui/checklist-item";
import { EmptyState } from "@/components/ui/empty-state";
import { Notice } from "@/components/ui/notice";
import { OfflineBanner } from "@/components/ui/offline-banner";
import { PhotoCapture } from "@/components/ui/photo-capture";
import { Skeleton, TaskCardSkeleton, TaskListSkeleton } from "@/components/ui/skeleton";
import { StatusBadge } from "@/components/ui/status-badge";
import { SubmitButton } from "@/components/ui/submit-button";
import { TaskCard } from "@/components/ui/task-card";
import { TextArea, TextField } from "@/components/ui/text-field";
import { contrastRatio, formatRatio } from "@/lib/design/contrast";
import { COLORS, type ColorRole, STATUS, STATUS_KEYS, type ThemeName } from "@/lib/design/tokens";
import { assertPrototypesEnabled } from "@/lib/dev/prototypes";

import { FOTO_ALT, FOTO_EXEMPLO, PESSOA, ROTINAS, TAREFAS } from "../_fixtures";
import { ChecklistDemo, ReasonDialogDemo, SubmitDemo } from "./demos";

export function generateMetadata(): Metadata {
  assertPrototypesEnabled();
  return { title: "Catálogo de componentes" };
}

const SECTIONS = [
  ["cores", "Cores"],
  ["tipografia", "Tipografia"],
  ["botoes", "Botões"],
  ["status", "Status"],
  ["cartao", "Cartão de tarefa"],
  ["lista", "Lista: estados"],
  ["checklist", "Checklist"],
  ["foto", "Foto"],
  ["vazio", "Estado vazio"],
  ["esqueleto", "Esqueleto"],
  ["conexao", "Conexão"],
  ["campos", "Avisos e campos"],
  ["dialog", "Dialog de motivo"],
  ["casca", "Cabeçalho e barra de ação"],
] as const;

function ThemeFrame({ theme, children }: { theme: ThemeName; children: ReactNode }) {
  return (
    <div
      className={`${theme} min-w-0 rounded-l border border-border bg-bg p-4 text-text sm:p-5`}
      data-theme-frame={theme}
    >
      <p className="mb-4 type-meta text-text-muted">
        {theme === "light" ? "Tema claro" : "Tema escuro"}
      </p>
      {children}
    </div>
  );
}

function Section({
  id,
  title,
  description,
  children,
}: {
  id: string;
  title: string;
  description: string;
  children: ReactNode | ((theme: ThemeName) => ReactNode);
}) {
  const render = (theme: ThemeName) =>
    typeof children === "function" ? children(theme) : children;
  return (
    <section id={id} aria-labelledby={`${id}-titulo`} className="flex scroll-mt-4 flex-col gap-4">
      <div>
        <h2 id={`${id}-titulo`} className="type-title-2 text-text">
          {title}
        </h2>
        <p className="mt-1 max-w-prose text-text-muted">{description}</p>
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        <ThemeFrame theme="light">{render("light")}</ThemeFrame>
        <ThemeFrame theme="dark">{render("dark")}</ThemeFrame>
      </div>
    </section>
  );
}

function Label({ children }: { children: ReactNode }) {
  return <p className="mb-2 type-meta text-text-muted">{children}</p>;
}

const SWATCHES: ColorRole[] = [
  "bg",
  "surface",
  "surface-muted",
  "surface-pressed",
  "text",
  "text-muted",
  "brand",
  "accent",
  "accent-text",
  "focus",
  "border",
  "border-control",
  "danger",
  "danger-text",
  "success",
  "inverse",
];

function ColorSwatches({ theme }: { theme: ThemeName }) {
  return (
    <div className="flex flex-col gap-5">
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {SWATCHES.map((role) => (
          <li key={role} className="flex flex-col gap-1.5">
            <span
              className="h-12 rounded-s border border-border"
              style={{ background: `var(--${role})` }}
            />
            <span className="type-meta text-text">{role}</span>
            <span className="-mt-1.5 type-meta tabular-nums text-text-muted">
              {COLORS[role][theme]}
            </span>
          </li>
        ))}
      </ul>
      <div>
        <Label>Status: contraste do texto sobre o fundo</Label>
        <ul className="flex flex-col gap-2">
          {STATUS_KEYS.map((key) => (
            <li key={key} className="flex items-center justify-between gap-3">
              <StatusBadge status={key} />
              <span className="type-meta tabular-nums text-text-muted">
                {formatRatio(contrastRatio(STATUS[key][theme].fg, STATUS[key][theme].bg))}:1
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export default function ComponentesPage() {
  assertPrototypesEnabled();

  return (
    <div className="min-h-dvh">
      <header className="bg-surface">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3">
          <LogoHorizontal priority />
          <ThemeToggle />
        </div>
      </header>

      <main className="mx-auto flex max-w-7xl flex-col gap-12 px-4 pt-8 pb-16">
        <div className="flex flex-col gap-4">
          <h1 className="type-title-1 text-text">Catálogo de componentes</h1>
          <Notice tone="info">
            Protótipo da Fase 2: todos os dados são de exemplo ([EXEMPLO]). Esta página só existe
            com ENABLE_PROTOTYPES=1. Cada componente aparece nos temas claro e escuro.
          </Notice>
          <nav aria-label="Seções do catálogo">
            <ul className="flex flex-wrap gap-x-4">
              {SECTIONS.map(([id, label]) => (
                <li key={id}>
                  <a className="link" href={`#${id}`}>
                    {label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </div>

        <Section
          id="cores"
          title="Cores"
          description="Papéis de cor derivados do manual da marca. Valores em src/lib/design/tokens.ts."
        >
          {(theme) => <ColorSwatches theme={theme} />}
        </Section>

        <Section
          id="tipografia"
          title="Tipografia"
          description="Bitter só em títulos curtos e números; Figtree em tudo que se lê. Texto corrido com 16px ou mais."
        >
          <div className="flex flex-col gap-4">
            <div>
              <Label>type-title-1 · Bitter 800</Label>
              <p className="type-title-1">Abertura da loja</p>
            </div>
            <div>
              <Label>type-title-2 · Bitter 800</Label>
              <p className="type-title-2">Salão de vendas</p>
            </div>
            <div className="flex gap-8">
              <div>
                <Label>type-kpi · Bitter 900</Label>
                <p className="type-kpi">92%</p>
              </div>
              <div>
                <Label>type-counter</Label>
                <p className="type-counter">3</p>
              </div>
            </div>
            <div>
              <Label>type-lead · Figtree 600</Label>
              <p className="type-lead">Corredores livres, sem caixas no caminho</p>
            </div>
            <div>
              <Label>type-body · Figtree 400</Label>
              <p className="type-body">
                Faça na ordem: alarme, luzes e equipamentos, conferência do salão e abertura das
                portas. Fotografe os itens indicados.
              </p>
            </div>
            <div>
              <Label>type-meta · Figtree 500 (nunca parágrafo)</Label>
              <p className="type-meta tabular-nums text-text-muted">
                07:30–08:15 · Salão de vendas
              </p>
            </div>
          </div>
        </Section>

        <Section
          id="botoes"
          title="Botões"
          description="Alvo de 44px ou mais, escala 0.97 ao pressionar, hover só com mouse."
        >
          <div className="flex flex-col gap-5">
            <div>
              <Label>Variantes</Label>
              <div className="flex flex-wrap gap-2">
                <Button>Iniciar tarefa</Button>
                <Button variant="secondary">Ver instruções</Button>
                <Button variant="ghost">Agora não</Button>
                <Button variant="danger">Reprovar</Button>
              </div>
            </div>
            <div>
              <Label>Tamanhos: sm 44 · md 48 · lg 56 · ícone 44</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Button size="sm">Pequeno</Button>
                <Button size="md">Médio</Button>
                <Button size="lg">Grande</Button>
                <Button size="icon" variant="secondary" aria-label="Tirar foto">
                  <IconCamera size={22} />
                </Button>
              </div>
            </div>
            <div>
              <Label>Com ícone · carregando · desabilitado</Label>
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary">
                  <IconNote size={20} />
                  Observação
                </Button>
                <Button loading loadingLabel="Entrando…">
                  Entrar
                </Button>
                <Button disabled>Enviar</Button>
              </div>
            </div>
            <div>
              <Label>Envio: Enviar → Enviando… → Enviada (toque para ver)</Label>
              <SubmitDemo />
            </div>
            <div>
              <Label>Os três estados parados</Label>
              <div className="flex flex-col gap-2">
                <SubmitButton type="button" state="idle" />
                <SubmitButton type="button" state="sending" />
                <SubmitButton type="button" state="sent" />
              </div>
            </div>
          </div>
        </Section>

        <Section
          id="status"
          title="Status"
          description="Sempre cor + ícone + texto. Atrasada e correção se destacam pela clareza; pendente e cancelada pelo contorno."
        >
          <div className="flex flex-col gap-4">
            <div className="flex flex-wrap gap-2">
              {STATUS_KEYS.map((key) => (
                <StatusBadge key={key} status={key} />
              ))}
            </div>
            <div className="flex flex-wrap gap-2">
              {STATUS_KEYS.map((key) => (
                <StatusBadge key={key} status={key} size="md" />
              ))}
            </div>
          </div>
        </Section>

        <Section
          id="cartao"
          title="Cartão de tarefa"
          description="Título, janela (números tabulares), status, setor, prioridade e marcador de tarefa crítica. O cartão inteiro é o link."
        >
          <ul className="flex flex-col gap-3">
            {TAREFAS.map((task, index) => (
              <li key={`${task.title}-${task.status}`}>
                <TaskCard {...task} href={index < 7 ? "#cartao" : undefined} />
              </li>
            ))}
          </ul>
        </Section>

        <Section
          id="lista"
          title="Lista: estados"
          description="Toda lista tem carregando (esqueleto), vazia (com orientação), erro (com ação) e sem conexão."
        >
          <div className="flex flex-col gap-6">
            <div>
              <Label>Carregando</Label>
              <TaskListSkeleton count={2} />
            </div>
            <div>
              <Label>Vazia</Label>
              <EmptyState title="Nada pendente agora" icon={IconListChecks}>
                A próxima tarefa é <strong className="text-text">Precificação</strong>, das 10:00 às
                12:00. Ela aparece aqui quando a janela abrir.
              </EmptyState>
            </div>
            <div>
              <Label>Erro</Label>
              <Notice
                tone="error"
                action={
                  <Button variant="secondary" size="sm">
                    <IconRetry size={18} />
                    Tentar de novo
                  </Button>
                }
              >
                Não conseguimos carregar suas tarefas. Confira a internet e toque em Tentar de novo.
              </Notice>
            </div>
            <div className="flex flex-col gap-3">
              <Label>Sem conexão</Label>
              <OfflineBanner status="offline" pending={3} />
              <TaskCard {...TAREFAS[2]!} />
            </div>
          </div>
        </Section>

        <Section
          id="checklist"
          title="Checklist"
          description="Toque na linha para marcar (check desenhado em 180ms). “Não está conforme” pede a observação."
        >
          <div className="flex flex-col gap-6">
            <ChecklistDemo />
            <div>
              <Label>Não conforme sem observação, depois de tentar enviar</Label>
              <ChecklistItem
                text="Portas abertas no horário, com fachada e vitrine limpas"
                value="not_ok"
                note=""
                requiresPhoto
                noteError="Escreva o que não está conforme. Sem isso, a tarefa não pode ser enviada."
              />
            </div>
            <div>
              <Label>Tarefa já enviada (só leitura)</Label>
              <ChecklistItem text="Alarme ativado" value="done" critical disabled />
            </div>
          </div>
        </Section>

        <Section
          id="foto"
          title="Foto"
          description="Casca da captura (a câmera entra na Fase 3): vazia, prévia, enviando, erro e guardada sem conexão."
        >
          <div className="grid gap-6 sm:grid-cols-2">
            <PhotoCapture state="empty" label="Foto do salão limpo" required />
            <PhotoCapture
              state="preview"
              label="Foto do corredor"
              previewSrc={FOTO_EXEMPLO}
              previewAlt={FOTO_ALT}
              capturedAt="07:42"
            />
            <PhotoCapture
              state="uploading"
              label="Foto do corredor"
              previewSrc={FOTO_EXEMPLO}
              previewAlt={FOTO_ALT}
              progress={42}
            />
            <PhotoCapture
              state="error"
              label="Foto do corredor"
              previewSrc={FOTO_EXEMPLO}
              previewAlt={FOTO_ALT}
              capturedAt="07:42"
            />
            <PhotoCapture
              state="queued"
              label="Foto do corredor"
              previewSrc={FOTO_EXEMPLO}
              previewAlt={FOTO_ALT}
              capturedAt="07:42"
            />
          </div>
        </Section>

        <Section
          id="vazio"
          title="Estado vazio"
          description="Diz o que aconteceu e o que fazer. Ação opcional."
        >
          <div className="flex flex-col gap-3">
            <EmptyState
              title="Tudo aprovado por hoje"
              action={<Button variant="secondary">Ver histórico</Button>}
            >
              Nenhuma tarefa esperando você. Amanhã a lista começa com a Abertura, às 07:30.
            </EmptyState>
            <EmptyState title="Nenhuma tarefa para revisar" headingLevel="h3">
              Quando alguém enviar uma tarefa, ela aparece aqui com a foto.
            </EmptyState>
          </div>
        </Section>

        <Section
          id="esqueleto"
          title="Esqueleto"
          description="Pulso de opacidade (parado com movimento reduzido). Nunca spinner de página inteira."
        >
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-2 rounded-m bg-surface p-4">
              <Skeleton className="h-6 w-2/3" />
              <Skeleton className="h-5 w-full" />
              <Skeleton className="h-5 w-5/6" />
            </div>
            <TaskCardSkeleton />
          </div>
        </Section>

        <Section
          id="conexao"
          title="Conexão"
          description="Faixa de conexão: maior contraste da paleta, legível no sol. Online e sem fila, some."
        >
          <div className="flex flex-col gap-3">
            <OfflineBanner status="offline" pending={3} />
            <OfflineBanner status="offline" pending={1} />
            <OfflineBanner status="offline" pending={0} />
            <OfflineBanner status="syncing" pending={3} />
          </div>
        </Section>

        <Section
          id="campos"
          title="Avisos e campos"
          description="Aviso = ícone + texto. Campo com label real; erro diz o que fazer."
        >
          <div className="flex flex-col gap-4">
            <Notice tone="error">E-mail ou senha incorretos. Confira e tente de novo.</Notice>
            <Notice tone="success">Senha alterada. Entre com a nova senha.</Notice>
            <Notice tone="info">A foto é obrigatória nesta etapa. Toque em Tirar foto.</Notice>
            <Notice tone="warning">3 envios aguardando conexão.</Notice>
            <TextField
              id="exemplo-email"
              name="email"
              type="email"
              label="E-mail"
              defaultValue="colaborador1.primavera@exemplo.local"
            />
            <TextField
              id="exemplo-senha"
              name="senha"
              type="password"
              label="Nova senha"
              hint="Pelo menos 8 caracteres, com letras (A a Z) e números."
            />
            <TextField
              id="exemplo-erro"
              name="erro"
              type="email"
              label="E-mail"
              defaultValue="maria@"
              error="Confira o e-mail. Ele precisa ter o formato nome@exemplo.com."
            />
            <TextArea id="exemplo-obs" name="obs" label="Observação (opcional)" />
          </div>
        </Section>

        <Section
          id="dialog"
          title="Dialog de motivo"
          description="Reprovar exige motivo (campo obrigatório, sem “segurar para confirmar”). Toque para abrir."
        >
          <ReasonDialogDemo />
        </Section>

        <Section
          id="casca"
          title="Cabeçalho e barra de ação"
          description="Cabeçalho das áreas logadas e barra inferior fixa (aqui no fluxo) com a ação principal ao alcance do polegar."
        >
          <div className="flex flex-col gap-4">
            <div className="overflow-hidden rounded-m">
              <AppHeader
                name={PESSOA}
                role="Colaborador"
                stores="Primavera"
                areas={["hoje"]}
                current="hoje"
              />
            </div>
            <div className="overflow-hidden rounded-m">
              <AppHeader
                name="[EXEMPLO] Proprietária da rede"
                role="Proprietária"
                stores="Todas as lojas"
                areas={["gerente", "painel"]}
                current="painel"
              />
            </div>
            <BottomActionBar fixed={false} hint={`3 de 5 itens · ${ROTINAS[0].title}`}>
              <Button variant="secondary" size="lg">
                <IconCamera size={22} />
                Foto
              </Button>
              <Button size="lg">
                <IconCloudUpload size={22} />
                Enviar
              </Button>
            </BottomActionBar>
          </div>
        </Section>
      </main>
    </div>
  );
}
