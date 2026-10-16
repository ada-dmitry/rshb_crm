require "test_helper"

class CampaignLaunchTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = Campaign.create!(user: users(:one), name: "Подтверждение", segment: "no_purchases", offer: "catalog_introduction", body: "Симуляция", channel: "email", scheduled_at: 1.minute.ago)
    @customer = Customer.create!(external_id: "launch-http", name: "Имя на момент запуска", email: "snapshot@example.com")
    @customer.consents.create!(channel: "email", granted: true)
  end

  test "confirm and launch require authentication and GET cannot change state" do
    %w[confirm launch].each do |action|
      post "/crm/campaigns/#{@campaign.id}/#{action}"
      assert_redirected_to new_session_path
    end
    sign_in_as users(:one)
    %w[confirm launch].each do |action|
      get "/crm/campaigns/#{@campaign.id}/#{action}"
      assert_response :not_found
    end
    assert_nil @campaign.reload.confirmed_at
    assert_empty @campaign.campaign_recipients
  end

  test "confirmation requires the displayed version and server sets identity and time" do
    sign_in_as users(:two)
    assert_respond_to @campaign, :lock_version
    get campaign_path(@campaign)
    assert_select "[data-demo-mode]", text: "Деморежим: данные синтетические. Email и SMS не отправляются."
    assert_select "form[action='#{confirm_campaign_path(@campaign)}']"
    post confirm_campaign_path(@campaign)
    assert_response :conflict
    assert_select '[role="alert"]', text: "Черновик изменился. Проверьте текущую версию и подтвердите её заново.", count: 1
    stale_version = @campaign.lock_version
    @campaign.update!(body: "Новая версия")
    post confirm_campaign_path(@campaign), params: { version: stale_version }
    assert_response :conflict
    assert_select '[role="alert"]', text: "Черновик изменился. Проверьте текущую версию и подтвердите её заново.", count: 1
    assert_nil @campaign.reload.confirmed_at
    at = Time.utc(2026, 10, 22, 12)
    travel_to at do
      post confirm_campaign_path(@campaign), params: { version: @campaign.lock_version, confirmed_by_id: users(:one).id, confirmed_at: 1.year.ago }
    end
    assert_redirected_to campaign_path(@campaign)
    assert_equal at, @campaign.reload.confirmed_at
    assert_equal users(:two), @campaign.confirmed_by
  end

  test "missing confirmation early launch and edited confirmation fail without contacts" do
    sign_in_as users(:one)
    post "/crm/campaigns/#{@campaign.id}/launch", params: { confirmed_at: Time.current, confirmed_by_id: users(:one).id }
    assert_response :unprocessable_content
    assert_select '[role="alert"]', text: "Подтвердите текущую версию черновика.", count: 1
    assert_nil @campaign.reload.confirmed_at
    @campaign.update!(scheduled_at: 1.hour.from_now)
    confirm
    get campaign_path(@campaign)
    assert_select "form[action='#{launch_campaign_path(@campaign)}'] button", text: "Запустить локальную симуляцию"
    post launch_campaign_path(@campaign)
    assert_response :unprocessable_content
    assert_select '[role="alert"]', text: "Планируемое время ещё не наступило.", count: 1
    patch campaign_path(@campaign), params: { campaign: { body: "Изменено", lock_version: @campaign.reload.lock_version } }
    assert_redirected_to campaign_path(@campaign)
    assert_nil @campaign.reload.confirmed_at
    assert_empty @campaign.campaign_recipients
  end

  test "launch renders frozen local results instead of preview and cannot be edited" do
    sign_in_as users(:one)
    confirm
    post launch_campaign_path(@campaign)
    assert_redirected_to campaign_path(@campaign)
    @customer.update!(email: "new@example.com", name: "Другое имя")
    @customer.consents.sole.update!(granted: false)
    [ campaign_path(@campaign), preview_campaign_path(@campaign) ].each do |path|
      get path
      assert_response :success
      assert_select "[data-launch-result]"
      assert_select "[data-launch-result] h2", "Результат локальной симуляции"
      assert_select "[data-demo-mode]", text: "Деморежим: данные синтетические. Email и SMS не отправляются."
      assert_select "[data-eligible-count]", "1"
      assert_select "td", text: /snapshot@example.com/
      assert_select "a", text: "Имя на момент запуска"
      assert_select "a[href='#{edit_campaign_path(@campaign)}']", count: 0
      assert_select "form[action*='launch']", count: 0
      assert_select "form[action*='confirm']", count: 0
    end
    assert_no_difference "CampaignRecipient.count" do
      post launch_campaign_path(@campaign)
    end
    get edit_campaign_path(@campaign)
    assert_response :conflict
    patch campaign_path(@campaign), params: { campaign: { body: "Запрещено" } }
    assert_response :conflict
    assert_equal "Симуляция", @campaign.reload.body
  end

  test "stale browser edit cannot overwrite a newer draft or confirmation" do
    sign_in_as users(:one)
    assert_respond_to @campaign, :lock_version
    version = @campaign.lock_version
    confirm
    patch campaign_path(@campaign), params: { campaign: { body: "Устаревшее", lock_version: version } }
    assert_response :conflict
    assert_select '[role="alert"]', text: "Черновик изменился. Проверьте текущую версию и подтвердите её заново.", count: 1
    assert_equal "Симуляция", @campaign.reload.body
    assert_not_nil @campaign.confirmed_at
  end

  test "zero reach completes with fixed exclusions and an empty segment completes too" do
    sign_in_as users(:one)
    @customer.consents.sole.update!(granted: false)
    confirm
    post launch_campaign_path(@campaign)
    follow_redirect!
    assert_select "[data-launch-result]"
    assert_select "[data-eligible-count]", "0"
    assert_select "[data-exclusion-reason='refused']"
    assert_nil @campaign.campaign_recipients.sole.contacted_at
    empty = Campaign.create!(@campaign.attributes.except("id", "created_at", "updated_at", "status", "confirmed_at", "confirmed_by_id", "launched_at", "lock_version").merge("segment" => "sleeping"))
    post confirm_campaign_path(empty), params: { version: empty.lock_version }
    post launch_campaign_path(empty)
    follow_redirect!
    assert_select "[data-launch-result]"
    assert_select "[data-candidate-count]", "0"
    assert_equal "launched", empty.reload.status
  end

  private
    def confirm
      post confirm_campaign_path(@campaign), params: { version: @campaign.reload.lock_version }
      assert_redirected_to campaign_path(@campaign)
    end
end
