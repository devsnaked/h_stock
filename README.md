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
esta última **seção por seção** (`dashboard_sections`): vendas, horários,
produtos, equipe, entrega, estoque e últimos pedidos são sete interruptores
independentes. A tela de Equipe tem todos eles.

**Estoque a peso, em lotes.** Produtos são vendidos por grama ou quilo.
Internamente **tudo é grama** (`Decimal`); a unidade do produto diz só como ele
é digitado e exibido, e preço e custo são sempre guardados por grama. Cada
entrada de mercadoria abre um **lote** com o custo pago, e lotes não se
misturam: duas compras do mesmo produto por preços diferentes continuam
separadas. O saldo nunca é editado direto — entradas, saídas, devoluções e
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

**Painel com gráficos, por categoria.** O resumo do período vira análise:
vendas e lucro por dia, movimento por hora, o que mais vendeu, quem registrou,
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
- Docker, para o Postgres de desenvolvimento

## Subindo o projeto

```sh
docker compose -f docker-compose.dev.yml up -d   # Postgres (5435) + Mailhog (8028)
mix setup                                        # deps, banco, seeds, assets
mix phx.server                                   # http://localhost:4000
```

Os seeds criam os acessos iniciais e alguns produtos de exemplo:

| Login          | Senha       | Perfil      |
| -------------- | ----------- | ----------- |
| `admin`        | `Pass@123!` | admin       |
| `funcionario`  | `Pass@123!` | funcionário |
| `entregador`   | `Pass@123!` | entregador  |

O admin é a única parte indispensável do seed: como não há cadastro público,
sem ele não existe forma de entrar e criar os outros usuários. Três variáveis
ajustam isso:

```sh
ADMIN_NICKNAME=chefe ADMIN_PASSWORD='umaSenhaBoa' SEED_DEMO=false \
  mix run priv/repo/seeds.exs
```

`SEED_DEMO=false` pula o funcionário, o entregador e os produtos de exemplo — é o que se usa
fora de desenvolvimento. Os seeds são idempotentes e não mexem em quem já
existe, então rodar de novo não reverte uma senha trocada.

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
**Em desenvolvimento ela está desligada** (`config/dev.exs`); em produção vale
o padrão, que é exigir.

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
mix assets.build       # build de CSS/JS
mix assets.deploy      # build minificado + digest (produção)
npm --prefix assets run check   # typecheck do TypeScript
```
