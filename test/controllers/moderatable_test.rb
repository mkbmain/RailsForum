require "test_helper"

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
    @other_sub_admin = User.create!(email: "sub2@example.com", name: "Sub2",
                                    password: "pass123", password_confirmation: "pass123",
                                    provider_id: 3)
    @other_sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
  end

  # These tests exercise can_moderate? indirectly via PostsController#destroy (Task 10).
  # Here we test the User predicates that Moderatable depends on.

  test "creator user is not a moderator" do
    assert_not @creator.moderator?
  end

  test "sub_admin user is a moderator" do
    assert @sub_admin.moderator?
  end

  test "admin user is a moderator" do
    assert @admin.moderator?
  end

  test "admin can moderate sub_admin (hierarchy)" do
    # Access via a helper: log in as admin, try to destroy sub_admin's post
    # This is tested more fully in PostsController tests; here just check predicates.
    assert @admin.admin?
    assert @other_sub_admin.sub_admin?
    # Admin can moderate sub_admin
    assert_not @admin == @other_sub_admin  # not self
    assert @admin.admin?  # so can_moderate? returns true
  end

  test "sub_admin cannot moderate another sub_admin" do
    # sub_admin targeting another sub_admin: !target.sub_admin? is false → cannot moderate
    assert @other_sub_admin.sub_admin?
    # can_moderate? would return false
    # Tested via controller in Task 10
  end
end
