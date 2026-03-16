class PostsController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login, only: [:new, :create]
  before_action :check_not_banned, only: [:create]
  before_action :check_rate_limit, only: [:create]

  def index
    @categories = Category.all.order(:name)
    posts = Post.includes(:user, :category, :replies).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))

    category_id = params[:category].to_i
    posts = posts.where(category_id: category_id) if category_id > 0

    take = (params[:take] || 10).to_i.clamp(1, 100)
    page = [(params[:page] || 1).to_i, 1].max

    @posts = posts.limit(take).offset((page - 1) * take)
    @take  = take
    @page  = page
  end

  def show
    @post  = Post.includes(:category, replies: :user).find(params[:id])
    @reply = Reply.new
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

  private

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
