require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "valid with id and name" do
    cat = Category.new(id: 2, name: "Tech", position: 5)
    assert cat.valid?
  end

  test "invalid without name" do
    cat = Category.new(id: 2, position: 5)
    assert_not cat.valid?
    assert_includes cat.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    # 'other' fixture (id:1, name:'Other') is already loaded via fixtures :all
    dup = Category.new(id: 2, name: "Other", position: 5)
    assert_not dup.valid?
    assert_includes dup.errors.full_messages, "Name has already been taken"
  end

  test "name max 100 characters" do
    cat = Category.new(id: 2, name: "a" * 101, position: 5)
    assert_not cat.valid?
    assert_includes cat.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "has many posts association" do
    assert_respond_to Category.new, :posts
  end
end
