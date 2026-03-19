require "test_helper"

class ReactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "u@example.com", name: "User",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @other = User.create!(email: "other@example.com", name: "Other",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @other, body: "A reply")
  end

  # --- Post reactions (existing behaviour preserved) ---

  test "POST creates a reaction on a post when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
  end

  test "POST rejects invalid emoji with 422 on a post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts on a post — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, reactionable: @post).emoji
  end

  test "POST on a post requires login" do
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own post reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reaction_path(@post, reaction)
    end
  end

  test "DELETE cannot destroy another user's post reaction" do
    reaction = Reaction.create!(user: @other, reactionable: @post, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  test "DELETE on a post requires login" do
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_redirected_to login_path
  end

  test "POST on hidden post returns 404" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "DELETE on hidden post returns 404" do
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  # --- Reply reactions (new) ---

  test "POST creates a reaction on a reply when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    end
    assert_equal "Reply", Reaction.last.reactionable_type
    assert_equal @reply.id, Reaction.last.reactionable_id
  end

  test "POST rejects invalid emoji on a reply with 422" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts on a reply — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, reactionable: @reply).emoji
  end

  test "POST on a reply requires login" do
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own reply reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
  end

  test "DELETE cannot destroy another user's reply reaction" do
    reaction = Reaction.create!(user: @other, reactionable: @reply, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
    assert_response :not_found
  end

  test "POST on a reply of a hidden post returns 404" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "POST on a hidden reply returns 404" do
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "DELETE on a hidden reply returns 404" do
    reaction = Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
    assert_response :not_found
  end
end
