require 'set'

def read_most_common_words
  File.read('100_000-english.txt').split("\n")
end

def read_etymologies
  File.read('etymwn.tsv').split("\n").map do |line|
    parts = line.downcase.split("\t")
    [parts[0], parts[2]]
  end.map do |word, origin|
    origin_parts = origin.split(' ')
    [word[0...3], word[5..], origin_parts[0][0..-2], origin_parts[1]]
  end.reject do |word, origin_lang, origin|
    word.start_with?('-') || word.end_with?('-') || origin.start_with?('-') || origin.end_with?('-') || word.start_with?("'")
  end
end


def read_word_vectors()
  File.read('glove.6B.50d.txt').split("\n").map do |line|
    parts = line.split(" ")
    [parts[0], parts[1...].map(&:to_f)]
  end.to_h
end

def build_etymology_graph(etymologies)
  word_lang_to_node_map = {}

  etymologies.select do |language, word, origin_language, origin|
    true
  end.each_with_index do |(language, word, origin_language, origin), index|
    if index % (etymologies.count / 10.0).to_i == 0
      puts "Building graph... #{(index / etymologies.count.to_f * 100).round}%"
    end

    node = word_lang_to_node_map[[word, language]] || {
      word: word,
      language: language,
      descendants: [],
      is_leaf: true,
      origin_node: nil
    }
    node[:is_leaf] = true

    origin_node = word_lang_to_node_map[[origin, origin_language]] || {
      word: origin,
      language: origin_language,
      descendants: [],
      is_leaf: false,
      origin_node: nil
    }
    origin_node[:descendants] << node

    node[:origin_node] = origin_node

    word_lang_to_node_map[[word, language]] = node
    word_lang_to_node_map[[origin, origin_language]] = origin_node
  end

  puts "Done.\n\n"

  word_lang_to_node_map
end

def recursively_print_node_origin(node, indent: 0, include_num_descendants: false)
  return if node.nil?

  puts ("  " * indent) + node_description(node, include_num_descendants: include_num_descendants)
  recursively_print_node_origin(node[:origin_node], indent: indent + 1, include_num_descendants: include_num_descendants)
end

def print_origin_of_word(word, language, etymology_graph, include_num_descendants: false)
  node = etymology_graph[[word, language]]
  if node.nil?
    puts "Unknown word/language"
  end

  recursively_print_node_origin(node, include_num_descendants: include_num_descendants)
end

def print_word_tree_for_node(node, etymology_graph, indent_level: 0, max_depth: 20, include_num_descendants: false)
  return if max_depth <= 0

  puts ("  " * indent_level) + node_description(node, include_num_descendants: include_num_descendants)
  node[:descendants].each do |desc|
    print_word_tree_for_node(desc, etymology_graph, indent_level: indent_level + 1, max_depth: max_depth - 1, include_num_descendants: include_num_descendants)
  end
end

def all_english_leaf_descendant_words_of_node(node, max_depth: 20)
  return [] if node.nil?
  return [] if max_depth <= 0

  words = []

  if node[:language] == 'eng' && node[:is_leaf]
    words << node[:word]
  end

  words += node[:descendants].map do |desc|
    all_english_leaf_descendant_words_of_node(desc, max_depth: max_depth - 1)
  end.flatten

  words
end

def all_english_leaf_ancestors_of_node(node, max_depth: 20)
  return [] if node.nil?
  return [] if max_depth <= 0

  words = []

  if node[:language] == 'eng' && node[:is_leaf]
    words << node[:word]
  end

  if (origin_node = node[:origin_node])
    words += all_english_leaf_ancestors_of_node(origin_node, max_depth: max_depth - 1)
  end

  words
end

def print_word_tree(word, language, etymology_graph, max_depth: 3, include_num_descendants: false)
  node = etymology_graph[[word, language]]
  if node.nil?
    puts "Unknown word/language"
    return
  end

  print_word_tree_for_node(node, etymology_graph, max_depth: max_depth, include_num_descendants: include_num_descendants)
