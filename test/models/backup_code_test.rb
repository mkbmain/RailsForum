require "test_helper"

class BackupCodeTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "bc@example.com", name: "BC User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
  end

  test "generate_for creates 8 backup codes for the user" do
    plaintext = BackupCode.generate_for(@user)
    assert_equal 8, plaintext.length
    assert_equal 8, @user.backup_codes.count
  end

  test "generate_for returns plaintext codes that are not stored in plaintext" do
    plaintext = BackupCode.generate_for(@user)
    digests = @user.backup_codes.pluck(:digest)
    plaintext.each do |code|
      assert_not_includes digests, code
    end
  end

  test "consume_for returns true and marks code used when a valid code is submitted" do
    plaintext = BackupCode.generate_for(@user)
    assert BackupCode.consume_for(@user, plaintext.first)
    used = @user.backup_codes.find { |bc| BCrypt::Password.new(bc.digest) == plaintext.first }
    assert_not_nil used&.used_at
  end

  test "consume_for returns false for an invalid code" do
    BackupCode.generate_for(@user)
    assert_not BackupCode.consume_for(@user, "invalid-code-000")
  end

  test "consume_for returns false when code has already been used" do
    plaintext = BackupCode.generate_for(@user)
    BackupCode.consume_for(@user, plaintext.first)
    assert_not BackupCode.consume_for(@user, plaintext.first)
  end

  test "unused scope excludes used codes" do
    BackupCode.generate_for(@user)
    code = @user.backup_codes.first
    code.update!(used_at: Time.current)
    assert_equal 7, @user.backup_codes.unused.count
  end
end
