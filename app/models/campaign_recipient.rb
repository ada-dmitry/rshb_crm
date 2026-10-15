class CampaignRecipient < ApplicationRecord
  STATUSES = %w[pending simulated failed excluded].freeze

  belongs_to :campaign
  belongs_to :customer
  has_many :campaign_events, dependent: :restrict_with_error

  validates :customer_id, uniqueness: { scope: :campaign_id }
  validates :channel, inclusion: { in: Consent::CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :contacted_at, presence: true, if: -> { status == "simulated" }
  validates :contacted_at, absence: true, unless: -> { status == "simulated" }

  def eligible?
    status == "simulated"
  end
end
