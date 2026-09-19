#!/usr/bin/env bash
# Acesso às imagens da plataforma. Elas são privadas: o token de leitura vem no material da trilha,
# é o mesmo para a turma, e o setup faz `docker login` no registro com o usuário fixo abaixo. A credencial fica só onde o Docker guarda
# (config.json do root, 600): NUNCA no .env, no estado nem no log.
# O registro é configurável (ASIMOV_REGISTRO no .env) para o dia em que a Asimov servir as imagens
# por um endereço próprio; o padrão é o GHCR.

REGISTRO_PADRAO="ghcr.io/asimov-academy"
# Conta só com leitura nos três pacotes. O operador nunca digita isto: só o token.
# ASIMOV_REGISTRO_USUARIO no .env passa por cima, para o dia em que o registro for outro.
REGISTRO_USUARIO_PADRAO="PREENCHER-conta-robo"

registro() {
  local valor
  valor=$(env_get ASIMOV_REGISTRO)
  printf '%s' "${valor:-$REGISTRO_PADRAO}"
}
registro_usuario() {
  local valor
  valor=$(env_get ASIMOV_REGISTRO_USUARIO)
  printf '%s' "${valor:-$REGISTRO_USUARIO_PADRAO}"
}
registro_host() { local r; r=$(registro); printf '%s' "${r%%/*}"; }

# acesso_confere: 0 se esta VPS consegue ler a imagem da versão deste setup. Diferente de zero
# deixa o motivo em ACESSO_MOTIVO: `token` (recusado pelo registro) ou `rede` (não deu para saber).
acesso_confere() {
  local saida
  ACESSO_MOTIVO=""
  if saida=$($SUDO docker manifest inspect "$(registro)/agentes-backend:v$VERSAO" 2>&1 >/dev/null); then
    return 0
  fi
  printf '%s acesso às imagens recusado: %s\n' "$(date -Is)" "$(head -c 300 <<<"$saida")" >>"$LOG"
  if grep -qiE 'unauthorized|denied|forbidden|401|403|no basic auth' <<<"$saida"; then
    ACESSO_MOTIVO=token
  else
    ACESSO_MOTIVO=rede
  fi
  return 1
}

# O token entra pelo stdin do docker: em argumento ele apareceria no `ps` e no histórico.
acesso_entra() { # acesso_entra TOKEN
  printf '%s' "$1" | $SUDO docker login "$(registro_host)" --username "$(registro_usuario)" --password-stdin >/dev/null 2>>"$LOG"
}

# pede_token: pergunta até o registro aceitar. Esc volta, como em toda pergunta.
pede_token() {
  local token
  dica "É o token de acesso que está no material da trilha. Ele fica guardado só nesta VPS."
  while true; do
    pergunta_secreta token "Token de acesso"
    printf '  %sConferindo…%s' "$CINZA" "$NORMAL"
    if acesso_entra "$token" && acesso_confere; then
      printf '\r\033[K'
      estado_set acesso_liberado "$(date -Is)"
      ok "Acesso liberado."
      return 0
    fi
    printf '\r\033[K'
    if [ "$ACESSO_MOTIVO" = rede ]; then
      falha "Não consegui falar com $(registro_host). Confira a internet da VPS e tente de novo."
    else
      falha "Token recusado. Confira se copiou inteiro e se é o mais recente do material da trilha."
    fi
  done
}

# tela_acesso: só aparece quando a VPS ainda não lê as imagens (instalação nova ou token vencido).
tela_acesso() {
  acesso_confere && return 0
  if [ "$ACESSO_MOTIVO" = rede ] && estado_tem acesso_liberado; then
    erro_fatal "Não consegui falar com $(registro_host)" "Confira a internet da VPS e rode o mesmo comando de novo."
  fi
  secao "Acesso"
  if estado_tem acesso_liberado; then
    aviso "O token de acesso desta VPS venceu ou foi trocado. O atual está no material da trilha."
  fi
  pede_token
}

# `asimov token`: troca o token, por exemplo quando a Asimov Academy renova o da turma.
fluxo_token() {
  secao "Token de acesso"
  if acesso_confere; then
    ok "O token atual está valendo ${CINZA}· $(registro_host)${NORMAL}"
    confirma "Trocar mesmo assim?" || return 0
  fi
  pede_token
}

mostra_acesso() {
  if acesso_confere; then
    campo "Imagens" "acesso ok ${CINZA}· $(registro)${NORMAL}"
  elif [ "$ACESSO_MOTIVO" = token ]; then
    falha "Token de acesso às imagens recusado. Rode: asimov token"
  else
    aviso "Não consegui conferir o acesso às imagens em $(registro_host)."
  fi
}
