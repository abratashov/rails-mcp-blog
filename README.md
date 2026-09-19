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
```
