require "test_helper"

class ConsentTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:Customer) && Object.const_defined?(:Consent), "Customer and Consent models are not implemented"
    @customer = Customer.create!(external_id: "test-1", name: "Покупатель")
  end

  test "defaults to refusal and records initial state timestamp" do
    freeze_time do
      consent = @customer.consents.create!(channel: "email")
      assert_equal false, consent.granted
      assert_equal Time.current, consent.changed_at
    end
  end

  test "changes timestamp only when permission actually changes" do
    consent = @customer.consents.create!(channel: "email", granted: true)
    original_time = consent.changed_at
    travel 1.day do
      consent.update!(granted: true)
      assert_equal original_time, consent.reload.changed_at
      consent.update!(granted: false)
      assert_equal Time.current.change(usec: 0), consent.reload.changed_at.change(usec: 0)
      consent.update!(granted: true)
      assert consent.reload.granted
    end
  end

  test "requires a customer a known channel and boolean permission with one consent per channel" do
    assert_not Consent.new(channel: "email").valid?
    assert_not @customer.consents.build(channel: "telegram").valid?
    assert_not @customer.consents.build(channel: "email", granted: nil).valid?
    @customer.consents.create!(channel: "email")
    assert_not @customer.consents.build(channel: "email").valid?
    assert @customer.consents.build(channel: "sms").valid?
  end

  test "failed validation followed by reverting permission preserves its original timestamp" do
    consent = @customer.consents.create!(channel: "email", granted: true)
    original_time = consent.changed_at
    travel 1.day do
      assert_not consent.update(granted: false, channel: "invalid")
      consent.update!(granted: true, channel: "email")
    end
    assert_equal original_time, consent.reload.changed_at
    assert consent.granted
  end

  test "database protects channel uniqueness boolean and timestamp" do
    consent = @customer.consents.create!(channel: "email")
    [ { channel: "telegram" }, { granted: nil }, { changed_at: nil }, { customer_id: -1 } ].each do |invalid|
      assert_raises ActiveRecord::StatementInvalid do
        Consent.transaction(requires_new: true) { consent.update_columns(invalid) }
      end
    end
    assert_raises ActiveRecord::RecordNotUnique do
      Consent.transaction(requires_new: true) do
        Consent.insert_all!([ { customer_id: @customer.id, channel: "email", granted: false, changed_at: Time.current } ])
      end
    end
  end
end
