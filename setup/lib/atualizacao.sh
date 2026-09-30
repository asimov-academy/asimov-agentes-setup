#!/usr/bin/env bash
# `asimov atualizar`: troca a versão das imagens e volta para a anterior se a nova não subir
# saudável, no mesmo espírito de `atualiza_waha`. Quem chama é `atualiza`, em setup/instalar.sh,
# depois de o install.sh ter trocado os arquivos do setup e guardado os antigos em ASIMOV_GUARDADO.

# revisao_do_banco: a migração em que o banco está, vista pela imagem que está no ar.
revisao_do_banco() {
  dc run --rm api alembic current 2>>"$LOG" | awk '/^[0-9a-f]+/ {print $1; exit}' || true
}

# sobe_versao: tudo o que pode dar errado numa versão nova, numa função só, para ter uma volta só.
# Só imagem pública aqui: token vencido não pode desfazer a atualização da plataforma inteira.
sobe_versao() {
  dc pull api worker &&
    migra &&
    sobe_servicos &&
    espera_url "${API_LOCAL:-http://127.0.0.1:8000}/health" 24
}

# atualiza_privadas: painel e copiloto, que vêm de imagem privada. Roda depois de a plataforma
# estar de pé e nunca desfaz nada: sem token válido, o painel fica na versão anterior e o operador
# resolve com `asimov token`. A plataforma no terminal segue na versão nova.
atualiza_privadas() {
  painel_ligado || return 0
  if ! dc pull painel >>"$LOG" 2>&1; then
    aviso "Token vencido ou trocado: o painel ficou na versão anterior."
    dica "Rode $(destaque "asimov token") e depois $(destaque "asimov atualizar") de novo."
    return 0
  fi
  dc up -d --force-recreate painel >>"$LOG" 2>&1 || true
  grep -q '^COPILOTO_ATIVO=1$' "$ARQ_ENV" 2>/dev/null || return 0
  if dc pull copiloto >>"$LOG" 2>&1; then
    dc up -d --force-recreate copiloto >>"$LOG" 2>&1 || true
  else
    aviso "O copiloto ficou na versão anterior: o registro recusou o token."
  fi
}

# atualiza_assinatura: o contêiner da assinatura na versão nova. Imagem pública, mas fora de
# `sobe_versao`: um experimento que não sobe não pode desfazer a atualização da plataforma.
atualiza_assinatura() {
  assinatura_ligada || return 0
  assinatura_acerta || aviso "O contêiner da assinatura não subiu na versão nova: os agentes respondem pela reserva."
}

# volta_versao ANTERIOR REVISAO: imagens, banco e arquivos do setup de volta ao que estava no ar.
volta_versao() {
  local anterior=$1 revisao=$2 pasta
  # O banco volta primeiro, e com a imagem nova: só ela conhece o caminho de volta das migrações
  # que aplicou. Se falhar, segue: migração daqui é aditiva, e a imagem anterior convive com ela.
  if [ -n "$revisao" ]; then
    dc run --rm api alembic downgrade "$revisao" >>"$LOG" 2>&1 || true
  fi
  env_set ASIMOV_VERSAO "$anterior"
  estado_set versao "${anterior#v}"
  # setup/ é apagada e copiada, nunca escrita por cima: o bash ainda está lendo os arquivos atuais.
  # deploy/ e modelos/ não: api, worker e caddy montam essas pastas, e a montagem fica presa ao
  # diretório de quando o contêiner subiu. Apagada, ela ficava vazia lá dentro (sem /privacidade,
  # sem o bloco do painel), e nada recriava os contêineres. Nelas saem só os arquivos, e as
  # subpastas (deploy/caddy) ficam.
  if [ -d "${ASIMOV_GUARDADO:-}" ]; then
    for pasta in setup deploy modelos; do
      [ -d "$ASIMOV_GUARDADO/$pasta" ] || continue
      if [ "$pasta" = setup ] || [ ! -d "$RAIZ_PROJETO/$pasta" ]; then
        rm -rf "${RAIZ_PROJETO:?}/$pasta"
        cp -a "$ASIMOV_GUARDADO/$pasta" "$RAIZ_PROJETO/$pasta"
      else
        find "${RAIZ_PROJETO:?}/$pasta" -mindepth 1 ! -type d -delete
        cp -a "$ASIMOV_GUARDADO/$pasta/." "$RAIZ_PROJETO/$pasta/"
      fi
    done
  fi
  sobe_servicos >>"$LOG" 2>&1 || true
  printf '%s atualização desfeita: voltei para %s\n' "$(date -Is)" "$anterior" >>"$LOG"
}

# atualiza_plataforma: sem versão anterior no .env, ou já na versão deste setup, é só a instalação
# de sempre, que retoma de onde parou.
atualiza_plataforma() {
  local anterior revisao
  anterior=$(env_get ASIMOV_VERSAO)
  if [ -z "$anterior" ] || [ "$anterior" = "v$VERSAO" ]; then
    tela_instalacao
    return 0
  fi

  secao "Atualização"
  info "De $(destaque "$anterior") para $(destaque "v$VERSAO"). A plataforma fica fora do ar por alguns segundos."
  echo
  printf '\n===== %s: atualização %s -> v%s =====\n' "$(date -Is)" "$anterior" "$VERSAO" >>"$LOG"
  revisao=$(revisao_do_banco)
  env_set ASIMOV_VERSAO "v$VERSAO"
  printf '  %sBaixando e subindo a versão nova…%s' "$CINZA" "$NORMAL"
  if ! sobe_versao >>"$LOG" 2>&1; then
    printf '\r\033[K'
    falha "A versão v$VERSAO não subiu saudável. Voltando para $anterior."
    volta_versao "$anterior" "$revisao"
    if espera_url "${API_LOCAL:-http://127.0.0.1:8000}/health" 24 >>"$LOG" 2>&1; then
      ok "Plataforma de volta em $(destaque "$anterior"), respondendo."
    else
      falha "A versão anterior também não respondeu."
    fi
    erro_fatal "Atualização desfeita" "Envie as últimas linhas do log ao suporte e tente asimov atualizar mais tarde."
  fi
  printf '\r\033[K'
  ok "Versão $(destaque "v$VERSAO") no ar."
  atualiza_privadas
  atualiza_assinatura
  echo
  # O que já foi feito aqui não repete na tela de instalação, que confere o resto (HTTPS, WAHA, backup).
  local passo_feito
  for passo_feito in imagens banco migracoes servicos api_local; do
    estado_set "passo_$passo_feito" "$(date -Is)"
  done
  tela_instalacao
}
