module RateLimitable
  extend ActiveSupport::Concern

  private

  def check_rate_limit
    limiter = PostRateLimiter.new(current_user)
    unless limiter.allowed?
      flash[:alert] = "You're posting too fast. Limit is #{limiter.limit} posts/replies per 15 minutes."
      redirect_to rate_limit_redirect_path
    end
  end

  def rate_limit_redirect_path
    root_path
  end
end
