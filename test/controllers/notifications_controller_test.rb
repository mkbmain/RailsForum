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

  test "PATCH /notifications/read_group marks specified notifications as read" do
    reply2 = Reply.create!(post: @post, user: @actor, body: "another reply")
    notif2 = Notification.create!(user: @user, actor: @actor, notifiable: reply2,
                                   event_type: :reply_in_thread)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    patch read_group_notifications_path, params: { ids: [ @notif.id, notif2.id ] }
    assert_redirected_to notifications_path
    assert_not_nil @notif.reload.read_at
    assert_not_nil notif2.reload.read_at
  end

  test "PATCH /notifications/read_group cannot mark another user's notifications" do
    other_notif = Notification.create!(
      user:       @actor,
      actor:      @user,
      notifiable: @reply,
      event_type: :reply_to_post
    )
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    patch read_group_notifications_path, params: { ids: [ other_notif.id ] }
    assert_nil other_notif.reload.read_at
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

  test "reply_in_thread notifications for the same post are grouped into one display item" do
    reply2 = Reply.create!(post: @post, user: @actor, body: "second reply")
    reply3 = Reply.create!(post: @post, user: @actor, body: "third reply")
    Notification.create!(user: @user, actor: @actor, notifiable: reply2, event_type: :reply_in_thread)
    Notification.create!(user: @user, actor: @actor, notifiable: reply3, event_type: :reply_in_thread)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success
    groups = assigns(:notification_groups)
    thread_groups = groups.select { |g| g[:type] == :group }
    assert_equal 1, thread_groups.size, "Two reply_in_thread for the same post should collapse into one group"
    assert_equal 2, thread_groups.first[:ids].size
  end

  test "GET /notifications excludes orphaned notifications from display and unread count" do
    orphan_reply = Reply.create!(post: @post, user: @actor, body: "orphan reply")
    Notification.create!(user: @user, actor: @actor, notifiable: orphan_reply,
                          event_type: :reply_to_post)
    Reply.where(id: orphan_reply.id).delete_all

    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success

    # Only the non-orphaned notification should appear (as a single-item group)
    assert_equal 1, assigns(:notification_groups).size
    assert_equal 1, assigns(:unread_count)
  end
end
