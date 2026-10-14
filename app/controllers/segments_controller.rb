class SegmentsController < CrmController
  def show
    @segment = params[:id].to_s
    @definition = @segment_definitions[@segment]
    raise ActiveRecord::RecordNotFound unless @definition

    @segment_size = @segment_counts.fetch(@segment, 0)
    @proposals = Recommendations::ForSegment.call(@segment)
  end
end
