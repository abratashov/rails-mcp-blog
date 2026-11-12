require "test_helper"

class RagContextAssemblerTest < ActiveSupport::TestCase
  Result = Struct.new(
    :document_id, :filename, :page_start, :page_end, :position,
    :content, :score, :distance, :metadata,
    keyword_init: true
  )

  test "sorts by relevance, removes duplicate chunks, and preserves source details" do
    results = [
      result(content: "Lower-ranked evidence.", position: 2, score: 0.7),
      result(
        content: "Strong evidence.",
        position: 1,
        score: 0.95,
        page_start: 4,
        page_end: 5,
        metadata: { "language" => "en" }
      ),
      result(content: "Strong evidence.", position: 1, score: 0.95)
    ]

    context = Rag::ContextAssembler.new.call(results)

    assert_equal 2, context.length
    assert_equal [ "Strong evidence.", "Lower-ranked evidence." ], context.map(&:content)
    assert_equal "1", context.first.source_id
    assert_equal "guide.txt", context.first.filename
    assert_equal [ 4, 5 ], [ context.first.page_start, context.first.page_end ]
    assert_equal({ "language" => "en" }, context.first.metadata)
    assert_includes context.first.context, "[Source 1] guide.txt (page 4-5)"
    assert_operator context.sum(&:token_count), :<=, Rag::ContextAssembler::DEFAULT_MAX_TOKENS
  end

  test "respects the context token budget" do
    context = Rag::ContextAssembler.new.call(
      [ result(content: "one two three four five six", position: 1, score: 1.0) ],
      max_tokens: 4
    )

    assert_equal 1, context.length
    assert_equal 4, context.first.token_count
    assert_equal "[Source 1] guide.txt one", context.first.context
  end

  private

  def result(content:, position:, score:, page_start: nil, page_end: nil, metadata: {})
    Result.new(
      document_id: 1,
      filename: "guide.txt",
      page_start: page_start,
      page_end: page_end,
      position: position,
      content: content,
      score: score,
      distance: 1.0 - score,
      metadata: metadata
    )
  end
end
