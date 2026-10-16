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

  test "consent revocation waits while launch holds eligibility snapshot" do
    entered, release, backend = Queue.new, Queue.new, Queue.new
    threads = []
    consent = @customer.consents.find_by!(channel: "email")
    delivery = ->(recipient:, at:) do
      entered << true
      Timeout.timeout(10) { release.pop }
      Campaigns::SimulatedDelivery.call(recipient: recipient, at: at)
    end
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Campaigns::Launch.call(campaign: Campaign.find(@campaigns.first.id), delivery: delivery)
      end
    end
    Timeout.timeout(10) { entered.pop }
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        backend << connection.select_value("SELECT pg_backend_pid()")
        Consent.find(consent.id).update!(granted: false)
      end
    end
    assert_database_wait(Timeout.timeout(10) { backend.pop }, threads.last)
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    assert_equal "simulated", @campaigns.first.campaign_recipients.sole.status
    assert_equal 1, CampaignRecipient.where(customer: @customer).count
    assert_not consent.reload.granted?
    decision = Campaigns::Eligibility.call(customer: @customer, channel: "email", at: Time.current)
    assert_includes decision.reasons, "refused"
  ensure
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
  end

  test "launch waits for pending revocation and excludes refused customer" do
    entered, release, backend = Queue.new, Queue.new, Queue.new
    threads = []
    consent = @customer.consents.find_by!(channel: "email")
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Consent.transaction do
          Consent.find(consent.id).update!(granted: false)
          entered << true
          Timeout.timeout(10) { release.pop }
        end
      end
    end
    Timeout.timeout(10) { entered.pop }
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        backend << connection.select_value("SELECT pg_backend_pid()")
        Campaigns::Launch.call(campaign: Campaign.find(@campaigns.first.id))
      end
    end
    assert_database_wait(Timeout.timeout(10) { backend.pop }, threads.last)
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    recipient = @campaigns.first.campaign_recipients.sole
    assert_equal "excluded", recipient.status
    assert_includes recipient.reasons, "refused"
    assert_nil recipient.contacted_at
    assert_equal 0, CampaignEvent.where(campaign_recipient_id: recipient.id).count
  ensure
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
  end

  test "moving a consent into the selected channel cannot bypass the launch snapshot lock" do
    @customer.consents.find_by!(channel: "email").destroy!
    consent = @customer.consents.find_by!(channel: "sms")
    entered, release, backend = Queue.new, Queue.new, Queue.new
    threads = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      if Thread.current[:consent_snapshot_probe] && event.payload[:sql].match?(/SELECT.*"consents".*FOR UPDATE/)
        entered << true
        Timeout.timeout(10) { release.pop }
      end
    end
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:consent_snapshot_probe] = true
        Campaigns::Launch.call(campaign: Campaign.find(@campaigns.first.id))
      ensure
        Thread.current[:consent_snapshot_probe] = nil
      end
    end
    Timeout.timeout(10) { entered.pop }
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        backend << connection.select_value("SELECT pg_backend_pid()")
        Consent.find(consent.id).update!(channel: "email")
        Consent.find(consent.id).update!(granted: false)
      end
    end
    assert_database_wait(Timeout.timeout(10) { backend.pop }, threads.last)
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    recipient = @campaigns.first.campaign_recipients.sole
    assert_equal "excluded", recipient.status
    assert_includes recipient.reasons, "missing_consent"
    assert_nil recipient.contacted_at
    assert_not consent.reload.granted?
  ensure
    release << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  private
    def assert_database_wait(pid, thread)
      Campaign.uncached do
        Timeout.timeout(5) do
          until Campaign.connection.select_value("SELECT cardinality(pg_blocking_pids(#{Integer(pid)})) > 0")
            assert thread.alive?, "Operation completed without waiting for the concurrent transaction"
            sleep 0.01
          end
        end
      end
    rescue Timeout::Error
      flunk "Operation did not wait on a PostgreSQL lock"
    end

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
