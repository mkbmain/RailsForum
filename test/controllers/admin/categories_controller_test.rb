require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")

    @creator = User.create!(email: "creator@example.com", name: "Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)

    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)

    # Use unscoped to avoid default_scope ordering issues in setup
    Category.unscoped.delete_all
    @cat_a = Category.create!(id: 2, name: "Alpha", position: 1)
    @cat_b = Category.create!(id: 3, name: "Beta",  position: 2)
    @cat_c = Category.create!(id: 4, name: "Gamma", position: 3)
  end

  # --- auth ---

  test "index redirects guest to login" do
    get admin_categories_path
    assert_redirected_to login_path
  end

  test "index redirects creator to root" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get admin_categories_path
    assert_redirected_to root_path
  end

  test "index redirects sub_admin to root" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_categories_path
    assert_redirected_to root_path
  end

  test "index is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_categories_path
    assert_response :success
  end

  # --- index ---

  test "index lists all categories" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_categories_path
    assert_response :success
    assert_match "Alpha", response.body
    assert_match "Beta", response.body
    assert_match "Gamma", response.body
  end

  # --- new ---

  test "new renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get new_admin_category_path
    assert_response :success
  end

  # --- create ---

  test "create with valid params creates category and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "Category.count", 1 do
      post admin_categories_path, params: { category: { name: "New Category" } }
    end
    assert_redirected_to admin_categories_path
    assert_equal "Category created.", flash[:notice]
  end

  test "create assigns next position automatically" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    post admin_categories_path, params: { category: { name: "New Category" } }
    assert_equal 4, Category.find_by!(name: "New Category").position
  end

  test "create with blank name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { name: "Alpha" } }
    end
    assert_response :unprocessable_entity
  end

  # --- edit ---

  test "edit renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get edit_admin_category_path(@cat_a)
    assert_response :success
  end

  # --- update ---

  test "update with valid params updates and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "Renamed" } }
    assert_redirected_to admin_categories_path
    assert_equal "Category updated.", flash[:notice]
    assert_equal "Renamed", @cat_a.reload.name
  end

  test "update with blank name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "update with duplicate name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "Beta" } }
    assert_response :unprocessable_entity
  end

  # --- move_up ---

  test "move_up swaps position with previous category" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_up_admin_category_path(@cat_b)
    assert_redirected_to admin_categories_path
    assert_equal 1, @cat_b.reload.position
    assert_equal 2, @cat_a.reload.position
  end

  test "move_up on first category is a no-op" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_up_admin_category_path(@cat_a)
    assert_redirected_to admin_categories_path
    assert_equal 1, @cat_a.reload.position
  end

  # --- move_down ---

  test "move_down swaps position with next category" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_down_admin_category_path(@cat_b)
    assert_redirected_to admin_categories_path
    assert_equal 3, @cat_b.reload.position
    assert_equal 2, @cat_c.reload.position
  end

  test "move_down on last category is a no-op" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_down_admin_category_path(@cat_c)
    assert_redirected_to admin_categories_path
    assert_equal 3, @cat_c.reload.position
  end

  # --- destroy ---

  test "destroy deletes category with no posts and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "Category.count", -1 do
      delete admin_category_path(@cat_a)
    end
    assert_redirected_to admin_categories_path
    assert_equal "Category deleted.", flash[:notice]
  end

  test "destroy is blocked when category has posts" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    post_record = Post.create!(user: @creator, title: "Post", body: "Body", category: @cat_a)
    assert_no_difference "Category.count" do
      delete admin_category_path(@cat_a)
    end
    assert_redirected_to admin_categories_path
    assert_match "Cannot delete", flash[:alert]
    post_record.destroy
  end
end
