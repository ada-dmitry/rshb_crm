require "test_helper"

class CampaignsTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = Campaign.create!(user: users(:one), name: "Черновик", segment: "no_purchases", offer: "catalog_introduction", body: "Пример предложения", channel: "email", scheduled_at: Time.utc(2026, 10, 20, 12))
    @allowed = Customer.create!(external_id: "campaign-ui-1", name: "Допустимый", email: "yes@example.com", phone: "demo-phone-001")
    @refused = Customer.create!(external_id: "campaign-ui-2", name: "Отказ", email: "no@example.com")
    @allowed.consents.create!(channel: "email", granted: true)
    @refused.consents.create!(channel: "email", granted: false)
  end

  test "campaign pages and mutation routes require authentication" do
    [ "/crm/campaigns", "/crm/campaigns/new", "/crm/campaigns/#{@campaign.id}", "/crm/campaigns/#{@campaign.id}/edit", "/crm/campaigns/#{@campaign.id}/preview" ].each do |path|
      get path
      assert_redirected_to "/session/new"
    end
    assert_no_difference "Campaign.count" do
      post "/crm/campaigns", params: { campaign: attributes }
    end
    assert_redirected_to "/session/new"
    patch "/crm/campaigns/#{@campaign.id}", params: { campaign: { body: "Изменено" } }
    assert_redirected_to "/session/new"
    assert_equal "Пример предложения", @campaign.reload.body
  end

  test "segment and proposal links open a prefilled constructor" do
    sign_in_as users(:one)
    get "/crm/segments/no_purchases"
    assert_select "a[href='/crm/campaigns/new?segment=no_purchases']"
    get "/crm/campaigns/new", params: { segment: "no_purchases", offer: "catalog_introduction" }
    assert_response :success
    assert_select "select[name='campaign[segment]'] option[selected][value='no_purchases']"
    assert_select "select[name='campaign[offer]'] option[selected][value='catalog_introduction']"
    assert_select "label[for='campaign_scheduled_at']", /UTC/
    assert_select "[data-demo-banner]"
  end

  test "creates draft for current user while rejecting injected lifecycle fields" do
    sign_in_as users(:one)
    assert_difference "Campaign.count", 1 do
      assert_no_difference "CampaignRecipient.count" do
        post "/crm/campaigns", params: { campaign: attributes.merge(user_id: users(:two).id, status: "launched", confirmed_at: Time.current) }
      end
    end
    created = Campaign.order(:id).last
    assert_equal users(:one), created.user
    assert created.draft?
    assert_equal Time.utc(2026, 10, 21, 12, 30), created.scheduled_at
    assert_redirected_to "/crm/campaigns/#{created.id}"
    follow_redirect!
    assert_select "[role='status']", /Сообщения не отправлены/
    assert_select "[data-eligible-count]", "1"
  end

  test "form schedule is always parsed in UTC and invalid input shows errors without saving" do
    sign_in_as users(:one)
    Time.use_zone("America/Los_Angeles") do
      post "/crm/campaigns", params: { campaign: attributes }
    end
    assert_equal Time.utc(2026, 10, 21, 12, 30), Campaign.order(:id).last.scheduled_at
    assert_no_difference "Campaign.count" do
      post "/crm/campaigns", params: { campaign: attributes.merge(body: "", channel: "telegram", scheduled_at: "bad-time", window_days: 0) }
    end
    assert_response 422
    assert_select "[role='alert']", /Не удалось сохранить черновик/
    assert_select "input[name='campaign[name]'][value='Новая кампания']"
  end

  test "updates draft and its analysis inputs and preview immediately reflects the new channel" do
    sign_in_as users(:one)
    patch "/crm/campaigns/#{@campaign.id}", params: { campaign: { name: "SMS-черновик", channel: "sms", reference_date: "2026-10-14", window_days: 30, status: "launched" } }
    assert_redirected_to "/crm/campaigns/#{@campaign.id}"
    assert_equal "SMS-черновик", @campaign.reload.name
    assert @campaign.draft?
    assert_equal 30, @campaign.window_days
    follow_redirect!
    assert_select "[data-eligible-count]", "0"
    assert_select "[data-zero-reach]", /Охват равен нулю/
    assert_select "[data-exclusion-reason='invalid_contact']"
    assert_select "[data-exclusion-reason='missing_consent']"
    original = @campaign.attributes
    patch "/crm/campaigns/#{@campaign.id}", params: { campaign: { body: "" } }
    assert_response 422
    assert_equal original, @campaign.reload.attributes
  end

  test "show and recalculation list reasons and do not change any business rows" do
    sign_in_as users(:one)
    before = snapshot
    get "/crm/campaigns/#{@campaign.id}"
    assert_response :success
    assert_select "[data-candidate-count]", "2"
    assert_select "[data-eligible-count]", "1"
    assert_select "[data-excluded-count]", "1"
    assert_select "[data-exclusion-reason='refused']"
    assert_equal before, snapshot
    @allowed.consents.find_by!(channel: "email").update!(granted: false)
    before = snapshot
    get "/crm/campaigns/#{@campaign.id}/preview"
    assert_select "[data-eligible-count]", "0"
    assert_equal before, snapshot
    assert_select "form[action*='launch']", count: 0
    post "/crm/campaigns/#{@campaign.id}/launch"
    assert_response :unprocessable_content
  end

  test "empty segment list unknown campaign and escaped body are handled" do
    sign_in_as users(:one)
    @campaign.update!(segment: "sleeping", body: "<script>alert(1)</script>")
    get "/crm/campaigns/#{@campaign.id}"
    assert_select "[data-empty-candidates]", /В выбранном сегменте нет покупателей/
    assert_not_includes response.body, "<script>alert(1)</script>"
    get "/crm/campaigns/99999999"
    assert_response :not_found
    get "/crm/campaigns"
    assert_select "[data-campaign-id]", count: 1
    @campaign.destroy!
    get "/crm/campaigns"
    assert_select "[data-empty-campaigns]", /Черновиков пока нет/
  end

  test "reserved launched state is not editable via draft interface" do
    @campaign.update!(status: "launched")
    sign_in_as users(:one)
    get "/crm/campaigns/#{@campaign.id}/edit"
    assert_response :conflict
    patch "/crm/campaigns/#{@campaign.id}", params: { campaign: { body: "Изменено" } }
    assert_response :conflict
    assert_equal "Пример предложения", @campaign.reload.body
  end

  private
    def attributes
      { name: "Новая кампания", segment: "no_purchases", offer: "catalog_introduction", body: "Тестовое предложение", channel: "email", scheduled_at: "2026-10-21T12:30", reference_date: "2026-10-13", window_days: 365 }
    end

    def snapshot
      [ Customer, Order, Consent, Campaign, CampaignRecipient ].map { |model| model.order(:id).map(&:attributes) }
    end
end
