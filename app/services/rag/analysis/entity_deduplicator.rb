module Rag
  module Analysis
    class EntityDeduplicator
      def call(entities)
        grouped = Array(entities).group_by { |entity| identity_key(entity) }

        grouped.map do |(name, disambiguation, ambiguous_source), mentions|
          {
            name: mentions.first[:canonical_name].presence || mentions.first[:name],
            type: mentions.first[:type],
            types: mentions.map { |entity| entity[:type] }.uniq,
            mention_count: mentions.length,
            document_count: source_references(mentions).map { |source| source[:document_id] }.uniq.length,
            source_references: source_references(mentions),
            aliases: mentions.map { |entity| entity[:name] }.uniq,
            uncertain: mentions.any? { |entity| entity[:ambiguous] || entity[:confidence].to_f < confidence_threshold },
            disambiguation: disambiguation.presence,
            ambiguous: !ambiguous_source.nil?
          }
        end.sort_by { |entity| [ entity[:type], normalize(entity[:name]) ] }
      end

      private

      def identity_key(entity)
        name = normalize(entity[:canonical_name].presence || entity[:name])
        disambiguation = normalize(entity[:disambiguation])
        ambiguous_source = entity[:ambiguous] ? entity[:source_chunk_id].to_s : nil
        [ name, disambiguation, ambiguous_source ]
      end

      def source_references(mentions)
        mentions.map do |entity|
          entity.slice(:source_chunk_id, :document_id, :filename, :page_start, :page_end)
        end.uniq { |source| source[:source_chunk_id] }
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{Alnum}]+/u, " ").strip
      end

      def confidence_threshold
        @confidence_threshold ||= Float(ENV.fetch("RAG_ANALYSIS_CONFIDENCE_THRESHOLD", "0.7"))
      end
    end
  end
end
