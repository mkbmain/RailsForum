require "test_helper"
require "ostruct"

class UserTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    Provider.find_or_create_by!(id: 1, name: "google")
  end

  test "internal user requires email, name, password" do
    user = User.new(provider_id: 3)
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
    assert_includes user.errors[:name], "can't be blank"
    assert_includes user.errors[:password], "can't be blank"
  end

  test "internal user is valid with email, name, password" do
    user = User.new(email: "test@example.com", name: "Test User",
                    password: "secret123", password_confirmation: "secret123",
                    provider_id: 3)
    assert user.valid?
  end

  test "email must be unique" do
    User.create!(email: "dup@example.com", name: "First", password: "secret123",
                 password_confirmation: "secret123", provider_id: 3)
    user2 = User.new(email: "dup@example.com", name: "Second", password: "secret123",
                     password_confirmation: "secret123", provider_id: 3)
    assert_not user2.valid?
  end

  test "oauth user does not need password" do
    user = User.new(email: "oauth@example.com", name: "OAuth User",
                    provider_id: 1, uid: "google-uid-123")
    assert user.valid?
  end

  test "from_omniauth finds or creates user" do
    auth = OpenStruct.new(
      uid: "google-123",
      info: OpenStruct.new(email: "g@example.com", name: "Google User", image: nil)
    )
    user = User.from_omniauth(auth, 1)
    assert_equal "g@example.com", user.email
    assert_equal 1, user.provider_id

    same_user = User.from_omniauth(auth, 1)
    assert_equal user.id, same_user.id
  end

  test "password shorter than 6 characters is invalid for internal user" do
    user = User.new(email: "short@example.com", name: "Short Pass",
                    password: "abc", password_confirmation: "abc",
                    provider_id: 3)
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 6 characters)"
  end

  test "password confirmation mismatch is invalid for internal user" do
    user = User.new(email: "mismatch@example.com", name: "Mismatch User",
                    password: "secret123", password_confirmation: "wrongpass",
                    provider_id: 3)
    assert_not user.valid?
    assert_includes user.errors[:password_confirmation], "doesn't match Password"
  end

  test "updating existing internal user with blank password does not change password" do
    user = User.create!(email: "existing@example.com", name: "Existing User",
                        password: "secret123", password_confirmation: "secret123",
                        provider_id: 3)
    user.password = ""
    # Rails 8 has_secure_password ignores empty-string assignment; the existing
    # password is retained and the record remains valid (no accidental blank hash).
    assert user.valid?
    assert user.authenticate("secret123"), "original password should still authenticate"
  end
end
