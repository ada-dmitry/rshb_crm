require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  setup { assert Object.const_defined?(:Customer), "Customer model is not implemented" }

  test "customer may have no contact or orders" do
    customer = Customer.create!(external_id: "test-1", name: "Покупатель")
    assert_nil customer.email
    assert_nil customer.phone
    assert_empty customer.orders
    assert_empty customer.consents
  end

  test "normalizes optional contacts and rejects malformed email" do
    customer = Customer.new(external_id: "test-1", name: "Покупатель", email: " TEST@EXAMPLE.COM ", phone: " ")
    assert customer.valid?
    assert_equal "test@example.com", customer.email
    assert_nil customer.phone
    customer.email = "not-email"
    assert_not customer.valid?
  end

  test "requires a name and unique external identifier" do
    assert_not Customer.new.valid?
    Customer.create!(external_id: "test-1", name: "Покупатель")
    assert_not Customer.new(external_id: "test-1", name: "Другой").valid?
    assert_raises ActiveRecord::RecordNotUnique do
      Customer.transaction(requires_new: true) do
        Customer.insert_all!([ { external_id: "test-1", name: "Другой" } ])
      end
    end
  end

  test "cannot delete a customer with purchase history" do
    customer = Customer.create!(external_id: "test-1", name: "Покупатель")
    customer.orders.create!(external_id: "order-1", total_cents: 100, status: "completed", ordered_at: Time.current)
    assert_not customer.destroy
    assert Customer.exists?(customer.id)
  end
end
