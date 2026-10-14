require "test_helper"

class RfmQueryTest < ActiveSupport::TestCase
  setup do
    assert Object.const_defined?(:RfmQuery), "RfmQuery is not implemented"
    @customer = Customer.create!(external_id: "rfm-1", name: "Покупатель")
    @date = Date.new(2026, 10, 13)
  end

  test "aggregates completed purchases as exact R F and M and ignores cancellations and future orders" do
    purchase("one", Time.utc(2026, 10, 3), 12345)
    purchase("two", Time.utc(2026, 10, 10, 23, 59, 59), 20001)
    purchase("cancelled", Time.utc(2026, 10, 13), 999999, status: "cancelled")
    purchase("future", Time.utc(2026, 10, 14), 999999)
    row = RfmQuery.call(as_of: @date).sole
    assert_equal @customer.id, row.customer_id
    assert_equal Time.utc(2026, 10, 10, 23, 59, 59), row.last_order_at
    assert_equal 3, row.recency_days
    assert_equal 2, row.frequency
    assert_equal 32346, row.monetary_cents
  end

  test "includes first midnight and reference day last microsecond but excludes adjacent timestamps" do
    start_time = Time.utc(2025, 10, 14)
    purchase("before", start_time - Rational(1, 1_000_000), 100000)
    purchase("start", start_time, 100)
    purchase("last", Time.utc(2026, 10, 14) - Rational(1, 1_000_000), 200)
    purchase("after", Time.utc(2026, 10, 14), 100000)
    row = RfmQuery.call(as_of: @date, window_days: 365).sole
    assert_equal 2, row.frequency
    assert_equal 300, row.monetary_cents
    assert_equal 0, row.recency_days
  end

  test "returns every customer once including empty or ineligible purchase histories" do
    empty = Customer.create!(external_id: "rfm-2", name: "Без заказов")
    cancelled = Customer.create!(external_id: "rfm-3", name: "Отмена")
    purchase("old", Time.utc(2025, 10, 13), 100)
    cancelled.orders.create!(external_id: "cancel-2", ordered_at: Time.utc(2026, 10, 13), total_cents: 100, status: "cancelled")
    rows = RfmQuery.call(as_of: @date)
    assert_equal [ @customer.id, empty.id, cancelled.id ], rows.map(&:customer_id)
    rows.each do |row|
      assert_nil row.last_order_at
      assert_nil row.recency_days
      assert_equal 0, row.frequency
      assert_equal 0, row.monetary_cents
    end
  end

  test "accepts ISO dates and a one day window independently of current clock and app timezone" do
    purchase("today", Time.utc(2026, 10, 13), 100)
    purchase("yesterday", Time.utc(2026, 10, 12, 23, 59, 59), 200)
    original = RfmQuery.call(as_of: "2026-10-13", window_days: 1)
    travel_to Time.utc(2030, 1, 1) do
      Time.use_zone("America/Los_Angeles") do
        assert_equal original, RfmQuery.call(as_of: @date, window_days: 1)
      end
    end
    assert_equal 1, original.sole.frequency
    assert_equal 100, original.sole.monetary_cents
  end

  test "rejects invalid input instead of interpolating it into SQL" do
    [ nil, "2026-02-30", "2026-10-13'; DROP TABLE orders;--", Time.current ].each do |date|
      assert_raises(ArgumentError) { RfmQuery.call(as_of: date) }
    end
    [ nil, 0, -1, 1.5, "365", 3651 ].each do |window|
      assert_raises(ArgumentError) { RfmQuery.call(as_of: @date, window_days: window) }
    end
  end

  test "sums amounts beyond 32-bit precision without floating point" do
    purchase("large-1", Time.utc(2026, 10, 13), 5_000_000_001)
    purchase("large-2", Time.utc(2026, 10, 13), 5_000_000_002)
    assert_equal 10_000_000_003, RfmQuery.call(as_of: @date).sole.monetary_cents
  end

  private
    def purchase(id, time, cents, status: "completed")
      @customer.orders.create!(external_id: id, ordered_at: time, total_cents: cents, status: status)
    end
end
