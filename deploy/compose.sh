#!/usr/bin/env bash
# Carregado por setup/lib/base.sh. Define `dc`, o docker compose da instalação.

RAIZ_PROJETO="${RAIZ_PROJETO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# O painel, o copiloto e a assinatura entram no Compose por perfil: o painel roda a imagem privada
# com o front dentro, o copiloto só depois de vincular a conta de IA, e a assinatura só quando
# `asimov ia` a liga. Sem o perfil, `dc up` derrubaria o que
# setup/lib/painel.sh e setup/lib/vinculo.sh subiram. A WAHA não tem perfil: ela é instalada com o
# resto da plataforma, senão ligar o WhatsApp pelo painel esbarra num contêiner que ninguém subiu.
dc() {
  # A versão das imagens vem só do .env: variável de mesmo nome no shell passaria por cima dele.
  unset ASIMOV_VERSAO
  local perfis=()
  if grep -q '^PAINEL_ATIVO=1$' "$RAIZ_PROJETO/.env" 2>/dev/null; then
    perfis+=(--profile painel)
  fi
  if grep -q '^COPILOTO_ATIVO=1$' "$RAIZ_PROJETO/.env" 2>/dev/null; then
    perfis+=(--profile copiloto)
  fi
  if grep -q '^ASSINATURA_NO_ATENDIMENTO=1$' "$RAIZ_PROJETO/.env" 2>/dev/null; then
    perfis+=(--profile assinatura)
  fi
  ${SUDO:-} docker compose --project-name asimov \
    --env-file "$RAIZ_PROJETO/.env" \
    -f "$RAIZ_PROJETO/deploy/docker-compose.yml" "${perfis[@]}" "$@"
}
