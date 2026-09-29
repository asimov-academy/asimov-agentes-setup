#!/usr/bin/env bash
# Uso na VPS:
#   bash <(curl -sSL https://raw.githubusercontent.com/asimov-academy/asimov-agentes-setup/main/install.sh)
# Para testar o que está na main em vez da versão marcada: ASIMOV_VERSAO=main antes do bash.
# Para atualizar uma instalação existente (mantém .env, prompts e o progresso):
#   ASIMOV_ATUALIZAR=1 antes do bash. É o que `asimov atualizar` faz.
#
# Baixa o instalador na versão marcada para ~/asimov-agentes e roda o setup. Aqui só vem o
# instalador: a plataforma chega em imagens Docker prontas, da mesma versão, puxadas pelo setup.
# Se a pasta já existe, só roda o setup (retomada ou resumo).
set -euo pipefail
ASIMOV_ESTADO_DIR="${ASIMOV_ESTADO_DIR:-$HOME/.asimov}"

# Sessão persistente antes de qualquer instalação longa. Reexecutar reconecta ao mesmo processo.
if [ -t 0 ] && [ -t 1 ] && [ -z "${ASIMOV_TTY:-}" ] && [ -z "${TMUX:-}" ] && [ -z "${ASIMOV_SESSAO:-}" ]; then
  if ! command -v tmux >/dev/null 2>&1; then
    echo "Preparando sessão recuperável (tmux)..."
    if [ "$(id -u)" = 0 ]; then
      apt-get -o DPkg::Lock::Timeout=600 update && apt-get -y -o DPkg::Lock::Timeout=600 install tmux
    else
      sudo apt-get -o DPkg::Lock::Timeout=600 update && sudo apt-get -y -o DPkg::Lock::Timeout=600 install tmux
    fi
  fi
  command -v tmux >/dev/null || { echo "Instale tmux e rode novamente para ter uma sessão recuperável."; exit 1; }
  if tmux has-session -t asimov-instalacao 2>/dev/null; then exec tmux attach -t asimov-instalacao; fi
  mkdir -p "$ASIMOV_ESTADO_DIR"; chmod 700 "$ASIMOV_ESTADO_DIR"
  sessao_script="$ASIMOV_ESTADO_DIR/instalador-sessao.sh"
  if [ -f "${BASH_SOURCE[0]}" ]; then
    install -m 600 "${BASH_SOURCE[0]}" "$sessao_script"
  else
    (umask 077; curl -fsSL https://raw.githubusercontent.com/asimov-academy/asimov-agentes-setup/main/install.sh -o "$sessao_script")
  fi
  printf -v sessao_comando 'env ASIMOV_SESSAO=1 ASIMOV_ESTADO_DIR=%q ASIMOV_ATUALIZAR=%q ASIMOV_DIR=%q ASIMOV_VERSAO=%q ASIMOV_PACOTE=%q ASIMOV_SHA256=%q bash %q' \
    "$ASIMOV_ESTADO_DIR" "${ASIMOV_ATUALIZAR:-}" "${ASIMOV_DIR:-$HOME/asimov-agentes}" "${ASIMOV_VERSAO:-v0.33.2}" "${ASIMOV_PACOTE:-}" "${ASIMOV_SHA256:-}" "$sessao_script"
  echo "Se a conexão cair, rode o mesmo comando ou: tmux attach -t asimov-instalacao"
  exec tmux new-session -A -s asimov-instalacao "$sessao_comando"
fi
mkdir -p "$ASIMOV_ESTADO_DIR"; chmod 700 "$ASIMOV_ESTADO_DIR"
exec 9>"$ASIMOV_ESTADO_DIR/instalacao.lock"
flock -n 9 || { echo "Outra instalação está em andamento. Use: tmux attach -t asimov-instalacao"; exit 1; }
export ASIMOV_LOCK=1

VERSAO="${ASIMOV_VERSAO:-v0.33.2}"
PACOTE="${ASIMOV_PACOTE:-https://codeload.github.com/asimov-academy/asimov-agentes-setup/tar.gz/$VERSAO}"
SHA256="${ASIMOV_SHA256:-}"
DESTINO="${ASIMOV_DIR:-$HOME/asimov-agentes}"
# A variável é do instalador. Exportada, o Compose a leria no lugar da que o setup grava no .env.
unset ASIMOV_VERSAO

if [ -f "$DESTINO/setup/instalar.sh" ] && [ -z "${ASIMOV_ATUALIZAR:-}" ] &&
    grep -q '^instalacao_concluida=' "$ASIMOV_ESTADO_DIR/estado" 2>/dev/null; then
  exec bash "$DESTINO/setup/instalar.sh"
fi

command -v curl >/dev/null 2>&1 || { echo "Instale o curl: apt-get install -y curl"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "Instale o tar: apt-get install -y tar"; exit 1; }

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

echo "Baixando o instalador $VERSAO..."
curl -fsSL "$PACOTE" -o "$temp/pacote.tar.gz"
if [ -n "$SHA256" ]; then
  echo "$SHA256  $temp/pacote.tar.gz" | sha256sum -c --quiet - || {
    echo "O pacote baixado não confere com o checksum esperado. Abortando."
    exit 1
  }
fi

# Atualizar sobrescreve os arquivos distribuídos, e alguns o operador é orientado a editar
# (modelos/privacidade.html, modelos/prompts). Antes de extrair, uma cópia do que existe vai para
# ~/.asimov/antes-da-atualizacao/<data>: nada se perde sem volta, e é dela que o setup restaura os
# arquivos se a versão nova não subir. O .env, os prompts dos agentes e o progresso nunca são tocados.
if [ -f "$DESTINO/setup/instalar.sh" ]; then
  echo "Atualizando o instalador em $DESTINO (.env, prompts e progresso ficam)."
  guardado="$ASIMOV_ESTADO_DIR/antes-da-atualizacao/$(date +%Y%m%d-%H%M%S)"
  if mkdir -p "$guardado" 2>/dev/null; then
    for pasta in setup modelos deploy; do
      [ -d "$DESTINO/$pasta" ] && cp -a "$DESTINO/$pasta" "$guardado/" 2>/dev/null || true
    done
    echo "Cópia do que havia em setup/, modelos/ e deploy/: $guardado"
    export ASIMOV_GUARDADO="$guardado"
  fi
fi
mkdir -p "$DESTINO"
tar -xzf "$temp/pacote.tar.gz" -C "$DESTINO" --strip-components=1 --no-same-owner
exec bash "$DESTINO/setup/instalar.sh"
