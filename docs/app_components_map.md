# App Components Map

- **Document Management** — Handles document ingestion and preparation for processing.
  - Document Upload & Processing — Extracts text and metadata from uploaded files.
  - Text Chunking — Splits extracted content into manageable chunks.
  - Embedding Generation — Generates and stores vector embeddings.

- **RAG Engine** — Handles retrieval and generation of answers based on document content.
  - Question Classification — Identifies the type and intent of a question.
  - Semantic Search — Retrieves relevant document chunks.
  - Comparative Search — Retrieves information for comparisons.
  - Exhaustive Search — Retrieves broader content for factual or aggregation questions.
  - Answer Generation — Produces grounded answers with citations.

- **RAG Evaluation** — Evaluates retrieval and answer quality.
  - Retrieval Evaluation — Measures relevance of retrieved chunks.
  - Answer Evaluation — Evaluates generated answers.
  - Evaluation Reports — Collects metrics and results.

- **MCP Integration** — Provides AI interactions with external tools and prompts.
  - MCP Session — Manages interactive AI sessions.
  - Tool Execution — Discovers and executes tools.
  - Prompt Discovery — Retrieves available prompts.
  - Authentication — Handles CLI OAuth flow.

## Document Management

```rb
Document Upload
  -> ProcessDocumentJob
    -> Documents::Processor
      -> Documents::TextExtractor
        Document file => segments (text + page/metadata)  # PDF => text segments with page numbers
      -> Documents::Chunker
        segments => chunk attributes                      # text => chunks of ~500 tokens with overlap
      -> persist DocumentChunk records [DB]

  -> GenerateDocumentEmbeddingsJob [QUEUE]
    -> Embeddings::Generator
      DocumentChunk records => batches of chunk text      # ["Chunk 1 text", "Chunk 2 text", ...]
      -> Embeddings::OpenAICompatibleProvider.embed(texts) [EMBEDDING][API]
        texts => vectors                                  # 2 texts => 2 embedding vectors
      -> persist DocumentChunkEmbedding records [DB]
```

## RAG Engine

### Question Classification

```rb
User question
  -> Rag::Assistant.call
    -> Rag::QueryClassifier.call(question)
      -> rule_based_classification
        Question => question_type + confidence (1.0)
        -> return Classification [RULE-BASED]
      -> OpenAI::Client.chat [LLM][API]
        System prompt => classification instructions
        User prompt => question
        -> response (JSON: type + confidence)
      -> classification_from
        JSON => validate type and confidence
        -> confidence >= threshold (0.6)
          -> return Classification
        -> invalid / low confidence / error
          -> fallback("specific") [FALLBACK]
```

### Semantic Search

```rb
Rag::Assistant.call
  -> Rag::RetrievalRouter.call
    question_type: specific
    -> Rag::Retriever.call
      -> Rag::Strategies::SemanticSearch.call
        -> Rag::Retrieval::QueryEmbedder.call(query)  # "Where do lions live?"
          query => validate text and length
          -> Embeddings::OpenAICompatibleProvider.embed [EMBEDDING][API]
            query => vector                           # [0.9, 0.7, 0.3, ...]
        -> DocumentChunkEmbedding [DB][VECTOR DB]
          -> filter by user_id
          -> filter by embedding identity
             (provider, model, dimensions, configuration_version)
          -> filter completed embeddings
          -> optional document_id filter
          -> optional metadata filter [DB]
          -> nearest_neighbors(vector)                # ["Lions inhabit...", "Lion habitat includes...", ...]
            -> metric + threshold
            -> Top-K limit
            -> preload document_chunks + documents
            -> map embeddings to Rag::Retrieval::Result
```

### Comparative Search

