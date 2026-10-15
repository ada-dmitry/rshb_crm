class Campaign < ApplicationRecord
  SEGMENTS = Segmentation::Rfm::RULES.fetch("segments").keys.freeze
  OFFERS = Segmentation::Rfm::RULES.fetch("recommendations").keys.freeze
  STATUSES = %w[draft launched].freeze

  belongs_to :user
  has_many :campaign_recipients, dependent: :restrict_with_error

  attribute :reference_date, :date, default: -> { Date.iso8601(Segmentation::Rfm::RULES.fetch("reference_date")) }
  attribute :window_days, :integer, default: -> { Segmentation::Rfm::RULES.fetch("window_days") }

  validates :name, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 2000 }
  validates :segment, inclusion: { in: SEGMENTS }
  validates :offer, inclusion: { in: OFFERS }
  validates :channel, inclusion: { in: Consent::CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_at, :reference_date, presence: true
  validates :window_days, numericality: { only_integer: true, in: 1..3650 }

  def draft?
    status == "draft"
  end
end
