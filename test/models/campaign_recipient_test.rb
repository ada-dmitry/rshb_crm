require "test_helper"

class CampaignRecipientTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:CampaignRecipient), "CampaignRecipient is not implemented"
    @customer = Customer.create!(external_id: "recipient-1", name: "Покупатель")
    @campaign = Campaign.create!(user: users(:one), name: "Кампания", segment: "active", offer: "repeat_purchase", body: "Предложение", channel: "email", scheduled_at: Time.utc(2026, 10, 20))
    @attributes = { campaign: @campaign, customer: @customer, channel: "email", status: "simulated", contacted_at: Time.utc(2026, 10, 13) }
  end

  test "records exact contact time and allows pending or failed rows without a contact" do
    recipient = CampaignRecipient.create!(@attributes)
    assert_equal Time.utc(2026, 10, 13), recipient.reload.contacted_at
    %w[pending failed].each do |status|
      assert CampaignRecipient.new(@attributes.merge(customer: Customer.new(external_id: "other-#{status}", name: "Другой"), status: status, contacted_at: nil)).valid?
    end
  end

  test "requires customer campaign channel and consistent status timestamp" do
    [ { customer: nil }, { campaign: nil }, { channel: "telegram" }, { status: "sent" },
      { contacted_at: nil }, { status: "pending" }, { status: "failed" } ].each do |invalid|
      assert_not CampaignRecipient.new(@attributes.merge(invalid)).valid?, invalid.inspect
    end
    CampaignRecipient.create!(@attributes)
    assert_not CampaignRecipient.new(@attributes).valid?
  end

  test "database enforces uniqueness foreign keys channel and timestamp consistency" do
    recipient = CampaignRecipient.create!(@attributes)
    [ { customer_id: -1 }, { campaign_id: -1 }, { channel: "telegram" }, { status: "sent" },
      { contacted_at: nil }, { status: "pending" } ].each do |invalid|
      assert_raises ActiveRecord::StatementInvalid do
        CampaignRecipient.transaction(requires_new: true) { recipient.update_columns(invalid) }
      end
    end
    assert_raises ActiveRecord::RecordNotUnique do
      CampaignRecipient.transaction(requires_new: true) do
        CampaignRecipient.insert_all!([ @attributes.except(:campaign, :customer).merge(campaign_id: @campaign.id, customer_id: @customer.id) ])
      end
    end
    assert_not @customer.destroy
    assert_not @campaign.destroy
  end
end
