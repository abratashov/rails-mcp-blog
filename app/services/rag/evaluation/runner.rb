require "securerandom"

module Rag
  module Evaluation
    class Runner
      Run = Struct.new(
        :id, :dataset, :started_at, :duration_seconds, :configuration,
        :results, :metrics, :token_usage, :estimated_cost, keyword_init: true
      )

      def initialize(
        assistant: Rag::Assistant.new,
        dataset_loader: DatasetLoader.new,
        answer_evaluator: AnswerEvaluator.new,
        retrieval_evaluator: RetrievalEvaluator.new,
        configuration: nil
      )
        @assistant = assistant
        @dataset_loader = dataset_loader
        @answer_evaluator = answer_evaluator
        @retrieval_evaluator = retrieval_evaluator
        @configuration = configuration
      end

      def call(user:, dataset_name: nil, document_id: nil)
        raise ArgumentError, "An evaluation user is required" if user.blank?

        datasets = dataset_name ? { dataset_name => @dataset_loader.load(dataset_name) } : @dataset_loader.all
        datasets.values.map { |dataset| evaluate(dataset, user, document_id) }
      end

      private

      def evaluate(dataset, user, document_id)
        started_at = Time.current
        monotonic_started_at = monotonic_time
        run_id = SecureRandom.uuid
        results = dataset.questions.map do |question|
          evaluate_question(question, user, document_id)
        end
        duration = monotonic_time - monotonic_started_at
        usage = aggregate_usage(results)
        estimated_cost = estimate_cost(usage)
        Run.new(
          id: run_id,
          dataset: dataset,
          started_at: started_at,
          duration_seconds: duration,
          configuration: configuration_for(
            dataset: dataset,
            run_id: run_id,
            started_at: started_at,
            duration: duration,
            document_id: document_id
          ),
          results: results,
          metrics: summarize(results),
          token_usage: usage,
          estimated_cost: estimated_cost
        )
      end

      def evaluate_question(question, user, document_id)
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

      def summarize(results)
        by_type = results.group_by { |result| result[:type] }.transform_values do |group|
          {
            accuracy: group.count { |result| result[:status] == "PASS" }.to_f / group.length,
            pass_rate: group.count { |result| result[:status] == "PASS" }.to_f / group.length,
            quality_score: average(group.map { |result| result[:score] }),
            average_score: average(group.map { |result| result[:score] })
          }
        end
        {
          accuracy: results.count { |result| result[:status] == "PASS" }.to_f / results.length,
          average_score: average(results.map { |result| result[:score] }),
          by_type: by_type,
          pass_rate: results.count { |result| result[:status] == "PASS" }.to_f / results.length,
          quality_score: average(results.map { |result| result[:score] }),
          pass_count: results.count { |result| result[:status] == "PASS" },
          partial_count: results.count { |result| result[:status] == "PARTIAL" },
          fail_count: results.count { |result| result[:status] == "FAIL" },
          question_type_accuracy: results.count { |result| result[:question_type_correct] }.to_f / results.length
        }
      end

      def average(values)
        return 0.0 if values.empty?

        values.sum.to_f / values.length
      end

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

      def configuration_for(dataset:, run_id:, started_at:, duration:, document_id:)
        return @configuration if @configuration

        provider = ENV.fetch("LLM_PROVIDER", "vllm").to_sym
        llm = AI::PromptRunner::LLMS.fetch(provider, {})
        embedding = Retrieval::SearchConfiguration.new
        classifier_provider = ENV.fetch("QUERY_CLASSIFIER_PROVIDER", provider.to_s).to_sym
        classifier_provider_config = AI::PromptRunner::LLMS.fetch(classifier_provider, {})
        aggregation_provider = provider
        aggregation_provider_config = AI::PromptRunner::LLMS.fetch(aggregation_provider, {})
        {
          llm: {
            provider: provider,
            model: ENV["LLM_MODEL"].presence || llm[:model],
            temperature: ENV.fetch("LLM_ANSWER_CREATIVITY", "0.2").to_f,
            max_tokens: nil
          },
          classifier: {
            provider: classifier_provider,
            model: ENV["QUERY_CLASSIFIER_MODEL"].presence ||
              ENV["LLM_MODEL"].presence || classifier_provider_config[:model] || "vllm",
            confidence_threshold: ENV.fetch("QUERY_CLASSIFIER_CONFIDENCE_THRESHOLD", "0.6").to_f,
            strategy: "rules_then_llm_fallback"
          },
          aggregation: {
            provider: aggregation_provider,
            model: ENV["LLM_MODEL"].presence || aggregation_provider_config[:model],
            temperature: 0,
            max_tokens: extraction_output_tokens,
            context_window: extraction_context_window,
            max_input_tokens: effective_extraction_input_tokens,
            configured_max_input_tokens: ENV.fetch(
              "RAG_ANALYSIS_MAX_INPUT_TOKENS",
              Rag::Analysis::BatchProcessor::DEFAULT_MAX_INPUT_TOKENS.to_s
            ).to_i,
            batch_size: ENV.fetch(
              "RAG_ANALYSIS_BATCH_SIZE",
              Rag::Analysis::BatchProcessor::DEFAULT_BATCH_SIZE.to_s
            ).to_i,
            max_retries: ENV.fetch("RAG_ANALYSIS_MAX_RETRIES", "2").to_i
          },
          embedding: embedding.embedding_identity,
          retrieval: {
            strategy: "question_type_routed",
            top_k: embedding.top_k,
            comparative_top_k: ENV.fetch("RAG_COMPARATIVE_TOP_K", Rag::Strategies::ComparativeSearch::DEFAULT_TOP_K).to_i,
            threshold: embedding.threshold,
            metric: embedding.metric
          },
          dataset: dataset.name,
          document_id: document_id,
          run: {
            id: run_id,
            timestamp: started_at.iso8601,
            duration_seconds: duration
          }
        }
      end

      def extraction_output_tokens
        ENV.fetch("RAG_ANALYSIS_EXTRACTION_MAX_TOKENS", "2000").to_i
      end

      def extraction_context_window
        ENV.fetch(
          "RAG_ANALYSIS_CONTEXT_WINDOW",
          Rag::Analysis::BatchProcessor::DEFAULT_CONTEXT_WINDOW.to_s
        ).to_i
      end

      def effective_extraction_input_tokens
        Rag::Analysis::BatchProcessor.effective_input_token_limit(
          configured: ENV.fetch(
            "RAG_ANALYSIS_MAX_INPUT_TOKENS",
            Rag::Analysis::BatchProcessor::DEFAULT_MAX_INPUT_TOKENS.to_s
          ),
          output_tokens: extraction_output_tokens,
          context_window: extraction_context_window
        )
      end

      def aggregate_usage(results)
        results.each_with_object({}) do |result, totals|
          result[:token_usage].each do |key, value|
            totals[key] = totals.fetch(key, 0) + value if value.is_a?(Numeric)
          end
        end
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

      def estimate_cost(usage)
        input_rate = ENV["RAG_EVAL_INPUT_COST_PER_MILLION_TOKENS"]
        output_rate = ENV["RAG_EVAL_OUTPUT_COST_PER_MILLION_TOKENS"]
        return unless input_rate.present? && output_rate.present?

        (usage.fetch(:prompt_tokens, 0) * Float(input_rate) +
          usage.fetch(:completion_tokens, 0) * Float(output_rate)) / 1_000_000.0
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
