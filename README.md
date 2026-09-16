# h_stock

Controle de estoque e pedidos para venda a peso, pensado para uso no celular.

Phoenix + [Ash](https://ash-hq.org) + [Inertia.js](https://inertiajs.com) com
React, TypeScript e shadcn/ui. Sem LiveView na aplicação: o Phoenix responde
páginas Inertia e o front é React puro.

| Camada  | Onde fica    | Módulos  |
| ------- | ------------ | -------- |
| Domínio | `lib/core/`  | `Core.*` |
| Web     | `lib/web/`   | `Web.*`  |
| Front   | `assets/js/` | —        |

A OTP app é `:h_stock` (é o nome usado em `config :h_stock, ...`).

## O que o sistema faz

**Três perfis.** `admin` controla tudo; `funcionário` registra pedidos no
balcão; `entregador` só recebe os pedidos prontos e marca a entrega. O admin
pode liberar a um funcionário específico a permissão de gerenciar o estoque
(`can_manage_stock`), a de gerenciar os pedidos de toda a equipe
(`can_manage_orders`) e a de abrir o painel da loja (`can_view_dashboard`) —
esta última **seção por seção** (`dashboard_sections`): mapa, vendas, horários,
produtos, equipe, entrega, estoque e últimos pedidos são oito interruptores
independentes. A tela de Equipe tem todos eles.

**Estoque a peso, em lotes.** Produtos são vendidos por grama ou quilo.
Internamente **tudo é grama** (`Decimal`); a unidade do produto diz só como ele
é digitado e exibido, e preço e custo são sempre guardados por grama. Cada
entrada de mercadoria abre um **lote** com o custo pago, e lotes não se
misturam: duas compras do mesmo produto por preços diferentes continuam
separadas. O custo de um lote pode ser corrigido depois (digitou errado a nota,
por exemplo) — vale para o que ainda vai sair dele, e a correção fica no log de
auditoria; o que já foi vendido guarda o custo que tinha na hora. O saldo nunca é editado direto — entradas, saídas, devoluções e
ajustes viram linhas em `stock_movements`, com autor, lote e motivo, na mesma
transação que muda o saldo.

**Pedidos, com lucro.** O funcionário monta o pedido escolhendo produto, lote e
peso (em g ou kg), com desconto opcional em porcentagem ou em reais sobre o
total. Registrar o pedido **dá baixa no lote escolhido**; cancelar devolve ao
mesmo lote. Preço e nome do produto, custo e nome do lote são copiados para o
item — mudar preço ou comprar mais caro depois não reescreve o histórico nem o
lucro daquela venda. Custo e lucro só aparecem para admin e para quem gerencia
estoque.

**Entrega com endereço, mapa e entregador.** O pedido guarda o endereço
escrito no balcão; quem registra pode procurá-lo no mapa (OpenStreetMap, sem
chave de API) e fixar o ponto, que fica gravado no pedido. Pronto o pedido, o
balcão manda para um entregador — na hora da venda ou depois, pela tela do
pedido. Ele abre `/entregas` no celular, vê o que está com ele, traça a rota e
marca a saída e a chegada.

**Painel com gráficos, por categoria.** O resumo do período vira análise: o
mapa de onde os pedidos foram parar (um pino por endereço, o balão com os
pedidos daquele ponto), vendas e lucro por dia, movimento por hora, o que mais
vendeu, quem registrou,
como anda a entrega (incluindo tempo médio e desempenho por entregador), o que
foi cancelado e onde o dinheiro está parado no estoque. Cada gráfico traz a
tabela dos números junto. **Cada categoria busca o próprio dado quando chega
perto da tela** — a página abre só com o recorte de datas, e o que ninguém
rolou até o fim nem é consultado no banco. Cada bloco recolhe no toque do
título, e a escolha é lembrada na próxima visita; bloco fechado não consulta
nada. A home é só análise: registrar pedido é na tela de pedidos.

**E o painel é permissão, dentro e fora.** Sem `can_view_dashboard` a pessoa
não abre a home — o dia dela começa nos pedidos, e a barra de navegação não
mostra o item. Com ela, aparecem só as seções liberadas: seção fechada não é
escondida na tela, ela não é calculada nem enviada, então nem uma recarga
parcial pedida à mão a alcança. Lucro e custo dentro das seções continuam
presos à permissão de estoque — liberar Vendas mostra o faturamento, não a
margem.

**Lista de pedidos com busca e páginas.** A busca acha por cliente, endereço,
observação, código do pedido e nome de quem registrou ou está entregando; a
lista vem de 20 em 20. Filtro, busca, período e página moram na URL, então o
link é compartilhável e o botão de voltar funciona.

**Quem vê o quê.** Admin (e quem tem `can_manage_orders`) vê todos os pedidos;
funcionário vê só os que ele registrou; entregador, só os que estão com ele.
Isso é policy do Ash, não filtro de controller.

## Requisitos

- Elixir ~> 1.15 / OTP 27
- Node 20+ (só para instalar as dependências do front; o bundle é feito pelo
  esbuild que o Mix baixa sozinho)
- Docker, só para a caixa de e-mails de desenvolvimento (opcional)

O banco é SQLite: um arquivo (`h_stock_dev.db`) na raiz do projeto, criado
pelo `mix setup`. Não há servidor de banco para subir.

## Subindo o projeto

```sh
docker compose -f docker-compose.dev.yml up -d   # Mailhog (8028), opcional
mix setup                                        # deps, banco, seeds, assets
mix phx.server                                   # http://localhost:4000
```

**Em produção os seeds criam um único usuário: o administrador** — é o que o
sistema não consegue criar por dentro, já que não há cadastro público. **Em
desenvolvimento eles criam também a loja de exemplo** (`Core.Demo`): tela vazia
não se avalia.

| Login         | Senha             | Perfil                     |
| ------------- | ----------------- | -------------------------- |
| `admin`       | sorteada, ver ↓   | admin                      |
| `funcionario` | `Pass@123!`       | funcionário, painel aberto |
| `entregador`  | `Pass@123!`       | entregador                 |

Sem `ADMIN_PASSWORD`, a senha do admin é **sorteada e mostrada uma única vez**,
no fim da saída do comando — guarde-a antes de fechar o terminal. Uma senha
padrão escrita no repositório seria uma senha pública.

```sh
mix run priv/repo/seeds.exs                              # senha sorteada
ADMIN_NICKNAME=chefe ADMIN_PASSWORD='umaSenhaBoa' \
  mix run priv/repo/seeds.exs                            # senha escolhida
```

Rodar de novo não duplica nada nem reverte uma senha trocada depois. E o
primeiro login pede a verificação em duas etapas: tenha o aplicativo
autenticador à mão (ou suba com `TOTP_REQUIRED=false mix phx.server`).

Para o painel ter o que mostrar — ele só desenha onde houve venda — falta o
movimento, e ele sai de uma tarefa:

```sh
mix demo.orders            # um mês de vendas, com entregas e cancelamentos
mix demo.orders --dias 60
```

Ela também cria o que faltar do elenco, e não roda em produção.

Serviços de desenvolvimento:

- App — <http://localhost:4000>
- LiveDashboard — <http://localhost:4000/dev/dashboard>
- Caixa de e-mails (Swoosh local) — <http://localhost:4000/dev/mailbox> —
  hoje sem uso: nada no sistema envia e-mail desde que o login virou nickname.

## Telas

| Rota                     | O quê                                       | Quem                |
| ------------------------ | ------------------------------------------- | ------------------- |
| `/sign-in`               | Login                                       | público             |
| `/`                      | Painel: gráficos do período, por seção      | permissão do painel |
| `/pedidos`, `/pedidos/…` | Lista, registro, detalhe e cancelamento     | autenticado         |
| `/produtos`              | Catálogo e saldo                            | autenticado         |
| `/produtos/:id`          | Ficha, movimentação e histórico             | histórico: estoque  |
| `/produtos/novo`, `…`    | Cadastro/edição e movimentação de estoque   | admin ou permissão  |
| `/entregas`              | As entregas na mão do entregador            | entregador          |
| `/usuarios`              | Equipe, permissões, bloqueio, senha e 2FA   | admin               |
| `/seguranca`             | Verificação em duas etapas da própria conta | autenticado         |
| `/verificacao`           | Código de 6 dígitos (login e revalidação)   | —                   |

A navegação principal é a barra inferior — o app é feito para ser usado com uma
mão, no balcão.

## Como uma página funciona

O controller devolve o nome do componente e os props:

```elixir
def index(conn, _params) do
  conn
  |> assign_prop(:products, fn -> Core.Inventory.list_products!(actor: actor(conn)) end)
  |> render_inertia("Products/Index")
end
```

`"Products/Index"` é resolvido em `assets/js/pages/Products/Index.tsx`. Cada
página vira um chunk próprio (`--splitting` do esbuild), carregado sob demanda.

Detalhes que valem saber:

- Props saem em camelCase (`camelize_props: true`), mesmo escritos em
  snake_case no Elixir. `Web.Serializers` converte os structs do domínio —
  `Decimal` não é serializável em JSON.
- `Web.Plugs.SetCurrentUser` publica `user`, `csrfToken` e `flash` em toda
  resposta; use `useAuth()` no front. As flash viram toast pelo
  `useFlashToasts`.
- Erro de validação: o controller usa `fail/3`, que responde com redirect +
  erros por campo. O Inertia preserva o estado do formulário nesse caso, então
  o que a pessoa digitou continua lá.
- Confirmação é sempre componente do shadcn (`Dialog`/`AlertDialog`), nunca
  `window.confirm` nem `<dialog>` nativo. Feedback é sempre toast (sonner).

## Autenticação

`ash_authentication` com senha, sem "manter conectado": toda entrada abre uma
sessão nova, que morre com o navegador. O login é o **nickname** — o
sistema não guarda e-mail. **Não há cadastro público**
(`registration_enabled? false`): quem cria usuário é o admin, em `/usuarios`.
Usuário bloqueado (`active: false`) não consegue entrar.

Sem e-mail, também não há recuperação de senha por link: quem esquece pede ao
admin, que define uma nova em `/usuarios/:id/senha`.

| Ação          | Rota                               |
| ------------- | ---------------------------------- |
| Login         | `POST /auth/user/password/sign_in` |
| Segundo fator | `POST /verificacao`                |
| Logout        | `DELETE /sign-out`                 |

Os campos vão aninhados sob `user` (é o `subject_name` do recurso).

### Verificação em duas etapas (obrigatória)

**Nenhuma tela do sistema abre sem ela.** Quem entra e ainda não ativou é
levado para *Segurança* e não sai de lá até ativar; e mesmo depois, o código é
pedido **de novo a cada hora** de uso — passada a hora, o conteúdo fecha até a
pessoa digitar o código outra vez. O login continua valendo: a senha não é
pedida de novo.

A janela de uma hora é ajustável em
`config :h_stock, :totp_revalidation_seconds`.

A ativação serve a mesma conta de três formas: um **link `otpauth://`**, que no
celular abre o aplicativo autenticador já com a conta preenchida (é o caminho
normal — quem está na página pelo celular não consegue apontar a câmera para a
própria tela), um QR Code para escanear de outro aparelho, e a chave em texto
para digitar à mão. Serve Google Authenticator, Authy, 1Password ou qualquer
outro: TOTP é padrão aberto (RFC 6238) e nenhum serviço externo participa. Códigos de janelas vizinhas (±30s) são aceitos, senão um celular com o
relógio dessincronizado nunca entraria.

Na ativação saem **8 códigos de recuperação**, mostrados uma única vez e
guardados como hash. Se a pessoa perder o celular e os códigos, o admin
desliga o 2FA dela na tela de Equipe (editar pessoa).

A exigência é uma chave de configuração (`config :h_stock, :totp_required`,
ou `TOTP_REQUIRED=false`): desligada, ninguém é parado no login nem levado
para a ativação — mas nada é apagado, e religar volta a pedir o mesmo código.
**Ela está ligada em todos os ambientes**; desligar é uma exceção pontual
(`TOTP_REQUIRED=false mix phx.server`), não o padrão de desenvolvimento.

O nome que o autenticador mostra ao lado da conta é `TOTP_ISSUER`
(`config :h_stock, :totp_issuer`, padrão `Mercado`) — de propósito não é
"h_stock": a tela do autenticador é lida em qualquer lugar e não precisa
anunciar o sistema da loja. É rótulo, não segredo: trocá-lo não invalida
ativação nenhuma, e o nome antigo só sai do aplicativo de quem já ativou
quando essa pessoa ativar de novo.

Duas garantias que valem conhecer antes de mexer nesse código:

- **Entre a senha e o código não existe sessão.** O login fica num bilhete de
  espera (`Web.TotpSession`) que expira em 10 minutos e some depois de 5
  tentativas erradas — por isso a sessão é **cifrada**, e não apenas assinada
  (ver `Web.Endpoint`). E não há credencial de longa duração: fechada a
  sessão, entra-se de novo pela senha e pelo código.
- **A ativação vive no banco, não na tela.** Enquanto `totp_secret` existe e
  `totp_confirmed_at` não, a tela de Segurança remonta o mesmo QR. É o que faz
  errar um dígito não invalidar o QR que a pessoa acabou de escanear.

## Trabalhando com Ash

```sh
mix ash.codegen <nome_da_mudanca>   # gera migrations a partir dos recursos
mix ash.setup                       # cria o banco e migra
mix ash.reset                       # recria do zero
```

Nunca escreva migration à mão: altere o recurso e rode `ash.codegen`.

## Comandos

```sh
mix test               # testes
mix precommit          # compila com warnings-as-errors, formata e testa
mix demo.orders        # loja de exemplo: catálogo, equipe e vendas (só fora de produção)
mix assets.build       # build de CSS/JS
mix assets.deploy      # build minificado + digest (produção)
npm --prefix assets run check   # typecheck do TypeScript
```

## Deploy

Uma máquina, um volume, dois containers: a aplicação (release Elixir) e o
[Caddy](https://caddyserver.com), que termina o TLS e repassa. **O banco é um
arquivo no volume `h_stock_data`** — é o sistema inteiro. SQLite não é servidor
de banco: não dá para pôr duas máquinas na frente do mesmo arquivo, e o
tamanho do disco é o limite.

No servidor só é preciso ter **Docker** e as portas 80 e 443 abertas. Nada de
código, Elixir ou Node: a imagem chega pronta.

**Sem domínio, o endereço sai do próprio IP.** `203.0.113.10` vira
`PHX_HOST=203-0-113-10.sslip.io`: o [sslip.io](https://sslip.io) é um DNS
público e gratuito que devolve o IP embutido no nome, sem nada para registrar
ou administrar. Ele está aqui por um motivo prático — o Caddy precisa de um
**nome** para pedir o certificado, o Let's Encrypt não emite para IP pelado, e
sem certificado a senha e o código do 2FA viajariam em texto claro. Com o
`PHX_HOST` ainda no valor de exemplo, o `deploy.sh` para e diz qual nome pôr
para o servidor daquele `deploy.env`; e avisa se o nome apontar para um IP
diferente daquele para onde você está entregando. (Se um dia o Let's Encrypt recusar por limite do
serviço, `nip.io` funciona no mesmo formato.)

Com domínio próprio é a mesma linha, com o domínio já apontando para o IP
antes da primeira subida.

### `./deploy.sh`

Do seu computador:

```sh
cp .env.prod.example .env.prod       # segredos da aplicação
cp deploy.env.example deploy.env     # onde entregar (host, usuário, senha/chave)
mix phx.gen.secret                   # duas vezes: SECRET_KEY_BASE e TOKEN_SIGNING_SECRET
$EDITOR .env.prod deploy.env

./deploy.sh --seed                   # primeira vez: sobe e cria o admin
./deploy.sh                          # daí em diante
```

Nenhum dos dois arquivos vai para o git.

O script constrói a imagem aqui, envia **comprimida direto para o Docker do
servidor** (`docker save | gzip | ssh | docker load` — não sobra tarball em
lugar nenhum), copia `docker-compose.prod.yml`, `Caddyfile` e `.env.prod`
(este com permissão 600), sobe, **espera o healthcheck** e limpa as imagens
antigas de lá. Volume nenhum é tocado: é onde o banco mora.

- Já enviou esta versão? Ele pula build e envio. `--force` refaz. Árvore suja
  (`-dirty` na tag) nunca é pulada.
- `--seed` roda os seeds no fim — é o que cria o admin de
  `ADMIN_NICKNAME`/`ADMIN_PASSWORD` (sem a segunda, sorteia a senha e a
  imprime uma única vez). Idempotente: com o admin já criado, não faz nada.
- Deu errado? O script mostra o log e o comando de rollback: a versão que
  estava no ar fica marcada como `h_stock:previous`.

Autenticação por **chave SSH** é o padrão (`SSH_KEY`, ou as chaves que o seu
`ssh` já usa sozinho). `SERVER_PASSWORD` funciona, mas precisa do `sshpass`
instalado aqui — e um servidor que aceita senha no SSH é um servidor a menos
de uma senha de distância.

### Desmontar: `./teardown.sh`

Tira o h_stock do servidor — **trazendo o banco antes**:

```sh
./teardown.sh                       # baixa o backup, pergunta, e desmonta
./teardown.sh --saida ~/loja.db     # escolhe onde salvar
./teardown.sh --sem-backup          # quando não há o que salvar
```

A ordem é o ponto: o `bin/backup` roda no servidor, o arquivo vem direto do
container para o seu disco (nada fica lá), e aqui ele é conferido — tamanho e
assinatura de arquivo SQLite — **antes** de qualquer coisa ser apagada. Só
então caem containers, volumes, imagens e o `REMOTE_DIR` inteiro, `.env.prod`
incluído. Sem `-y`, ele ainda pede que você digite o endereço do servidor.

O padrão é `backups/h_stock-<data>.db`, que não vai para o git.

**Para voltar de um backup**, com a pilha no ar (o `stop` evita escrita
concorrente, e o `-wal`/`-shm` do banco vazio precisa sair junto):

```sh
scp backups/h_stock-….db root@SERVIDOR:/tmp/restaurar.db
ssh root@SERVIDOR
cd /opt/h_stock
vol=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' h_stock)
docker compose -f docker-compose.prod.yml stop app
docker run --rm -i -v "$vol":/data h_stock:latest \
  sh -c 'cat > /data/h_stock.db && rm -f /data/h_stock.db-wal /data/h_stock.db-shm' < /tmp/restaurar.db
docker compose -f docker-compose.prod.yml start app && rm /tmp/restaurar.db
```

### Na mão, sem o script

```sh
git clone git@github.com:devsnaked/h_stock.git && cd h_stock
cp .env.prod.example .env.prod && $EDITOR .env.prod
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml exec app /app/bin/seed   # só na 1ª vez
```

O container **migra sozinho antes de subir** (`rel/overlays/bin/start`), então
atualizar é `git pull` e o mesmo `up -d --build`.

### Detalhes que valem saber

- O essencial do `.env.prod` é `PHX_HOST`, `SECRET_KEY_BASE` e
  `TOKEN_SIGNING_SECRET` — sem os dois últimos a aplicação se recusa a subir,
  de propósito. **Trocar o `TOKEN_SIGNING_SECRET` desconecta todo mundo.**
- **`/health`** responde `ok` sem autenticação e consulta o banco. É o
  healthcheck do container e o que o Caddy espera antes de repassar.
- **Backup é uma cópia do arquivo — mas não com `cp`.** Com o WAL ligado, uma
  cópia crua sai pela metade; `bin/backup` pede ao próprio SQLite um banco
  novo e íntegro, sem parar as escritas:

  ```sh
  docker compose -f docker-compose.prod.yml exec app /app/bin/backup
  docker compose -f docker-compose.prod.yml cp app:/data/backup-… ./backup.db
  ```

- **Console remoto:** `docker compose -f docker-compose.prod.yml exec app
  /app/bin/h_stock remote`.
- Variáveis lidas do ambiente ficam em `config/runtime.exs`. `config.exs` é
  lido em tempo de **compilação** — variável posta lá não chega na imagem.
