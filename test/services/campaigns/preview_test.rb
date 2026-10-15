require "test_helper"

class CampaignsPreviewTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:Campaigns), "Campaigns::Preview is not implemented"
    @campaign = Campaign.create!(user: users(:one), name: "Черновик", segment: "no_purchases", offer: "catalog_introduction", body: "Пример предложения", channel: "email", scheduled_at: Time.utc(2026, 10, 20, 12))
    @allowed = Customer.create!(external_id: "preview-1", name: "Согласен", email: "yes@example.com")
    @refused = Customer.create!(external_id: "preview-2", name: "Отказ", email: "no@example.com")
    @missing = Customer.create!(external_id: "preview-3", name: "Без контакта")
    @allowed.consents.create!(channel: "email", granted: true)
    @refused.consents.create!(channel: "email", granted: false)
    @missing.consents.create!(channel: "email", granted: true)
    outside = Customer.create!(external_id: "preview-4", name: "Другой сегмент", email: "outside@example.com")
    outside.orders.create!(external_id: "preview-order-1", ordered_at: Time.utc(2026, 10, 13), total_cents: 100, status: "completed")
  end

  test "returns only segment candidates with eligibility and every exclusion reason without persisting" do
    before = snapshot
    preview = Campaigns::Preview.call(campaign: @campaign)
    assert_equal 3, preview.candidate_count
    assert_equal 1, preview.eligible_count
    assert_equal 2, preview.excluded_count
    assert_equal [ @allowed.id, @refused.id, @missing.id ], preview.entries.map { |entry| entry.customer.id }
    assert_equal [ "refused" ], preview.entries.find { |entry| entry.customer == @refused }.reasons
    assert_equal [ "missing_contact" ], preview.entries.find { |entry| entry.customer == @missing }.reasons
    assert_equal @campaign.scheduled_at, preview.evaluated_at
    assert_equal before, snapshot
  end

  test "recalculates consent and contact changes including zero reach without reserving recipients" do
    assert_equal 1, Campaigns::Preview.call(campaign: @campaign).eligible_count
    @allowed.consents.find_by!(channel: "email").update!(granted: false)
    assert_equal 0, Campaigns::Preview.call(campaign: @campaign).eligible_count
    @refused.consents.find_by!(channel: "email").update!(granted: true)
    @missing.update!(email: "restored@example.com")
    preview = Campaigns::Preview.call(campaign: @campaign)
    assert_equal 2, preview.eligible_count
    assert_equal 0, CampaignRecipient.count
    assert_equal "draft", @campaign.reload.status
  end

  test "evaluates global frequency at scheduled time and recomputes history" do
    history = Campaign.create!(user: users(:one), name: "История", segment: "no_purchases", offer: "catalog_introduction", body: "Тест", channel: "sms", scheduled_at: @campaign.scheduled_at - 10.days)
    recipient = history.campaign_recipients.create!(customer: @allowed, channel: "sms", status: "simulated", contacted_at: @campaign.scheduled_at - 6.days)
    assert_equal 0, Campaigns::Preview.call(campaign: @campaign).eligible_count
    recipient.update!(contacted_at: @campaign.scheduled_at - 7.days)
    assert_equal 1, Campaigns::Preview.call(campaign: @campaign).eligible_count
  end

  test "uses saved reference date and window and handles an empty segment" do
    @campaign.update!(segment: "new_customers")
    assert_equal 1, Campaigns::Preview.call(campaign: @campaign).candidate_count
    @campaign.update!(reference_date: Date.new(2026, 10, 14), window_days: 1)
    preview = Campaigns::Preview.call(campaign: @campaign)
    assert_equal 0, preview.candidate_count
    assert_equal 0, preview.eligible_count
    assert_empty preview.entries
  end

  test "rejects invalid campaign parameters rather than calculating unsafe reach" do
    @campaign.channel = "unknown"
    assert_raises(ArgumentError) { Campaigns::Preview.call(campaign: @campaign) }
  end

  private
    def snapshot
      [ Customer, Order, Consent, Campaign, CampaignRecipient ].map { |model| model.order(:id).map(&:attributes) }
    end
end
