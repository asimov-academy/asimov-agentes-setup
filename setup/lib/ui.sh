#!/usr/bin/env bash
# shellcheck disable=SC2034  # cores usadas pelas outras telas
# Tela: cores, banners, seções, perguntas, passos numerados e erros.
#
# Padrão visual: seção em ciano, pergunta com ❯, dica em cinza, valor em negrito,
# ✓ verde para sucesso, ▲ amarelo para atenção, ✗ vermelho para erro.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  CIANO=$'\033[36m'
  VERDE=$'\033[32m'
  AMARELO=$'\033[33m'
  VERMELHO=$'\033[31m'
  CINZA=$'\033[90m'
  NEGRITO=$'\033[1m'
  NORMAL=$'\033[0m'
else
  CIANO="" VERDE="" AMARELO="" VERMELHO="" CINZA="" NEGRITO="" NORMAL=""
fi

# Respostas vêm do terminal (descritor 3), mesmo quando o script chega por bash <(curl ...).
# Testes automatizados trocam o terminal por um arquivo com as respostas (ASIMOV_TTY).
# O grupo evita que o 2>/dev/null do exec fique valendo para o script inteiro.
{ exec 3<"${ASIMOV_TTY:-/dev/tty}"; } 2>/dev/null || exec 3<&0

