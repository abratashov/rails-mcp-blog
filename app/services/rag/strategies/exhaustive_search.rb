module Rag
  module Strategies
    class ExhaustiveSearch
      def initialize(fallback:)
        @fallback = fallback
      end

      def call(question, user:, document_id: nil, metadata: nil, top_k: nil)
        @fallback.call(
          question,
          user: user,
          document_id: document_id,
          metadata: metadata,
          top_k: top_k
        )
      end
    end
  end
end
