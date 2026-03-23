class PostsController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login,    only: [ :new, :create, :destroy, :edit, :update, :restore ]
  before_action :require_moderator, only: [ :destroy, :restore ]
  before_action :check_not_banned, only: [ :create ]
  before_action :check_rate_limit, only: [ :create ]
  before_action :set_post,          only: [ :edit, :update, :restore ]
  before_action :check_ownership, only: [ :edit, :update ]
  before_action :check_edit_window, only: [ :edit, :update ]

  def index
    @categories = Category.all.order(:name)
    posts = Post.visible.includes(:user, :category, :replies).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))

    category_id = params[:category].to_i
    posts = posts.where(category_id: category_id) if category_id > 0

    take = (params[:take] || 10).to_i.clamp(1, 100)
    page = [ (params[:page] || 1).to_i, 1 ].max

    @posts = posts.limit(take + 1).offset((page - 1) * take)
    @take  = take
    @page  = page
  end

  def show
    @post  = Post.includes(:category).find(params[:id])
    @reply = Reply.new

    take = (params[:take] || 20).to_i.clamp(1, 100)
    page = [ (params[:page] || 1).to_i, 1 ].max

    @replies      = @post.replies.visible.includes(:user).order(:created_at).limit(take + 1).offset((page - 1) * take)
    @reply_count  = @post.replies.visible.count
    @take         = take
    @page         = page

    @flagged_reply_ids = if current_user.present?
      current_user.flags
                  .where(content_type_id: ContentType::CONTENT_REPLY,
                         flaggable_id: @replies.map(&:id))
                  .pluck(:flaggable_id).to_set
    else
      Set.new
    end

    if logged_in?
      participant_ids = (@post.replies.visible.distinct.pluck(:user_id) + [ @post.user_id ]).uniq
      @mention_users = User.where(id: participant_ids)
    else
      @mention_users = []
    end
  end

  def new
    @post       = Post.new
    @categories = Category.all.order(:name)
  end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: "Post created!"
    else
      @categories = Category.all.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = Category.all.order(:name)
  end

  def update
    if @post.update(post_params.merge(last_edited_at: Time.current))
      redirect_to @post, notice: "Post updated!"
    else
      @categories = Category.all.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post = Post.find(params[:id])
    unless can_moderate?(@post.user)
      redirect_to @post, alert: "Not authorized to remove this post."
      return
    end
    @post.update!(removed_at: Time.current, removed_by: current_user)
    NotificationService.content_removed(@post, removed_by: current_user)
    redirect_to @post, notice: "Post removed."
  end

  def restore
    @post.update!(removed_at: nil, removed_by: nil)
    redirect_to @post, notice: "Post restored."
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def check_ownership
    if @post.removed?
      return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
    end
    unless @post.user == current_user
      redirect_to(@post, alert: "Not authorized to edit this post.")
    end
  end

  def check_edit_window
    if Time.current - @post.created_at > EDIT_WINDOW_SECONDS
      redirect_to(@post, alert: "This post can no longer be edited (edit window has expired).")
    end
  end

  def post_params
    params.require(:post).permit(:title, :body, :category_id)
  end

  def rate_limit_redirect_path
    new_post_path
  end

  def ban_redirect_path
    new_post_path
  end
end
