class UsersController < ApplicationController
  before_action :require_login,    only: [ :edit, :update ]
  before_action :set_profile_user, only: [ :show, :edit, :update ]
  before_action :require_owner,    only: [ :edit, :update ]

  def new
    redirect_to(root_path) and return if logged_in?
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.provider_id = Provider::INTERNAL
    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome, #{@user.name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    permitted = params.require(:user).permit(:name, :bio, :current_password, :password, :password_confirmation)

    if permitted[:password].present?
      unless @profile_user.authenticate(permitted[:current_password].to_s)
        @profile_user.errors.add(:base, "Current password is incorrect")
        render :edit, status: :unprocessable_entity and return
      end
      attrs = permitted.except(:current_password).to_h
    else
      attrs = permitted.slice(:name, :bio).to_h
    end

    if @profile_user.update(attrs)
      redirect_to user_path(@profile_user), notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def show
    page = [ (params[:page] || 1).to_i, 1 ].max
    per  = 20

    rows      = fetch_activity_rows(@profile_user, page: page, per: per)
    @has_more = rows.size > per
    rows      = rows.first(per)

    post_ids   = rows.select { |r| r["kind"] == "post"  }.map { |r| r["id"].to_i }
    reply_ids  = rows.select { |r| r["kind"] == "reply" }.map { |r| r["id"].to_i }

    posts_by_id   = Post.includes(:category).where(id: post_ids).index_by(&:id)
    replies_by_id = Reply.includes(:post).where(id: reply_ids).index_by(&:id)

    @activity = rows.map do |r|
      if r["kind"] == "post"
        { type: :post,  record: posts_by_id[r["id"].to_i],   created_at: r["created_at"] }
      else
        { type: :reply, record: replies_by_id[r["id"].to_i], created_at: r["created_at"] }
      end
    end

    @post_count  = @profile_user.posts.visible.count
    @reply_count = @profile_user.replies.visible.count
    @page        = page
  end

  private

  def set_profile_user
    @profile_user = User.find(params[:id])
  end

  def require_owner
    unless @profile_user == current_user
      redirect_to root_path, alert: "Not authorized."
    end
  end

  def fetch_activity_rows(user, page:, per:)
    offset      = (page - 1) * per
    posts_sql   = Post.visible.where(user: user).select("'post' AS kind, id, created_at").to_sql
    replies_sql = Reply.visible.where(user: user).select("'reply' AS kind, id, created_at").to_sql

    # LIMIT and OFFSET are computed Ruby integers (never user-supplied strings) — safe to interpolate.
    # .to_sql embeds the user_id literal from ActiveRecord — no injection vector.
    ActiveRecord::Base.connection.exec_query(<<~SQL).to_a
      (#{posts_sql}) UNION ALL (#{replies_sql})
      ORDER BY created_at DESC
      LIMIT #{per + 1} OFFSET #{offset}
    SQL
  end

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end
end
