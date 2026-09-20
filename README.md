# README

Example Rails setup with MCP by workshop ["Paweł Strzałkowski - Make Rails AI-Ready by Design with the Model Context Protocol"](https://www.youtube.com/watch?v=IYAWJQ_HSQ)

## Setup

```sh
# Tab 1
bundle
bin/dev

# Goto
http://localhost:3000/

npx @modelcontextprotocol/inspector@latest
# Add Server:
#   Server ID: rails-mcp-blog
#   Transport: streamable-http
#   URL: http://localhost:3000/mcp

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
```
