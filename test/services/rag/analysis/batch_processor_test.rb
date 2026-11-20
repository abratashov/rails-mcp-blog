require "test_helper"

class Rag::Analysis::BatchProcessorTest < ActiveSupport::TestCase
  Chunk = Struct.new(:id, :document_id, :filename, :page_start, :page_end, :content, keyword_init: true)

  test "retries only the failed batch and does not duplicate successful batch output" do
    extractor = RetryExtractor.new
    processor = Rag::Analysis::BatchProcessor.new(
      extractor: extractor,
      batch_size: 1,
      max_input_tokens: 1_000,
      max_retries: 1,
      retry_delay: 0
    )
    progress = []

    result = processor.call(
      question: "Count species",
      chunks: [ chunk(1), chunk(2), chunk(3) ],
      progress: ->(event) { progress << event }
    )

    assert_equal [ [ "1" ], [ "2" ], [ "2" ], [ "3" ] ], extractor.calls
    assert_equal %w[1 2 3], result.entities.map { |entity| entity[:source_chunk_id].to_s }
    assert_equal 3, result.processed_batches
    assert_empty result.failed_batches
    assert_includes progress.map { |event| event[:status] }, "retrying"
    assert_equal "guide-2.txt", result.entities.second[:filename]
  end

  test "splits overlong chunks into bounded extraction windows while retaining provenance" do
    extractor = CapturingExtractor.new
    processor = Rag::Analysis::BatchProcessor.new(
      extractor: extractor,
      batch_size: 1,
      max_input_tokens: 700,
      max_retries: 0
    )
    content = (1..1_000).map { |index| "word#{index}" }.join(" ")

    result = processor.call(question: "Count", chunks: [ chunk(8, content: content) ])

    windows = extractor.calls.flatten
    assert_operator windows.length, :>, 1
    assert_equal [ 8 ], windows.map { |item| item[:id] }.uniq
    assert_equal content.split, windows.flat_map { |item| item[:content].split }
    assert_equal windows.length, result.processed_batches
  end

  test "splits long tokens and escaped markup to remain within the configured input budget" do
    extractor = CapturingExtractor.new
    processor = Rag::Analysis::BatchProcessor.new(
      extractor: extractor,
      batch_size: 1,
      max_input_tokens: 700,
      max_retries: 0
    )
    content = ("&" * 2_000) + " " + ("x" * 2_000)

    processor.call(question: "Count", chunks: [ chunk(9, content: content) ])

    windows = extractor.calls.flatten
    assert_operator windows.length, :>, 2
    windows.each do |window|
      estimated = processor.send(:estimate_tokens, CGI.escapeHTML(window[:content])) +
        processor.send(:chunk_overhead, window)
      assert_operator estimated, :<=, 700 - Rag::Analysis::BatchProcessor::PROMPT_OVERHEAD_TOKENS -
        processor.send(:estimate_tokens, "Count")
    end
  end

  test "reports a batch after all configured retry attempts fail" do
    processor = Rag::Analysis::BatchProcessor.new(
      extractor: AlwaysFailingExtractor.new,
      batch_size: 1,
      max_input_tokens: 1_000,
      max_retries: 1,
      retry_delay: 0
    )

    result = processor.call(question: "Count", chunks: [ chunk(7) ])

    assert_equal 1, result.failed_batches.length
    assert_equal 2, result.failed_batches.sole.attempts
    assert_equal [ 7 ], result.failed_batches.sole.chunk_ids
    assert_equal "provider timeout", result.failed_batches.sole.error
    assert_equal 0, result.processed_batches
  end

  test "does not keep partial batch output when validation fails before retry" do
    processor = Rag::Analysis::BatchProcessor.new(
      extractor: PartiallyMalformedExtractor.new,
      batch_size: 1,
      max_input_tokens: 1_000,
      max_retries: 1,
      retry_delay: 0
    )

    result = processor.call(question: "Count", chunks: [ chunk(5) ])

    assert_equal 1, result.entities.length
    assert_equal 5, result.entities.sole[:source_chunk_id]
    assert_empty result.failed_batches
  end

  private

  def chunk(id, content: "Lion is mentioned.")
    Chunk.new(
      id: id,
      document_id: id,
      filename: "guide-#{id}.txt",
      page_start: id,
      page_end: id,
      content: content
    )
  end

  class RetryExtractor
    attr_reader :calls

    def initialize
      @calls = []
      @retried = false
    end

    def call(question:, chunks:)
      ids = chunks.map { |item| item.id.to_s }
      @calls << ids
      if ids == [ "2" ] && !@retried
        @retried = true
        raise "rate limit"
      end

      {
        entities: chunks.map do |item|
          { source_chunk_id: item.id, name: "lion", canonical_name: "lion", type: "species", confidence: 0.9 }
        end,
        facts: []
      }
    end
  end

  class CapturingExtractor
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(question:, chunks:)
      @calls << chunks
      { entities: [], facts: [] }
    end
  end

  class AlwaysFailingExtractor
    def call(question:, chunks:)
      raise "provider timeout"
    end
  end

  class PartiallyMalformedExtractor
    def initialize
      @calls = 0
    end

    def call(question:, chunks:)
      @calls += 1
      entity = {
        source_chunk_id: chunks.first.id,
        name: "lion",
        canonical_name: "lion",
        type: "species",
        confidence: 0.9
      }
      fact = { text: "A fact", source_chunk_id: @calls == 1 ? 999 : chunks.first.id, confidence: 0.9 }
      { entities: [ entity ], facts: [ fact ] }
    end
  end
end
