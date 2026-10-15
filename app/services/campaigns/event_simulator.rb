require "digest"

module Campaigns
  class EventSimulator
    VERSION = 1

    # Deterministic illustrative choices, NOT observed delivery or behavior.
    # Parent lock + unique (recipient, type) makes retries/concurrent calls safe.
    def self.call(campaign:)
      Campaign.uncached do
        Campaign.transaction do
          campaign.reload.lock!
          raise ArgumentError, "События моделируются только для запущенной кампании." if campaign.draft?

          CampaignRecipient.where(campaign_id: campaign.id, status: "simulated").order(:id).each do |recipient|
            next unless number(campaign, recipient, "delivery") % 100 < 90

            delivery_time = recipient.contacted_at + (30 + number(campaign, recipient, "delivery_delay") % 271).seconds
            record(recipient, "delivered", delivery_time)
            if number(campaign, recipient, "click") % 100 < 30
              click_time = delivery_time + (300 + number(campaign, recipient, "click_delay") % 3301).seconds
              record(recipient, "clicked", click_time)
            end
          end
        end
      end
      campaign
    end

    def self.number(campaign, recipient, purpose)
      identity = recipient.customer_external_id.presence || "customer-#{recipient.customer_id}"
      Digest::SHA256.hexdigest("crm-events-v#{VERSION}:#{campaign.id}:#{identity}:#{purpose}")[0, 16].to_i(16)
    end
    private_class_method :number

    def self.record(recipient, type, time)
      CampaignEvent.find_or_create_by!(campaign_recipient: recipient, event_type: type) do |event|
        event.occurred_at = time
        event.source = "simulated"
        event.simulation_version = VERSION
      end
    end
    private_class_method :record
  end
end
