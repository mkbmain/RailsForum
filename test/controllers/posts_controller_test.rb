require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User", password: "pass123",
                         password_confirmation: "pass123", provider_id: 3)
    @post = Post.create!(user: @user, title: "Hello World", body: "First post body")
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                               password: "pass123", password_confirmation: "pass123",
                               provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
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
    tech = Category.create!(id: 2, name: "Tech", position: 1)
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
    Category.create!(id: 2, name: "Tech", position: 1)
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
    assert_match ban_reason.name, flash[:alert]
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

  # ---- moderation: post removal ----

  test "DELETE /posts/:id requires login" do
    delete post_path(@post)
    assert_redirected_to login_path
  end

  test "DELETE /posts/:id is forbidden for creator-only user" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    delete post_path(@post)
    assert_redirected_to root_path
    assert_match /Not authorized/, flash[:alert]
  end

  test "DELETE /posts/:id soft-deletes post as sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    delete post_path(@post)
    assert_redirected_to post_path(@post)
    assert @post.reload.removed?
    assert_equal @sub_admin.id, @post.reload.removed_by_id
  end

  test "DELETE /posts/:id soft-deletes post as admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    delete post_path(@post)
    assert_redirected_to post_path(@post)
    assert @post.reload.removed?
  end

  test "DELETE /posts/:id is forbidden when sub_admin targets another sub_admin's post" do
    other_sub = User.create!(email: "sub2@example.com", name: "Sub2",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    other_sub.roles << Role.find_by!(name: Role::SUB_ADMIN)
    their_post = Post.create!(user: other_sub, title: "Sub post", body: "body")
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    delete post_path(their_post)
    assert_not their_post.reload.removed?
    assert_match /Not authorized/, flash[:alert]
  end

  test "DELETE /posts/:id is forbidden when moderator targets their own post" do
    own_post = Post.create!(user: @sub_admin, title: "Own post", body: "body")
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    delete post_path(own_post)
    assert_not own_post.reload.removed?
    assert_match /Not authorized/, flash[:alert]
  end

  test "GET /posts index excludes removed posts" do
    @post.update_column(:removed_at, Time.current)
    get posts_path
    assert_select ".post-card", count: 0
  end

  # ---- tombstone view ----

  test "GET /posts/:id shows tombstone body for removed post" do
    @post.update_column(:removed_at, Time.current)
    @post.update_column(:removed_by_id, @sub_admin.id)
    get post_path(@post)
    assert_response :success
    assert_select "div", text: /\[removed by moderator\]/
    assert_select "div", text: /First post body/, count: 0
  end

  test "GET /posts/:id shows audit info to moderator on removed post" do
    @post.update_column(:removed_at, Time.current)
    @post.update_column(:removed_by_id, @sub_admin.id)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get post_path(@post)
    assert_response :success
    assert_select "p", text: /Removed by Sub/
  end

  test "GET /posts/:id does not show audit info to non-moderator on removed post" do
    @post.update_column(:removed_at, Time.current)
    @post.update_column(:removed_by_id, @sub_admin.id)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_response :success
    assert_select "p", text: /Removed by/, count: 0
  end

  # ---- edit / update ----

  test "GET /posts/:id/edit requires login" do
    get edit_post_path(@post)
    assert_redirected_to login_path
  end

  test "GET /posts/:id/edit renders form when owner and within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(@post)
    assert_response :success
    assert_select "form[action=?]", post_path(@post)
    assert_select "select[name=?]", "post[category_id]"
  end

  test "GET /posts/:id/edit is forbidden for non-owner" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(other_post)
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "GET /posts/:id/edit is blocked after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(@post)
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  test "PATCH /posts/:id updates post and sets last_edited_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    original_last_edited_at = @post.last_edited_at
    travel_to 1.minute.from_now do
      patch post_path(@post), params: { post: { title: "Updated Title", body: "Updated body" } }
    end
    assert_redirected_to post_path(@post)
    @post.reload
    assert_equal "Updated Title", @post.title
    assert @post.last_edited_at > original_last_edited_at
  end

  test "PATCH /posts/:id does not change last_replied_at" do
    @post.update_column(:last_replied_at, 1.hour.ago)
    original_last_replied_at = @post.reload.last_replied_at
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "Edited", body: "Edited body" } }
    assert_in_delta original_last_replied_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "PATCH /posts/:id is forbidden for non-owner" do
    other = User.create!(email: "other2@example.com", name: "Other2",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(other_post), params: { post: { title: "Hacked", body: "hacked" } }
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "GET /posts/:id/edit by non-owner when edit window also expired redirects with not-authorized message" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Other Post", body: "body")
    other_post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(other_post)
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "PATCH /posts/:id by non-owner when edit window also expired redirects with not-authorized message" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Other Post", body: "body")
    other_post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(other_post), params: { post: { title: "Hacked", body: "hacked" } }
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "PATCH /posts/:id with invalid params re-renders edit with category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "", body: "" } }
    assert_response :unprocessable_entity
    assert_select "select[name=?]", "post[category_id]"
  end

  test "PATCH /posts/:id is blocked after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "Late Edit", body: "too late" } }
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  # ---- show view: edit link and last-edited display ----

  test "GET /posts/:id shows edit link for post owner within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post)
  end

  test "GET /posts/:id hides edit link for non-owner" do
    other = User.create!(email: "other3@example.com", name: "Other3",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(other_post)
    assert_select "a[href=?]", edit_post_path(other_post), count: 0
  end

  test "GET /posts/:id hides edit link after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post), count: 0
  end

  test "GET /posts/:id hides edit link when not logged in" do
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post), count: 0
  end

  test "GET /posts/:id shows last edited at when post has been edited" do
    @post.update_column(:last_edited_at, @post.created_at + 5.minutes)
    get post_path(@post)
    assert_select ".last-edited-at"
  end

  test "GET /posts/:id does not show last edited at on fresh post" do
    get post_path(@post)
    assert_select ".last-edited-at", count: 0
  end

  test "GET /posts/:id shows last edited at on reply that has been edited" do
    reply_user = User.create!(email: "rv2@example.com", name: "RV2",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: reply_user, body: "a reply")
    reply.update_column(:last_edited_at, reply.created_at + 5.minutes)
    get post_path(@post)
    assert_select ".last-edited-at"
  end

  test "GET /posts/:id shows edit link for reply owner within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply)
  end

  test "GET /posts/:id hides edit link for reply non-owner" do
    other = User.create!(email: "other4@example.com", name: "Other4",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply), count: 0
  end

  test "GET /posts/:id hides edit link for reply after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply), count: 0
  end

  test "GET /posts/:id Next link is not shown when exactly @take replies exist" do
    reply_user = User.create!(email: "rp1@example.com", name: "RP1",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    20.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
    get post_path(@post), params: { take: 20 }
    assert_response :success
    assert_select "a", text: /Next/, count: 0
  end

  test "GET /posts/:id Next link is shown when more replies exist" do
    reply_user = User.create!(email: "rp2@example.com", name: "RP2",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    21.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
    get post_path(@post), params: { take: 20 }
    assert_response :success
    assert_select "a", text: /Next/
  end

  test "GET /posts/:id only @take replies are rendered even when probe record is loaded" do
    reply_user = User.create!(email: "rp3@example.com", name: "RP3",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    21.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
    get post_path(@post), params: { take: 20 }
    assert_response :success
    assert_select ".bg-gray-50.border-gray-200", count: 20
  end

  test "GET /posts/:id reply count excludes removed replies" do
    reply_user = User.create!(email: "rc2@example.com", name: "RC2",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: reply_user, body: "visible reply")
    removed = Reply.create!(post: @post, user: reply_user, body: "removed reply")
    removed.update_columns(removed_at: Time.current, removed_by_id: @sub_admin.id)
    get post_path(@post)
    assert_response :success
    # Only 1 visible reply; the removed one must not be counted
    assert_select "h2", text: /Replies \(1\)/
  end

  test "GET /posts/:id reply cards have anchor ids" do
    reply_user = User.create!(email: "anc@example.com", name: "Anc",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: reply_user, body: "anchor me")
    get post_path(@post)
    assert_response :success
    assert_select "div#reply-#{reply.id}"
  end

  # ---- posts index probe pattern ----

  test "GET /posts does not show Older link when exactly take posts exist" do
    # setup creates 1 post; create take-1 more to reach exactly take=10 total
    9.times { |i| Post.create!(user: @user, title: "Extra #{i}", body: "body") }
    get posts_path, params: { take: 10 }
    assert_response :success
    assert_select "a", text: /Older/, count: 0
  end

  test "GET /posts shows Older link when more than take posts exist" do
    # setup creates 1 post; create take more to reach take+1=11 total
    10.times { |i| Post.create!(user: @user, title: "Extra #{i}", body: "body") }
    get posts_path, params: { take: 10 }
    assert_response :success
    assert_select "a", text: /Older/
  end

  # ---- Restore ----

  test "PATCH restore as moderator clears removed_at and removed_by" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_path(@post)
    @post.reload
    assert_nil @post.removed_at
    assert_nil @post.removed_by
    assert_redirected_to post_path(@post)
    assert_equal "Post restored.", flash[:notice]
  end

  test "PATCH restore as non-moderator is rejected" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch restore_post_path(@post)
    @post.reload
    assert_not_nil @post.removed_at
    assert_redirected_to root_path
  end

  test "PATCH restore requires login" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    patch restore_post_path(@post)
    @post.reload
    assert_not_nil @post.removed_at
    assert_redirected_to login_path
  end

  # ---- @mention_users ----

  test "show sets @mention_users to post author and visible repliers, deduplicated" do
    replier_a = User.create!(email: "ra@example.com", name: "Replier A",
                              password: "pass123", password_confirmation: "pass123", provider_id: 3)
    replier_b = User.create!(email: "rb@example.com", name: "Replier B",
                              password: "pass123", password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: replier_a, body: "reply one")
    Reply.create!(post: @post, user: replier_b, body: "reply two")
    # replier_a replies twice — should appear only once
    Reply.create!(post: @post, user: replier_a, body: "reply three")

    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)

    assert_response :success
    mention_users = assigns(:mention_users)
    assert_not_nil mention_users
    assert_includes mention_users, @user       # post author
    assert_includes mention_users, replier_a
    assert_includes mention_users, replier_b
    assert_equal mention_users.map(&:id).uniq.length, mention_users.length
  end

  test "show excludes removed replies from @mention_users" do
    replier = User.create!(email: "gone@example.com", name: "Gone User",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: replier, body: "about to be removed",
                  removed_at: Time.current, removed_by: @admin)

    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)

    assert_not_includes assigns(:mention_users), replier
  end

  test "show sets @mention_users to empty array for logged-out requests" do
    get post_path(@post)
    assert_equal [], assigns(:mention_users)
  end

  test "reply form renders mention autocomplete data attribute with correct JSON" do
    replier = User.create!(email: "rj@example.com", name: "Reply Jones",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: replier, body: "a reply")

    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)

    assert_response :success
    assert_select "[data-controller~='mention-autocomplete']"
    assert_select "[data-mention-autocomplete-users-value]" do |elements|
      json = JSON.parse(elements.first["data-mention-autocomplete-users-value"])
      tokens = json.map { |e| e["token"] }
      displays = json.map { |e| e["display"] }
      assert_includes tokens, "reply_jones"
      assert_includes displays, "Reply Jones"
      assert_includes tokens, "user"
      assert_includes displays, "User"
    end
  end

  test "GET /posts/:id/edit for removed post owned by user redirects" do
    @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(@post)
    assert_redirected_to post_path(@post)
    assert_equal "This content has been removed and can no longer be edited.", flash[:alert]
  end

  test "PATCH /posts/:id for removed post owned by user does not update" do
    @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "Restore attempt" } }
    assert_redirected_to post_path(@post)
    assert_equal "Hello World", @post.reload.title
  end

  test "PATCH /posts/:id by non-owner redirects and does not update" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    post login_path, params: { email: "other@example.com", password: "pass123" }
    original_title = @post.title
    patch post_path(@post), params: { post: { title: "Hijacked" } }
    assert_redirected_to post_path(@post)
    assert_equal original_title, @post.reload.title
  end

  test "PATCH /posts/:id outside edit window redirects and does not update" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    travel_to(EDIT_WINDOW_SECONDS.seconds.from_now + 1.second) do
      patch post_path(@post), params: { post: { title: "Late edit" } }
      assert_redirected_to post_path(@post)
      assert_equal "Hello World", @post.reload.title
    end
  end

  test "GET /posts shows correct reply count excluding removed replies" do
    Reply.create!(post: @post, user: @user, body: "Visible reply")
    removed_reply = Reply.create!(post: @post, user: @user, body: "Removed reply")
    removed_reply.update_columns(removed_at: Time.current, removed_by_id: @admin.id)

    get posts_path
    assert_response :success
    assert_equal 1, assigns(:reply_counts)[@post.id]
  end

  test "GET /posts/:id does not fire per-reply reaction queries" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply1 = Reply.create!(post: @post, user: @user, body: "reply 1")
    reply2 = Reply.create!(post: @post, user: @user, body: "reply 2")
    Reaction.create!(user: @user, reactionable: reply1, emoji: "👍")
    Reaction.create!(user: @user, reactionable: reply2, emoji: "❤️")

    query_count = 0
    counter = ->(*, **) { query_count += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get post_path(@post)
    end
    assert_response :ok
    assert query_count < 28, "Expected <28 queries, got #{query_count} — possible N+1 on reactions"
  end
end
