module CampaignAnalyticsHelper
  def analytics_campaign(statuses: %w[simulated], id: nil, launched: true)
    at = Time.utc(2026, 10, 21, 12)
    attributes = { user: users(:one), name: "Модель событий", segment: "no_purchases", offer: "catalog_introduction", body: "Синтетическое предложение", channel: "email", scheduled_at: at }
    attributes[:id] = id if id
    campaign = Campaign.create!(attributes)
    statuses.each_with_index do |status, index|
      external_id = "analytics-#{index + 1}"
      customer = Customer.find_or_create_by!(external_id: external_id) do |record|
        record.name = "Синтетический покупатель #{index + 1}"
        record.email = "analytics-#{index + 1}@example.com"
      end
      campaign.campaign_recipients.create!(customer: customer, channel: "email", status: status,
        contacted_at: status == "simulated" ? at : nil,
        customer_name: customer.name, customer_external_id: customer.external_id, contact: customer.email,
        reasons: status == "excluded" ? [ "refused" ] : [])
    end
    campaign.update!(status: "launched", launched_at: at) if launched
    campaign
  end

  def analytics_event(recipient, type, at: nil)
    CampaignEvent.create!(campaign_recipient: recipient, event_type: type, occurred_at: at || recipient.contacted_at + (type == "clicked" ? 20.minutes : 1.minute))
  end
end
