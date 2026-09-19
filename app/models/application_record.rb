class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def to_mcp_response
    result = [ self.class.name ]
    result += attributes.map do |key, value|
      "  **#{key}**: #{value}"
    end

    result.join("\n")
  end
end
