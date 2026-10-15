module Campaigns
  class Eligibility
    CONTACT_INTERVAL = 7 * 24 * 60 * 60
    REASON_LABELS = {
      "missing_contact" => "Контакт для выбранного канала не указан",
      "invalid_contact" => "Контакт не соответствует формату выбранного канала",
      "missing_consent" => "Согласие по выбранному каналу не зафиксировано",
      "refused" => "Покупатель отказался от сообщений по выбранному каналу",
      "frequency_limit" => "Частотный лимит: контакт за последние 7 дней по любому каналу или некорректная будущая история"
    }.freeze
    Decision = Struct.new(:customer, :channel, :reasons, keyword_init: true) do
      def eligible?
        reasons.empty?
      end

      def contact
        channel == "email" ? customer.email : customer.phone
      end
    end

    def self.call(customer:, channel:, at:)
      unless customer.is_a?(Customer) && customer.persisted?
        raise ArgumentError, "Нужен сохранённый покупатель."
      end
      for_customers(customer_ids: [ customer.id ], channel: channel, at: at).first || raise(ActiveRecord::RecordNotFound)
    end

    def self.for_customers(customer_ids:, channel:, at:)
      unless Consent::CHANNELS.include?(channel) && (at.is_a?(Time) || at.is_a?(ActiveSupport::TimeWithZone))
        raise ArgumentError, "Нужны известный канал и точное время оценки."
      end

      Customer.where(id: customer_ids).includes(:consents, :campaign_recipients).order(:id).map do |customer|
        decision_for(customer: customer, channel: channel, at: at)
      end
    end

    def self.decision_for(customer:, channel:, at:)
      contact = channel == "email" ? customer.email : customer.phone
      reasons = []
      if contact.blank?
        reasons << "missing_contact"
      elsif !(channel == "email" ? URI::MailTo::EMAIL_REGEXP : /\A\+[1-9]\d{7,14}\z/).match?(contact)
        reasons << "invalid_contact"
      end

      consent = customer.consents.find { |record| record.channel == channel }
      if consent.nil?
        reasons << "missing_consent"
      elsif !consent.granted?
        reasons << "refused"
      end

      cutoff = at.to_time.utc - CONTACT_INTERVAL
      if customer.campaign_recipients.any? { |record| record.status == "simulated" && record.contacted_at > cutoff }
        reasons << "frequency_limit"
      end
      Decision.new(customer: customer, channel: channel, reasons: reasons.freeze)
    end
    private_class_method :decision_for
  end
end
