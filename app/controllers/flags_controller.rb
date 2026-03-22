class FlagsController < ApplicationController
  before_action :require_login

  def create
    if params[:reply_id]
      post_record = Post.visible.find_by(id: params[:post_id])
      flaggable = post_record&.replies&.visible&.find_by(id: params[:reply_id])
      content_type_id = ContentType::CONTENT_REPLY
      flaggable_id    = params[:reply_id].to_i
    else
      flaggable = Post.visible.find_by(id: params[:post_id])
      content_type_id = ContentType::CONTENT_POST
      flaggable_id    = params[:post_id].to_i
    end

    if flaggable.nil?
      redirect_back(fallback_location: posts_path, allow_other_host: false,
                    alert: "Content not found.") and return
    end

    flag = Flag.new(
      user:            current_user,
      content_type_id: content_type_id,
      flaggable_id:    flaggable_id,
      reason:          flag_params[:reason]
    )

    if flag.save
      redirect_back(fallback_location: post_path(params[:post_id]), allow_other_host: false,
                    notice: "Content reported.")
    else
      redirect_back(fallback_location: post_path(params[:post_id]), allow_other_host: false,
                    alert: flag.errors.full_messages.to_sentence)
    end
  end

  private

  def flag_params
    params.require(:flag).permit(:reason)
  end
end
