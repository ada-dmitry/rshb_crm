require "test_helper"
require_relative "../test_helpers/campaign_analytics_helper"

class CampaignEventTest < ActiveSupport::TestCase
  include CampaignAnalyticsHelper

  setup do
    @campaign = analytics_campaign(statuses: %w[simulated excluded pending failed])
    @recipient = @campaign.campaign_recipients.order(:id).first
  end

  test "only simulated delivery and click events with valid identity source and timestamps are accepted" do
    assert defined?(CampaignEvent), "CampaignEvent must be implemented"
    event = analytics_event(@recipient, "delivered")
    assert_equal "simulated", event.source
    assert_equal 1, event.simulation_version
    [ { event_type: "opened" }, { occurred_at: nil }, { source: "real" }, { simulation_version: 2 }, { campaign_recipient: nil } ].each do |invalid|
      assert_not CampaignEvent.new({ campaign_recipient: @recipient, event_type: "clicked", occurred_at: @recipient.contacted_at + 20.minutes }.merge(invalid)).valid?
    end
    assert_not CampaignEvent.new(campaign_recipient: @recipient, event_type: "delivered", occurred_at: @recipient.contacted_at).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      CampaignEvent.transaction(requires_new: true) { CampaignEvent.insert_all!([ event.attributes.except("id") ]) }
    end
  end

  test "events cannot be attached to drafts or noncontacted recipients even through direct inserts" do
    assert defined?(CampaignEvent), "CampaignEvent must be implemented"
    draft = analytics_campaign(launched: false)
    recipients = @campaign.campaign_recipients.where.not(status: "simulated").to_a + draft.campaign_recipients.to_a
    recipients.each do |recipient|
      assert_raises(ActiveRecord::StatementInvalid) do
        CampaignEvent.transaction(requires_new: true) do
          CampaignEvent.insert_all!([ { campaign_recipient_id: recipient.id, event_type: "delivered", occurred_at: @campaign.launched_at } ])
        end
      end
    end
  end

  test "click requires an earlier delivery and events cannot precede contact" do
    assert defined?(CampaignEvent), "CampaignEvent must be implemented"
    assert_raises(ActiveRecord::RecordInvalid) { analytics_event(@recipient, "clicked") }
    assert_raises(ActiveRecord::RecordInvalid) { analytics_event(@recipient, "delivered", at: @recipient.contacted_at - 1.second) }
    analytics_event(@recipient, "delivered")
    assert_raises(ActiveRecord::RecordInvalid) { analytics_event(@recipient, "clicked", at: @recipient.contacted_at + 30.seconds) }
    assert analytics_event(@recipient, "clicked").persisted?
  end

  test "recorded simulated events are immutable including direct update and delete" do
    assert defined?(CampaignEvent), "CampaignEvent must be implemented"
    event = analytics_event(@recipient, "delivered")
    [ -> { event.update_columns(occurred_at: event.occurred_at + 1.hour) }, -> { event.delete } ].each do |write|
      assert_raises(ActiveRecord::StatementInvalid) do
        CampaignEvent.transaction(requires_new: true) { write.call }
      end
    end
    assert CampaignEvent.exists?(event.id)
  end

  test "database rejects unsupported events source version and chronology even without model validation" do
    assert defined?(CampaignEvent), "CampaignEvent must be implemented"
    attributes = { campaign_recipient_id: @recipient.id, event_type: "delivered", occurred_at: @recipient.contacted_at + 1.minute }
    [ { event_type: "opened" }, { source: "real" }, { simulation_version: 2 }, { occurred_at: nil },
      { occurred_at: @recipient.contacted_at - 1.second }, { event_type: "clicked" } ].each do |invalid|
      assert_raises(ActiveRecord::StatementInvalid) do
        CampaignEvent.transaction(requires_new: true) { CampaignEvent.insert_all!([ attributes.merge(invalid) ]) }
      end
    end
  end
end
