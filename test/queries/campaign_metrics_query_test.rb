require "test_helper"
require_relative "../test_helpers/campaign_analytics_helper"

class CampaignMetricsQueryTest < ActiveSupport::TestCase
  include CampaignAnalyticsHelper

  test "counts unique recipients not joined event rows and uses contacted and delivered denominators" do
    assert defined?(CampaignMetricsQuery), "CampaignMetricsQuery must be implemented"
    campaign = analytics_campaign(statuses: %w[simulated simulated simulated excluded pending failed])
    first, second = campaign.campaign_recipients.order(:id).first(2)
    delivery = analytics_event(first, "delivered")
    analytics_event(first, "clicked")
    analytics_event(second, "delivered")
    metrics = CampaignMetricsQuery.call(campaign: campaign)
    assert_equal [ 6, 3, 1, 2, 1, 3 ], [ metrics.candidate_count, metrics.contacted_count, metrics.excluded_count, metrics.delivered_count, metrics.clicked_count, metrics.event_count ]
    assert_equal 66.7, metrics.delivery_rate
    assert_equal 50.0, metrics.click_rate
    assert_raises(ActiveRecord::RecordNotUnique) do
      CampaignEvent.transaction(requires_new: true) { CampaignEvent.insert_all!([ delivery.attributes.except("id") ]) }
    end
    assert_equal metrics.to_h, CampaignMetricsQuery.call(campaign: campaign).to_h
  end

  test "another campaign and current customer or order changes cannot contaminate frozen metrics" do
    assert defined?(CampaignMetricsQuery), "CampaignMetricsQuery must be implemented"
    campaign = analytics_campaign
    recipient = campaign.campaign_recipients.sole
    analytics_event(recipient, "delivered")
    other = analytics_campaign
    analytics_event(other.campaign_recipients.sole, "delivered")
    analytics_event(other.campaign_recipients.sole, "clicked")
    recipient.customer.update!(email: nil)
    recipient.customer.orders.create!(external_id: "analytics-order", total_cents: 999_999, status: "completed", ordered_at: 1.day.from_now)
    metrics = CampaignMetricsQuery.call(campaign: campaign)
    assert_equal [ 1, 1, 0, 100.0, 0.0 ], [ metrics.contacted_count, metrics.delivered_count, metrics.clicked_count, metrics.delivery_rate, metrics.click_rate ]
    assert_not_respond_to metrics, :revenue
    assert_not_respond_to metrics, :sales_growth
  end

  test "zero and empty reach have undefined percentages while missing events do not fabricate deliveries" do
    assert defined?(CampaignMetricsQuery), "CampaignMetricsQuery must be implemented"
    [ [], %w[excluded], %w[failed pending] ].each do |statuses|
      metrics = CampaignMetricsQuery.call(campaign: analytics_campaign(statuses: statuses))
      assert_equal 0, metrics.contacted_count
      assert_equal 0, metrics.delivered_count
      assert_equal 0, metrics.clicked_count
      assert_nil metrics.delivery_rate
      assert_nil metrics.click_rate
    end
    metrics = CampaignMetricsQuery.call(campaign: analytics_campaign)
    assert_equal 0.0, metrics.delivery_rate
    assert_nil metrics.click_rate
    assert_equal 0, metrics.event_count
  end

  test "query is read only and only accepts saved launched campaigns including stale callers" do
    assert defined?(CampaignMetricsQuery), "CampaignMetricsQuery must be implemented"
    draft = analytics_campaign(launched: false)
    assert_raises(ArgumentError) { CampaignMetricsQuery.call(campaign: draft) }
    assert_raises(ArgumentError) { CampaignMetricsQuery.call(campaign: Campaign.new) }
    Campaign.find(draft.id).update!(status: "launched", launched_at: draft.scheduled_at)
    before = [ Campaign, CampaignRecipient, CampaignEvent ].map { |model| model.order(:id).map(&:attributes) }
    metrics = CampaignMetricsQuery.call(campaign: draft)
    assert_equal 1, metrics.contacted_count
    assert_equal before, [ Campaign, CampaignRecipient, CampaignEvent ].map { |model| model.order(:id).map(&:attributes) }
  end
end
