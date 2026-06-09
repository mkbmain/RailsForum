module RateLimitable
  extend ActiveSupport::Concern

  private

  def check_rate_limit
    limiter = PostRateLimiter.new(current_user)
    unless limiter.allowed?
      used = limiter.limit - limiter.remaining
      flash[:alert] = "You're posting too fast. You've used #{used} of #{limiter.limit} posts/replies in the last 15 minutes."
      redirect_to rate_limit_redirect_path
    end
  end

  def rate_limit_redirect_path
    root_path
  end
end
