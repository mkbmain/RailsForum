class PostRateLimiter
  WINDOW     = 15.minutes
  BASE_LIMIT = 5
  MAX_LIMIT  = 15

  def initialize(user)
    @user = user
  end

  def allowed?
    activity < limit
  end

  def limit
    @limit ||= begin
      age_in_days = ((Time.current - @user.created_at) / 1.day).floor
      weeks       = [(age_in_days / 7).floor, 4].min
      months      = [[((age_in_days / 30).floor) - 1, 0].max, 6].min
      [BASE_LIMIT + weeks + months, MAX_LIMIT].min
    end
  end

  def remaining
    [limit - activity, 0].max
  end

  private

  def activity
    @activity ||= begin
      posts_count   = @user.posts.where(created_at: WINDOW.ago..).count
      replies_count = @user.replies.where(created_at: WINDOW.ago..).count
      posts_count + replies_count
    end
  end
end
