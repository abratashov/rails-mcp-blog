module Rag
  class Assistant
    def initialize(
      retriever: nil,
      query_classifier: nil,
      retrieval_router: nil,
      context_assembler: nil,
      prompt_builder: nil,
      answer_generator: nil,
      batch_processor: nil,
      aggregator: nil,
      aggregation_presenter: nil,
      citation_presenter: nil,
      aggregation_prompt_max_tokens: ENV.fetch("RAG_ANALYSIS_ANSWER_MAX_TOKENS", "2_000"),
      default_context_limit: 4_000
    )
      @retriever = retriever || Retriever.new
      @query_classifier = query_classifier || QueryClassifier.new
      @retrieval_router = retrieval_router || RetrievalRouter.new(semantic_search: @retriever)
      @context_assembler = context_assembler || ContextAssembler.new(max_tokens: default_context_limit)
      @prompt_builder = prompt_builder || PromptBuilder.new
      @answer_generator = answer_generator || AnswerGenerator.new
      @batch_processor = batch_processor || Analysis::BatchProcessor.new
      @aggregator = aggregator || Analysis::Aggregator.new
      @aggregation_prompt_max_tokens = Integer(aggregation_prompt_max_tokens)
      raise ArgumentError, "Aggregation answer token limit must be positive" unless @aggregation_prompt_max_tokens.positive?
      @aggregation_presenter = aggregation_presenter || Assistant::AggregationPresenter.new(
        max_tokens: @aggregation_prompt_max_tokens
      )
      @citation_presenter = citation_presenter || Assistant::CitationPresenter.new
      @default_context_limit = default_context_limit
    end

    def call(question, user:, document_id: nil, metadata: nil, conversation: [], max_context_tokens: nil, top_k: nil, progress: nil)
      raise ArgumentError, "A question is required to generate an answer" if question.to_s.strip.empty?
      raise ArgumentError, "A user is required to generate a document-grounded answer" if user.blank?

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timings = {}
      retrieval_results = []
      context = []
      prompt = ""
      classification = nil
      retrieval_strategy = nil
      retrieval_queries = nil
      incomplete_documents = []
      document_count = nil
      aggregation_results = nil
      prompt_aggregation_data = nil
      failed_batches = []

      begin
        classification_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          classification = @query_classifier.call(question)
        ensure
          timings[:classification_seconds] = elapsed_since(classification_started_at)
        end
        retrieval_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          routing_result = @retrieval_router.call(
            question,
            question_type: classification.question_type,
            user: user,
            document_id: document_id,
            metadata: metadata,
            top_k: top_k
          )
        ensure
          timings[:retrieval_seconds] = elapsed_since(retrieval_started_at)
        end
        retrieval_results = routing_result.chunks
        retrieval_strategy = routing_result.strategy
        retrieval_queries = routing_result.retrieval_queries
        incomplete_documents = routing_result.incomplete_documents || []
        document_count = routing_result.document_count

        if retrieval_strategy == "exhaustive"
          extraction = @batch_processor.call(
            question: question,
            chunks: retrieval_results,
            progress: progress
          )
          failed_batches = extraction.failed_batches
          aggregation_results = @aggregator.call(
            entities: extraction.entities,
            facts: extraction.facts,
            document_count: document_count || distinct_document_count(retrieval_results)
          )
          aggregation_results[:incomplete_batch_count] = failed_batches.length
          aggregation_results[:incomplete_document_count] = incomplete_documents.length
          aggregation_results[:failed_batches] = failed_batches.map do |failure|
            { batch: failure.batch, chunk_ids: failure.chunk_ids, attempts: failure.attempts, error: failure.error }
          end
        end

        context = if retrieval_strategy == "exhaustive"
          []
        else
          @context_assembler.call(retrieval_results, max_tokens: max_context_tokens || @default_context_limit)
        end
        prompt_aggregation_data = @aggregation_presenter.prompt_results(aggregation_results, context)
        prompt = @prompt_builder.call(
          question: question,
          context: context,
          question_type: classification.question_type,
          aggregation_results: prompt_aggregation_data
        )

        if retrieval_results.empty?
          return Rag::Result.new(
            answer: no_evidence_answer(incomplete_documents),
            sources: [],
            citations: [],
            retrieved_chunks: retrieval_results,
            context: context,
            prompt: prompt,
            grounded: false,
            metadata: result_metadata(document_id, metadata, classification, retrieval_strategy, retrieval_queries, retrieval_results, incomplete_documents, document_count, aggregation_results),
            provider: @answer_generator.instance_variable_get(:@provider),
            model: @answer_generator.instance_variable_get(:@model),
            error: nil,
            timings: timings.merge(total_seconds: elapsed_since(started_at)),
            token_usage: nil
          )
        end

        generation_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          response = @answer_generator.call(prompt: prompt, conversation: conversation)
        ensure
          timings[:generation_seconds] = elapsed_since(generation_started_at)
        end
        answer = response.fetch(:text)
        answer = answer.to_s.sub(/\n{0,2}Sources:\s.*\z/im, "").strip
        citations = @citation_presenter.build_citations(context)
        if aggregation_results
          citations = @aggregation_presenter.append_citations(
            prompt_aggregation_data,
            citations,
            retrieval_results
          )
        end
        citations = @citation_presenter.citations_used_by(answer, citations)
        answer_text = @citation_presenter.decorate_with_citations(
          aggregation_results ? @aggregation_presenter.caveat(answer, aggregation_results) : answer,
          citations
        )

        Rag::Result.new(
          answer: answer_text,
          sources: citations,
          citations: citations,
          retrieved_chunks: retrieval_results,
          context: context,
          prompt: prompt,
          grounded: true,
          metadata: result_metadata(document_id, metadata, classification, retrieval_strategy, retrieval_queries, retrieval_results, incomplete_documents, document_count, aggregation_results),
          provider: response[:provider],
          model: response[:model],
          error: nil,
          timings: timings.merge(total_seconds: elapsed_since(started_at)),
          token_usage: response[:usage]
        )
      rescue StandardError => e
        Rag::Result.new(
          answer: "I couldn't generate a grounded answer because the document retrieval or LLM response failed.",
          sources: [],
          citations: [],
          retrieved_chunks: retrieval_results || [],
          context: context || [],
          prompt: prompt || "",
          grounded: false,
          metadata: result_metadata(document_id, metadata, classification, retrieval_strategy, retrieval_queries, retrieval_results, incomplete_documents, document_count, aggregation_results),
          provider: @answer_generator.instance_variable_get(:@provider),
          model: @answer_generator.instance_variable_get(:@model),
          error: e.message,
          timings: timings.merge(total_seconds: elapsed_since(started_at)),
          token_usage: nil
        )
      end
    end

    private

    def elapsed_since(started_at)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end

    def result_metadata(document_id, metadata, classification, retrieval_strategy, retrieval_queries = nil, retrieval_results = [], incomplete_documents = [], document_count = nil, aggregation_results = nil)
      {
        document_id: document_id,
        metadata: metadata,
        question_type: classification&.question_type || "specific",
        classification_confidence: classification&.confidence,
        classification_error: classification&.error,
        retrieval_strategy: retrieval_strategy || "semantic_top_k",
        retrieval_queries: retrieval_queries,
        selected_chunks: selected_chunk_references(retrieval_results),
        document_count: document_count,
        incomplete_documents: incomplete_documents,
        aggregation: aggregation_results
      }
    end

    def distinct_document_count(results)
      Array(results).map { |chunk| chunk_value(chunk, :document_id) }.compact.uniq.length
    end

    def no_evidence_answer(incomplete_documents)
      response = "I couldn't find enough relevant information in the uploaded documents to answer that question reliably."
      return response if incomplete_documents.empty?

      "#{response} Evidence is incomplete because #{incomplete_documents.length} selected document(s) could not be fully processed."
    end

    def selected_chunk_references(results)
      Array(results).map do |chunk|
        {
          document_id: chunk_value(chunk, :document_id),
          filename: chunk_value(chunk, :filename),
          position: chunk_value(chunk, :position),
          score: chunk_value(chunk, :score)
        }
      end
    end

    def chunk_value(chunk, key)
      return chunk[key] if chunk.is_a?(Hash) && chunk.key?(key)
      return chunk[key.to_s] if chunk.is_a?(Hash) && chunk.key?(key.to_s)
      return chunk.public_send(key) if chunk.respond_to?(key)

      nil
    end
  end
end
