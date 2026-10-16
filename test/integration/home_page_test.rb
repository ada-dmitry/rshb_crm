require "test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  test "home page presents sign in and CRM links as primary and secondary buttons" do
    get root_path

    assert_response :success
    assert_select ".home-actions" do
      assert_select "a.button.button-primary[href=?]", new_session_path, text: "Войти"
      assert_select "a.button.button-secondary[href=?]", crm_path, text: "Открыть CRM"
    end
  end
end
