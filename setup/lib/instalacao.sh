#!/usr/bin/env bash
# shellcheck disable=SC2034  # PASSO_ATUAL e PASSO_TOTAL são lidas por passo(), em estado.sh
# Tela 5: firewall, ferramentas de desenvolvimento, segredos e a plataforma no ar.

# garante_swap: abaixo de 4 GB, 2 GB de swap. A plataforma inteira (WAHA e copiloto em uso) encosta
# em 2 GB de RAM; sem swap, o kernel mata um contêiner no meio de um atendimento. Não mexe em VPS
# que já tem swap, seja qual for o tamanho.
garante_swap() {
  local memoria
  memoria=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  [ "$memoria" -lt 3800 ] || return 0
  [ "$(awk 'NR>1' /proc/swaps | wc -l)" -eq 0 ] || return 0
  [ ! -e /swapfile ] || return 0
  $SUDO fallocate -l 2G /swapfile || $SUDO dd if=/dev/zero of=/swapfile bs=1M count=2048
  $SUDO chmod 600 /swapfile
  $SUDO mkswap /swapfile
  $SUDO swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab >/dev/null
}

firewall() {
  local porta
  # Libera a porta real do SSH antes de ligar o firewall, para não trancar o operador fora.
  for porta in $($SUDO ss -tlnpH 2>/dev/null | awk '/sshd/ {n=split($4,a,":"); print a[n]}' | sort -u); do
    $SUDO ufw allow "$porta/tcp"
  done
  $SUDO ufw allow OpenSSH
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp
  $SUDO ufw --force enable
  [ "$(env_get PROVEDOR_VPS)" = oracle ] && abre_iptables_da_oracle
  return 0
}

# A imagem Ubuntu da Oracle Cloud carrega um `REJECT` no fim da cadeia INPUT, e as cadeias do ufw
# entram depois dele: `ufw allow` sozinho não abre nada. O ACCEPT de 80 e 443 vai antes do REJECT.
# Persistência: com o netfilter-persistent da imagem, salva nele; se o pacote saiu quando o ufw
# entrou, as regras da imagem não voltam no boot e quem vale é o ufw, que já libera as duas portas.
# A Security List no painel da Oracle é com o operador: daqui não dá para ver nem mudar.
abre_iptables_da_oracle() {
  local porta posicao
  for porta in 80 443; do
    while $SUDO iptables -D INPUT -p tcp --dport "$porta" -j ACCEPT 2>/dev/null; do :; done
    posicao=$($SUDO iptables -L INPUT -n --line-numbers | awk '$2 == "REJECT" {print $1; exit}' || true)
    $SUDO iptables -I INPUT "${posicao:-1}" -p tcp --dport "$porta" -j ACCEPT
  done
  if command -v netfilter-persistent >/dev/null 2>&1; then
    $SUDO netfilter-persistent save
  fi
}

# Só quem escolhe o Codex precisa de Node na VPS: o CLI dele é um pacote npm. O Claude Code tem
# instalador próprio.
instala_node() {
  command -v node >/dev/null 2>&1 && return 0
  curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource.sh
  $SUDO bash /tmp/nodesource.sh
  apt_instala nodejs
}

instala_agente_codigo() {
  if [ "$(env_get AGENTE_CODIGO)" = codex ]; then
    instala_node
    command -v codex >/dev/null 2>&1 || $SUDO npm install -g @openai/codex
  else
    command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ] ||
      curl -fsSL https://claude.ai/install.sh | bash
  fi
}

gera_segredos() {
  env_set_se_vazio POSTGRES_USER asimov
  env_set_se_vazio POSTGRES_DB asimov
  env_set_se_vazio POSTGRES_PASSWORD "$(openssl rand -hex 24)"
  env_set_se_vazio CHAVE_API_ADMIN "$(openssl rand -hex 32)"
  env_set_se_vazio CHAVE_CRIPTOGRAFIA "$(openssl rand -base64 32 | tr '+/' '-_')"
  # A chave da WAHA nasce aqui mesmo sem o contêiner dela: assim ligar o WhatsApp depois não
  # precisa reiniciar a API para ela enxergar a chave nova.
  env_set_se_vazio WAHA_API_KEY "$(openssl rand -hex 32)"
  env_set_se_vazio LOG_NIVEL INFO
  for variavel in OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GROQ_API_KEY MODELO_FALLBACK; do
    env_set_se_vazio "$variavel" ""
  done
  # Os contêineres rodam com o usuário 1000 e criam os prompts de cada agente.
  mkdir -p "$RAIZ_PROJETO/prompts"
  $SUDO chown -R 1000:1000 "$RAIZ_PROJETO/prompts"
}

# Roda em toda execução: extrair uma atualização como root devolve prompts/ ao root, e a API
# (usuário 1000 no contêiner) deixaria de conseguir criar o prompt de um agente novo.
ajusta_permissoes() {
  mkdir -p "$RAIZ_PROJETO/prompts"
  $SUDO chown -R 1000:1000 "$RAIZ_PROJETO/prompts"
}

# A VPS não constrói nada: puxa do GHCR as imagens da versão deste setup. ASIMOV_VERSAO é o que o
# Compose lê; gravar aqui, e não no install.sh, mantém `.env` e setup sempre na mesma versão.
baixa_imagens() {
  env_set ASIMOV_VERSAO "v$VERSAO"
  dc pull api worker
}

