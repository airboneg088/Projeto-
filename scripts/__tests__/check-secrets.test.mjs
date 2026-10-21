// Autoteste do scripts/check-secrets.mjs (R2-APP-05): monta árvores mínimas numa pasta temporária
// e confere que cada forma conhecida de vazar a chave secreta faz o script falhar (exit 1).
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

const SCRIPT = resolve(dirname(fileURLToPath(import.meta.url)), "../check-secrets.mjs");
const SECRET = "sb_secret_valor-de-teste-do-autoteste-0123456789";

const BASE = {
  "src/lib/supabase/admin.ts": `import "server-only";\nimport { getServerEnv } from "@/lib/env.server";\nexport const k = () => getServerEnv().SUPABASE_SECRET_KEY;\n`,
  "src/lib/env.server.ts": `import "server-only";\nexport const getServerEnv = () => ({ SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY ?? "" });\n`,
  "src/lib/auth/admin-login.server.ts": `import "server-only";\nimport { k } from "@/lib/supabase/admin";\nexport const f = () => k();\n`,
  "src/app/page.tsx": `import { Botao } from "./botao";\nexport default function Page() { return <Botao />; }\n`,
  "src/app/botao.tsx": `"use client";\nexport function Botao() { return <button>ok</button>; }\n`,
  "next.config.ts": `const config = { poweredByHeader: false };\nexport default config;\n`,
};

const roots = [];

function tree(files) {
  const root = mkdtempSync(join(tmpdir(), "check-secrets-"));
  roots.push(root);
  for (const [path, content] of Object.entries({ ...BASE, ...files })) {
    if (content === null) continue;
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), content);
  }
  return root;
}

