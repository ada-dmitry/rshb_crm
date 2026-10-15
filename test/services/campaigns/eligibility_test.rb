require "test_helper"

class CampaignsEligibilityTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:Campaigns), "Campaigns::Eligibility is not implemented"
    @at = Time.utc(2026, 10, 20, 12)
    @customer = Customer.create!(external_id: "eligible-1", name: "Покупатель", email: "eligible@example.com", phone: "+12025550123")
    Consent::CHANNELS.each { |channel| @customer.consents.create!(channel: channel, granted: true) }
  end

  test "allows valid contact with channel permission and no recent history" do
    %w[email sms].each do |channel|
      decision = check(channel)
      assert decision.eligible?
      assert_empty decision.reasons
    end
  end

  test "distinguishes missing contact invalid contact missing consent and explicit refusal" do
    @customer.update!(email: nil)
    assert_equal [ "missing_contact" ], check.reasons
    @customer.update_columns(email: "not-email")
    assert_equal [ "invalid_contact" ], check.reasons
    @customer.update!(email: "valid@example.com")
    consent = @customer.consents.find_by!(channel: "email")
    consent.destroy!
    assert_equal [ "missing_consent" ], check.reasons
    @customer.consents.create!(channel: "email", granted: false)
    assert_equal [ "refused" ], check.reasons
  end

  test "permissions are per channel and demo SMS contact is invalid" do
    @customer.consents.find_by!(channel: "email").update!(granted: false)
    assert check("sms").eligible?
    assert_not check.eligible?
    @customer.update!(phone: "demo-phone-001")
    assert_equal [ "invalid_contact" ], check("sms").reasons
  end

  test "shows all reasons and recent contact excludes across channels" do
    @customer.update!(email: nil)
    @customer.consents.find_by!(channel: "email").update!(granted: false)
    history(contacted_at: @at - 1.day, channel: "sms")
    assert_equal %w[missing_contact refused frequency_limit], check.reasons
    assert_not check.eligible?
  end

  test "exactly seven days is allowed but one microsecond newer is excluded" do
    record = history(contacted_at: @at - 7.days)
    assert check.eligible?
    record.update!(contacted_at: @at - 7.days + Rational(1, 1_000_000))
    assert_equal [ "frequency_limit" ], check.reasons
  end

  test "pending and failed attempts do not consume contact budget and future history fails closed" do
    history(status: "pending", contacted_at: nil)
    history(status: "failed", contacted_at: nil)
    assert check.eligible?
    history(contacted_at: @at + 1.day)
    assert_equal [ "frequency_limit" ], check.reasons
  end

  test "rejects unsupported channel and missing evaluation time" do
    assert_raises(ArgumentError) { check("telegram") }
    assert_raises(ArgumentError) { Campaigns::Eligibility.call(customer: @customer, channel: "email", at: nil) }
  end

  test "reusing a customer instance does not reuse stale contact or consent associations" do
    assert Campaigns::Eligibility.call(customer: @customer, channel: "email", at: @at).eligible?
    Customer.where(id: @customer.id).update_all(email: nil)
    Consent.where(customer_id: @customer.id, channel: "email").update_all(granted: false)
    decision = Campaigns::Eligibility.call(customer: @customer, channel: "email", at: @at)
    assert_equal %w[missing_contact refused], decision.reasons
  end

  private
    def check(channel = "email")
      @customer.reload
      Campaigns::Eligibility.call(customer: @customer, channel: channel, at: @at)
    end

    def history(contacted_at:, channel: "email", status: "simulated")
      campaign = Campaign.create!(user: users(:one), name: "История контакта", segment: "no_purchases", offer: "catalog_introduction", body: "Тест", channel: channel, scheduled_at: @at - 10.days)
      campaign.campaign_recipients.create!(customer: @customer, channel: channel, status: status, contacted_at: contacted_at)
    end
end