sobe_banco() { dc up -d --wait postgres redis; }
migra() { dc run --rm api alembic upgrade head; }
sobe_servicos() {
  dc up -d api worker caddy
  # O Caddyfile é montado, então atualizar o projeto muda o arquivo mas não o que o Caddy já
  # carregou: caminho público novo continuava respondendo 404 depois de `asimov atualizar`.
  # `reload` não derruba conexão; se ele falhar (contêiner recém-criado, por exemplo), reinicia.
  dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >>"$LOG" 2>&1 ||
    dc restart caddy >>"$LOG" 2>&1 || true
}

espera_url() {
  local url=$1 tentativas=${2:-24}
  for _ in $(seq 1 "$tentativas"); do
    curl -fsS --max-time 10 "$url" && return 0
    sleep 5
  done
  return 1
}

# instala_timer_backup: dump do banco e cópia do .env todo dia de madrugada, com retenção.
# Roda no host, como o timer da WAHA: quem fala com o Docker é o host, nunca um contêiner.
instala_timer_backup() {
  local quando="*-*-* 03:20:00 America/Sao_Paulo"
  command -v systemctl >/dev/null 2>&1 || return 0
  if ! systemd-analyze calendar "$quando" >/dev/null 2>&1; then
    quando="*-*-* 03:20:00"
  fi
  $SUDO tee /etc/systemd/system/asimov-backup.service >/dev/null <<UNIDADE || return 1
[Unit]
Description=Backup diário do Asimov Agentes
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
Environment=HOME=$HOME
ExecStart=$RAIZ_PROJETO/deploy/backup.sh
UNIDADE
  $SUDO tee /etc/systemd/system/asimov-backup.timer >/dev/null <<UNIDADE || return 1
[Unit]
Description=Guarda o banco e o .env todo dia

[Timer]
OnCalendar=$quando
RandomizedDelaySec=20m
Persistent=true

[Install]
WantedBy=timers.target
UNIDADE
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || return 1
  $SUDO systemctl enable --now asimov-backup.timer >/dev/null 2>&1 || return 1
  return 0
}

# confere_maquina: o que a VPS precisa ter antes de a instalação começar a demorar.
# Aviso, não impedimento: a pessoa pode saber de algo que a checagem não sabe, e travar a
# instalação por 200 MB de RAM a menos seria pior que deixá-la tentar.
confere_maquina() {
  local memoria disco
  memoria=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  disco=$(df -m --output=avail "$RAIZ_PROJETO" 2>/dev/null | tail -1 | tr -d ' ' || echo 0)
  [ "${memoria:-0}" -ge 1900 ] || aviso "Esta VPS tem ${memoria} MB de memória. Abaixo de 2 GB a plataforma pode ser morta por falta de memória."
  [ "${disco:-0}" -ge 8000 ] || aviso "Restam ${disco} MB de disco. As imagens do Docker pedem uns 8 GB."
  return 0
}

# confere_proxy_do_dns: a nuvem laranja da Cloudflare responde pelo domínio e o Caddy nunca tira o
# certificado; o operador fica esperando um SSL que não vem. O IP dela é o sintoma visível.
confere_proxy_do_dns() {
  local sub ips
  sub=$(env_get SUBDOMINIO_BOT)
  [ -n "$sub" ] || return 0
  ips=$(dig +short "$sub" A 2>/dev/null || true)
  case "$ips" in
    104.16.* | 104.17.* | 104.18.* | 104.19.* | 104.20.* | 104.21.* | 172.6[4-9].* | 172.7[0-1].* | 188.114.* | 190.93.*)
      aviso "O DNS de $sub aponta para a Cloudflare. Desligue a nuvem laranja (modo DNS only), senão o certificado nunca sai."
      ;;
  esac
  return 0
}

tela_instalacao() {
  secao "Instalação"
  PASSO_ATUAL=0
  PASSO_TOTAL=12
  local sub
  sub=$(env_get SUBDOMINIO_BOT)

  confere_maquina
  confere_proxy_do_dns
  passo swap "Memória de reserva (swap)" "Veja o log." garante_swap
  passo firewall "Firewall (SSH, 80 e 443)" "Confira com: ufw status" firewall
  passo agente_codigo "$(ia_nome)" "Veja o log." instala_agente_codigo
  passo segredos "Senhas e chaves" "Veja o log." --sem-repetir gera_segredos
  passo imagens "Plataforma $(destaque "v$VERSAO")" \
    "Confira a internet da VPS e o espaço em disco: df -h" baixa_imagens
  passo banco "Banco e Redis" "Veja: source deploy/compose.sh && dc logs postgres" sobe_banco
  passo migracoes "Tabelas do banco" "Veja o log." migra
  passo servicos "API, worker e HTTPS" "Veja o log." sobe_servicos
  passo api_local "API respondendo" "Veja: source deploy/compose.sh && dc logs api" \
    --sem-repetir espera_url http://127.0.0.1:8000/health 24
  passo api_https "Certificado SSL em $sub" \
    "Confira se as portas 80 e 443 estão livres e se o domínio aponta para a VPS." \
    --sem-repetir espera_url "https://$sub/health" 36
  # Depois de a API responder: `sobe_waha` avisa a plataforma da manutenção antes de mexer no
  # contêiner. A WAHA entra na instalação porque o painel não sabe subir contêiner nenhum.
  passo whatsapp "WhatsApp na VPS (WAHA)" \
    "Veja: source deploy/compose.sh && dc logs waha" instala_waha
  # Depois de a plataforma estar no ar: backup de instalação que não subiu não serve para nada.
  passo backup "Backup diário" "Veja: systemctl status asimov-backup.timer" instala_timer_backup
  # O `.env` guarda a chave que decifra as credenciais dos canais: ninguém além do dono o lê.
  chmod 600 "$RAIZ_PROJETO/.env" 2>/dev/null || true
}
