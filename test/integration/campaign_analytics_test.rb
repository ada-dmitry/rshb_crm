require "test_helper"
require_relative "../test_helpers/campaign_analytics_helper"

class CampaignAnalyticsTest < ActionDispatch::IntegrationTest
  include CampaignAnalyticsHelper

  setup do
    @campaign = analytics_campaign(id: 830001, statuses: Array.new(12, "simulated") + %w[excluded])
  end

  test "modeling requires sign in and POST and rejects drafts and unknown campaigns" do
    post "/crm/campaigns/#{@campaign.id}/simulate_events"
    assert_redirected_to new_session_path
    sign_in_as users(:one)
    get "/crm/campaigns/#{@campaign.id}/simulate_events"
    assert_response :not_found
    post "/crm/campaigns/999999999/simulate_events"
    assert_response :not_found
    draft = analytics_campaign(launched: false)
    get campaign_path(draft)
    assert_select "[data-simulated-analytics]", count: 0
    assert_select "form[action*='simulate_events']", count: 0
    post "/crm/campaigns/#{draft.id}/simulate_events"
    assert_response :unprocessable_content
    assert_equal 0, CampaignEvent.count
  end

  test "viewing a historical campaign is read only and states that no events have been modeled" do
    sign_in_as users(:one)
    before = snapshot
    [ campaign_path(@campaign), preview_campaign_path(@campaign) ].each do |path|
      get path
      assert_response :success
      assert_select "[data-simulated-analytics]", /Моделируемая аналитика/
      assert_select "[data-no-modeled-events]"
      assert_select "[data-contacted-count]", "12"
      assert_select "[data-delivered-count]", "0"
      assert_select "[data-clicked-count]", "0"
      assert_select "[data-delivery-rate]", "0,0%"
      assert_select "[data-click-rate]", "—"
      assert_select "form[action='/crm/campaigns/#{@campaign.id}/simulate_events']"
    end
    assert_equal before, snapshot
  end

  test "POST generates explicitly simulated unique metrics and repetitions do not mutate launch or events" do
    sign_in_as users(:one)
    original = [ @campaign.attributes, @campaign.campaign_recipients.order(:id).map(&:attributes) ]
    post "/crm/campaigns/#{@campaign.id}/simulate_events", params: { source: "real", simulation_version: 999, seed: 123 }
    assert_redirected_to campaign_path(@campaign)
    follow_redirect!
    assert_select "[data-no-modeled-events]", count: 0
    assert_select "[data-simulated-analytics]", /Не реальные доставки и переходы/
    assert_select "[data-contacted-count]", "12"
    assert_select "[data-delivered-count]", "11"
    assert_select "[data-clicked-count]", "2"
    assert_select "[data-delivery-rate]", "91,7%"
    assert_select "[data-click-rate]", "18,2%"
    assert_select "[data-sales-growth], [data-revenue]", count: 0
    assert_equal original, [ @campaign.reload.attributes, @campaign.campaign_recipients.order(:id).map(&:attributes) ]
    assert_equal [ "simulated" ], CampaignEvent.distinct.pluck(:source)
    before = snapshot
    post "/crm/campaigns/#{@campaign.id}/simulate_events"
    assert_redirected_to campaign_path(@campaign)
    get preview_campaign_path(@campaign)
    assert_equal before, snapshot
  end

  test "zero reach and empty campaigns have no invented percentages and modeling remains harmless" do
    sign_in_as users(:one)
    [ [], %w[excluded] ].each do |statuses|
      campaign = analytics_campaign(statuses: statuses)
      assert_no_difference "CampaignEvent.count" do
        post "/crm/campaigns/#{campaign.id}/simulate_events"
      end
      assert_redirected_to campaign_path(campaign)
      follow_redirect!
      assert_select "[data-delivered-count]", "0"
      assert_select "[data-clicked-count]", "0"
      assert_select "[data-delivery-rate]", "—"
      assert_select "[data-click-rate]", "—"
      assert_select "[data-no-modeled-events]"
    end
  end

  private
    def snapshot
      [ Campaign, CampaignRecipient, CampaignEvent, Customer, Order, Consent ].map { |model| model.order(:id).map(&:attributes) }
    end
end
