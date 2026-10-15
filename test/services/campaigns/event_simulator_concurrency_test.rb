require "test_helper"
require "timeout"
require_relative "../../test_helpers/campaign_analytics_helper"

class CampaignsEventSimulatorConcurrencyTest < ActiveSupport::TestCase
  include CampaignAnalyticsHelper
  self.use_transactional_tests = false

  setup do
    @campaign = analytics_campaign(id: 830001, statuses: Array.new(12, "simulated"))
    @customer_ids = @campaign.campaign_recipients.pluck(:customer_id)
  end

  teardown do
    Campaign.transaction do
      connection = Campaign.connection
      connection.execute("ALTER TABLE campaign_events DISABLE TRIGGER protect_campaign_event")
      connection.execute("ALTER TABLE campaign_recipients DISABLE TRIGGER protect_campaign_snapshot")
      connection.execute("ALTER TABLE campaigns DISABLE TRIGGER protect_campaign_launch")
      CampaignEvent.where(campaign_recipient_id: @campaign.campaign_recipients.select(:id)).delete_all
      CampaignRecipient.where(campaign_id: @campaign.id).delete_all
      Campaign.where(id: @campaign.id).delete_all
      Customer.where(id: @customer_ids).delete_all
      connection.execute("ALTER TABLE campaigns ENABLE TRIGGER protect_campaign_launch")
      connection.execute("ALTER TABLE campaign_recipients ENABLE TRIGGER protect_campaign_snapshot")
      connection.execute("ALTER TABLE campaign_events ENABLE TRIGGER protect_campaign_event")
    end
  end

  test "two overlapping simulations of a previously launched campaign create one immutable set" do
    entered = Queue.new
    release = Queue.new
    backend = Queue.new
    threads = []
    threads << Thread.new do
      Campaign.connection_pool.with_connection do
        campaign = Campaign.find(@campaign.id)
        campaign.with_lock do
          entered << true
          Timeout.timeout(10) { release.pop }
          Campaigns::EventSimulator.call(campaign: campaign)
        end
      end
    end
    Timeout.timeout(10) { entered.pop }
    threads << Thread.new do
      Campaign.connection_pool.with_connection do |connection|
        backend << connection.select_value("SELECT pg_backend_pid()")
        Campaigns::EventSimulator.call(campaign: Campaign.find(@campaign.id))
      end
    end
    pid = Timeout.timeout(10) { backend.pop }
    Campaign.uncached do
      Timeout.timeout(10) do
        until Campaign.connection.select_value("SELECT cardinality(pg_blocking_pids(#{Integer(pid)})) > 0")
          sleep 0.01
        end
      end
    end
    assert_equal 0, CampaignEvent.count
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    Campaign.connection.clear_query_cache
    assert_equal 11, CampaignEvent.where(event_type: "delivered").count
    assert_equal 2, CampaignEvent.where(event_type: "clicked").count
    assert_equal 13, CampaignEvent.count
  ensure
    release << true if release
    threads&.each { |thread| Timeout.timeout(10) { thread.value } }
  end
end
