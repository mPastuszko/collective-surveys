# encoding: utf-8

module WordProcessor
  CharSubs = {
    source: 'ąćęłńóśźż',
    target: 'acelnoszz'
  }

  def self.statistics(histogram)
    frequencies = histogram.map(&:last)
    frequency_sample = frequencies
      .each_with_index
      .map { |freq, index| [index] * freq }
      .flatten
    frequency_sample_scale = frequency_sample.to_scale
    {
      standard_deviation: frequencies.to_scale.standard_deviation_sample,
      skewness: frequency_sample_scale.skew,
      kurtosis: frequency_sample_scale.kurtosis
    }
  end

  def self.histograms_difference_matrix(word_sets, histogram_length)
    words = word_sets.map { |ws| ws[:base_word] }
    histogram_matrices = word_sets.inject({}) { |memo, ws|
      histogram = ws[:histogram][0...histogram_length].map(&:last)
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

  def self.histogram(elements)
    elements
      .reject(&:nil?)
      .inject(Hash.new(0)) { |counter, word| counter[word] += 1; counter }
      .to_a
      .sort {|a, b| b.last <=> a.last }
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
end