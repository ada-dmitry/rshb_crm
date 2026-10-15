require "test_helper"
require_relative "../../test_helpers/campaign_analytics_helper"

class CampaignsEventSimulatorTest < ActiveSupport::TestCase
  include CampaignAnalyticsHelper

  test "deterministic v1 delivers and clicks only selected contacted recipients with modeled timestamps" do
    assert defined?(Campaigns::EventSimulator), "EventSimulator must be implemented"
    campaign = analytics_campaign(id: 830001, statuses: Array.new(12, "simulated") + %w[excluded pending failed])
    original = campaign.attributes
    Campaigns::EventSimulator.call(campaign: campaign)
    events = CampaignEvent.joins(:campaign_recipient).where(campaign_recipients: { campaign_id: campaign.id })
    assert_equal %w[analytics-1 analytics-2 analytics-3 analytics-4 analytics-5 analytics-6 analytics-7 analytics-8 analytics-10 analytics-11 analytics-12].sort,
      events.where(event_type: "delivered").map { |event| event.campaign_recipient.customer_external_id }.sort
    clicks = events.where(event_type: "clicked").sort_by { |event| event.campaign_recipient.customer_external_id }
    assert_equal %w[analytics-11 analytics-5], clicks.map { |event| event.campaign_recipient.customer_external_id }
    assert_equal [ campaign.launched_at + 2849.seconds, campaign.launched_at + 2317.seconds ], clicks.map(&:occurred_at)
    assert_equal original, campaign.reload.attributes
    assert events.all? { |event| event.source == "simulated" && event.simulation_version == 1 }
    assert events.all? { |event| event.campaign_recipient.status == "simulated" }
  end

  test "repeating with stale associations and a different clock leaves exactly the same event rows" do
    assert defined?(Campaigns::EventSimulator), "EventSimulator must be implemented"
    campaign = analytics_campaign(id: 830001, statuses: Array.new(12, "simulated"))
    campaign.campaign_recipients.load
    Campaigns::EventSimulator.call(campaign: campaign)
    original = CampaignEvent.order(:id).map(&:attributes)
    travel_to 1.year.from_now do
      Campaigns::EventSimulator.call(campaign: campaign)
    end
    assert_equal original, CampaignEvent.order(:id).map(&:attributes)
  end

  test "rejects drafts and handles zero contacted recipients and empty campaigns" do
    assert defined?(Campaigns::EventSimulator), "EventSimulator must be implemented"
    draft = analytics_campaign(launched: false)
    assert_raises(ArgumentError) { Campaigns::EventSimulator.call(campaign: draft) }
    [ [], %w[excluded failed pending] ].each do |statuses|
      campaign = analytics_campaign(statuses: statuses)
      assert_no_difference "CampaignEvent.count" do
        Campaigns::EventSimulator.call(campaign: campaign)
      end
    end
  end

  test "any inconsistent existing chronology rolls back all new events without changing launch history" do
    assert defined?(Campaigns::EventSimulator), "EventSimulator must be implemented"
    campaign = analytics_campaign(id: 830001, statuses: Array.new(5, "simulated"))
    recipient = campaign.campaign_recipients.order(:id).last
    analytics_event(recipient, "delivered", at: recipient.contacted_at + 1.day)
    original = [ campaign.attributes, campaign.campaign_recipients.order(:id).map(&:attributes), CampaignEvent.order(:id).map(&:attributes) ]
    assert_raises(ActiveRecord::RecordInvalid) { Campaigns::EventSimulator.call(campaign: campaign) }
    assert_equal original, [ campaign.reload.attributes, campaign.campaign_recipients.order(:id).map(&:attributes), CampaignEvent.order(:id).map(&:attributes) ]
  end
end
