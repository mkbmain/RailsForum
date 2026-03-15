require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "pt@example.com", name: "Post Tester",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
  end

  test "body at exactly 1000 characters is valid" do
    post = Post.new(user: @user, title: "Title", body: "a" * 1000)
    assert post.valid?, "Expected valid but got: #{post.errors.full_messages}"
  end

  test "body at 1001 characters is invalid" do
    post = Post.new(user: @user, title: "Title", body: "a" * 1001)
    assert_not post.valid?
    assert_includes post.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "body at 1 character is valid" do
    post = Post.new(user: @user, title: "Title", body: "a")
    assert post.valid?, "Expected valid but got: #{post.errors.full_messages}"
  end

  test "last_activity_at returns created_at when no replies" do
    post = Post.create!(user: @user, title: "No replies", body: "body")
    assert_equal post.created_at, post.last_activity_at
  end

  test "last_activity_at returns last_replied_at when set" do
    post = Post.create!(user: @user, title: "Has replies", body: "body")
    time = 1.hour.from_now
    post.update_column(:last_replied_at, time)
    assert_equal time.to_i, post.reload.last_activity_at.to_i
  end
end
