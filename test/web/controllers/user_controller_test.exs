defmodule Web.UserControllerTest do
  use Web.ConnCase, async: true

  require Ash.Query

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Accounts.User

  test "funcionário não acessa a área de equipe", %{conn: conn} do
    conn = conn |> log_in(user_fixture()) |> get(~p"/usuarios")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administrador"
  end

  describe "admin" do
    setup %{conn: conn} do
      admin = admin_fixture(name: "Chefe")
      %{conn: log_in(conn, admin), admin: admin}
    end

    test "lista a equipe", %{conn: conn} do
      user_fixture(name: "Joana")
      conn = get(conn, ~p"/usuarios")

      assert inertia_component(conn) == "Users/Index"
      assert %{users: users} = inertia_props(conn)
      assert "Joana" in Enum.map(users, & &1.name)
    end

    test "cadastra funcionário", %{conn: conn} do
      conn =
        post(conn, ~p"/usuarios", %{
          "name" => "Novo",
          "nickname" => "novo",
          "password" => "senha12345",
          "password_confirmation" => "senha12345",
          "role" => "employee",
          "can_manage_stock" => true
        })

      assert redirected_to(conn) == ~p"/usuarios"

      user =
        User
        |> Ash.Query.filter(nickname == "novo")
        |> Ash.read_one!(authorize?: false)

      assert user.name == "Novo"
      assert user.role == :employee
      assert user.can_manage_stock
    end

    test "senhas diferentes voltam com erro", %{conn: conn} do
      conn =
        post(conn, ~p"/usuarios", %{
          "name" => "Novo",
          "nickname" => "outro",
          "password" => "senha12345",
          "password_confirmation" => "outra-senha"
        })

      assert redirected_to(conn) == ~p"/usuarios/novo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "libera a permissão de estoque de um funcionário", %{conn: conn} do
      employee = user_fixture()

      conn =
        put(conn, ~p"/usuarios/#{employee.id}", %{
          "role" => "employee",
          "can_manage_stock" => true
        })

      assert redirected_to(conn) == ~p"/usuarios"
      assert Ash.get!(User, employee.id, authorize?: false).can_manage_stock
    end

    test "libera o painel com as seções escolhidas", %{conn: conn} do
      employee = user_fixture()

      conn =
        put(conn, ~p"/usuarios/#{employee.id}", %{
          "role" => "employee",
          "can_view_dashboard" => true,
          # Fora de ordem e com uma seção inventada: sai na ordem do painel, e
          # o que não existe é descartado em vez de virar erro.
          "dashboard_sections" => ["stock", "sales", "faturamento-do-vizinho"]
        })

      assert redirected_to(conn) == ~p"/usuarios"

      employee = Ash.get!(User, employee.id, authorize?: false)

      assert employee.can_view_dashboard
      assert employee.dashboard_sections == [:sales, :stock]
    end

    test "desligar o painel esvazia as seções", %{conn: conn} do
      employee = user_fixture(can_view_dashboard: true, dashboard_sections: :all)

      conn =
        put(conn, ~p"/usuarios/#{employee.id}", %{
          "role" => "employee",
          "dashboard_sections" => ["sales"]
        })

      assert redirected_to(conn) == ~p"/usuarios"

      employee = Ash.get!(User, employee.id, authorize?: false)

      refute employee.can_view_dashboard
      # Nada de permissão pendurada: religar a chave não devolve a seção
      # sozinho, alguém precisa escolher de novo.
      assert employee.dashboard_sections == []
    end

    test "cadastra funcionário já com o painel", %{conn: conn} do
      conn =
        post(conn, ~p"/usuarios", %{
          "name" => "Analista",
          "nickname" => "analista",
          "password" => "senha12345",
          "password_confirmation" => "senha12345",
          "role" => "employee",
          "can_view_dashboard" => true,
          "dashboard_sections" => ["sales", "hours"]
        })

      assert redirected_to(conn) == ~p"/usuarios"

      user =
        User
        |> Ash.Query.filter(nickname == "analista")
        |> Ash.read_one!(authorize?: false)

      assert user.can_view_dashboard
      assert user.dashboard_sections == [:sales, :hours]
    end

    test "bloqueia o acesso de um funcionário", %{conn: conn} do
      employee = user_fixture()

      conn = post(conn, ~p"/usuarios/#{employee.id}/ativo", %{"active" => false})

      assert redirected_to(conn) == ~p"/usuarios"
      refute Ash.get!(User, employee.id, authorize?: false).active
    end

    test "não pode desativar a própria conta", %{conn: conn, admin: admin} do
      conn = post(conn, ~p"/usuarios/#{admin.id}/ativo", %{"active" => false})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "própria conta"
      assert Ash.get!(User, admin.id, authorize?: false).active
    end

    test "desliga o 2FA de quem perdeu o celular", %{conn: conn} do
      employee = user_fixture()
      {:ok, employee} = User.start_totp_enrollment(employee, actor: employee)

      {:ok, employee} =
        User.confirm_totp(employee, NimbleTOTP.verification_code(employee.totp_secret),
          actor: employee
        )

      conn = post(conn, ~p"/usuarios/#{employee.id}/2fa/desligar")

      assert redirected_to(conn) == ~p"/usuarios/#{employee.id}/editar"
      recarregado = Ash.get!(User, employee.id, authorize?: false)
      refute recarregado.totp_confirmed_at
      refute recarregado.totp_secret
    end

    test "funcionário não desliga o 2FA de outro", %{conn: _conn} do
      alvo = user_fixture()
      {:ok, alvo} = User.start_totp_enrollment(alvo, actor: alvo)

      {:ok, alvo} =
        User.confirm_totp(alvo, NimbleTOTP.verification_code(alvo.totp_secret), actor: alvo)

      conn =
        build_conn()
        |> log_in(user_fixture())
        |> post(~p"/usuarios/#{alvo.id}/2fa/desligar")

      # O plug de admin barra antes de chegar na policy.
      assert redirected_to(conn) == ~p"/"
      assert Ash.get!(User, alvo.id, authorize?: false).totp_confirmed_at
    end

    test "redefine a senha de um funcionário", %{conn: conn} do
      employee = user_fixture()
      hash_antes = employee.hashed_password

      conn =
        post(conn, ~p"/usuarios/#{employee.id}/senha", %{
          "password" => "nova-senha-123",
          "password_confirmation" => "nova-senha-123"
        })

      assert redirected_to(conn) == ~p"/usuarios"
      assert Ash.get!(User, employee.id, authorize?: false).hashed_password != hash_antes
    end
  end
end
