/** Textos de autenticação exibidos na interface (pt-BR). Os testes E2E usam os mesmos textos. */
export const AUTH_MESSAGES = {
  invalidCredentials: "E-mail ou senha incorretos. Confira e tente de novo.",
  noAccess: "Seu acesso não está ativo. Fale com a gerência da loja.",
  tooManyAttempts: "Muitas tentativas seguidas. Espere alguns minutos e tente de novo.",
  signInUnavailable:
    "Não foi possível entrar agora. Confira a internet e tente de novo em instantes.",
  invalidLink: "O link expirou ou já foi usado. Peça um novo em “Esqueci minha senha”.",
  linkOtherBrowser:
    "Este link só funciona uma vez e no mesmo aparelho e navegador em que você pediu a nova senha. Abra o link por lá ou peça um novo em “Esqueci minha senha”.",
  resetSent: "Se o e-mail estiver cadastrado, você vai receber um link para criar uma nova senha.",
  passwordChanged: "Senha alterada. Entre com a nova senha.",
  recoveryRequired:
    "Para criar uma nova senha, abra o link que enviamos para o seu e-mail. Se o link expirou, peça outro.",
  samePassword: "A nova senha precisa ser diferente da senha atual.",
  weakPassword:
    "Essa senha é fácil de adivinhar. Use pelo menos 8 caracteres, com pelo menos uma letra (de A a Z) e um número.",
  passwordTooLong:
    "Essa senha é longa demais. Use no máximo 72 caracteres (letras com acento, ç e emojis contam como mais de um).",
  passwordUpdateFailed: "Não foi possível salvar a nova senha. Tente de novo em instantes.",
} as const;

/**
 * Lê uma mensagem de uma tabela pelo valor vindo da URL (?erro=, ?aviso=). Só aceita chaves
 * próprias da tabela: "__proto__", "constructor" ou "toString" devolvem `undefined` em vez de um
 * objeto ou função do protótipo (que quebravam a renderização com 500).
 */
export function lookupMessage(
  table: Readonly<Record<string, string>>,
  key: string | undefined,
): string | undefined {
  if (key === undefined || !Object.hasOwn(table, key)) return undefined;
  const value = table[key];
  return typeof value === "string" ? value : undefined;
}
