require "test_helper"

class RagEvaluationRunnerTest < ActiveSupport::TestCase
  Chunk = Struct.new(:id, :filename, :position, :content, :score, keyword_init: true)

  setup do
    @user = users(:one)
    @dataset = Rag::Evaluation::DatasetLoader::Dataset.new(
      name: "test_v1",
      questions: [
        {
          "id" => "lion",
          "type" => "specific",
          "question" => "Where do lions live?",
          "expected_answer" => "Lions live in prides.",
          "expected_terms" => %w[lions prides],
          "relevant_source_chunks" => [ { "content_contains" => "Lions live in prides." } ]
        },
        {
          "id" => "failure",
          "type" => "specific",
          "question" => "What failed?",
          "expected_answer" => "No answer",
          "expected_terms" => [ "answer" ]
        }
      ]
    )
  end

  test "runs selected datasets, continues after failed questions, and records configuration and metrics" do
    runner = Rag::Evaluation::Runner.new(
      assistant: FakeAssistant.new,
      dataset_loader: FakeDatasetLoader.new(@dataset),
      configuration: {
        llm: { provider: "test", model: "fake" },
        embedding: { provider: "test", model: "fake", dimensions: 3 },
        retrieval: { strategy: "semantic", top_k: 2 },
        dataset: "test_v1",
        run: { timestamp: Time.current.iso8601 }
      }
    )

    runs = runner.call(user: @user, dataset_name: "test_v1")
    run = runs.first

    assert_equal 1, runs.length
    assert_equal "test_v1", run.dataset.name
    assert_equal 2, run.results.length
    assert_equal "PASS", run.results.first[:status]
    assert_equal "FAIL", run.results.last[:status]
    assert_equal 0.5, run.metrics[:accuracy]
    assert_equal 10, run.token_usage[:total_tokens]
    assert_equal "fake", run.configuration.dig(:llm, :model)
    assert run.id.present?
    assert run.duration_seconds >= 0
  end

  test "rejects a missing evaluation user" do
    runner = Rag::Evaluation::Runner.new(
      assistant: FakeAssistant.new,
      dataset_loader: FakeDatasetLoader.new(@dataset)
    )

    assert_raises(ArgumentError) { runner.call(user: nil, dataset_name: "test_v1") }
  end

  test "restricts each assistant call to the requested document" do
    assistant = FakeAssistant.new
    runner = Rag::Evaluation::Runner.new(
      assistant: assistant,
      dataset_loader: FakeDatasetLoader.new(@dataset),
      configuration: {}
    )

    runner.call(user: @user, dataset_name: "test_v1", document_id: 42)

    assert_equal [ 42, 42 ], assistant.document_ids
  end

  test "scores grouped comparative terms without raising" do
    dataset = Rag::Evaluation::DatasetLoader::Dataset.new(
      name: "comparative_v1",
      questions: [
        {
          "id" => "compare",
          "type" => "comparative",
          "question" => "Compare lions and tigers.",
          "expected_answer" => "Lions live in prides, while tigers are solitary.",
          "expected_term_groups" => [ %w[lion lions], %w[pride prides], %w[tiger tigers], %w[solitary alone] ],
          "comparison_term_groups" => [ %w[lion lions], %w[pride prides], %w[tiger tigers], %w[solitary alone] ],
          "relevant_source_chunks" => []
        }
      ]
    )
    runner = Rag::Evaluation::Runner.new(
      assistant: FakeAssistant.new,
      dataset_loader: FakeDatasetLoader.new(dataset),
      configuration: {}
    )

    result = runner.call(user: @user, dataset_name: "comparative_v1").first.results.first

    assert_nil result[:error]
    assert_equal 0.5, result[:comparative_coverage]
  end

  test "scores aggregation entities from extracted results rather than the generated answer" do
    dataset = Rag::Evaluation::DatasetLoader::Dataset.new(
      name: "aggregation_v1",
      questions: [
        {
          "id" => "count_species",
          "type" => "aggregation",
          "question" => "How many species are there?",
          "expected_answer" => "Two species: lion and tiger.",
          "expected_terms" => %w[two lion tiger],
          "expected_count" => 2,
          "expected_entities" => %w[lion tiger],
          "gold_concepts" => [
            { "id" => "lion", "aliases" => %w[lion лев] },
            { "id" => "tiger", "aliases" => %w[tiger тигр] }
          ],
          "relevant_source_chunks" => []
        }
      ]
    )
    assistant = Struct.new(:result) do
      def call(*, **)
        result
      end
    end.new(
      Rag::Result.new(
        answer: "The answer could not be generated.",
        retrieved_chunks: [],
        citations: [],
        grounded: false,
        metadata: {
          question_type: "aggregation",
          aggregation: {
            unique_entity_count: 2,
            entities: [
              { canonical_name: "Lion" },
              { canonical_name: "Тигр" }
            ],
            incomplete_batch_count: 0,
            failed_batches: []
          }
        }
      )
    )
    runner = Rag::Evaluation::Runner.new(
      assistant: assistant,
      dataset_loader: FakeDatasetLoader.new(dataset),
      configuration: {}
    )

    result = runner.call(user: @user, dataset_name: "aggregation_v1").first.results.first

    assert_equal 1.0, result.dig(:aggregation, :entity_accuracy)
    assert_empty result.dig(:aggregation, :missing_entities)
    assert_empty result.dig(:aggregation, :unexpected_entities)
  end

  test "preserves incomplete aggregation batch details in per-question results" do
    dataset = Rag::Evaluation::DatasetLoader::Dataset.new(
      name: "aggregation_v1",
      questions: [
        {
          "id" => "count_species",
          "type" => "aggregation",
          "question" => "How many species are there?",
          "expected_count" => 6,
          "expected_entities" => %w[lion tiger],
          "expected_term_groups" => [ %w[six 6], %w[lion tiger] ],
          "gold_concepts" => [
            { "id" => "lion", "aliases" => [ "lion" ] },
            { "id" => "tiger", "aliases" => [ "tiger" ] }
          ],
          "relevant_source_chunks" => []
        }
      ]
    )
    assistant = Struct.new(:result) do
      def call(*, **)
        result
      end
    end.new(
      Rag::Result.new(
        answer: "A reliable total cannot be determined.",
        retrieved_chunks: [],
        citations: [],
        grounded: true,
        metadata: {
          question_type: "aggregation",
          aggregation: {
            unique_entity_count: 0,
            entities: [],
            incomplete_batch_count: 1,
            failed_batches: [
              { batch: 1, chunk_ids: [ 14, 15 ], attempts: 3, error: "provider timeout" }
            ]
          }
        }
      )
    )
    runner = Rag::Evaluation::Runner.new(
      assistant: assistant,
      dataset_loader: FakeDatasetLoader.new(dataset),
      configuration: {}
    )

    result = runner.call(user: @user, dataset_name: "aggregation_v1").first.results.first

    assert_equal 1, result.dig(:aggregation, :incomplete_batch_count)
    assert_equal 6, result.dig(:aggregation, :expected_count)
    assert_equal 0, result.dig(:aggregation, :actual_count)
    assert_equal 0.0, result.dig(:aggregation, :count_accuracy)
    assert_equal 0.0, result.dig(:aggregation, :entity_accuracy)
    assert_equal "provider timeout", result.dig(:aggregation, :failed_batches, 0, :error)
    assert_equal [ 14, 15 ], result.dig(:aggregation, :failed_batches, 0, :chunk_ids)
    assert_equal "PARTIAL", result[:status]
  end

  private

  class FakeDatasetLoader
    def initialize(dataset)
      @dataset = dataset
    end

    def load(_name)
      @dataset
    end

    def all
      { @dataset.name => @dataset }
    end
  end

  class FakeAssistant
    attr_reader :document_ids

    def initialize
      @document_ids = []
    end

    def call(question, user:, conversation:, document_id: nil)
      raise "unexpected question" unless user.present? && conversation.empty?
      document_ids << document_id
      raise "simulated pipeline failure" if question == "What failed?"

      chunk = Chunk.new(id: 7, filename: "animals.txt", position: 1, content: "Lions live in prides.", score: 0.9)
      Rag::Result.new(
        answer: "Lions live in prides.",
        grounded: true,
        retrieved_chunks: [ chunk ],
        citations: [ { source_chunk_id: 7, content: chunk.content } ],
        metadata: { question_type: "specific" },
        timings: { retrieval_seconds: 0.01, generation_seconds: 0.02, total_seconds: 0.03 },
        token_usage: { "prompt_tokens" => 6, "completion_tokens" => 4, "total_tokens" => 10 }
      )
    end
  end
end
