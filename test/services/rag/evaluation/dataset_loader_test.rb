require "test_helper"

class RagEvaluationDatasetLoaderTest < ActiveSupport::TestCase
  test "loads the fixed multilingual dataset and validates question types" do
    dataset = Rag::Evaluation::DatasetLoader.new.load("animals_v1")

    assert_equal "animals_v1", dataset.name
    assert_equal 10, dataset.questions.length
    assert_equal %w[aggregation comparative specific], dataset.questions.map { |question| question["type"] }.uniq.sort
    assert dataset.questions.any? { |question| question["language"] == "ua" }
    assert dataset.questions.any? { |question| question["language"] == "ru" }
    assert dataset.questions.any? { |question| question["insufficient_evidence"] }
    assert_equal [ "content_contains" ], dataset.questions.first["relevant_source_chunks"].first.keys
  end

  test "loads all datasets keyed by their name" do
    datasets = Rag::Evaluation::DatasetLoader.new.all

    assert_equal [ "animals_v1" ], datasets.keys
  end
end
