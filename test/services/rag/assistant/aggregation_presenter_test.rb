require "test_helper"

class Rag::Assistant::AggregationPresenterTest < ActiveSupport::TestCase
  test "limits aggregation source references and labels them consistently with context" do
    context = [ Struct.new(:source_chunk_id).new("chunk-1") ]
    results = {
      document_count: 2,
      unique_entity_count: 1,
      entities: [
        {
          name: "lion",
          type: "species",
          source_references: [
            { source_chunk_id: "chunk-1" },
            { source_chunk_id: "chunk-2" },
            { source_chunk_id: "chunk-3" }
          ]
        }
      ],
      facts: []
    }

    payload = Rag::Assistant::AggregationPresenter.new(max_tokens: 2_000).prompt_results(results, context)

    references = payload[:entities].sole[:source_references]
    assert_equal [ 1, 2 ], references.map { |reference| reference[:citation_label] }
    assert_equal 1, payload[:omitted_source_reference_count]
  end

  test "adds cited aggregation chunks not already present in context citations" do
    chunks = [
      Struct.new(:id, :position, :content).new("chunk-1", 1, "Existing"),
      Struct.new(:id, :position, :content).new("chunk-2", 2, "Additional")
    ]
    citations = [ { source_chunk_id: "chunk-1" } ]
    results = {
      entities: [
        {
          source_references: [
            { source_chunk_id: "chunk-1" },
            {
              source_chunk_id: "chunk-2",
              citation_label: 2,
              document_id: 7,
              filename: "guide.txt",
              page_start: 3
            }
          ]
        }
      ],
      facts: []
    }

    merged = Rag::Assistant::AggregationPresenter.new(max_tokens: 2_000)
      .append_citations(results, citations, chunks)

    assert_equal 2, merged.length
    assert_equal 2, merged.last[:label]
    assert_equal "Additional", merged.last[:content]
    assert_equal 2, merged.last[:position]
  end
end
