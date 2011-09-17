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

      def reset!
        @children = nil
        @branch_index = nil
        @parent = nil
      end

      def reset_next_branch!
        @branch_index = nil
      end

      def terminal?; false; end
      def non_terminal?; true; end

      def has_more_branches?
        @branch_index < (branch_count - 1)
      end

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
        @children.each {|child| child.parent = self }     # point each child's parent pointer to the this node, self.
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

      def to_s(spaces = 0)
        (" " * spaces) + "Node(#{object_id} #{production} #{start_index} #{end_index} OR_node?=#{OR_node?} rightmost?=#{is_rightmost_child?} have_parent?=#{!parent.nil?} branch=#{@branch_index} #branches=#{branch_count})\n" +
        children.map{|child| child.to_s(spaces + 2) }.join("\n")
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
      def production; :no_production; end
      def OR_node?; false; end
      def terminal?; true; end
      def non_terminal?; false; end
      def to_sexp; value; end
      def reset_next_branch!; end
      def is_rightmost_child?
        if parent
          parent.children.last == self       # this node is the rightmost child of the parent
        end
      end
      def inspect
        to_s
      end
      def to_s(spaces = 0)
        " " * spaces + "TerminalNode(#{object_id} value='#{value}' #{start_index} #{end_index})"
      end
    end


    include Enumerable

    attr_accessor :tree_validator
    attr_reader :token_stream

    def initialize(token_stream, nodes, root_nodes, tree_validator = nil)
      @token_stream = token_stream
      @root_nodes = root_nodes
      @nodes = nodes
      @tree_validator = tree_validator

      @nodes_by_start_index = @nodes.group_by {|node| node.start_index }
    end

    # this generates all the alternative patterns for each node
    # this is the equivalent of generating a parse forest grammar using the given nodes
    # this is also the equivalent of building a DAG representing the parse forest
    def generate_node_alternatives!
      @nodes.each do |node|
        node.alternatives = generate_alternatives(node)
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
            character = new_pattern[term_index]
            if @token_stream[start_index] == character
              new_pattern[term_index] = TerminalNode.new(character, start_index, start_index + 1)
              [new_pattern]
            else    # the current alternative is invalid, so drop it by representing the current alternative as an empty alternative
              []    # an empty alternative will be dropped
            end
          end
        end.flatten(1)
      end

      # reject any derivations that don't end at the same character offset as the parent node's end_index
      derivations = patterns.reject do |pattern|
        if pattern.empty?   # if the pattern is epsilon (i.e. the pattern has no terms):
          # the epsilon (empty) pattern is an invalid alternative if the node doesn't represent the empty string.
          node.start_index != node.end_index      # this node doesn't represent the empty string
        else
          # the pattern is an invalid alternative if the right-most child node doesn't end at the same index as the parent node's end_index
          pattern.last.end_index != node.end_index
        end
      end

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

    def reset_all_nodes!
      @nodes.each(&:reset!)
    end

    # Returns an Enumerator that represents a sequence of parse trees
    # The enumerator traverses the DAG in a depth-first manner.
    # The disambiguation rules are applied as DAG-branches are chosen.
    # Each element of the enumerator is a pair of the form: [root_node, {or_node1: index1, ..., or_nodeN: indexN}]
    #   The root_node is the root node of the tree.
    #   The hash of OR-nodes indicates the branch-index of each active/used OR-node in the tree.
    def to_enum
      Enumerator.new() do |yielder|
        reset_all_nodes!
        @root_nodes.each do |root_node|
          # pp "root node = #{root_node.inspect}"
          next_node_index = 0

          # nodes is an array of [node, index] pairs s.t. the index is a strictly increasing integer, starting at 0
          # each new item pushed onto the nodes stack has an index that is one greater than the index of the previously added pair
          nodes = [[root_node, next_node_index]]

          # or_nodes is also an array of [node, index] pairs.
          # the index of each or_node pair is significant because when the need arises to backtrack to the last branch-point
          # we need to remove all the node-pairs in the nodes array that were added after the or_node was last added to the nodes
          # list. We accomplish this by popping all the pairs on the nodes array that have a node_index 
          # greater than or equal to the or_node's index.
          or_nodes = []

          begin
            tree_modified = false

            # this implements backtracking logic
            # every pop of an or_node is a search for the next branch point
            until or_nodes.empty?
              or_node, or_node_index = or_nodes.pop
              # puts "PROCESSING OR node: #{or_node.inspect}"

              # remove all the pairs that were added appended to the nodes array *after* the current branch was taken.
              # that is, pop all the pairs on the nodes array that have a node_index (i.e. the second element in the pair)
              # greater than or equal to the or_node_index
              while !nodes.empty? && nodes.last[1] >= or_node_index
                nodes.pop
              end

              # if the current or_node has more branches, add it to the nodes list so that the next branch will be built-out
              if or_node.has_more_branches?
                nodes << [or_node, next_node_index += 1]
                break
              end
            end

            # visit the nodes in the tree
            # a node is only visited if its parent changes
            # when the following until loop finishes, we will have constructed a parse tree with root node root_node
            until nodes.empty?
              tree_modified = true

              node_pair = nodes.pop
              node, node_index = node_pair

              # puts "processing #{node.inspect}"

              # we want to check the subtree for validity before adding this node's children to be processed
              if branch_is_invalid?(node)
                # puts 'invalid'
                # backtrack to the last branch point and select the next possible branch
                tree_modified = false
                break
              end

              if node.non_terminal?
                # select the next branch of the current node
                node.select_next_branch!
                or_nodes << node_pair if node.OR_node?      # make a note of the current branch if the node is an OR-node (a node with multiple branches)

                # we want to visit the node's children, so add them to the stack
                new_nodes = node.children
                new_nodes.each(&:reset_next_branch!)    # reset them so that when they're visited, the call to select_next_branch! won't select a non-existent branch
                new_pairs = new_nodes.reverse.map{|node| [node, next_node_index += 1] }
                nodes.concat(new_pairs)
              end
            end

            # yield the constructed parse tree and corresponding branch selections to the block
            if tree_modified
              or_node_branch_index_pairs = or_nodes.map do |node_stack_index_pair|
                or_node = node_stack_index_pair.first
                [or_node, or_node.branch_index]
              end
              selected_branches = Hash[ or_node_branch_index_pairs ]
              yielder.yield(root_node, selected_branches)
            end
          end until or_nodes.empty?
        end    # end of @root_nodes.each
      end
    end

    def branch_is_invalid?(child_node)
      if child_node.is_rightmost_child?
        # puts 'checking tree for validity:'
        # puts child_node.parent.to_sexp
        valid = tree_validator.nil? || tree_validator.subtree_obeys_disambiguation_rules?(token_stream, child_node.parent)
        # unless valid
        #   pp 'invalid'
        #   pp child_node.parent
        #   pp child_node
        # end
        !valid
      end
    end

    # this method enumerates the trees in the parse forest
    def each(&blk)
      to_enum.each(&blk)
    end

    def trees
      Enumerator.new() do |yielder|
        to_enum.map {|tree, or_nodes| yielder.yield(tree) }
      end
    end
  end
end