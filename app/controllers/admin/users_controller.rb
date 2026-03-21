class Admin::UsersController < Admin::BaseController
  PER_PAGE     = 20
  TAB_PER_PAGE = 30

  def index
    scope = User.includes(:roles, :user_bans)
    if params[:q].present?
      term  = params[:q].strip
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{term}%", "%#{term}%")
    end
    page      = [ (params[:page] || 1).to_i, 1 ].max
    users     = scope.order(:name).limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
    @has_more = users.size > PER_PAGE
    @users    = users.first(PER_PAGE)
    @page     = page
    @q        = params[:q].to_s

    user_ids     = @users.map(&:id)
    @post_counts = Post.where(user_id: user_ids).group(:user_id).count
  end

  def show
  end

  def promote
    redirect_to admin_root_path
  end

  def demote
    redirect_to admin_root_path
  end
end
