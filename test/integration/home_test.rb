require "test_helper"

class HomeTest < ActionDispatch::IntegrationTest
  test "home shows the foundation page" do
    get "/"

    assert_response :success
    assert_select "h1", "CRM возврата покупателей"
    assert_select "p", /Стартовая страница/
  end

  test "health endpoint is available" do
    get "/up"

    assert_response :success
  end
end
