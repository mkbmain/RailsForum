class SearchController < ApplicationController
  def index
    @query      = params[:q].to_s.strip
    @categories = Category.all.order(:name)
    @take       = (params[:take] || 10).to_i.clamp(1, 100)
    @page       = [ (params[:page] || 1).to_i, 1 ].max

    if @query.present?
      safe_q = ActiveRecord::Base.sanitize_sql_like(@query)
      posts = Post.visible
                  .includes(:user, :category)
                  .where("title ILIKE :q OR body ILIKE :q", q: "%#{safe_q}%")

      category_id = params[:category].to_i
      posts = posts.where(category_id: category_id) if category_id > 0

      posts = posts.order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))
      @total = posts.count
      @posts = posts.limit(@take + 1).offset((@page - 1) * @take)
    else
      @posts = []
      @total = 0
    end
  end
end
