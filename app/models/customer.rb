class Customer < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error
  has_many :consents, dependent: :destroy

  normalizes :email, with: ->(value) { value.strip.downcase.presence }
  normalizes :phone, with: ->(value) { value.strip.presence }

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
end
