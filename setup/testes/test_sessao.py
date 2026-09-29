"""PTY real: bootstrap por pipe, queda do terminal e reconexão ao mesmo processo tmux."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
if not shutil.which('tmux'):
    raise SystemExit('tmux é necessário para este teste')

with tempfile.TemporaryDirectory(prefix='asimov-sessao-') as nome:
    pasta = Path(nome)
    estado = pasta / 'estado'
    estado.mkdir()
    (estado / 'estado').write_text('instalacao_concluida=teste\n')
    projeto = pasta / 'projeto'
    (projeto / 'setup').mkdir(parents=True)
    (projeto / 'setup/instalar.sh').write_text('''#!/usr/bin/env bash
set -eu
echo "$$" >>"$TEST_DIR/pids"
[ "$ASIMOV_PACOTE" = pacote-teste ]
[ "$ASIMOV_SHA256" = checksum-teste ]
while [ ! -f "$TEST_DIR/liberar" ]; do sleep 0.1; done
''')
    binarios = pasta / 'bin'
    binarios.mkdir()
    curl = binarios / 'curl'
    curl.write_text('''#!/usr/bin/env bash
set -eu
while [ "$1" != -o ]; do shift; done
cp "$TEST_INSTALL" "$2"
''')
    curl.chmod(0o700)
    env = dict(os.environ, ASIMOV_ESTADO_DIR=str(estado), ASIMOV_DIR=str(projeto),
               ASIMOV_PACOTE='pacote-teste', ASIMOV_SHA256='checksum-teste',
               TEST_DIR=nome, TEST_INSTALL=str(ROOT/'install.sh'), TERM='xterm',
               TMUX_TMPDIR=nome, PATH=f'{binarios}:{os.environ["PATH"]}')
    for chave in ('TMUX', 'ASIMOV_SESSAO', 'ASIMOV_TTY', 'ASIMOV_LOCK', 'ASIMOV_ATUALIZAR'):
        env.pop(chave, None)
    # Servidor tmux anterior deve receber as opções da invocação atual explicitamente.
    subprocess.run(['tmux', 'new-session', '-d', '-s', 'anterior', 'sleep 60'], env=env, check=True)
    def abrir():
        mestre, escravo = pty.openpty()
        proc = subprocess.Popen(['bash', '-c', 'bash <(cat "$TEST_INSTALL")'], env=env,
                                stdin=escravo, stdout=escravo, stderr=escravo, start_new_session=True)
        os.close(escravo)
        return proc, mestre
    def esperar(condicao, fd):
        fim = time.monotonic()+15
        while time.monotonic() < fim:
            if condicao(): return
            if select.select([fd], [], [], 0.1)[0]:
                try: os.read(fd, 65536)
                except OSError: break
        raise AssertionError('sessão não chegou ao estado esperado')
    try:
        primeiro, fd = abrir()
        esperar(lambda: (pasta/'pids').exists(), fd)
        pid = (pasta/'pids').read_text()
        os.close(fd)
        primeiro.wait(timeout=5)
        segundo, fd = abrir()
        time.sleep(0.5)
        assert (pasta/'pids').read_text() == pid, 'instalador duplicado'
        assert segundo.poll() is None, 'reconexão falhou'
        (pasta/'liberar').touch()
        esperar(lambda: segundo.poll() is not None, fd)
        os.close(fd)
        assert (pasta/'pids').read_text() == pid
        print('ok: pipe, queda de PTY, reconexão e opções preservadas no tmux')
    finally:
        subprocess.run(['tmux', 'kill-server'], env=env, check=False, capture_output=True)
