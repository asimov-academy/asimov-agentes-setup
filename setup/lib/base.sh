#!/usr/bin/env bash
# shellcheck disable=SC2034  # variáveis usadas pelas telas e pelo comando asimov
# Caminhos, versão, sudo e bibliotecas. Carregado por setup/instalar.sh e setup/asimov.sh.

VERSAO="0.31.0"
# O instalador da main aponta sempre para a última versão marcada.
URL_INSTALL="https://raw.githubusercontent.com/asimov-academy/asimov-agentes-setup/main/install.sh"

# Contagem de caracteres (alinhamento com acentos) depende de locale UTF-8.
if locale -a 2>/dev/null | grep -qi '^c\.utf-\?8$'; then
  export LC_ALL=C.UTF-8
fi
DIR_ESTADO="$HOME/.asimov"
ARQ_ESTADO="$DIR_ESTADO/estado"
ARQ_ENV="$RAIZ_PROJETO/.env"
LOG="$DIR_ESTADO/setup.log"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Rode como root ou com um usuário que tenha sudo."
    exit 1
  fi
  SUDO="sudo"
fi

DIR_LIB="$RAIZ_PROJETO/setup/lib"
# shellcheck source=setup/lib/ui.sh
source "$DIR_LIB/ui.sh"
# shellcheck source=setup/lib/estado.sh
source "$DIR_LIB/estado.sh"
# shellcheck source=setup/lib/sistema.sh
source "$DIR_LIB/sistema.sh"
# shellcheck source=setup/lib/dados.sh
source "$DIR_LIB/dados.sh"
# shellcheck source=setup/lib/dns.sh
source "$DIR_LIB/dns.sh"
# shellcheck source=setup/lib/instalacao.sh
source "$DIR_LIB/instalacao.sh"
# shellcheck source=setup/lib/acesso.sh
source "$DIR_LIB/acesso.sh"
# shellcheck source=setup/lib/atualizacao.sh
source "$DIR_LIB/atualizacao.sh"
# shellcheck source=setup/lib/vinculo.sh
source "$DIR_LIB/vinculo.sh"
# shellcheck source=setup/lib/agente.sh
source "$DIR_LIB/agente.sh"
# shellcheck source=setup/lib/waha.sh
source "$DIR_LIB/waha.sh"
# shellcheck source=setup/lib/whatsapp.sh
source "$DIR_LIB/whatsapp.sh"
# shellcheck source=setup/lib/painel.sh
source "$DIR_LIB/painel.sh"
# shellcheck source=setup/lib/menu.sh
source "$DIR_LIB/menu.sh"
# shellcheck source=setup/lib/conversa.sh
source "$DIR_LIB/conversa.sh"
# shellcheck source=setup/lib/final.sh
source "$DIR_LIB/final.sh"
# shellcheck source=deploy/compose.sh
source "$RAIZ_PROJETO/deploy/compose.sh"

confere_permissao_env

# Nenhuma queda silenciosa: qualquer erro não tratado mostra onde parou e o caminho do log.
erro_inesperado() {
  local codigo=$? linha=$1 arquivo=$2
  trap - ERR
  erro_fatal "Erro inesperado (código $codigo) em ${arquivo#"$RAIZ_PROJETO"/}, linha $linha" \
    "Rode o mesmo comando de novo; se repetir, envie as últimas linhas do log."
}
arma_erro() { trap 'erro_inesperado "$LINENO" "${BASH_SOURCE[0]:-setup}"' ERR; }
arma_erro

# com_voltar comando...: roda a ação num subshell. Esc em qualquer pergunta encerra só a ação e
# volta para quem chamou. Depois, VOLTOU=1 se foi Esc e FALHOU=1 se a ação parou com erro.
# O que a ação precisa deixar para quem chamou sai por `devolve VAR...`.
# shellcheck disable=SC2030  # ARQ_DEVOLVE e VOLTA_ATIVA só valem dentro do subshell, de propósito
com_voltar() {
  local __status __arquivo
  __arquivo=$(mktemp)
  # Dentro de `if` ou `||` o set -e do subshell ficaria desligado: desliga só aqui fora.
  set +e
  trap - ERR
  (
    set -e
    arma_erro
    VOLTA_ATIVA=1
    ARQ_DEVOLVE=$__arquivo
    "$@"
  )
  __status=$?
  set -e
  arma_erro
  VOLTOU=0 FALHOU=0
  if [ "$__status" -eq 0 ]; then
    # shellcheck source=/dev/null
    [ -s "$__arquivo" ] && source "$__arquivo"
  elif [ "$__status" -eq "$SAIDA_VOLTAR" ]; then
    VOLTOU=1
  else
    FALHOU=1
  fi
  rm -f "$__arquivo"
}

# shellcheck disable=SC2031
devolve() {
  local __nome
  [ -n "${ARQ_DEVOLVE:-}" ] || return 0
  for __nome in "$@"; do
    printf '%s=%q\n' "$__nome" "${!__nome}" >>"$ARQ_DEVOLVE"
  done
}
