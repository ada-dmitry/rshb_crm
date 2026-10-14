module Recommendations
  class ForSegment
    Proposal = Struct.new(:kind, :title, :reason, :channel, :timing, :requires_confirmation, keyword_init: true)

    def self.call(segment)
      rules = Segmentation::Rfm::RULES
      definition = rules.fetch("segments")[segment.to_s]
      raise ArgumentError, "Неизвестный сегмент." unless definition

      definition.fetch("recommendations").map do |kind|
        template = rules.fetch("recommendations").fetch(kind)
        Proposal.new(
          kind: kind, title: template.fetch("title"),
          reason: "#{definition.fetch('reason')} #{template.fetch('reason')}",
          channel: template.fetch("channel"), timing: template.fetch("timing"), requires_confirmation: true
        )
      end
    end
  end
end
