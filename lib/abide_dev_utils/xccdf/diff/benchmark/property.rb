# frozen_string_literal: true

require 'amatch'

module AbideDevUtils
  module XCCDF
    module Diff
      # Diffs benchmark properties.
      module BenchmarkPropertyDiff
        DEFAULT_PROPERTY_DIFF_OPTS = {
          rule_properties_for_similarity: %i[title description rationale fixtext],
          rule_properties_for_confidence: %i[description rationale fixtext],
          rule_confidence_property_threshold: 0.7,
          rule_confidence_total_threshold: 0.5,
          digest_similarity_threshold: 0.75,
          digest_similarity_label_weights: {
            'title' => 4.0,
          },
          digest_similarity_only_labels: %w[title description fixtext rationale],
          digest_top_x_similarities: 10,
        }.freeze

        def safe_rule_prop(rule, prop)
          rule.respond_to?(prop) ? rule.send(prop).to_s : :none
        end

        def self_rule_vals
          @self_rule_vals ||= {}
        end

        def other_rule_vals
          @other_rule_vals ||= {}
        end

        def add_rule_val(rule, prop, val, container: nil)
          raise ArgumentError, 'container must not be nil' if container.nil?

          return unless container.dig(rule, prop).nil?

          container[rule] ||= {}
          container[rule][prop] = val
        end

        def add_self_rule_val(rule, prop, val)
          add_rule_val(rule, prop, val, container: self_rule_vals)
        end

        def add_other_rule_val(rule, prop, val)
          add_rule_val(rule, prop, val, container: other_rule_vals)
        end

        def same_rule?(prop_similarities)
          confidence_indicator = 0.0
          opts[:rule_properties_for_confidence].each do |prop|
            confidence_indicator += 1.0 if prop_similarities[prop] >= opts[:rule_confidence_property_threshold]
          end
          (confidence_indicator / opts[:rule_properties_for_confidence].length) >= opts[:rule_confidence_total_threshold]
        end

        def maxed_digest_similarities(child, other_children)
          similarities = other_children.each_with_object([]) do |other_child, ary|
            if other_child.digest_equal? child
              ary << [1.0, other_child]
              next
            end

            d_sim = child.digest_similarity(other_child,
                                            only_labels: opts[:digest_similarity_only_labels],
                                            label_weights: opts[:digest_similarity_label_weights])
            ary << [d_sim, other_child]
          end
          max_digest_similarities(similarities)
        end

        def max_digest_similarities(digest_similarities)
          digest_similarities.reject! { |s| s[0] < opts[:digest_similarity_threshold] }
          return digest_similarities if digest_similarities.empty?

          digest_similarities.max_by(opts[:digest_top_x_similarities]) { |s| s[0] }
        end

        def rule_property_similarity(rule1, rule2)
          prop_similarities = {}
          prop_diff = {}
          opts[:rule_properties_for_similarity].each do |prop|
            add_self_rule_val(rule1, prop, safe_rule_prop(rule1, prop).to_s)
            add_other_rule_val(rule2, prop, safe_rule_prop(rule2, prop).to_s)
            prop_similarities[prop] = self_rule_vals[rule1][prop].levenshtein_similar(other_rule_vals[rule2][prop])
            if prop_similarities[prop] < 1.0
              prop_diff[prop] = { self: self_rule_vals[rule1][prop], other: other_rule_vals[rule2][prop] }
            end
          end
          total = prop_similarities.values.sum / opts[:rule_properties_for_similarity].length
          {
            total: total,
            prop_similarities: prop_similarities,
            prop_diff: prop_diff,
            confident_same: same_rule?(prop_similarities),
          }
        end

        def most_similar(child, maxed_digest_similarities)
          most_similar_map = maxed_digest_similarities.each_with_object({}) do |similarity, h|
            prop_similarities = rule_property_similarity(child, similarity[1])
            if child.title.to_s == similarity[1].title.to_s
              prop_similarities[:total] = 99.0 # magic number denoting a title match
            end
            h[prop_similarities[:total]] = { self: child, other: similarity[1] }.merge(prop_similarities)
          end
          most_similar_map[most_similar_map.keys.max]
        end

        def find_most_similar(children, other_children)
          children.each_with_object({}) do |benchmark_child, h|
            maxed_similarities = maxed_digest_similarities(benchmark_child, other_children)
            next if maxed_similarities.empty?

            best = most_similar(benchmark_child, maxed_similarities)
            next if best.nil? || best.empty?

            h[benchmark_child] = best
          end
        end
      end
    end
  end
end
