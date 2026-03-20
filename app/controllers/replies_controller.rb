class RepliesController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login
  before_action :check_not_banned, only: [ :create ]
  before_action :check_rate_limit, only: [ :create ]
  before_action :set_reply, only: [ :edit, :update ]
  before_action :check_ownership, only: [ :edit, :update ]
  before_action :check_edit_window, only: [ :edit, :update ]

  def create
    @post = Post.find(params[:post_id])
    @reply = @post.replies.build(reply_params.merge(user: current_user))
    if @reply.save
      NotificationService.reply_created(@reply, current_user: current_user)
      broadcast_reply_created
      redirect_to @post, notice: "Reply posted!"
    else
      @take    = 20
      @page    = 1
      @replies = @post.replies.includes(:user).order(:created_at).limit(@take).offset(0)
      @reply_count = @post.replies.count
      render "posts/show", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @reply.update(reply_params.merge(last_edited_at: Time.current))
      broadcast_reply_updated
      redirect_to @post, notice: "Reply updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post  = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])

    if current_user.moderator? && can_moderate?(@reply.user)
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      NotificationService.content_removed(@reply, removed_by: current_user)
      broadcast_reply_soft_deleted
      redirect_to @post, notice: "Reply removed."
    elsif @reply.user == current_user
      @reply.destroy
      broadcast_reply_hard_deleted
      redirect_to @post, notice: "Reply deleted."
    else
      redirect_to @post, alert: "Not authorized.", status: :see_other
    end
  end

  private

  def set_reply
    @post  = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])
  end

  def check_ownership
    unless @reply.user == current_user
      redirect_to @post, alert: "Not authorized to edit this reply."
    end
  end

  def check_edit_window
    if Time.current - @reply.created_at > EDIT_WINDOW_SECONDS
      redirect_to @post, alert: "This reply can no longer be edited (edit window has expired)."
    end
  end

  def reply_params
    params.require(:reply).permit(:body)
  end

  def rate_limit_redirect_path
    post_path(params[:post_id])
  end

  def ban_redirect_path
    post_path(params[:post_id])
  end

  def broadcast_reply_created
    Turbo::StreamsChannel.broadcast_append_to(
      [ @post, :replies ],
      target: "replies-list-#{@post.id}",
      partial: "replies/reply",
      locals: { reply: @reply, post: @post }
    )
    broadcast_reply_count
  end

  def broadcast_reply_updated
    Turbo::StreamsChannel.broadcast_replace_to(
      [ @post, :replies ],
      target: "reply-#{@reply.id}",
      partial: "replies/reply",
      locals: { reply: @reply, post: @post }
    )
  end

  def broadcast_reply_soft_deleted
    Turbo::StreamsChannel.broadcast_replace_to(
      [ @post, :replies ],
      target: "reply-#{@reply.id}",
      partial: "replies/reply",
      locals: { reply: @reply, post: @post }
    )
    broadcast_reply_count
  end

  def broadcast_reply_hard_deleted
    Turbo::StreamsChannel.broadcast_remove_to(
      [ @post, :replies ],
      target: "reply-#{@reply.id}"
    )
    broadcast_reply_count
  end

  def broadcast_reply_count
    Turbo::StreamsChannel.broadcast_replace_to(
      [ @post, :replies ],
      target: "replies_count_#{@post.id}",
      partial: "replies/count",
      locals: { post: @post, count: @post.replies.visible.count }
    )
  end
end
