# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module RangeExtensions
      module_function

      def intersects?(r1, r2)
        r1.include?(r2.begin) || r2.include?(r1.begin)

        # adapted from Rails - activesupport/lib/active_support/core_ext/range/overlaps.rb
        # r2.begin == r1.begin || r1.cover?(r2.begin) || r2.cover?(r1.begin)
      end

      def merge(r1, r2)
        (r1.begin < r2.begin ? r1.begin : r2.begin)..(r1.end > r2.end ? r1.end : r2.end)
      end

      # Takes an array of ranges and a range which it will
      # merge into an existing range if they intersect, otherwise
      # it will append this range to the end the array.
      def merge_or_append(range, ranges)
        i = ranges.index { |r| intersects?(r, range) }
        (ranges[i] = merge(ranges[i], range) and return ranges) if i

        ranges << range
      end

      # Computes the amount of overlap between range and an array of ranges.
      # For efficiency, it assumes that range intersects with each of the
      # ranges in the ranges array.
      def compute_overlap(range, ranges)
        ranges.inject(0) do |memo, other|
          next memo unless intersects?(range, other)
          lower_bound = range.begin > other.begin ? range.begin : other.begin
          upper_bound = range.end < other.end ? range.end : other.end
          memo += upper_bound - lower_bound
        end
      end
    end
  end
end
