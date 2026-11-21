module Embeddings
  class Provider
    class Error < StandardError; end

    def embed(_texts, prefix: nil)
      raise NotImplementedError
    end
  end
end
