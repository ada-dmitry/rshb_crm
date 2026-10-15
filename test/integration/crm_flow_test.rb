require "test_helper"

class CrmFlowTest < ActionDispatch::IntegrationTest
  test "farmer goes from sign in and segment to an immutable simulated campaign with repeatable analytics" do
    travel_to Time.utc(2026, 10, 22, 12) do
      allowed = 12.times.map do |index|
        customer = Customer.create!(external_id: "flow-#{index}", name: "Покупатель #{index}", email: "flow-#{index}@example.com")
        customer.consents.create!(channel: "email", granted: true)
        customer
      end
      revoked = Customer.create!(external_id: "flow-revoked", name: "Отозвал согласие", email: "revoked@example.com")
      revoked.consents.create!(channel: "email", granted: true)
      refused = Customer.create!(external_id: "flow-refused", name: "Отказался", email: "refused@example.com")
      refused.consents.create!(channel: "email", granted: false)

      get crm_path
      assert_redirected_to new_session_path
      get new_session_path
      assert_response :success
      post session_path, params: { email_address: users(:one).email_address, password: "password" }
      assert_redirected_to crm_path
      follow_redirect!
      assert_select "[data-demo-banner]"

      get segment_path("no_purchases")
      assert_response :success
      assert_select "a[href='#{new_campaign_path(segment: "no_purchases", offer: "catalog_introduction")}']"
      get new_campaign_path, params: { segment: "no_purchases", offer: "catalog_introduction" }
      assert_select "option[selected][value='no_purchases']"
      assert_difference "Campaign.count", 1 do
        post campaigns_path, params: { campaign: {
          name: "Сквозная приёмка", segment: "no_purchases", offer: "catalog_introduction",
          body: "Знакомство с ассортиментом — локальная модель", channel: "email",
          scheduled_at: "2026-10-22T11:59", reference_date: "2026-10-13", window_days: 365
        } }
      end
      campaign = Campaign.order(:id).last
      assert_redirected_to campaign_path(campaign)
      assert_equal users(:one), campaign.user
      assert campaign.draft?
      follow_redirect!
      assert_select "[data-simulated-analytics]", count: 0

      before_preview = business_snapshot(campaign)
      2.times do
        get preview_campaign_path(campaign)
        assert_response :success
        assert_select "[data-candidate-count]", "14"
        assert_select "[data-eligible-count]", "13"
        assert_select "[data-exclusion-reason='refused']", count: 1
      end
      assert_equal before_preview, business_snapshot(campaign)
      assert_empty campaign.campaign_recipients
      assert_equal 0, CampaignEvent.count

      post confirm_campaign_path(campaign), params: { version: campaign.lock_version }
      assert_redirected_to campaign_path(campaign)
      assert_equal users(:one), campaign.reload.confirmed_by
      assert_equal Time.current, campaign.confirmed_at
      assert_empty campaign.campaign_recipients
      # Eligibility is checked again, not copied from preview or confirmation.
      revoked.consents.sole.update!(granted: false)
      post launch_campaign_path(campaign)
      assert_redirected_to campaign_path(campaign)
      assert_equal "launched", campaign.reload.status
      assert_equal 14, campaign.campaign_recipients.count
      assert_equal allowed.map(&:id).sort, campaign.campaign_recipients.where(status: "simulated").order(:customer_id).pluck(:customer_id)
      [ revoked, refused ].each do |customer|
        recipient = campaign.campaign_recipients.find_by!(customer: customer)
        assert_equal "excluded", recipient.status
        assert_equal [ "refused" ], recipient.reasons
        assert_nil recipient.contacted_at
        assert_empty recipient.campaign_events
      end

      events = CampaignEvent.joins(:campaign_recipient).where(campaign_recipients: { campaign_id: campaign.id })
      assert events.exists?(event_type: "delivered")
      assert_equal [ "simulated" ], events.distinct.pluck(:source)
      assert_equal [ 1 ], events.distinct.pluck(:simulation_version)
      delivered = events.where(event_type: "delivered").distinct.count(:campaign_recipient_id)
      clicked = events.where(event_type: "clicked").distinct.count(:campaign_recipient_id)
      frozen_result = business_snapshot(campaign)
      allowed.first.update!(name: "Изменённое имя", email: "changed@example.com")
      allowed.first.consents.sole.update!(granted: false)

      2.times do
        post launch_campaign_path(campaign)
        assert_redirected_to campaign_path(campaign)
        post simulate_events_campaign_path(campaign)
        assert_redirected_to campaign_path(campaign)
        [ campaign_path(campaign), preview_campaign_path(campaign) ].each do |path|
          get path
          assert_response :success
          assert_select "[data-launch-result]"
          assert_select "[data-eligible-count]", "12"
          assert_select "[data-simulated-analytics]", /Не реальные доставки и переходы/
          assert_select "[data-contacted-count]", "12"
          assert_select "[data-delivered-count]", delivered.to_s
          assert_select "[data-clicked-count]", clicked.to_s
          assert_select "td", text: /flow-0@example.com/
          assert_select "a", text: "Покупатель 0"
          assert_select "a[href='#{edit_campaign_path(campaign)}']", count: 0
          assert_select "form[action='#{launch_campaign_path(campaign)}']", count: 0
        end
        assert_equal frozen_result, business_snapshot(campaign)
      end

      get edit_campaign_path(campaign)
      assert_response :conflict
      patch campaign_path(campaign), params: { campaign: { body: "Запрещённое изменение", lock_version: campaign.reload.lock_version } }
      assert_response :conflict
      assert_equal frozen_result, business_snapshot(campaign)
      delete session_path
      assert_redirected_to new_session_path
      get campaign_path(campaign)
      assert_redirected_to new_session_path
    end
  end

  private
    def business_snapshot(campaign)
      [ campaign.reload.attributes,
        campaign.campaign_recipients.order(:id).map(&:attributes),
        CampaignEvent.order(:id).map(&:attributes) ]
    end
end
