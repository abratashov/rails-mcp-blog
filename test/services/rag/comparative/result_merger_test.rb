require "test_helper"

class Rag::Comparative::ResultMergerTest < ActiveSupport::TestCase
  Chunk = Struct.new(:document_id, :position, :filename, :content, :score, :metadata, keyword_init: true)
  Query = Rag::Comparative::QueryBuilder::Query

  test "interleaves subject results, deduplicates by stable chunk identity, and preserves evidence metadata" do
    lion_chunk = chunk(1, 0.99, "Lion evidence")
    shared_chunk = chunk(2, 0.95, "Shared evidence")
    tiger_chunk = chunk(3, 0.80, "Tiger evidence")
    duplicate = chunk(2, 0.90, "Duplicate text for same chunk")
    query_results = [
      { query: Query.new(subject: "lions", aspect: nil, text: "lions"), results: [ lion_chunk, shared_chunk, tiger_chunk ] },
      { query: Query.new(subject: "tigers", aspect: nil, text: "tigers"), results: [ duplicate, tiger_chunk ] }
    ]

    merged = Rag::Comparative::ResultMerger.new.call(query_results)

    assert_equal [ 1, 2, 3 ], merged.map { |result| result[:position] }
    assert_equal [ 0.99, 0.90, 0.80 ], merged.map { |result| result[:score] }
    assert_equal "lions", merged.first[:metadata]["comparative_subject"]
    assert_equal "existing", merged.first[:metadata]["source"]
    assert_equal "tigers", merged.second[:metadata]["comparative_subject"]
  end

  private

  def chunk(position, score, content)
    Chunk.new(
      document_id: 7,
      position: position,
      filename: "wildlife.txt",
      content: content,
      score: score,
      metadata: { "source" => "existing" }
    )
  end
end
