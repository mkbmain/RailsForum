module ReactionsHelper
  include ActionView::RecordIdentifier  # gives dom_id to both views and the controller

  # Path to POST a new reaction (create)
  def reaction_create_path(reactionable)
    case reactionable
    when Post  then post_reactions_path(reactionable)
    when Reply then post_reply_reactions_path(reactionable.post, reactionable)
    end
  end

  # Path to DELETE an existing reaction
  def reaction_destroy_path(reactionable, reaction)
    case reactionable
    when Post  then post_reaction_path(reactionable, reaction)
    when Reply then post_reply_reaction_path(reactionable.post, reactionable, reaction)
    end
  end

  # Turbo Frame ID for the reactions widget of any reactionable
  def reactions_frame_id(reactionable)
    "#{dom_id(reactionable)}_reactions"
  end
end
