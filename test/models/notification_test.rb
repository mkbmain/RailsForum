require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "notif@example.com",  name: "Notif User",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @actor = User.create!(email: "actor@example.com", name: "Actor",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @actor, body: "A reply")
  end

  test "valid notification" do
    n = Notification.new(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert n.valid?, n.errors.full_messages.inspect
  end

  test "requires user" do
    n = Notification.new(actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "requires actor" do
    n = Notification.new(user: @user, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "requires notifiable" do
    n = Notification.new(user: @user, actor: @actor, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "read? returns false when read_at is nil" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.read?
  end

  test "read? returns true when read_at is set" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    n.update_column(:read_at, Time.current)
    assert n.read?
  end

  test "all event_type values are accessible" do
    %i[reply_to_post reply_in_thread mention moderation].each do |type|
      n = Notification.new(user: @user, actor: @actor, notifiable: @reply, event_type: type)
      assert n.valid?, "Expected #{type} to be valid: #{n.errors.full_messages}"
    end
  end

  test "unread scope returns only notifications with nil read_at" do
    unread = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    read   = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :mention,
                                    read_at: Time.current)
    scoped = Notification.where(id: [ unread.id, read.id ])
    assert_includes scoped.unread, unread
    assert_not_includes scoped.unread, read
  end

  test "read scope returns only notifications with read_at set" do
    unread = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    read   = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :mention,
                                    read_at: Time.current)
    scoped = Notification.where(id: [ unread.id, read.id ])
    assert_includes scoped.read, read
    assert_not_includes scoped.read, unread
  end

  test "mark_as_read! sets read_at" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_nil n.read_at
    n.mark_as_read!
    assert_not_nil n.reload.read_at
  end

  test "mark_as_read! is idempotent — does not update read_at if already read" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    n.mark_as_read!
    original_read_at = n.reload.read_at
    n.mark_as_read!
    assert_equal original_read_at, n.reload.read_at
  end

  test "target_post returns the post when notifiable is a Post" do
    post_notif = Notification.create!(user: @user, actor: @actor, notifiable: @post, event_type: :moderation)
    assert_equal @post, post_notif.target_post
  end

  test "target_post returns parent post when notifiable is a Reply" do
    reply_notif = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_equal @post, reply_notif.target_post
  end
end
