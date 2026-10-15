require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:Campaign), "Campaign is not implemented"
    @attributes = { user: users(:one), name: "Повторная покупка", segment: "active", offer: "repeat_purchase", body: "Проверьте наш актуальный ассортимент.", channel: "email", scheduled_at: Time.utc(2026, 10, 20, 12) }
  end

  test "defaults to draft and freezes explicit RFM inputs" do
    campaign = Campaign.create!(@attributes)
    assert campaign.draft?
    assert_equal Date.new(2026, 10, 13), campaign.reference_date
    assert_equal 365, campaign.window_days
    assert_empty campaign.campaign_recipients
  end

  test "requires known segment offer channel owner text schedule and valid window" do
    [ { user: nil }, { name: "" }, { name: "x" * 121 }, { segment: "unknown" }, { offer: "unknown" },
      { body: "" }, { body: "x" * 2001 }, { channel: "telegram" }, { scheduled_at: nil },
      { reference_date: nil }, { window_days: 0 }, { window_days: 3651 }, { window_days: 1.5 },
      { status: "sending" } ].each do |invalid|
      assert_not Campaign.new(@attributes.merge(invalid)).valid?, invalid.inspect
    end
  end

  test "database rejects unsupported channel segment offer state and analysis window" do
    campaign = Campaign.create!(@attributes)
    [ { channel: "telegram" }, { segment: "unknown" }, { offer: "unknown" }, { status: "sending" },
      { window_days: 0 }, { user_id: -1 }, { scheduled_at: nil } ].each do |invalid|
      assert_raises ActiveRecord::StatementInvalid do
        Campaign.transaction(requires_new: true) { campaign.update_columns(invalid) }
      end
    end
  end
end
