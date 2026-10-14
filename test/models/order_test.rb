require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:Customer) && Object.const_defined?(:Order), "Customer and Order models are not implemented"
    @customer = Customer.create!(external_id: "test-1", name: "Покупатель")
    @attributes = { customer: @customer, external_id: "order-1", total_cents: 12345, status: "completed", ordered_at: Time.current }
  end

  test "stores an exact integer amount in kopecks and allows cancelled or future orders" do
    order = Order.create!(@attributes)
    assert_equal 12345, order.reload.total_cents
    assert Order.new(@attributes.merge(external_id: "order-2", status: "cancelled", ordered_at: 1.day.from_now)).valid?
  end

  test "requires customer timestamp identifier and valid amount and status" do
    [ { customer: nil }, { ordered_at: nil }, { external_id: nil }, { total_cents: -1 },
      { total_cents: 1.5 }, { total_cents: nil }, { status: "pending" } ].each do |invalid|
      assert_not Order.new(@attributes.merge(invalid)).valid?, invalid.inspect
    end
    Order.create!(@attributes)
    assert_not Order.new(@attributes).valid?
  end

  test "database enforces amount status uniqueness and foreign key without model validation" do
    order = Order.create!(@attributes)
    [ { total_cents: -1 }, { status: "pending" }, { customer_id: -1 } ].each do |invalid|
      assert_raises ActiveRecord::StatementInvalid do
        Order.transaction(requires_new: true) { order.update_columns(invalid) }
      end
    end
    assert_raises ActiveRecord::RecordNotUnique do
      Order.transaction(requires_new: true) do
        Order.insert_all!([ @attributes.except(:customer).merge(customer_id: @customer.id) ])
      end
    end
  end
end