end

def node_description(node, include_num_descendants: false)
  "#{node[:language]}: #{node[:word]}" + (include_num_descendants ? ", #{node[:descendants].count} descendant(s)" : "")
end

def print_origin_info(node)
  origin_node = node[:origin_node]
  if origin_node.nil?
    puts "No origin"
    return
  end

  puts "Origin: #{node_description(origin_node)}, #{origin_node[:descendants].count} descendant(s)"
end

def root_origin_node_of_node(node, etymology_graph, max_depth: 20)
  return node if max_depth <= 0

  origin_node = node[:origin_node]
  return node if origin_node.nil?
  return node if origin_node[:word]&.end_with?('-')

  root_origin_node_of_node(origin_node, etymology_graph, max_depth: max_depth - 1)
end

def root_origin_node_of_word(word, language, etymology_graph)
  node = etymology_graph[[word, language]]
  if node.nil?
    return nil
  end

  root_origin_node_of_node(node, etymology_graph)
end

def vec_distance(vec1, vec2)
  vec1.each_with_index.map do |vec1_value, index|
    (vec1_value - vec2[index])**2
  end.sum**0.5
end

def word_has_common_prefix(word)
  ['re', 'bi', 'in', 'un', 'non'].any? do |prefix|
    word.start_with?(prefix)
  end
end

def words_have_shared_prefix(word1, word2)
  word1[0...3] == word2[0...3]
end

def main(should_exclude_common_starts: false, common_subword_exclusion_length: nil)
  most_common_words = read_most_common_words
  word_vectors = read_word_vectors
  etymology_graph = build_etymology_graph(read_etymologies)

  words_i_dont_know = ['gree', 'leed', 'copyboy', 'midcap', 'een', 'poisonwood', 'localhost', 'morningtide', 'seel', 'mesic', 'idée', 'olivia']

  language = 'eng'
  (most_common_words - words_i_dont_know).reject do |word|
    word_has_common_prefix(word)
  end.map do |word|
    word_vec = word_vectors[word]
    next [] if word_vec.nil?

    node = etymology_graph[[word, language]]
    root_node = root_origin_node_of_word(word, language, etymology_graph)

    (all_english_leaf_descendant_words_of_node(root_node) - all_english_leaf_descendant_words_of_node(node) - all_english_leaf_ancestors_of_node(node) - words_i_dont_know).reject do |related_word|
      (word_has_common_prefix(word) && word_has_common_prefix(related_word)) ||
        words_have_shared_prefix(word, related_word)
    end.reject do |related_word|
      word_has_common_prefix(related_word)
    end.reject do |related_word|
      next false if !should_exclude_common_starts
      related_word[0] == word[0]
    end.reject do |related_word|
      next false if common_subword_exclusion_length.nil?
      (related_word.length - common_subword_exclusion_length + 1).times.map do |index|
        related_word[index...index + 4]
      end.any? do |subword|
        word.include?(subword)
      end
    end.map do |related_word|
      [related_word, word_vectors[related_word]]
    end.select(&:last).map do |related_word, related_word_vec|
      [word, related_word, vec_distance(word_vec, related_word_vec)]
    end
  end.flatten(1).sort_by(&:last).reverse.each do |word, related_word, distance|
    puts "#{word} <-> #{related_word} - #{distance}"
  end
end
# main(should_exclude_common_starts: false, common_subword_exclusion_length: 4)

def print_word_info(word, etymology_graph: nil)
  if etymology_graph.nil?
    etymologies = read_etymologies
    etymology_graph = build_etymology_graph(etymologies)
  end

  root_node = root_origin_node_of_word(word, 'eng', etymology_graph)
  puts "tree for #{root_node[:language]}: #{root_node[:word]}"
  print_word_tree(root_node[:word], root_node[:language], etymology_graph, max_depth: 20, include_num_descendants: false)
end

etymology_graph = build_etymology_graph(read_etymologies)
# print_word_info('effigy', etymology_graph: etymology_graph)