module Rag
  module Evaluation
    class ConfigurationSnapshot
      def initialize(configuration: nil)
        @configuration = configuration
      end

      def call(dataset:, run_id:, started_at:, duration:, document_id:)
        return @configuration if @configuration

        provider = ENV.fetch("LLM_PROVIDER", "vllm").to_sym
        llm = AI::PromptRunner::LLMS.fetch(provider, {})
        embedding = Rag::Retrieval::SearchConfiguration.new
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

      private

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
    end
  end
end
