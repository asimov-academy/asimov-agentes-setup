#!/usr/bin/env bash
# Acesso às imagens privadas: o painel e o copiloto.
#
# O que roda pelo terminal sai de imagem pública e não pede nada. O painel no navegador faz parte
# da trilha da Asimov Academy, e a imagem dele é privada: quem liga o painel entra no registro com
# o token da turma. A conta é fixa e só de leitura.
#
# O token mora só na credencial do Docker (`docker login`). NUNCA no .env, no estado ou no log.

REGISTRO_PADRAO="ghcr.io/asimov-academy"
REGISTRO_USUARIO_PADRAO="vitorpaimio"
# Endereço da trilha, mostrado a quem ainda não é aluno.
URL_TRILHA="https://asimov.academy"

# ASIMOV_REGISTRO e ASIMOV_REGISTRO_USUARIO no .env passam por cima dos padrões, para o dia em que
# as imagens forem servidas por um endereço próprio, com token por aluno.
registro() {
  local valor
  valor=$(env_get ASIMOV_REGISTRO)
  printf '%s' "${valor:-$REGISTRO_PADRAO}"
}

# Só o host, que é com quem o `docker login` fala.
registro_host() {
  local endereco
  endereco=$(registro)
  printf '%s' "${endereco%%/*}"
}

registro_usuario() {
  local valor
  valor=$(env_get ASIMOV_REGISTRO_USUARIO)
  printf '%s' "${valor:-$REGISTRO_USUARIO_PADRAO}"
}

# A versão instalada vem do .env; na primeira instalação ainda não existe e vale a deste setup.
imagem_painel() {
  local versao
  versao=$(env_get ASIMOV_VERSAO)
  printf '%s/agentes-painel:%s' "$(registro)" "${versao:-v$VERSAO}"
}

# acesso_valido: o token guardado no Docker ainda abre a imagem privada do painel?
acesso_valido() {
  $SUDO docker manifest inspect "$(imagem_painel)" >>"$LOG" 2>&1
}

# acesso_login TOKEN: o token entra por stdin, nunca por argumento, senão aparece no `ps`.
acesso_login() {
  printf '%s' "$1" | $SUDO docker login "$(registro_host)" \
    --username "$(registro_usuario)" --password-stdin >>"$LOG" 2>&1
}

acesso_explica_trilha() {
  info "O painel no navegador faz parte da trilha de agentes da Asimov Academy, e o token vem no material."
  dica "Ainda não é aluno? $(destaque "$URL_TRILHA")"
  echo
}

# acesso_pede_token: pergunta, entra no registro e confere. 0 = acesso liberado, 1 = desistiu.
acesso_pede_token() {
  local token
  while true; do
    pergunta_secreta token "Token da trilha"
    printf '  %sEntrando no registro de imagens…%s' "$CINZA" "$NORMAL"
    if acesso_login "$token" && acesso_valido; then
      token=""
      printf '\r\033[K'
      ok "Token aceito."
      return 0
    fi
    token=""
    printf '\r\033[K'
    falha "O registro recusou o token."
    dica "Confira se copiou o token inteiro, sem espaço no fim."
    confirma "Tentar de novo?" || return 1
  done
}

# acesso_garante: usado antes de ligar o painel. Com token guardado, não pergunta nada.
acesso_garante() {
  acesso_valido && return 0
  acesso_explica_trilha
  # Padrão Não: quem chega pelo workshop gratuito não tem token, e Enter segue sem painel.
  confirma "Tem o token da trilha?" false || return 1
  acesso_pede_token
}

# Tela do comando `asimov token`: trocar o token quando ele é rotacionado. Não mexe em versão,
# banco nem contêiner; com o painel ligado, oferece trazer a imagem e reiniciar.
fluxo_token() {
  secao "Token da trilha"
  acesso_explica_trilha
  acesso_pede_token || return 0

  painel_ligado || return 0
  echo
  confirma "Baixar a imagem do painel e reiniciar?" || return 0
  printf '  %sSubindo…%s' "$CINZA" "$NORMAL"
  if painel_sobe; then
    printf '\r\033[K'
    ok "Painel no ar em $(destaque "$(painel_endereco)")"
  else
    printf '\r\033[K'
    falha "O painel não subiu. Veja o log: $LOG"
  fi
}
