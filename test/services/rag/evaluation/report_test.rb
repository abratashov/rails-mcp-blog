require "test_helper"

class RagEvaluationReportTest < ActiveSupport::TestCase
  test "renders configuration, per-question scores, metrics, and failed-case details" do
    dataset = Rag::Evaluation::DatasetLoader::Dataset.new(name: "animals_v1", questions: [])
    run = Rag::Evaluation::Runner::Run.new(
      id: "run-123",
      dataset: dataset,
      started_at: Time.zone.parse("2026-01-01 10:00:00"),
      duration_seconds: 1.25,
      configuration: {
        llm: { provider: "vllm", model: "Qwen3-4B", temperature: 0.2, max_tokens: nil },
        classifier: { provider: "vllm", model: "Qwen3-4B", strategy: "rules_then_llm_fallback" },
        aggregation: {
          provider: "vllm", model: "Qwen3-4B", max_input_tokens: 1840,
          configured_max_input_tokens: 6000, max_tokens: 2000, context_window: 4096, batch_size: 8
        },
        embedding: { provider: "openai_compatible", model: "e5", dimensions: 1024 },
        retrieval: { strategy: "routed", top_k: 3, comparative_top_k: 5, threshold: nil }
      },
      results: [
        {
          id: "question-1", type: "specific", status: "FAIL", score: 0.5,
          latency_seconds: 0.4, question: "Where do lions live?",
          timings: { classification_seconds: 0.1, retrieval_seconds: 0.2, generation_seconds: 0.3 },
          expected_answer: "In prides.",
          actual_answer: "Not found.\n\nSources: [1] animals.txt",
          error: "server responded with status 500",
          answer: {
            concepts: {
              missing: [ "red_fox" ],
              incorrect: [ { concept: "red_fox", term: "красная кошка" } ]
            },
            relations: { missing: [ "lion -> pride" ] }
          },
          retrieval: { unsupported_claims: [ "lion -> pride" ], claim_support: nil, faithfulness: nil },
          aggregation: {
            count_accuracy: 0.0, expected_count: 6, actual_count: 0,
            entity_accuracy: 0.0, actual_entities: [],
            missing_entities: [ "lion", "tiger" ],
            unexpected_entities: [ "mammal species" ],
            incomplete_batch_count: 1,
            failed_batches: [
              { batch: 2, chunk_ids: [ 14, 15 ], attempts: 3, error: "provider timeout" }
            ]
          },
          citations: [ { label: 1, filename: "animals.txt", page_start: 2, content: "Lion evidence." } ],
          retrieved_sources: [ { filename: "animals.txt" } ]
        }
      ],
      metrics: {
        accuracy: 0.0, pass_rate: 0.0, quality_score: 0.5, pass_count: 0,
        by_type: { "specific" => { accuracy: 0.0, pass_rate: 0.0, quality_score: 0.5 } }
      },
      token_usage: { total_tokens: 10 },
      estimated_cost: nil
    )

    report = Rag::Evaluation::Report.new.render([ run ])

    assert_includes report, "Dataset: animals_v1 | Questions: 1"
    assert_includes report, "Qwen3-4B"
    assert_includes report, "strategy=rules_then_llm_fallback"
    assert_includes report, "input_tokens=1840 effective, configured=6000, output_tokens=2000, context_window=4096, batch_size=8"
    assert_includes report, "FAIL"
    assert_includes report, "Quality score: 50%"
    assert_includes report, "Pass rate:     0% (0/1 passed)"
    assert_includes report, "Expected: In prides."
    assert_includes report, "Actual:   Not found."
    assert_includes report, "Pipeline error: server responded with status 500"
    assert_includes report, "Aggregation count: actual=0, expected=6 (accuracy 0.00)"
    assert_includes report, "Aggregation entity accuracy: 0.00"
    assert_includes report, "Unexpected aggregation entities: mammal species"
    assert_not_includes report, "Actual:   Not found.\n\nSources:"
    assert_includes report, "Missing concepts: red_fox"
    assert_includes report, "Incorrect concepts: red_fox=красная кошка"
    assert_includes report, "Missing relations: lion -> pride"
    assert_includes report, "Claims without cited support: lion -> pride"
    assert_includes report, "claim support: n/a | cited-term support: n/a"
    assert_includes report, "Citations: [1] animals.txt p. 2: Lion evidence."
    assert_includes report, "animals.txt"
    assert_includes report, "Tokens:        10"
    assert_includes report, "Aggregation extraction incomplete: 1 batch(es) failed"
    assert_includes report, "Batch 2 failed after 3 attempts (chunks: 14, 15): provider timeout"
    assert_includes report, "Classification: 0.10s"
    assert_includes report, "Retrieval:     0.20s"
    assert_includes report, "Generation:    0.30s"
  end

  test "renders unavailable diagnostic scores as n/a instead of zero" do
    dataset = Rag::Evaluation::DatasetLoader::Dataset.new(name: "animals_v1", questions: [])
    run = Rag::Evaluation::Runner::Run.new(
      id: "run-456",
      dataset: dataset,
      started_at: Time.zone.parse("2026-01-01 10:00:00"),
      duration_seconds: 1.0,
      configuration: {},
      results: [
        {
          id: "question-2", type: "aggregation", status: "PARTIAL", score: 0.5,
          latency_seconds: 0.4, question: "How many species?",
          answer: { correctness: 0.5 },
          retrieval: { coverage: 1.0, citation_accuracy: 1.0, citation_relevance: 0.5 }
        }
      ],
      metrics: {
        accuracy: 0.0, pass_rate: 0.0, quality_score: 0.5, pass_count: 0,
        by_type: { "aggregation" => { accuracy: 0.0, pass_rate: 0.0, quality_score: 0.5 } }
      },
      token_usage: {},
      estimated_cost: nil
    )

    report = Rag::Evaluation::Report.new.render([ run ])

    assert_includes report, "claim support: n/a"
    assert_includes report, "cited-term support: n/a"
  end
end