```rb
Rag::Assistant.call
  -> Rag::RetrievalRouter.call
    question_type: comparative                    # "Compare lions and tigers"
    -> Rag::Strategies::ComparativeSearch.call
      -> Rag::Strategies::Comparative::QueryBuilder.call
        question => extract subjects + aspect     # subjects: ["lions", "tigers"], aspect: "social behavior"
        -> build independent queries per subject  # ["lions social behavior", "tigers social behavior"]
      -> execute queries [LOOP]                   # Q1: "lions social behavior", Q2: "tigers social behavior"
        -> Rag::Retriever.call
          -> Rag::Strategies::SemanticSearch.call
            query => embedding [EMBEDDING][API]
            -> nearest_neighbors [VECTOR DB]
            -> Top-K (default 3 per subject)
            -> results                            # 3 lion chunks + 3 tiger chunks
      -> Rag::Strategies::Comparative::ResultMerger.call
        -> interleave results by rank             # Lion 1, Tiger 1, Lion 2, Tiger 2...
        -> deduplicate chunks
        -> attach comparative metadata
          comparative_subject                     # "lions" / "tigers"
          comparative_aspect                      # "social behavior"
          comparative_query                       # original query for each subject
        -> merged chunks                          # Combined, ranked, deduplicated results
      -> log_retrieval [LOG]
      -> SearchResult (chunks + queries)
```

### Exhaustive Search

```rb
Rag::Assistant.call
  -> Rag::RetrievalRouter.call
    question_type: aggregation                            # "How many lions live in each habitat?"
    -> Rag::Strategies::ExhaustiveSearch.call
      -> Document [DB]
        -> filter by user_id
        -> optional document_id                           # Limit analysis to a specific document
        -> split documents
          -> completed documents                          # Documents ready for analysis
          -> incomplete documents (status + error)        # Failed or unfinished processing
        -> DocumentChunk [DB]
          -> optional metadata filter
          -> order by document_id + position
          -> preload documents
          -> map to Rag::Retrieval::Result                # All matching chunks, not similarity-ranked
        -> SearchResult
          chunks                                          # All retrieved chunks
          incomplete_documents                            # Documents that could not be fully processed
          document_count                                  # Number of documents included

  -> Rag::Analysis::BatchProcessor.call
    chunks => split into token-safe windows               # chunk1, chunk2, chunk3... grouped into batches
    -> build batches (size + token limits)
    -> process batches [LOOP]                             # Batch 1 -> Batch 2 -> Batch 3...
      -> Rag::Analysis::EntityExtractor.call [LLM][API]
        question + batch chunks => JSON                   # entities: ["lion", "savanna"],
                                                          # facts: ["Lions live in groups called prides"]
        -> validate schema and source_chunk_ids
        -> enrich extracted records with source metadata  # Attach document and chunk references for traceability
      -> retry failed batch (exponential delay)           # Retry after progressively longer delays
      -> collect entities + facts + failed batches

  -> Rag::Analysis::Aggregator.call
    entities
      -> normalize identities   # "Lion" / "lions" => same entity
      -> deduplicate entities
      -> mention counts         # Number of occurrences across chunks
      -> document counts        # Number of documents mentioning each entity
      -> percentages            # Share of documents containing an entity
      -> uncertainty indicators # Mark incomplete or unreliable data
      -> source references      # Links to originating chunks/documents
    facts
      -> normalize text
      -> deduplicate facts
      -> source references      # Preserve origin
    -> aggregated results       # Consolidated entities, statistics, facts, and sources
```

### Answer Generation

