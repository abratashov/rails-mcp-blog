module Rag
  class Assistant
    def initialize(
      retriever: nil,
      context_assembler: nil,
      prompt_builder: nil,
      answer_generator: nil,
      default_context_limit: 4_000
    )
      @retriever = retriever || Retriever.new
      @context_assembler = context_assembler || ContextAssembler.new(max_tokens: default_context_limit)
      @prompt_builder = prompt_builder || PromptBuilder.new
      @answer_generator = answer_generator || AnswerGenerator.new
      @default_context_limit = default_context_limit
    end

    def call(question, user:, document_id: nil, metadata: nil, conversation: [], max_context_tokens: nil, top_k: nil)
      raise ArgumentError, "A question is required to generate an answer" if question.to_s.strip.empty?
      raise ArgumentError, "A user is required to generate a document-grounded answer" if user.blank?

      retrieval_results = []
      context = []
      prompt = ""

      begin
        retrieval_results = @retriever.call(
          question,
          user: user,
          document_id: document_id,
          metadata: metadata,
          top_k: top_k
        )

        context = @context_assembler.call(retrieval_results, max_tokens: max_context_tokens || @default_context_limit)
        prompt = @prompt_builder.call(question: question, context: context, conversation: conversation)

        if retrieval_results.empty?
          return Rag::Result.new(
            answer: "I couldn't find enough relevant information in the uploaded documents to answer that question reliably.",
            sources: [],
            citations: [],
            retrieved_chunks: retrieval_results,
            context: context,
            prompt: prompt,
            grounded: false,
            metadata: { document_id: document_id, metadata: metadata },
            provider: @answer_generator.instance_variable_get(:@provider),
            model: @answer_generator.instance_variable_get(:@model),
            error: nil
          )
        end

        response = @answer_generator.call(prompt: prompt, conversation: conversation)
        answer = response.fetch(:text)
        citations = build_citations(context)
        answer_text = decorate_with_citations(answer, citations)

        Rag::Result.new(
          answer: answer_text,
          sources: citations,
          citations: citations,
          retrieved_chunks: retrieval_results,
          context: context,
          prompt: prompt,
          grounded: true,
          metadata: { document_id: document_id, metadata: metadata },
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
          metadata: { document_id: document_id, metadata: metadata },
          provider: @answer_generator.instance_variable_get(:@provider),
          model: @answer_generator.instance_variable_get(:@model),
          error: e.message
        )
      end
    end

    private

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
