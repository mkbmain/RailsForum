class RepliesController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login
  before_action :check_not_banned, only: [:create]
  before_action :check_rate_limit, only: [:create]

  def create
    @post = Post.find(params[:post_id])
    @reply = @post.replies.build(reply_params.merge(user: current_user))
    if @reply.save
      redirect_to @post, notice: "Reply posted!"
    else
      @post = Post.includes(replies: :user).find(params[:post_id])
      render "posts/show", status: :unprocessable_entity
    end
  end

  def destroy
    @post  = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])

    if current_user.moderator? && can_moderate?(@reply.user)
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      redirect_to @post, notice: "Reply removed."
    elsif @reply.user == current_user
      @reply.destroy
      redirect_to @post, notice: "Reply deleted."
    else
      redirect_to @post, alert: "Not authorized.", status: :see_other
    end
  end

  private

  def reply_params
    params.require(:reply).permit(:body)
  end

  def rate_limit_redirect_path
    post_path(params[:post_id])
  end

  def ban_redirect_path
    post_path(params[:post_id])
  end
end
