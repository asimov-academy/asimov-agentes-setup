<div align="center">

<img src="assets/asimov-academy.png" alt="Asimov Academy" width="120" />

# Asimov Agentes

**Agentes de IA de atendimento humanizado na sua própria VPS.**
Um comando instala tudo. Você cria, testa e coloca agentes no WhatsApp ou no Chatwoot sem montar uma pilha de ferramentas.

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](#antes-de-começar)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](#como-funciona)
[![WhatsApp](https://img.shields.io/badge/WhatsApp-oficial%20e%20WAHA-25D366?logo=whatsapp&logoColor=white)](#canais)
[![Chatwoot](https://img.shields.io/badge/Chatwoot-integrado-1F93FF?logo=chatwoot&logoColor=white)](#canais)
[![IA](https://img.shields.io/badge/IA-OpenAI%20%7C%20Anthropic%20%7C%20Gemini%20%7C%20Groq-111111)](#modelos-de-ia)
[![Copiloto](https://img.shields.io/badge/copiloto-Claude%20Code%20%7C%20Codex-D97757?logo=anthropic&logoColor=white)](#copiloto)
[![arm64](https://img.shields.io/badge/arquitetura-amd64%20%7C%20arm64-6f42c1)](#antes-de-começar)

[O que você ganha](#o-que-você-ganha) ·
[Antes de começar](#antes-de-começar) ·
[Instalação](#instalação) ·
[Comandos](#comandos) ·
[Painel](#painel) ·
[Canais](#canais) ·
[Atualizar](#atualizar) ·
[Suporte](#suporte)

</div>

---

## Por que existe

Hoje, para ter um agente de IA atendendo no WhatsApp, a maioria instala várias ferramentas na VPS e liga uma na outra. O Asimov Agentes é uma plataforma só: o agente, o atendimento, as conversas, os contatos e o painel já vêm juntos, instalados por um comando.

## O que você ganha

| | |
|---|---|
| 🗣️ **Atendimento com cara de gente** | Espera o contato terminar de mandar as mensagens, mostra "digitando" e responde em mensagens curtas. |
| 🎧 **Entende áudio, imagem e PDF** | Transcreve áudio, lê foto de documento e PDF, e não processa de novo o mesmo arquivo reenviado. |
| 🙋 **Passa para uma pessoa** | Quando o contato pede, o agente transfere a conversa para o atendente certo, com um resumo do que já foi falado. |
| 🧠 **Modelo por função** | Resposta, reserva, visão e transcrição, cada uma com seu provedor. Se o modelo principal cair, a reserva responde. |
| 🏢 **Uma empresa ou várias** | Use só na sua empresa ou revenda agentes para clientes, com os dados de cada um isolados. |
| 🖥️ **Painel no navegador** | Visão geral, agentes, canais, conversas, contatos e funil de oportunidades. |
| 🤖 **Copiloto** | Você pede em português e ele cria agente, reescreve o prompt e liga ferramenta. Nada muda sem o seu Confirmar. |
| 🧪 **Teste antes de publicar** | Converse com qualquer agente no terminal, vendo cada etapa, tokens e custo, sem nada ir para o cliente. |

## Antes de começar

- VPS com **Ubuntu 24.04**, acesso root por SSH, pelo menos **2 GB de RAM** e **20 GB livres**; **4 GB** se for usar o WhatsApp pela WAHA junto com o copiloto (amd64 ou arm64)
- Um **domínio** onde você consiga criar registros DNS
- Chave de API de pelo menos um provedor: **OpenAI, Anthropic, Gemini ou Groq**
- Conforme o canal escolhido:
  - **Chatwoot:** acesso de administrador
  - **WhatsApp oficial:** app e número preparados na Meta ([passo a passo](docs/whatsapp-oficial.md))
  - **WhatsApp pela WAHA:** um número só para o agente
- Para o copiloto: assinatura **Claude Pro ou Max**, ou **ChatGPT Plus ou Pro**

## Instalação

Na VPS, como root:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/asimov-academy/asimov-agentes-setup/main/install.sh)
```

O instalador pergunta, nesta ordem:

1. Se os agentes são só da sua empresa ou para empresas clientes
2. Domínio e e-mail para o certificado SSL
3. Onde está sua VPS: **outro provedor** (Hostinger, HostGator...) ou **Oracle Cloud**
4. Claude Code ou Codex para o copiloto
5. O registro DNS `bot.<seu-domínio>` (ele mostra o IP e espera propagar)
6. Se quer entrar na sua conta do assistente agora, ou depois com `asimov ia`
7. Se quer o painel em `app.<seu-domínio>`
8. O canal do primeiro agente e a IA que responde por ele

> [!TIP]
> Se algo falhar, ele mostra o motivo. Rode o mesmo comando de novo e ele continua de onde parou.

> [!NOTE]
> Na **Oracle Cloud**, libere as portas 80 e 443 na Security List da sua rede antes de instalar. O instalador preserva o firewall da máquina.

## Comandos

Depois de instalar, tudo passa pelo comando `asimov`:

| Comando | O que faz |
|---|---|
| `asimov` | Menu: criar, listar, editar e remover agentes, ver consumo e falhas |
| `asimov novo-agente` | Cria outro agente no Chatwoot, no WhatsApp ou nativo |
| `asimov conversar` | Conversa de teste com qualquer agente no terminal; nada vai para o canal |
| `asimov agentes` | Lista agentes, empresas e webhooks |
| `asimov editar` | Muda nome, tempo de espera, mensagens por resposta, modelos ou handoff |
| `asimov remover` | Remove um agente e desconecta o canal dele |
| `asimov consumo` | Turnos, tokens, custo estimado e falhas dos últimos 7 e 30 dias |
| `asimov handoff` | Troca quem recebe a conversa passada pelo agente |
| `asimov painel` | Liga ou desliga o painel e gera o código do primeiro acesso |
| `asimov ia` | Entra na sua conta do Claude Code ou do Codex |
| `asimov token` | Troca o token da trilha, que abre a imagem do painel |
| `asimov diagnostico` | Mostra a versão instalada e se cada endereço está respondendo |
| `asimov atualizar` | Baixa a versão nova e reinicia |
| `asimov desinstalar` | Remove da VPS tudo o que o Asimov instalou, com backup opcional antes |

**Personalidade do agente:** edite `~/asimov-agentes/prompts/<empresa>/<agente>/persona.md`. A mudança vale na próxima mensagem.

## Painel

Tudo o que está acima funciona pelo terminal, sem token nenhum. O painel no navegador faz parte da trilha de agentes da Asimov Academy: a imagem dele é privada, e o token vem no material do curso.

Ligue com `asimov painel`. Ele pede o token da trilha, o registro DNS de `app.<seu-domínio>` e mostra um código de uso único para você criar a senha no primeiro acesso. O token fica guardado na credencial do Docker, nunca no `.env`; `asimov token` troca quando ele é rotacionado.

| Tela | O que faz |
|---|---|
| **Visão geral** | Se está tudo de pé, turnos, custo e quanto o agente resolveu sozinho |
| **Agentes** | Criação guiada em cinco passos, com prévia do jeito que ele fala e conversa de teste |
| **Canais** | Status de cada canal, QR code do WhatsApp e reinício da sessão |
| **Chat** | Conversas, histórico, custo de cada turno e devolução da conversa ao agente |
| **Contatos** | Quem já falou com algum agente, por nome ou telefone |
| **Oportunidades** | Funil em kanban por empresa, com etapas e etiquetas suas |
| **Copiloto** | O botão no canto de qualquer tela |

### Copiloto

Com a sua conta do Claude Code ou do Codex vinculada, o painel ganha um assistente que lê a plataforma, propõe a mudança e espera você confirmar. Ele usa a assinatura que você já paga, sem chave de API e sem custo por token.

## Canais

| Canal | Quando usar |
|---|---|
| **Chatwoot** | Você já atende pelo Chatwoot e quer o agente dentro da caixa de entrada |
| **WhatsApp oficial** | Número homologado pela Meta, para operação profissional |
| **WhatsApp pela WAHA** | Parear um número lendo o QR code. É uma API **não oficial**: use um chip só para o agente, porque o número pode ser bloqueado |
| **Nativo** | Testar o agente no terminal antes de ligar num canal |

**Passar para uma pessoa:** no Chatwoot, o agente fica calado enquanto a conversa está Aberta e volta quando você marca como Pendente. No WhatsApp direto, quem recebe o aviso devolve a conversa reagindo com 👍 ou mandando `/retomar <código>`. Se alguém da equipe responder pelo celular, o agente para na hora.

## Modelos de IA

Cada função usa o provedor que você escolher:

| Função | Para que serve |
|---|---|
| Resposta | O modelo que conversa com o contato |
| Reserva | Responde se o principal cair |
| Visão | Lê imagens e documentos |
| Transcrição | Converte áudio em texto |

As chaves de API são testadas na hora e guardadas cifradas no banco.

## Atualizar

```bash
asimov atualizar
```

Ele baixa a versão nova e reinicia. Se a versão nova não subir saudável, volta sozinho para a que estava no ar. O `.env`, os prompts dos agentes e as conversas não são tocados.

## Desinstalar

```bash
asimov desinstalar
```

Remove da VPS tudo o que o Asimov instalou: contêineres, volumes e imagens, agentes, conversas, prompts, conexões dos canais, o pareamento do WhatsApp, os timers do backup e da WAHA, a integração com o Caddy da VPS (só a linha e o arquivo do Asimov), o login no registro das imagens, o comando `asimov`, a pasta do projeto e o estado em `~/.asimov`. Antes, ele oferece um backup (banco, `.env`, prompts e conhecimento) em `/var/lib/asimov/backups`, que fica na VPS. Para confirmar, é preciso digitar `desinstalar`.

Ficam na VPS o Docker, os pacotes do sistema e a sua conta do Claude Code ou do Codex. Depois, no celular do WhatsApp, desconecte a VPS em Aparelhos conectados e, no Chatwoot, apague o bot do agente. Para instalar de novo, use o comando da [Instalação](#instalação).

## Como funciona

```
WhatsApp ─► Chatwoot ou WhatsApp direto ─► bot.<domínio> ─► fila ─► agente ─► modelo de IA
                                                                        │
contato ◄──────────────── resposta em mensagens curtas ◄────────────────┘
```

Tudo roda em contêineres Docker na sua VPS, com HTTPS automático. Nada é carregado de CDN.

## Suporte

Este instalador faz parte da trilha **Agentes de Atendimento Humanizado** da [Asimov Academy](https://asimov.academy). Dúvidas e suporte ficam na comunidade da trilha.

---

<div align="center">

Feito pela [Asimov Academy](https://asimov.academy)

</div>


## Retomar e compartilhar uma VPS

A partir da v0.33.0, o comando público abre uma sessão tmux chamada
`asimov-instalacao`. Se a conexão cair, execute o mesmo comando ou
`tmux attach -t asimov-instalacao`. Uma trava impede instalações concorrentes.
Uma instalação incompleta recebe o instalador atualizado ao repetir o comando.

Ao retomar, o setup inventaria os contêineres do próprio projeto e confere os passos
salvos. Serviços, migrações e saúde são reconciliados; DNS é conferido novamente.
Volumes existentes sem as chaves originais interrompem a instalação: restaure o
`.env` do backup, nunca gere outra chave para o mesmo banco.

Desde a v0.33.1, portas públicas ocupadas selecionam automaticamente o proxy existente. O gateway Caddy do
Asimov passa a escutar somente em portas locais livres, preservando o bloqueio de
`/admin`. A API administrativa também usa porta local livre. O Caddy padrão do
host recebe um import automaticamente, com validação, backup e rollback.
Outros proxies recebem instruções e um arquivo de referência em
`deploy/proxy-externo.caddy`; o setup só confirma sucesso depois de HTTPS responder.
Proxy dentro de outro contêiner precisa alcançar o host por uma rede configurada
pelo administrador, nunca por `localhost` do próprio contêiner.

O firewall é sempre preservado, sem perguntas de configuração, e a atualização geral do sistema deixa de fazer
parte da instalação. Pacotes necessários continuam sendo instalados. Em um Caddy
com configuração modificada depois de uma interrupção, a recuperação para e aponta
o backup para conciliação, sem apagar alterações posteriores.

Testes adicionais: `bash setup/testes/simula_retomada.sh`,
`python3 setup/testes/test_sessao.py` (tmux) e `bash setup/testes/caddy_real.sh`
(Docker em Linux). Os testes usam configurações e serviços fictícios isolados.

## Contexto para evoluir os agentes

A instalação cria `AGENTS.md` e `CLAUDE.md` na pasta do projeto, para o operador
manter a VPS com o assistente, e uma área de trabalho em `agentes/` para evoluir os
agentes:

```bash
cd ~/asimov-agentes/agentes && claude
```

Troque `claude` por `codex`. Na primeira vez, o Codex pergunta se confia na pasta:
confirme, senão cada comando `asimov` pede aprovação. Em `agentes/` o assistente grava
só ali dentro, longe de `setup/`, `deploy/` e do `.env`, e os comandos de leitura e de
preparo (`asimov agente`, `asimov ferramenta`) rodam sem aprovação. Os que mudam o
atendimento (aplicar ou restaurar prompt, conversa de teste, ativar, ligar, restaurar,
segredo e executar ferramenta) pedem a sua aprovação a cada vez. Aberto na raiz, o
assistente pede aprovação para todos: é de propósito, porque ali ele poderia editar o
código que esses comandos executam como root.

`asimov atualizar` recupera arquivos ausentes e reescreve só os trechos da plataforma,
sem trocar o que você escreveu fora deles.
