require "yaml"

module Segmentation
  class Rfm
    RULES = YAML.safe_load_file(Rails.root.join("config/segment_rules.yml"), aliases: false).freeze
    Result = Struct.new(
      :customer_id, :last_order_at, :recency_days, :frequency, :monetary_cents,
      :r_score, :f_score, :m_score, :segment, :segment_label, :explanation, :as_of, :window_days,
      keyword_init: true
    )

    def self.call(as_of: RULES.fetch("reference_date"), window_days: RULES.fetch("window_days"))
      new(as_of: as_of, window_days: window_days).call
    end

    def initialize(as_of: RULES.fetch("reference_date"), window_days: RULES.fetch("window_days"))
      @query = RfmQuery.new(as_of: as_of, window_days: window_days)
    end

    def call
      @query.call.map { |row| classify(row) }
    end

    def classify(row)
      if row.frequency.zero?
        scores = { "r" => 0, "f" => 0, "m" => 0 }
        segment = "no_purchases"
        evidence = "Нет завершённых покупок в окне; R не определена, F=0, M=0 коп. RUB."
      else
        thresholds = RULES.fetch("thresholds")
        scores = {
          "r" => 3 - thresholds.fetch("recency_days").count { |limit| row.recency_days > limit },
          "f" => 1 + thresholds.fetch("frequency").count { |limit| row.frequency >= limit },
          "m" => 1 + thresholds.fetch("monetary_cents").count { |limit| row.monetary_cents >= limit }
        }
        rule = RULES.fetch("rules").find { |candidate| matches?(candidate, scores) }
        segment = rule.fetch("segment")
        evidence = "R=#{row.recency_days} дн., F=#{row.frequency} заказов, M=#{row.monetary_cents} коп. RUB. " \
          "Баллы R=#{scores.fetch('r')}, F=#{scores.fetch('f')}, M=#{scores.fetch('m')}; #{rule_evidence(rule)}."
      end

      definition = RULES.fetch("segments").fetch(segment)
      Result.new(
        **row.to_h, r_score: scores.fetch("r"), f_score: scores.fetch("f"), m_score: scores.fetch("m"),
        segment: segment, segment_label: definition.fetch("label"),
        explanation: "#{evidence} Правило #{segment}: #{definition.fetch('reason')} " \
          "Дата #{@query.as_of.iso8601}, окно #{@query.window_days} дн.; первое подходящее правило.",
        as_of: @query.as_of, window_days: @query.window_days
      )
    end

    private
      def matches?(rule, scores)
        rule.fetch("minimum", {}).all? { |axis, limit| scores.fetch(axis) >= limit } &&
          rule.fetch("maximum", {}).all? { |axis, limit| scores.fetch(axis) <= limit }
      end

      def rule_evidence(rule)
        conditions = rule.fetch("minimum", {}).map { |axis, limit| "#{axis.upcase}≥#{limit}" } +
          rule.fetch("maximum", {}).map { |axis, limit| "#{axis.upcase}≤#{limit}" }
        conditions.empty? ? "резервное правило" : "условия: #{conditions.join(', ')}"
      end
  end
end
