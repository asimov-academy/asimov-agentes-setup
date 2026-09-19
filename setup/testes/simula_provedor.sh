#!/usr/bin/env bash
# Os dois caminhos de "Onde está sua VPS?" e o que cada um faz no firewall, sem VPS:
#   1. Outro provedor pelo número, como na simulação do onboarding: firewall não toca no iptables.
#   2. Oracle Cloud: o ACCEPT de 80 e 443 entra antes do REJECT da imagem, e a regra é salva.
#   3. Outro provedor com Enter, num terminal de verdade (pty): é o padrão, a opção já marcada.
#   bash setup/testes/simula_provedor.sh
set -Eeuo pipefail
RAIZ_PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASH_5=${BASH_5:-$(command -v bash)}

# Roda tela_dados e o firewall com tudo de mentira. As respostas vêm de ASIMOV_TTY (arquivo) ou do
# terminal, quando chamado dentro do pty.
if [ "${1:-}" = --tela ]; then
  DIR=$2
  export HOME=$DIR
  # shellcheck source=setup/lib/base.sh
  source "$RAIZ_PROJETO/setup/lib/base.sh"
  ARQ_ENV=$DIR/.env
  SUDO=""
  estado_iniciar
  clear() { :; }
  ip_publico() { echo 203.0.113.10; }
  ss() { :; }
  ufw() { echo "ufw $*" >>"$DIR/firewall.log"; }
  netfilter-persistent() { echo "netfilter-persistent $*" >>"$DIR/firewall.log"; }
  # INPUT como na imagem Ubuntu da Oracle: o REJECT é a regra 5.
  iptables() {
    echo "iptables $*" >>"$DIR/firewall.log"
    case "$1" in
      -D) return 1 ;;
      -L) printf 'Chain INPUT\nnum target\n1 ACCEPT\n2 ACCEPT\n3 ACCEPT\n4 ACCEPT\n5 REJECT all\n' ;;
    esac
  }
  tela_dados
  firewall
  exit 0
fi

confere() { # confere NOME DIR PROVEDOR_ESPERADO
  local nome=$1 dir=$2 esperado=$3 gravado
  gravado=$(grep -m1 '^PROVEDOR_VPS=' "$dir/.env" | cut -d= -f2 || true)
  [ "$gravado" = "$esperado" ] || { echo "FALHOU: $nome: PROVEDOR_VPS=$gravado"; cat "$dir/saida.log"; exit 1; }
  if [ "$esperado" = oracle ]; then
    grep -q "iptables -I INPUT 5 -p tcp --dport 80 -j ACCEPT" "$dir/firewall.log" &&
      grep -q "iptables -I INPUT 5 -p tcp --dport 443 -j ACCEPT" "$dir/firewall.log" &&
      grep -q "netfilter-persistent save" "$dir/firewall.log" ||
      { echo "FALHOU: $nome: iptables"; cat "$dir/firewall.log"; exit 1; }
  else
    ! grep -q "^iptables" "$dir/firewall.log" || { echo "FALHOU: $nome: mexeu no iptables"; exit 1; }
  fi
  grep -q "ufw allow 443/tcp" "$dir/firewall.log" || { echo "FALHOU: $nome: ufw"; exit 1; }
  echo "ok: $nome"
  rm -rf "$dir"
}

por_numero() { # por_numero NOME NUMERO PROVEDOR_ESPERADO
  local dir
  dir=$(mktemp -d)
  printf 'exemplo.com.br\noperador@exemplo.com.br\n%s\n1\n' "$2" >"$dir/respostas"
  ASIMOV_TTY=$dir/respostas "$BASH_5" "$0" --tela "$dir" >"$dir/saida.log" 2>&1 ||
    { echo "FALHOU: $1"; cat "$dir/saida.log"; exit 1; }
  confere "$1" "$dir" "$3"
}

# Com terminal as escolhas andam com as setas, e Enter confirma a que já vem marcada. Cada tecla só
# vai depois de a pergunta aparecer: a leitura começa descartando o que chegou antes da hora.
com_enter() {
  local dir
  dir=$(mktemp -d)
  python3 - "$BASH_5" "$0" "$dir" >"$dir/saida.log" 2>&1 <<'PY' || { echo "FALHOU: Enter no terminal"; cat "$dir/saida.log"; exit 1; }
import os, pty, select, sys, time

bash, script, pasta = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm"
    os.environ.pop("ASIMOV_TTY", None)
    os.execv(bash, [bash, script, "--tela", pasta])

passos = [(b"Dom\xc3\xadnio", b"exemplo.com.br\r"), (b"E-mail", b"operador@exemplo.com.br\r"),
          (b"Onde est", b"\r"), (b"Assistente do copiloto", b"\r")]
visto, fim = b"", time.time() + 60
while time.time() < fim:
    pronto, _, _ = select.select([fd], [], [], 0.5)
    if pronto:
        try:
            pedaco = os.read(fd, 4096)
        except OSError:
            break
        if not pedaco:
            break
        visto += pedaco
        sys.stdout.write(pedaco.decode(errors="replace"))
    if passos and passos[0][0] in visto:
        time.sleep(0.4)
        os.write(fd, passos[0][1])
        visto = b""
        passos.pop(0)
_, status = os.waitpid(pid, 0)
sys.exit(1 if passos or os.waitstatus_to_exitcode(status) else 0)
PY
  confere "Outro provedor com Enter, no terminal" "$dir" outro
}

por_numero "Outro provedor pelo número" 1 outro
por_numero "Oracle Cloud abre o iptables antes do REJECT" 2 oracle
com_enter
