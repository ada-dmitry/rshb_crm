class CampaignMetricsQuery
  Result = Struct.new(:candidate_count, :contacted_count, :excluded_count, :delivered_count, :clicked_count, :event_count, keyword_init: true) do
    def delivery_rate
      percentage(delivered_count, contacted_count)
    end

    def click_rate
      percentage(clicked_count, delivered_count)
    end

    private
      def percentage(numerator, denominator)
        (100.0 * numerator / denominator).round(1) unless denominator.zero?
      end
  end

  def self.call(campaign:)
    unless campaign.is_a?(Campaign) && campaign.persisted? && Campaign.find(campaign.id).status == "launched"
      raise ArgumentError, "Аналитика доступна только для сохранённой запущенной кампании."
    end

    # One statement provides consistent counters, DISTINCT protects denominators
    # from multiplication by the delivery/click join. Never join current orders.
    values = CampaignRecipient.where(campaign_id: campaign.id).left_joins(:campaign_events).pick(
      Arel.sql("COUNT(DISTINCT campaign_recipients.id)"),
      Arel.sql("COUNT(DISTINCT campaign_recipients.id) FILTER (WHERE campaign_recipients.status = 'simulated')"),
      Arel.sql("COUNT(DISTINCT campaign_recipients.id) FILTER (WHERE campaign_recipients.status = 'excluded')"),
      Arel.sql("COUNT(DISTINCT campaign_recipients.id) FILTER (WHERE campaign_recipients.status = 'simulated' AND campaign_events.event_type = 'delivered' AND campaign_events.source = 'simulated')"),
      Arel.sql("COUNT(DISTINCT campaign_recipients.id) FILTER (WHERE campaign_recipients.status = 'simulated' AND campaign_events.event_type = 'clicked' AND campaign_events.source = 'simulated')"),
      Arel.sql("COUNT(DISTINCT campaign_events.id)")
    )
    Result.new(**Result.members.zip(values.map(&:to_i)).to_h)
  end
end
