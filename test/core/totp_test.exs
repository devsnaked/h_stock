defmodule Core.TotpTest do
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Accounts.Totp
  alias Core.Accounts.User

  defp enrolled(user) do
    {:ok, user} = User.start_totp_enrollment(user, actor: user)
    code = NimbleTOTP.verification_code(user.totp_secret)
    {:ok, user} = User.confirm_totp(user, code, actor: user)
    user
  end

  describe "ativação" do
    test "começar gera um segredo mas ainda não liga o 2FA" do
      user = user_fixture()

      {:ok, user} = User.start_totp_enrollment(user, actor: user)

      assert user.totp_secret
      refute user.totp_confirmed_at
    end

    test "confirmar com o código certo liga e devolve os códigos de recuperação" do
      user = user_fixture()
      {:ok, user} = User.start_totp_enrollment(user, actor: user)

      code = NimbleTOTP.verification_code(user.totp_secret)
      {:ok, user} = User.confirm_totp(user, code, actor: user)

      assert user.totp_confirmed_at
      assert length(user.totp_recovery_hashes) == 8
      assert [_ | _] = codes = user.__metadata__.recovery_codes
      assert length(codes) == 8
      # Guardados como hash: o banco nunca vê o código em claro.
      refute Enum.any?(codes, &(&1 in user.totp_recovery_hashes))
    end

    test "confirmar com código errado não liga nada" do
      user = user_fixture()
      {:ok, user} = User.start_totp_enrollment(user, actor: user)

      assert {:error, %Ash.Error.Invalid{}} = User.confirm_totp(user, "000000", actor: user)

      user = Ash.get!(User, user.id, authorize?: false)
      refute user.totp_confirmed_at
    end

    test "começar de novo descarta a ativação anterior" do
      user = enrolled(user_fixture())
      primeiro_segredo = user.totp_secret

      {:ok, user} = User.start_totp_enrollment(user, actor: user)

      refute user.totp_confirmed_at
      refute user.totp_secret == primeiro_segredo
      assert user.totp_recovery_hashes == []
    end

    test "desligar apaga segredo e códigos" do
      user = enrolled(user_fixture())

      {:ok, user} = User.disable_totp(user, actor: user)

      refute user.totp_secret
      refute user.totp_confirmed_at
      assert user.totp_recovery_hashes == []
    end
  end

  describe "permissões" do
    test "ninguém ativa o 2FA de outra pessoa" do
      user = user_fixture()
      colega = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               User.start_totp_enrollment(user, actor: colega)
    end

    test "admin pode desligar o de um funcionário travado" do
      admin = admin_fixture()
      user = enrolled(user_fixture())

      assert {:ok, user} = User.disable_totp(user, actor: admin)
      refute user.totp_confirmed_at
    end

    test "funcionário não desliga o de outro" do
      user = enrolled(user_fixture())
      colega = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} = User.disable_totp(user, actor: colega)
    end
  end

  describe "conferência do código" do
    test "aceita o código do momento" do
      secret = Totp.secret()

      assert Totp.valid?(secret, NimbleTOTP.verification_code(secret), nil)
    end

    test "recusa código errado, vazio ou fora de formato" do
      secret = Totp.secret()

      refute Totp.valid?(secret, "000000", nil)
      refute Totp.valid?(secret, "", nil)
      refute Totp.valid?(secret, "abc", nil)
      refute Totp.valid?(secret, nil, nil)
      refute Totp.valid?(nil, "123456", nil)
    end

    test "o mesmo código não vale duas vezes" do
      secret = Totp.secret()
      code = NimbleTOTP.verification_code(secret)

      assert Totp.valid?(secret, code, nil)
      # Depois de usado, `since` no agora recusa a repetição dentro da janela.
      refute Totp.valid?(secret, code, DateTime.utc_now())
    end
  end

  describe "códigos de recuperação" do
    test "um código válido é aceito e sai da lista" do
      {codes, hashes} = Totp.generate_recovery_codes()
      [primeiro | _] = codes

      assert {:ok, restantes} = Totp.consume_recovery_code(hashes, primeiro)
      assert length(restantes) == length(hashes) - 1

      # E não serve de novo.
      assert :error = Totp.consume_recovery_code(restantes, primeiro)
    end

    test "código inexistente é recusado" do
      {_codes, hashes} = Totp.generate_recovery_codes()

      assert :error = Totp.consume_recovery_code(hashes, "naoexiste")
      assert :error = Totp.consume_recovery_code(hashes, nil)
      assert :error = Totp.consume_recovery_code([], "qualquer")
    end
  end
end
