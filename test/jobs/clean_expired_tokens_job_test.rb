require "test_helper"

class CleanExpiredTokensJobTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "token@example.com", name: "Token User",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
  end

  test "deletes expired password resets" do
    pr = PasswordReset.create!(user: @user)
    pr.update_columns(created_at: (PasswordReset::EXPIRY + 1.minute).ago)

    assert_difference "PasswordReset.count", -1 do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "keeps unexpired password resets" do
    PasswordReset.create!(user: @user)

    assert_no_difference "PasswordReset.count" do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "deletes expired email verifications" do
    ev = EmailVerification.create!(user: @user)
    ev.update_columns(created_at: (EmailVerification::EXPIRY + 1.minute).ago)

    assert_difference "EmailVerification.count", -1 do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "keeps unexpired email verifications" do
    EmailVerification.create!(user: @user)

    assert_no_difference "EmailVerification.count" do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "deletes both in one run" do
    pr = PasswordReset.create!(user: @user)
    pr.update_columns(created_at: (PasswordReset::EXPIRY + 1.minute).ago)

    user2 = User.create!(email: "token2@example.com", name: "Token User2",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    ev = EmailVerification.create!(user: user2)
    ev.update_columns(created_at: (EmailVerification::EXPIRY + 1.minute).ago)

    assert_difference "PasswordReset.count", -1 do
      assert_difference "EmailVerification.count", -1 do
        CleanExpiredTokensJob.perform_now
      end
    end
  end
end
