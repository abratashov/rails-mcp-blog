# RAG Evaluation

`$ RAG_EVALUATION_USER_EMAIL=test@test.org bin/rails rag:evaluate`

## BGE-M3

```sh
RAG Evaluation Report
====================================================
Dataset: animals_v1 | Questions: 10
Run ID:  08f72d27-5aa5-4a83-a2be-b51a3a05c7e2
Started: 2026-11-21T11:32:33Z
Document:  16
LLM:       vllm / Qwen/Qwen3-4B-AWQ (temperature=0.2, max_tokens=default)
Classifier: vllm / Qwen/Qwen3-4B-AWQ (strategy=rules_then_llm_fallback)
Aggregation: vllm / Qwen/Qwen3-4B-AWQ (input_tokens=1840 effective, configured=6000, output_tokens=2000, context_window=4096, batch_size=8)
Embedding: openai_compatible / bge-m3 (dimensions=1024)
Retrieval: question_type_routed Top-K=5, comparative Top-K=3, threshold=none

  #  Type          Result  Score   Latency
----------------------------------------------------
  1  Specific      PASS    1.00      3.51s
  2  Specific      PARTIAL 0.83      3.67s
  3  Specific      PASS    1.00      9.40s
  4  Specific      PARTIAL 0.89      4.95s
  5  Comparative   PARTIAL 0.81      5.91s
  6  Comparative   PARTIAL 0.79      8.99s
  7  Aggregation   PASS    0.98     34.06s
  8  Aggregation   PASS    0.96     84.11s
  9  Specific      PASS    1.00      5.76s
 10  Specific      PASS    1.00      6.63s

----------------------------------------------------
Quality score: 93%
Pass rate:     60% (6/10 passed)
Specific:      quality 95% | pass 67%
Comparative:   quality 80% | pass 0%
Aggregation:   quality 97% | pass 100%

Duration:      167.00s
Classification: 0.00s
Retrieval:     0.35s
Generation:    120.08s
Embedding:     n/a (not exposed by the retrieval service)
Tokens:        26223
Cost:          $0.000000
```

## E5

```sh
RAG Evaluation Report
====================================================
Dataset: animals_v1 | Questions: 10
Run ID:  e9ceb49b-558f-44c2-a89e-3bb5b7fe6ffb
Started: 2026-11-21T11:22:29Z
Document:  15
LLM:       vllm / Qwen/Qwen3-4B-AWQ (temperature=0.2, max_tokens=default)
Classifier: vllm / Qwen/Qwen3-4B-AWQ (strategy=rules_then_llm_fallback)
Aggregation: vllm / Qwen/Qwen3-4B-AWQ (input_tokens=1840 effective, configured=6000, output_tokens=2000, context_window=4096, batch_size=8)
Embedding: openai_compatible / jeffh/intfloat-multilingual-e5-large:q8_0 (dimensions=1024)
Retrieval: question_type_routed Top-K=5, comparative Top-K=3, threshold=none

  #  Type          Result  Score   Latency
----------------------------------------------------
  1  Specific      PASS    1.00      4.81s
  2  Specific      PASS    1.00      3.86s
  3  Specific      PASS    1.00      6.80s
  4  Specific      PARTIAL 0.94      7.58s
  5  Comparative   PARTIAL 0.88      5.73s
  6  Comparative   PARTIAL 0.79      8.65s
  7  Aggregation   PASS    0.90     29.24s
  8  Aggregation   PASS    0.88     30.16s
  9  Specific      PASS    1.00      5.54s
 10  Specific      PASS    1.00      6.57s

----------------------------------------------------
Quality score: 94%
Pass rate:     70% (7/10 passed)
Specific:      quality 99% | pass 83%
Comparative:   quality 83% | pass 0%
Aggregation:   quality 89% | pass 100%

Duration:      108.94s
Classification: 0.00s
Retrieval:     0.51s
Generation:    64.73s
Embedding:     n/a (not exposed by the retrieval service)
Tokens:        20782
Cost:          $0.000000
```
