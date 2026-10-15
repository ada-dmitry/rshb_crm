class CampaignRecipient < ApplicationRecord
  STATUSES = %w[pending simulated failed].freeze

  belongs_to :campaign
  belongs_to :customer

  validates :customer_id, uniqueness: { scope: :campaign_id }
  validates :channel, inclusion: { in: Consent::CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :contacted_at, presence: true, if: -> { status == "simulated" }
  validates :contacted_at, absence: true, unless: -> { status == "simulated" }
end
