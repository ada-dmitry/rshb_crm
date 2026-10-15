class Campaign < ApplicationRecord
  SEGMENTS = Segmentation::Rfm::RULES.fetch("segments").keys.freeze
  OFFERS = Segmentation::Rfm::RULES.fetch("recommendations").keys.freeze
  STATUSES = %w[draft launched].freeze
  DRAFT_FIELDS = %w[name segment offer body channel scheduled_at reference_date window_days user_id].freeze

  belongs_to :user
  belongs_to :confirmed_by, class_name: "User", optional: true
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
  validate :launched_is_immutable, on: :update
  before_save :invalidate_confirmation
  before_destroy :prevent_launched_destruction

  def confirm!(user:, version:)
    reload.with_lock do
      raise ActiveRecord::StaleObjectError.new(self, "confirm") unless version == lock_version
      raise Campaigns::Launch::NotReady, "Запущенную кампанию нельзя подтверждать." unless draft?
      update!(confirmed_by: user, confirmed_at: Time.current)
    end
  end

  def draft?
    status == "draft"
  end

  private
    def invalidate_confirmation
      if persisted? && DRAFT_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
        self.confirmed_at = nil
        self.confirmed_by = nil
      end
    end

    def launched_is_immutable
      errors.add(:base, "Запущенную кампанию нельзя изменять.") if status_in_database == "launched" && has_changes_to_save?
    end

    def prevent_launched_destruction
      if status_in_database == "launched"
        errors.add(:base, "Запущенную кампанию нельзя удалять.")
        throw :abort
      end
    end
end
