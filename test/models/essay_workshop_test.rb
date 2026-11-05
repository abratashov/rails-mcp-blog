require "test_helper"

class EssayWorkshopTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "uses English as the default prompt language" do
    result = EssayWorkshop.template({}, server_context: {})

    assert_includes result.messages.first.content.text, "in English"
  end

  test "uses the requested prompt language" do
    result = EssayWorkshop.template({ language: "French" }, server_context: {})

    assert_includes result.messages.first.content.text, "in French"
    assert_includes result.messages.first.content.text, "After each stage, wait for the user's response"
  end
end