function run(root, env = {}) {
  const clean = { PATH: process.env.PATH, HOME: process.env.HOME, ...env };
  const result = spawnSync(process.execPath, [SCRIPT, "--root", root], {
    env: clean,
    encoding: "utf8",
  });
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("check-secrets", () => {
  it("passa numa árvore limpa", () => {
    const { status, output } = run(tree({}));
    expect(output).toContain("[check:secrets] ok");
    expect(status).toBe(0);
  });

  it("pega o vazamento A do revisor: env no next.config + SUPABASE_SERVICE_ROLE_KEY no cliente", () => {
    const { status, output } = run(
      tree({
        "next.config.ts": `export default { env: { SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SECRET_KEY } };\n`,
        "src/app/vaza.tsx": `"use client";\nexport const v = process.env.SUPABASE_SERVICE_ROLE_KEY;\n`,
      }),
    );
    expect(status).toBe(1);
    expect(output).toContain("next.config.ts tem bloco `env`");
    expect(output).toMatch(/src\/app\/vaza\.tsx:2 contém "SERVICE_ROLE"/);
    expect(output).toMatch(/next\.config\.ts:1 contém "SECRET_KEY"/);
  });

  it.each([
    ["service_role", `export const r = "service_role";\n`],
    ["Service-Role", `export const r = "Service-Role";\n`],
    ["supabaseSecretKey", `export const supabaseSecretKey = 1;\n`],
    ["SECRETKEY", `export const SECRETKEY = 1;\n`],
  ])("nome de segredo sem diferenciar maiúsculas: %s", (_name, code) => {
    const { status, output } = run(tree({ "src/lib/qualquer.ts": code }));
    expect(status).toBe(1);
    expect(output).toContain("src/lib/qualquer.ts:1 contém");
  });

  it("pega o vazamento C do revisor: Server Component lê env.server e passa ao cliente", () => {
    const { status, output } = run(
      tree({
        "src/app/page.tsx": `import { getServerEnv } from "@/lib/env.server";\nimport { Botao } from "./botao";\nexport default function Page() { return <Botao k={getServerEnv()} />; }\n`,
      }),
    );
    expect(status).toBe(1);
    expect(output).toContain("src/app/page.tsx importa src/lib/env.server.ts");
  });

  it("admin.ts só em módulos *.server.ts com server-only", () => {
    const page = run(
      tree({
        "src/app/page.tsx": `import { k } from "@/lib/supabase/admin";\nexport default function Page() { return <p>{String(k)}</p>; }\n`,
      }),
    );
    expect(page.status).toBe(1);
    expect(page.output).toContain("src/app/page.tsx importa src/lib/supabase/admin.ts");

    const noGuard = run(
      tree({
        "src/lib/auth/admin-login.server.ts": `import { k } from "@/lib/supabase/admin";\nexport const f = () => k();\n`,
      }),
    );
    expect(noGuard.status).toBe(1);
    expect(noGuard.output).toContain("src/lib/auth/admin-login.server.ts importa");
  });

  // R4-APP-01: formas de importar que o regex antigo não reconhecia (D103)
  it.each([
    [
      "identificador com $",
      `import { createAdminClient as $admin } from "@/lib/supabase/admin";\nexport default function Page() { return <p>{String($admin)}</p>; }\n`,
    ],
    [
      "comentário dentro das chaves",
      `import { k /* x */ } from "@/lib/supabase/admin";\nexport default function Page() { return <p>{String(k)}</p>; }\n`,
    ],
    [
      "import() com template literal",
      "export default async function Page() { const m = await import(`@/lib/supabase/admin`); return <p>{String(m.k)}</p>; }\n",
    ],
    [
      "require",
      `const { k } = require("@/lib/supabase/admin");\nexport default function Page() { return <p>{String(k)}</p>; }\n`,
    ],
    [
      "import x = require",
      `import admin = require("@/lib/supabase/admin");\nexport default function Page() { return <p>{String(admin.k)}</p>; }\n`,
    ],
    ["export * from", `export * from "@/lib/supabase/admin";\n`],
  ])("página que importa admin.ts com %s é recusada", (_name, code) => {
    const { status, output } = run(tree({ "src/app/page.tsx": code }));
    expect(status).toBe(1);
    expect(output).toContain("src/app/page.tsx importa src/lib/supabase/admin.ts");
  });

  it("import() com argumento que não é texto fixo é recusado", () => {
    const { status, output } = run(
      tree({
        "src/app/page.tsx":
          'const alvo = "@/lib/supabase/" + "admin";\nexport default async function Page() { const m = await import(alvo); return <p>{String(m)}</p>; }\n',
      }),
    );
    expect(status).toBe(1);
    expect(output).toContain("src/app/page.tsx:2 importa com argumento que não é texto fixo");
  });

  it("import type de admin.ts não conta (não vai para o bundle)", () => {
    const { status, output } = run(
      tree({
        "src/app/page.tsx": `import type { k } from "@/lib/supabase/admin";\nexport type K = typeof k;\nexport default function Page() { return <p>ok</p>; }\n`,
      }),
    );
    expect(output).toContain("[check:secrets] ok");
    expect(status).toBe(0);
  });

  it("cliente que chega ao admin por outro arquivo", () => {
    const { status, output } = run(
      tree({
        "src/app/botao.tsx": `"use client";\nimport { f } from "@/lib/ponte";\nexport function Botao() { return <button>{String(f)}</button>; }\n`,
        "src/lib/ponte.ts": `export { f } from "@/lib/auth/admin-login.server";\n`,
      }),
    );
    expect(status).toBe(1);
    expect(output).toContain("código de cliente importa src/lib/supabase/admin");
  });

  it("valor da chave em qualquer arquivo do build (static ou server)", () => {
    for (const path of [".next/static/chunks/x.js", ".next/server/app/login.html"]) {
      const { status, output } = run(tree({ [path]: `var k="${SECRET}";` }), {
        SUPABASE_SECRET_KEY: SECRET,
      });
      expect(status, path).toBe(1);
      expect(output).toContain(`${path} contém o valor da chave secreta`);
    }
  });

  it("valor lido do .env.local e .next/cache fora da varredura", () => {
    const root = tree({
      ".env.local": `SUPABASE_SECRET_KEY=${SECRET}\n`,
      ".next/cache/x": SECRET,
      ".next/static/ok.js": "console.log(1)",
    });
    expect(run(root).status).toBe(0);
  });

  it("nome da variável secreta no código do navegador", () => {
    const { status, output } = run(
      tree({ ".next/static/chunks/y.js": "process.env.SUPABASE_SERVICE_ROLE_KEY" }),
      { SUPABASE_SECRET_KEY: SECRET },
    );
    expect(status).toBe(1);
    expect(output).toContain("cita SUPABASE_SERVICE_ROLE_KEY");
  });

  it("build sem o valor da chave: aviso fora de CI, erro em CI", () => {
    const root = tree({ ".next/static/ok.js": "console.log(1)" });
    const local = run(root);
    expect(local.status).toBe(0);
    expect(local.output).toContain("aviso");
    const ci = run(root, { CI: "true" });
    expect(ci.status).toBe(1);
    expect(ci.output).toContain("em CI é obrigatório");
  });

  it("variável NEXT_PUBLIC_ com nome de segredo", () => {
    const { status, output } = run(tree({ ".env.production": "NEXT_PUBLIC_SERVICE_X=1\n" }));
    expect(status).toBe(1);
    expect(output).toContain("NEXT_PUBLIC_SERVICE_X");
  });
});
