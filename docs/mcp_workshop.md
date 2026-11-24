## MCP Workshop

Manual steps to reproduce the MCP part of this repository:

```sh
# 1. Initialize a Rails application using the MCP template generator
mise use ruby@4.0
git clone https://github.com/pstrzalk/mcp-on-rails.git
cd mcp-on-rails

# Generate a new Rails application using the MCP template
rails new rails-mcp-blog -m mcp

# Alternative: apply the template to an existing application
# rails app:template LOCATION=../mcp-on-rails/mcp

# 2. Add the Posts resource
rails g scaffold post title:string body:text
rails db:migrate

# Open http://localhost:3000/posts
rails mcp:tools

# 3. Add the Comments resource
rails g scaffold comment post:references content:text
rails db:migrate

# Open http://localhost:3000/comments
rails mcp:tools

# 4. Add a custom tool
rails g mcp_tool CheckWeatherTool location:string

# 5. Add OAuth
# Re-run the MCP template generator and select the Doorkeeper & Devise option
rails new rails-mcp-blog -m mcp

# 6. Add Posts as MCP Resources
# Claude doesn't support Resources, but you can explore them using:
npx @modelcontextprotocol/inspector@latest

# 7. Add a Prompt
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
# After each stage, wait for the user's response.
```
