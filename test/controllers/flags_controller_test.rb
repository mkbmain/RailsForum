require "test_helper"

class FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "u@example.com", name: "User",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @other = User.create!(email: "other@example.com", name: "Other",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @other, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @other, body: "Reply")
  end

  # --- Auth ---

  test "requires login to flag a post" do
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    assert_redirected_to login_path
  end

  test "requires login to flag a reply" do
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_redirected_to login_path
  end

  # --- Create on post ---

  test "creates a flag on a post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    f = Flag.last
    assert_equal @user,                    f.user
    assert_equal ContentType::CONTENT_POST, f.content_type_id
    assert_equal @post.id,                 f.flaggable_id
    assert_equal "spam",                   f.reason
    assert_redirected_to post_path(@post)
    assert_equal "Content reported.", flash[:notice]
  end

  test "duplicate flag on a post redirects with alert" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "other" } }
    end
    assert_includes flash[:alert], "already flagged"
  end

  test "cannot flag a soft-deleted post" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  # --- Create on reply ---

  test "creates a flag on a reply" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "harassment" } }
    end
    f = Flag.last
    assert_equal @user,                     f.user
    assert_equal ContentType::CONTENT_REPLY, f.content_type_id
    assert_equal @reply.id,                 f.flaggable_id
    assert_equal "harassment",              f.reason
  end

  test "reply flag is scoped to parent post — wrong post redirects with alert" do
    other_post = Post.create!(user: @other, title: "Other", body: "Body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(other_post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  test "cannot flag a soft-deleted reply" do
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  # --- User can flag their own content ---

  test "user can flag their own post" do
    own_post = Post.create!(user: @user, title: "Mine", body: "Body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_flags_path(own_post), params: { flag: { reason: "spam" } }
    end
  end
end
