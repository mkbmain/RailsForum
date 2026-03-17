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

    recent_posts   = @profile_user.posts.visible.includes(:category)
                                   .order(created_at: :desc).limit(per * page + 1).to_a
    recent_replies = @profile_user.replies.visible.includes(:post)
                                   .order(created_at: :desc).limit(per * page + 1).to_a

    combined = (recent_posts.map  { |p| { type: :post,  record: p, created_at: p.created_at } } +
                recent_replies.map { |r| { type: :reply, record: r, created_at: r.created_at } })
               .sort_by { |item| -item[:created_at].to_i }

    offset        = (page - 1) * per
    @has_more     = combined.size > offset + per
    @activity     = combined[offset, per] || []
    @post_count   = @profile_user.posts.visible.count
    @reply_count  = @profile_user.replies.visible.count
    @page         = page
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

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end
end
