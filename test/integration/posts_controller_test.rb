require "test_helper"

class PostsControllerIntegrationTest < ActionDispatch::IntegrationTest
  fixtures :all

  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "breadcrumb_u@example.com", name: "User", password: "pass123",
                         password_confirmation: "pass123", provider_id: 3,
                         email_verified_at: Time.current)
    @post = Post.create!(user: @user, title: "Hello World", body: "First post body")
  end

  test "GET /posts includes default og:title meta tag" do
    get posts_path
    assert_response :success
    assert_select "meta[property='og:title']", count: 1
  end

  test "GET /posts/:id includes post og:title meta tag" do
    get post_path(@post)
    assert_response :success
    assert_select "meta[property='og:title'][content='#{@post.title}']", count: 1
    assert_select "meta[property='og:type'][content='article']", count: 1
    assert_select "meta[property='og:description'][content^='First post']", count: 1
  end

  test "GET /posts/:id og:description decodes HTML entities correctly" do
    @post.update!(body: "Cats & Dogs are great")
    get post_path(@post)
    assert_response :success
    assert_select "meta[property='og:description'][content^='Cats & Dogs']", count: 1
  end

  test "GET /posts/:id shows breadcrumb trail with category link" do
    get post_path(@post)
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb']" do
      assert_select "a[href='#{root_path}']", text: "Forum"
      assert_select "a[href*='category=#{@post.category_id}']"
    end
  end
end
