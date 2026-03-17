require "test_helper"

class UserRoleTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "ur@example.com", name: "UR",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @role = Role.find_by!(name: Role::SUB_ADMIN)
  end

  test "belongs to user and role" do
    ur = UserRole.create!(user: @user, role: @role)
    assert_equal @user, ur.user
    assert_equal @role, ur.role
  end

  test "duplicate (user, role) pair is rejected by DB" do
    UserRole.create!(user: @user, role: @role)
    assert_raises(ActiveRecord::RecordNotUnique) do
      UserRole.create!(user: @user, role: @role)
    end
  end

  test "created_at is set automatically" do
    ur = UserRole.create!(user: @user, role: @role)
    assert_not_nil ur.created_at
  end
end
