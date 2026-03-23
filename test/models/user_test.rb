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

  test "has many user_bans" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user   = User.create!(email: "u@example.com", name: "U", password: "pass123",
                          password_confirmation: "pass123", provider_id: 3)
    reason = BanReason.create!(name: "Spam")
    ban    = UserBan.create!(user: user, ban_reason: reason, banned_until: 1.day.from_now,
                             banned_by: user)
    assert_includes user.user_bans, ban
  end

  test "new user is automatically assigned the creator role" do
    user = User.create!(email: "newrole@example.com", name: "New",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    assert user.creator?
  end

  test "creator? returns false when user has no creator role" do
    user = User.create!(email: "norole@example.com", name: "No Role",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    user.user_roles.destroy_all
    assert_not user.creator?
  end

  test "sub_admin? returns true when user has sub_admin role" do
    user = User.create!(email: "sa@example.com", name: "SA",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    user.roles << Role.find_by!(name: Role::SUB_ADMIN)
    assert user.sub_admin?
  end

  test "admin? returns true when user has admin role" do
    user = User.create!(email: "adm@example.com", name: "Admin",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    user.roles << Role.find_by!(name: Role::ADMIN)
    assert user.admin?
  end

  test "moderator? is true for sub_admin" do
    user = User.create!(email: "mod@example.com", name: "Mod",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    user.roles << Role.find_by!(name: Role::SUB_ADMIN)
    assert user.moderator?
  end

  test "moderator? is true for admin" do
    user = User.create!(email: "adm2@example.com", name: "Admin2",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    user.roles << Role.find_by!(name: Role::ADMIN)
    assert user.moderator?
  end

  test "moderator? is false for creator-only user" do
    user = User.create!(email: "creator@example.com", name: "Creator",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    assert_not user.moderator?
  end

  test "has_role? returns false for role user does not have" do
    user = User.create!(email: "norole2@example.com", name: "No SA",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    assert_not user.has_role?(Role::SUB_ADMIN)
  end

  test "underscore in name is replaced with space on save" do
    user = User.new(email: "under@example.com", name: "Jane_Doe",
                    password: "pass123", password_confirmation: "pass123",
                    provider_id: 3)
    user.valid?
    assert_equal "Jane Doe", user.name
  end

  test "name without underscore is unchanged on save" do
    user = User.new(email: "plain@example.com", name: "Jane Doe",
                    password: "pass123", password_confirmation: "pass123",
                    provider_id: 3)
    user.valid?
    assert_equal "Jane Doe", user.name
  end

  test "from_omniauth with underscore name saves with underscores replaced by spaces" do
    auth = OpenStruct.new(
      uid: "google-underscore",
      info: OpenStruct.new(email: "under2@example.com", name: "Jane_Doe", image: nil)
    )
    user = User.from_omniauth(auth, 1)
    assert_equal "Jane Doe", user.name
  end

  test "mention_handle converts spaces to underscores and lowercases" do
    user = User.new(name: "John Doe")
    assert_equal "john_doe", user.mention_handle
  end

  test "mention_handle strips apostrophes" do
    user = User.new(name: "O'Brien")
    assert_equal "obrien", user.mention_handle
  end

  test "mention_handle strips hyphens" do
    user = User.new(name: "Mary-Jane")
    assert_equal "maryjane", user.mention_handle
  end

  test "find_by_mention_handle finds user with special-char name" do
    provider = Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "obrien@example.com", name: "O'Brien",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: provider.id)
    assert_equal user, User.find_by_mention_handle("OBrien")
  end

  test "find_by_mention_handle still finds user with plain space name" do
    provider = Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "jdoe@example.com", name: "John Doe",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: provider.id)
    assert_equal user, User.find_by_mention_handle("John_Doe")
  end

  test "email is normalized to lowercase before save" do
    user = User.create!(email: "TEST@EXAMPLE.COM", name: "Tester",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: Provider.find_or_create_by!(id: 3, name: "internal").id)
    assert_equal "test@example.com", user.reload.email
  end

  test "email uniqueness is enforced case-insensitively at DB level" do
    provider = Provider.find_or_create_by!(id: 3, name: "internal")
    User.create!(email: "dupe@example.com", name: "First",
                 password: "pass123", password_confirmation: "pass123", provider_id: provider.id)
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.connection.execute(
        "INSERT INTO users (email, name, password_digest, provider_id, created_at, updated_at) " \
        "VALUES ('DUPE@EXAMPLE.COM', 'Second', 'x', #{provider.id}, NOW(), NOW())"
      )
    end
  end
end
