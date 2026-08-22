defmodule Core.Accounts do
  use Ash.Domain,
    otp_app: :h_stock

  resources do
    resource Core.Accounts.Token
    resource Core.Accounts.User
  end
end
