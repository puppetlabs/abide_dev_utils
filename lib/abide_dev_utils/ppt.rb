# frozen_string_literal: true

require 'abide_dev_utils/output'
require 'abide_dev_utils/ppt/class_utils'

module AbideDevUtils
  module Ppt
    # Renames a Puppet class by renaming the class declaration and class file
    # @param from [String] fully-namespaced existing Puppet class name
    # @param to [String] fully-namespaced new Puppet class name
    def self.rename_puppet_class(from, to, **kwargs)
      from_path = ClassUtils.path_from_class_name(from)
      to_path = ClassUtils.path_from_class_name(to)
      file_path = kwargs.fetch(:declaration_in_to_file, false) ? to_path : from_path
      raise ClassFileNotFoundError, "Path:#{file_path}" if !File.file?(file_path) && kwargs.fetch(:validate_path, true)

      rename_puppet_class_declaration(from, to, file_path, **kwargs)
      AbideDevUtils::Output.simple("Renamed #{from} to #{to} at #{file_path}.")
      return unless kwargs.fetch(:declaration_only, false)

      rename_class_file(from_path, to_path, **kwargs)
      AbideDevUtils::Output.simple("Renamed file #{from_path} to #{to_path}.")
    end

    def self.audit_class_names(dir, **kwargs)
      mismatched = ClassUtils.find_all_mismatched_class_declarations(dir)
      outfile = kwargs.key?(:file) ? File.open(kwargs[:file], 'a') : nil
      quiet = kwargs.fetch(:quiet, false)
      mismatched.each do |class_file|
        AbideDevUtils::Output.simple("Mismatched class name in file #{class_file}") unless quiet
        outfile << "MISMATCHED_CLASS_NAME: #{class_file}\n" unless outfile.nil?
      end
      outfile&.close
      AbideDevUtils::Output.simple("Found #{mismatched.length} mismatched classes in #{dir}.") unless quiet
    ensure
      outfile&.close
    end

    def self.fix_class_names_file_rename(dir, **kwargs)
      mismatched = ClassUtils.find_all_mismatched_class_declarations(dir)
      progress = AbideDevUtils::Output.progress(title: 'Renaming files', total: mismatched.length)
      mismatched.each do |class_path|
        should = ClassUtils.path_from_class_name(class_name_from_declaration(class_path))
        ClassUtils.rename_class_file(class_path, should, **kwargs)
        progress.increment
        AbideDevUtils::Output.simple("Renamed file #{class_path} to #{should}...") if kwargs.fetch(:verbose, false)
      end
      AbideDevUtils::Output.simple('Successfully fixed all classes.')
    end

    def self.fix_class_names_class_rename(dir, **kwargs)
      mismatched = ClassUtils.find_all_mismatched_class_declarations(dir)
      progress = AbideDevUtils::Output.progress(title: 'Renaming classes', total: mismatched.length)
      mismatched.each do |class_path|
        current = ClassUtils.class_name_from_declaration(class_path)
        should = ClassUtils.class_name_from_path(class_path)
        ClassUtils.rename_puppet_class_declaration(current, should, class_path, **kwargs)
        progress.increment
        AbideDevUtils::Output.simple("Renamed #{from} to #{to} at #{file_path}...") if kwargs.fetch(:verbose, false)
      end
      AbideDevUtils::Output.simple('Successfully fixed all classes.')
    end

    def self.generate_coverage_report(puppet_class_dir, hiera_path, profile = nil)
      require 'abide_dev_utils/ppt/coverage'
      CoverageReport.generate(puppet_class_dir, hiera_path, profile)
    end

    def self.build_new_object(type, name, opts)
      require 'abide_dev_utils/ppt/new_obj'
      AbideDevUtils::Ppt::NewObjectBuilder.new(
        type,
        name,
        opts: opts,
        vars: opts.fetch(:vars, '').split(',').map { |i| i.split('=') }.to_h # makes the str a hash
      ).build
    end
  end
end
