require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User", password: "pass123",
                         password_confirmation: "pass123", provider_id: 3)
    @post = Post.create!(user: @user, title: "Hello World", body: "First post body")
  end

  test "GET /posts lists posts" do
    get posts_path
    assert_response :success
    assert_select "h2", text: /Hello World/
  end

  test "GET /posts/:id shows post" do
    get post_path(@post)
    assert_response :success
    assert_select "h1", text: /Hello World/
  end

  test "GET /posts/new requires login" do
    get new_post_path
    assert_redirected_to login_path
  end

  test "GET /posts/new renders form when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get new_post_path
    assert_response :success
  end

  test "POST /posts creates post when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Post.count", 1 do
      post posts_path, params: { post: { title: "New Post", body: "Some content here" } }
    end
    assert_redirected_to post_path(Post.last)
  end

  test "POST /posts denied when not logged in" do
    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Sneaky", body: "body" } }
    end
    assert_redirected_to login_path
  end

  test "POST /posts with invalid params re-renders new form" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "", body: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /posts assigns post to current user" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "My Post", body: "Some content" } }
    assert_equal @user.id, Post.last.user_id
  end

  test "GET /posts/:id shows reply form when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_response :success
    assert_select "form[action=?]", post_replies_path(@post)
  end

  # ---- category filter ----

  test "GET /posts filters by category" do
    tech = Category.create!(id: 2, name: "Tech")
    Post.create!(user: @user, title: "Tech Post", body: "body", category_id: 2)
    get posts_path, params: { category: 2 }
    assert_response :success
    assert_select "h2 a", text: /Tech Post/
    assert_select "h2 a", text: /Hello World/, count: 0
  end

  test "GET /posts with unknown category returns empty results" do
    get posts_path, params: { category: 999 }
    assert_response :success
    assert_select ".post-card", count: 0
  end

  test "GET /posts with no category shows all posts" do
    get posts_path
    assert_response :success
    assert_select "h2 a", text: /Hello World/
  end

  test "GET /posts paginates: take=1 page=1 returns 1 post" do
    Post.create!(user: @user, title: "Post 2", body: "body")
    get posts_path, params: { take: 1, page: 1 }
    assert_response :success
    assert_select ".post-card", count: 1
  end

  test "GET /posts clamps take to minimum 1" do
    # take=0 should be treated as take=1; only 1 post-card rendered even with 2 posts
    Post.create!(user: @user, title: "Post 2", body: "body")
    get posts_path, params: { take: 0 }
    assert_response :success
    assert_select ".post-card", count: 1
  end

  test "GET /posts clamps take to maximum 100" do
    # take=999 should be capped at 100; with only 1 post in setup, we see 1 card (not an error)
    get posts_path, params: { take: 999 }
    assert_response :success
    assert_select ".post-card", count: 1
  end

  # ---- new post form ----

  test "GET /posts/new renders category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get new_post_path
    assert_response :success
    assert_select "select[name=?]", "post[category_id]"
    assert_select "option", text: "Other"
  end

  # ---- create with category ----

  test "POST /posts with category_id saves correctly" do
    Category.create!(id: 2, name: "Tech")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "Tech Post", body: "Some content", category_id: 2 } }
    assert_equal 2, Post.last.category_id
  end

  test "POST /posts with invalid params re-renders with category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "", body: "" } }
    assert_response :unprocessable_entity
    assert_select "select[name=?]", "post[category_id]"
  end

  # ---- show includes category ----

  test "GET /posts/:id shows category badge" do
    get post_path(@post)
    assert_response :success
    assert_select ".category-badge"
  end

  test "nav shows New Post button when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    assert_select "nav a[href=?]", new_post_path
  end

  test "nav hides New Post button when logged out" do
    get posts_path
    assert_select "body > nav a[href=?]", new_post_path, count: 0
  end

  test "nav shows login and signup links when logged out" do
    get posts_path
    assert_select "nav a[href=?]", login_path
    assert_select "nav a[href=?]", signup_path
  end

  test "nav shows logout button when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    assert_select "nav form[action=?]", logout_path
  end

  test "GET /posts shows post body preview" do
    get posts_path
    assert_response :success
    assert_select ".post-card p", text: /First post body/
  end

  test "GET /posts shows reply count on post card" do
    reply_user = User.create!(email: "rc@example.com", name: "RC", password: "pass123",
                              password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: reply_user, body: "reply here")
    get posts_path
    assert_response :success
    assert_select ".post-card .reply-count", text: /1/
  end

  test "GET /posts shows empty state when no posts" do
    Post.delete_all
    get posts_path
    assert_response :success
    assert_select ".empty-state"
  end

  test "GET /posts does not show New Post button in the post feed when posts exist" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    # When posts exist the feed renders cards, not the empty-state New Post button.
    assert_select ".empty-state", count: 0
  end

  test "POST /posts with body over 1000 chars is rejected" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Long post", body: "a" * 1001 } }
    end
    assert_response :unprocessable_entity
  end

  # ---- rate limiting ----

  test "POST /posts is blocked when user hits rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }

    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Spam 6", body: "blocked" } }
    end
    assert_redirected_to new_post_path
    assert_match /posting too fast/, flash[:alert]
  end

  test "POST /posts flash includes the user limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    post posts_path, params: { post: { title: "X", body: "Y" } }
    assert_match /5/, flash[:alert]
  end

  test "POST /posts is allowed when under rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    3.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    assert_difference "Post.count", 1 do
      post posts_path, params: { post: { title: "5th Post", body: "allowed" } }
    end
  end

  test "GET /posts orders by last activity: post with recent reply appears first" do
    older_post = Post.create!(user: @user, title: "Older Post", body: "body",
                               created_at: 2.hours.ago)
    newer_reply_user = User.create!(email: "nr@example.com", name: "NR",
                                     password: "pass123", password_confirmation: "pass123",
                                     provider_id: 3)
    # Give the setup post (@post, created more recently) no replies.
    # Give older_post a very recent reply so it should sort first.
    Reply.create!(post: older_post, user: newer_reply_user, body: "recent reply")

    get posts_path
    assert_response :success

    titles = css_select(".post-card h2 a").map(&:text).map(&:strip)
    assert_equal "Older Post", titles.first,
      "Post with recent reply should appear first. Got: #{titles.inspect}"
  end

  test "GET /posts shows last reply time when post has a reply" do
    reply_user = User.create!(email: "rv@example.com", name: "RV",
                               password: "pass123", password_confirmation: "pass123",
                               provider_id: 3)
    # Create reply, then manually set last_replied_at to a known time
    reply = Reply.create!(post: @post, user: reply_user, body: "a reply")
    known_time = 3.hours.ago
    @post.update_column(:last_replied_at, known_time)

    get posts_path
    assert_response :success
    # time_ago_in_words(3.hours.ago) produces "about 3 hours"
    assert_select ".post-card span.text-xs", text: /about 3 hours ago/
  end

  test "GET /posts shows last reply time in reply count row" do
    reply_user = User.create!(email: "rl@example.com", name: "RL",
                               password: "pass123", password_confirmation: "pass123",
                               provider_id: 3)
    Reply.create!(post: @post, user: reply_user, body: "a reply")
    @post.update_column(:last_replied_at, 2.hours.ago)

    get posts_path
    assert_response :success
    assert_select ".reply-count", text: /last reply/
    assert_select ".reply-count", text: /about 2 hours ago/
  end

  test "GET /posts does not show last reply text when post has no replies" do
    get posts_path
    assert_response :success
    assert_select ".reply-count", text: /last reply/, count: 0
  end

  # ---- ban enforcement ----

  test "POST /posts is blocked when user is banned" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Sneaky", body: "blocked" } }
    end
    assert_redirected_to new_post_path
    assert_match /banned until/, flash[:alert]
  end

  test "POST /posts ban flash includes the expiry date" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    expiry = 5.days.from_now
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: expiry,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "X", body: "Y" } }
    assert_match expiry.strftime("%B %-d, %Y"), flash[:alert]
  end

  test "POST /posts is allowed when ban is expired" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_from: 2.days.ago, banned_until: 1.second.ago,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_difference "Post.count", 1 do
      post posts_path, params: { post: { title: "Allowed", body: "some content" } }
    end
  end

  test "GET /posts/new is accessible when user is banned" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get new_post_path
    assert_response :success
  end
end
