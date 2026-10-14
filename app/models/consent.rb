class Consent < ApplicationRecord
  CHANNELS = %w[email sms].freeze

  belongs_to :customer

  validates :channel, inclusion: { in: CHANNELS }, uniqueness: { scope: :customer_id }
  validates :granted, inclusion: { in: [ true, false ] }
  validates :changed_at, presence: true

  before_validation :initialize_permission_time, on: :create
  before_save :record_permission_change, if: -> { persisted? && will_save_change_to_granted? }

  private
    def initialize_permission_time
      self.changed_at ||= Time.current
    end

    def record_permission_change
      self.changed_at = Time.current
    end
end
