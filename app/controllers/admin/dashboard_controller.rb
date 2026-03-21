class Admin::DashboardController < Admin::BaseController
  def index
    @total_users   = User.count
    @total_posts   = Post.count
    @total_replies = Reply.count
    @banned_users  = UserBan.where("banned_until >= ?", Time.current).count

    bans = UserBan.includes(:banned_by, :user, :ban_reason)
                  .order(banned_from: :desc).limit(20)
                  .map { |b| { type: :ban, time: b.banned_from, record: b } }

    removed_posts = Post.where.not(removed_at: nil)
                        .includes(:removed_by)
                        .order(removed_at: :desc).limit(20)
                        .map { |p| { type: :removed_post, time: p.removed_at, record: p } }

    removed_replies = Reply.where.not(removed_at: nil)
                           .includes(:removed_by, :post)
                           .order(removed_at: :desc).limit(20)
                           .map { |r| { type: :removed_reply, time: r.removed_at, record: r } }

    @activity = (bans + removed_posts + removed_replies)
                  .sort_by { |item| -item[:time].to_i }
                  .first(20)
  end
end
