import os
from collections import defaultdict
import math

# Helper functions
def read_most_common_words():
    with open('100_000-english.txt', 'r') as file:
        return file.read().splitlines()

def read_etymologies():
    with open('etymwn-20130208/etymologies.tsv', 'r') as file:
        lines = file.read().splitlines()
    etymologies = []
    for line in lines:
        parts = line.lower().split("\t")
        word, origin = parts[0], parts[2]
        origin_parts = origin.split(' ')
        if len(origin_parts) >= 2:
            etymologies.append([
                word[:3],
                word[5:],
                origin_parts[0][:-1],
                origin_parts[1]
            ])
    return [e for e in etymologies if not (
        e[0].startswith('-') or e[0].endswith('-') or
        e[2].startswith('-') or e[2].endswith('-') or
        e[0].startswith("'")
    )]

def read_word_vectors():
    word_vectors = {}
    with open('glove.6B.50d.txt', 'r') as file:
        for line in file:
            parts = line.split()
            word_vectors[parts[0]] = list(map(float, parts[1:]))
    return word_vectors

def build_etymology_graph(etymologies):
    word_lang_to_node_map = {}
    for index, (language, word, origin_language, origin) in enumerate(etymologies):
        if index % (len(etymologies) // 10) == 0:
            print(f"Building graph... {round(index / len(etymologies) * 100)}%")

        node = word_lang_to_node_map.get((word, language), {
            'word': word,
            'language': language,
            'descendants': [],
            'is_leaf': True,
            'origin_node': None
        })
        node['is_leaf'] = True

        origin_node = word_lang_to_node_map.get((origin, origin_language), {
            'word': origin,
            'language': origin_language,
            'descendants': [],
            'is_leaf': False,
            'origin_node': None
        })
        origin_node['descendants'].append(node)

        node['origin_node'] = origin_node

        word_lang_to_node_map[(word, language)] = node
        word_lang_to_node_map[(origin, origin_language)] = origin_node

    print("Done.\n\n")
    return word_lang_to_node_map

def recursively_print_node_origin(node, indent=0, include_num_descendants=False):
    if not node:
        return
    print(("  " * indent) + node_description(node, include_num_descendants=include_num_descendants))
    recursively_print_node_origin(node['origin_node'], indent=indent + 1, include_num_descendants=include_num_descendants)

def print_origin_of_word(word, language, etymology_graph, include_num_descendants=False):
    node = etymology_graph.get((word, language))
    if not node:
        print("Unknown word/language")
        return
    recursively_print_node_origin(node, include_num_descendants=include_num_descendants)

def print_word_tree_for_node(node, etymology_graph, indent_level=0, max_depth=20, include_num_descendants=False):
    if max_depth <= 0 or not node:
        return
    print(("  " * indent_level) + node_description(node, include_num_descendants=include_num_descendants))
    for desc in node['descendants']:
        print_word_tree_for_node(desc, etymology_graph, indent_level=indent_level + 1, max_depth=max_depth - 1, include_num_descendants=include_num_descendants)

def node_description(node, include_num_descendants=False):
    return f"{node['language']}: {node['word']}" + (f", {len(node['descendants'])} descendant(s)" if include_num_descendants else "")

def vec_distance(vec1, vec2):
    return math.sqrt(sum((v1 - v2) ** 2 for v1, v2 in zip(vec1, vec2)))

def word_has_common_prefix(word):
    prefixes = ['re', 'bi', 'in', 'un', 'non']
    return any(word.startswith(prefix) for prefix in prefixes)

def words_have_shared_prefix(word1, word2):
    return word1[:3] == word2[:3]

def main(should_exclude_common_starts=False, common_subword_exclusion_length=None):
    most_common_words = read_most_common_words()
    word_vectors = read_word_vectors()
    etymology_graph = build_etymology_graph(read_etymologies())

    words_i_dont_know = ['gree', 'leed', 'copyboy', 'midcap', 'een', 'poisonwood', 'localhost', 'morningtide', 'seel', 'mesic', 'idée', 'olivia']

    language = 'eng'
    for word in set(most_common_words) - set(words_i_dont_know):
        if word_has_common_prefix(word):
            continue
        word_vec = word_vectors.get(word)
        if not word_vec:
            continue

        node = etymology_graph.get((word, language))
        root_node = root_origin_node_of_node(node, etymology_graph)

        related_words = (
            all_english_leaf_descendant_words_of_node(root_node) -
            all_english_leaf_descendant_words_of_node(node) -
            all_english_leaf_ancestors_of_node(node) -
            set(words_i_dont_know)
        )

        # Exclude logic based on prefixes and subwords as needed

        for related_word in related_words:
            related_word_vec = word_vectors.get(related_word)
            if not related_word_vec:
                continue

            distance = vec_distance(word_vec, related_word_vec)
            print(f"{word} <-> {related_word} - {distance}")

if __name__ == "__main__":
    main(should_exclude_common_starts=False, common_subword_exclusion_length=4)
