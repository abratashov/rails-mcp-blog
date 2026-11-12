module Embeddings
  class Provider
    class Error < StandardError; end

    def embed(_texts)
      raise NotImplementedError
    end
  end
end
