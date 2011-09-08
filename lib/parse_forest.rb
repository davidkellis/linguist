module Linguist
  class ParseForest
    class Node
      attr_accessor :production, :start_index, :end_index, :alternatives, :branch_index, :value, :children, :parent

      def initialize(production, start_index, end_index)
        @production = production
        @start_index = start_index
        @end_index = end_index
        @alternatives = []
        
        @value = production.non_terminal
        @children = nil
        @branch_index = nil
        @parent = nil
      end

      def terminal?; false; end
      def non_terminal?; true; end

      def is_rightmost_child?
        if parent
          parent.children.last == self       # this node is the rightmost child of the parent
        end
      end

      def OR_node?
        @alternatives.length > 1
      end

      def branch_count
        @alternatives.length
      end

      def select_branch!(branch_index)
        self.branch_index = branch_index
        @children = @alternatives[branch_index]
        @children.each {|child| child.parent = self }
        @children
      end

      # returns the index of the newly selected branch
      # if there is no "next" branch, returns nil
      def select_next_branch!
        next_index = (branch_index || -1) + 1
        if next_index < branch_count
          select_branch!(next_index)
          next_index
        else
          self.branch_index = nil
          nil
        end
      end

      def to_s
        "Node(#{object_id} #{production} #{start_index} #{end_index})"
      end

      def to_sexp
        if children.empty?
          value
        else
          [value] + children.map(&:to_sexp)
        end
      end
    end

    TerminalNode = Struct.new(:value, :start_index, :end_index, :parent)
    class TerminalNode
      def OR_node?; false; end
      def terminal?; true; end
      def non_terminal?; false; end
      def to_sexp; value; end
    end


    include Enumerable
    include Disambiguation::TreeValidations

    attr_accessor :associativity_rules, :priority_tree

    def initialize(nodes, root_node, associativity_rules = nil, priority_tree = nil)
      @associativity_rules = associativity_rules
      @priority_tree = priority_tree
      @root_node = root_node
      @nodes = nodes
      @nodes_by_start_index = @nodes.group_by {|node| node.start_index }
    end

    # this generates all the alternative patterns for each node
    # this is the equivalent of generating a parse forest grammar using the given nodes
    def generate_node_alternatives!
      @nodes.each do |node|
        node.alternatives = generate_alternatives(node)
        node.select_next_branch! if node.branch_count == 1
      end
    end

    def generate_alternatives(node)
      parent_pattern = node.production.pattern

      patterns = [parent_pattern]
      (0...parent_pattern.length).each do |term_index|         # for each term in the parent node's pattern:
        patterns = patterns.map do |pattern|                   # construct all possible derivations from that pattern
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
            new_pattern = pattern.clone
            new_pattern[term_index] = TerminalNode.new(new_pattern[term_index], start_index, start_index + 1)
            [new_pattern]
          end
        end.flatten(1)
      end

      # reject any derivations that don't end at the same character offset as the parent node's end_index
      derivations = patterns.reject{|pattern| pattern.last.end_index != node.end_index }
      derivations
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

    # Returns an Enumerator that represents a sequence of parse trees
    # Each element of the enumerator is a pair of the form: [root_node, {or_node1: index1, ..., or_nodeN: indexN}]
    #   The root_node is the root node of the tree.
    #   The hash of OR-nodes indicates the branch-index of each active/used OR-node in the tree.
    def to_enum
      Enumerator.new() do |yielder|
        nodes = [@root_node]
        or_nodes = []
        tree_modified = false

        begin
          until or_nodes.empty?
            or_node = or_nodes.pop
            if or_node.select_next_branch!      # switching branches was successful, so we can stop backtracking
              tree_modified = true
              or_nodes << or_node
              nodes.concat(or_node.children.reverse)
              break
            end
          end

          # when the following until loop finishes, we will have constructed a parse tree with root node @root_node
          until nodes.empty?
            tree_modified = true

            node = nodes.pop

            if branch_is_invalid?(node)
              # 1. prune this tree from the parse forest
              # all we have to do is backtrack and try another branch

              # 2. backtrack
              tree_modified = false
              break
            end

            if node.OR_node?
              or_nodes << node
              node.select_next_branch!
            end

            unless node.terminal?
              nodes.concat(node.children.reverse)
            end
          end

          # yield the constructed parse tree to the block
          yielder.yield(@root_node, Hash[ or_nodes.map{|or_node| [or_node, or_node.branch_index] } ]) if tree_modified
          tree_modified = false
        end until or_nodes.empty?
      end
    end

    def branch_is_invalid?(child_node)
      if child_node.non_terminal? && child_node.is_rightmost_child?
        !subtree_obeys_disambiguation_rules?(child_node.parent)
      end
    end

    # this method enumerates the trees in the parse forest
    def each(&blk)
      to_enum.each(&blk)
    end
  end
end