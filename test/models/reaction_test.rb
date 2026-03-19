require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "reactor@example.com", name: "Reactor",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @user, body: "Reply")
  end

  test "valid with an allowed emoji on a post" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: "👍")
    assert r.valid?, r.errors.full_messages.inspect
  end

  test "valid with an allowed emoji on a reply" do
    r = Reaction.new(user: @user, reactionable: @reply, emoji: "❤️")
    assert r.valid?, r.errors.full_messages.inspect
  end

  test "invalid with an unknown emoji" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: "🦄")
    assert_not r.valid?
    assert_includes r.errors[:emoji], "is not included in the list"
  end

  test "invalid without emoji" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: nil)
    assert_not r.valid?
  end

  test "only one reaction per user per post" do
    Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    dup = Reaction.new(user: @user, reactionable: @post, emoji: "❤️")
    assert_not dup.valid?
  end

  test "only one reaction per user per reply" do
    Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    dup = Reaction.new(user: @user, reactionable: @reply, emoji: "❤️")
    assert_not dup.valid?
  end

  test "same user can react to both post and reply independently" do
    Reaction.create!(user: @user, reactionable: @post,  emoji: "👍")
    r = Reaction.new(user: @user, reactionable: @reply, emoji: "👍")
    assert r.valid?
  end

  test "ALLOWED_REACTIONS contains the four expected emoji" do
    assert_equal %w[👍 ❤️ 😂 😮], Reaction::ALLOWED_REACTIONS
  end
end
