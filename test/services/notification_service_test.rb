require "test_helper"

class NotificationServiceTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @post_owner = User.create!(email: "owner@example.com", name: "owner",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @replier    = User.create!(email: "replier@example.com", name: "replier",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @participant = User.create!(email: "part@example.com", name: "participant",
                                password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @post_owner, title: "My Post", body: "content")
    # participant has previously replied
    Reply.create!(post: @post, user: @participant, body: "earlier reply")
    @reply = Reply.create!(post: @post, user: @replier, body: "new reply")
  end

  # --- reply_created ---

  test "notifies post owner with reply_to_post" do
    assert_difference "Notification.where(event_type: :reply_to_post).count", 1 do
      NotificationService.reply_created(@reply, current_user: @replier)
    end
    n = Notification.find_by(user: @post_owner, event_type: :reply_to_post)
    assert_not_nil n
    assert_equal @replier, n.actor
    assert_equal @reply, n.notifiable
  end

  test "does not notify post owner with reply_in_thread (only reply_to_post)" do
    NotificationService.reply_created(@reply, current_user: @replier)
    assert_nil Notification.find_by(user: @post_owner, event_type: :reply_in_thread)
  end

  test "notifies thread participant with reply_in_thread" do
    assert_difference "Notification.where(event_type: :reply_in_thread).count", 1 do
      NotificationService.reply_created(@reply, current_user: @replier)
    end
    n = Notification.find_by(user: @participant, event_type: :reply_in_thread)
    assert_not_nil n
  end

  test "does not notify actor about their own reply" do
    NotificationService.reply_created(@reply, current_user: @replier)
    assert_nil Notification.find_by(user: @replier)
  end

  test "does not send reply_in_thread if already notified within 24 hours" do
    # Pre-create a recent notification for the participant on this post
    Notification.create!(
      user: @participant, actor: @replier,
      notifiable: @post, event_type: :reply_in_thread,
      created_at: 1.hour.ago
    )
    assert_no_difference "Notification.where(event_type: :reply_in_thread, user: @participant).count" do
      reply2 = Reply.create!(post: @post, user: @replier, body: "another reply")
      NotificationService.reply_created(reply2, current_user: @replier)
    end
  end

  test "notifies mentioned user" do
    new_user = User.create!(email: "new@example.com", name: "newbie",
                            password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_mention = Reply.create!(post: @post, user: @replier, body: "hey @newbie come look")
    assert_difference "Notification.where(event_type: :mention).count", 1 do
      NotificationService.reply_created(reply_with_mention, current_user: @replier)
    end
    n = Notification.find_by(user: new_user, event_type: :mention)
    assert_not_nil n
  end

  test "does not double-notify: mention does not re-notify a user already notified" do
    reply_mentioning_owner = Reply.create!(post: @post, user: @replier,
                                           body: "hey @#{@post_owner.name} nice post")
    before = Notification.where(user: @post_owner).count
    NotificationService.reply_created(reply_mentioning_owner, current_user: @replier)
    after = Notification.where(user: @post_owner).count
    # only one notification created (reply_to_post), not two (mention is skipped)
    assert_equal 1, after - before
    assert_not_nil Notification.find_by(user: @post_owner, event_type: :reply_to_post)
    assert_nil Notification.find_by(user: @post_owner, event_type: :mention)
  end

  test "does not notify for unknown @mention" do
    reply = Reply.create!(post: @post, user: @replier, body: "@nobody_exists here")
    assert_no_difference "Notification.where(event_type: :mention).count" do
      NotificationService.reply_created(reply, current_user: @replier)
    end
  end

  # --- content_removed ---

  test "notifies content owner on moderation" do
    assert_difference "Notification.where(event_type: :moderation).count", 1 do
      NotificationService.content_removed(@post, removed_by: @replier)
    end
    n = Notification.find_by(user: @post_owner, event_type: :moderation)
    assert_equal @replier, n.actor
    assert_equal @post, n.notifiable
  end

  test "does not notify if moderator removes own content" do
    assert_no_difference "Notification.count" do
      NotificationService.content_removed(@post, removed_by: @post_owner)
    end
  end

  test "multi-word mention @Jane_Doe notifies user named 'Jane Doe'" do
    jane = User.create!(email: "jane@example.com", name: "Jane Doe",
                        password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_mention = Reply.create!(post: @post, user: @replier, body: "hey @Jane_Doe nice work")
    assert_difference "Notification.where(event_type: :mention).count", 1 do
      NotificationService.reply_created(reply_with_mention, current_user: @replier)
    end
    assert_not_nil Notification.find_by(user: jane, event_type: :mention)
  end

  test "single-word mention still resolves correctly after gsub change" do
    new_user = User.create!(email: "solo@example.com", name: "soloist",
                            password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_mention = Reply.create!(post: @post, user: @replier, body: "good job @soloist")
    assert_difference "Notification.where(event_type: :mention).count", 1 do
      NotificationService.reply_created(reply_with_mention, current_user: @replier)
    end
    assert_not_nil Notification.find_by(user: new_user, event_type: :mention)
  end

  test "mentions work for users with apostrophes in names" do
    provider = Provider.find_or_create_by!(id: 3, name: "internal")
    obrien = User.create!(email: "obrien@example.com", name: "O'Brien",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: provider.id)
    mentioning_reply = Reply.create!(post: @post, user: @replier, body: "Hey @OBrien check this out")
    assert_difference "Notification.where(event_type: :mention, user: obrien).count", 1 do
      NotificationService.reply_created(mentioning_reply, current_user: @replier)
    end
  end
end
