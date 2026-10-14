class CustomersController < CrmController
  def index
    @query = params[:q].to_s.strip.first(100)
    @selected_segment = params[:segment].to_s
    scope = Customer.order(:id)
    if @selected_segment.present?
      raise ActiveRecord::RecordNotFound unless @segment_definitions.key?(@selected_segment)
      ids = @rfm_results.select { |result| result.segment == @selected_segment }.map(&:customer_id)
      scope = scope.where(id: ids)
    end
    if @query.present?
      term = "%#{Customer.sanitize_sql_like(@query)}%"
      scope = scope.where("name ILIKE :term OR external_id ILIKE :term OR email ILIKE :term OR phone ILIKE :term", term: term)
    end
    @pagination_params = { q: @query.presence, segment: @selected_segment.presence }.compact
    @customers = paginate(scope)
  end

  def show
    @customer = Customer.find(params[:id])
    @rfm = @rfm_by_customer.fetch(@customer.id)
    @consents = @customer.consents.index_by(&:channel)
    @pagination_params = {}
    @orders = paginate(@customer.orders.order(ordered_at: :desc, id: :desc))
  end
end
