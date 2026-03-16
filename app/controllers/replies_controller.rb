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
    @post = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])
    unless @reply.user == current_user
      redirect_to @post, alert: "Not authorized to delete this reply.", status: :see_other
      return
    end
    @reply.destroy
    redirect_to @post, notice: "Reply deleted."
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
