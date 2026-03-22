require "test_helper"

class RepliesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User", password: "pass123",
                         password_confirmation: "pass123", provider_id: 3)
    @post = Post.create!(user: @user, title: "A Post", body: "Post body")
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                               password: "pass123", password_confirmation: "pass123",
                               provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
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
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "blocked reply" } }
    end
    assert_redirected_to post_path(@post)
    assert_match /banned until/, flash[:alert]
    assert_match ban_reason.name, flash[:alert]
  end

  test "POST /posts/:post_id/replies ban redirects back to the post, not root" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_replies_path(@post), params: { reply: { body: "blocked" } }
    assert_redirected_to post_path(@post)
  end

  test "POST /posts/:post_id/replies is allowed when ban is expired" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_from: 2.days.ago, banned_until: 1.second.ago,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }

    assert_difference "Reply.count", 1 do
      post post_replies_path(@post), params: { reply: { body: "allowed reply" } }
    end
  end

  # ---- moderation: reply removal ----

  test "DELETE reply as sub_admin soft-deletes instead of hard-deletes" do
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      delete post_reply_path(@post, reply)
    end
    assert reply.reload.removed?
    assert_equal @sub_admin.id, reply.reload.removed_by_id
    assert_redirected_to post_path(@post)
  end

  test "DELETE reply as admin soft-deletes" do
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      delete post_reply_path(@post, reply)
    end
    assert reply.reload.removed?
  end

  test "DELETE reply as sub_admin targeting another sub_admin's reply is forbidden" do
    other_sub = User.create!(email: "sub2@example.com", name: "Sub2",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    other_sub.roles << Role.find_by!(name: Role::SUB_ADMIN)
    reply = Reply.create!(post: @post, user: other_sub, body: "Sub reply")
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    delete post_reply_path(@post, reply)
    assert_not reply.reload.removed?
    assert_redirected_to post_path(@post)
    assert_match /Not authorized/, flash[:alert]
  end

  test "DELETE admin's own reply hard-deletes via owner path" do
    reply = Reply.create!(post: @post, user: @admin, body: "Admin reply")
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  test "DELETE reply as admin targeting another admin's reply soft-deletes (admin can moderate any non-self)" do
    other_admin = User.create!(email: "admin2@example.com", name: "Admin2",
                                password: "pass123", password_confirmation: "pass123",
                                provider_id: 3)
    other_admin.roles << Role.find_by!(name: Role::ADMIN)
    reply = Reply.create!(post: @post, user: other_admin, body: "Admin2 reply")
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      delete post_reply_path(@post, reply)
    end
    assert reply.reload.removed?
    assert_redirected_to post_path(@post)
  end

  test "DELETE reply as moderator recalculates post last_replied_at" do
    reply = Reply.create!(post: @post, user: @user, body: "Only reply")
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    delete post_reply_path(@post, reply)
    assert_nil @post.reload.last_replied_at
  end

  test "owner hard-delete still works after moderation path added" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  test "DELETE /posts/:post_id/replies/:id is unaffected by ban" do
    ban_reason = BanReason.find_or_create_by!(name: "Spam")
    UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")

    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end

  # ---- edit / update ----

  test "GET /posts/:post_id/replies/:id/edit requires login" do
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    get edit_post_reply_path(@post, reply)
    assert_redirected_to login_path
  end

  test "GET /posts/:post_id/replies/:id/edit renders form when owner and within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    get edit_post_reply_path(@post, reply)
    assert_response :success
    assert_select "form[action=?]", post_reply_path(@post, reply)
    assert_select "textarea[name=?]", "reply[body]"
  end

  test "GET /posts/:post_id/replies/:id/edit is forbidden for non-owner" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_reply_path(@post, reply)
    assert_redirected_to post_path(@post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "GET /posts/:post_id/replies/:id/edit is blocked after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Old reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    get edit_post_reply_path(@post, reply)
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  test "PATCH /posts/:post_id/replies/:id updates reply and sets last_edited_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Original body")
    original_last_edited_at = reply.last_edited_at
    travel_to 1.minute.from_now do
      patch post_reply_path(@post, reply), params: { reply: { body: "Updated body" } }
    end
    assert_redirected_to post_path(@post)
    reply.reload
    assert_equal "Updated body", reply.body
    assert reply.last_edited_at > original_last_edited_at
  end

  test "PATCH /posts/:post_id/replies/:id does not change post last_replied_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    @post.update_column(:last_replied_at, 1.hour.ago)
    original_last_replied_at = @post.reload.last_replied_at
    patch post_reply_path(@post, reply), params: { reply: { body: "Edited" } }
    assert_in_delta original_last_replied_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "PATCH /posts/:post_id/replies/:id is forbidden for non-owner" do
    other = User.create!(email: "other2@example.com", name: "Other2",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_reply_path(@post, reply), params: { reply: { body: "Hacked" } }
    assert_redirected_to post_path(@post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "PATCH /posts/:post_id/replies/:id with blank body re-renders edit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Valid body")
    patch post_reply_path(@post, reply), params: { reply: { body: "" } }
    assert_response :unprocessable_entity
  end

  test "PATCH /posts/:post_id/replies/:id is blocked after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Old reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    patch post_reply_path(@post, reply), params: { reply: { body: "Too late" } }
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  # ---- Turbo Stream broadcasts ----

  test "POST create broadcasts append + count to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_broadcasts(stream_name_from([ @post, :replies ]), 2) do
      post post_replies_path(@post), params: { reply: { body: "live reply" } }
    end
  end

  test "PATCH update broadcasts replace to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "original")
    assert_broadcasts(stream_name_from([ @post, :replies ]), 1) do
      patch post_reply_path(@post, reply), params: { reply: { body: "updated" } }
    end
  end

  test "DELETE (owner hard-delete) broadcasts remove + count to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "my reply")
    assert_broadcasts(stream_name_from([ @post, :replies ]), 2) do
      delete post_reply_path(@post, reply)
    end
  end

  test "DELETE (moderator soft-delete) broadcasts replace + count to replies stream" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "reply to moderate")
    assert_broadcasts(stream_name_from([ @post, :replies ]), 2) do
      delete post_reply_path(@post, reply)
    end
  end

  # ---- Restore ----

  test "PATCH restore as moderator clears removed_at and removed_by" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    @post.update_column(:last_replied_at, nil)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    reply.reload
    assert_nil reply.removed_at
    assert_nil reply.removed_by
    assert_redirected_to post_path(@post)
    assert_equal "Reply restored.", flash[:notice]
  end

  test "PATCH restore recalculates post last_replied_at" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    @post.update_column(:last_replied_at, nil)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    @post.reload
    assert_not_nil @post.last_replied_at
  end

  test "PATCH restore broadcasts replace + count to replies stream" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_broadcasts(stream_name_from([ @post, :replies ]), 2) do
      patch restore_post_reply_path(@post, reply)
    end
  end

  test "PATCH restore as non-moderator is rejected" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    reply.reload
    assert_not_nil reply.removed_at
    assert_redirected_to root_path
  end
end
