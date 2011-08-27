module Linguist
  module Disambiguation
    module TreeValidations
      def tree_obeys_disambiguation_rules?(tree_root_node)
        tree_root_node.descendants.all? { |tree_node| subtree_obeys_disambiguation_rules?(tree_node) }
      end

      def subtree_obeys_disambiguation_rules?(tree_root_node)
        subtree_obeys_priority_rules?(tree_root_node) && subtree_obeys_associativity_rules?(tree_root_node)
      end
      
      def subtree_obeys_priority_rules?(tree_root_node)
        grammar.priority_tree.is_parse_tree_valid?(tree_root_node)
      end
      
      def subtree_obeys_associativity_rules?(tree_root_node)
        if tree_root_node.non_terminal?
          if grammar.associativity_rules.include?(tree_root_node.production)
            associativity_rule = @grammar.associativity_rules[tree_root_node.production]
            associativity_rule.is_parse_tree_valid?(tree_root_node)
          else
            true    # there is no associativity rule that applies to the production from which tree_root_node was derived
          end
        else
          true      # the tree_root_node represents a terminal symbol, so it is a valid parse tree (i.e. it is a leaf node)
        end
      end
    end

    # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.priorities
    # If A > B, then all trees are removed that have a B node as a direct child of an A node.
    # That is, the tree where B is a direct child of A violates the priority rule.
    class PriorityTree
      def initialize()
        @priority_relations = Hash.new
      end
    
      # prefer greater_production over lesser_production
      # That is, greater_production > lesser_production
      def prefer(greater_production, lesser_production)
        greater_production_node = (@priority_relations[greater_production] ||= PriorityNode.new(greater_production))
        lesser_production_node = (@priority_relations[lesser_production] ||= PriorityNode.new(lesser_production))
        greater_production_node.children << lesser_production_node
        lesser_production_node.parents << greater_production_node
      end
    
      def is_parse_tree_valid?(parent_node)
        if parent_node.non_terminal?
          if @priority_relations.include?(parent_node.production)
            lesser_priority_nodes = @priority_relations[parent_node.production].descendants
            lesser_priority_productions = lesser_priority_nodes.map(&:value)
            # do any of the child nodes cause the Priority rule to be violated?
            is_rule_violated = parent_node.children.any? do |child_node|
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
    
      def is_parse_tree_valid?(parent_node)
        is_parse_tree_invalid = case @direction
          when :left
            # filter out all occurences of P as a direct child of P in the right-most argument
            parent_node.production == @production && parent_node.children.last.production == @production
          when :right
            # filter out all occurences of P as a direct child of P in the left-most argument
            parent_node.production == @production && parent_node.children.first.production == @production
          when :non_assoc
            # filter out all occurrences of P as a direct child of P in any argument
            parent_node.production == @production && parent_node.children.any? {|child_node| child_node.production == @production }
        end
        !is_parse_tree_invalid
      end
    end
    
    class EqualPriorityGroupAssociativityRule
      def initialize(direction, production_set)
        @direction = direction
        @production_set = production_set
      end
      
      def is_parse_tree_valid?(parent_node)
        parent_production = parent_node.production
        is_parse_tree_invalid = @production_set.include?(parent_production) && case @direction
          when :left
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in the right-most argument
            @production_set.include?(parent_node.children.last.production)
          when :right
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in the left-most argument
            @production_set.include?(parent_node.children.first.production)
          when :non_assoc
            # filter out all occurences of P1 ∈ @production_set that occur as a direct child of P1 ∈ @production_set in any argument
            parent_node.children.any? {|child_node| @production_set.include?(child_node.production) }
        end
        !is_parse_tree_invalid
      end
    end
  end
end