# Fim da entrada (Ctrl+D ou arquivo de respostas no fim) encerra: as telas repetem a pergunta
# até ter resposta e ficariam presas.
ler() {
  IFS= read -r "$@" <&3 && return 0
  local __nome=${!#}
  [ -n "${!__nome}" ] && return 0
  echo
  exit 1
}

banner_asimov() {
  clear 2>/dev/null || true
  printf '%s%s' "$CIANO" "$NEGRITO"
  cat <<'ARTE'

     █████╗ ███████╗██╗███╗   ███╗ ██████╗ ██╗   ██╗
    ██╔══██╗██╔════╝██║████╗ ████║██╔═══██╗██║   ██║
    ███████║███████╗██║██╔████╔██║██║   ██║██║   ██║
    ██╔══██║╚════██║██║██║╚██╔╝██║██║   ██║╚██╗ ██╔╝
    ██║  ██║███████║██║██║ ╚═╝ ██║╚██████╔╝ ╚████╔╝
    ╚═╝  ╚═╝╚══════╝╚═╝╚═╝     ╚═╝ ╚═════╝   ╚═══╝
ARTE
  printf '%s    %sACADEMY%s  %sagentes de atendimento · v%s%s\n\n' \
    "$NORMAL" "$NEGRITO" "$NORMAL" "$CINZA" "$VERSAO" "$NORMAL"
}

banner_iniciando() {
  clear 2>/dev/null || true
  printf '%s%s' "$CIANO" "$NEGRITO"
  cat <<'ARTE'

  ██╗███╗   ██╗██╗ ██████╗██╗ █████╗ ███╗   ██╗██████╗  ██████╗
  ██║████╗  ██║██║██╔════╝██║██╔══██╗████╗  ██║██╔══██╗██╔═══██╗
  ██║██╔██╗ ██║██║██║     ██║███████║██╔██╗ ██║██║  ██║██║   ██║
  ██║██║╚██╗██║██║██║     ██║██╔══██║██║╚██╗██║██║  ██║██║   ██║
  ██║██║ ╚████║██║╚██████╗██║██║  ██║██║ ╚████║██████╔╝╚██████╔╝
  ╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝
ARTE
  printf '%s  %sv%s%s\n\n' "$NORMAL" "$CINZA" "$VERSAO" "$NORMAL"
}

# secao "Título": tela nova. Limpa tudo, redesenha o banner e mostra o cabeçalho de uma linha.
secao() {
  local traco
  banner_asimov
  traco=$(printf '%*s' $((56 - ${#1})) '' | tr ' ' '-')
  printf '%s%s▍ %s %s%s%s\n\n' "$CIANO" "$NEGRITO" "$1" "$NORMAL$CINZA" "$traco" "$NORMAL"
}
titulo() { secao "$@"; }

info() { printf '  %s\n' "$*"; }
dica() { printf '  %s%s%s\n' "$CINZA" "$*" "$NORMAL"; }
ok() { printf '  %s✓%s %s\n' "$VERDE" "$NORMAL" "$*"; }
aviso() { printf '  %s▲%s %s\n' "$AMARELO" "$NORMAL" "$*"; }
falha() { printf '  %s✗%s %s\n' "$VERMELHO" "$NORMAL" "$*"; }
destaque() { printf '%s%s%s' "$NEGRITO" "$*" "$NORMAL"; }

# campo "Rótulo" "valor": linha de resumo alinhada.
campo() {
  local espacos
  espacos=$(printf '%*s' $((11 - ${#1})) '')
  printf '  %s%s%s%s %s%s%s\n' "$CINZA" "$1" "$espacos" "$NORMAL" "$NEGRITO" "$2" "$NORMAL"
}

_prompt() { printf '%s❯%s %s%s%s' "$CIANO" "$NORMAL" "$NEGRITO" "$1" "$NORMAL"; }

# Variáveis internas com prefixo __ para não colidir com a variável de quem chama.

# pergunta VAR "texto" [padrão]: Enter aceita o padrão.
pergunta() {
  local __var=$1 __texto=$2 __padrao=${3:-} __resposta
  while true; do
    _prompt "$__texto"
    [ -n "$__padrao" ] && printf ' %s(%s)%s' "$CINZA" "$__padrao" "$NORMAL"
    printf ': '
    __resposta=""
    if tem_terminal; then
      ler_linha __resposta
      echo
    else
      ler __resposta
    fi
    __resposta=${__resposta:-$__padrao}
    if [ -n "$__resposta" ]; then
      printf -v "$__var" '%s' "$__resposta"
      return 0
    fi
    falha "Resposta obrigatória."
  done
}

# pergunta_numero VAR "texto" mínimo máximo [padrão]
pergunta_numero() {
  local __var=$1 __texto=$2 __min=$3 __max=$4 __padrao=${5:-} __numero
  while true; do
    pergunta __numero "$__texto" "$__padrao"
    if [[ "$__numero" =~ ^[0-9]{1,6}$ ]] && [ "$((10#$__numero))" -ge "$__min" ] && [ "$((10#$__numero))" -le "$__max" ]; then
      printf -v "$__var" '%s' "$((10#$__numero))"
      return 0
    fi
    falha "Digite um número de $__min a $__max."
  done
}

# normaliza "texto": sem acento, maiúscula, espaço ou pontuação, como o slug da API.
# normaliza_linhas: como `normaliza`, mas em lote, uma linha por vez do stdin. Um processo só
# para listas grandes (os grupos do WhatsApp).
normaliza_linhas() {
  python3 -c 'import sys, unicodedata, re
for linha in sys.stdin.read().split("\n"):
    t = unicodedata.normalize("NFKD", linha).encode("ascii", "ignore").decode().lower()
    print(re.sub(r"[^a-z0-9]+", "", t))'
}

normaliza() {
  python3 -c 'import sys, unicodedata, re
t = unicodedata.normalize("NFKD", sys.argv[1]).encode("ascii", "ignore").decode().lower()
print(re.sub(r"[^a-z0-9]+", "", t))' "$1"
}

# coluna "texto" largura: alinha contando caracteres (o printf conta bytes e desalinha acentos).
coluna() {
  local __texto=$1 __largura=$2
  [ "${#__texto}" -gt "$__largura" ] && __texto="${__texto:0:$((__largura - 1))}…"
  printf '%s%*s' "$__texto" $((__largura - ${#__texto})) ''
}

# pergunta_secreta VAR "texto": não mostra o que é digitado.
pergunta_secreta() {
  local __var=$1 __texto=$2 __resposta
  while true; do
    _prompt "$__texto"
    printf ': '
    __resposta=""
    if tem_terminal; then
      ler_linha __resposta secreta
    else
      ler -s __resposta
    fi
    if [ -n "$__resposta" ]; then
      printf '%s••••••••%s\n' "$CINZA" "$NORMAL"
      printf -v "$__var" '%s' "$__resposta"
      return 0
    fi
    echo
    falha "Resposta obrigatória."
  done
}

# Com terminal, escolhas andam com as setas e confirmam com Enter. Sem terminal (ASIMOV_TTY com
# arquivo de respostas, usado na simulação), a resposta é uma linha com o número ou S/N.
tem_terminal() { [ -t 3 ] && [ -t 1 ]; }

# Esc sozinho é um byte só; setas e teclas com Shift chegam como Esc seguido de uma sequência.
# A espera cobre sequência que chega atrasada em conexão lenta.
ESPERA_SEQUENCIA=1
[ "${BASH_VERSINFO[0]}" -ge 4 ] && ESPERA_SEQUENCIA=0.4
SAIDA_VOLTAR=20

# volta_se_puder: Esc dentro de `com_voltar` (base.sh) encerra a ação e volta à tela anterior.
# Fora dele (primeira instalação) não há para onde voltar e o Esc não faz nada.
volta_se_puder() {
  [ -n "${VOLTA_ATIVA:-}" ] || return 0
  printf '\033[?25h\n'
  exit "$SAIDA_VOLTAR"
}

# descarta_pendentes: joga fora o que chegou antes de a pergunta aparecer. Terminais no navegador
# (painel da Hostinger) mandam Enter como \r\n: o segundo Enter respondia sozinho a pergunta seguinte.
descarta_pendentes() {
  local __sobra
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || return 0
  while IFS= read -rsn1 -t 0.05 __sobra <&3; do :; done
}

# ler_linha VAR [secreta]: resposta digitada tecla a tecla, para o Esc voltar. Backspace apaga.
ler_linha() {
  local __destino=$1 __secreta=${2:-} __digitado="" __letra
  descarta_pendentes
  while true; do
    le_tecla __letra
    case "$__letra" in
      enter) break ;;
      esc) volta_se_puder ;;
      apagar)
        if [ -n "$__digitado" ]; then
          __digitado=${__digitado%?}
          [ -n "$__secreta" ] || printf '\b \b'
        fi
        ;;
      ?)
        __digitado+=$__letra
        [ -n "$__secreta" ] || printf '%s' "$__letra"
        ;;
    esac
  done
  printf -v "$__destino" '%s' "$__digitado"
}

if tem_terminal; then
  trap 'printf "\033[?25h"' EXIT
fi

# le_tecla VAR [segundos]: um caractere digitado, ou enter, esc, apagar, cima, baixo, esquerda, direita,
# ignorar. Lê a sequência de escape inteira: sobra dela nunca vira texto nem Esc falso.
# Com segundos, devolve `nada` se nenhuma tecla chegar nesse tempo (a conversa no terminal consulta a API).
le_tecla() {
  local __lida="" __proximo="" __parametros="" __final="" __status=0
  local -a __espera=()
  [ -n "${2:-}" ] && __espera=(-t "$2")
  IFS= read -rsn1 ${__espera[@]+"${__espera[@]}"} __lida <&3 || __status=$?
  if [ "$__status" -gt 128 ]; then
    printf -v "$1" '%s' nada
    return 0
  elif [ "$__status" -ne 0 ]; then
    printf '\033[?25h\n'
    exit 1
  fi
  case "$__lida" in
    "") __lida=enter ;;
    $'\177' | $'\b') __lida=apagar ;;
    $'\033')
      if ! IFS= read -rsn1 -t "$ESPERA_SEQUENCIA" __proximo <&3 || [ -z "$__proximo" ]; then
        __lida=esc
      elif [ "$__proximo" = "[" ] || [ "$__proximo" = O ]; then
        # Parâmetros (dígitos, ; e :) até o byte final (letra ou ~).
        while IFS= read -rsn1 -t "$ESPERA_SEQUENCIA" __final <&3; do
          case "$__final" in
            [0-9\;:?]) __parametros+=$__final ;;
            *) break ;;
          esac
          __final=""
        done
        __lida=$(traduz_sequencia "$__proximo" "$__parametros" "$__final")
      else
        __lida=ignorar
      fi
      ;;
    [[:cntrl:]]) __lida=ignorar ;;
  esac
  printf -v "$1" '%s' "$__lida"
}

# traduz_sequencia "[" parâmetros final: setas, e Shift+letra nos formatos que terminais modernos
# mandam (kitty `CSI código;mod u` e xterm `CSI 27;mod;código ~`). O resto é ignorado e vai para o log.
traduz_sequencia() {
  local inicio=$1 parametros=$2 final=$3 codigo="" mods=1 base
  case "$final" in
    A) echo cima; return ;;
    B) echo baixo; return ;;
    C) echo direita; return ;;
    D) echo esquerda; return ;;
    u)
      base=${parametros%%;*}
      codigo=${base%%:*}
      [[ "$base" == *:* ]] && [ -n "${base#*:}" ] && codigo=${base#*:} && codigo=${codigo%%:*}
      [[ "$parametros" == *\;* ]] && mods=${parametros#*;} && mods=${mods%%[;:]*}
      ;;
    "~")
      if [[ "$parametros" == 27\;*\;* ]]; then
        mods=${parametros#27;}
        mods=${mods%%;*}
        codigo=${parametros##*;}
      fi
      ;;
  esac
  case "$codigo" in
    27) echo esc; return ;;
    13) echo enter; return ;;
    8 | 127) echo apagar; return ;;
  esac
  if [[ "$codigo" =~ ^[0-9]+$ ]] && [ "$codigo" -ge 32 ] && [ "$codigo" -lt 57344 ] && [ "$codigo" -ne 127 ]; then
    local letra
    # shellcheck disable=SC2059  # o formato é o próprio \U com o código da letra
    printf -v letra "\\U$(printf '%08x' "$codigo")"
    # Shift ligado (bit 1 do modificador) e o terminal mandou a letra minúscula.
    if [ $(((${mods:-1} - 1) & 1)) -eq 1 ] && [[ "$letra" == [a-z] ]]; then
      letra=$(printf '%s' "$letra" | tr '[:lower:]' '[:upper:]')
    fi
    echo "$letra"
    return
  fi
  printf 'tecla ignorada: ESC %q\n' "$inicio$parametros$final" >>"${LOG:-/dev/null}" 2>/dev/null || true
  echo ignorar
}

