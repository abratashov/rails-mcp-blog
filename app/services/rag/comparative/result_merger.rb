module Rag
  module Comparative
    class ResultMerger
      def call(query_results)
        seen = {}
        merged = []
        max_results = query_results.map { |entry| entry.fetch(:results).length }.max.to_i

        max_results.times do |rank|
          query_results.each do |entry|
            result = entry.fetch(:results)[rank]
            next unless result

            key = chunk_identity(result)
            next if seen[key]

            seen[key] = true
            merged << with_comparative_metadata(result, entry.fetch(:query))
          end
        end

        merged
      end

      private

      def chunk_identity(result)
        document_id = read_value(result, :document_id)
        position = read_value(result, :position)
        return [ document_id, position ] if document_id.present? && position.present?

        source_id = read_value(result, :id) || read_value(result, :source_id)
        return [ :source, source_id ] if source_id.present?

        [ document_id, position, read_value(result, :content).to_s.strip ]
      end

      def with_comparative_metadata(result, query)
        attributes = result.respond_to?(:to_h) ? result.to_h : {}
        metadata = read_value(result, :metadata)
        attributes[:metadata] = (metadata || {}).to_h.merge(
          "comparative_subject" => query.subject,
          "comparative_aspect" => query.aspect,
          "comparative_query" => query.text
        )
        attributes
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
