module Rag
  class RetrievalRouter
    RoutingResult = Struct.new(:chunks, :strategy, keyword_init: true)

    STRATEGY_NAMES = {
      "specific" => "semantic_top_k",
      "comparative" => "multi_chunk",
      "aggregation" => "exhaustive"
    }.freeze

    def initialize(semantic_search: nil, comparative_search: nil, exhaustive_search: nil)
      @semantic_search = semantic_search || Retriever.new
      @comparative_search = comparative_search || Rag::Strategies::ComparativeSearch.new(fallback: @semantic_search)
      @exhaustive_search = exhaustive_search || Rag::Strategies::ExhaustiveSearch.new(fallback: @semantic_search)
    end

    def call(question, question_type:, user:, document_id: nil, metadata: nil, top_k: nil)
      strategy = strategy_for(question_type)
      chunks = strategy.call(
        question,
        user: user,
        document_id: document_id,
        metadata: metadata,
        top_k: top_k
      )

      RoutingResult.new(chunks: chunks, strategy: STRATEGY_NAMES.fetch(normalize_type(question_type)))
    end

    private

    def strategy_for(question_type)
      case normalize_type(question_type)
      when "comparative" then @comparative_search
      when "aggregation" then @exhaustive_search
      else @semantic_search
      end
    end

    def normalize_type(question_type)
      value = question_type.respond_to?(:question_type) ? question_type.question_type : question_type
      value = value.to_s
      STRATEGY_NAMES.key?(value) ? value : "specific"
    end
  end
end
