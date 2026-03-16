require "test_helper"

class RepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User", password: "pass123",
                         password_confirmation: "pass123", provider_id: 3)
    @post = Post.create!(user: @user, title: "A Post", body: "Post body")
  end

  test "POST /posts/:post_id/replies requires login" do
    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "Hi there" } }
    end
    assert_redirected_to login_path
  end

  test "POST /posts/:post_id/replies creates reply when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reply.count", 1 do
      post post_replies_path(@post), params: { reply: { body: "Great post!" } }
    end
    assert_redirected_to post_path(@post)
  end

  test "POST /posts/:post_id/replies with blank body re-renders post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "DELETE /posts/:post_id/replies/:id requires login" do
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    assert_no_difference "Reply.count" do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to login_path
  end

  test "DELETE /posts/:post_id/replies/:id succeeds when owner" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  test "DELETE /posts/:post_id/replies/:id is forbidden for non-owner" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    other_user = User.create!(email: "other@example.com", name: "Other",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other_user, body: "Other reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  test "POST /posts/:post_id/replies with body over 1000 chars is rejected" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "a" * 1001 } }
    end
    assert_response :unprocessable_entity
  end

  # ---- rate limiting ----

  test "POST /posts/:post_id/replies is blocked when user hits rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }

    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "blocked reply" } }
    end
    assert_redirected_to post_path(@post)
    assert_match /posting too fast/, flash[:alert]
  end

  test "POST /posts/:post_id/replies rate limit redirects back to the post, not new_post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    post post_replies_path(@post), params: { reply: { body: "blocked" } }
    assert_redirected_to post_path(@post)
  end

  test "DELETE /posts/:post_id/replies/:id is unaffected by rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  # ---- ban enforcement ----

  test "POST /posts/:post_id/replies is blocked when user is banned" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "blocked reply" } }
    end
    assert_redirected_to post_path(@post)
    assert_match /banned until/, flash[:alert]
  end

  test "POST /posts/:post_id/replies ban redirects back to the post, not root" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_replies_path(@post), params: { reply: { body: "blocked" } }
    assert_redirected_to post_path(@post)
  end

  test "POST /posts/:post_id/replies is allowed when ban is expired" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_from: 2.days.ago, banned_until: 1.second.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_difference "Reply.count", 1 do
      post post_replies_path(@post), params: { reply: { body: "allowed reply" } }
    end
  end

  test "DELETE /posts/:post_id/replies/:id is unaffected by ban" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")

    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end
end
