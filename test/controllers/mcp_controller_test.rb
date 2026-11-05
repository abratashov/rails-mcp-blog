require "test_helper"

class McpControllerTest < ActionController::TestCase
  self.fixture_table_names = []

  test "excludes unloaded subclasses after a Rails reload" do
    old_class = MCP.const_set(:ReloadedTestTool, Class.new(MCP::Tool))
    Object.const_get("MCP::ReloadedTestTool").tool_name("reloaded-test-tool")

    MCP.send(:remove_const, :ReloadedTestTool)
    current_class = MCP.const_set(:ReloadedTestTool, Class.new(MCP::Tool))
    current_class.tool_name("reloaded-test-tool")

    subclasses = @controller.send(:current_descendants, MCP::Tool)

    assert_includes subclasses, current_class
    assert_not_includes subclasses, old_class
  ensure
    MCP.send(:remove_const, :ReloadedTestTool) if MCP.const_defined?(:ReloadedTestTool, false)
  end
end