```rb
Rag::Assistant.call
  -> retrieval results
    -> Semantic / Comparative
      -> Rag::ContextAssembler.call
        -> deduplicate chunks               # Remove duplicate content across retrieved results
        -> order by relevance (except comparative results) # Highest relevance first
        -> format source entries            # Add document titles and source information
        -> estimate tokens
        -> enforce context budget           # Keep context within the model's token limit
        -> truncate last chunk if necessary # Trim content to fit remaining budget
        -> ContextItem records              # Prepared context items with source metadata

    -> Exhaustive
      -> skip regular context assembly
      -> Rag::Assistant::AggregationPresenter.prompt_results
        -> prepare aggregated entities + facts  # Example: lion, habitat, population facts
        -> attach source references             # Link facts/entities to original chunks
        -> label citations                      # Assign source identifiers
        -> enforce aggregation token budget     # Keep aggregated data within the available prompt budget

  -> Rag::PromptBuilder.call [PROMPT]
    question + context + question_type + aggregation data # Example: "Where do lions live?" + retrieved chunks
      -> detect answer language                           # Respond in the question's language
      -> add grounded-answer instructions                 # Use retrieved information, avoid unsupported claims
      -> add comparative instructions (if comparative)    # Compare subjects using retrieved evidence
      -> add aggregation instructions (if aggregation)    # Answer using aggregated entities, facts, and statistics
      -> format retrieved sources                         # Structured source blocks
      -> format aggregation data                          # Structured entities/facts
      -> final prompt                                     # Complete prompt sent to the LLM

  -> Rag::AnswerGenerator.call [LLM][API]
    -> normalize conversation messages            # Prepare messages in provider-compatible format
    -> append final user prompt
    -> configure model + temperature + max_tokens # Example: Qwen3-4B, temperature, response token limit
    -> client.chat
    -> retry up to 2 times if response text is empty
    -> extract response text
    -> remove <think> reasoning                   # Remove model reasoning tags from output
    -> collect token usage                        # Prompt + completion tokens
    -> response (text + provider + model + usage)

  -> Citation processing
    -> Rag::Assistant::CitationPresenter.build_citations(context) # Map retrieved context items to source citations
    -> AggregationPresenter.append_citations (if aggregation)     # Append source references for aggregated data
    -> CitationPresenter.citations_used_by(answer)                # Identify citations referenced in the generated answer
    -> CitationPresenter.decorate_with_citations(answer)          # Format citations in the final response
    -> Rag::Result
      answer + sources + citations + metadata + timings + token usage
```

## RAG Evaluation

### Retrieval Evaluation

```rb
Rag::Evaluation::RetrievalEvaluator.call(question, result)
  -> retrieved_chunks vs relevant_source_chunks
    -> match retrieved chunks with expected sources   # expected chunk ID 12 matches retrieved chunk ID 12
    -> relevant_chunks_found
    -> relevant_chunks_expected
    -> relevance                                      # Relevant / Retrieved
    -> coverage                                       # Found / Expected

  -> citations
    -> validate citation source_chunk_id against retrieved IDs  # citation ID 12 is valid if retrieved IDs are [12, 15, 18]
    -> citation_accuracy                              # Valid / Total
    -> match citations against expected sources and claims
    -> citations_relevant
    -> citation_relevance                             # Relevant / Total

  -> evidence_term_groups
    -> collect and normalize citation content
    -> match expected evidence terms                  # ["savanna", "grasslands"] => either term matches
    -> faithfulness                                   # Supported groups / Expected groups

  -> gold_relations
    -> verify claims using citation evidence          # Subject + predicate + object must be supported
    -> supported_claims
    -> unsupported_claims
    -> claim_support                                  # Supported / Expected

  -> metrics
    -> relevance + coverage + citation_accuracy + citation_relevance
    -> faithfulness + claim_support
```

### Answer Evaluation

```rb
Rag::Evaluation::AnswerEvaluator.call(question, result)
  -> check insufficient_evidence
    -> detect phrases indicating missing information [REGEX]  # "The documents do not contain enough information"
    -> correctness + completeness + concept_coverage          # 1.0 if acknowledged correctly, otherwise 0.0
    -> language_match
    -> empty concept + relation metrics
    -> insufficient_evidence_correct

  -> expected_term_groups
    -> answer_term_groups (fallback to expected_term_groups)
    -> expected_terms / expected_answer (fallback)
    -> normalize answer text
    -> match expected terms                                   # ["savanna", "grasslands"] => either term matches
    -> term_recall                                            # Matched / Expected groups

  -> evaluate concepts (except aggregation)
    -> gold_concepts
    -> match aliases, exclude incorrect_aliases               # "pride" matches lion social-group concept
    -> found + missing concepts
    -> detect incorrect concepts
    -> concept_recall

  -> evaluate relations (except aggregation)
    -> gold_relations
    -> split answer into sentences / claims
    -> match subject + predicate + object aliases             # lions -> live in -> prides
    -> found + missing relations
    -> relation_recall

  -> calculate correctness
    -> average available term_recall + concept_recall + relation_recall
    -> cap by relation_recall when relations exist

  -> language_match [HEURISTIC]                               # expected Ukrainian markers vs English/Russian markers
    -> expected-language hits / total language hits

  -> AnswerMetrics
    -> correctness + completeness + concept_coverage + language_match
    -> concepts + relations + expected_terms + matched_terms
```

