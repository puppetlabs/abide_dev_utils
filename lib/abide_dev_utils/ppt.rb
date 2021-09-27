# frozen_string_literal: true

require 'abide_dev_utils/output'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/errors'
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

    def self.add_cis_comment(path, xccdf, number_format: false)
      require 'abide_dev_utils/xccdf'

      parsed_xccdf = AbideDevUtils::XCCDF::Benchmark.new(xccdf)
      return add_cis_comment_to_all(path, parsed_xccdf, number_format: number_format) if File.directory?(path)
      return add_cis_comment_to_single(path, parsed_xccdf, number_format: number_format) if File.file?(path)

      raise AbideDevUtils::Errors::FileNotFoundError, path
    end

    def self.add_cis_comment_to_single(path, xccdf, number_format: false)
      write_cis_comment_to_file(
        path,
        cis_recommendation_comment(
          path,
          xccdf,
          number_format
        )
      )
    end

    def self.add_cis_comment_to_all(path, xccdf, number_format: false)
      comments = {}
      Dir[File.join(path, '*.pp')].each do |puppet_file|
        comment = cis_recommendation_comment(puppet_file, xccdf, number_format)
        comments[puppet_file] = comment unless comment.nil?
      end
      comments.each do |key, value|
        write_cis_comment_to_file(key, value)
      end
      AbideDevUtils::Output.simple('Successfully added comments.')
    end

    def self.write_cis_comment_to_file(path, comment)
      require 'tempfile'
      tempfile = Tempfile.new
      begin
        File.open(tempfile, 'w') do |nf|
          nf.write("#{comment}\n")
          File.foreach(path) do |line|
            nf.write(line) unless line == "#{comment}\n"
          end
        end
        File.rename(path, "#{path}.old")
        tempfile.close
        File.rename(tempfile.path, path)
        File.delete("#{path}.old")
        AbideDevUtils::Output.simple("Added CIS recomendation comment to #{path}...")
      ensure
        tempfile.close
        tempfile.unlink
      end
    end

    def self.cis_recommendation_comment(puppet_file, xccdf, number_format)
      _, control = xccdf.find_cis_recommendation(
        File.basename(puppet_file, '.pp'),
        number_format: number_format
      )
      if control.nil?
        AbideDevUtils::Output.simple("Could not find recommendation text for #{puppet_file}...")
        return nil
      end
      control_title = xccdf.resolve_control_reference(control).xpath('./xccdf:title').text
      "# #{control_title}"
    end
  end
end
