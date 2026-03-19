class ReactionsController < ApplicationController
  include ReactionsHelper  # gives controller access to reactions_frame_id

  before_action :require_login
  before_action :set_reactionable

  def create
    emoji = params[:emoji].to_s
    unless Reaction::ALLOWED_REACTIONS.include?(emoji)
      head :unprocessable_entity and return
    end

    Reaction.upsert(
      {
        user_id:           current_user.id,
        reactionable_type: @reactionable.class.name,
        reactionable_id:   @reactionable.id,
        emoji:             emoji,
        created_at:        Time.current,
        updated_at:        Time.current
      },
      unique_by: %i[user_id reactionable_type reactionable_id]
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          reactions_frame_id(@reactionable),
          partial: "reactions/reactions",
          locals:  { reactionable: @reactionable }
        )
      end
      format.html { redirect_to @post }
    end
  end

  def destroy
    reaction = @reactionable.reactions.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless reaction

    reaction.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          reactions_frame_id(@reactionable),
          partial: "reactions/reactions",
          locals:  { reactionable: @reactionable }
        )
      end
      format.html { redirect_to @post }
    end
  end

  private

  def set_reactionable
    if params[:reply_id]
      @post         = Post.visible.find(params[:post_id])
      @reactionable = @post.replies.visible.find(params[:reply_id])
    else
      @reactionable = Post.visible.find(params[:post_id])
      @post         = @reactionable
    end
  end
end
