require "test_helper"

class CampaignsLaunchTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 10, 21, 12)
    @campaign = Campaign.create!(user: users(:one), name: "Запуск", segment: "no_purchases", offer: "catalog_introduction", body: "Локальный пример", channel: "email", scheduled_at: @now - 1.day)
    @customer = Customer.create!(external_id: "launch-1", name: "Получатель", email: "yes@example.com", phone: "+12025550123")
    @consent = @customer.consents.create!(channel: "email", granted: true)
  end

  test "requires explicit confirmation and refuses an early launch without side effects" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    travel_to @now do
      assert_raises(Campaigns::Launch::NotReady) { launch }
      confirm
      @campaign.update!(scheduled_at: @now + 1.second)
      confirm
      assert_raises(Campaigns::Launch::NotReady) { launch }
      assert_empty @campaign.campaign_recipients
      assert @campaign.reload.draft?
    end
  end

  test "confirmation records server time and user and editing invalidates it" do
    assert_respond_to @campaign, :confirm!
    travel_to @now do
      confirm
      assert_equal @now, @campaign.confirmed_at
      assert_equal users(:two), @campaign.confirmed_by
      @campaign.update!(body: "Новая версия")
      assert_nil @campaign.confirmed_at
      assert_nil @campaign.confirmed_by_id
      assert_raises(ActiveRecord::StaleObjectError) { @campaign.confirm!(user: users(:one), version: 0) }
    end
  end

  test "rechecks revoked consent and missing current contact after preview even with stale loaded data" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    Campaigns::Preview.call(campaign: @campaign)
    @customer.consents.load
    @campaign.campaign_recipients.load
    @consent.update!(granted: false)
    Customer.where(id: @customer.id).update_all(email: nil)
    confirm
    travel_to @now do
      launch
      recipient = @campaign.campaign_recipients.reload.sole
      assert_equal "excluded", recipient.status
      assert_equal %w[missing_contact refused], recipient.reasons
      assert_nil recipient.contacted_at
      assert_nil recipient.contact
      assert_equal @now, @campaign.reload.launched_at
    end
  end

  test "uses saved RFM inputs but fresh orders to determine candidates" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    Campaigns::Preview.call(campaign: @campaign)
    @customer.orders.create!(external_id: "launch-order", ordered_at: Time.utc(2026, 10, 13), status: "completed", total_cents: 100)
    confirm
    travel_to(@now) { launch }
    assert_empty @campaign.campaign_recipients
    assert_not @campaign.reload.draft?
  end

  test "stale campaign instance cannot launch a changed and no longer confirmed draft" do
    confirm
    stale = Campaign.find(@campaign.id)
    @campaign.update!(channel: "sms")
    travel_to @now do
      assert_raises(Campaigns::Launch::NotReady) { Campaigns::Launch.call(campaign: stale) }
    end
    assert_empty @campaign.campaign_recipients
    confirm
    @customer.consents.create!(channel: "sms", granted: true)
    travel_to(@now) { Campaigns::Launch.call(campaign: stale) }
    assert_equal "sms", stale.campaign_recipients.sole.channel
    assert_equal "+12025550123", stale.campaign_recipients.sole.contact
  end

  test "uses actual launch time and the exact seven times 24 hour boundary across channels" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    history = @campaign.dup
    history.save!
    record = history.campaign_recipients.create!(customer: @customer, channel: "sms", status: "simulated", contacted_at: @now - 7.days + Rational(1, 1_000_000))
    confirm
    travel_to(@now) { launch }
    assert_equal [ "frequency_limit" ], @campaign.campaign_recipients.sole.reasons
    second = history.dup
    second.save!
    record.update!(contacted_at: @now - 7.days)
    second.confirm!(user: users(:one), version: second.lock_version)
    travel_to(@now) { Campaigns::Launch.call(campaign: second) }
    assert_equal "simulated", second.campaign_recipients.sole.status
    assert_equal @now, second.campaign_recipients.sole.contacted_at
  end

  test "launch is idempotent and persists contact and all exclusion reasons as a snapshot" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    confirm
    stale = Campaign.find(@campaign.id)
    travel_to(@now) { launch }
    original = @campaign.campaign_recipients.sole.attributes
    @customer.update!(email: "changed@example.com")
    @consent.update!(granted: false)
    assert_no_difference "CampaignRecipient.count" do
      Campaigns::Launch.call(campaign: stale)
    end
    assert_equal original, @campaign.campaign_recipients.reload.sole.attributes
    assert_equal "yes@example.com", original.fetch("contact")
    assert_equal "simulated", original.fetch("status")
  end

  test "rolls back recipients and lifecycle when simulation fails part way through" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    another = Customer.create!(external_id: "launch-2", name: "Второй", email: "second@example.com")
    another.consents.create!(channel: "email", granted: true)
    confirm
    calls = 0
    failure = ->(**arguments) do
      calls += 1
      raise "simulation failed" if calls == 2
      arguments.fetch(:recipient).update!(status: "simulated", contacted_at: @now)
    end
    assert_no_difference "CampaignRecipient.count" do
      assert_raises(RuntimeError) { travel_to(@now) { Campaigns::Launch.call(campaign: @campaign, delivery: failure) } }
    end
    assert_equal 2, calls
    assert @campaign.reload.draft?
    assert_nil @campaign.launched_at
    assert_not_nil @campaign.confirmed_at
    travel_to(@now) { launch }
    assert_equal 2, @campaign.campaign_recipients.count
  end

  test "launched campaign cannot be edited or destroyed including through a stale instance" do
    assert defined?(Campaigns::Launch), "Launch must be implemented"
    confirm
    stale = Campaign.find(@campaign.id)
    travel_to(@now) { launch }
    assert_not @campaign.update(body: "Изменено")
    assert_not @campaign.destroy
    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(body: "Устаревшее изменение") }
    assert_equal "Локальный пример", @campaign.reload.body
  end

  test "validation skipping and direct draft writes invalidate confirmation and version" do
    confirm
    version = @campaign.lock_version
    @campaign.update_attribute(:body, "Без валидации")
    assert_nil @campaign.reload.confirmed_at
    assert_operator @campaign.lock_version, :>, version
    confirm
    version = @campaign.lock_version
    @campaign.update_columns(body: "Прямая запись")
    assert_nil @campaign.reload.confirmed_at
    assert_operator @campaign.lock_version, :>, version
    assert_raises(ActiveRecord::StaleObjectError) { @campaign.confirm!(user: users(:one), version: version) }
  end

  test "launched campaigns and recipient snapshots reject validation skipping writes and deletes" do
    confirm
    travel_to(@now) { launch }
    [ -> { @campaign.update_attribute(:body, "Обход") },
      -> { @campaign.update_columns(status: "draft") },
      -> { @campaign.delete },
      -> { @campaign.campaign_recipients.sole.update!(status: "failed", contacted_at: nil) },
      -> { @campaign.campaign_recipients.sole.delete } ].each do |write|
      assert_raises(ActiveRecord::StatementInvalid) do
        Campaign.transaction(requires_new: true) { write.call }
      end
      @campaign.reload
    end
    assert_equal "launched", @campaign.reload.status
    assert_equal "simulated", @campaign.campaign_recipients.sole.status
    assert_equal [ "frequency_limit" ], Campaigns::Eligibility.call(customer: @customer, channel: "sms", at: @now).reasons - [ "missing_consent" ]
  end

  test "even an empty launched campaign cannot be deleted directly or receive new recipients" do
    @campaign.update!(segment: "sleeping")
    confirm
    travel_to(@now) { launch }
    [ -> { @campaign.delete },
      -> { @campaign.campaign_recipients.create!(customer: @customer, channel: "email") } ].each do |write|
      assert_raises(ActiveRecord::StatementInvalid) do
        Campaign.transaction(requires_new: true) { write.call }
      end
    end
  end

  private
    def confirm
      @campaign.confirm!(user: users(:two), version: @campaign.lock_version)
    end

    def launch
      Campaigns::Launch.call(campaign: @campaign)
    end
end
