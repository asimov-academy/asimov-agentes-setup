#!/usr/bin/env bash
# Chamado pelo timer asimov-backup.timer (de madrugada), nunca à mão no dia a dia.
# Guarda o banco e o `.env` em /var/lib/asimov/backups, apaga o que passou da retenção e registra o
# resultado no estado do setup, que é o que o menu mostra.
#
# O que entra: o dump do Postgres (que tem conversas, agentes e credenciais cifradas) e o `.env`
# (que tem a chave que decifra essas credenciais). Sem o `.env`, o dump não serve para restaurar.
# Por isso a pasta é 700 e cada arquivo 600: quem lê o backup lê a instalação inteira.
set -Eeuo pipefail
umask 077

RAIZ_PROJETO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=setup/lib/base.sh
source "$RAIZ_PROJETO/setup/lib/base.sh"
# shellcheck source=deploy/compose.sh
source "$RAIZ_PROJETO/deploy/compose.sh"

PASTA_BACKUP=${PASTA_BACKUP:-/var/lib/asimov/backups}
DIAS_DE_RETENCAO=${DIAS_DE_RETENCAO:-14}

estado_iniciar
printf '\n===== backup em %s =====\n' "$(date -Is)" >>"$LOG"

mkdir -p "$PASTA_BACKUP"
chmod 700 "$PASTA_BACKUP"

carimbo=$(date +%Y%m%d-%H%M%S)
arquivo="$PASTA_BACKUP/asimov-$carimbo.sql.gz"

parcial_prompts="$PASTA_BACKUP/prompts-$carimbo.tar.gz.parcial"
parcial_conhecimento="$PASTA_BACKUP/conhecimento-$carimbo.tar.gz.parcial"

if dc exec -T postgres pg_dump -U "$(env_get POSTGRES_USER)" "$(env_get POSTGRES_DB)" 2>>"$LOG" |
  gzip >"$arquivo.parcial"; then
  mv "$arquivo.parcial" "$arquivo"
  chmod 600 "$arquivo"
  # O dump é o que restaura a instalação: registra a data agora, para o menu não dizer que a noite
  # passou em branco quando só o resto falhar. A falha abaixo ainda aparece, e vence na tela.
  estado_set backup_em "$(date -Is)"
  if ! cp "$RAIZ_PROJETO/.env" "$PASTA_BACKUP/env-$carimbo" 2>>"$LOG" ||
    ! tar -czf "$parcial_prompts" -C "$RAIZ_PROJETO" prompts 2>>"$LOG" ||
    ! dc exec -T worker tar -czf - -C /var/lib/asimov conhecimento >"$parcial_conhecimento" 2>>"$LOG"; then
    # A retenção lá embaixo só varre `*.tar.gz`: `.parcial` que sobrar aqui fica no disco para
    # sempre, e uma falha que se repete toda noite enche a pasta.
    rm -f "$parcial_prompts" "$parcial_conhecimento"
    estado_set backup_falhou "$(date -Is)"
    printf 'backup: dump do banco gravado em %s, mas o .env, os prompts ou o conhecimento falhou\n' "$arquivo" >>"$LOG"
    exit 1
  fi
  mv "$parcial_prompts" "$PASTA_BACKUP/prompts-$carimbo.tar.gz"
  mv "$parcial_conhecimento" "$PASTA_BACKUP/conhecimento-$carimbo.tar.gz"
  chmod 600 "$PASTA_BACKUP/env-$carimbo" "$PASTA_BACKUP/prompts-$carimbo.tar.gz" "$PASTA_BACKUP/conhecimento-$carimbo.tar.gz"
  estado_set backup_falhou ""
  printf 'backup gravado em %s\n' "$arquivo" >>"$LOG"
else
  rm -f "$arquivo.parcial"
  estado_set backup_falhou "$(date -Is)"
  printf 'backup falhou\n' >>"$LOG"
  exit 1
fi

# Retenção: o que passou do prazo sai, e o dump mais novo nunca sai, mesmo que o prazo seja curto.
find "$PASTA_BACKUP" -maxdepth 1 -name 'asimov-*.sql.gz' -mtime "+$DIAS_DE_RETENCAO" -delete 2>>"$LOG" || true
find "$PASTA_BACKUP" -maxdepth 1 -name 'env-*' -mtime "+$DIAS_DE_RETENCAO" -delete 2>>"$LOG" || true

find "$PASTA_BACKUP" -maxdepth 1 -name 'prompts-*.tar.gz' -mtime "+$DIAS_DE_RETENCAO" -delete 2>>"$LOG" || true
find "$PASTA_BACKUP" -maxdepth 1 -name 'conhecimento-*.tar.gz' -mtime "+$DIAS_DE_RETENCAO" -delete 2>>"$LOG" || true
