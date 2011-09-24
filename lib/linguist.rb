# encoding: UTF-8

require 'set'
require 'pp'
require 'strscan'
require 'pattern_builder'
require 'structures'
require 'disambiguation'
require 'parse_forest'
require 'parsers/earley_item'
require 'parsers/practical_earley'

module Linguist
  Production = Struct.new(:non_terminal, :pattern)

  # In a BNF Grammar, "productions" is a hash of the form:
  # { :NT -> [[:A, :B, 'c'], [:D, 'e'], ...] }
  # In other words, each key/value pair is a non-terminal/array-of-alternatives pair, where the
  # array-of-alternatives is an array of sequence arrays, with each sequence array being a flat array
  # containing only terminals (characters) and non-terminals (symbols).
  class BNFGrammar
    attr_accessor :start, :productions, :tree_validator, :semantic_actions

    def initialize
      @productions = {}
      @start = nil
      @tree_validator = Disambiguation::TreeValidator.new
      @semantic_actions = {}
    end

    def non_terminals
      productions.keys
    end

    def alternatives(non_terminal)
      productions[non_terminal] || []
    end

    def nullable_non_terminals
      unless @nullable_non_terminals
        non_terminals_directly_deriving_epsilon = non_terminals.select do |nt|
          productions[nt].any? {|sequence| sequence.empty? }
        end
        @nullable_non_terminals = Set.new(non_terminals_directly_deriving_epsilon)
        begin
          original_nullable_count = @nullable_non_terminals.size
          
          @nullable_non_terminals += non_terminals.select do |nt|
            productions[nt].any? {|sequence| sequence.all? {|token| @nullable_non_terminals.include?(token) } }
          end
        end until original_nullable_count == @nullable_non_terminals.size
      end
      @nullable_non_terminals
    end
  end

  # Grammar is a data structure that represents a context-free grammar (CFG).
  #
  # From wikipedia:
  #   Formally, a context-free grammar G is defined by the 4-tuple:
  #   G = (V, E, P, S)
  #   where
  #   V is a finite set of non-terminals.
  #   E is a finite set of terminals, disjoint from V.
  #   P is a finite set of productions.
  #   S is the start symbol representing the non-terminal from which the grammar derives sentences.
  class Grammar
    include PatternBuilder
    
    attr_accessor :start, :productions, :tree_validator, :semantic_actions, :production_pattern_labels
    
    def self.unique_non_terminal
      @id_count ||= 0
      @id_count += 1
      "__NT_#{@id_count}__".to_sym
    end
    
    def initialize(start_non_terminal = nil, &block)
      @start = start_non_terminal
      @productions = {}
      @tree_validator = Disambiguation::TreeValidator.new
      @semantic_actions = {}
      @production_pattern_labels = {}
      instance_eval(&block) if block_given?
    end
    
    def to_bnf
      bnf_grammar = BNFGrammar.new
      bnf_grammar.start = start
      tmp_productions = productions.reduce({}) do |m, kv|
        non_terminal, alternatives = kv
        m[non_terminal] = alternatives.map(&:to_bnf_pattern)
        m
      end
      bnf_grammar.productions.merge!(tmp_productions)
      bnf_grammar.tree_validator = tree_validator
      bnf_grammar.semantic_actions = semantic_actions
      bnf_grammar
    end
    
    def to_s
      productions.map{|k,v| "#{k} -> #{v}" }
    end

    # Associates the production with the given module
    # When a parse tree is constructed, the tree nodes that represent the given production will
    # be extended with the given semantic_actions_modules.
    # Returns the given production.
    def bind(production, semantic_actions_module)
      if production.is_a? Array
        production.each{|p| bind(p, semantic_actions_module) }
      else
        semantic_actions[production] ||= []
        semantic_actions[production] << semantic_actions_module
      end
      production
    end

    # Create a production
    def production(name, pattern)
      sym = name.to_sym
      
      # set the start non-terminal if it isn't already set
      self.start ||= sym

      # ensure that productions[sym] is an array
      productions[sym] ||= []

      case pattern
      # Range is a special case - it represents an array of productions
      # If differs from the logic in PatternBuilder#wrap in that we don't want to generate a new
      # non-terminal - we want the productions to derive directly from the given non-terminal, name,
      # instead of indirectly through a generated non-terminal, __NT_5__.
      when Range
        chars = pattern.to_a.map(&:to_s)
        if chars.length == 0
          raise "A range must have one or more characters in it."
        elsif chars.count == 1
          production(name, chars.first)
        else
          chars.map do |char|
            production(name, char)
          end
        end
      else
        # productions[sym] is a set of pattern sequences representing one of the following Pattern types:
        # Terminal
        # NonTerminal
        # Epsilon
        # Any (Dot; wildcard)
        # Sequence (represents a sequence of patterns)
        alternative = wrap(pattern)
        productions[sym] << alternative

        production = Production.new(sym, alternative.to_bnf_pattern)

        label_references_module = module_with_label_references_to_children(alternative.pattern_labels)
        bind(production, label_references_module)
        # production_pattern_labels[production] = alternative.pattern_labels
        production
      end
    end

    def module_with_label_references_to_children(production_pattern_labels)
      label_module = Module.new
      production_pattern_labels.each.with_index do |label, term_index|
        label_module.send(:define_method, label) { children[term_index] } if label
      end
      label_module
    end


    ########################################################################################################
    # Disambiguation Methods
    ########################################################################################################

    # Priorities
    # ftp://ftp.stratego-language.org/pub/stratego/docs/sdfintro.pdf
    # Using associativity attributes, ambiguities between various applications of the same
    #   production are resolved. To resolve ambiguities between different productions you can deﬁne
    #   relative priorities between them.
    # Arguments:
    #   production1 > production2
    def prioritize(production1, production2)
      tree_validator.priority_tree.prioritize(production1, production2)
    end
    
    # Associativity
    # ftp://ftp.stratego-language.org/pub/stratego/docs/sdfintro.pdf
    # To indicate whether you want operators to associate to the left or to the right,
    #   the left and right attributes are available.
    def associate(direction, production)
      tree_validator.associativity_rules[production] = Disambiguation::IndividualAssociativityRule.new(direction, production)
    end

    def associate_equal_priority_group(direction, production_group)
      group_associativity_rule = Disambiguation::EqualPriorityGroupAssociativityRule.new(direction, Set.new(production_group))
      production_group.each do |production|
        tree_validator.associativity_rules[production] = group_associativity_rule
      end
    end

    # Rejects
    # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.disambrejects
    # Given non-terminal N and regular expression R, we tell the parser to reject
    # any derivation N => S where S is a string that is derivable from the regular expression R.
    # In other words, if S matches the regular expression R, then we prune the tree in which the derivation
    # N => S exists.
    def reject(non_terminal, regular_expression_or_string_literal)
      tree_validator.reject_rules[non_terminal] ||= []
      tree_validator.reject_rules[non_terminal] << regular_expression_or_string_literal
    end

    def add_follow_restriction(non_terminals, regular_expression)
      non_terminals.each do |non_terminal|
        tree_validator.follow_restrictions[non_terminal] ||= []
        tree_validator.follow_restrictions[non_terminal] << regular_expression
      end
    end

    # Prefer/Preferences Disambiguation Filter
    # http://homepages.cwi.nl/~daybuild/daily-books/syntax/2-sdf/sdf.html#section.disambpreferences
    # Given production P, with the following alternatives:
    # P -> if E then P
    # P -> if E then P else P
    # we need to be able to parse the sentence: "if blah1 then if blah2 then blah3 else blah4"
    # and without preferring one of the alternatives, we don't know whether this sentence means:
    # if blah1 then (if blah2 then blah3) else blah4
    # OR
    # if blah1 then (if blah2 then blah3 else blah4)
    # By introducing a preference:
    # P -> if E then P {prefer}
    # we indicate that the interpretation "if blah1 then (if blah2 then blah3 else blah4)" is preferred
    # over the interpretation "if blah1 then (if blah2 then blah3) else blah4".
    def prefer(production)
      tree_validator.preferred_productions[production.non_terminal] ||= []
      tree_validator.preferred_productions[production.non_terminal] << production
    end
    def avoid(production)
      tree_validator.avoided_productions[production.non_terminal] ||= []
      tree_validator.avoided_productions[production.non_terminal] << production
    end
  end
end

class Object
  def grammar(&block)
    Linguist::Grammar.new(&block)
  end
end
