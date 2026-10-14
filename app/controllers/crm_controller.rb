class CrmController < ApplicationController
  before_action :load_rfm

  private
    def load_rfm
      @segment_definitions = Segmentation::Rfm::RULES.fetch("segments")
      @rfm_results = Segmentation::Rfm.call
      @rfm_by_customer = @rfm_results.index_by(&:customer_id)
      @segment_counts = @rfm_results.group_by(&:segment).transform_values(&:size)
      @reference_date = Date.iso8601(Segmentation::Rfm::RULES.fetch("reference_date"))
      @window_days = Segmentation::Rfm::RULES.fetch("window_days")
    end

    def paginate(scope)
      @total_count = scope.count
      @page_count = (@total_count / 20.0).ceil
      requested_page = Integer(params[:page].to_s, exception: false) || 1
      @page = requested_page.clamp(1, [ @page_count, 1 ].max)
      scope.limit(20).offset((@page - 1) * 20)
    end
end
