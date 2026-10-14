class Order < ApplicationRecord
  STATUSES = %w[completed cancelled].freeze

  belongs_to :customer

  validates :external_id, presence: true, uniqueness: true
  validates :ordered_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
