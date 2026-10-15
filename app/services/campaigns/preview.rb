module Campaigns
  class Preview
    Result = Struct.new(:entries, :evaluated_at, :generated_at, keyword_init: true) do
      def candidate_count
        entries.length
      end

      def eligible_count
        entries.count(&:eligible?)
      end

      def excluded_count
        candidate_count - eligible_count
      end
    end

    def self.call(campaign:)
      raise ArgumentError, "Параметры кампании некорректны." unless campaign.valid?

      ids = Segmentation::Rfm.call(as_of: campaign.reference_date, window_days: campaign.window_days)
        .select { |result| result.segment == campaign.segment }.map(&:customer_id)
      entries = Eligibility.for_customers(customer_ids: ids, channel: campaign.channel, at: campaign.scheduled_at)
      Result.new(entries: entries.freeze, evaluated_at: campaign.scheduled_at, generated_at: Time.current)
    end
  end
end
