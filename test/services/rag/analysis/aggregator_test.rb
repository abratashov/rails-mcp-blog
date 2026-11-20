require "test_helper"

class Rag::Analysis::AggregatorTest < ActiveSupport::TestCase
  test "deduplicates multilingual aliases, distinguishes entity types, and calculates document statistics" do
    entities = [
      entity(name: "lion", canonical_name: "lion", type: "species", chunk_id: 1, document_id: 10),
      entity(name: "лев", canonical_name: "lion", type: "species", chunk_id: 2, document_id: 10),
      entity(name: "лев", canonical_name: "lion", type: "species", chunk_id: 3, document_id: 11),
      entity(name: "Lion", canonical_name: "lion", type: "organization", chunk_id: 4, document_id: 11)
    ]

    result = Rag::Analysis::Aggregator.new.call(entities: entities, facts: [], document_count: 4)

    lion = result[:entities].find { |item| item[:type] == "species" }
    assert_equal 2, result[:unique_entity_count]
    assert_equal 4, result[:total_mention_count]
    assert_equal 3, lion[:mention_count]
    assert_equal 2, lion[:document_count]
    assert_equal 50.0, lion[:document_percentage]
    assert_equal [ 1, 2, 3 ], lion[:source_references].map { |source| source[:source_chunk_id] }
  end

  test "keeps ambiguous identities separate and marks lower-confidence aggregates uncertain" do
    entities = [
      entity(name: "Mercury", canonical_name: "Mercury", type: "entity", chunk_id: 1, document_id: 10, ambiguous: true),
      entity(name: "Mercury", canonical_name: "Mercury", type: "entity", chunk_id: 2, document_id: 10, confidence: 0.4)
    ]

    result = Rag::Analysis::Aggregator.new.call(entities: entities, facts: [], document_count: 1)

    assert_equal 2, result[:unique_entity_count]
    assert_equal 2, result[:uncertain_entity_count]
    assert result[:entities].all? { |item| item[:uncertain] }
  end

  test "deduplicates equivalent facts while retaining every source reference" do
    facts = [
      {
        text: "Lions live in groups.",
        source_chunk_id: 1,
        document_id: 10,
        filename: "first.txt",
        page_start: 2,
        page_end: 2,
        confidence: 0.9
      },
      {
        text: " lions live in groups! ",
        source_chunk_id: 2,
        document_id: 11,
        filename: "second.txt",
        page_start: 4,
        page_end: 4,
        confidence: 0.6
      }
    ]

    result = Rag::Analysis::Aggregator.new.call(entities: [], facts: facts, document_count: 2)

    assert_equal 1, result[:facts].length
    assert_equal 2, result[:facts].sole[:source_references].length
    assert result[:facts].sole[:uncertain]
  end

  private

  def entity(name:, canonical_name:, type:, chunk_id:, document_id:, confidence: 0.9, ambiguous: false)
    {
      name: name,
      canonical_name: canonical_name,
      type: type,
      source_chunk_id: chunk_id,
      document_id: document_id,
      filename: "document-#{document_id}.txt",
      page_start: chunk_id,
      page_end: chunk_id,
      confidence: confidence,
      ambiguous: ambiguous
    }
  end
end
