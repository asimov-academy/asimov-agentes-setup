"""PTY real: bootstrap por pipe, queda do terminal e reconexão ao mesmo processo tmux."""
import io
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import subprocess
import tarfile
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
                except OSError: time.sleep(0.05)
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


def fim_na_tela(atualizar, codigo):
    """O fim do setup fica na tela do tmux até o Enter: o erro sempre, o sucesso na atualização."""
    with tempfile.TemporaryDirectory(prefix='asimov-tela-') as nome:
        pasta = Path(nome)
        estado = pasta / 'estado'
        estado.mkdir()
        (estado / 'estado').write_text('instalacao_concluida=teste\n')
        instalar = f'#!/usr/bin/env bash\necho fim-do-setup\nexit {codigo}\n'.encode()
        projeto = pasta / 'projeto'
        (projeto / 'setup').mkdir(parents=True)
        (projeto / 'setup/instalar.sh').write_bytes(instalar)
        # A atualização baixa o pacote de novo: o curl de mentira entrega um com o mesmo setup.
        pacote = pasta / 'pacote.tar.gz'
        with tarfile.open(pacote, 'w:gz') as tar:
            info = tarfile.TarInfo('pacote/setup/instalar.sh')
            info.size = len(instalar)
            tar.addfile(info, io.BytesIO(instalar))
        binarios = pasta / 'bin'
        binarios.mkdir()
        curl = binarios / 'curl'
        curl.write_text('#!/usr/bin/env bash\nwhile [ "$1" != -o ]; do shift; done\ncp "$TEST_PACOTE" "$2"\n')
        curl.chmod(0o700)
        env = dict(os.environ, TERM='xterm', TMUX_TMPDIR=nome, TEST_PACOTE=str(pacote),
                   PATH=f'{binarios}:{os.environ["PATH"]}')
        for chave in ('TMUX', 'ASIMOV_SESSAO', 'ASIMOV_TTY', 'ASIMOV_LOCK', 'ASIMOV_ATUALIZAR'):
            env.pop(chave, None)
        comando = shlex.join(['env', 'ASIMOV_SESSAO=1', f'ASIMOV_ESTADO_DIR={estado}',
                              f'ASIMOV_DIR={projeto}', f'ASIMOV_ATUALIZAR={"1" if atualizar else ""}',
                              'bash', str(ROOT/'install.sh')])
        def tela():
            r = subprocess.run(['tmux', 'capture-pane', '-p', '-t', 'fim'], env=env,
                               capture_output=True, text=True)
            return r.stdout if r.returncode == 0 else None
        try:
            subprocess.run(['tmux', 'new-session', '-d', '-s', 'fim', comando], env=env, check=True)
            limite = time.monotonic()+15
            while 'Enter para fechar' not in (texto := tela() or ''):
                assert tela() is not None, 'a tela fechou antes de alguém ler'
                assert time.monotonic() < limite, f'a tela não chegou ao fim: {tela()!r}'
                time.sleep(0.1)
            assert 'fim-do-setup' in texto
            assert ('A instalação parou' in texto) == (codigo != 0)
            subprocess.run(['tmux', 'send-keys', '-t', 'fim', 'Enter'], env=env, check=True)
            limite = time.monotonic()+5
            while tela() is not None:
                assert time.monotonic() < limite, 'o Enter não fechou a tela'
                time.sleep(0.1)
        finally:
            subprocess.run(['tmux', 'kill-server'], env=env, check=False, capture_output=True)


fim_na_tela(atualizar=False, codigo=3)
fim_na_tela(atualizar=True, codigo=3)
fim_na_tela(atualizar=True, codigo=0)
print('ok: erro e fim da atualização ficam na tela do tmux até o Enter')
