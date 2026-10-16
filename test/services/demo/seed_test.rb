require "test_helper"

class DemoSeedTest < ActiveSupport::TestCase
  setup { assert Demo.const_defined?(:Seed), "Demo::Seed is not implemented" }

  test "loads 200 synthetic customers 1000 orders and channel-specific consents with edge cases" do
    assert_difference "Customer.count", 200 do
      assert_difference "Order.count", 1000 do
        assert_difference "Consent.count", 400 do
          Demo::Seed.call
        end
      end
    end
    assert_equal 20, Customer.where.missing(:orders).count
    assert Order.exists?(status: "cancelled")
    assert Order.exists?([ "ordered_at > ?", Demo::Seed::REFERENCE_TIME ])
    assert Order.exists?([ "ordered_at < ?", Demo::Seed::REFERENCE_TIME - 365.days ])
    assert Customer.exists?(email: nil)
    assert Customer.exists?(phone: nil)
    assert Consent.exists?(granted: false)
    assert Consent.exists?(granted: true)
    assert_equal [ "email", "sms" ], Consent.distinct.order(:channel).pluck(:channel)
    assert_equal Demo::CustomerAttributes.call(number: 1).stringify_keys,
      Customer.find_by!(external_id: "demo-customer-001").attributes.slice("name", "email", "phone")
  end

  test "restores a deleted customer with identical contacts without changing surviving rows" do
    Demo::Seed.call
    customer = Customer.find_by!(external_id: "demo-customer-010")
    original_contacts = customer.attributes.slice("name", "email", "phone")
    original_business_data = business_snapshot
    customer.destroy!
    before = database_snapshot

    assert_difference "Customer.count", 1 do
      Demo::Seed.call
    end
    assert_equal original_contacts, Customer.find_by!(external_id: "demo-customer-010").attributes.slice("name", "email", "phone")
    assert_equal original_business_data, business_snapshot
    before.each do |model, rows|
      assert_equal rows, model.where(id: rows.map { |row| row.fetch("id") }).order(:id).map(&:attributes)
    end
  end

  test "preserves existing legacy placeholder contacts" do
    customer = Customer.create!(external_id: "demo-customer-001", name: "Демо-покупатель 001",
      email: "customer001@example.com", phone: "demo-phone-001")
    before = customer.attributes
    Demo::Seed.call
    assert_equal before, customer.reload.attributes
  end

  test "SMS eligibility includes recipients and explains missing invalid and refused contacts" do
    Demo::Seed.call
    decisions = Campaigns::Eligibility.for_customers(customer_ids: Customer.ids, channel: "sms", at: Demo::Seed::REFERENCE_TIME)
    assert decisions.any?(&:eligible?)
    %w[missing_contact invalid_contact refused].each do |reason|
      assert decisions.any? { |decision| decision.reasons.include?(reason) }, "Missing exclusion: #{reason}"
    end
  end

  test "reloading preserves every existing row including edited contacts purchases refusals and sessions" do
    Demo::Seed.call
    customer = Customer.find_by!(external_id: "demo-customer-001")
    customer.update!(name: "Изменённое имя", email: nil)
    customer.orders.first.update!(total_cents: 999, status: "cancelled")
    customer.consents.find_by!(channel: "email").update!(granted: false)
    manual_customer = Customer.create!(external_id: "manual-1", name: "Вручную")
    session = users(:one).sessions.create!
    before = database_snapshot
    assert_no_difference [ "Customer.count", "Order.count", "Consent.count", "User.count", "Session.count" ] do
      Demo::Seed.call
    end
    assert_equal before, database_snapshot
    assert Customer.exists?(manual_customer.id)
    assert Session.exists?(session.id)
  end

  test "restores missing records without changing surviving records" do
    Demo::Seed.call
    Order.find_by!(external_id: "demo-order-0001").destroy!
    Consent.joins(:customer).find_by!(customers: { external_id: "demo-customer-001" }, channel: "sms").destroy!
    before = database_snapshot
    assert_difference "Order.count", 1 do
      assert_difference "Consent.count", 1 do
        assert_no_difference "Customer.count" do
          Demo::Seed.call
        end
      end
    end
    before.each do |model, rows|
      assert_equal rows, model.where(id: rows.map { |row| row.fetch("id") }).order(:id).map(&:attributes)
    end
  end

  test "fresh loads reproduce business data independently of clock and generated database ids" do
    Demo::Seed.call
    original = business_snapshot
    Consent.delete_all
    Order.delete_all
    Customer.delete_all
    travel 30.days do
      Demo::Seed.call
    end
    assert_equal original, business_snapshot
  end

  test "rejects production before writing any business data" do
    original_env = Rails.env
    Rails.env = "production"
    assert_no_difference [ "Customer.count", "Order.count", "Consent.count" ] do
      assert_raises(ArgumentError) { Demo::Seed.call }
    end
  ensure
    Rails.env = original_env
  end

  test "instance loading also rejects production before writing" do
    original_env = Rails.env
    Rails.env = "production"
    assert_no_difference [ "Customer.count", "Order.count", "Consent.count" ] do
      assert_raises(ArgumentError) { Demo::Seed.new.call }
    end
  ensure
    Rails.env = original_env
  end

  test "failure midway through loading rolls back all business writes" do
    Customer.create!(external_id: "manual-1", name: "Вручную")
    before = database_snapshot
    failing_loader = Class.new(Demo::Seed) do
      private
        def seed_order(number, customer)
          super
          raise "Controlled loading failure" if number == 2
        end
    end
    assert_raises(RuntimeError) { failing_loader.call }
    assert_equal before, database_snapshot
  end

  private
    def database_snapshot
      [ Customer, Order, Consent ].to_h { |model| [ model, model.order(:id).map(&:attributes) ] }
    end

    def business_snapshot
      {
        customers: Customer.order(:external_id).pluck(:external_id, :name, :email, :phone),
        orders: Order.joins(:customer).order(:external_id).pluck("orders.external_id", "customers.external_id", :total_cents, :status, :ordered_at),
        consents: Consent.joins(:customer).order("customers.external_id", :channel).pluck("customers.external_id", :channel, :granted, :changed_at)
      }
    end
end
