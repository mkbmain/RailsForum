require "test_helper"

class ReplyTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "rt@example.com", name: "Reply Tester",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post = Post.create!(user: @user, title: "A Post", body: "Post body")
  end

  test "body at exactly 1000 characters is valid" do
    reply = Reply.new(post: @post, user: @user, body: "a" * 1000)
    assert reply.valid?, "Expected valid but got: #{reply.errors.full_messages}"
  end

  test "body at 1001 characters is invalid" do
    reply = Reply.new(post: @post, user: @user, body: "a" * 1001)
    assert_not reply.valid?
    assert_includes reply.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "body at 1 character is valid" do
    reply = Reply.new(post: @post, user: @user, body: "a")
    assert reply.valid?, "Expected valid but got: #{reply.errors.full_messages}"
  end

  test "creating a reply sets post last_replied_at" do
    reply = Reply.create!(post: @post, user: @user, body: "first reply")
    assert_in_delta reply.created_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "destroying the only reply sets post last_replied_at to nil" do
    reply = Reply.create!(post: @post, user: @user, body: "only reply")
    reply.destroy
    assert_nil @post.reload.last_replied_at
  end

  test "destroying a non-last reply keeps last_replied_at as the remaining latest" do
    older = Reply.create!(post: @post, user: @user, body: "older", created_at: 2.hours.ago)
    newer = Reply.create!(post: @post, user: @user, body: "newer", created_at: 1.hour.ago)
    older.destroy
    assert_in_delta newer.created_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "removed? returns false when removed_at is nil" do
    reply = Reply.create!(post: @post, user: @user, body: "hello")
    assert_not reply.removed?
  end

  test "removed? returns true when removed_at is set" do
    reply = Reply.create!(post: @post, user: @user, body: "hello")
    reply.update_column(:removed_at, Time.current)
    assert reply.removed?
  end

  test "visible scope excludes removed replies" do
    reply = Reply.create!(post: @post, user: @user, body: "hello")
    reply.update_column(:removed_at, Time.current)
    assert_not_includes @post.replies.visible, reply
  end

  test "visible scope includes non-removed replies" do
    reply = Reply.create!(post: @post, user: @user, body: "hello")
    assert_includes @post.replies.visible, reply
  end

  test "edited? returns false for a new reply" do
    reply = Reply.create!(post: @post, user: @user, body: "fresh reply")
    assert_not reply.reload.edited?
  end

  test "edited? returns true after last_edited_at is updated" do
    reply = Reply.create!(post: @post, user: @user, body: "fresh reply")
    reply.update_column(:last_edited_at, reply.created_at + 1.second)
    assert reply.reload.edited?
  end

  test "destroying a reply destroys its associated notifications" do
    actor = User.create!(email: "actor2@example.com", name: "Actor",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    Notification.create!(user: @user, actor: actor, notifiable: reply, event_type: :reply_to_post)
    assert_difference "Notification.count", -1 do
      reply.destroy
    end
  end
end
