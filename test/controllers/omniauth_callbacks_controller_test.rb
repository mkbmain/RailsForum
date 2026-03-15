require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 1, name: "google")
    Provider.find_or_create_by!(id: 3, name: "internal")

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-999",
      info: { email: "google@example.com", name: "Google User", image: nil }
    )
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "successful google callback creates user and logs in" do
    get "/auth/google_oauth2/callback"
    assert_redirected_to root_path
    assert_not_nil session[:user_id]
    user = User.find(session[:user_id])
    assert_equal "google@example.com", user.email
    assert_equal 1, user.provider_id
  end

  test "second login with same oauth finds existing user" do
    get "/auth/google_oauth2/callback"
    first_user_id = session[:user_id]

    delete logout_path
    get "/auth/google_oauth2/callback"
    assert_equal first_user_id, session[:user_id]
    assert_equal 1, User.where(uid: "google-uid-999").count
  end

  test "auth failure redirects to login with alert" do
    get "/auth/failure?message=access_denied"
    assert_redirected_to login_path
  end
end
