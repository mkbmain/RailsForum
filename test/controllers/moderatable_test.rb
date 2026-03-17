require "test_helper"

# NOTE: can_moderate? controller behavior (hierarchy checks, require_moderator/require_admin)
# is tested in test/controllers/posts_controller_test.rb (Task 10).
# These tests verify the User role predicates that Moderatable depends on.
class ModeratableTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @creator = User.create!(email: "creator@example.com", name: "Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
  end

  test "creator user is not a moderator" do
    assert_not @creator.moderator?
  end

  test "sub_admin user is a moderator" do
    assert @sub_admin.moderator?
  end

  test "admin user is a moderator" do
    assert @admin.moderator?
  end
end