# escolha VAR "texto" opção1 opção2 ...: devolve o número escolhido.
# Esc escolhe a opção ESC_ESCOLHE quando definida (ex.: Voltar, Sair); senão volta à tela anterior.
# ESCOLHA_ATUAL começa o cursor numa opção, para a tela de editar já vir no valor de hoje.
escolha() {
  local __var=$1 __texto=$2 __atual=1 __tecla __i __item
  shift 2
  if [ -n "${ESCOLHA_ATUAL:-}" ] && [ "$ESCOLHA_ATUAL" -ge 1 ] && [ "$ESCOLHA_ATUAL" -le "$#" ]; then
    __atual=$ESCOLHA_ATUAL
  fi
  if ! tem_terminal; then
    escolha_digitada "$__var" "$__texto" "$@"
    return 0
  fi
  descarta_pendentes
  _prompt "$__texto"
  printf '  %s↑ ↓ e Enter%s%s\n' "$CINZA" "$([ -n "${ESC_ESCOLHE:-}${VOLTA_ATIVA:-}" ] && echo ' · Esc volta')" "$NORMAL"
  printf '\033[?25l'
  while true; do
    __i=1
    for __item in "$@"; do
      if [ "$__i" -eq "$__atual" ]; then
        printf '\r\033[K  %s❯%s %s%s%s\n' "$CIANO" "$NORMAL" "$NEGRITO" "$__item" "$NORMAL"
      else
        printf '\r\033[K    %s\n' "$__item"
      fi
      __i=$((__i + 1))
    done
    le_tecla __tecla
    case "$__tecla" in
      cima | k) __atual=$((__atual == 1 ? $# : __atual - 1)) ;;
      baixo | j) __atual=$((__atual == $# ? 1 : __atual + 1)) ;;
      [1-9]) [ "$__tecla" -le "$#" ] && __atual=$__tecla ;;
      enter) break ;;
      esc)
        if [ -n "${ESC_ESCOLHE:-}" ]; then
          __atual=$ESC_ESCOLHE
          break
        fi
        volta_se_puder
        ;;
    esac
    printf '\033[%sA' "$#"
  done
  # A lista vira uma linha só com o que foi escolhido.
  printf '\033[%sA\r\033[J' "$(($# + 1))"
  _prompt "$__texto"
  printf ': %s\n' "${!__atual}"
  printf '\033[?25h'
  printf -v "$__var" '%s' "$__atual"
}

