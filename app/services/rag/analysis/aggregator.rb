module Rag
  module Analysis
    class Aggregator
      def initialize(entity_deduplicator: EntityDeduplicator.new)
        @entity_deduplicator = entity_deduplicator
      end

      def call(entities:, facts:, document_count:)
        unique_entities = @entity_deduplicator.call(entities)
        {
          document_count: document_count.to_i,
          unique_entity_count: unique_entities.length,
          total_mention_count: Array(entities).length,
          uncertain_entity_count: unique_entities.count { |entity| entity[:uncertain] || entity[:ambiguous] },
          entities: unique_entities.map do |entity|
            entity.merge(document_percentage: percentage(entity[:document_count], document_count))
          end,
          facts: aggregate_facts(facts)
        }
      end

      private

      def percentage(count, total)
        return 0.0 if total.to_i.zero?

        (count.to_f * 100 / total.to_i).round(1)
      end

      def aggregate_facts(facts)
        Array(facts).group_by { |fact| normalize(fact[:text]) }.map do |_key, matching_facts|
          {
            text: matching_facts.first[:text],
            source_references: matching_facts.map do |fact|
              fact.slice(:source_chunk_id, :document_id, :filename, :page_start, :page_end)
            end.uniq { |source| source[:source_chunk_id] },
            uncertain: matching_facts.any? { |fact| fact[:confidence].to_f < 0.7 }
          }
        end
      end

      def normalize(text)
        text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{Alnum}]+/u, " ").strip
      end
    end
  end
end
