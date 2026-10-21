#!/usr/bin/env node
// Gera o ambiente do GoTrue (supabase/auth) da stack local a partir de supabase/config.toml,
// no formato `export CHAVE='valor'` (seguro para `source` no bash).
//
// Uso: node scripts/local-stack/auth-env.mjs [--db <banco>]
//
// O config.toml continua sendo a fonte única: site_url, URLs de redirecionamento, cadastro,
// expiração do JWT, regras de senha, troca segura de senha, confirmação de e-mail,
// templates/assuntos de e-mail, avisos por e-mail ([auth.email.notification.*]) e hooks do
// Auth ([auth.hook.*], ex.: custom_access_token, D79).
// Diferenças deliberadas (ver docs/dev-local.md):
// - limites de taxa (rate limits) e o intervalo mínimo entre e-mails ([auth.email]
//   max_frequency, 1 s aqui) ficam folgados localmente para os testes automatizados não
//   esbarrarem neles;
// - login por link de e-mail ("magic link", /otp e /magiclink) desligado
//   (GOTRUE_EXTERNAL_EMAIL_MAGIC_LINK_ENABLED, sem chave no config.toml da CLI; D67).

import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseToml } from "./toml.mjs";
import { JWT_SECRET } from "./gen-keys.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");

const args = process.argv.slice(2);
const dbIdx = args.indexOf("--db");
const db = dbIdx >= 0 && args[dbIdx + 1] ? args[dbIdx + 1] : "postgres";

const cfgPath = join(root, "supabase/config.toml");
const cfg = existsSync(cfgPath) ? parseToml(readFileSync(cfgPath, "utf8")) : {};
const auth = cfg.auth ?? {};
const email = auth.email ?? {};

const API_URL = "http://127.0.0.1:54321";
const pick = (v, d) => (v === undefined ? d : v);

// [auth] password_requirements -> GOTRUE_PASSWORD_REQUIRED_CHARACTERS (mesmo mapeamento da CLI:
// grupos separados por ":"; a senha precisa de ao menos um caractere de cada grupo).
const LOWER = "abcdefghijklmnopqrstuvwxyz";
const UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS = "0123456789";
// ":" separa os grupos; "\\:" é um ":" literal dentro do grupo (formato do GoTrue).
const SYMBOLS = String.raw`!@#$%^&*()_+-=[]{};'\:"|<>?,./` + "`~";
const PASSWORD_REQUIRED_CHARACTERS = {
  "": "",
  letters_digits: `${LOWER}${UPPER}:${DIGITS}`,
  lower_upper_letters_digits: `${LOWER}:${UPPER}:${DIGITS}`,
  lower_upper_letters_digits_symbols: `${LOWER}:${UPPER}:${DIGITS}:${SYMBOLS}`,
};
const requirements = pick(auth.password_requirements, "");
if (!(requirements in PASSWORD_REQUIRED_CHARACTERS)) {
  console.error(`[auth-env] password_requirements desconhecido: ${requirements}`);
  process.exit(1);
}

