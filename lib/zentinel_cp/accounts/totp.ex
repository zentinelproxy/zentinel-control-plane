defmodule ZentinelCp.Accounts.Totp do
  @moduledoc """
  TOTP multi-factor authentication context.
  Handles enrollment, verification, recovery codes, and org enforcement policies.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Accounts.UserTotp

  @doc """
  Gets the TOTP configuration for a user.
  Returns nil if MFA is not enrolled.
  """
  def get_user_totp(user_id) do
    Repo.get_by(UserTotp, user_id: user_id)
  end

  @doc """
  Creates a new TOTP enrollment for a user.
  Returns the UserTotp with the secret and recovery codes.
  The TOTP is not active until verified with a valid code.
  """
  def create_user_totp(user_id) do
    %UserTotp{}
    |> UserTotp.create_changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  @doc """
  Verifies a TOTP code and activates MFA for the user.
  Used during initial enrollment to confirm the user has the correct secret.
  """
  def verify_totp_enrollment(%UserTotp{} = totp, code) do
    if valid_totp_code?(totp, code) do
      totp
      |> UserTotp.verify_changeset()
      |> Repo.update()
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Validates a TOTP code during login.
  Returns {:ok, totp} if valid, {:error, :invalid_code} otherwise.
  """
  def validate_totp(%UserTotp{} = totp, code) do
    cond do
      valid_totp_code?(totp, code) ->
        {:ok, _} =
          totp
          |> UserTotp.touch_changeset()
          |> Repo.update()

        {:ok, totp}

      valid_recovery_code?(totp, code) ->
        {:ok, _} =
          totp
          |> UserTotp.use_recovery_code_changeset(code)
          |> Repo.update()

        {:ok, totp}

      true ->
        {:error, :invalid_code}
    end
  end

  @doc """
  Deletes the TOTP configuration for a user (disables MFA).
  """
  def delete_user_totp(%UserTotp{} = totp) do
    Repo.delete(totp)
  end

  @doc """
  Regenerates recovery codes for a user's TOTP.
  """
  def regenerate_recovery_codes(%UserTotp{} = totp) do
    totp
    |> UserTotp.regenerate_recovery_codes_changeset()
    |> Repo.update()
  end

  @doc """
  Checks if a user has MFA enabled (enrolled and verified).
  """
  def mfa_enabled?(user_id) do
    case get_user_totp(user_id) do
      %UserTotp{} = totp -> UserTotp.verified?(totp)
      nil -> false
    end
  end

  @doc """
  Checks if a user needs to enroll in MFA based on org policy.
  Returns `{:required, deadline}` if MFA is required but not enrolled,
  `:ok` if MFA is not required or already enrolled.
  """
  def check_mfa_requirement(user, org) do
    policy = org_mfa_policy(org)

    case policy do
      "optional" ->
        :ok

      "required" ->
        if mfa_enabled?(user.id), do: :ok, else: {:required, mfa_deadline(org)}

      "required_for_admins" ->
        if user.role == "admin" and not mfa_enabled?(user.id) do
          {:required, mfa_deadline(org)}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp valid_totp_code?(%UserTotp{secret: secret}, code) when is_binary(code) do
    NimbleTOTP.valid?(secret, code)
  end

  defp valid_totp_code?(_, _), do: false

  defp valid_recovery_code?(%UserTotp{recovery_codes: codes}, code) when is_binary(code) do
    code in codes
  end

  defp valid_recovery_code?(_, _), do: false

  defp org_mfa_policy(org) do
    Map.get(org, :mfa_policy, "optional")
  end

  defp mfa_deadline(org) do
    grace_days = Map.get(org, :mfa_grace_period_days, 14)
    enforced_at = Map.get(org, :mfa_enforced_at)

    if enforced_at do
      DateTime.add(enforced_at, grace_days * 86_400, :second)
    else
      nil
    end
  end
end
