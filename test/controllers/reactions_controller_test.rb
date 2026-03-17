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
  end

  test "POST creates a reaction when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
  end

  test "POST rejects invalid emoji with 422" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, post: @post).emoji
  end

  test "POST requires login" do
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, post: @post, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reaction_path(@post, reaction)
    end
  end

  test "DELETE cannot destroy another user's reaction" do
    reaction = Reaction.create!(user: @other, post: @post, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  test "DELETE requires login" do
    reaction = Reaction.create!(user: @user, post: @post, emoji: "👍")
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
    reaction = Reaction.create!(user: @user, post: @post, emoji: "👍")
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end
end