const env = {
  GOTRUE_API_HOST: "127.0.0.1",
  GOTRUE_API_PORT: "54331",
  API_EXTERNAL_URL: `${API_URL}/auth/v1`,
  GOTRUE_DB_DRIVER: "postgres",
  GOTRUE_DB_DATABASE_URL: `postgres://supabase_auth_admin:postgres@127.0.0.1:54322/${db}`,
  DATABASE_URL: `postgres://supabase_auth_admin:postgres@127.0.0.1:54322/${db}`,
  GOTRUE_DB_NAMESPACE: "auth",
  GOTRUE_DB_MIGRATIONS_PATH: join(root, ".local/bin/auth/migrations"),
  GOTRUE_SITE_URL: pick(auth.site_url, "http://localhost:3000"),
  GOTRUE_URI_ALLOW_LIST: (auth.additional_redirect_urls ?? []).join(","),
  GOTRUE_DISABLE_SIGNUP: String(!pick(auth.enable_signup, false)),
  GOTRUE_JWT_SECRET: JWT_SECRET,
  GOTRUE_JWT_EXP: String(pick(auth.jwt_expiry, 3600)),
  GOTRUE_JWT_AUD: "authenticated",
  GOTRUE_JWT_DEFAULT_GROUP_NAME: "authenticated",
  GOTRUE_JWT_ADMIN_ROLES: "service_role",
  GOTRUE_JWT_ISSUER: `${API_URL}/auth/v1`,
  GOTRUE_PASSWORD_MIN_LENGTH: String(pick(auth.minimum_password_length, 6)),
  GOTRUE_PASSWORD_REQUIRED_CHARACTERS: PASSWORD_REQUIRED_CHARACTERS[requirements],
  GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED: String(
    pick(auth.enable_refresh_token_rotation, true),
  ),
  GOTRUE_SECURITY_REFRESH_TOKEN_REUSE_INTERVAL: String(pick(auth.refresh_token_reuse_interval, 10)),
  GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_REAUTHENTICATION: String(
    pick(email.secure_password_change, false),
  ),
  GOTRUE_EXTERNAL_EMAIL_ENABLED: String(pick(email.enable_signup, true)),
  // O app só usa e-mail e senha; o link de login por e-mail fica desligado (D67).
  GOTRUE_EXTERNAL_EMAIL_MAGIC_LINK_ENABLED: "false",
  GOTRUE_EXTERNAL_PHONE_ENABLED: "false",
  GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED: String(pick(auth.enable_anonymous_sign_ins, false)),
  GOTRUE_MAILER_AUTOCONFIRM: String(!pick(email.enable_confirmations, false)),
  GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED: String(pick(email.double_confirm_changes, true)),
  GOTRUE_MAILER_OTP_EXP: String(pick(email.otp_expiry, 3600)),
  GOTRUE_MAILER_OTP_LENGTH: String(pick(email.otp_length, 6)),
  GOTRUE_MAILER_URLPATHS_INVITE: "/auth/v1/verify",
  GOTRUE_MAILER_URLPATHS_CONFIRMATION: "/auth/v1/verify",
  GOTRUE_MAILER_URLPATHS_RECOVERY: "/auth/v1/verify",
  GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: "/auth/v1/verify",
  GOTRUE_SMTP_HOST: "127.0.0.1",
  GOTRUE_SMTP_PORT: "54325",
  GOTRUE_SMTP_USER: "",
  GOTRUE_SMTP_PASS: "",
  GOTRUE_SMTP_ADMIN_EMAIL: "nao-responda@exemplo.local",
  GOTRUE_SMTP_SENDER_NAME: "Éde Gestão (local)",
  // Intervalo mínimo entre e-mails para o mesmo endereço: 1 s localmente (os testes E2E pedem
  // vários links seguidos); o config.toml (e o hospedado) usam 60 s.
  GOTRUE_SMTP_MAX_FREQUENCY: "1s",
  GOTRUE_RATE_LIMIT_EMAIL_SENT: "1000",
  GOTRUE_RATE_LIMIT_SMS_SENT: "1000",
  GOTRUE_RATE_LIMIT_TOKEN_REFRESH: "1000",
  GOTRUE_RATE_LIMIT_VERIFY: "1000",
  GOTRUE_RATE_LIMIT_OTP: "1000",
  GOTRUE_RATE_LIMIT_SSO: "1000",
  GOTRUE_RATE_LIMIT_ANONYMOUS_USERS: "1000",
  GOTRUE_LOG_LEVEL: "info",
};

// Templates e assuntos de e-mail: [auth.email.template.<tipo>] subject / content_path.
// O GoTrue baixa o template por HTTP; o gateway serve os arquivos de supabase/templates/.
function templateUrl(contentPath) {
  const abs = resolve(root, contentPath);
  const rel = relative(root, abs).split("\\").join("/");
  if (existsSync(abs) && rel.startsWith("supabase/templates/")) {
    return `${API_URL}/email-templates/${rel}`;
  }
  console.error(
    `[auth-env] template ignorado (não encontrado em supabase/templates/): ${contentPath}`,
  );
  return undefined;
}

const templates = email.template ?? {};
for (const [type, t] of Object.entries(templates)) {
  const key = type.toUpperCase();
  if (typeof t.subject === "string") env[`GOTRUE_MAILER_SUBJECTS_${key}`] = t.subject;
  if (typeof t.content_path === "string") {
    const url = templateUrl(t.content_path);
    if (url) env[`GOTRUE_MAILER_TEMPLATES_${key}`] = url;
  }
}

// Avisos por e-mail: [auth.email.notification.<tipo>] enabled / subject / content_path
// (mesmos nomes de variável que a CLI usa, ex.: password_changed).
const notifications = email.notification ?? {};
for (const [type, n] of Object.entries(notifications)) {
  const key = type.toUpperCase();
  env[`GOTRUE_MAILER_NOTIFICATIONS_${key}_ENABLED`] = String(pick(n.enabled, false));
  if (typeof n.subject === "string") env[`GOTRUE_MAILER_SUBJECTS_${key}_NOTIFICATION`] = n.subject;
  if (typeof n.content_path === "string") {
    const url = templateUrl(n.content_path);
    if (url) env[`GOTRUE_MAILER_TEMPLATES_${key}_NOTIFICATION`] = url;
  }
}

// Hooks do Auth: [auth.hook.<nome>] enabled / uri (mesmos nomes de variável que a CLI usa, ex.:
// GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_ENABLED/URI). Hook "pg-functions://" roda no banco do Auth.
const hooks = auth.hook ?? {};
for (const [type, h] of Object.entries(hooks)) {
  const key = type.toUpperCase();
  env[`GOTRUE_HOOK_${key}_ENABLED`] = String(pick(h.enabled, false));
  if (typeof h.uri === "string") env[`GOTRUE_HOOK_${key}_URI`] = h.uri;
}

const quote = (v) => `'${String(v).replace(/'/g, `'\\''`)}'`;
process.stdout.write(
  Object.entries(env)
    .map(([k, v]) => `export ${k}=${quote(v)}`)
    .join("\n") + "\n",
);
