class ReactionsController < ApplicationController
  before_action :require_login
  before_action :set_post

  def create
    emoji = params[:emoji].to_s
    unless Reaction::ALLOWED_REACTIONS.include?(emoji)
      head :unprocessable_entity and return
    end

    Reaction.upsert(
      { user_id: current_user.id, post_id: @post.id, emoji: emoji, created_at: Time.current, updated_at: Time.current },
      unique_by: %i[user_id post_id]
    )

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("post_reactions_#{@post.id}", partial: "posts/reactions", locals: { post: @post }) }
      format.html         { redirect_to @post }
    end
  end

  def destroy
    reaction = @post.reactions.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless reaction

    reaction.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("post_reactions_#{@post.id}", partial: "posts/reactions", locals: { post: @post }) }
      format.html         { redirect_to @post }
    end
  end

  private

  def set_post
    @post = Post.visible.find(params[:post_id])
  end
end
