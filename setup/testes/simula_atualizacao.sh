#!/usr/bin/env bash
# Simula `asimov atualizar` sem VPS: o `dc` é de mentira e a saúde da API é decidida pelo teste.
# Dois cenários: a versão nova sobe; a versão nova não sobe e tudo volta para a anterior.
#   bash setup/testes/simula_atualizacao.sh
set -Eeuo pipefail
RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cenario() { # cenario NOME SAUDE_DA_NOVA(0 sobe, 1 não sobe) [PAINEL(1 ligado, token vencido)]
  local nome=$1 quebrada=$2 painel=${3:-} dir resultado=0
  dir=$(mktemp -d)
  # Cópia da instalação, porque a volta apaga e restaura pastas de verdade.
  mkdir -p "$dir/projeto" "$dir/guardado"
  cp -R "$RAIZ_REPO/setup" "$RAIZ_REPO/deploy" "$RAIZ_REPO/modelos" "$dir/projeto/"
  cp -R "$RAIZ_REPO/setup" "$RAIZ_REPO/deploy" "$RAIZ_REPO/modelos" "$dir/guardado/"
  echo "marca da versão anterior" >"$dir/guardado/setup/MARCA"
  # api, worker e caddy montam essas pastas: a volta tem que manter o mesmo diretório.
  local inode_modelos inode_extras
  inode_modelos=$(ls -di "$dir/projeto/modelos" | awk '{print $1}')
  inode_extras=$(ls -di "$dir/projeto/deploy/caddy" | awk '{print $1}')
  (
    export HOME=$dir ASIMOV_GUARDADO=$dir/guardado
    RAIZ_PROJETO=$dir/projeto
    # shellcheck source=setup/lib/base.sh
    source "$RAIZ_PROJETO/setup/lib/base.sh"
    estado_iniciar
    clear() { :; }
    env_set ASIMOV_VERSAO v0.0.1
    estado_set versao 0.0.1
    [ -z "$painel" ] || env_set PAINEL_ATIVO 1
    dc() {
      echo "[$(env_get ASIMOV_VERSAO)] dc $*" >>"$dir/dc.log"
      case "$*" in
        *"alembic current"*) echo "abc123 (head)" ;;
        # O contêiner ainda enxerga o Caddyfile de antes da extração (inode antigo).
        *"cat /etc/caddy/Caddyfile"*) echo "Caddyfile antigo" ;;
      esac
      # Token vencido: o registro recusa a imagem privada, e o `up` sem ela no disco falha.
      if [ -n "$painel" ] && [ "$(env_get ASIMOV_VERSAO)" != v0.0.1 ]; then
        case "$*" in "pull painel" | *"up "*painel*) return 1 ;; esac
      fi
    }
    # A API só responde saudável na versão anterior quando o cenário é o da versão quebrada.
    espera_url() { [ "$quebrada" = 0 ] || [ "$(env_get ASIMOV_VERSAO)" = v0.0.1 ]; }
    tela_instalacao() { echo "tela_instalacao" >>"$dir/dc.log"; }
    atualiza_plataforma
  ) >"$dir/saida.log" 2>&1 || resultado=$?

  local versao
  versao=$(grep -m1 '^ASIMOV_VERSAO=' "$dir/projeto/.env" | cut -d= -f2)
  if [ "$quebrada" = 0 ]; then
    [ "$resultado" = 0 ] && [ "$versao" != v0.0.1 ] && grep -q "tela_instalacao" "$dir/dc.log" &&
      ! grep -q "alembic downgrade" "$dir/dc.log" ||
      { echo "FALHOU: $nome"; cat "$dir/saida.log" "$dir/dc.log"; exit 1; }
    grep -q "dc restart caddy" "$dir/dc.log" ||
      { echo "FALHOU: $nome (Caddy com o Caddyfile antigo não reiniciou)"; cat "$dir/dc.log"; exit 1; }
    [ -z "$painel" ] || grep -q "Token vencido" "$dir/saida.log" ||
      { echo "FALHOU: $nome (sem aviso do token)"; cat "$dir/saida.log"; exit 1; }
  else
    [ "$resultado" != 0 ] && [ "$versao" = v0.0.1 ] &&
      grep -q "alembic downgrade abc123" "$dir/dc.log" &&
      [ -f "$dir/projeto/setup/MARCA" ] && ! grep -q "tela_instalacao" "$dir/dc.log" ||
      { echo "FALHOU: $nome"; cat "$dir/saida.log" "$dir/dc.log"; exit 1; }
    [ "$(ls -di "$dir/projeto/modelos" | awk '{print $1}')" = "$inode_modelos" ] &&
      [ "$(ls -di "$dir/projeto/deploy/caddy" | awk '{print $1}')" = "$inode_extras" ] ||
      { echo "FALHOU: $nome (a volta trocou pasta montada nos contêineres)"; exit 1; }
  fi
  echo "ok: $nome"
  rm -rf "$dir"
}

cenario "versão nova sobe" 0
cenario "versão nova não sobe e volta para a anterior" 1
cenario "painel com token vencido não desfaz a versão nova" 0 1
