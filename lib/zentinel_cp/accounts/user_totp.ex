defmodule ZentinelCp.Accounts.UserTotp do
  @moduledoc """
  Schema for TOTP-based multi-factor authentication.
  Stores the shared secret and recovery codes for each user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @recovery_code_count 10

  schema "user_totps" do
    field :secret, :binary
    field :recovery_codes, {:array, :string}, default: []
    field :verified_at, :utc_datetime
    field :last_used_at, :utc_datetime

    belongs_to :user, ZentinelCp.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(totp, attrs) do
    totp
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> put_secret()
    |> put_recovery_codes()
    |> foreign_key_constraint(:user_id)
  end

  def verify_changeset(totp) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    totp
    |> change(%{verified_at: now, last_used_at: now})
  end

  def touch_changeset(totp) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(totp, %{last_used_at: now})
  end

  def use_recovery_code_changeset(totp, code) do
    remaining = List.delete(totp.recovery_codes, code)
    change(totp, %{recovery_codes: remaining})
  end

  def regenerate_recovery_codes_changeset(totp) do
    change(totp, %{recovery_codes: generate_recovery_codes()})
  end

  def verified?(%__MODULE__{verified_at: nil}), do: false
  def verified?(%__MODULE__{}), do: true

  defp put_secret(changeset) do
    if get_field(changeset, :secret) do
      changeset
    else
      put_change(changeset, :secret, NimbleTOTP.secret())
    end
  end

  defp put_recovery_codes(changeset) do
    put_change(changeset, :recovery_codes, generate_recovery_codes())
  end

  defp generate_recovery_codes do
    Enum.map(1..@recovery_code_count, fn _ ->
      :crypto.strong_rand_bytes(5) |> Base.encode32(padding: false) |> String.downcase()
    end)
  end

  @doc """
  Generates an otpauth:// URI for QR code generation.
  """
  def otpauth_uri(%__MODULE__{secret: secret}, email) when is_binary(email) do
    NimbleTOTP.otpauth_uri("ZentinelCP:#{email}", secret, issuer: "ZentinelCP")
  end
end
