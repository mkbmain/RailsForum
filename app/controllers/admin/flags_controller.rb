class Admin::FlagsController < Admin::BaseController
  PER_PAGE = 20

  def index
    page  = [ (params[:page] || 1).to_i, 1 ].max
    flags = Flag.pending
                .includes(:user, :content_type)
                .order(created_at: :asc)
                .limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE)
                .to_a

    @has_more = flags.size > PER_PAGE
    @flags    = flags.first(PER_PAGE)
    @page     = page

    post_flaggable_ids  = @flags.select { |f| f.content_type_id == ContentType::CONTENT_POST  }.map(&:flaggable_id)
    reply_flaggable_ids = @flags.select { |f| f.content_type_id == ContentType::CONTENT_REPLY }.map(&:flaggable_id)

    @flaggables = {}
    Post.where(id: post_flaggable_ids).each do |r|
      @flaggables[[ ContentType::CONTENT_POST, r.id ]] = r
    end
    Reply.where(id: reply_flaggable_ids).includes(:post).each do |r|
      @flaggables[[ ContentType::CONTENT_REPLY, r.id ]] = r
    end
  end

  def dismiss
    flag = Flag.find_by(id: params[:id])
    if flag.nil? || flag.resolved_at.present?
      redirect_to admin_flags_path, notice: "Already resolved." and return
    end
    flag.update!(resolved_at: Time.current, resolved_by: current_user)
    redirect_to admin_flags_path, notice: "Flag dismissed."
  end
end