### Evaluation Reports

```rb
Rag::Evaluation::Runner#call
  -> load datasets [FILE]
  -> evaluate each question
    -> QuestionRunner
      -> run RAG pipeline
      -> AnswerEvaluator
      -> RetrievalEvaluator
      -> calculate question score + status
      -> collect metrics, sources, citations, timings, token usage
    -> aggregate results by question type             # Specific / Comparative / Aggregation
    -> calculate pass rate + quality score
    -> collect performance metrics
      -> total duration
      -> classification + retrieval + generation time
      -> token usage
      -> estimated cost                               # Calculated when token rates are configured
    -> ConfigurationSnapshot
      -> document ID
      -> LLM + classifier configuration
      -> aggregation configuration                    # Token limits, context window, batch size
      -> embedding configuration
      -> retrieval configuration                      # Top-K, similarity threshold

  -> Report#render(runs)
    -> RAG Evaluation Report
      -> dataset + question count
      -> run ID + start timestamp
      -> configuration
      -> question results [LOOP]                      # 1 | Specific | PASS | 0.92 | 4.21s
        -> question type + status + score + latency
      -> summary metrics
        -> quality score + pass rate + pass count
        -> metrics grouped by question type
      -> performance summary
        -> duration + timings + tokens + cost
      -> failure details (non-PASS questions)
        -> question ID + status + question text
        -> quality score + individual metrics
        -> expected + actual answer                   # Remove <think> and Sources
        -> error details
        -> diagnostics
          -> missing / incorrect concepts
          -> missing relations + unsupported claims
          -> aggregation count + entity accuracy
          -> missing / unexpected entities
          -> failed batches
        -> citation summary                           # Filename, pages, content excerpt
      -> formatted report text
```

## MCP Integration

### MCP Session

```rb
AI::PromptRunnerSession
  -> show / submit / end_session
    -> find prompt from available_prompts
    -> load cached conversation [CACHE]             # Cache key: user ID + prompt name + session ID
      -> check session expiration
      -> clear expired session

    -> submit message + arguments
      -> validate message length (10,000 chars)
      -> validate required prompt arguments
      -> create temporary Doorkeeper access token
      -> PromptRunner
      -> start or continue conversation
      -> save messages to cache (2 hours) [CACHE]
      -> revoke access token
      -> return session result

    -> end_session
      -> delete cached messages
      -> remove session ID
```

### Tool Execution

```rb
AI::PromptRunner
  -> load_llm_tools [MCP]
    -> tools/list
    -> convert MCP tools to LLM function definitions  # Tool name + description + inputSchema => function definition
  -> perform_turn [LOOP]
    -> send messages + available tools to LLM [API]
    -> extract assistant message
    -> check tool_calls
      -> execute_tool [LOOP]
        -> parse tool arguments [JSON]
        -> tools/call [MCP]                           # tool name + arguments => MCP request
        -> extract text content from result
        -> append tool result to messages
    -> repeat LLM request until no tool calls
    -> return assistant response + tool calls + messages
```

### Prompt Discovery

```rb
AI::PromptRunnerSession.available_prompts
  -> MCP::Prompt.descendants
    -> select valid prompt classes
    -> deduplicate by prompt name
    -> extract prompt details
      -> name
      -> title                        # Prompt name humanized if title is missing
      -> description
      -> arguments
    -> sort by name

AI::PromptRunner
  -> client.prompts
    -> MCP client prompt discovery
```

### Authentication

```rb
AI::CLIAuthenticator#authenticate
  -> generate code_verifier [PKCE]
  -> generate code_challenge [SHA256]
  -> build authorization URL [OAuth]        # response_type=code + client_id + redirect_uri + scope + code_challenge
  -> start local callback server [HTTP]
    -> listen on 127.0.0.1:9876/oauth/callback
  -> open browser
  -> receive authorization code
  -> exchange code for access token [HTTP]  # authorization_code + code_verifier + redirect_uri
  -> validate token response
    -> return access_token
  -> shutdown callback server

AI::PromptRunnerSession
  -> create Doorkeeper application [DB]
  -> create temporary access token [DB]
    -> scope: public
  -> pass token to PromptRunner [AUTH]
  -> revoke token after execution
```
