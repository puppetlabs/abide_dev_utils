# frozen_string_literal: true

module AbideDevUtils
  module Errors
    # Generic error class. Errors in AbideDevUtil all follow the
    # same format: "<msg> <subject>". Each error has a default
    # error message relating to error class name. Subjects should
    # always be the thing that failed (file, class, data, etc.).
    # @param subject [String] what failed
    # @param msg [String] an error message to override the default
    class GenericError < StandardError
      @default = 'Generic error:'
      class << self
        attr_reader :default
      end

      attr_reader :subject

      def initialize(subject = nil, msg: self.class.default)
        @msg = msg
        @subject = subject
        message = subject.nil? ? @msg : "#{@msg} #{@subject}"
        super(message)
      end
    end
  end
end