# marca VAR "texto" "1 0 1" opção1 opção2 opção3: lista de marcar. O terceiro argumento diz quais
# começam marcadas. Devolve em VAR os números marcados, separados por espaço (vazio = nenhum).
# Setas andam, Espaço marca e desmarca, Enter confirma, Esc volta. Sem terminal: números numa linha.
marca() {
  local __var=$1 __texto=$2 __atual=1 __tecla __i __item __resposta __numero
  local -a __marcadas
  read -r -a __marcadas <<<"$3"
  shift 3
  if ! tem_terminal; then
    _prompt "$__texto"
    echo
    __i=1
    for __item in "$@"; do
      printf '    %s%s%s  [%s] %s\n' "$CIANO" "$__i" "$NORMAL" "$([ "${__marcadas[$((__i - 1))]:-0}" = 1 ] && echo x || echo ' ')" "$__item"
      __i=$((__i + 1))
    done
    printf '  %sNúmeros marcados (Enter mantém, 0 desmarca todas):%s ' "$CINZA" "$NORMAL"
    __resposta=""
    ler __resposta
    if [ -n "$__resposta" ]; then
      __marcadas=()
      for __i in $(seq 1 "$#"); do __marcadas+=(0); done
      for __numero in ${__resposta//,/ }; do
        [[ "$__numero" =~ ^[0-9]+$ ]] && [ "$__numero" -ge 1 ] && [ "$__numero" -le "$#" ] && __marcadas[__numero - 1]=1
      done
    fi
  else
    descarta_pendentes
    _prompt "$__texto"
    printf '  %s↑ ↓, Espaço marca, Enter confirma%s%s\n' "$CINZA" "$([ -n "${VOLTA_ATIVA:-}" ] && echo ' · Esc volta')" "$NORMAL"
    printf '\033[?25l'
    while true; do
      __i=1
      for __item in "$@"; do
        printf '\r\033[K  %s %s %s\n' \
          "$([ "$__i" -eq "$__atual" ] && printf '%s❯%s' "$CIANO" "$NORMAL" || echo ' ')" \
          "$([ "${__marcadas[$((__i - 1))]:-0}" = 1 ] && printf '%s[x]%s' "$VERDE" "$NORMAL" || echo '[ ]')" \
          "$__item"
        __i=$((__i + 1))
      done
      le_tecla __tecla
      case "$__tecla" in
        cima | k) __atual=$((__atual == 1 ? $# : __atual - 1)) ;;
        baixo | j) __atual=$((__atual == $# ? 1 : __atual + 1)) ;;
        " ") __marcadas[__atual - 1]=$((1 - ${__marcadas[$((__atual - 1))]:-0})) ;;
        enter) break ;;
        esc) volta_se_puder ;;
      esac
      printf '\033[%sA' "$#"
    done
    printf '\033[?25h'
  fi
  __resposta=""
  for __i in $(seq 1 "$#"); do
    [ "${__marcadas[$((__i - 1))]:-0}" = 1 ] && __resposta+="$__i "
  done
  printf -v "$__var" '%s' "${__resposta% }"
}

