require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "searcher@example.com", name: "Searcher",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post = Post.create!(user: @user, title: "Ruby on Rails tips", body: "Use strong params always")
  end

  test "GET /search renders page" do
    get search_path
    assert_response :success
  end

  test "GET /search with query returns matching posts" do
    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search matches on body text" do
    get search_path, params: { q: "strong params" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search is case-insensitive" do
    get search_path, params: { q: "ruby on rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search excludes removed posts" do
    @post.update_column(:removed_at, Time.current)
    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/, count: 0
  end

  test "GET /search with no results shows empty state" do
    get search_path, params: { q: "xyzzy123notfound" }
    assert_response :success
    assert_select "p", text: /No posts found/
  end

  test "GET /search filters by category" do
    cat2 = Category.create!(id: (Category.maximum(:id) || 0) + 1, name: "Meta")
    other = Post.create!(user: @user, title: "Rails and Meta", body: "body", category_id: cat2.id)
    get search_path, params: { q: "Rails", category: cat2.id }
    assert_response :success
    assert_select "a", text: /Rails and Meta/
    assert_select "a", text: /Ruby on Rails tips/, count: 0
  end
end
