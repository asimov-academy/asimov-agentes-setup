#!/usr/bin/env bash
# Setup Asimov Academy: prepara uma VPS Ubuntu 24.04 vazia e sobe a plataforma de agentes.
# Pode ser rodado de novo a qualquer momento: continua de onde parou ou atualiza a instalação.
set -Eeuo pipefail

RAIZ_PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=setup/lib/base.sh
source "$RAIZ_PROJETO/setup/lib/base.sh"

# Instalação já concluída: completa o que versões novas pedem (modo), troca a versão das imagens
# (voltando para a anterior se a nova não subir), mostra o resumo e abre o menu. `asimov atualizar` para no resumo.
atualiza() {
  banner_asimov
  tela_modo
  atualiza_plataforma
  confere_https_depois_de_atualizar
  ajusta_permissoes
  instala_comando
  gera_arquivos_de_contexto || erro_fatal "Não foi possível preparar o contexto dos assistentes" "Confira $LOG e rode novamente."
  # O pacote da atualização traz o painel.caddy desligado por cima do bloco do operador.
  painel_garante_caddy
  confere_painel_depois_de_atualizar
  # A WAHA passou a vir com a instalação: VPS instalada por uma versão anterior pode não ter o
  # contêiner, o timer semanal nem os eventos de hoje nas sessões que já existem.
  garante_waha
  instala_timer_waha || true
  reconfigura_sessoes_waha
  tela_handoff_pendente
  tela_vinculo_ia
  tela_painel_oferta
  mostra_resumo
  [ -n "${ASIMOV_ATUALIZAR:-}" ] || menu_operador
}

principal() {
  estado_iniciar
  trava_instalacao
  estado_tem instalacao_concluida || tela_boas_vindas
  inventario_instalacao
  prepara_rede
  estado_nova_versao
  printf '\n===== setup %s iniciado em %s =====\n' "$VERSAO" "$(date -Is)" >>"$LOG"

  if estado_tem instalacao_concluida; then
    atualiza
    exit 0
  fi

  tela_boas_vindas
  tela_modo
  tela_iniciando
  tela_dados
  tela_dns
  tela_instalacao
  ajusta_permissoes
  # O essencial está no ar. A conta de IA vem antes do painel: vinculada, o painel já nasce com o
  # copiloto. O painel vem antes do primeiro agente: quem liga o painel cria o agente por lá, no
  # passo a passo com prévia; quem fica no terminal cria aqui.
  tela_vinculo_ia
  tela_painel_oferta
  tela_primeiro_agente
  estado_set handoff_perguntado "$(date -Is)"
  tela_final
}

principal "$@"
