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
        configuration: nil,
        question_runner: nil,
        configuration_snapshot: nil
      )
        @dataset_loader = dataset_loader
        @question_runner = question_runner || QuestionRunner.new(
          assistant: assistant,
          answer_evaluator: answer_evaluator,
          retrieval_evaluator: retrieval_evaluator
        )
        @configuration_snapshot = configuration_snapshot || ConfigurationSnapshot.new(
          configuration: configuration
        )
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
          @question_runner.call(question, user: user, document_id: document_id)
        end
        duration = monotonic_time - monotonic_started_at
        usage = aggregate_usage(results)
        estimated_cost = estimate_cost(usage)
        Run.new(
          id: run_id,
          dataset: dataset,
          started_at: started_at,
          duration_seconds: duration,
          configuration: @configuration_snapshot.call(
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

      def aggregate_usage(results)
        results.each_with_object({}) do |result, totals|
          result[:token_usage].each do |key, value|
            totals[key] = totals.fetch(key, 0) + value if value.is_a?(Numeric)
          end
        end
      end

      def estimate_cost(usage)
        input_rate = ENV["RAG_EVAL_INPUT_COST_PER_MILLION_TOKENS"]
        output_rate = ENV["RAG_EVAL_OUTPUT_COST_PER_MILLION_TOKENS"]
        return unless input_rate.present? && output_rate.present?

        (usage.fetch(:prompt_tokens, 0) * Float(input_rate) +
          usage.fetch(:completion_tokens, 0) * Float(output_rate)) / 1_000_000.0
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
