require "test_helper"

class FlagTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "flagger@example.com", name: "Flagger",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @user, body: "Reply body")
  end

  test "valid flag on a post" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    assert f.valid?, f.errors.full_messages.inspect
  end

  test "valid flag on a reply" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                 flaggable_id: @reply.id, reason: :harassment)
    assert f.valid?, f.errors.full_messages.inspect
  end

  test "invalid without content_type_id" do
    f = Flag.new(user: @user, flaggable_id: @post.id, reason: :spam)
    assert_not f.valid?
    assert f.errors[:content_type_id].any?
  end

  test "invalid with unknown content_type_id" do
    f = Flag.new(user: @user, content_type_id: 99,
                 flaggable_id: @post.id, reason: :spam)
    assert_not f.valid?
    assert f.errors[:content_type_id].any?
  end

  test "invalid without flaggable_id" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST, reason: :spam)
    assert_not f.valid?
    assert f.errors[:flaggable_id].any?
  end

  test "one flag per user per content item regardless of reason" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    dup = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST,
                   flaggable_id: @post.id, reason: :harassment)
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already flagged this content"
  end

  test "same user can flag a post and a reply independently" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                 flaggable_id: @reply.id, reason: :spam)
    assert f.valid?
  end

  test "reason enum has all four values" do
    assert_equal({ "spam" => 0, "harassment" => 1, "misinformation" => 2, "other" => 3 },
                 Flag.reasons)
  end

  test "flaggable returns the Post for a post flag" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    assert_equal @post, f.flaggable
  end

  test "flaggable returns the Reply for a reply flag" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                     flaggable_id: @reply.id, reason: :spam)
    assert_equal @reply, f.flaggable
  end

  test "flaggable returns nil when content has been hard-deleted" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    @reply.delete  # remove reply first to satisfy FK constraint
    @post.delete   # bypass callbacks, remove the row directly
    assert_nil f.reload.flaggable
  end

  test "flaggable returns the soft-deleted record when content has been soft-deleted" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    @post.update_column(:removed_at, Time.current)
    assert_equal @post, f.reload.flaggable
  end

  test "pending scope returns unresolved flags" do
    f1 = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                      flaggable_id: @post.id, reason: :spam)
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    f2 = Flag.create!(user: other, content_type_id: ContentType::CONTENT_POST,
                      flaggable_id: @post.id, reason: :harassment,
                      resolved_at: Time.current, resolved_by: other)
    assert_includes Flag.pending, f1
    assert_not_includes Flag.pending, f2
  end

  test "resolved scope returns resolved flags" do
    resolver = User.create!(email: "r@example.com", name: "R",
                             password: "pass123", password_confirmation: "pass123",
                             provider_id: 3)
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam,
                     resolved_at: Time.current, resolved_by: resolver)
    assert_includes Flag.resolved, f
    assert_not_includes Flag.pending, f
  end
end
