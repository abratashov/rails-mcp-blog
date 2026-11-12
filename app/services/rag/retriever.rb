module Rag
  class Retriever
    def initialize(configuration: Retrieval::SearchConfiguration.new, search_service: nil)
      @configuration = configuration
      @search_service = search_service || Retrieval::SemanticSearch.new(configuration: @configuration)
    end

    def call(question, user:, document_id: nil, metadata: nil, top_k: nil)
      raise ArgumentError, "A question is required to retrieve document evidence" if question.to_s.strip.empty?
      raise ArgumentError, "A user is required to retrieve document evidence" if user.blank?

      scoped_configuration = top_k.present? ? build_configuration(top_k) : @configuration
      search_service = @search_service if @search_service.respond_to?(:call)
      search_service ||= Retrieval::SemanticSearch.new(configuration: scoped_configuration)

      search_service.call(question, user: user, document_id: document_id, metadata: metadata)
    end

    private

    def build_configuration(top_k)
      Retrieval::SearchConfiguration.new(
        embedding_configuration: @configuration.embedding_configuration,
        embedding_identity: @configuration.embedding_identity,
        top_k: top_k,
        threshold: @configuration.threshold,
        metric: @configuration.metric
      )
    end
  end
end
