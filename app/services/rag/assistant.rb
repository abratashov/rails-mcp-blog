require "json"

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
      @default_context_limit = default_context_limit
    end

    def call(question, user:, document_id: nil, metadata: nil, conversation: [], max_context_tokens: nil, top_k: nil, progress: nil)
      raise ArgumentError, "A question is required to generate an answer" if question.to_s.strip.empty?
      raise ArgumentError, "A user is required to generate a document-grounded answer" if user.blank?

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
        classification = @query_classifier.call(question)
        routing_result = @retrieval_router.call(
          question,
          question_type: classification.question_type,
          user: user,
          document_id: document_id,
          metadata: metadata,
          top_k: top_k
        )
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
        prompt_aggregation_data = prompt_aggregation_results(aggregation_results, context)
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
            error: nil
          )
        end

        response = @answer_generator.call(prompt: prompt, conversation: conversation)
        answer = response.fetch(:text)
        citations = aggregation_results ? build_aggregation_citations(prompt_aggregation_data, context, retrieval_results) : build_citations(context)
        answer_text = decorate_with_citations(aggregation_results ? aggregation_caveat(answer, aggregation_results) : answer, citations)

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
          error: nil
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
          error: e.message
        )
      end
    end

    private

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

    def prompt_aggregation_results(results, context)
      return nil unless results

      entities = Array(results[:entities]).map do |entity|
        entity.slice(:name, :type, :mention_count, :document_count, :document_percentage, :uncertain, :ambiguous)
          .merge(source_references: Array(entity[:source_references]).first(2))
      end
      facts = Array(results[:facts]).map do |fact|
        {
          text: fact[:text].to_s.truncate(300),
          uncertain: fact[:uncertain],
          source_references: Array(fact[:source_references]).first(2)
        }
      end
      original_entity_count = entities.length
      original_fact_count = facts.length
      original_reference_count = Array(results[:entities]).sum { |entity| Array(entity[:source_references]).length } +
        Array(results[:facts]).sum { |fact| Array(fact[:source_references]).length }

      loop do
        labels = {}
        Array(context).each_with_index do |item, index|
          labels[item.source_chunk_id.to_s] = index + 1 if item.source_chunk_id.present?
        end
        references = entities.flat_map { |entity| entity[:source_references] } +
          facts.flat_map { |fact| fact[:source_references] }
        next_label = Array(context).length + 1
        references.each do |reference|
          key = reference[:source_chunk_id].to_s
          next if labels.key?(key)

          labels[key] = next_label
          next_label += 1
        end

        payload = {
          document_count: results[:document_count],
          unique_entity_count: results[:unique_entity_count],
          total_mention_count: results[:total_mention_count],
          uncertain_entity_count: results[:uncertain_entity_count],
          incomplete_batch_count: results[:incomplete_batch_count],
          incomplete_document_count: results[:incomplete_document_count],
          omitted_entity_count: original_entity_count - entities.length,
          omitted_fact_count: original_fact_count - facts.length,
          omitted_source_reference_count: original_reference_count -
            (entities.sum { |entity| entity[:source_references].length } + facts.sum { |fact| fact[:source_references].length }),
          entities: entities.map do |entity|
            entity.merge(source_references: labeled_references(entity[:source_references], labels))
          end,
          facts: facts.map do |fact|
            fact.merge(source_references: labeled_references(fact[:source_references], labels))
          end
        }
        break payload if estimated_tokens(payload) <= @aggregation_prompt_max_tokens
        break payload if entities.empty? && facts.empty?

        if facts.any?
          facts.pop
        else
          entities.pop
        end
      end
    end

    def labeled_references(references, labels)
      Array(references).map do |reference|
        reference.merge(citation_label: labels[reference[:source_chunk_id].to_s])
      end
    end

    def build_aggregation_citations(results, context, retrieved_chunks)
      citations = build_citations(context)
      existing_ids = citations.map { |citation| citation[:source_chunk_id].to_s }
      chunk_by_id = Array(retrieved_chunks).index_by { |chunk| chunk_value(chunk, :id).to_s }
      refs = Array(results[:entities]).flat_map { |entity| entity[:source_references] } +
        Array(results[:facts]).flat_map { |fact| fact[:source_references] }

      refs.uniq { |reference| reference[:source_chunk_id] }.each do |reference|
        next if existing_ids.include?(reference[:source_chunk_id].to_s)

        citations << {
          label: reference[:citation_label],
          source_chunk_id: reference[:source_chunk_id],
          document_id: reference[:document_id],
          filename: reference[:filename],
          page_start: reference[:page_start],
          page_end: reference[:page_end],
          position: chunk_value(chunk_by_id[reference[:source_chunk_id].to_s], :position),
          content: chunk_value(chunk_by_id[reference[:source_chunk_id].to_s], :content),
          score: nil,
          distance: nil
        }
      end
      citations
    end

    def estimated_tokens(value)
      text = JSON.generate(value)
      [ (text.scan(/\S+/).length * 1.5).ceil, (text.length / 3.0).ceil ].max
    end

    def aggregation_caveat(answer, results)
      caveats = [ "Counts are based on structured LLM extraction and may miss or misclassify mentions; they are not guaranteed exact." ]
      caveats << "Evidence is incomplete: #{results[:incomplete_batch_count]} extraction batch(es) failed." if results[:incomplete_batch_count].to_i.positive?
      caveats << "Evidence is incomplete: #{results[:incomplete_document_count]} document(s) could not be fully processed." if results[:incomplete_document_count].to_i.positive?
      "#{answer.strip}\n\n#{caveats.join(' ')}"
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

    def decorate_with_citations(answer, citations)
      return answer if citations.empty?

      references = citations.map { |citation| "[#{citation[:label]}] #{citation[:filename]}#{page_reference(citation)}" }.join(" | ")
      "#{answer.strip}\n\nSources: #{references}"
    end

    def page_reference(citation)
      pages = [citation[:page_start], citation[:page_end]].compact.uniq
      return "" if pages.empty?

      " (p. #{pages.join("-")})"
    end

    def build_citations(context)
      context.map.with_index(1) do |item, index|
        {
          label: index,
          source_id: item.source_id,
          source_chunk_id: item.source_chunk_id,
          document_id: item.document_id,
          filename: item.filename,
          page_start: item.page_start,
          page_end: item.page_end,
          position: item.position,
          content: item.content,
          score: item.score,
          distance: item.distance
        }
      end
    end
  end
end
