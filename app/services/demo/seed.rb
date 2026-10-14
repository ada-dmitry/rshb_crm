module Demo
  class Seed
    REFERENCE_TIME = Time.utc(2026, 10, 13, 12).freeze
    CUSTOMER_COUNT = 200
    ORDER_COUNT = 1000

    def self.call
      new.call
    end

    def call
      unless Rails.env.development? || Rails.env.test?
        raise ArgumentError, "Демоданные разрешены только в development и test."
      end

      ApplicationRecord.transaction do
        customers = (1..CUSTOMER_COUNT).map { |number| seed_customer(number) }
        buyers = customers.reject.with_index { |_, index| (index + 1) % 10 == 0 }
        (1..ORDER_COUNT).each do |number|
          seed_order(number, buyers[(number - 1) % buyers.length])
        end
      end
    end

    private
      def seed_customer(number)
        customer = Customer.find_or_create_by!(external_id: format("demo-customer-%03d", number)) do |record|
          record.name = format("Демо-покупатель %03d", number)
          record.email = format("customer%03d@example.com", number) unless number % 7 == 0
          # Deliberately non-routable contact, not a real subscriber's number.
          record.phone = format("demo-phone-%03d", number) unless number % 9 == 0
        end

        Consent::CHANNELS.each_with_index do |channel, index|
          customer.consents.find_or_create_by!(channel: channel) do |consent|
            consent.granted = (number + index) % 4 != 0
            consent.changed_at = REFERENCE_TIME - 30.days
          end
        end
        customer
      end

      def seed_order(number, customer)
        Order.find_or_create_by!(external_id: format("demo-order-%04d", number)) do |order|
          order.customer = customer
          order.total_cents = 10_000 + (number * 7_919) % 490_000
          order.status = number % 13 == 0 ? "cancelled" : "completed"
          order.ordered_at = number % 41 == 0 ? REFERENCE_TIME + 7.days : REFERENCE_TIME - (number * 17 % 450).days
        end
      end
  end
end
