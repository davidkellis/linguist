module Linguist
  class ParseForest
    class Node
      attr_accessor :production, :start_index, :end_index, :alternatives

      def initialize(production, start_index, end_index)
        @production = production
        @start_index = start_index
        @end_index = end_index
        @alternatives = []
        @children = nil
        @value = nil
      end
    end

    TerminalNode = Struct.new(:value, :start_index, :end_index)

    def initialize(nodes, root_nodes)
      @root_nodes = root_nodes
      @nodes = nodes
      @nodes_by_start_index = @nodes.group_by {|node| node.start_index }
    end

    def generate_subtrees_from_nodes
      @nodes.each do |node|
        node.alternatives = generate_alternatives(node)
      end
    end

    def generate_alternatives(node)
      parent_pattern = node.production.pattern

      patterns = [parent_pattern]
      (0...parent_pattern.length).each do |term_index|         # for each term in the parent node's pattern:
        patterns = patterns.map do |pattern|
          start_index = term_index > 0 ? pattern[term_index - 1].end_index : node.start_index

          # if the term in the pattern is a non-terminal, then we need to figure out which other nodes
          # the non-terminal can refer to, and then for each alternative node construct an alternate pattern 
          # in which the term at position 'term_index' is replaced by the alternative node.
          pattern_alternatives = if pattern[term_index].is_a?(Symbol)
            child_nodes_for_curent_term = find_child_nodes_by_term_position(node, term_index, start_index)
            child_nodes_for_curent_term.map do |child_node|
              new_pattern = pattern.clone
              new_pattern[term_index] = child_node
              new_pattern
            end
          else
            pattern[term_index] = TerminalNode.new(pattern[term_index], start_index, start_index + 1)
            [pattern]
          end
        end.flatten(1)
        patterns
      end
      # reject any patterns that don't end at the same character offset as the parent node's end_index
      patterns.reject{|pattern| pattern.last.end_index != node.end_index }
    end

    # This method finds the nodes that could fill the place of a particular term in the parent_node's production pattern.
    # We only consider nodes that start at the given start_index, and have an end index no greater than the parent_node's end_index.
    def find_child_nodes_by_term_position(parent_node, term_index, start_index)
      pattern_term = parent_node.production.pattern[term_index]
      end_index = parent_node.end_index
      (@nodes_by_start_index[start_index] || []).select do |node|
        node.production.non_terminal == pattern_term && 
        node.end_index <= end_index &&
        node != parent_node
      end
    end

    def tree_count
    end
  end
end