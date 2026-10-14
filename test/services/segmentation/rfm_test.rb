require "test_helper"

class SegmentationRfmTest < ActiveSupport::TestCase
  setup { assert Object.const_defined?(:Segmentation), "Segmentation::Rfm is not implemented" }

  test "scores exact recency frequency and monetary threshold boundaries" do
    [ [ 0, 3 ], [ 30, 3 ], [ 31, 2 ], [ 90, 2 ], [ 91, 1 ] ].each do |days, expected|
      assert_equal expected, classify(days, 1, 0).r_score
    end
    [ [ 1, 1 ], [ 2, 2 ], [ 4, 2 ], [ 5, 3 ] ].each do |frequency, expected|
      assert_equal expected, classify(0, frequency, 0).f_score
    end
    [ [ 0, 1 ], [ 29999, 1 ], [ 30000, 2 ], [ 99999, 2 ], [ 100000, 3 ] ].each do |cents, expected|
      assert_equal expected, classify(0, 1, cents).m_score
    end
  end

  test "first matching rule wins and every purchased customer has a segment" do
    [ [ 30, 5, 100000, "champions" ], [ 31, 5, 100000, "loyal" ],
      [ 0, 5, 99999, "loyal" ], [ 91, 2, 30000, "at_risk" ],
      [ 91, 1, 100000, "sleeping" ], [ 30, 1, 30000, "new_customers" ],
      [ 31, 1, 30000, "active" ], [ 0, 2, 100000, "active" ] ].each do |days, frequency, cents, segment|
      result = classify(days, frequency, cents)
      assert_equal segment, result.segment
      assert result.segment_label.present?
      assert_includes result.explanation, "R=#{days}"
      assert_includes result.explanation, "F=#{frequency}"
      assert_includes result.explanation, "M=#{cents}"
      assert_includes result.explanation, segment
    end
    (1..3).to_a.repeated_permutation(3).each do |r, f, m|
      days = { 1 => 100, 2 => 50, 3 => 10 }.fetch(r)
      frequency = { 1 => 1, 2 => 3, 3 => 6 }.fetch(f)
      cents = { 1 => 100, 2 => 50000, 3 => 150000 }.fetch(m)
      assert classify(days, frequency, cents).segment.present?
    end
  end

  test "no eligible purchases gets its own segment with zero scores rather than invented recency" do
    result = classify(nil, 0, 0)
    assert_equal "no_purchases", result.segment
    assert_equal [ 0, 0, 0 ], [ result.r_score, result.f_score, result.m_score ]
    assert_nil result.recency_days
    assert_includes result.explanation, "Нет завершённых покупок"
  end

  test "calculation includes date window and raw metrics without persisting changes" do
    customer = Customer.create!(external_id: "segment-1", name: "Покупатель")
    customer.orders.create!(external_id: "segment-order-1", ordered_at: Time.utc(2026, 10, 13), total_cents: 12345, status: "completed")
    result = Segmentation::Rfm.call.sole
    assert_equal customer.id, result.customer_id
    assert_equal Date.new(2026, 10, 13), result.as_of
    assert_equal 365, result.window_days
    assert_equal 12345, result.monetary_cents
    assert_equal "new_customers", result.segment
    travel 1.year do
      assert_equal result, Segmentation::Rfm.call.sole
    end
    assert_equal "no_purchases", Segmentation::Rfm.call(as_of: "2026-10-14", window_days: 1).sole.segment
  end

  private
    def classify(days, frequency, cents)
      row = RfmQuery::Row.new(customer_id: 1, recency_days: days, frequency: frequency, monetary_cents: cents)
      Segmentation::Rfm.new.classify(row)
    end
end
