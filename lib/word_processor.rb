module WordProcessor
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

  def self.histogram(elements)
    elements
      .reject(&:nil?)
      .inject(Hash.new(0)) { |counter, word| counter[word] += 1; counter }
      .to_a
      .sort {|a, b| b.last <=> a.last }
  end

  def self.merge_word_variants(words)

  end
end