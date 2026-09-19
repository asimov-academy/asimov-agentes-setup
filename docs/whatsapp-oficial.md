# WhatsApp oficial: como preparar a Meta

Passo a passo para deixar um número pronto na **Cloud API oficial da Meta** e criar o agente com
`asimov novo-agente`. Conferido no painel da Meta em setembro de 2026.

Quer testar rápido, sem número próprio e sem verificar empresa? Vá para
[Caminho rápido: número de teste](#caminho-rápido-número-de-teste).

> **O painel mudou de nome em 2026.** Onde antes havia **Produtos**, agora há **Casos de uso**, e a
> configuração do WhatsApp virou um fluxo guiado em **Casos de uso > Personalizar**, com três
> etapas. A documentação da Meta ainda fala em "Produtos" e "Configuração da API" em várias
> páginas: é a mesma coisa com nome antigo. Por isso este documento dá o **link direto** sempre que
> existe um, que é o que não muda de lugar.

O setup pede **três dados**, e descobre o resto sozinho:

| Dado | Onde aparece | Passo |
|---|---|---|
| ID do app | Configurações do app > Básico | [8](#8-id-do-app-e-chave-secreta) |
| Chave secreta do app | Configurações do app > Básico | [8](#8-id-do-app-e-chave-secreta) |
| Token de acesso permanente | Configurações do negócio > Usuários do sistema | [7](#7-usuário-do-sistema-e-token-permanente) |

Com esses três, o setup pergunta à própria Meta quais contas de WhatsApp Business o token alcança e
lista para você escolher, junto com os números e os templates da conta. Se precisar do ID da conta
à mão, veja [onde fica o ID da conta](#onde-fica-o-id-da-conta-de-whatsapp-business).

Para o app sair do modo de desenvolvimento, a Meta pede política de privacidade e ícone: os dois
estão prontos no [passo 10](#10-publicar-o-app).

## Duas coisas que o painel pede e você pode pular

**O webhook.** A primeira coisa que o fluxo guiado pede é configurar o webhook, com URL de retorno
e token de verificação. **Pule.** Quem faz isso é a plataforma, quando o agente é criado: ela liga
os webhooks do app, inscreve a conta e aponta o webhook daquele número para o endereço do agente.
Configurar à mão ali só atrapalha, porque o endereço do agente ainda não existe.

**O ID da conta de WhatsApp Business.** O painel não diz com clareza onde ele fica, e você não
precisa dele: o setup descobre. Se quiser conferir, está em
[onde fica o ID da conta](#onde-fica-o-id-da-conta-de-whatsapp-business).

## Duas mudanças recentes que valem ler antes

**1. A partir de 1º de outubro de 2026 a resposta dentro da janela de 24 horas passa a ser cobrada.** Era o que
mais confundia: até setembro de 2026, responder um contato que escreveu primeiro não custava nada.
Agora cada mensagem de serviço (a resposta em texto livre, que é o que o agente manda) é cobrada
pela tarifa de utilidade do país, depois de **1.000 mensagens grátis por número por mês**, que não
acumulam para o mês seguinte. Mensagem recebida do contato continua de graça, e a janela de 72
horas de anúncios Click to WhatsApp também.

**Consequência prática: sem forma de pagamento na conta, a Meta não entrega as respostas do
agente.** Não é só limite de teste: mensagem de serviço sem meio de pagamento deixou de ser
entregue. Faça o [passo 5](#5-forma-de-pagamento) antes de testar.

Fontes: [preços na WhatsApp Business Platform](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing)
e [mudanças em mensagens de serviço e utilidade](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing/non-template-messages).

**2. Desde 15 de janeiro de 2026 a Meta proíbe assistente de IA de propósito geral no WhatsApp.**
O alvo são os assistentes que respondem sobre qualquer assunto usando o WhatsApp como canal de
distribuição (ChatGPT, Perplexity e parecidos). Agente de atendimento de uma empresa, que responde
sobre os produtos, os pedidos e os horários dela, continua permitido: é exatamente para isso que a
plataforma existe. Vale a pena manter o prompt do agente dentro do assunto da empresa e não
transformá-lo em assistente geral.

## O que esperar de prazo

- **Verificação do negócio**: de algumas horas a alguns dias, e pode pedir documento da empresa.
- **Aprovação do nome de exibição**: em geral 1 a 2 dias.
- **Aprovação do template**: costuma sair em minutos.

## 1. Portfólio de negócios (Business Manager)

1. Abra as [configurações do negócio](https://business.facebook.com/settings) e crie um portfólio
   de negócios, se ainda não tiver um. Use o nome real da empresa, igual ao do documento.
2. Em **Informações do negócio**, preencha nome legal, endereço, telefone e site. A verificação
   compara o que está aqui com o documento.

Se você atende várias empresas (modo revenda), o normal é **um portfólio por empresa cliente**,
cada um com o próprio app, número e token. Um agente da plataforma corresponde a um número.

## 2. Criar o app

1. Abra [Meus Apps](https://developers.facebook.com/apps) e clique em **Criar app**.
2. Em caso de uso, escolha **Conectar-se com clientes pelo WhatsApp**.
3. Ligue o app ao portfólio de negócios do passo 1.
4. O app abre em **Casos de uso > Personalizar**, com o caso de uso **Conectar no WhatsApp**
   selecionado. Em **Escolha o tipo de integração**, mantenha **Integrar com API**.

   "Torne-se um parceiro" é para quem vai ser Provedor de Tecnologia e revender acesso a outras
   empresas. Não é o seu caso aqui, mesmo no modo revenda: cada empresa cliente tem o próprio app.

5. Do lado esquerdo aparece **Configuração básica**, com três etapas: **Etapa 1. Experimente**,
   **Etapa 2. Configuração da produção** e **Etapa 3. Verificação da empresa**. Os próximos passos
   seguem essa ordem.

Referência: [primeiros passos da Cloud API](https://developers.facebook.com/documentation/business-messaging/whatsapp/get-started).

## 3. Etapa 1: Experimente

A Meta dá um número de teste e um token de 24 horas para você mandar a primeira mensagem e ver a
API funcionando. Leva uns 5 minutos e não compromete nada.

Se o fluxo pedir para configurar o webhook nesta etapa, pule: a plataforma faz isso sozinha.

Se quiser, pare aqui e vá para o [caminho rápido](#caminho-rápido-número-de-teste): dá para criar
um agente de verdade com o número de teste.

## 4. Conta de WhatsApp Business e número

Na **Etapa 2. Configuração da produção**:

1. Escolha ou crie a **conta de WhatsApp Business** (WABA), se ainda não tiver.
2. Clique em **Adicionar número de telefone**. Use um número que:
   - possa receber SMS ou ligação para confirmar;
   - **não** esteja em uso no aplicativo do WhatsApp nem no WhatsApp Business. Se estiver, apague a
     conta naquele número antes, senão a Meta recusa.
3. Confirme o código que chegar.

O número da Cloud API não roda no celular. Ninguém responde pelo aparelho: quem atende usa o
Chatwoot, ou recebe o aviso de handoff no próprio WhatsApp (passo 11).

Os números da conta também ficam em
[WhatsApp Manager > Números de telefone](https://business.facebook.com/wa/manage/phone-numbers/),
que é onde você confere o **ID do número** se precisar.

## 5. Forma de pagamento

1. Abra as [formas de pagamento](https://business.facebook.com/billing_hub/payment_settings), ou
   vá pelo [WhatsApp Manager](https://business.facebook.com/wa/manage/) em **Configurações da conta
   > Cobrança e pagamentos**.
2. Adicione um cartão à conta de WhatsApp Business.

**Não deixe para depois.** A partir de outubro de 2026, conta sem forma de pagamento deixa de ter mensagem de
serviço entregue, e mensagem de serviço é justamente a resposta do agente ao contato.

## 6. Nome de exibição

Em [Números de telefone](https://business.facebook.com/wa/manage/phone-numbers/), abra o número e
defina o **nome de exibição**, que é o que o contato vê. As regras da Meta:

- precisa representar a empresa de verdade, com pelo menos 3 caracteres;
- sem URL, sem telefone, sem emoji, sem pontuação estranha;
- sem tudo em maiúsculas, a não ser que seja sigla;
- não pode conter WhatsApp, WA, Insta, FB, Meta nem Facebook.

Referência: [sobre o nome de exibição](https://www.facebook.com/business/help/338047025165344).

Ative também a **verificação em duas etapas** do número (PIN de 6 dígitos), que a Meta exige.

## 7. Usuário do sistema e token permanente

O token que aparece na Etapa 1 vale 24 horas. O agente precisa de um permanente.

1. Abra [Configurações do negócio > Usuários do sistema](https://business.facebook.com/settings/system-users).
2. Clique em **Adicionar**, dê um nome (por exemplo `agente-atendimento`) e escolha a função
   **Administrador**.
3. Selecione o usuário criado e clique em **Adicionar ativos**:
   - o **app** do passo 2, com **Gerenciar app**;
   - a **conta de WhatsApp Business** do passo 4, com **Gerenciar contas do WhatsApp Business**.
4. Clique em **Gerar token**, escolha o app e marque **as duas permissões**:
   - `whatsapp_business_messaging` (mandar e receber mensagem)
   - `whatsapp_business_management` (número, templates e webhook)
5. Em validade, escolha **Nunca expira**.
6. Copie o token. **Ele aparece uma vez só.** Se perder, gere outro.

**`business_management` não aparece na lista? Não precisa dela.** App criado pelo caso de uso
"Conectar-se com clientes pelo WhatsApp" oferece só as permissões daquele caso de uso, e as duas
acima são todas as que o agente usa. Também não precisa de `whatsapp_business_manage_events` nem de
`manage_app_solution`.

A `business_management` serve a uma coisa só aqui: deixar o setup **descobrir** a conta de WhatsApp
Business pelos negócios do token. Sem ela, o setup ainda descobre pelos escopos do próprio token e,
se não achar, pergunta o ID à mão, que está em
[onde fica o ID da conta](#onde-fica-o-id-da-conta-de-whatsapp-business). Nada deixa de funcionar.

Referência: [tokens de acesso](https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/).

O token vai para a plataforma e é guardado criptografado no banco. Ele nunca aparece em log, na
resposta da API nem no `.env`.

## 8. ID do app e chave secreta

1. No painel do app, abra **Configurações do app > Básico**
   (`https://developers.facebook.com/apps/<ID_DO_APP>/settings/basic/`).
2. Copie o **ID do app**, que fica no topo.
3. Em **Chave secreta do app**, clique em **Mostrar** e copie.

A chave secreta é o que prova que o webhook veio da Meta: cada corpo chega assinado com ela
(`X-Hub-Signature-256`) e a plataforma recusa o que não confere.

## 9. Etapa 3: Verificação da empresa

1. Na **Etapa 3. Verificação da empresa**, ou direto no
   [Centro de Segurança](https://business.facebook.com/settings/security), clique em **Iniciar
   verificação**.
2. Envie documento da empresa (contrato social, CNPJ ou equivalente) e comprovação de endereço ou
   telefone.

Sem verificar, o número fica com limites baixos de mensagens e o nome de exibição não é aprovado.
Dá para desenvolver e testar antes.

## 10. Publicar o app

Enquanto o app está em **modo de desenvolvimento**, ele só fala com os números de teste. Para
atender gente de verdade, o app precisa ficar **Ativo**, e a Meta pede duas coisas antes:

**URL da política de privacidade.** Esta instalação serve uma, no seu domínio, em três níveis.
Na Meta existe **um app por número**, e cada app quer a própria URL, então o nível mais útil é o do
agente:

```
https://bot.<seu-dominio>/privacidade/<empresa>/<agente>   ← use esta no app do número
https://bot.<seu-dominio>/privacidade/<empresa>            ← a empresa, sem citar agente
https://bot.<seu-dominio>/privacidade                      ← a instalação
```

A URL do agente aparece pronta no fim da criação e em **Editar agente > WhatsApp**, linha
Privacidade. Não precisa montar à mão. Os slugs são o nome em minúsculas com hífens: `Loja Exemplo`
com a agente `Ana` dá `/privacidade/loja-exemplo/ana`.

O texto é um modelo em `modelos/privacidade.html`, no projeto: ele cobre o que um agente de
atendimento trata (mensagens, nome e telefone, arquivos, uso de provedores de IA, prazo e
contato), e **você deve revisar** para bater com o seu caso. É a sua política, não a nossa. Depois
de editar, não precisa reiniciar nada: a página é lida a cada visita.

**Ícone quadrado do app.** A instalação também serve, para você abrir no navegador e salvar:

```
https://bot.<seu-dominio>/icone-app.png
```

É um PNG 1024x1024. Para trocar por outro, sobrescreva `modelos/icone-app.png` na pasta da
instalação.

Com os dois preenchidos em **Configurações do app > Básico**, e a empresa verificada
([passo 9](#9-etapa-3-verificação-da-empresa)), o botão de publicar libera.

## 11. Template do aviso de handoff

Quando o agente passa a conversa para uma pessoa, ele manda um aviso com o resumo para o número que
você escolher. Esse número normalmente nunca falou com o agente, e a Meta só entrega mensagem para
quem não escreveu nas últimas 24 horas se ela for um **template aprovado**.

1. Abra [WhatsApp Manager > Modelos de mensagem](https://business.facebook.com/wa/manage/message-templates/)
   e clique em **Criar modelo**.
2. Categoria **Utilidade**, idioma **Português (BR)**, nome `aviso_handoff`.
3. No corpo, use exatamente três variáveis:

```
O agente passou uma conversa para voce.

Contato: {{1}}
Resumo: {{2}}
Codigo: {{3}}

Responda /retomar neste chat quando terminar.
```

4. Envie para aprovação. O setup lista só os templates aprovados com três variáveis, então se o seu
   tiver outra forma ele não vai aparecer na lista.

Sem template o handoff continua funcionando, mas o aviso só chega se quem recebe tiver escrito ao
agente nas últimas 24 horas. Referência:
[modelos de mensagem](https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates).

## 12. Criar o agente

Na VPS:

```bash
asimov novo-agente
```

Escolha **WhatsApp oficial** e responda: conta de WhatsApp Business, ID do app, token de acesso,
chave secreta, número (o setup lista os da conta), nome do agente, empresa, ferramentas, horas até
o agente voltar sozinho, quem o agente atende e, por fim, o número que recebe o handoff e o
template do passo 11.

No fim, mande uma mensagem para o número e o agente responde.

## Onde fica o ID da conta de WhatsApp Business

O setup descobre sozinho, mas este é o dado que mais gera dúvida, então fica registrado. Ele tem 15
ou 16 dígitos e **não** é o ID do app nem o ID do número.

Dois caminhos:

- [Configurações > Contas > Contas do WhatsApp](https://business.facebook.com/settings/whatsapp-business-accounts),
  no Gerenciador de Negócios: o ID aparece embaixo do nome da conta. Clicando na conta, ele também
  fica no alto à direita.
- [WhatsApp Manager](https://business.facebook.com/wa/manage/): na página de contas, embaixo do
  nome da conta.

Se o setup disser que o token não enxerga nenhuma conta, o problema não é achar o ID: é o token.

**A causa mais comum: o token foi gerado antes de a conta ser atribuída ao usuário do sistema.** O
token guarda os ativos de quando nasceu, então atribuir a conta depois não vale para ele. Volte em
Usuários do sistema, confira que a conta está nos ativos e **gere o token de novo**. O antigo pode
ser revogado.

Fora disso, confira no [passo 7](#7-usuário-do-sistema-e-token-permanente) que o token saiu com
`whatsapp_business_management` e `whatsapp_business_messaging`.

Informar o ID à mão resolve a tela, mas não resolve o token: se ele não alcança a conta, a Meta vai
recusar as chamadas seguintes com erro de permissão.

## Conferir se funcionou

- `asimov agentes` mostra o agente, o canal e o webhook dele.
- `asimov consumo` mostra os turnos e as falhas dos últimos dias.
- Nada acontece quando você manda mensagem? Veja o log da API:

```bash
source deploy/compose.sh && dc logs -n 100 api
```

Linha `webhook_verificado` quer dizer que a Meta conferiu o endereço. Linha `webhook_aceito` quer
dizer que a mensagem chegou.

## Erros comuns

| O que acontece | Causa provável | O que fazer |
|---|---|---|
| A Meta recusa o token de acesso | token de 24 h da Etapa 1, ou sem as permissões | refaça o passo 7, com as duas permissões e "Nunca expira" |
| `business_management` não aparece para marcar | app do caso de uso do WhatsApp só oferece as permissões dele | não precisa: marque as duas `whatsapp_*` |
| `(#100) The App_id in the input_token did not match the Viewing App` | o ID do app informado não é o do app que gerou o token | use o ID e a chave secreta do **mesmo** app que você escolheu em "Gerar token" |
| A Meta pede política de privacidade para publicar o app | é obrigatório para sair do modo de desenvolvimento | [passo 10](#10-publicar-o-app): a instalação serve a página |
| A URL da política responde 404 | o Caddy está com a configuração antiga em memória | `asimov atualizar`, ou na hora: `source deploy/compose.sh && dc restart caddy` |
| A Meta recusa apontar o webhook | o usuário do sistema não tem o app ou a conta como ativo | passo 7, item 3 |
| O agente recebe mas nada chega ao contato | conta sem forma de pagamento | passo 5 |
| O agente não recebe nada | alguém mexeu na configuração do webhook pelo painel da Meta | `asimov editar`, opção **WhatsApp**, **Refazer o webhook na Meta** |
| Aviso de handoff não chega | fora da janela de 24 h e sem template aprovado | passo 11; `asimov consumo` mostra a falha `handoff_incompleto` |
| Só alguns números recebem resposta | número de teste com destinatários cadastrados | passo 4, use um número de produção |
| Não consigo adicionar o número | ele está em uso no app do WhatsApp | apague a conta do WhatsApp naquele número e tente de novo |
| Não acho "Produtos" no painel | virou **Casos de uso** em 2026 | Casos de uso > Personalizar |
| Não acho o ID da conta de WhatsApp Business | o painel não mostra isso no fluxo guiado | não precisa: o setup descobre. Se quiser conferir, veja [onde fica](#onde-fica-o-id-da-conta-de-whatsapp-business) |
| O setup diz que o token não enxerga nenhuma conta | o token foi gerado antes de a conta ser atribuída ao usuário do sistema | gere o token de novo, no passo 7 |

## Caminho rápido: número de teste

Para testar a plataforma antes de resolver verificação, pagamento e nome de exibição:

1. Faça os passos 1, 2, 3 (ficando no número de teste da Etapa 1), 7 e 8. Publicar o app e
   verificar a empresa podem esperar.
2. Na Etapa 1, cadastre em **Para** até 5 números que vão conversar com o agente. O número de teste
   só fala com esses.
3. Crie o agente sem template (o setup deixa seguir sem). Para testar o handoff, mande primeiro uma
   mensagem qualquer do número que vai receber o aviso para o número do agente: isso abre a janela
   de 24 horas e o aviso chega em texto.

Quando o número de verdade estiver pronto, crie outro agente com ele.

## WhatsApp oficial ou WAHA

| | Oficial (Cloud API) | WAHA |
|---|---|---|
| Homologação | da Meta | nenhuma, é API não oficial |
| Risco de bloqueio | baixo: o número é homologado, mas a conta pode ser suspensa por violar a política | o número pode ser bloqueado sem aviso |
| Custo | por mensagem, tabela da Meta, com 1.000 respostas grátis por número por mês | só a VPS |
| Preparação | os passos deste documento | ler um QR code no terminal |
| Número | não roda no celular | é o seu celular, alguém pode responder pelo aparelho |
| Aviso de handoff | template aprovado fora da janela de 24 h | mensagem comum |

Para testar ideia e prompt, a WAHA resolve em minutos. Para produção com número da empresa, o
oficial é o caminho.
