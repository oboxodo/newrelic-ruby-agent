require 'benchmark'

TIMES = 100_000
RANGE1 = (1..100_000)
RANGE2 = (77_000..125_000)
RANGES = [1..10_000, 15_000..20_000, 60_000..70_000, 90_000..120_000]

Benchmark.bm do |bench|
  bench.report('Original intersects?') do
    TIMES.times do
      RANGE1.include?(RANGE2.begin) || RANGE2.include?(RANGE1.begin)
    end
  end
  bench.report('New intersects?') do
    TIMES.times do
      RANGE2.begin == RANGE1.begin || RANGE1.cover?(RANGE2.begin) || RANGE2.cover?(RANGE1.begin)
    end
  end
end

puts
puts
puts

Benchmark.bm do |bench|
  bench.report('Original merge') do
    TIMES.times do
      range_min = RANGE1.begin < RANGE2.begin ? RANGE1.begin : RANGE2.begin
      range_max = RANGE1.end > RANGE2.end ? RANGE1.end : RANGE2.end
      range_min..range_max
    end
  end
  bench.report('New merge') do
    TIMES.times do
      (RANGE1.begin < RANGE2.begin ? RANGE1.begin : RANGE2.begin)..(RANGE1.end > RANGE2.end ? RANGE1.end : RANGE2.end)
    end
  end
end


puts
puts
puts

Benchmark.bm do |bench|
  bench.report('Original merge_or_append') do
    TIMES.times do
      duped = RANGES.dup
      merged = false
      duped.each_with_index do |r, i|
        if r.include?(RANGE2.begin) || RANGE2.include?(r.begin)
          range_min = r.begin < RANGE2.begin ? r.begin : RANGE2.begin
          range_max = r.end > RANGE2.end ? r.end : RANGE2.end
          merged = range_min..range_max
          duped[i] = merged
          merged = true
        end
        duped.push(RANGE2) unless merged
      end
    end
  end
  bench.report('New merge_or_append') do
    TIMES.times do

    end
  end
end

