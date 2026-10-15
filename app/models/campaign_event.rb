class CampaignEvent < ApplicationRecord
  TYPES = %w[delivered clicked].freeze

  belongs_to :campaign_recipient

  validates :event_type, inclusion: { in: TYPES }, uniqueness: { scope: :campaign_recipient_id }
  validates :source, inclusion: { in: [ "simulated" ] }
  validates :simulation_version, inclusion: { in: [ 1 ] }
  validates :occurred_at, presence: true
  validate :modeled_contact_and_chronology

  private
    def modeled_contact_and_chronology
      recipient = campaign_recipient
      unless recipient&.status == "simulated" && recipient.campaign.status == "launched" && recipient.contacted_at
        errors.add(:campaign_recipient, "нужен симулированный контакт запущенной кампании")
        return
      end
      return unless occurred_at

      errors.add(:occurred_at, "не может быть раньше контакта") if occurred_at < recipient.contacted_at
      if event_type == "clicked" && !self.class.exists?(campaign_recipient_id: recipient.id, event_type: "delivered", occurred_at: ..occurred_at)
        errors.add(:occurred_at, "переход требует предшествующей моделируемой доставки")
      end
    end
end
