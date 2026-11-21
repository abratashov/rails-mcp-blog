module Rag
  module Evaluation
    class RetrievalEvaluator
      def call(question, result)
        retrieved = Array(result.retrieved_chunks)
        relevant = Array(question["relevant_source_chunks"])
        matches = relevant.count do |source|
          retrieved.any? { |chunk| source_matches?(source, chunk) }
        end
        retrieved_relevant = retrieved.count do |chunk|
          relevant.any? { |source| source_matches?(source, chunk) }
        end
        citations = Array(result.citations)
        retrieved_ids = retrieved.filter_map do |chunk|
          read_value(chunk, :id)&.to_s || read_value(chunk, :source_chunk_id)&.to_s
        end
        valid_citations = citations.count do |citation|
          source_id = read_value(citation, :source_chunk_id)
          source_id.present? && retrieved_ids.include?(source_id.to_s)
        end
        evidence_text = citations.map { |citation| read_value(citation, :content).to_s }.join(" ")
        expected_groups = Array(question["evidence_term_groups"])
        expected_groups = Array(question["expected_term_groups"]) if expected_groups.empty?
        expected_groups = Array(question["expected_terms"]).map { |term| [ term ] } if expected_groups.empty?
        supported_groups = expected_groups.count do |group|
          Array(group).any? { |term| normalize(evidence_text).include?(normalize(term)) }
        end
        faithfulness = if question["insufficient_evidence"] == true
          1.0
        elsif expected_groups.empty?
          nil
        else
          supported_groups.to_f / expected_groups.length
        end
        expected_claims = Array(question["gold_relations"])
        supported_claims = expected_claims.select do |claim|
          citations.any? { |citation| citation_supports_claim?(citation, claim) }
        end
        unsupported_claims = expected_claims - supported_claims
        expected_evidence_groups = Array(question["evidence_term_groups"])
        expected_evidence_groups = Array(question["expected_term_groups"]) if expected_evidence_groups.empty?
        relevant_citations = citations.count do |citation|
          relevant.any? { |source| source_matches?(source, citation) } ||
            expected_claims.any? { |claim| citation_supports_claim?(citation, claim) } ||
            (question["type"] == "aggregation" &&
              expected_evidence_groups.any? { |group| citation_supports_group?(citation, group) })
        end

        {
          relevance: retrieved.empty? ? (relevant.empty? ? 1.0 : 0.0) : retrieved_relevant.to_f / retrieved.length,
          coverage: relevant.empty? ? 1.0 : matches.to_f / relevant.length,
          relevant_chunks_found: matches,
          relevant_chunks_expected: relevant.length,
          citation_accuracy: citations.empty? ?
            (question["insufficient_evidence"] == true || retrieved.empty? ? 1.0 : 0.0) :
            valid_citations.to_f / citations.length,
          citations_valid: valid_citations,
          citations_total: citations.length,
          citations_relevant: relevant_citations,
          citation_relevance: citations.empty? ? (relevant.empty? ? 1.0 : 0.0) :
            relevant_citations.to_f / citations.length,
          faithfulness: faithfulness,
          claim_support: expected_claims.empty? ? nil : supported_claims.length.to_f / expected_claims.length,
          claims_supported: supported_claims.length,
          claims_expected: expected_claims.length,
          unsupported_claims: unsupported_claims.map { |claim| "#{claim['subject']} -> #{claim['object']}" }
        }
      end

      private

      def source_matches?(source, chunk)
        source_id = read_value(source, :id)
        return false if source_id.present? && read_value(chunk, :id).to_s != source_id.to_s

        filename = read_value(source, :filename)
        return false if filename.present? && read_value(chunk, :filename).to_s != filename.to_s

        content = read_value(source, :content_contains)
        return false if content.present? && !read_value(chunk, :content).to_s.downcase.include?(content.to_s.downcase)

        source_id.present? || filename.present? || content.present?
      end

      def normalize(text)
        text.to_s.unicode_normalize(:nfkc).downcase
      end

      def phrase_present?(text, phrase)
        normalized_text = normalize(text).gsub(/[^\p{Alnum}\p{Han}\p{Hiragana}\p{Katakana}]+/u, " ").strip
        normalized_phrase = normalize(phrase).gsub(/[^\p{Alnum}\p{Han}\p{Hiragana}\p{Katakana}]+/u, " ").strip
        return false if normalized_phrase.blank?

        normalized_text.match?(/(?:\A| )#{Regexp.escape(normalized_phrase)}(?= |\z)/)
      end

      def citation_supports_claim?(citation, claim)
        evidence_groups = Array(claim["evidence_groups"])
        return false if evidence_groups.empty?

        evidence_groups.all? do |group|
          citation_supports_group?(citation, group)
        end
      end

      def citation_supports_group?(citation, group)
        content = read_value(citation, :content)
        Array(group).any? { |term| phrase_present?(content, term) }
      end

      def read_value(record, key)
        return record[key] if record.is_a?(Hash) && record.key?(key)
        return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
        return record.public_send(key) if record.respond_to?(key)

        nil
      end
    end
  end
end
