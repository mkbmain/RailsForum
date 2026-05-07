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

  test "reply_in_thread notification points to the reply, not the post" do
    NotificationService.reply_created(@reply, current_user: @replier)
    n = Notification.find_by(user: @participant, event_type: :reply_in_thread)
    assert_not_nil n
    assert_equal "Reply", n.notifiable_type,
      "reply_in_thread notifiable must be a Reply so the view can anchor to it"
    assert_equal @reply.id, n.notifiable_id
  end

  test "reply_in_thread dedup still works after notifiable change" do
    NotificationService.reply_created(@reply, current_user: @replier)
    assert_equal 1, Notification.where(user: @participant, event_type: :reply_in_thread).count

    reply2 = Reply.create!(post: @post, user: @replier, body: "follow-up reply")
    assert_no_difference "Notification.where(user: @participant, event_type: :reply_in_thread).count" do
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

  test "does not notify user mentioned inside a fenced code block" do
    User.create!(email: "codementor@example.com", name: "codementor",
                 password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_code = Reply.create!(
      post: @post, user: @replier,
      body: "here is an example:\n```\n@codementor does this\n```\nnot a real mention"
    )
    assert_no_difference "Notification.where(event_type: :mention).count" do
      NotificationService.reply_created(reply_with_code, current_user: @replier)
    end
  end

  test "does not notify user mentioned inside an inline code span" do
    User.create!(email: "inlinementor@example.com", name: "inlinementor",
                 password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_inline = Reply.create!(
      post: @post, user: @replier,
      body: "run `@inlinementor` in your shell"
    )
    assert_no_difference "Notification.where(event_type: :mention).count" do
      NotificationService.reply_created(reply_with_inline, current_user: @replier)
    end
  end

  test "rolls back all notifications when any creation fails" do
    # Override Notification.create! to succeed on call 1, raise on call 2
    original_create = Notification.method(:create!)
    call_count = 0

    Notification.define_singleton_method(:create!) do |*args, **kwargs|
      call_count += 1
      raise ActiveRecord::RecordInvalid.new(Notification.new) if call_count == 2
      original_create.call(*args, **kwargs)
    end

    before_count = Notification.count
    assert_raises(ActiveRecord::RecordInvalid) do
      NotificationService.reply_created(@reply, current_user: @replier)
    end
    assert_equal before_count, Notification.count, "transaction must roll back all notifications"
  ensure
    Notification.define_singleton_method(:create!, original_create)
  end

  test "still notifies user mentioned outside code blocks" do
    mentioned = User.create!(email: "realmentor@example.com", name: "realmentor",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_mixed = Reply.create!(
      post: @post, user: @replier,
      body: "hey @realmentor, see this:\n```\n@other_person\n```"
    )
    assert_difference "Notification.where(event_type: :mention).count", 1 do
      NotificationService.reply_created(reply_mixed, current_user: @replier)
    end
    n = Notification.find_by(user: mentioned, event_type: :mention)
    assert_not_nil n
  end

  test "does not notify user mentioned inside a tilde-fenced code block" do
    User.create!(email: "tildementor@example.com", name: "tildementor",
                 password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: @replier,
                          body: "~~~\n@tildementor\n~~~")
    assert_no_difference "Notification.where(event_type: :mention).count" do
      NotificationService.reply_created(reply, current_user: @replier)
    end
  end
end