escolha_digitada() {
  local __var=$1 __texto=$2 __resposta __i __item
  shift 2
  _prompt "$__texto"
  echo
  __i=1
  for __item in "$@"; do
    printf '    %s%s%s  %s\n' "$CIANO" "$__i" "$NORMAL" "$__item"
    __i=$((__i + 1))
  done
  while true; do
    printf '  %sNúmero:%s ' "$CINZA" "$NORMAL"
    __resposta=""
    ler __resposta
    if [[ "$__resposta" =~ ^[0-9]+$ ]] && [ "$__resposta" -ge 1 ] && [ "$__resposta" -le "$#" ]; then
      printf -v "$__var" '%s' "$__resposta"
      return 0
    fi
    falha "Escolha de 1 a $#."
  done
}

# confirma "texto" -> 0 para sim. Setas trocam, Enter confirma, S e N respondem direto.
confirma() {
  local __resposta="" __sim=1 __tecla
  [ "${2:-true}" = false ] && __sim=0
  if ! tem_terminal; then
    _prompt "$1"
    if [ "$__sim" = 1 ]; then
      printf ' %s(S/n)%s: ' "$CINZA" "$NORMAL"
    else
      printf ' %s(s/N)%s: ' "$CINZA" "$NORMAL"
    fi
    ler __resposta
    if [ -z "$__resposta" ]; then [ "$__sim" = 1 ]; return; fi
    [[ "$__resposta" =~ ^[SsYy]$ ]]
    return
  fi
  descarta_pendentes
  printf '\033[?25l'
  while true; do
    printf '\r\033[K'
    _prompt "$1"
    if [ "$__sim" -eq 1 ]; then
      printf '   %s❯ Sim%s     %sNão%s' "$CIANO$NEGRITO" "$NORMAL" "$CINZA" "$NORMAL"
    else
      printf '     %sSim%s   %s❯ Não%s' "$CINZA" "$NORMAL" "$CIANO$NEGRITO" "$NORMAL"
    fi
    le_tecla __tecla
    case "$__tecla" in
      cima | baixo | esquerda | direita) __sim=$((1 - __sim)) ;;
      [SsYy]) __sim=1 && break ;;
      [Nn]) __sim=0 && break ;;
      enter) break ;;
      esc) volta_se_puder ;;
    esac
  done
  printf '\r\033[K'
  _prompt "$1"
  printf ': %s\n' "$([ "$__sim" -eq 1 ] && echo Sim || echo Não)"
  printf '\033[?25h'
  [ "$__sim" -eq 1 ]
}

