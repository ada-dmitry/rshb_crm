module Campaigns
  class Launch
    class NotReady < StandardError; end

    # One household: serialize ALL launches, not just a campaign/customer pair.
    # Transaction-scoped, automatically released on commit/rollback. Acquire
    # before campaign locks, then re-read eligibility under READ COMMITTED.
    LAUNCH_LOCK = 7_202_610_130

    def self.call(campaign:, delivery: SimulatedDelivery)
      Campaign.uncached { perform(campaign: campaign, delivery: delivery) }
    end

    def self.perform(campaign:, delivery:)
      Campaign.transaction do
        Campaign.connection.execute("SELECT pg_advisory_xact_lock(#{LAUNCH_LOCK})")
        campaign.reload.lock!
        return campaign unless campaign.draft?

        at = Time.current
        raise NotReady, "Подтвердите текущую версию черновика." unless campaign.confirmed_at && campaign.confirmed_by_id
        raise NotReady, "Планируемое время ещё не наступило." if campaign.scheduled_at > at

        ids = Segmentation::Rfm.call(as_of: campaign.reference_date, window_days: campaign.window_days)
          .select { |result| result.segment == campaign.segment }.map(&:customer_id)
        # Protect contact rows from concurrent edits while taking the snapshot.
        Customer.where(id: ids).order(:id).lock.load
        Eligibility.for_customers(customer_ids: ids, channel: campaign.channel, at: at).each do |decision|
          recipient = campaign.campaign_recipients.create!(
            customer: decision.customer, channel: campaign.channel, contact: decision.contact,
            customer_name: decision.customer.name, customer_external_id: decision.customer.external_id,
            reasons: decision.reasons, status: decision.eligible? ? "pending" : "excluded"
          )
          delivery.call(recipient: recipient, at: at) if decision.eligible?
        end
        campaign.update!(status: "launched", launched_at: at)
        EventSimulator.call(campaign: campaign)
      end
      campaign
    end
    private_class_method :perform
  end
end
