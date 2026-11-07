defmodule ZentinelCp.Accounts.TotpTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Accounts.Totp
  alias ZentinelCp.Accounts.UserTotp

  import ZentinelCp.AccountsFixtures

  describe "create_user_totp/1" do
    test "creates a TOTP enrollment with secret and recovery codes" do
      user = user_fixture()

      assert {:ok, totp} = Totp.create_user_totp(user.id)
      assert totp.user_id == user.id
      assert totp.secret != nil
      assert byte_size(totp.secret) > 0
      assert length(totp.recovery_codes) == 10
      assert totp.verified_at == nil
    end

    test "enforces one TOTP per user" do
      user = user_fixture()

      {:ok, totp} = Totp.create_user_totp(user.id)
      {:ok, _} = Totp.verify_totp_enrollment(totp, NimbleTOTP.verification_code(totp.secret))
      assert {:error, changeset} = Totp.create_user_totp(user.id)
      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "replaces an abandoned enrollment" do
      user = user_fixture()

      {:ok, abandoned} = Totp.create_user_totp(user.id)
      {:ok, replacement} = Totp.create_user_totp(user.id)

      assert replacement.id != abandoned.id
    end
  end

  describe "verify_totp_enrollment/2" do
    test "activates MFA with valid code" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)

      valid_code = NimbleTOTP.verification_code(totp.secret)
      assert {:ok, verified} = Totp.verify_totp_enrollment(totp, valid_code)
      assert verified.verified_at != nil
    end

    test "rejects invalid code" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)

      assert {:error, :invalid_code} = Totp.verify_totp_enrollment(totp, "000000")
    end
  end

  describe "validate_totp/2" do
    setup do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)
      valid_code = NimbleTOTP.verification_code(totp.secret)
      {:ok, totp} = Totp.verify_totp_enrollment(totp, valid_code)

      # Enrollment used this time step's code. Clear that so tests can use it again.
      totp = totp |> Ecto.Changeset.change(last_used_at: nil) |> Repo.update!()
      %{totp: totp}
    end

    test "validates correct TOTP code", %{totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)
      assert {:ok, _} = Totp.validate_totp(totp, code)
    end

    test "rejects a code that was already used", %{totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)
      {:ok, _} = Totp.validate_totp(totp, code)
      used = Totp.get_user_totp(totp.user_id)
      assert {:error, :invalid_code} = Totp.validate_totp(used, code)
    end

    test "rejects wrong TOTP code", %{totp: totp} do
      assert {:error, :invalid_code} = Totp.validate_totp(totp, "000000")
    end

    test "accepts recovery code and removes it", %{totp: totp} do
      recovery_code = hd(totp.plain_recovery_codes)
      refute recovery_code in totp.recovery_codes
      assert {:ok, _} = Totp.validate_totp(totp, recovery_code)

      # Recovery code should be consumed
      updated_totp = Totp.get_user_totp(totp.user_id)
      assert length(updated_totp.recovery_codes) == 9
      assert {:error, :invalid_code} = Totp.validate_totp(updated_totp, recovery_code)
    end
  end

  describe "mfa_enabled?/1" do
    test "returns false when no TOTP enrolled" do
      user = user_fixture()
      assert Totp.mfa_enabled?(user.id) == false
    end

    test "returns false when TOTP enrolled but not verified" do
      user = user_fixture()
      {:ok, _} = Totp.create_user_totp(user.id)
      assert Totp.mfa_enabled?(user.id) == false
    end

    test "returns true when TOTP verified" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)
      code = NimbleTOTP.verification_code(totp.secret)
      {:ok, _} = Totp.verify_totp_enrollment(totp, code)
      assert Totp.mfa_enabled?(user.id) == true
    end
  end

  describe "delete_user_totp/1" do
    test "removes TOTP configuration" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)

      assert {:ok, _} = Totp.delete_user_totp(totp)
      assert Totp.get_user_totp(user.id) == nil
    end
  end

  describe "regenerate_recovery_codes/1" do
    test "replaces recovery codes" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)
      original_codes = totp.recovery_codes

      assert {:ok, updated} = Totp.regenerate_recovery_codes(totp)
      assert length(updated.recovery_codes) == 10
      assert updated.recovery_codes != original_codes
    end
  end

  describe "check_mfa_requirement/2" do
    test "returns :ok when policy is optional" do
      user = user_fixture()
      org = %{settings: %{"mfa_policy" => "optional"}}
      assert Totp.check_mfa_requirement(user, org) == :ok
    end

    test "returns :ok when MFA is required and enabled" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)
      code = NimbleTOTP.verification_code(totp.secret)
      {:ok, _} = Totp.verify_totp_enrollment(totp, code)

      org = %{
        mfa_policy: "required",
        mfa_enforced_at: DateTime.utc_now(),
        mfa_grace_period_days: 14
      }

      assert Totp.check_mfa_requirement(user, org) == :ok
    end

    test "returns {:required, deadline} when MFA is required but not enabled" do
      user = user_fixture()
      enforced_at = DateTime.to_iso8601(DateTime.utc_now())
      org = %{settings: %{"mfa_policy" => "required", "mfa_enforced_at" => enforced_at}}

      assert {:required, deadline} = Totp.check_mfa_requirement(user, org)
      assert deadline != nil
    end

    test "only enforces for admins when policy is required_for_admins" do
      admin = user_fixture(%{role: "admin"})
      operator = user_fixture(%{role: "operator"})

      org = %{
        settings: %{
          "mfa_policy" => "required_for_admins",
          "mfa_enforced_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "mfa_grace_period_days" => 14
        }
      }

      assert {:required, _} = Totp.check_mfa_requirement(admin, org)
      assert :ok = Totp.check_mfa_requirement(operator, org)
    end
  end

  describe "UserTotp.otpauth_uri/2" do
    test "generates a valid otpauth URI" do
      user = user_fixture()
      {:ok, totp} = Totp.create_user_totp(user.id)

      uri = UserTotp.otpauth_uri(totp, "test@example.com")
      assert String.starts_with?(uri, "otpauth://totp/ZentinelCP:test@example.com")
      assert String.contains?(uri, "issuer=ZentinelCP")
    end
  end
end
