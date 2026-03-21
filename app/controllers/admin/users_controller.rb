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
    @user       = User.includes(:roles).find(params[:id])
    @tab        = params[:tab].presence_in(%w[posts replies bans activity]) || "posts"
    @active_ban = @user.user_bans.where("banned_until >= ?", Time.current)
                       .order(banned_until: :desc).first
    @has_moderation_history = UserBan.where(banned_by: @user).exists? ||
                              Post.where(removed_by: @user).exists? ||
                              Reply.where(removed_by: @user).exists?

    page = [ (params[:page] || 1).to_i, 1 ].max

    case @tab
    when "posts"
      scope     = @user.posts.includes(:removed_by).order(created_at: :desc)
      items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      @has_more = items.size > TAB_PER_PAGE
      @items    = items.first(TAB_PER_PAGE)
    when "replies"
      scope     = @user.replies.includes(:post, :removed_by).order(created_at: :desc)
      items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      @has_more = items.size > TAB_PER_PAGE
      @items    = items.first(TAB_PER_PAGE)
    when "bans"
      scope     = @user.user_bans.includes(:ban_reason, :banned_by).order(banned_from: :desc)
      items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      @has_more = items.size > TAB_PER_PAGE
      @items    = items.first(TAB_PER_PAGE)
    when "activity"
      bans_raw         = UserBan.where(banned_by: @user).includes(:user, :ban_reason)
                                .order(banned_from: :desc)
                                .limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      posts_raw        = Post.where(removed_by: @user).includes(:user)
                             .order(removed_at: :desc)
                             .limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      replies_raw      = Reply.where(removed_by: @user).includes(:user, :post)
                              .order(removed_at: :desc)
                              .limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
      @has_more        = bans_raw.size > TAB_PER_PAGE ||
                         posts_raw.size > TAB_PER_PAGE ||
                         replies_raw.size > TAB_PER_PAGE
      @bans_issued     = bans_raw.first(TAB_PER_PAGE)
      @posts_removed   = posts_raw.first(TAB_PER_PAGE)
      @replies_removed = replies_raw.first(TAB_PER_PAGE)
    end

    @page = page
  end

  def promote
    redirect_to admin_root_path
  end

  def demote
    redirect_to admin_root_path
  end
end
