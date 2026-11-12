class RagConversation < ApplicationRecord
  DisplayMessage = Struct.new(:role, :content, :metadata, keyword_init: true)

  belongs_to :user, optional: true

  before_validation :parse_json_messages
  before_validation :parse_json_metadata

  validate :messages_must_be_an_array
  validate :metadata_must_be_a_hash

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at id title updated_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end

  def append_message(role:, content:, metadata: {})
    self.messages = parsed_messages
    self.messages << {
      "role" => role.to_s,
      "content" => content.to_s,
      "metadata" => metadata,
      "created_at" => Time.current.iso8601
    }
    save!
  end

  def messages_for_display
    decoded_messages = parsed_messages
    return [] if decoded_messages.nil?
    return [invalid_message_display] unless decoded_messages.is_a?(Array)

    decoded_messages.map do |message|
      unless message.is_a?(Hash)
        next DisplayMessage.new(role: "Invalid message", content: message.to_s, metadata: nil)
      end

      DisplayMessage.new(
        role: message["role"] || message[:role],
        content: message["content"] || message[:content],
        metadata: message["metadata"] || message[:metadata]
      )
    end
  rescue JSON::ParserError
    [invalid_message_display]
  end

  def metadata_hash
    decoded_metadata = metadata.is_a?(String) ? JSON.parse(metadata) : metadata
    raise ArgumentError, "Conversation metadata must be a JSON object" unless decoded_metadata.is_a?(Hash)

    decoded_metadata
  rescue JSON::ParserError
    raise ArgumentError, "Conversation metadata must contain valid JSON"
  end

  private

  def parse_json_messages
    return unless messages.is_a?(String)

    self.messages = JSON.parse(messages)
  rescue JSON::ParserError
    errors.add(:messages, "must contain valid JSON")
  end

  def messages_must_be_an_array
    errors.add(:messages, "must be an array") unless messages.is_a?(Array)
  end

  def parse_json_metadata
    return unless metadata.is_a?(String)

    self.metadata = JSON.parse(metadata)
  rescue JSON::ParserError
    errors.add(:metadata, "must contain valid JSON")
  end

  def metadata_must_be_a_hash
    errors.add(:metadata, "must be an object") unless metadata.is_a?(Hash)
  end

  def parsed_messages
    return JSON.parse(messages) if messages.is_a?(String)

    messages
  end

  def invalid_message_display
    DisplayMessage.new(
      role: "Invalid message data",
      content: messages.to_s,
      metadata: nil
    )
  end
end
