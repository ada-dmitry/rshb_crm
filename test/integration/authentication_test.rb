require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "CRM requires authentication" do
    get "/crm"

    assert_response :redirect
    assert_redirected_to "/session/new"
  end

  test "home and sign in are public without registration or password reset" do
    get "/"
    assert_response :success
    assert_select "a[href='/session/new']", "Войти"
    get "/session/new"
    assert_response :success
    assert_select "label[for='email_address']", "Электронная почта"
    assert_select "label[for='password']", "Пароль"
    assert_select "input[type='password'][maxlength='72'][size='24']"
    get "/passwords/new"
    assert_response :not_found
    get "/users/new"
    assert_response :not_found
  end

  test "valid credentials open CRM and set an HttpOnly SameSite cookie" do
    assert_difference "Session.count", 1 do
      post "/session", params: { email_address: " ONE@EXAMPLE.COM ", password: "password" }
    end
    assert_redirected_to "/crm"
    assert_match(/httponly/i, response.headers["Set-Cookie"].to_s)
    assert_match(/samesite=lax/i, response.headers["Set-Cookie"].to_s)
    follow_redirect!
    assert_response :success
    assert_select "h1", "Кабинет фермера"
    assert_select "button", "Выйти"
  end

  test "login returns to the requested protected page" do
    get "/crm"
    post "/session", params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to "/crm"
    follow_redirect!
    assert_response :success
  end

  test "invalid credentials neither create a session nor reveal whether an email exists" do
    [ @user.email_address, "missing@example.com" ].each do |email|
      assert_no_difference "Session.count" do
        post "/session", params: { email_address: email, password: "wrong" }
      end
      assert_redirected_to "/session/new"
      assert_nil cookies[:session_id]
      follow_redirect!
      assert_select "[role='alert']", "Неверная почта или пароль."
    end
  end

  test "logout deletes the server session and a copied cookie cannot reopen CRM" do
    post "/session", params: { email_address: @user.email_address, password: "password" }
    old_cookie = cookies[:session_id]
    assert_difference "Session.count", -1 do
      delete "/session"
    end
    assert_response :see_other
    assert_redirected_to "/session/new"
    assert_empty cookies[:session_id]
    cookies[:session_id] = old_cookie
    get "/crm"
    assert_redirected_to "/session/new"
  end

  test "tampered session cookie is rejected" do
    post "/session", params: { email_address: @user.email_address, password: "password" }
    cookies[:session_id] = "#{cookies[:session_id]}tampered"
    get "/crm"
    assert_redirected_to "/session/new"
  end

  test "login is throttled after ten attempts" do
    10.times { post "/session", params: { email_address: @user.email_address, password: "wrong" } }
    assert_no_difference "Session.count" do
      post "/session", params: { email_address: @user.email_address, password: "password" }
    end
    assert_redirected_to "/session/new"
    follow_redirect!
    assert_select "[role='alert']", "Слишком много попыток. Попробуйте через 3 минуты."
  end
end
