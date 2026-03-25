require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "nuser@example.com", name: "Nuser",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @actor = User.create!(email: "nactor@example.com", name: "NActor",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @actor, body: "reply")
    @notif = Notification.create!(user: @user, actor: @actor, notifiable: @reply,
                                  event_type: :reply_to_post)
  end

  test "GET /notifications requires login" do
    get notifications_path
    assert_redirected_to login_path
  end

  test "GET /notifications shows notifications for current user" do
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success
    assert_select "a", text: /NActor/
  end

  test "PATCH /notifications/:id/read marks one notification as read" do
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    assert_nil @notif.read_at
    patch read_notification_path(@notif)
    assert_redirected_to notifications_path
    assert_not_nil @notif.reload.read_at
  end

  test "PATCH /notifications/:id/read cannot mark another user's notification" do
    other = User.create!(email: "sneaky@example.com", name: "Sneaky",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    post login_path, params: { email: "sneaky@example.com", password: "pass123" }
    patch read_notification_path(@notif)
    assert_nil @notif.reload.read_at
  end

  test "PATCH /notifications/read_all marks all unread notifications as read" do
    notif2 = Notification.create!(user: @user, actor: @actor, notifiable: @reply,
                                   event_type: :mention)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    patch read_all_notifications_path
    assert_redirected_to notifications_path
    assert_not_nil @notif.reload.read_at
    assert_not_nil notif2.reload.read_at
  end

  test "GET /notifications reply notification links to post with reply anchor" do
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success
    assert_select "a[href=?]", post_path(@post, anchor: "reply-#{@reply.id}")
  end

  test "GET /notifications post notification links to post without anchor" do
    @notif.update_column(:notifiable_type, "Post")
    @notif.update_column(:notifiable_id,   @post.id)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success
    assert_select "a[href=?]", post_path(@post)
  end

  test "GET /notifications excludes orphaned notifications from display and unread count" do
    # Create a second reply and a notification pointing at it
    orphan_reply = Reply.create!(post: @post, user: @actor, body: "orphan reply")
    Notification.create!(user: @user, actor: @actor, notifiable: orphan_reply,
                          event_type: :reply_to_post)
    # Raw-delete the reply (bypasses callbacks so the notification becomes orphaned)
    Reply.where(id: orphan_reply.id).delete_all

    # @user now has 2 DB notifications: @notif (valid) and orphan_notif (notifiable missing)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success

    # Only the non-orphaned notification should be in @notifications
    assert_equal 1, assigns(:notifications).size
    # Unread count must match the visible set, not the raw DB count
    assert_equal 1, assigns(:unread_count)
  end
end
