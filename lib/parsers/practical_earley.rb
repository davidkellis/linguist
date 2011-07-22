require 'parsers/earley'    # only for the definition of Item

module Linguist
  # PracticalEarleyParser implements the Earley algorithm as described by Aycock and Horspool
  # in "Practical Earley Parsing" (http://webhome.cs.uvic.ca/~nigelh/Publications/PracticalEarleyParsing.pdf)
  class PracticalEarleyParser
    attr_reader :grammar
    attr_reader :list
  
    def initialize(bnf_grammar)
      @grammar = bnf_grammar
    
      reset
    end
  
    def reset
      @input_length = 0
      @list = []
    end
  
    def match?(input)
      reset
      token_stream = input.chars
      @input_length = token_stream.count
      recognize(token_stream)
    end
  
    def parse(input)
      match? ? parse_trees : []
    end
  
    # @param alternatives is an array of pattern sequences, where each pattern sequence is 
    #                     an array of terminals and non-terminals.
    # @return A UniqueArray containing Items, each of the form [non_terminal -> •alternative, position],
    #         for every alternative sequence in +alternatives+
    def construct_initial_item_set(non_terminal, alternatives, position)
      UniqueArray.new(alternatives.map {|pattern| Item.new(non_terminal, [], pattern, position) })
    end
  
    def build_initial_itemset
      list[0] = construct_initial_item_set(grammar.start, grammar.alternatives(grammar.start), 0)
    end
  
    # This is the driver method that invokes the scanner, predictor, and completer for every item
    # in every item list
    def recognize(token_stream)
      build_initial_itemset

      token_stream.each_with_index do |token, position|
        # if the previous invocation of this block did not populate list[position], then break out, because the parse has failed
        break if list[position].nil?
      
        # examine each item in list[position] only once...
        i = 0
        while i < list[position].size
          item = list[position][i]
        
          scan(token, item, position + 1)
          predict(item, position)
          complete(item, position)
        
          i += 1
        end
      end

      # run the predictor and completer on the last set in list, because it hasn't been predicted or completed yet.
      i = 0
      count = token_stream.count
      if list[count]
        while i < list[count].size
          item = list[count][i]
      
          predict(item, count)
          complete(item, count)
      
          i += 1
        end
      end
    
      # list.with_index{|arr,i| puts i; pp arr }
    
      # If the item set that resulted from processing the last token in the input contains an item 
      # S -> ...•@1, that is, an item spanning the entire input and reducing to the start symbol,
      # we have found a valid parse!
      (list[token_stream.count] || []).any? do |item|
        item.non_terminal == grammar.start &&
        item.right_pattern.empty? &&
        item.position == 0
      end
    end
  
    # this runs the scanner
    # This implements the following rule from Practical Earley Parsing:
    # SCANNER. If [A → ...•a..., j] is in S[i] and a=x[i+1], add [A → ...a•..., j] to S[i+1].
    def scan(token, item, destination_position)
      # if item is of the form [A -> ...•token..., j], then we add [A -> ...token•..., j] to list[destination_position]
      if item.right_pattern.first == token ||       # we just saw token in the token stream
         item.right_pattern.first == Pattern::DOT   # this matches the ANY/DOT token in the token stream
        # the part before the • was already recognized and now token is recognized;
        # consequently, the Scanner changes •σ into σ•
        new_item = Item.new(item.non_terminal,
                            item.left_pattern + [token],
                            item.right_pattern[1...item.right_pattern.size],
                            item.position)

        list[destination_position] ||= UniqueArray.new
        list[destination_position] << new_item
      end
    end
  
    # this runs the predictor
    # This implements the following rule from Practical Earley Parsing:
    # PREDICTOR. If [A → ...•B..., j] is in S[i], add [B → •α, i] to S[i] for all productions/rules B→α.
    def predict(item, position)
      # NOTE: A non-terminal is predicted by an item if the token to the right of the DOT is a non-terminal.
      # if item is of the form [A -> ...•B..., position] (where B is a non-terminal)...
      predicted_token = item.right_pattern.first
      if predicted_token.is_a?(Symbol)
        # ... then we add [B -> •α..., position] to list[position] for every production alternative B -> α
        list[position] += construct_initial_item_set(predicted_token, 
                                                     grammar.alternatives(predicted_token), 
                                                     position)
      end
    end

    # this runs the completer
    # This implements the following rule from Practical Earley Parsing:
    # COMPLETER. If [A → ...•, j] is in S[i], add [B → ...A•..., k] to S[i] for all items [B → ...•A..., k] in S[j].
    def complete(item, position)
      # If [A → ...•, j] is in S[i] ...
      if item.right_pattern.empty?
        # ... add [B → ...A•..., k] to S[i] for all items [B → ...•A..., k] in S[j].
        list[item.position].each do |reducing_item|
          scan(item.non_terminal, reducing_item, position)
        end
      end
    end
    
    # examine every item in every item-set within list, and filter out all non-complete items.
    # note: a complete item is an item of the form [A → ...•, j] (i.e. the dot is at the end of the pattern)
    def completed_list
      list.map{|item_set| item_set.select{|item| item.right_pattern.empty? } }
    end
    
    # returns an array of parse trees that can be built given a grammar and input
    def parse_trees
      # pp "completed items:"
      # pp completed_list
      trees = build_parse_trees(completed_list)
      trees.map(&:to_sexp)
    end
    
    # build_parse_trees takes a list of completed items that occur at each position of the input,
    # and returns a list of parse trees - a parse forest
    def build_parse_trees(completed_items)
      # build the root nodes of all the initially obvious parse trees
      roots = parse_tree_root_nodes(completed_items)
      # puts "roots = #{roots.inspect}"

      # construct the initial set of trees, each containing only the root node of the tree
      trees = Set.new(construct_trees_from_roots(roots, completed_items))
      # puts "trees = #{trees.first.unused_completed.inspect}"

      completion_queue = roots
      until completion_queue.empty?
        node = completion_queue.shift
        # puts "*" * 80
        subtree_roots, trees = build_subtrees_with_root(node, trees)
        # puts "subtree roots:"
        # puts subtree_roots.join("\n")
        # trees += subtree_roots.map(&:tree)
        new_children = subtree_roots.map(&:children).flatten
        completion_queue.concat(new_children)
      end

      trees
    end

    # Search for items of the form [S → ...•, 0] in the item list after the last input token (i.e. at position @input_length).
    # This selects the items that represent the root node of a parse tree (in each possible tree, the grammar's
    #   start symbol derives the entire input string), and constructs Node objects out of them
    # Returns Node objects that are complete except that they are missing a tree attribute
    def parse_tree_root_nodes(completed_items)
      root_items = completed_items[@input_length].select{|item| item.non_terminal == grammar.start && item.position == 0 }
      root_items.map {|item| Node.new(item.non_terminal, nil, item, 0, @input_length - 1) }
    end

    def construct_trees_from_roots(root_nodes, completed_items)
      root_nodes.map do |root_node|
        unused_completed = completed_items.clone
        unused_completed[root_node.end_index + 1] -= [root_node.item]
        tree = Tree.new(root_node, unused_completed)
        root_node.tree = tree     # complete the root node by setting its tree attribute
        tree
      end
    end

    # This takes a given parent_node and returns all the sub-trees (containing 1 level of children) that
    # are derived from it. Every sub-tree is rooted at the parent_node (or a clone of it). The sub-trees that
    # are rooted at a clone of parent_node are also part of a clone of the tree containing parent_node.
    # In other words, every sub-tree that is returned is a part of a different tree entirely.
    # parent_node is a complete node (it has all its attributes set)
    def build_subtrees_with_root(parent_node, trees)
      # puts "build_subtrees_with_root(#{parent_node.inspect})"
      subtree_roots = [parent_node]

      if parent_node.non_terminal?
        pattern = parent_node.item.left_pattern
        # puts "parent node pattern: #{pattern.inspect}"
        parent_node.children = pattern.map {|term| Node.new(term, parent_node, nil, nil, nil, parent_node.tree) }

        i = 0
        while i < subtree_roots.length
          subtree_root = subtree_roots[i]
          # puts "subtree_roots[#{i}] = #{subtree_root.inspect}"

          end_index = subtree_root.end_index
          subtree_root.children.reverse.each do |child_node|
            complete_child_node(child_node, subtree_root, end_index, subtree_roots)

            end_index = child_node.start_index - 1
          end

          # if the subtree's leftmost child node doesn't start at the same index as the parent's start index
          # then the parse tree that the subtree is a part of is an invalid parse tree
          if subtree_root.children.first.start_index != parent_node.start_index
            # remove the parse tree from the set of valid parse trees
            trees -= [subtree_root.tree]

            # mark the parse tree as invalid because it is invalid
            subtree_root.tree.invalid!
          else
            # subtree is valid, so add it to the trees
            trees += [subtree_root.tree]
          end

          i += 1
        end
      end

      [subtree_roots.select{|root_node| root_node.tree.valid? }, trees]
    end

    def complete_child_node(child_node, subtree_root, end_index, subtree_roots)
      # puts "complete_child_node(#{child_node}, #{subtree_root}, #{end_index}, #{subtree_roots})"
      unless child_node.complete?
        if child_node.non_terminal?
          # 1. grab the item (or items) that should be associated with this child node
          # select the items in list[end_index + 1] that have a non-terminal equal to the child node's non-terminal
          child_node_completed_items = subtree_root.tree.unused_completed[end_index + 1].select do |item|
            item.non_terminal == child_node.value
          end

          # puts "child_node_completed_items = #{child_node_completed_items.inspect}"

          # Note: if child_node_completed_items contains more than 1 item, then we are dealing with a sentence that
          # has more than one parse tree, and this is where a tree diverges into two or more trees.
          # So, we need to clone the part of the tree that is the same accross both trees, and then construct
          # the remainder of each tree independently so that we capture all possible parse trees.

          # iterate over all the completed items except the first (0th) one, creating a duplicate of the partial tree
          # for every item. This ensures that we build a parse tree for every possible interpretation of the input string.
          # This is how we wind up with a parse forest, instead of a single parse tree.
          if child_node_completed_items.length > 1
            child_node_completed_items[1..-1].each do |item|
              new_tree = child_node.tree.clone
              new_node = new_tree.node_at(child_node.path)

              finish_non_terminal_node(new_node, item, end_index)

              # puts "adding to subtree_roots: #{new_node.parent.inspect}"
              subtree_roots << new_node.parent
            end
          end

          finish_non_terminal_node(child_node, child_node_completed_items[0], end_index) if child_node_completed_items[0]
        else
          finish_terminal_node(child_node, end_index)
        end
      end
    end

    def finish_non_terminal_node(node, item, end_index)
      node.tree.unused_completed[end_index + 1] -= [item]
      node.item = item
      node.start_index = item.position
      node.end_index = end_index
    end

    def finish_terminal_node(node, end_index)
      node.start_index = end_index
      node.end_index = end_index
    end
  end

  class PracticalEarleyEpsilonParser < PracticalEarleyParser
    # this runs the predictor
    # This implements the following rule from Practical Earley Parsing:
    # PREDICTOR. If [A → ...•B..., j] is in S[i], add [B → •α, i] to S[i] for all productions/rules B→α.
    #            If B is nullable, also add [A → ...B•..., j] to S[i].
    def predict(item, position)
      # NOTE: A non-terminal is predicted by an item if the token to the right of the DOT is a non-terminal.
      # if item is of the form [A -> ...•B..., position] (where B is a non-terminal)...
      predicted_token = item.right_pattern.first
      if predicted_token.is_a?(Symbol)
        # ... then we add [B -> •α..., position] to list[position] for every production alternative B -> α
        list[position] += construct_initial_item_set(predicted_token, 
                                                     grammar.alternatives(predicted_token), 
                                                     position)
        # If B is nullable, also add [A → ...B•..., j] to list[position]
        if grammar.nullable_non_terminals.include?(predicted_token)
          list[position] << Item.new(item.non_terminal,
                                     item.left_pattern + [item.right_pattern.first],
                                     item.right_pattern[1...item.right_pattern.size],
                                     item.position)
        end
      end
    end
  end
  
  class PracticalEarleyParser::Tree
    attr_accessor :root
    attr_accessor :unused_completed

    def initialize(root, unused_completed = nil)
      @root = root
      @unused_completed = unused_completed
      @valid = true
    end

    def valid?
      @valid
    end

    def invalid!
      @valid = false
    end

    def to_s
      root.to_s
    end

    def clone
      new_tree = self.class.new(nil, unused_completed.clone)
      new_root = root.deep_clone {|node| node.tree = new_tree }
      new_tree.root = new_root

      new_tree
    end

    # node_path is an array of index positions, that together, point to a specific node in the tree
    # 
    # Example:
    # in the tree:
    #   (a
    #     (b
    #       c)
    #     (d
    #       e
    #       f)
    #     (g
    #       (h
    #         i
    #         j)
    #       k
    #       l
    #       m))
    # [0] points to node "a"
    # [0, 2] points to node "g"
    # [0, 1, 0] points to node "e"
    # [0, 2, 3] points to node "m"
    # [0, 2, 0, 1] points to node "j"
    def node_at(node_path)
      unless node_path.empty?
        children = [root]
        node = nil

        node_path.each do |child_index|
          raise "The node path #{node_path.join(',')} does not point to a node" if child_index >= children.length
          node = children[child_index]
          children = node.children
        end

        node
      end
    end

    def to_sexp
      root.to_sexp
    end
  end

  class PracticalEarleyParser::Node < Linguist::Node
    attr_accessor :item, :start_index, :end_index
    attr_accessor :parent, :tree

    def initialize(node_value, parent = nil, item = nil, start_index = nil, end_index = nil, tree = nil)
      super(node_value)
      @parent = parent
      @item = item
      @start_index = start_index
      @end_index = end_index
      @tree = tree
    end

    def clone
      self.class.new(value, parent, item, start_index, end_index, tree)
    end

    def deep_clone(&blk)
      new_self = clone
      new_children = children.map do |child|
        new_child = child.deep_clone(&blk)
        new_child.parent = new_self
        new_child
      end
      new_self.children = new_children
      yield(new_self) if block_given?
      new_self
    end

    def clone_with_parent(new_parent = nil)
      self.class.new(value, new_parent, item, start_index, end_index, new_parent.tree)
    end

    def complete?
      item && start_index && end_index && tree
    end

    def path
      if parent
        child_index = parent.children.find_index(self)
        parent.path + [child_index]
      else
        [0]
      end
    end

    def to_sexp
      if children.empty?
        value
      else
        [value] + children.map(&:to_sexp)
      end
    end
  end
end