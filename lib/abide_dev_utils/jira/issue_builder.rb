# frozen_string_literal: true

require_relative '../errors/jira'

module AbideDevUtils
  module Jira
    class IssueBuilder
      CUSTOM_FIELDS = {
        'epic_link' => 'customfield_10014',
        'epic_name' => 'customfield_10011',
      }.freeze

      FIELD_DEFAULTS = {
        'issuetype' => 'Task',
        'priority' => 'Medium',
        'labels' => ['abide_dev_utils'],
      }.freeze

      REQUIRED_FIELDS = %w[project summary].freeze

      def initialize(client, finder)
        @client = client
        @finder = finder
      end

      def can_create?(type)
        respond_to?("create_#{type}".to_sym, true)
      end

      def create(type, **fields)
        type = type.to_s.downcase.to_sym
        raise ArgumentError, "Invalid type \"#{type}\"; no method \"create_#{type}\"" unless can_create?(type)

        fields = process_fields(fields)
        send("create_#{type}".to_sym, **fields)
      end

      private

      attr_reader :client

      def create_issue(**fields)
        iss = client.Issue.build
        iss.save({ 'fields' => fields })
        iss
      rescue StandardError => e
        raise AbideDevUtils::Errors::Jira::CreateIssueError, e
      end

      def create_subtask(**fields)
        fields['parent'] = find_if_not_type(:issue, client.Issue.target_class, fields['parent'])
        issue_fields = fields['parent'].attrs['fields']
        fields['project'] = issue_fields['project']
        fields['issuetype'] = find_if_not_type(:issuetype, client.Issuetype.target_class, 'Sub-task')
        fields['priority'] = issue_fields['priority']
        iss = client.Issue.build
        iss.save({ 'fields' => fields })
        iss
      rescue StandardError => e
        raise AbideDevUtils::Errors::Jira::CreateSubtaskError, e
      end

      def process_fields(fields)
        fields = fields.dup
        normalize_field_keys!(fields)
        validate_required_fields!(fields)
        normalize_field_values(fields)
      end

      def validate_required_fields!(fields)
        missing = REQUIRED_FIELDS.reject { |f| fields.key?(f) }
        raise "Missing required field(s) \"#{missing}\"; present fields: \"#{fields.keys}\"" unless missing.empty?
      end

      def normalize_field_keys!(fields)
        fields.transform_keys! { |k| k.to_s.downcase }
        fields.transform_keys! { |k| CUSTOM_FIELDS[k] || k }
      end

      def normalize_field_values(fields)
        fields = FIELD_DEFAULTS.merge(fields).map do |k, v|
          v = case k
              when 'labels'
                v.is_a?(Array) ? v : [v]
              when 'issuetype'
                find_if_not_type(:issuetype, client.Issuetype.target_class, v)
              when 'parent'
                find_if_not_type(:issue, client.Issue.target_class, v)
              when 'priority'
                find_if_not_type(:priority, client.Priority.target_class, v)
              when 'epic_link', CUSTOM_FIELDS['epic_link']
                find_if_not_type(:issue, client.Issue.target_class, v)&.key || v
              when 'project'
                find_if_not_type(:project, client.Project.target_class, v)
              else
                v
              end
          [k, v]
        end
        fields.to_h
      end

      def find_if_not_type(typesym, typeklass, obj)
        return obj if obj.is_a?(typeklass)

        @finder.send(typesym, obj)
      end
    end
  end
end
