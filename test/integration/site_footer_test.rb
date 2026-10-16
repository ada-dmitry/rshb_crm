require "test_helper"

class SiteFooterTest < ActionDispatch::IntegrationTest
  test "public pages display development credits" do
    [ "/", "/session/new" ].each do |path|
      get path
      assert_response :success
      assert_select "body > footer.site-footer[lang='en']", count: 1,
        text: "Developed by Antipenko D. A. for RSHB · 2026"
    end
  end

  test "authenticated CRM pages display development credits" do
    sign_in_as users(:one)
    [ "/crm", "/crm/customers", "/crm/campaigns" ].each do |path|
      get path
      assert_response :success
      assert_select "body > footer.site-footer[lang='en']", count: 1,
        text: "Developed by Antipenko D. A. for RSHB · 2026"
    end
  end
end
