module Campaigns
  class SimulatedDelivery
    # Local database simulation only. No transport, network or background job.
    def self.call(recipient:, at:)
      recipient.update!(status: "simulated", contacted_at: at)
    end
  end
end
