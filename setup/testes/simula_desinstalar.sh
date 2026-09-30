#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034,SC2030,SC2031  # Comandos falsos; o subshell muda variável de propósito.
# `asimov desinstalar` com Docker, systemd, tmux e Caddy de mentira, tudo numa pasta temporária.
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
HOME="$TEMP_TESTE/casa"
RAIZ_PROJETO="$HOME/asimov-agentes"
DIR_ESTADO="$HOME/.asimov"
ARQ_ESTADO="$DIR_ESTADO/estado"
ARQ_ENV="$RAIZ_PROJETO/.env"
LOG="$DIR_ESTADO/setup.log"
DIR_SYSTEMD="$TEMP_TESTE/systemd"
LINK_COMANDO="$TEMP_TESTE/bin/asimov"
PASTA_DO_SISTEMA="$TEMP_TESTE/var-lib-asimov"
CADDYFILE="$TEMP_TESTE/caddy/Caddyfile"
REGISTRO_DE_COMANDOS="$TEMP_TESTE/comandos"
URL_INSTALL="https://exemplo.invalid/install.sh"
VERSAO="0.0.0-teste"
SUDO=""
RESPOSTAS="$TEMP_TESTE/respostas"
: >"$RESPOSTAS"
export ASIMOV_TTY="$RESPOSTAS"
# shellcheck source=setup/lib/ui.sh
source "$REPO/setup/lib/ui.sh"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/acesso.sh
source "$REPO/setup/lib/acesso.sh"
# shellcheck source=setup/lib/desinstalar.sh
source "$REPO/setup/lib/desinstalar.sh"
date() { command date '+%Y-%m-%dT%H:%M:%S'; }
docker() {
  echo "docker $*" >>"$REGISTRO_DE_COMANDOS"
  case "$1 $2" in
    "ps -aq") printf 'c1\nc2\n' ;;
    "volume ls") echo asimov_postgres ;;
    "network ls") echo asimov_default ;;
    "image ls") printf '%s\n' ghcr.io/asimov-academy/agentes-backend:v0.34.0 devlikeapro/waha:gows-2026.8.2 nginx:latest ;;
  esac
}
systemctl() { echo "systemctl $*" >>"$REGISTRO_DE_COMANDOS"; [ "$1" != is-active ]; }
tmux() { echo "tmux $*" >>"$REGISTRO_DE_COMANDOS"; [ "$1" = has-session ]; }
caddy() { echo "caddy $*" >>"$REGISTRO_DE_COMANDOS"; }

# Uma VPS com o Asimov instalado ao lado de outro site no Caddy do host.
prepara_vps() {
  rm -rf "${HOME:?}" "${DIR_SYSTEMD:?}" "${TEMP_TESTE:?}/bin" "${PASTA_DO_SISTEMA:?}" "${TEMP_TESTE:?}/caddy"
  : >"$REGISTRO_DE_COMANDOS"
  mkdir -p "$RAIZ_PROJETO/setup" "$RAIZ_PROJETO/deploy" "$RAIZ_PROJETO/prompts/loja-exemplo/ana" \
    "$DIR_ESTADO/caddy-antes.teste" "$DIR_SYSTEMD" "$TEMP_TESTE/bin" "$PASTA_DO_SISTEMA/backups" \
    "$PASTA_DO_SISTEMA/restos" "$TEMP_TESTE/caddy" "$HOME/.claude"
  touch "$RAIZ_PROJETO/setup/asimov.sh" "$RAIZ_PROJETO/deploy/docker-compose.yml" "$ARQ_ESTADO" "$LOG"
  printf 'CHAVE_CRIPTOGRAFIA=teste\n' >"$ARQ_ENV"
  printf 'Você é Ana.\n' >"$RAIZ_PROJETO/prompts/loja-exemplo/ana/persona.md"
  printf '#!/usr/bin/env bash\ntouch "%s/backups/asimov-novo.sql.gz"\n' "$PASTA_DO_SISTEMA" >"$RAIZ_PROJETO/deploy/backup.sh"
  # Sem chmod +x: o tarball do codeload traz o modo do repositório, e o setup não pode depender dele.
  touch "$PASTA_DO_SISTEMA/backups/asimov-antigo.sql.gz" "$HOME/.claude/.credentials.json"
  printf '%s\n' "$CADDYFILE" >"$DIR_ESTADO/caddy-antes.teste/alvo"
  printf 'outro.exemplo.com.br {\n respond "outro site"\n}\n\nimport %s\n' "$TEMP_TESTE/caddy/asimov.caddy" >"$CADDYFILE"
  printf '# Gerado pelo Asimov. O gateway interno bloqueia /admin.\nbot.exemplo.com.br {\n}\n' >"$TEMP_TESTE/caddy/asimov.caddy"
  for unidade in "${UNIDADES_DO_ASIMOV[@]}"; do touch "$DIR_SYSTEMD/$unidade"; done
  touch "$DIR_SYSTEMD/outro.service"
  ln -s "$RAIZ_PROJETO/setup/asimov.sh" "$LINK_COMANDO"
}

responde() {
  printf '%s\n' "$@" >"$RESPOSTAS"
  exec 3<"$RESPOSTAS"
}

