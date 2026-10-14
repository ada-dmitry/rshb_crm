class RfmQuery
  Row = Struct.new(:customer_id, :last_order_at, :recency_days, :frequency, :monetary_cents, keyword_init: true)

  attr_reader :as_of, :window_days

  def self.call(as_of:, window_days: 365)
    new(as_of: as_of, window_days: window_days).call
  end

  def initialize(as_of:, window_days: 365)
    @as_of = case as_of
    when Date then as_of.to_date
    when String then Date.iso8601(as_of)
    else raise ArgumentError, "Дата расчёта должна быть Date или строкой ISO 8601."
    end
    unless window_days.is_a?(Integer) && window_days.between?(1, 3650)
      raise ArgumentError, "Окно анализа должно содержать от 1 до 3650 целых дней."
    end
    @window_days = window_days
  end

  def call
    end_time = Time.utc(as_of.year, as_of.month, as_of.day) + 1.day
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { as_of: as_of, starts_at: end_time - window_days.days, ends_at: end_time } ])
      SELECT customers.id AS customer_id,
             MAX(orders.ordered_at) AS last_order_at,
             DATE(:as_of) - CAST(MAX(orders.ordered_at) AS date) AS recency_days,
             COUNT(orders.id) AS frequency,
             COALESCE(SUM(orders.total_cents), 0) AS monetary_cents
      FROM customers
      LEFT JOIN orders ON orders.customer_id = customers.id
                       AND orders.status = 'completed'
                       AND orders.ordered_at >= :starts_at
                       AND orders.ordered_at < :ends_at
      GROUP BY customers.id
      ORDER BY customers.id
    SQL

    ApplicationRecord.connection.select_all(sql, "RFM aggregation").map do |row|
      Row.new(
        customer_id: row.fetch("customer_id"),
        last_order_at: row.fetch("last_order_at"),
        recency_days: row.fetch("recency_days"),
        frequency: row.fetch("frequency").to_i,
        monetary_cents: row.fetch("monetary_cents").to_i
      )
    end
  end
end
