module Linguist
  module Disambiguation
    class TreeValidator
      attr_accessor :associativity_rules, 
                    :priority_tree, 
                    :reject_rules, 
                    :follow_restrictions, 
                    :preferred_productions,
                    :avoided_productions

      def initialize()
        @associativity_rules = {}
        @priority_tree = PriorityTree.new
        @reject_rules = {}
        @follow_restrictions = {}
        @preferred_productions = {}
        @avoided_productions = {}
      end

      # Follow Restrictions
      # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.restrictions
      # Given non-terminal N and regular expression R, we tell the parser to reject
      # any derivation N => S  (where S is a substring of the input being parsed) such that S is immediately followed
      # by X, a string that is derivable from the regular expression R.
      # In other words, if N derives string S, and S is followed by substring X, and X matches the regular expression R, 
      # then we prune the tree in which the derivation N => S exists.
      def select_nodes_obeying_follow_restrictions(token_stream, non_terminal_nodes)
        non_terminal_nodes.select { |node| node_obeys_follow_restrictions?(token_stream, node) }
      end

      def node_obeys_follow_restrictions?(token_stream, parent_node)
        if parent_node.non_terminal?
          follow_string_scanner = StringScanner.new(token_stream[parent_node.end_index..-1].join())
          derivation_string = token_stream[parent_node.start_index...parent_node.end_index].join()

          # since follow restriction rules can be of the form:
          # NON_TERMINAL1, ID, NUM -/- /[a-z]/
          # OR
          # 'terminal_string', 'break', 'return', 'if' -/- /[a-z]/
          # we need to look up rejection patterns associated with either 
          # a non-terminal or a terminal string literal associated with the current parent_node
          rejection_patterns = (follow_restrictions[parent_node.production.non_terminal] || []) +
                               (follow_restrictions[derivation_string] || [])

          # if any of the rejection patterns match at the beginning of the follow string, 
          # then the derivation N => S is invalid, and the tree in which it exists should be discarded.
          rejection_patterns.none? { |rejection_pattern| follow_string_scanner.check(rejection_pattern) }
        else
          # we're dealing with a terminal node, I'm pretty sure this code should never be reached
          # because I only only validate nodes that have children
          raise "I don't think this code will ever be reached."
          
          follow_string_scanner = StringScanner.new(token_stream[parent_node.end_index..-1].join())
          derivation_string = token_stream[parent_node.start_index...parent_node.end_index].join()

          rejection_patterns = (follow_restrictions[derivation_string] || [])

          # if any of the rejection patterns match at the beginning of the follow string, 
          # then the derivation N => S is invalid, and the tree in which it exists should be discarded.
          rejection_patterns.none? { |rejection_pattern| follow_string_scanner.check(rejection_pattern) }
        end
      end

      # this method returns the subset of the given nodes that have a production that is either preferred
      # or non-avoided.
      def select_preferred_and_non_avoided_nodes(nodes)
        node_groups = group_nodes_by_non_terminal_then_by_indices(nodes)

        node_groups.map do |non_terminal, node_group|
          prefer_productions = preferred_productions[non_terminal]
          avoid_productions = avoided_productions[non_terminal]

          node_group.map do |index_pair, node_array|
            # If an array of nodes has more than one node in it, we observe that the nodes are competing.
            # We filter out any nodes that are supposed to be avoided (if applicable).
            # Of the remaining nodes, we filter out any that aren't preferred (if applicable).
            # If an array of nodes only has one node in it, then we do not perform filtering on it.
            if node_array.length > 1
              # First, we apply the avoid-filtering rules
              non_avoided_nodes = node_array
              if avoid_productions
                # filter out any nodes with avoided productions
                non_avoided_nodes = node_array.reject {|node| avoid_productions.include?(node.production) }

                # if filtering out the nodes with avoided productions removes all nodes,
                # then put all the nodes back, and proceed as if none of the nodes are flagged to be avoided
                non_avoided_nodes = node_array if non_avoided_nodes.empty?
              end

              # Second, we apply the prefer-filtering rules
              preferred_nodes = non_avoided_nodes
              if prefer_productions
                # of the remaining nodes that weren't filtered out by the avoid-filtering,
                # select only the the nodes with preferred productions
                preferred_nodes = non_avoided_nodes.select {|node| prefer_productions.include?(node.production) }

                # if filtering out the non-preferred nodes removes all nodes,
                # then put all the non_avoided_nodes back, and proceed as if all of the non-avoided nodes are flagged as preferred
                preferred_nodes = non_avoided_nodes if preferred_nodes.empty?
              end

              preferred_nodes
            else
              node_array
            end
          end
        end.flatten
      end

      # Given a set of nodes, this method groups them by non-terminal and [start_index, end_index] pair
      # and returns a structure of the form:
      # {
      #   :NONTERMINAL1 => {[start_index1, end_index1] => [node_with_start_index1_and_end_index1,
      #                                                    another_node_with_start_index1_and_end_index1],
      #                     [start_index2, end_index2] => [node_with_start_index2_and_end_index2]},
      #   :NONTERMINAL2 => {[start_index3, end_index3] => [node_with_start_index3_and_end_index3]}
      # }
      # In other words, the method gruops the nodes by their non-terminal first, then within each group,
      # groups the nodes by their [start_index, end_index] pair.
      def group_nodes_by_non_terminal_then_by_indices(nodes)
        node_groups_per_non_terminal = nodes.group_by {|node| node.production.non_terminal }
        node_groups_per_non_terminal.merge(node_groups_per_non_terminal) do |non_terminal, node_array, newval|
          node_array.group_by {|node| [node.start_index, node.end_index] }
        end
      end

      # this method examines each alternative branch of every node, and prunes those alternative branches
      # that would cause the node to violate the priority rules
      # Returns the same collection of nodes that were given, but some of the alternative branches of each node
      # may have been removed.
      def select_branches_conforming_to_priority_rules(non_terminal_nodes)
        non_terminal_nodes.each do |node|
          node.alternatives.select! do |children|
            priority_tree.is_parent_children_relationship_valid?(node, children)
          end
        end
      end

      def select_branches_conforming_to_associativity_rules(non_terminal_nodes)
        non_terminal_nodes.each do |node|
          node.alternatives.select! do |children|
            if associativity_rules.include?(node.production)
              associativity_rule = associativity_rules[node.production]
              associativity_rule.is_parent_children_relationship_valid?(node, children)
            else
              true    # there is no associativity rule that applies to the production from which tree_root_node was derived
            end
          end
        end
      end

      # Rejects
      # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.disambrejects
      # Given non-terminal N and regular expression R, we tell the parser to reject
      # any derivation N => S where S is a string that is derivable from the regular expression R.
      # In other words, if S matches the regular expression R, then we prune the tree in which the derivation
      # N => S exists.
      def select_nodes_conforming_to_reject_rules(token_stream, non_terminal_nodes)
        non_terminal_nodes.select { |node| node_obeys_reject_rules?(token_stream, node) }
      end

      def node_obeys_reject_rules?(token_stream, parent_node)
        if parent_node.non_terminal?
          derivation_string = token_stream[parent_node.start_index...parent_node.end_index].join()
          (reject_rules[parent_node.production.non_terminal] || []).none? do |rejection_pattern|
            if rejection_pattern.is_a? Regexp
              derivation_string =~ rejection_pattern
            else
              derivation_string == rejection_pattern
            end
          end
        else
          true
        end
      end

    end     # end TreeValidator

    # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.priorities
    # If A > B, then all trees are removed that have a B node as a direct child of an A node.
    # That is, the tree where B is a direct child of A violates the priority rule.
    class PriorityTree
      def initialize()
        @priority_relations = Hash.new
      end
    
      # prioritize greater_production over lesser_production (so that greater_production takes priority over lesser_production)
      # That is, greater_production > lesser_production
      def prioritize(greater_production, lesser_production)
        greater_production_node = (@priority_relations[greater_production] ||= PriorityNode.new(greater_production))
        lesser_production_node = (@priority_relations[lesser_production] ||= PriorityNode.new(lesser_production))
        greater_production_node.children << lesser_production_node
        lesser_production_node.parents << greater_production_node
      end
    
      def is_parent_children_relationship_valid?(parent_node, child_nodes)
        if parent_node.non_terminal?
          if @priority_relations.include?(parent_node.production)
            lesser_priority_nodes = @priority_relations[parent_node.production].descendants
            lesser_priority_productions = lesser_priority_nodes.map(&:value)
            # do any of the child nodes cause the Priority rule to be violated?
            is_rule_violated = child_nodes.any? do |child_node|
              lesser_priority_productions.include?(child_node.production)
            end
            !is_rule_violated
          else
            true    # there are no priority rules that reference parent_node.production
          end
        else
          true      # the parent node represents a terminal symbol, so it is a valid parse tree (i.e. it is a leaf node)
        end
      end
    end
    
    class PriorityNode
      attr_accessor :value, :parents, :children
      
      def initialize(value)
        @value = value
        @parents = Set.new
        @children = Set.new
      end
      
      # Returns the Set of all PriorityNode objects that are descendants of self
      def descendants
        visited_children = Set.new
        unvisited_children = @children.to_a
        until unvisited_children.empty?
          child = unvisited_children.pop
          unless visited_children.include?(child)
            visited_children << child
            unvisited_children = unvisited_children.concat(child.children.to_a)
          end
        end
        visited_children
      end
    end
    
    # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.disambassociativity
    # The :left associativity attribute on a production P filters [out] all occurences of P as a direct child of P
    #   in the right-most argument. This implies that :left is only effective on productions that are
    #   recursive on the right (as in A B C -> C).
    # The :right associativity attribute on a production P filters [out] all occurences of P as a direct child of P
    #   in the left-most argument. This implies that :right is only effective on productions that are 
    #   recursive on the left ( as in C A B -> C).
    # The :non_assoc associativity attribute on a production P filters [out] all occurrences of P as a direct child
    #   of P in any argument. This implies that :non_assoc is only effective if a production is indeed
    #   recursive (as in A C B -> C).
    class IndividualAssociativityRule
      def initialize(direction, production)
        @direction = direction
        @production = production
      end
    
      def is_parent_children_relationship_valid?(parent_node, child_nodes)
        is_parse_tree_invalid = case @direction
          when :left
            # filter out all occurences of P as a direct child of P in the right-most argument
            parent_node.production == @production && child_nodes.last.production == @production
          when :right
            # filter out all occurences of P as a direct child of P in the left-most argument
            parent_node.production == @production && child_nodes.first.production == @production
          when :non_assoc
            # filter out all occurrences of P as a direct child of P in any argument
            parent_node.production == @production && child_nodes.any? {|child_node| child_node.production == @production }
        end
        !is_parse_tree_invalid
      end
    end
    
    class EqualPriorityGroupAssociativityRule
      def initialize(direction, production_set)
        @direction = direction
        @production_set = production_set
      end
      
      def is_parent_children_relationship_valid?(parent_node, child_nodes)
        parent_production = parent_node.production
        is_parse_tree_invalid = @production_set.include?(parent_production) && case @direction
          when :left
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in the right-most argument
            @production_set.include?(child_nodes.last.production)
          when :right
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in the left-most argument
            @production_set.include?(child_nodes.first.production)
          when :non_assoc
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in any argument
            child_nodes.any? {|child_node| @production_set.include?(child_node.production) }
        end
        !is_parse_tree_invalid
      end
    end
  end
end