rodou() { grep -qxF "$1" "$REGISTRO_DE_COMANDOS"; }

# Sem a palavra de confirmação, nada sai.
prepara_vps
responde n n sim
fluxo_desinstalar >/dev/null
[ -f "$ARQ_ENV" ] && [ -L "$LINK_COMANDO" ] && [ -f "$DIR_SYSTEMD/asimov-backup.timer" ]
grep -q "^import " "$CADDYFILE"
if grep -q '^docker ' "$REGISTRO_DE_COMANDOS"; then exit 1; fi
echo 'ok: confirmação errada não remove nada'

# Com backup: sai tudo o que é do Asimov, e só isso.
prepara_vps
responde s desinstalar
fluxo_desinstalar >/dev/null
[ ! -e "$RAIZ_PROJETO" ] && [ ! -e "$DIR_ESTADO" ] && [ ! -e "$LINK_COMANDO" ]
for unidade in "${UNIDADES_DO_ASIMOV[@]}"; do [ ! -e "$DIR_SYSTEMD/$unidade" ]; done
[ -e "$DIR_SYSTEMD/outro.service" ]
rodou "systemctl disable --now asimov-backup.timer"
rodou "docker rm -f c1 c2"
rodou "docker volume rm asimov_postgres"
rodou "docker network rm asimov_default"
rodou "docker image rm ghcr.io/asimov-academy/agentes-backend:v0.34.0"
rodou "docker image rm devlikeapro/waha:gows-2026.8.2"
if rodou "docker image rm nginx:latest"; then echo 'FALHOU: imagem de outra aplicação'; exit 1; fi
rodou "docker logout ghcr.io"
rodou "tmux kill-session -t asimov-instalacao"
echo 'ok: contêineres, volumes, imagens, timers, sessão e comando saem'

if grep -q '^import ' "$CADDYFILE"; then echo 'FALHOU: import do Asimov ficou'; exit 1; fi
grep -q 'outro site' "$CADDYFILE"
[ ! -e "$TEMP_TESTE/caddy/asimov.caddy" ]
grep -qF "caddy validate --config $CADDYFILE." "$REGISTRO_DE_COMANDOS"
echo 'ok: Caddy da VPS perde só o import e o snippet do Asimov'

[ -e "$PASTA_DO_SISTEMA/backups/asimov-novo.sql.gz" ] && [ -e "$PASTA_DO_SISTEMA/backups/asimov-antigo.sql.gz" ]
[ ! -e "$PASTA_DO_SISTEMA/restos" ]
[ -e "$HOME/.claude/.credentials.json" ]
echo 'ok: backups e conta do Claude Code ficam'

# Sem backup e apagando os antigos: a pasta do sistema sai inteira.
prepara_vps
responde n s desinstalar
fluxo_desinstalar >/dev/null
[ ! -e "$PASTA_DO_SISTEMA" ] && [ ! -e "$RAIZ_PROJETO" ]
echo 'ok: backups antigos saem quando o operador pede'

# Interrompida no meio: rodar de novo termina, com o que já saiu fora do caminho.
prepara_vps
rm -f "$DIR_SYSTEMD"/asimov-* "$TEMP_TESTE/caddy/asimov.caddy"
printf 'outro.exemplo.com.br {\n}\n' >"$CADDYFILE"
docker() { echo "docker $*" >>"$REGISTRO_DE_COMANDOS"; }
responde n n desinstalar
fluxo_desinstalar >/dev/null
[ ! -e "$RAIZ_PROJETO" ] && [ ! -e "$LINK_COMANDO" ] && [ -e "$PASTA_DO_SISTEMA/backups/asimov-antigo.sql.gz" ]
grep -q 'outro.exemplo.com.br' "$CADDYFILE"
echo 'ok: desinstalação repetida termina o que faltou'

# Link de outro programa com o mesmo nome não é nosso.
prepara_vps
rm "$LINK_COMANDO"
touch "$TEMP_TESTE/outro-asimov"
ln -s "$TEMP_TESTE/outro-asimov" "$LINK_COMANDO"
desinstala_comando
[ -L "$LINK_COMANDO" ]
echo 'ok: comando asimov de outro programa fica'

# Pasta errada nunca vira rm -rf da casa do usuário.
(
  RAIZ_PROJETO="$HOME"
  touch "$HOME/importante"
  if desinstala_pastas 0; then exit 1; fi
  [ -e "$HOME/importante" ]
)
echo 'ok: pasta que não é do Asimov não é apagada'

# Backup que falha pergunta antes de seguir; recusar não remove nada.
prepara_vps
printf '#!/usr/bin/env bash\nexit 1\n' >"$RAIZ_PROJETO/deploy/backup.sh"
responde s desinstalar n
fluxo_desinstalar >/dev/null
[ -f "$ARQ_ENV" ] && [ -f "$DIR_SYSTEMD/asimov-backup.timer" ]
echo 'ok: backup que falha não deixa desinstalar sem perguntar'

# Script de deploy/ que o systemd ou o setup chamam vai versionado executável.
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  ! git -C "$REPO" ls-files -s 'deploy/*.sh' | grep -v '^100755'
  echo 'ok: scripts de deploy/ versionados executáveis'
fi

echo 'Desinstalação: todos os cenários passaram.'