# pausa ["texto"]: segura a tela até uma tecla, antes de o menu limpar o que foi mostrado.
pausa() {
  local __tecla
  tem_terminal || return 0
  descarta_pendentes
  printf '\n  %s%s%s' "$CINZA" "${1:-Enter para voltar}" "$NORMAL"
  le_tecla __tecla
  echo
}

linha_ok() { printf '\r\033[K  %s%2s/%s%s  %s✓%s  %s\n' "$CINZA" "$1" "$2" "$NORMAL" "$VERDE" "$NORMAL" "$3"; }
linha_rodando() { printf '\r\033[K  %s%2s/%s%s  %s…%s  %s' "$CINZA" "$1" "$2" "$NORMAL" "$CIANO" "$NORMAL" "$3"; }
linha_erro() { printf '\r\033[K  %s%2s/%s%s  %s✗%s  %s\n' "$CINZA" "$1" "$2" "$NORMAL" "$VERMELHO" "$NORMAL" "$3"; }

# erro_fatal "o que falhou" "o que fazer"
erro_fatal() {
  echo
  printf '  %s%s✗ %s%s\n' "$VERMELHO" "$NEGRITO" "$1" "$NORMAL"
  [ -n "${2:-}" ] && printf '    %s\n' "$2"
  printf '    %sLog: %s · rode o mesmo comando de novo para continuar daqui%s\n\n' "$CINZA" "$LOG" "$NORMAL"
  exit 1
}
