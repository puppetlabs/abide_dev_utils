# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Parser
      module Objects
        # Methods for providing and comparing hash digests of objects
        module DigestObject
          # Excludes instance variables that are not used in the digest
          def exclude_from_digest(exclude)
            unless exclude.is_a?(Array) || exclude.is_a?(Symbol)
              raise ArgumentError, 'exclude must be an Array or Symbol'
            end

            @exclude_from_digest ||= []
            if exclude.is_a?(Array)
              exclude.map! do |e|
                normalize_exclusion(e)
              end
              @exclude_from_digest += exclude
            else
              @exclude_from_digest << normalize_exclusion(exclude)
            end
            @exclude_from_digest.uniq!
          end

          # Exclusions are instance variable symbols and must be prefixed with "@"
          def normalize_exclusion(exclude)
            exclude = "@#{exclude}" unless exclude.to_s.start_with?('@')
            exclude.to_sym
          end

          # Checks SHA256 digest equality
          def digest_equal?(other)
            digest == other.digest
          end

          # Returns a SHA256 digest of the object, including the digests of all
          # children
          def digest
            return @digest if defined?(@digest)

            parts = [labeled_self_digest]
            children.each { |child| parts << child.digest } unless children.empty?
            @digest = parts.join('|')
            @digest
          end

          # Returns a labeled digest of the current object
          def labeled_self_digest
            return "#{label}:#{Digest::SHA256.hexdigest(digestable_instance_variables)}" if respond_to?(:label)

            "none:#{Digest::SHA256.hexdigest(digestable_instance_variables)}"
          end

          # Returns a string of all instance variable values that are not nil, empty, or excluded
          def digestable_instance_variables
            instance_vars = instance_variables.reject { |iv| @exclude_from_digest.include?(iv) }.sort_by!(&:to_s)
            return 'empty' if instance_vars.empty?

            var_vals = instance_vars.map { |iv| instance_variable_get(iv) }
            var_vals.reject! { |v| v.nil? || v.empty? }
            return 'empty' if var_vals.empty?

            var_vals.join
          end

          # Compares two objects by their SHA256 digests
          # and returns the degree to which they are similar
          # as a percentage.
          def digest_similarity(other, only_labels: [], label_weights: {})
            digest_parts = sorted_digest_parts(digest)
            number_compared = 0
            cumulative_similarity = 0.0
            digest_parts.each do |digest_part|
              label, self_digest = split_labeled_digest(digest_part)
              next unless only_labels.empty? || only_labels.include?(label)

              label_weight = label_weights.key?(label) ? label_weights[label] : 1.0
              sorted_digest_parts(other.digest).each do |other_digest_part|
                other_label, other_digest = split_labeled_digest(other_digest_part)
                next unless (label == other_label) && (self_digest == other_digest)

                number_compared += 1
                cumulative_similarity += 1.0 * label_weight
                break # break when found
              end
            end
            cumulative_similarity / (number_compared.zero? ? 1.0 : number_compared)
          end

          def sorted_digest_parts(dgst)
            @sorted_digest_parts_cache = {} unless defined?(@sorted_digest_parts_cache)
            return @sorted_digest_parts_cache[dgst] if @sorted_digest_parts_cache.key?(dgst)

            @sorted_digest_parts_cache ||= {}
            @sorted_digest_parts_cache[dgst] = dgst.split('|').sort_by { |part| split_labeled_digest(part).first }
            @sorted_digest_parts_cache[dgst]
          end

          # If one of the digest parts is nil and the other is not, we can't compare
          def non_compatible?(digest_part, other_digest_part)
            (digest_part.nil? || other_digest_part.nil?) && digest_part != other_digest_part
          end

          # Splits a digest into a label and digest
          def split_labeled_digest(digest_part)
            @labeled_digest_part_cache = {} unless defined?(@labeled_digest_part_cache)
            return @labeled_digest_part_cache[digest_part] if @labeled_digest_part_cache.key?(digest_part)

            @labeled_digest_part_cache[digest_part] = digest_part.split(':')
            @labeled_digest_part_cache[digest_part]
          end
        end
      end
    end
  end
end
