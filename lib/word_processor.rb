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

  def self.histogram(elements)
    elements
      .reject(&:nil?)
      .inject(Hash.new(0)) { |counter, word| counter[word] += 1; counter }
      .to_a
      .sort {|a, b| b.last <=> a.last }
  end

  def self.normalize_national_chars(words)
    best_forms = Hash.new { |k, v| v }
    words.each do |e|
      better_form = e.count(CharSubs[:source]) > best_forms[ascii_form(e)].count(CharSubs[:source])
      if better_form
        best_forms[ascii_form(e)] = e
      end
    end
    words.map { |e| best_forms[ascii_form(e)] }
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