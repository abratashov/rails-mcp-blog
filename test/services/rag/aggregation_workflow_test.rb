require "test_helper"

class RagAggregationWorkflowTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @first_document = create_document(@user, "forest guide", status: "completed")
    @second_document = create_document(@user, "wildlife guide", status: "completed")
    create_chunk(@first_document, 1, "Лев и lion живуть у прайді.", 1)
    create_chunk(@second_document, 1, "Лев полює на здобич.", 3)
    create_chunk(@second_document, 2, "Lion is mentioned again.", 4)
    create_document(@user, "unprocessed guide", status: "failed", error: "Text extraction failed")

    @extractor = EntityExtractor.new
    @answer_generator = CapturingAnswerGenerator.new
    @assistant = Rag::Assistant.new(
      query_classifier: AggregationClassifier.new,
      batch_processor: Rag::Analysis::BatchProcessor.new(
        extractor: @extractor,
        batch_size: 1,
        max_retries: 0
      ),
      answer_generator: @answer_generator
    )
  end

  test "exhaustively extracts, aggregates, and cites evidence from the selected owner scope" do
    progress = []
    result = @assistant.call(
      "How many unique species and mentions are there?",
      user: @user,
      progress: ->(event) { progress << event }
    )

    assert result.grounded
    assert_equal "exhaustive", result.metadata[:retrieval_strategy]
    assert_equal 3, result.retrieved_chunks.length
    assert_equal 3, result.metadata[:document_count]
    assert_equal 1, result.metadata[:incomplete_documents].length
    assert_equal 1, result.metadata.dig(:aggregation, :unique_entity_count)
    assert_equal 3, result.metadata.dig(:aggregation, :total_mention_count)
    assert_equal 2, result.metadata.dig(:aggregation, :entities).sole[:document_count]
    assert_equal 66.7, result.metadata.dig(:aggregation, :entities).sole[:document_percentage]
    assert_equal 3, result.metadata.dig(:aggregation, :entities).sole[:source_references].length
    assert_equal 3, @extractor.calls.length
    assert_empty result.context
    assert_equal "completed", progress.last[:status]
    assert_includes @answer_generator.prompt, '"unique_entity_count": 1'
    assert_includes @answer_generator.prompt, '"total_mention_count": 3'
    assert_includes @answer_generator.prompt, '"omitted_source_reference_count": 1'
    assert_includes @answer_generator.prompt, "citation_label"
    assert_equal 2, result.citations.length
    assert_includes result.answer, "may miss or misclassify mentions"
    assert_includes result.answer, "1 document(s) could not be fully processed"
    assert_includes result.answer, "[1] forest guide.txt (p. 1)"
    assert_includes result.answer, "wildlife guide.txt"
  end

  private

  def create_document(user, contents, status:, error: nil)
    document = Document.new(user: user, status: status, processing_error: error)
    document.file.attach(io: StringIO.new(contents), filename: "#{contents}.txt", content_type: "text/plain")
    document.save!
    document
  end

  def create_chunk(document, position, content, page)
    document.document_chunks.create!(
      position: position,
      content: content,
      page_start: page,
      page_end: page
    )
  end

  class AggregationClassifier
    def call(_question)
      Rag::QueryClassifier::Classification.new(question_type: "aggregation", confidence: 0.99)
    end
  end

  class EntityExtractor
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(question:, chunks:)
      @calls << chunks.map(&:id)
      {
        entities: chunks.map do |chunk|
          {
            name: chunk.content.include?("lion") ? "lion" : "Лев",
            canonical_name: "lion",
            type: "species",
            source_chunk_id: chunk.id,
            confidence: 0.95
          }
        end,
        facts: []
      }
    end
  end

  class CapturingAnswerGenerator
    attr_reader :prompt

    def call(prompt:, conversation: [])
      @prompt = prompt
      { text: "The documents mention one unique species in six extracted occurrences.", provider: :test, model: "test-model" }
    end
  end
end
