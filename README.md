# README

Example Rails setup with MCP by workshop ["Paweł Strzałkowski - Make Rails AI-Ready by Design with the Model Context Protocol"](https://www.youtube.com/watch?v=IYAWJQ_HSQ)

## Setup


```sh
# Set appropriate API_TOKEN for LLM providers
cp .default.env.development .env.development

# Installation
mise install
bundle
rails db:prepare
rails db:seed

# Tab 1
bin/dev

http://localhost:3000/
test@test.org / test@test.org

# Tab 2
npx @modelcontextprotocol/inspector@latest
# Add Server:
#   Server ID: rails-mcp-blog
#   Transport: streamable-http
#   URL: http://localhost:3000/mcp

# Tab 3
# Run ngrok to translate your http://localhost:3000 to the Web
# https://dashboard.ngrok.com/get-started/share-localhost
ngrok http 3000

# Add our MCP to Claude https://claude.ai
# Settings => Connectors => Add
#   Name: rails-mcp-blog
#   URL: https://78d6-194-44-131-88.ngrok-free.app/mcp

# Now we can tell to Claude to perform some actions:
#   Create three short story posts about animals for my Rails MCP blog.
#   And now, could you add two short comments for two posts?
#   Remove the last post.
#   Make the latest comment more intense.
#   Write a post comparing the current weather in Lviv to the weather in Kyiv, use my own weather tool!

# Tab 4
# To run an interactive prompt in the CLI:
rails mcp:prompt_runner[essay_workshop]
# Or sign in to the Rails app and open the prompt list:
http://localhost:3000/prompts

# Upload PDF, DOCX, and TXT document:
http://localhost:3000/admin/documents

# For Semantic Search with `pgvector` check and update appropriate EMBEDDING settings in the env file.
http://localhost:3000/admin/semantic_search
```

## Tests

Tests use WebMock to block unregistered outbound requests and mock external weather
and OAuth API responses. SimpleCov enforces a 90% minimum line coverage and writes
the HTML report to `coverage/`.

```sh
bin/rails test
```

## Workshop Steps

Manual steps to reproduce this repository:

```sh
# 1. Init Rails app & MCP templates generator
mise use ruby@4.0
git clone https://github.com/pstrzalk/mcp-on-rails.git
cd mcp-on-rails
rails new rails-mcp-blog
rails new rails-mcp-blog -m mcp
# New Application
#   rails new app_name -m mcp-on-rails/mcp
# Existing Application
#   rails app:template LOCATION=../mcp-on-rails/mcp

# 2. Add posts resource
rails g scaffold post title:string body:text
rails db:migrate
# Go to http://localhost:3000/posts
rails mcp:tools

# 3. Add comments resource
rails g scaffold comment post:references content:text
rails db:migrate
# Go to http://localhost:3000/comments
rails mcp:tools

# 4. Add custom tool
rails g mcp_tool CheckWeatherTool location:string

# 5. Add OAuth
# Re-run and choose item with Doorkeeper & Devise
rails new rails-mcp-blog -m mcp

# 6. Add Posts as MCP Resources
# Claude doesn't support Resources but we can explore ones with:
npx @modelcontextprotocol/inspector@latest

# 7. Add Prompt
rails g mcp_prompt EssayWorkshop language:required

# EssayWorkshop
# Description: A guided writing exercise in which the user writes, corrects, practices, and evaluates a short essay, with an option to publish the final essay as a Post.
# Conduct a guided writing exercise with the user in #{language}.

# Follow these steps:

# 1. Suggest a random, interesting, short essay topic about a dream, memory, thought, problem, situation, or a description of an image, book, piece of music, or movie. Ask the user to write several sentences about the topic.

# 2. After the user submits their essay:
#    - Review it and identify up to 5 important grammar or collocation mistakes.
#    - Focus on meaningful errors that affect correctness or naturalness, not minor stylistic preferences.
#    - For each mistake, briefly explain why it is incorrect and provide the natural correction.
#    - Evaluate the original essay from 1–10 based on grammar, vocabulary, clarity, and naturalness.
#    - Create a practice exercise using the user's original sentences: replace the incorrect words or collocations with blanks and ask the user to fill them in.

# 3. After the user completes the exercise and the essay has been corrected, offer the user the option to publish the final essay as a Post using the `create_post` tool.
#    - Never publish the essay without the user's explicit confirmation.
#    - Before publishing, show the final version that will be published and ask for confirmation.

# Keep the exercise interactive: do not complete all steps at once.
# After each stage, wait for the user's response before continuing.

# Ollama usage
cd ~/installs
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
curl -I http://localhost:11434
ollama pull qwen3:4b
ollama run qwen3:4b
# >> Give me an interesting topic for an essay

# vLLM usage
cd ~/installs
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt install cuda-toolkit-12-9
vllm --version
# or add to your terminal init in case of vllm not found:
# nano ~/.bashrc
# export CUDA_HOME=/usr/local/cuda-12.9
# export PATH="$CUDA_HOME/bin:$PATH"
# export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
# export PATH="$HOME/installs/.venv/bin:$PATH"
vllm serve Qwen/Qwen3-4B-AWQ --max-model-len 4096 --gpu-memory-utilization 0.90 --enable-auto-tool-choice --tool-call-parser hermes

# OpenRouter usage
# Get OPENROUTER_API_KEY from https://openrouter.ai/workspaces/default/keys
# And put it into .env.development

# OpenAI usage
# Get OPENAI_API_KEY from https://platform.openai.com/api-keys
# And put it into .env.development
```
