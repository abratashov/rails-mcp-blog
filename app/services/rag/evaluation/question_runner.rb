module Rag
  module Evaluation
    class QuestionRunner
      def initialize(assistant:, answer_evaluator:, retrieval_evaluator:)
        @assistant = assistant
        @answer_evaluator = answer_evaluator
        @retrieval_evaluator = retrieval_evaluator
      end

      def call(question, user:, document_id: nil)
        started_at = monotonic_time
        result = @assistant.call(
          question.fetch("question"),
          user: user,
          document_id: document_id,
          conversation: []
        )
        answer_metrics = @answer_evaluator.call(question, result)
        retrieval_metrics = @retrieval_evaluator.call(question, result)
        question_type = result.metadata.to_h[:question_type] || result.metadata.to_h["question_type"]
        question_type_correct = question_type.to_s == question["type"]
        comparative_coverage = if question["type"] == "comparative"
          term_coverage(
            question["comparison_term_groups"] || question["expected_term_groups"] || Array(question["comparison_terms"]),
            result.answer
          )
        end
        aggregation_metrics = aggregation_metrics_for(question, result, answer_metrics)
        scores = [
          answer_metrics[:correctness],
          retrieval_metrics[:coverage],
          retrieval_metrics[:citation_accuracy],
          retrieval_metrics[:citation_relevance]
        ]
        scores << retrieval_metrics[:faithfulness] if retrieval_metrics[:faithfulness]
        scores << retrieval_metrics[:claim_support] unless retrieval_metrics[:claim_support].nil?
        scores << comparative_coverage if comparative_coverage
        scores.concat(aggregation_metrics.values_at(:count_accuracy, :entity_accuracy)) if aggregation_metrics
        score = scores.sum.to_f / scores.length
        critical_checks = [
          answer_metrics[:correctness] >= 0.75,
          retrieval_metrics[:coverage] >= 0.5,
          retrieval_metrics[:citation_accuracy] >= 0.8,
          retrieval_metrics[:citation_relevance] >= 0.8,
          question_type_correct
        ]
        critical_checks << (retrieval_metrics[:claim_support] >= 0.8) unless retrieval_metrics[:claim_support].nil?
        critical_checks << (comparative_coverage >= 0.75) if comparative_coverage
        if aggregation_metrics
          critical_checks.concat(aggregation_metrics.values_at(:count_accuracy, :entity_accuracy).map { |value| value >= 1.0 })
          critical_checks << aggregation_metrics[:incomplete_batch_count].zero?
        end
        critical_checks << answer_metrics.dig(:concepts, :incorrect).empty?
        status = if result.error.present?
          "FAIL"
        elsif critical_checks.all?
          "PASS"
        elsif score.zero?
          "FAIL"
        else
          "PARTIAL"
        end

        {
          id: question.fetch("id"),
          type: question.fetch("type"),
          question: question.fetch("question"),
          expected_answer: question["expected_answer"],
          actual_answer: result.answer,
          status: status,
          score: score,
          latency_seconds: monotonic_time - started_at,
          timings: result.timings || {},
          token_usage: normalize_usage(result.token_usage),
          error: result.error,
          answer: answer_metrics,
          retrieval: retrieval_metrics,
          question_type_correct: question_type_correct,
          comparative_coverage: comparative_coverage,
          aggregation: aggregation_metrics,
          retrieved_sources: source_summaries(result.retrieved_chunks),
          citations: result.citations || []
        }
      rescue StandardError => error
        {
          id: question["id"],
          type: question["type"],
          question: question["question"],
          expected_answer: question["expected_answer"],
          actual_answer: nil,
          status: "FAIL",
          score: 0.0,
          latency_seconds: monotonic_time - started_at,
          timings: {},
          token_usage: {},
          error: error.message,
          answer: {},
          retrieval: {},
          question_type_correct: false,
          comparative_coverage: nil,
          aggregation: nil,
          retrieved_sources: [],
          citations: []
        }
      end

      private

      def term_coverage(terms, answer)
        return 1.0 if terms.empty?

        normalized_answer = normalize(answer)
        terms.count do |term|
          Array(term).any? { |alternative| normalized_answer.include?(normalize(alternative)) }
        end.to_f / terms.length
      end

      def aggregation_metrics_for(question, result, answer_metrics)
        return unless question["type"] == "aggregation"

        expected_count = question["expected_count"]
        expected_entities = Array(question["expected_entities"]).map { |name| normalize(name) }
        aggregation = result.metadata.to_h[:aggregation] || result.metadata.to_h["aggregation"] || {}
        actual_count = aggregation[:unique_entity_count] || aggregation["unique_entity_count"]
        actual_entities = Array(aggregation[:entities] || aggregation["entities"]).map do |entity|
          entity[:canonical_name] || entity["canonical_name"] || entity[:name] || entity["name"]
        end.compact
        count_score = expected_count.nil? ? 1.0 : (expected_count.to_i == actual_count.to_i ? 1.0 : 0.0)
        concepts = answer_metrics[:concepts] || {}
        entity_concepts = Array(question["gold_concepts"])
        expected_entity_keys = expected_entities.map { |name| entity_key(name, entity_concepts) }.uniq
        actual_entity_keys = actual_entities.map { |name| entity_key(name, entity_concepts) }.uniq
        entity_score = if expected_entity_keys.empty? && entity_concepts.any?
          concepts.fetch(:recall, 0.0)
        elsif expected_entity_keys.empty?
          1.0
        else
          intersection_size = (expected_entity_keys & actual_entity_keys).length
          union_size = (expected_entity_keys | actual_entity_keys).length
          union_size.zero? ? 1.0 : intersection_size.to_f / union_size
        end
        missing_entities = expected_entities.reject do |name|
          actual_entity_keys.include?(entity_key(name, entity_concepts))
        end
        unexpected_entities = actual_entities.reject do |name|
          expected_entity_keys.include?(entity_key(name, entity_concepts))
        end
        {
          count_accuracy: count_score,
          expected_count: expected_count,
          actual_count: actual_count,
          entity_accuracy: entity_score,
          actual_entities: actual_entities,
          missing_entities: expected_entities.any? ? missing_entities : (concepts[:missing] || []),
          unexpected_entities: unexpected_entities,
          incorrect_entities: concepts[:incorrect] || [],
          incomplete_batch_count: aggregation[:incomplete_batch_count] || aggregation["incomplete_batch_count"] || 0,
          failed_batches: Array(aggregation[:failed_batches] || aggregation["failed_batches"]).map do |failure|
            {
              batch: failure[:batch] || failure["batch"],
              chunk_ids: failure[:chunk_ids] || failure["chunk_ids"],
              attempts: failure[:attempts] || failure["attempts"],
              error: failure[:error] || failure["error"]
            }
          end
        }
      end

      def entity_key(name, concepts)
        normalized_name = normalize(name)
        concept = concepts.find do |item|
          Array(item["aliases"]).any? { |alias_name| normalize(alias_name) == normalized_name } ||
            normalize(item["id"]) == normalized_name
        end
        concept ? normalize(concept["id"]) : normalized_name
      end

      def normalize_usage(usage)
        return {} unless usage.respond_to?(:to_h)

        values = usage.to_h.symbolize_keys
        {
          prompt_tokens: values[:prompt_tokens] || values[:input_tokens],
          completion_tokens: values[:completion_tokens] || values[:output_tokens],
          total_tokens: values[:total_tokens]
        }.compact
      end

      def source_summaries(chunks)
        Array(chunks).map do |chunk|
          {
            id: read_value(chunk, :id),
            filename: read_value(chunk, :filename),
            position: read_value(chunk, :position),
            content: read_value(chunk, :content),
            score: read_value(chunk, :score)
          }
        end
      end

      def read_value(record, key)
        return record[key] if record.is_a?(Hash) && record.key?(key)
        return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
        return record.public_send(key) if record.respond_to?(key)

        nil
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{Alnum}]+/u, " ").strip
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
