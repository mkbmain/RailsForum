class Admin::CategoriesController < Admin::BaseController
  before_action :require_admin
  before_action :set_category, only: [ :edit, :update, :destroy, :move_up, :move_down ]

  def index
    @categories  = Category.all
    @post_counts = Post.group(:category_id).count
  end

  def new
    @category = Category.new
  end

  def create
    @category = Category.new(category_params)
    @category.id       = Category.unscoped.maximum(:id).to_i + 1
    @category.position = Category.unscoped.maximum(:position).to_i + 1
    if @category.save
      redirect_to admin_categories_path, notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      redirect_to admin_categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.posts.exists?
      redirect_to admin_categories_path, alert: "Cannot delete: category has posts." and return
    end
    @category.destroy
    redirect_to admin_categories_path, notice: "Category deleted."
  end

  def move_up
    prev_cat = Category.unscoped.where("position < ?", @category.position).order(position: :desc).first
    if prev_cat
      ActiveRecord::Base.transaction do
        pos = @category.position
        @category.update!(position: prev_cat.position)
        prev_cat.update!(position: pos)
      end
    end
    redirect_to admin_categories_path
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_categories_path, alert: "Could not reorder categories. Please try again."
  end

  def move_down
    next_cat = Category.unscoped.where("position > ?", @category.position).order(position: :asc).first
    if next_cat
      ActiveRecord::Base.transaction do
        pos = @category.position
        @category.update!(position: next_cat.position)
        next_cat.update!(position: pos)
      end
    end
    redirect_to admin_categories_path
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_categories_path, alert: "Could not reorder categories. Please try again."
  end

  private

  def set_category
    @category = Category.unscoped.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name)
  end
end
