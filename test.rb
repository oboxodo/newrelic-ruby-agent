require 'benchmark'
# require 'benchmark/ips'

RUNS = 100.freeze
STARTING_ARRAY_SIZE = 100.freeze
EXISTING_RANGES = [(Time.now.to_f)..(Time.now.to_f + 5.0)]
until EXISTING_RANGES.size == STARTING_ARRAY_SIZE
  start = EXISTING_RANGES.last.end + 2.0
  stop = start + rand((start + 1.0)..(start + 10_000.0))
  EXISTING_RANGES << (start..stop)
end
EXISTING_RANGES.freeze
NEW_RANGES = [(EXISTING_RANGES.first.begin + 2.0)..(EXISTING_RANGES.first.begin + 3.0)]
until NEW_RANGES.size == STARTING_ARRAY_SIZE
  start = NEW_RANGES.last.end + 2.0
  stop = start + rand((start + 1.0)..(start + 10_000.0))
  NEW_RANGES << (start..stop)
end
NEW_RANGES.freeze

class Original
  def intersects?(r1, r2)
    r1.include?(r2.begin) || r2.include?(r1.begin)
  end

  def merge(r1, r2)
    return unless intersects?(r1, r2)
    range_min = r1.begin < r2.begin ? r1.begin : r2.begin
    range_max = r1.end > r2.end ? r1.end : r2.end
    range_min..range_max
  end

  def merge_or_append(range, ranges)
    ranges.each_with_index do |r, i|
      if merged = merge(r, range)
        ranges[i] = merged
        return ranges
      end
    end
    ranges.push(range)
  end
end

class Improved
  def intersects?(r1, r2)
    r1.begin > r2.begin ? r2.cover?(r1.begin) : r1.cover?(r2.begin)
  end

  def merge(r1, r2)
    (r1.begin < r2.begin ? r1.begin : r2.begin)..(r1.end > r2.end ? r1.end : r2.end)
  end

  def merge_or_append(range, ranges)
    i = ranges.index { |r| intersects?(r, range) }
    (ranges[i] = merge(ranges[i], range) and return ranges) if i
    ranges << range
  end
end

class Experimental
  def intersects?(r1, r2)
    r1.begin > r2.begin ? r2.cover?(r1.begin) : r1.cover?(r2.begin)
  end

  def merge(r1, r2)
    (r1.begin < r2.begin ? r1.begin : r2.begin)..(r1.end > r2.end ? r1.end : r2.end)
  end

  def merge_or_append(range, ranges)
    # return ranges << range if ranges.size > 10
    i = ranges.index { |r| intersects?(r, range) }
    (ranges[i] = merge(ranges[i], range) and return ranges) if i
    ranges << range
  end
end

Benchmark.bm do |bench|
# Benchmark.ips do |bench|
  bench.report('Original') do
    RUNS.times do
      original = Original.new
      ranges = EXISTING_RANGES.dup
      NEW_RANGES.each do |new_range|
        original.merge_or_append(new_range, ranges)
      end
    end
  end
  bench.report('Improved') do
    RUNS.times do
      improved = Improved.new
      ranges = EXISTING_RANGES.dup
      NEW_RANGES.each do |new_range|
        improved.merge_or_append(new_range, ranges)
      end
    end
  end
  bench.report('Experimental') do
    RUNS.times do
      experimental = Experimental.new
      ranges = EXISTING_RANGES.dup
      NEW_RANGES.each do |new_range|
        experimental.merge_or_append(new_range, ranges)
      end
    end
  end
end
