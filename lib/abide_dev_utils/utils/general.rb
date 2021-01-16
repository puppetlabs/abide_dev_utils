# frozen_string_literal: true

module AbideDevUtils
  module Utils
    def self.deep_copy(hash_obj)
      Marshal.load(Marshal.dump(hash_obj))
    end
  end
end
