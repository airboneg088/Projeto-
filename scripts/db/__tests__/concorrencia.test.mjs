/**
 * Regressões de concorrência nas RPCs de execução:
 *   - R1-FI-06: foto, resposta e envio da mesma tentativa ao mesmo tempo não geram deadlock;
 *   - R2-FUNC-03: o mesmo registro de foto (client_mutation_id) chegando duas vezes ao mesmo
 *     tempo devolve a mesma evidência, não 'duplicate_photo';
 *   - R2-FUNC-04: quem deixou de ser o responsável enquanto esperava a trava não inicia a tarefa;
 *   - R2-REGRAS-S6: nem envia (a tentativa dele é encerrada sem envio e o novo responsável inicia);
 *   - R3-FUNCOES-03: a reatribuição numa transação que começou antes de a tentativa ser iniciada
 *     (inclusive um PATCH em lote que esperou trava) encerra a tentativa com o relógio real;
 *   - R4-INTEGRIDADE-01: o início no meio de uma mudança de vínculo ou perfil espera o commit e
 *     recebe 'forbidden' (não fica tentativa aberta de quem saiu);
 *   - R4-INTEGRIDADE-03: incluir item na rotina enquanto a 1ª tarefa é gerada não deixa dois
 *     checklists diferentes na mesma versão.
 *
 * Os cenários precisam de dados commitados e de várias sessões (dblink), então não cabem na
 * suíte pgTAP (cada arquivo roda numa transação desfeita no fim). Aqui o teste cria um banco
 * descartável a partir do template da stack local (migrations, sem seed), roda cada
 * scripts/db/concorrencia/*.sql e apaga o banco.
 *
 * Sem a stack local (CI sem Postgres), o teste é pulado.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const PSQL = path.join(process.env.PG_BIN ?? "/usr/lib/postgresql/16/bin", "psql");
const DB = "concorrencia_check";
const PG_ENV = {
  ...process.env,
  PGHOST: "127.0.0.1",
  PGPORT: "54322",
  PGUSER: "postgres",
  PGPASSWORD: "postgres",
  PGCONNECT_TIMEOUT: "3",
};

const SCENARIOS = [
  {
    file: "deadlock-evidencia-envio.sql",
    title: "foto, resposta e envio da mesma tentativa ao mesmo tempo não geram deadlock",
  },
  {
    file: "reenvio-concorrente-da-foto.sql",
    title: "o mesmo registro de foto chegando duas vezes ao mesmo tempo devolve a mesma evidência",
  },
  {
    file: "inicio-depois-de-reatribuir.sql",
    title: "quem deixou de ser o responsável enquanto esperava a trava não inicia a tarefa",
  },
  {
    file: "envio-depois-de-reatribuir.sql",
    title: "quem deixou de ser o responsável enquanto esperava a trava não envia a tarefa",
  },
  {
    file: "passagem-em-transacao-antiga.sql",
    title:
      "reatribuição numa transação iniciada antes da tentativa encerra a tentativa (não falha)",
  },
  {
    file: "inicio-durante-mudanca-de-vinculo.sql",
    title:
      "início durante o fim do vínculo, a troca de setor ou a desativação não deixa tentativa aberta",
  },
  {
    file: "versao-da-rotina-em-corrida.sql",
    title: "item incluído enquanto a 1ª tarefa é gerada não deixa dois checklists na mesma versão",
  },
];

function psql(db, args) {
  return spawnSync(PSQL, ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", db, ...args], {
    env: PG_ENV,
    encoding: "utf8",
  });
}

const stackUp =
  existsSync(PSQL) &&
  psql("template1", [
    "-Atc",
    "select 1 from pg_database where datname = 'ede_template'",
  ]).stdout?.trim() === "1";

describe.skipIf(!stackUp)("concorrência nas RPCs de execução (banco descartável)", () => {
  beforeAll(() => {
    const reset = spawnSync("bash", [path.join(ROOT, "scripts/db/reset.sh")], {
      env: {
        ...process.env,
        DB_NAME: DB,
        SEED_FILE: path.join(tmpdir(), "sem-seed-concorrencia.sql"),
      },
      encoding: "utf8",
    });
    expect(reset.status, reset.stderr).toBe(0);
  }, 120_000);

  afterAll(() => {
    psql("template1", ["-c", `drop database if exists ${DB} with (force)`]);
  });

  for (const scenario of SCENARIOS) {
    it(
      scenario.title,
      () => {
        const file = path.join(ROOT, "scripts/db/concorrencia", scenario.file);
        const planned = Number(/select plan\((\d+)\)/.exec(readFileSync(file, "utf8"))?.[1]);
        const run = psql(DB, ["-At", "-f", file]);
        const output = `${run.stdout}${run.stderr}`;
        expect(run.status, output).toBe(0);
        expect(output).not.toMatch(/^not ok/m);
        expect(output.match(/^ok \d+/gm)?.length, output).toBe(planned);
      },
      120_000,
    );
  }
});
