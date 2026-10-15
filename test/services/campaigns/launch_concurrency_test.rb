require "test_helper"
require "timeout"

class CampaignsLaunchConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @customer = Customer.create!(external_id: "concurrent-#{SecureRandom.hex(8)}", name: "Общий покупатель", email: "shared@example.com", phone: "+12025550123")
    Consent::CHANNELS.each { |channel| @customer.consents.create!(channel: channel, granted: true) }
    @campaigns = %w[email sms].map do |channel|
      Campaign.create!(user: users(:one), name: "Конкурентный запуск", segment: "no_purchases", offer: "catalog_introduction", body: "Только симуляция", channel: channel, scheduled_at: 1.minute.ago).tap do |campaign|
        campaign.confirm!(user: users(:one), version: campaign.lock_version)
      end
    end
  end

  teardown do
    # These tests commit on independent connections. Only test cleanup may
    # bypass immutable-history triggers; restore them in the same transaction.
    Campaign.transaction do
      connection = Campaign.connection
      connection.execute("ALTER TABLE campaign_events DISABLE TRIGGER protect_campaign_event")
      connection.execute("ALTER TABLE campaign_recipients DISABLE TRIGGER protect_campaign_snapshot")
      connection.execute("ALTER TABLE campaigns DISABLE TRIGGER protect_campaign_launch")
      CampaignEvent.where(campaign_recipient_id: CampaignRecipient.where(campaign_id: @campaigns.map(&:id))).delete_all
      CampaignRecipient.where(campaign_id: @campaigns.map(&:id)).delete_all
      Campaign.where(id: @campaigns.map(&:id)).delete_all
      @customer.consents.delete_all
      @customer.delete
      connection.execute("ALTER TABLE campaigns ENABLE TRIGGER protect_campaign_launch")
      connection.execute("ALTER TABLE campaign_recipients ENABLE TRIGGER protect_campaign_snapshot")
      connection.execute("ALTER TABLE campaign_events ENABLE TRIGGER protect_campaign_event")
    end
  end

  test "overlapping requests for the same campaign produce one contact" do
    race(@campaigns.first, @campaigns.first)
    assert_equal 1, CampaignRecipient.where(customer: @customer).count
    assert_equal 1, CampaignRecipient.where(customer: @customer, status: "simulated").count
  end

  test "overlapping campaigns in different channels cannot spend the same contact budget" do
    race(*@campaigns)
    records = CampaignRecipient.where(customer: @customer).order(:id).to_a
    assert_equal %w[simulated excluded], records.map(&:status)
    assert_equal [ "frequency_limit" ], records.last.reasons
    assert @campaigns.all? { |campaign| campaign.reload.status == "launched" }
  end

  private
    def race(first, second)
      entered = Queue.new
      release = Queue.new
      backend = Queue.new
      threads = []
      delivery = ->(recipient:, at:) do
        entered << true
        Timeout.timeout(10) { release.pop }
        Campaigns::SimulatedDelivery.call(recipient: recipient, at: at)
      end
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Campaigns::Launch.call(campaign: Campaign.find(first.id), delivery: delivery)
        end
      end
      Timeout.timeout(10) { entered.pop }
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          Campaign.cache do
            stale = Campaign.find(second.id)
            Campaigns::Eligibility.for_customers(customer_ids: [ @customer.id ], channel: second.channel, at: Time.current)
            backend << connection.select_value("SELECT pg_backend_pid()")
            Campaigns::Launch.call(campaign: stale)
          end
        end
      end
      pid = Timeout.timeout(10) { backend.pop }
      # Prove the requests overlap: first transaction has not committed and
      # second has reached PostgreSQL and is waiting for the shared mutex.
      Campaign.uncached do
        Timeout.timeout(10) do
          until ActiveRecord::Base.connection.select_value("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = #{Integer(pid)} AND locktype = 'advisory' AND NOT granted)")
            sleep 0.01
          end
        end
      end
      assert_equal 0, CampaignRecipient.where(customer: @customer).count
    ensure
      release << true if release
      threads&.each { |thread| Timeout.timeout(10) { thread.value } }
      ActiveRecord::Base.connection.clear_query_cache
    end
end
