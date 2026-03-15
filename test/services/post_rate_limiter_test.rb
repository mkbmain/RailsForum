require "test_helper"

class PostRateLimiterTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(
      email: "limiter@example.com",
      name: "Rate Tester",
      password: "pass123",
      password_confirmation: "pass123",
      provider_id: 3
    )
  end

  # ---- limit formula: week boundaries ----

  test "day 0 limit is 5" do
    assert_equal 5, limiter_at_age(0).limit
  end

  test "day 6 limit is still 5" do
    assert_equal 5, limiter_at_age(6).limit
  end

  test "day 7 limit is 6" do
    assert_equal 6, limiter_at_age(7).limit
  end

  test "day 13 limit is 6" do
    assert_equal 6, limiter_at_age(13).limit
  end

  test "day 14 limit is 7" do
    assert_equal 7, limiter_at_age(14).limit
  end

  test "day 20 limit is 7" do
    assert_equal 7, limiter_at_age(20).limit
  end

  test "day 21 limit is 8" do
    assert_equal 8, limiter_at_age(21).limit
  end

  test "day 27 limit is 8" do
    assert_equal 8, limiter_at_age(27).limit
  end

  test "day 28 limit is 9" do
    assert_equal 9, limiter_at_age(28).limit
  end

  # ---- limit formula: month boundaries ----

  test "day 59 limit is 9" do
    assert_equal 9, limiter_at_age(59).limit
  end

  test "day 60 limit is 10" do
    assert_equal 10, limiter_at_age(60).limit
  end

  test "day 89 limit is 10" do
    assert_equal 10, limiter_at_age(89).limit
  end

  test "day 90 limit is 11" do
    assert_equal 11, limiter_at_age(90).limit
  end

  test "day 119 limit is 11" do
    assert_equal 11, limiter_at_age(119).limit
  end

  test "day 120 limit is 12" do
    assert_equal 12, limiter_at_age(120).limit
  end

  test "day 149 limit is 12" do
    assert_equal 12, limiter_at_age(149).limit
  end

  test "day 150 limit is 13" do
    assert_equal 13, limiter_at_age(150).limit
  end

  test "day 179 limit is 13" do
    assert_equal 13, limiter_at_age(179).limit
  end

  test "day 180 limit is 14" do
    assert_equal 14, limiter_at_age(180).limit
  end

  test "day 209 limit is 14" do
    assert_equal 14, limiter_at_age(209).limit
  end

  test "day 210 limit is 15" do
    assert_equal 15, limiter_at_age(210).limit
  end

  test "day 999 limit is capped at 15" do
    assert_equal 15, limiter_at_age(999).limit
  end

  # ---- allowed? and remaining ----

  test "allowed? is true when no activity" do
    assert limiter_now.allowed?
  end

  test "allowed? is true when activity is below limit" do
    create_posts(4)
    assert limiter_now.allowed?   # new user limit=5, activity=4
  end

  test "allowed? is false when activity equals limit" do
    create_posts(5)
    assert_not limiter_now.allowed?   # new user limit=5, activity=5
  end

  test "allowed? is false when activity exceeds limit" do
    create_posts(6)
    assert_not limiter_now.allowed?
  end

  test "remaining returns correct count below limit" do
    create_posts(3)
    assert_equal 2, limiter_now.remaining   # 5 - 3 = 2
  end

  test "remaining returns 0 when at limit" do
    create_posts(5)
    assert_equal 0, limiter_now.remaining
  end

  test "remaining returns 0 and does not go negative when over limit" do
    create_posts(7)
    assert_equal 0, limiter_now.remaining
  end

  test "activity outside the 15-minute window does not count" do
    travel_to 20.minutes.ago do
      Post.create!(user: @user, title: "Old post", body: "Old body")
    end
    assert_equal 5, limiter_now.remaining   # still full budget
  end

  test "replies count toward the same budget as posts" do
    create_posts(3)
    other_user = User.create!(
      email: "other@example.com", name: "Other User",
      password: "pass123", password_confirmation: "pass123", provider_id: 3
    )
    a_post = Post.create!(user: other_user, title: "A post", body: "A body")
    Reply.create!(post: a_post, user: @user, body: "My reply")
    assert_equal 1, limiter_now.remaining   # 5 - 4 = 1
  end

  private

  def limiter_at_age(days)
    @user.update_column(:created_at, days.days.ago)
    PostRateLimiter.new(@user)
  end

  def limiter_now
    PostRateLimiter.new(@user)
  end

  def create_posts(count)
    count.times do |i|
      Post.create!(user: @user, title: "Post #{i}", body: "Body #{i}")
    end
  end
end
