# frozen_string_literal: true

require_relative '../output'

module AbideDevUtils
  module Jira
    module DryRun
      def dry_run(*method_names)
        method_names.each do |method_name|
          proxy = Module.new do
            define_method(method_name) do |*args, **kwargs|
              if !!@dry_run
                case method_name
                when %r{^create}
                  AbideDevUtils::Output.simple("DRY RUN: #{self.class.name}##{method_name}(#{args[0]}, #{args[1].map { |k, v| "#{k}: #{v.inspect}" }.join(', ')})")
                  sleep 0.1
                  return DummyIssue.new if args[0].match?(%r{^issue$})
                  return DummySubtask.new if args[0].match?(%r{^subtask$})
                when %r{^find}
                  AbideDevUtils::Output.simple("DRY RUN: #{self.class.name}##{method_name}(#{args[0]}, #{args[1].inspect})")
                  return DummyIssue.new if args[0].match?(%r{^issue$})
                  return DummySubtask.new if args[0].match?(%r{^subtask$})
                  return DummyProject.new if args[0].match?(%r{^project$})

                  "Dummy #{args[0].capitalize}"
                else
                  AbideDevUtils::Output.simple("DRY RUN: #{self.class.name}##{method_name}(#{args.map(&:inspect).join(', ')})")
                end
              else
                super(*args, **kwargs)
              end
            end
          end
          self.prepend(proxy)
        end
      end

      def dry_run_simple(*method_names)
        method_names.each do |method_name|
          proxy = Module.new do
            define_method(method_name) do |*args, **kwargs|
              return if !!@dry_run

              super(*args, **kwargs)
            end
          end
          self.prepend(proxy)
        end
      end

      def dry_run_return_true(*method_names)
        method_names.each do |method_name|
          proxy = Module.new do
            define_method(method_name) do |*args, **kwargs|
              return true if !!@dry_run

              super(*args, **kwargs)
            end
          end
          self.prepend(proxy)
        end
      end

      def dry_run_return_false(*method_names)
        method_names.each do |method_name|
          proxy = Module.new do
            define_method(method_name) do |*args, **kwargs|
              return false if !!@dry_run

              super(*args, **kwargs)
            end
          end
          self.prepend(proxy)
        end
      end

      class Dummy
        attr_reader :dummy

        def initialize
          @dummy = true
        end
      end

      class DummyIssue < Dummy
        attr_reader :summary, :key

        def initialize
          super
          @summary = 'Dummy Issue'
          @key = 'DUM-111'
        end

        def attrs
          {
            'fields' => {
              'project' => 'dummy',
              'priority' => 'dummy',
            },
          }
        end
      end

      class DummySubtask < DummyIssue
        def initialize
          super
          @summary = 'Dummy Subtask'
          @key = 'DUM-222'
        end

        def attrs
          {
            'fields' => {
              'project' => 'dummy',
              'priority' => 'dummy',
              'parent' => DummyIssue.new,
            },
          }
        end
      end

      class DummyProject < Dummy
        attr_reader :key, :issues

        def initialize
          super
          @key = 'DUM'
          @issues = [DummyIssue.new, DummySubtask.new]
        end
      end
    end
  end
end
