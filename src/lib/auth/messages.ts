/** Textos de autenticação exibidos na interface (pt-BR). Os testes E2E usam os mesmos textos. */
export const AUTH_MESSAGES = {
  invalidCredentials: "E-mail ou senha incorretos. Confira e tente de novo.",
  noAccess: "Seu acesso não está ativo. Fale com a gerência da loja.",
  tooManyAttempts: "Muitas tentativas seguidas. Espere alguns minutos e tente de novo.",
  signInUnavailable:
    "Não foi possível entrar agora. Confira a internet e tente de novo em instantes.",
  invalidLink: "O link expirou ou já foi usado. Peça um novo em “Esqueci minha senha”.",
  resetSent: "Se o e-mail estiver cadastrado, você vai receber um link para criar uma nova senha.",
  passwordChanged: "Senha alterada. Entre com a nova senha.",
  recoveryRequired:
    "Para criar uma nova senha, abra o link que enviamos para o seu e-mail. Se o link expirou, peça outro.",
  samePassword: "A nova senha precisa ser diferente da senha atual.",
  weakPassword:
    "Essa senha é fácil de adivinhar. Use pelo menos 8 caracteres, com letras e números.",
  passwordUpdateFailed: "Não foi possível salvar a nova senha. Tente de novo em instantes.",
} as const;
