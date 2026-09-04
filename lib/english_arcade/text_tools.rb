# frozen_string_literal: true

module EnglishArcade
  # Small, dependency-free text primitives shared by the Arena generators and
  # graders. Normalized comparisons work on words, while span helpers retain
  # authored punctuation so technical phrases are not silently recomposed.
  module TextTools
    STOPWORDS = %w[
      a an and are as at be been being but by can could did do does for from
      had has have he her here him his how i if in into is it its me more most
      my no not of on or our out she so than that the their them then there
      these they this to was we were what when where which who will with would
      you your
    ].freeze

    WORD = /[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)?/.freeze
    module_function

    def normalize(value)
      words(value).join(" ")
    end

    def words(value)
      value.to_s.downcase.scan(WORD)
    end

    def token_ranges(value)
      text = value.to_s
      ranges = []
      offset = 0
      while (match = WORD.match(text, offset))
        ranges << { start: match.begin(0), finish: match.end(0) }
        offset = match.end(0)
      end
      ranges
    end

    def span_crosses_punctuation?(value, start, length)
      ranges = token_ranges(value)
      first = ranges[start.to_i]
      last = ranges[start.to_i + length.to_i - 1]
      return true unless first && last && length.to_i.positive?

      value.to_s[first[:finish]...last[:start]].to_s.match?(/[^\s]/)
    end

    # One display token per normalized word, with punctuation attached to the
    # nearest word. The indexes therefore remain compatible with `words`,
    # while the learner still sees `/payments`, commas, and sentence marks.
    def display_tokens(value)
      text = value.to_s
      ranges = token_ranges(text)
      cursor = 0
      result = []
      ranges.each_with_index do |range, index|
        gap = text[cursor...range[:start]].to_s
        token = text[range[:start]...range[:finish]].to_s
        if index.zero?
          token = "#{gap}#{token}"
        else
          punctuation = gap.gsub(/\s+/, "")
          if punctuation.start_with?("/") && gap.match?(/\s\S/)
            token = "#{punctuation}#{token}"
          else
            result[-1] = "#{result[-1]}#{punctuation}" unless punctuation.empty?
          end
        end
        result << token
        cursor = range[:finish]
      end
      trailing = text[cursor..].to_s.gsub(/\s+/, "")
      result[-1] = "#{result[-1]}#{trailing}" unless trailing.empty? || result.empty?
      result
    end

    def informative_phrase?(value)
      words(value).any? { |word| !STOPWORDS.include?(word) }
    end

    def word_count(value)
      words(value).length
    end

    # Returns matching word-index pairs in the longest common subsequence.
    # Keeping indexes makes it possible to recover the authored replacement
    # phrases without inventing a wording for a cloze chip.
    def lcs_pairs(left, right)
      a = words(left)
      b = words(right)
      table = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      (a.length - 1).downto(0) do |i|
        (b.length - 1).downto(0) do |j|
          table[i][j] = if a[i] == b[j]
            table[i + 1][j + 1] + 1
          else
            [ table[i + 1][j], table[i][j + 1] ].max
          end
        end
      end

      pairs = []
      i = j = 0
      while i < a.length && j < b.length
        if a[i] == b[j]
          pairs << [ i, j ]
          i += 1
          j += 1
        elsif table[i + 1][j] >= table[i][j + 1]
          i += 1
        else
          j += 1
        end
      end
      pairs
    end

    def lcs_length(left, right)
      lcs_pairs(left, right).length
    end

    def similarity(left, right)
      denominator = word_count(right)
      return 0.0 if denominator.zero?

      lcs_length(left, right).fdiv(denominator)
    end

    # Each entry is an authored replacement between LCS anchors. Token indexes
    # refer to normalized best-answer words, which keeps this stable across
    # whitespace and punctuation-only pack edits.
    def diff_segments(best_answer, alternative)
      left = words(best_answer)
      right = words(alternative)
      anchors = [ [ -1, -1 ], *lcs_pairs(best_answer, alternative), [ left.length, right.length ] ]
      anchors.each_cons(2).filter_map do |(left_before, right_before), (left_after, right_after)|
        best_tokens = left[(left_before + 1)...left_after] || []
        alternative_tokens = right[(right_before + 1)...right_after] || []
        next if best_tokens.empty? || alternative_tokens.empty?

        {
          start: left_before + 1,
          length: best_tokens.length,
          best: best_tokens.join(" "),
          alternative: alternative_tokens.join(" ")
        }
      end
    end

    # Splits a response into recoverable clause-sized chunks. Connector splits
    # are deliberately conservative; the final word grouping is only a safety
    # valve for very short or punctuation-free authored answers.
    def clause_chunks(text, minimum: 3, maximum: 8)
      sentences = text.to_s.strip.split(/(?<=[.!?])\s+/)
      chunks = sentences.flat_map do |sentence|
        sentence.split(/(?<=[;:])\s+|,(?=\s*(?:and|but|so|which|because|then|or|rather than|instead of|unless|while|although|whereas|since|before|after|otherwise|not)\b)/i)
      end.map(&:strip).reject(&:empty?)
      chunks = merge_short_chunks(chunks)
      chunks = split_long_chunks(chunks, minimum) if chunks.length < minimum
      chunks = merge_to_maximum(chunks, maximum)
      chunks
    end

    def merge_short_chunks(chunks)
      result = chunks.each_with_object([]) do |chunk, merged|
        if word_count(chunk) < 4 && merged.any?
          merged[-1] = "#{merged.last} #{chunk}"
        else
          merged << chunk
        end
      end
      if result.length > 1 && word_count(result.first) < 4
        result[0, 2] = [ "#{result.first} #{result[1]}" ]
      end
      result
    end
    private_class_method :merge_short_chunks

    def split_long_chunks(chunks, minimum)
      result = chunks.dup
      while result.length < minimum
        index = result.each_index.max_by { |position| word_count(result[position]) }
        tokens = result[index].to_s.split
        break if tokens.length < 8

        midpoint = tokens.length / 2
        left = tokens.first(midpoint).join(" ")
        right = tokens.drop(midpoint).join(" ")
        result[index, 1] = [ left, right ]
      end
      result
    end
    private_class_method :split_long_chunks

    def merge_to_maximum(chunks, maximum)
      result = chunks.dup
      while result.length > maximum
        index = result.each_index.min_by { |position| word_count(result[position]) + word_count(result[position + 1] || "") }
        index = [ index, result.length - 2 ].min
        result[index, 2] = [ "#{result[index]} #{result[index + 1]}" ]
      end
      result
    end
    private_class_method :merge_to_maximum
  end
end
