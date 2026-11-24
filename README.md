# Rails MCP Blog

A Rails application exploring AI integration through the Model Context Protocol (MCP) and Retrieval-Augmented Generation (RAG).

The MCP implementation is based on the workshop ["Paweł Strzałkowski - Make Rails AI-Ready by Design with the Model Context Protocol"](https://www.youtube.com/watch?v=IYAWJQ_HSQ). See [MCP Workshop](docs/mcp_workshop.md) for instructions on reproducing it.

The RAG implementation covers document ingestion, semantic retrieval, and document-based question answering.

## Setup

```sh
# Set the appropriate API_TOKEN for LLM providers
cp .default.env.development .env.development

# Install dependencies and prepare the database
mise install
pg_ctl -D ~/.local/share/mise/installs/postgres/15.7/data start
bundle install
rails db:prepare
rails db:seed

# Tab 1: Start the Rails application
bin/dev

# Tab 2: Start the embedding service (Ollama)
sudo systemctl start ollama

# Start the LLM server (vLLM)
vllm serve Qwen/Qwen3-4B-AWQ --max-model-len 4096 --gpu-memory-utilization 0.90 --enable-auto-tool-choice --tool-call-parser hermes

# Open http://localhost:3000/
# Credentials: test@test.org / test@test.org
```

## MCP Tools & Prompts

```sh
# Tab 3: Start MCP Inspector
npx @modelcontextprotocol/inspector@latest

# Add Server:
#   Server ID: rails-mcp-blog
#   Transport: streamable-http
#   URL: http://localhost:3000/mcp

# Tab 4: Expose the local Rails application to the web using ngrok
# https://dashboard.ngrok.com/get-started/share-localhost
ngrok http 3000

# Add the MCP server to Claude (https://claude.ai)
# Settings => Connectors => Add
#   Name: rails-mcp-blog
#   URL: https://<your-ngrok-subdomain>.ngrok-free.app/mcp

# You can now ask Claude to perform actions such as:
#   Create three short story posts about animals for my Rails MCP blog.
#   And now, could you add two short comments for two posts?
#   Remove the last post.
#   Make the latest comment more intense.
#   Write a post comparing the current weather in Lviv to the weather in Kyiv, use my own weather tool!

# Open the prompt interface in the Rails application
# Follow the interactive essay workshop and confirm publishing when prompted.
http://localhost:3000/prompts

# Tab 5: Run the prompt runner in the CLI (alternative to the web UI)
rails mcp:prompt_runner[essay_workshop]
```

### RAG Application

In addition to the MCP functionality, this project includes a RAG application that allows you to upload documents and chat about their content.

```sh
# Upload a PDF, DOCX, or TXT document:
http://localhost:3000/admin/documents

# Semantic search is powered by pgvector.
# Make sure the EMBEDDING_* settings in the environment file are configured correctly.

# Ask questions about uploaded documents:
# - specific: what, who, where, when, why, which, whose, whom, how
# - comparative: compare, contrast, versus, vs, difference between, differences between
# - aggregation: how many, count, total number, number of
http://localhost:3000/chat
```

### Embedding Configuration

The application supports OpenAI-compatible embedding APIs, including Ollama and vLLM.

Example configuration for multilingual E5 using Ollama:

```dotenv
EMBEDDING_API_BASE_URL=http://localhost:11434/v1
EMBEDDING_API_KEY=ollama
EMBEDDING_MODEL=jeffh/intfloat-multilingual-e5-large:q8_0
EMBEDDING_DIMENSIONS=1024
EMBEDDING_SEND_DIMENSIONS=false
EMBEDDING_QUERY_PREFIX="query: "
EMBEDDING_PASSAGE_PREFIX="passage: "
```

E5 uses different prefixes for queries and document chunks:

- `query: ` — user questions
- `passage: ` — document chunks

When changing embedding models, regenerate document embeddings to rebuild the vector index. Embeddings produced by different models should not be mixed.

### RAG Evaluation

```sh
# The fixed multilingual evaluation dataset covers specific, comparative, aggregation, and insufficient-evidence questions.

# Check and set the following environment variables:
# - RAG_ANALYSIS_CONTEXT_WINDOW
# - RAG_EVAL_INPUT_COST_PER_MILLION_TOKENS
# - RAG_EVAL_OUTPUT_COST_PER_MILLION_TOKENS

# Run evaluation:
RAG_EVALUATION_USER_EMAIL=test@test.org bin/rails rag:evaluate

# Example results: docs/rag_evaluation.md
```

## Tests

WebMock blocks unregistered outbound requests and mocks external weather and OAuth API responses. SimpleCov enforces a 90% minimum line coverage and generates an HTML report in `coverage/`.

```sh
bin/rails test
```

### Setup LLM Models

```sh
# OpenRouter usage
# Get LLM_ACCESS_TOKEN from https://openrouter.ai/workspaces/default/keys
# Add it to .env.development

# OpenAI usage
# Get LLM_ACCESS_TOKEN from https://platform.openai.com/api-keys
# Add it to .env.development

# Ollama usage:
cd ~/installs
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
curl -I http://localhost:11434

# Load LLM model
ollama pull qwen3:4b

# Load embedding models
ollama pull bge-m3
ollama pull jeffh/intfloat-multilingual-e5-large:q8_0

# Run LLM
ollama run qwen3:4b

# Example prompt:
# Give me an interesting topic for an essay.

# vLLM usage
cd ~/installs
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt install cuda-toolkit-12-9
vllm --version

# Alternatively, add the following to your ~/.bashrc if vLLM is not found:
# nano ~/.bashrc
# export CUDA_HOME=/usr/local/cuda-12.9
# export PATH="$CUDA_HOME/bin:$PATH"
# export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
# export PATH="$HOME/installs/.venv/bin:$PATH"

# Test Embedding Models (Ollama native API)
curl http://localhost:11434/api/embed -d '{ "model": "bge-m3", "input": "What do lions eat?" }'

curl http://localhost:11434/api/embed -d '{ "model": "jeffh/intfloat-multilingual-e5-large:q8_0", "input": "query: Where do tigers live?" }'

curl http://localhost:11434/api/embed -d '{ "model": "jeffh/intfloat-multilingual-e5-large:q8_0", "input": "passage: Tigers live in forests and grasslands." }'
```

### App Components Map

See [App Components Map](docs/app_components_map.md) for details on the application implementation.
