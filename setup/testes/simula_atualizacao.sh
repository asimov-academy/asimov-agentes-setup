#!/usr/bin/env bash
# Simula `asimov atualizar` sem VPS: o `dc` é de mentira e a saúde da API é decidida pelo teste.
# Três cenários: a versão nova sobe; a versão nova não sobe e tudo volta para a anterior; o token
# de acesso às imagens venceu e nada é tocado.
#   bash setup/testes/simula_atualizacao.sh
set -Eeuo pipefail
RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cenario() { # cenario NOME SAUDE_DA_NOVA(0 sobe, 1 não sobe) [TOKEN(0 vale, 1 vencido)]
  local nome=$1 quebrada=$2 vencido=${3:-0} dir resultado=0
  dir=$(mktemp -d)
  # Cópia da instalação, porque a volta apaga e restaura pastas de verdade.
  mkdir -p "$dir/projeto" "$dir/guardado"
  cp -R "$RAIZ_REPO/setup" "$RAIZ_REPO/deploy" "$RAIZ_REPO/modelos" "$dir/projeto/"
  cp -R "$RAIZ_REPO/setup" "$RAIZ_REPO/deploy" "$RAIZ_REPO/modelos" "$dir/guardado/"
  echo "marca da versão anterior" >"$dir/guardado/setup/MARCA"
  (
    export HOME=$dir ASIMOV_GUARDADO=$dir/guardado
    RAIZ_PROJETO=$dir/projeto
    # shellcheck source=setup/lib/base.sh
    source "$RAIZ_PROJETO/setup/lib/base.sh"
    estado_iniciar
    clear() { :; }
    env_set ASIMOV_VERSAO v0.0.1
    estado_set versao 0.0.1
    dc() {
      echo "[$(env_get ASIMOV_VERSAO)] dc $*" >>"$dir/dc.log"
      case "$*" in *"alembic current"*) echo "abc123 (head)" ;; esac
    }
    # A API só responde saudável na versão anterior quando o cenário é o da versão quebrada.
    espera_url() { [ "$quebrada" = 0 ] || [ "$(env_get ASIMOV_VERSAO)" = v0.0.1 ]; }
    tela_instalacao() { echo "tela_instalacao" >>"$dir/dc.log"; }
    acesso_confere() { [ "$vencido" = 0 ] && return 0; ACESSO_MOTIVO=token; return 1; }
    atualiza_plataforma
  ) >"$dir/saida.log" 2>&1 || resultado=$?

  local versao
  versao=$(grep -m1 '^ASIMOV_VERSAO=' "$dir/projeto/.env" | cut -d= -f2)
  if [ "$vencido" = 1 ]; then
    # Token vencido: avisa e para antes de tocar em versão, banco ou contêiner. Sem volta, porque
    # não há o que desfazer.
    [ "$resultado" != 0 ] && [ "$versao" = v0.0.1 ] && [ ! -s "$dir/dc.log" ] &&
      grep -q "Token vencido ou trocado" "$dir/saida.log" && grep -q "asimov token" "$dir/saida.log" ||
      { echo "FALHOU: $nome"; cat "$dir/saida.log" "$dir/dc.log" 2>/dev/null; exit 1; }
  elif [ "$quebrada" = 0 ]; then
    [ "$resultado" = 0 ] && [ "$versao" != v0.0.1 ] && grep -q "tela_instalacao" "$dir/dc.log" ||
      { echo "FALHOU: $nome"; cat "$dir/saida.log" "$dir/dc.log"; exit 1; }
  else
    [ "$resultado" != 0 ] && [ "$versao" = v0.0.1 ] &&
      grep -q "alembic downgrade abc123" "$dir/dc.log" &&
      [ -f "$dir/projeto/setup/MARCA" ] && ! grep -q "tela_instalacao" "$dir/dc.log" ||
      { echo "FALHOU: $nome"; cat "$dir/saida.log" "$dir/dc.log"; exit 1; }
  fi
  echo "ok: $nome"
  rm -rf "$dir"
}

cenario "versão nova sobe" 0
cenario "versão nova não sobe e volta para a anterior" 1
cenario "token vencido para antes de mexer em qualquer coisa" 0 1
