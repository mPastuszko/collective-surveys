# encoding: utf-8

module WordProcessor
  CharSubs = {
    source: 'ąćęłńóśźż',
    target: 'acelnoszz'
  }

  def self.statistics(histogram)
    frequencies = histogram.map {|h| h[:frequency] }
    frequency_sample = frequencies
      .each_with_index
      .map { |freq, index| [index] * freq }
      .flatten
    frequency_sample_scale = frequency_sample.to_scale
    sd = frequencies.to_scale.standard_deviation_sample
    skew = frequency_sample_scale.skew
    kurtosis = frequency_sample_scale.kurtosis
    {
      standard_deviation: sd.nan? ? 0.0 : sd,
      skewness: skew.nan? ? 0.0 : skew,
      kurtosis: kurtosis.nan? ? 0.0 : kurtosis
    }
  end

  def self.histograms_difference_matrix(word_sets, histogram_length)
    words = word_sets.map { |ws| ws[:base_word] }
    histogram_matrices = word_sets.inject({}) { |memo, ws|
      histogram = ws[:histogram][0...histogram_length].map {|h| h[:frequency] }
      histogram.fill(1, histogram.size...histogram_length)
      memo[ws[:base_word]] = Matrix[histogram]
      memo
    }
    differences_matrix = words.map { |word1|
      words.map { |word2|
        m1, m2 = histogram_matrices[word1], histogram_matrices[word2]
        Statsample::Test.chi_square(m1, m2).chi_square.to_f
      }
    }
    labelled_matrix = words.zip(differences_matrix)
  end

  def self.similar_distributions(word, histograms_difference_matrix, limit = -1)
    words = histograms_difference_matrix.map(&:first)
    histograms_difference_matrix
      .assoc(word)
      .last
      .each_with_index
      .sort
      .slice(1...limit+1) # skip first because it is the same word as the given one
      .map { |diff, index|
        [words[index], diff]
      }
  end

  def self.merge(histogram, merged_words)
    result = histogram.dup
    merged_words.each do |merge_set|
      main, rest = merge_set.first, merge_set[1..-1]
      main_pos = result.index {|h| h[:word] == main }
      result[main_pos] = result[main_pos].dup
      result[main_pos][:merged_words] ||= []
      result[main_pos][:merged_words] += rest
      rest.each do |w|
        pos = result.index {|h| h[:word] == w }
        result[main_pos][:frequency] += result[pos][:frequency]
        result.delete_at(pos)
      end
    end
    result.sort {|a, b| b[:frequency] <=> a[:frequency] }
  end

  def self.histogram(elements)
    elements
      .reject(&:nil?)
      .inject(Hash.new(0)) { |counter, word| counter[word] += 1; counter }
      .map { |word, counter|
        {
          word: word,
          frequency: counter
        }
      }
      .sort {|a, b| b[:frequency] <=> a[:frequency] }
  end

  def self.normalize_national_chars(words)
    best_forms = Hash.new { |k, v| v }
    words.compact.each do |e|
      better_form = e.count(CharSubs[:source]) > best_forms[ascii_form(e)].count(CharSubs[:source])
      if better_form
        best_forms[ascii_form(e)] = e
      end
    end
    words.map { |e| best_forms[ascii_form(e.to_s)] }
  end

  def self.clean(words)
    words.reject { |w|
      w.strip.empty?
    }
  end

  def self.ascii_form(text)
    text.tr(CharSubs[:source], CharSubs[:target])
  end

  def self.fas(histogram)
    sum = histogram
      .map {|h| h[:frequency] }
      .inject(:+)
    histogram.map {|h| h[:frequency].to_f / sum }
  end
end