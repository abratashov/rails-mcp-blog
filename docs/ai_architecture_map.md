# AI Architecture Map

```rb
# Uploads documents, extracts text, chunks it, and queues embedding/indexing.
Document
  enqueue_processing
    ProcessDocumentJob.perform_later [QUEUE]
      ProcessDocumentJob#perform [QUEUE]
        Documents::Processor#call
          Document#with_lock [DB]
            Documents::TextExtractor#call
              Documents::TextExtractor#extract_pdf
              Documents::TextExtractor#extract_docx
              Documents::TextExtractor#extract_txt
            Documents::Chunker#call
            document_chunks
              create! [DB]
            Document#update! [DB]
          GenerateDocumentEmbeddingsJob.perform_later [QUEUE]
            GenerateDocumentEmbeddingsJob#perform [QUEUE]
              Embeddings::Generator#call
                Embeddings::Generator#generate_batch
                  Embeddings::Generator#claim [DB]
                  Embeddings::OpenAICompatibleProvider#embed [EMBEDDING][API]
                  Embeddings::Generator#persist_vector [VECTOR DB][DB]
```

```rb
# Creates, loads, and displays a user's persisted document-chat conversations.
ChatsController
  create
    RagConversation#create! [DB]
    submit_question
  create_message
    load_conversation
    submit_question
  show
    RagConversation#messages_for_display [DB]
```

```rb
# Classifies each question, routes retrieval, and generates a cited answer.
ChatsController#submit_question
  RagConversation#messages_for_display [DB]
  Rag::Assistant#call
    Rag::QueryClassifier#call [LLM][API]
      OpenAI::Client#chat
    Rag::RetrievalRouter#call
      Rag::RetrievalRouter#strategy_for
        Rag::Retriever#call
          Retrieval::SemanticSearch#call
            Retrieval::QueryEmbedder#call
              Embeddings::OpenAICompatibleProvider#embed [EMBEDDING][API]
            nearest_neighbors [VECTOR DB][DB]
            Retrieval::SemanticSearch#build_result
        Rag::Strategies::ComparativeSearch#call
          # Retrieves evidence for each comparison subject and merges the results.
          Rag::Comparative::QueryBuilder#call
          Rag::Retriever#call
          Rag::Comparative::ResultMerger#call
        Rag::Strategies::ExhaustiveSearch#call [DB]
          # Loads all eligible document chunks for aggregation.
          Document.where [DB]
          DocumentChunk.joins [DB]
    Rag::Analysis::BatchProcessor#call
      # aggregation only
      Rag::Analysis::BatchProcessor#build_batches
      Rag::Analysis::EntityExtractor#call [LLM][API]
        OpenAI::Client#chat
      Rag::Analysis::BatchProcessor#enrich_sources
    Rag::Analysis::Aggregator#call
      # aggregation only
      Rag::Analysis::EntityDeduplicator#call
      Rag::Analysis::Aggregator#aggregate_facts
    Rag::ContextAssembler#call
      # specific and comparative only
    Rag::PromptBuilder#call [PROMPT]
    Rag::AnswerGenerator#call [LLM][API]
      OpenAI::Client#chat
    Rag::Assistant#build_citations
    Rag::Assistant#decorate_with_citations
  RagConversation#append_message [DB]
  RagConversation#append_message [DB]
```

```rb
# Discovers MCP prompts and tools, runs LLM turns, and returns tool results in chat.
PromptRunnersController
  index
    AI::PromptRunnerSession.available_prompts [MCP PROMPT]
  show
    AI::PromptRunnerSession#show
      AI::PromptRunnerSession#load_messages
        Rails.cache.read
    render
  create
    AI::PromptRunnerSession#submit
      AI::PromptRunnerSession#find_prompt [MCP PROMPT]
      AI::PromptRunner#initialize
        AI::PromptRunner#load_initial_messages
          MCP::Client#connect
          MCP::Client::HTTP#send_request [MCP PROMPT]
            prompts/get
              McpController#handle
                McpController#mcp_server
                MCP::Server#handle_json [MCP PROMPT]
                  prompts/get [MCP PROMPT]
                    EssayWorkshop.template [MCP PROMPT]
                render
        AI::PromptRunner#load_llm_tools
          MCP::Client::HTTP#send_request [MCP TOOL]
            tools/list
      AI::PromptRunner#start
        AI::PromptRunner#perform_turn
          OpenAI::Client#chat [LLM][API]
          AI::PromptRunner#execute_tool
            MCP::Client::HTTP#send_request [MCP TOOL]
              tools/call
                McpController#handle
                  McpController#mcp_server
                    McpController#current_descendants
                      MCP::Tool.descendants [MCP TOOL]
                      MCP::Prompt.descendants [MCP PROMPT]
                      MCP::Resource.descendants
                      MCP::ResourceTemplate.descendants
                  MCP::Server#handle_json [MCP TOOL]
                    prompts/list [MCP PROMPT]
                    prompts/get [MCP PROMPT]
                    tools/list [MCP TOOL]
                    tools/call [MCP TOOL]
                      Posts::CreateTool.call [DB]
                      Posts::IndexTool.call [DB]
                      Posts::ShowTool.call [DB]
                      Posts::UpdateTool.call [DB]
                      Posts::DeleteTool.call [DB]
                      Comments::CreateTool.call [DB]
                      Comments::IndexTool.call [DB]
                      Comments::ShowTool.call [DB]
                      Comments::UpdateTool.call [DB]
                      Comments::DeleteTool.call [DB]
                      CheckWeatherTool.call [API]
                  render
          OpenAI::Client#chat [LLM][API] # repeats when tool calls are returned
      AI::PromptRunner#reply
        AI::PromptRunner#add_user_message
        AI::PromptRunner#perform_turn
      Rails.cache.write
    redirect_to
  destroy
    AI::PromptRunnerSession#end_session
      Rails.cache.delete
```

```rb
# Shared providers, persistence, prompt, and conversation components.
Embeddings::Configuration
Embeddings::Provider
Embeddings::OpenAICompatibleProvider
Retrieval::SearchConfiguration
DocumentChunkEmbedding
Rag::PromptBuilder
MCP::Prompt
EssayWorkshop
  # Prompt refers to create_post; registered tool name is post-create-tool
AI::PromptRunner
AI::PromptRunner#llm_config
Rag::AnswerGenerator
Rag::AnswerGenerator#llm_config
Rag::QueryClassifier
Rag::QueryClassifier#llm_config
Rag::Analysis::EntityExtractor
Rag::Analysis::EntityExtractor#llm_config
RagConversation
AI::PromptRunnerSession
```
