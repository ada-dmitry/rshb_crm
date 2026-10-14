require "test_helper"

class RecommendationsForSegmentTest < ActiveSupport::TestCase
  setup { assert Object.const_defined?(:Recommendations), "Recommendations::ForSegment is not implemented" }

  test "every segment has deterministic actionable proposals and explicit confirmation requirement" do
    %w[no_purchases champions loyal at_risk sleeping new_customers active].each do |segment|
      proposals = Recommendations::ForSegment.call(segment)
      assert proposals.length.between?(1, 3)
      assert_equal proposals, Recommendations::ForSegment.call(segment)
      proposals.each do |proposal|
        assert proposal.title.present?
        assert proposal.reason.present?
        assert proposal.timing.present?
        assert_equal "email", proposal.channel
        assert_equal true, proposal.requires_confirmation
      end
    end
  end

  test "covers repeat purchase seasonal preorder and cross sell without suggesting repeat purchases to nonbuyers" do
    kinds = %w[champions loyal at_risk sleeping new_customers active].flat_map do |segment|
      Recommendations::ForSegment.call(segment).map(&:kind)
    end
    %w[repeat_purchase seasonal_preorder cross_sell].each { |kind| assert_includes kinds, kind }
    assert_equal [ "catalog_introduction" ], Recommendations::ForSegment.call("no_purchases").map(&:kind)
  end

  test "unknown segment is rejected and no database records or messages are created" do
    [ nil, "", "unknown" ].each do |segment|
      assert_raises(ArgumentError) { Recommendations::ForSegment.call(segment) }
    end
    assert_no_difference [ "Customer.count", "Order.count", "Consent.count" ] do
      Recommendations::ForSegment.call("champions")
    end
  end
end
