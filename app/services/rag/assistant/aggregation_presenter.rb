require "json"

module Rag
  class Assistant
    class AggregationPresenter
      def initialize(max_tokens:)
        @max_tokens = Integer(max_tokens)
        raise ArgumentError, "Aggregation answer token limit must be positive" unless @max_tokens.positive?
      end

      def prompt_results(results, context)
        return nil unless results

        entities = Array(results[:entities]).map do |entity|
          entity.slice(:name, :type, :mention_count, :document_count, :document_percentage, :uncertain, :ambiguous)
            .merge(source_references: Array(entity[:source_references]).first(2))
        end
        facts = Array(results[:facts]).map do |fact|
          {
            text: fact[:text].to_s.truncate(300),
            uncertain: fact[:uncertain],
            source_references: Array(fact[:source_references]).first(2)
          }
        end
        original_entity_count = entities.length
        original_fact_count = facts.length
        original_reference_count = Array(results[:entities]).sum { |entity| Array(entity[:source_references]).length } +
          Array(results[:facts]).sum { |fact| Array(fact[:source_references]).length }

        loop do
          labels = {}
          Array(context).each_with_index do |item, index|
            labels[item.source_chunk_id.to_s] = index + 1 if item.source_chunk_id.present?
          end
          references = entities.flat_map { |entity| entity[:source_references] } +
            facts.flat_map { |fact| fact[:source_references] }
          next_label = Array(context).length + 1
          references.each do |reference|
            key = reference[:source_chunk_id].to_s
            next if labels.key?(key)

            labels[key] = next_label
            next_label += 1
          end

          payload = {
            document_count: results[:document_count],
            unique_entity_count: results[:unique_entity_count],
            total_mention_count: results[:total_mention_count],
            uncertain_entity_count: results[:uncertain_entity_count],
            incomplete_batch_count: results[:incomplete_batch_count],
            incomplete_document_count: results[:incomplete_document_count],
            omitted_entity_count: original_entity_count - entities.length,
            omitted_fact_count: original_fact_count - facts.length,
            omitted_source_reference_count: original_reference_count -
              (entities.sum { |entity| entity[:source_references].length } + facts.sum { |fact| fact[:source_references].length }),
            entities: entities.map do |entity|
              entity.merge(source_references: labeled_references(entity[:source_references], labels))
            end,
            facts: facts.map do |fact|
              fact.merge(source_references: labeled_references(fact[:source_references], labels))
            end
          }
          break payload if estimated_tokens(payload) <= @max_tokens
          break payload if entities.empty? && facts.empty?

          if facts.any?
            facts.pop
          else
            entities.pop
          end
        end
      end

      def append_citations(results, citations, retrieved_chunks)
        existing_ids = citations.map { |citation| citation[:source_chunk_id].to_s }
        chunk_by_id = Array(retrieved_chunks).index_by { |chunk| read_value(chunk, :id).to_s }
        refs = Array(results[:entities]).flat_map { |entity| entity[:source_references] } +
          Array(results[:facts]).flat_map { |fact| fact[:source_references] }

        refs.uniq { |reference| reference[:source_chunk_id] }.each do |reference|
          next if existing_ids.include?(reference[:source_chunk_id].to_s)

          citations << {
            label: reference[:citation_label],
            source_chunk_id: reference[:source_chunk_id],
            document_id: reference[:document_id],
            filename: reference[:filename],
            page_start: reference[:page_start],
            page_end: reference[:page_end],
            position: read_value(chunk_by_id[reference[:source_chunk_id].to_s], :position),
            content: read_value(chunk_by_id[reference[:source_chunk_id].to_s], :content),
            score: nil,
            distance: nil
          }
        end
        citations
      end

      def caveat(answer, results)
        caveats = [ "Counts are based on structured LLM extraction and may miss or misclassify mentions; they are not guaranteed exact." ]
        caveats << "Evidence is incomplete: #{results[:incomplete_batch_count]} extraction batch(es) failed." if results[:incomplete_batch_count].to_i.positive?
        caveats << "Evidence is incomplete: #{results[:incomplete_document_count]} document(s) could not be fully processed." if results[:incomplete_document_count].to_i.positive?
        "#{answer.strip}\n\n#{caveats.join(' ')}"
      end

      private

      def labeled_references(references, labels)
        Array(references).map do |reference|
          reference.merge(citation_label: labels[reference[:source_chunk_id].to_s])
        end
      end

      def estimated_tokens(value)
        text = JSON.generate(value)
        [ (text.scan(/\S+/).length * 1.5).ceil, (text.length / 3.0).ceil ].max
      end

      def read_value(result, key)
        return result[key] if result.is_a?(Hash) && result.key?(key)
        return result[key.to_s] if result.is_a?(Hash) && result.key?(key.to_s)
        return result.public_send(key) if result.respond_to?(key)

        nil
      end
    end
  end
end
