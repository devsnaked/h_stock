defmodule Web.UserController do
  @moduledoc """
  Gestão de usuários — só admin. É por aqui que se define o perfil de cada
  pessoa (balcão ou entregador) e se liberam a um funcionário as permissões de
  gerenciar o estoque, os pedidos da equipe e o painel da loja — este último
  seção por seção.
  """
  use Web, :controller

  require Ash.Query

  alias Core.Accounts.Permissions
  alias Core.Accounts.User
  alias Web.Serializers

  def index(conn, _params) do
    users =
      User
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: actor(conn))

    conn
    |> assign_prop(:users, Enum.map(users, &Serializers.user/1))
    |> render_inertia("Users/Index")
  end

  def new(conn, _params) do
    conn
    |> assign_prop(:user, nil)
    |> render_inertia("Users/Form")
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, user} <- fetch(User, id, actor: actor(conn)) do
      conn
      |> assign_prop(:user, Serializers.user(user))
      |> render_inertia("Users/Form")
    else
      :error -> not_found(conn, ~p"/usuarios", "Usuário não encontrado.")
    end
  end

  def create(conn, params) do
    User.create_user(
      params["nickname"],
      params["name"],
      params["password"],
      params["password_confirmation"],
      permissions(params, "employee"),
      actor: actor(conn)
    )
    |> case do
      {:ok, user} ->
        conn
        |> put_flash(:info, "#{user.name} cadastrado(a).")
        |> redirect(to: ~p"/usuarios")

      {:error, error} ->
        fail(conn, error, ~p"/usuarios/novo")
    end
  end

  def update(conn, %{"id" => id} = params) do
    admin = actor(conn)

    with {:ok, user} <- fetch(User, id, actor: admin),
         {:ok, user} <-
           User.set_permissions(user, permissions(params, to_string(user.role)), actor: admin) do
      conn
      |> put_flash(:info, "Permissões de #{user.name} atualizadas.")
      |> redirect(to: ~p"/usuarios")
    else
      :error -> not_found(conn, ~p"/usuarios", "Usuário não encontrado.")
      {:error, error} -> fail(conn, error, ~p"/usuarios/#{id}/editar")
    end
  end

  # As permissões do formulário, do jeito que o domínio as espera. Switch
  # desmarcado não chega como `false` — não chega — então tudo é comparado com
  # `true`: o que o formulário não afirmar está desligado.
  defp permissions(params, default_role) do
    %{
      role: params["role"] || default_role,
      can_manage_stock: params["can_manage_stock"] == true,
      can_manage_orders: params["can_manage_orders"] == true,
      can_view_dashboard: params["can_view_dashboard"] == true,
      dashboard_sections: sections(params["dashboard_sections"])
    }
  end

  # A lista chega como nomes de seção; o que não estiver na lista canônica é
  # descartado. Nada de `String.to_atom/1` em parâmetro de requisição: os
  # átomos saem de `Core.Accounts.Permissions`, e o que vem do navegador só
  # escolhe entre eles.
  defp sections(wanted) do
    wanted = wanted |> List.wrap() |> Enum.filter(&is_binary/1)

    Enum.filter(Permissions.dashboard_sections(), &(to_string(&1) in wanted))
  end

  @doc "Ativa/desativa o acesso. Usuário inativo não consegue mais entrar."
  def toggle_active(conn, %{"id" => id, "active" => active}) do
    admin = actor(conn)

    with {:ok, user} <- fetch(User, id, actor: admin) do
      if user.id == admin.id do
        conn
        |> put_flash(:error, "Você não pode desativar a própria conta.")
        |> redirect(to: ~p"/usuarios")
      else
        set_active(conn, user, active == true, admin)
      end
    else
      :error -> not_found(conn, ~p"/usuarios", "Usuário não encontrado.")
    end
  end

  @doc "Admin define uma nova senha (o funcionário esqueceu, por exemplo)."
  def reset_password(conn, %{"id" => id} = params) do
    admin = actor(conn)

    with {:ok, user} <- fetch(User, id, actor: admin),
         {:ok, user} <-
           User.set_password(
             user,
             params["password"],
             params["password_confirmation"],
             actor: admin
           ) do
      conn
      |> put_flash(:info, "Senha de #{user.name} redefinida.")
      |> redirect(to: ~p"/usuarios")
    else
      :error -> not_found(conn, ~p"/usuarios", "Usuário não encontrado.")
      {:error, error} -> fail(conn, error, ~p"/usuarios/#{id}/editar")
    end
  end

  @doc """
  Destrava quem perdeu o celular e gastou os códigos de recuperação.

  É a única saída para uma conta com 2FA e sem acesso ao aplicativo — por isso
  a policy de `disable_totp` aceita o admin, além da própria pessoa.
  """
  def disable_totp(conn, %{"id" => id}) do
    admin = actor(conn)

    with {:ok, user} <- fetch(User, id, actor: admin),
         {:ok, user} <- User.disable_totp(user, actor: admin) do
      conn
      |> put_flash(:info, "Verificação em duas etapas de #{user.name} desligada.")
      |> redirect(to: ~p"/usuarios/#{user.id}/editar")
    else
      :error -> not_found(conn, ~p"/usuarios", "Usuário não encontrado.")
      {:error, error} -> fail(conn, error, ~p"/usuarios/#{id}/editar")
    end
  end

  defp set_active(conn, user, active, admin) do
    case User.set_active(user, active, actor: admin) do
      {:ok, user} ->
        conn
        |> put_flash(:info, if(user.active, do: "Acesso liberado.", else: "Acesso bloqueado."))
        |> redirect(to: ~p"/usuarios")

      {:error, error} ->
        fail(conn, error, ~p"/usuarios")
    end
  end
end
