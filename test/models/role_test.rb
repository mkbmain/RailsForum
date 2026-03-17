require "test_helper"

class RoleTest < ActiveSupport::TestCase
  test "constants are defined" do
    assert_equal "creator",   Role::CREATOR
    assert_equal "sub_admin", Role::SUB_ADMIN
    assert_equal "admin",     Role::ADMIN
  end

  test "invalid without name" do
    role = Role.new
    assert_not role.valid?
    assert_includes role.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    existing = Role.find_by!(name: "creator")
    duplicate = Role.new(name: existing.name)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "valid with unique name" do
    role = Role.new(name: "custom_role")
    assert role.valid?
  end
end
