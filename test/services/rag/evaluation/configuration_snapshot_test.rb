require "test_helper"

class RagEvaluationConfigurationSnapshotTest < ActiveSupport::TestCase
  test "captures run metadata and current retrieval configuration" do
    dataset = Struct.new(:name).new("animals_v1")
    started_at = Time.zone.parse("2026-11-23T10:00:00Z")
    search_configuration = Rag::Retrieval::SearchConfiguration.new

    configuration = Rag::Evaluation::ConfigurationSnapshot.new.call(
      dataset: dataset,
      run_id: "run-123",
      started_at: started_at,
      duration: 12.5,
      document_id: 42
    )

    assert_equal "animals_v1", configuration[:dataset]
    assert_equal 42, configuration[:document_id]
    assert_equal search_configuration.embedding_identity, configuration[:embedding]
    assert_equal search_configuration.top_k, configuration.dig(:retrieval, :top_k)
    assert_equal(
      { id: "run-123", timestamp: started_at.iso8601, duration_seconds: 12.5 },
      configuration[:run]
    )
  end
end
