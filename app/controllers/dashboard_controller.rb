class DashboardController < CrmController
  def index
    @customer_count = @rfm_results.length
    @order_count = Order.count
    @window_revenue_cents = @rfm_results.sum(&:monetary_cents)
  end
end
