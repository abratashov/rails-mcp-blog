# README

Example Rails setup with MCP by workshop ["Paweł Strzałkowski - Make Rails AI-Ready by Design with the Model Context Protocol"](https://www.youtube.com/watch?v=IYAWJQ_HSQ)

## Setup

```sh
# Tab 1
bundle
bin/dev

# Goto
http://localhost:3000/
```

## Workshop Steps

Manual steps to reproduce this repository:

```sh
mise use ruby@4.0
git clone https://github.com/pstrzalk/mcp-on-rails.git
cd mcp-on-rails
rails new rails-mcp-blog
rails new rails-mcp-blog -m mcp
```
