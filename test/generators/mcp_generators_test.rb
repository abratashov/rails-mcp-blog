require "test_helper"
require "rails/generators/test_case"
require "tmpdir"
require_relative "../../lib/generators/mcp_tool/mcp_tool_generator"
require_relative "../../lib/generators/mcp_prompt/mcp_prompt_generator"
require_relative "../../lib/generators/rails/mcp_generator"
require_relative "../../lib/generators/rails/scaffold_controller_generator"

class McpToolGeneratorTest < Rails::Generators::TestCase
  tests McpToolGenerator
  destination File.join(Dir.tmpdir, "rails-mcp-generators-#{Process.pid}-mcp_tool")

  setup do
    self.class.destination_root = File.join(Dir.tmpdir, "rails-mcp-#{Process.pid}-#{name}")
    prepare_destination
  end

  teardown do
    FileUtils.rm_rf(self.class.destination_root)
  end

  test "generates a tool with types mapped from attributes" do
    run_generator [ "check_weather", "location:string", "post:references", "active:boolean", "created_at:timestamp" ]

    assert_file "app/tools/check_weather.rb" do |content|
      assert_includes content, "class CheckWeather < MCP::Tool"
      assert_includes content, 'location: { type: "string" }'
      assert_includes content, 'post_id: { type: "integer" }'
      assert_includes content, 'active: { type: "boolean" }'
      assert_includes content, 'created_at: { type: "integer" }'
    end
  end
end

class McpPromptGeneratorTest < Rails::Generators::TestCase
  tests McpPromptGenerator
  destination File.join(Dir.tmpdir, "rails-mcp-generators-#{Process.pid}-mcp_prompt")

  setup do
    self.class.destination_root = File.join(Dir.tmpdir, "rails-mcp-#{Process.pid}-#{name}")
    prepare_destination
  end

  teardown do
    FileUtils.rm_rf(self.class.destination_root)
  end

  test "generates a prompt with required and optional arguments" do
    run_generator [ "essay_workshop_prompt", "language:required", "topic" ]

    assert_file "app/prompts/essay_workshop_prompt.rb" do |content|
      assert_includes content, 'prompt_name "essay-workshop"'
      assert_includes content, 'name: "language"'
      assert_includes content, "required: true"
      assert_includes content, 'name: "topic"'
      assert_includes content, "required: false"
    end
  end
end

class RailsMcpGeneratorTest < Rails::Generators::TestCase
  tests Rails::Generators::McpGenerator
  destination File.join(Dir.tmpdir, "rails-mcp-generators-#{Process.pid}-rails_mcp")

  setup do
    self.class.destination_root = File.join(Dir.tmpdir, "rails-mcp-#{Process.pid}-#{name}")
    prepare_destination
  end

  teardown do
    FileUtils.rm_rf(self.class.destination_root)
  end

  test "skips MCP tool generation when requested" do
    generator = build_generator
    generator.define_singleton_method(:ask) { |*| "none" }

    generator.create_mcp_tools

    assert_no_file "app/tools/posts/create_tool.rb"
  end

  test "generates all resource tools when requested" do
    generator = build_generator
    generator.define_singleton_method(:ask) { |*| "all" }

    generator.create_mcp_tools

    %w[show_tool index_tool create_tool update_tool delete_tool].each do |tool|
      assert_file "app/tools/posts/#{tool}.rb"
    end
  end

  test "generates selected resource tools and skips the rest" do
    generator = build_generator
    generator.define_singleton_method(:ask) { |*| "some" }
    answers = [ true, false, false, true, false ]
    generator.define_singleton_method(:yes?) { |*| answers.shift }

    generator.create_mcp_tools

    assert_file "app/tools/posts/show_tool.rb"
    assert_file "app/tools/posts/update_tool.rb"
    assert_no_file "app/tools/posts/index_tool.rb"
    assert_no_file "app/tools/posts/create_tool.rb"
    assert_no_file "app/tools/posts/delete_tool.rb"
  end

  private

  def build_generator
    Rails::Generators::McpGenerator.new(
      [ "post", "title:string", "published:boolean", "created_at:timestamp" ],
      {},
      destination_root: self.class.destination_root
    )
  end
end
