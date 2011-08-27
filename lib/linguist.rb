# encoding: UTF-8

require 'set'
require 'pp'
require 'structures'
require 'disambiguation'
require 'parsers/earley_item'
require 'parsers/earley'
require 'parsers/practical_earley'

module Linguist
  VERSION = 1.0

  module PatternBuilder
    def wrap(pattern)
      case pattern
      when String
        if pattern.length == 0
          raise "A quoted string must have one or more characters in it."
        elsif pattern.length == 1
          Grammar::Terminal.new(pattern)
        else
          Grammar::Sequence.new(pattern.chars.map {|char| Terminal.new(char) })
        end
      when Symbol
        Grammar::NonTerminal.new(pattern)
      else
        pattern
      end
    end
    
    # Creates a new epsilon pattern that matches nothing, and consumes no input.
    def epsilon
      Grammar::Epsilon.new
    end
    
    # Creates a new pattern (dot/any operator) that will match any single character.
    def dot
      Grammar::Dot.new
    end
    alias_method :any, :dot
    
    # Creates a new Sequence using all arguments.
    def seq(*args)
      Grammar::Sequence.new(args)
    end

    # returns a non terminal representing the productions:
    # NT -> epsilon
    # NT -> pattern NT
    def kleene(pattern)
      new_non_terminal = Grammar.unique_non_terminal
      production(new_non_terminal, seq(pattern, new_non_terminal))
      production(new_non_terminal, epsilon)
      new_non_terminal
    end
    alias_method :star, :kleene
    
    def plus(pattern)
      seq(pattern, kleene(pattern))
    end
    
    # returns a non terminal representing the productions:
    # NT -> epsilon
    # NT -> pattern
    def optional(pattern)
      new_non_terminal = Grammar.unique_non_terminal
      production(new_non_terminal, pattern)
      production(new_non_terminal, epsilon)
      new_non_terminal
    end

    # Priorities
    # ftp://ftp.stratego-language.org/pub/stratego/docs/sdfintro.pdf
    # Using associativity attributes, ambiguities between various applications of the same
    #   production are resolved. To resolve ambiguities between different productions you can deﬁne
    #   relative priorities between them.
    # Arguments:
    #   production1 > production2
    def prefer(production1, production2)
      priority_tree.prefer(production1, production2)
    end
    
    # Associativity
    # ftp://ftp.stratego-language.org/pub/stratego/docs/sdfintro.pdf
    # To indicate whether you want operators to associate to the left or to the right,
    #   the left and right attributes are available.
    def associate(direction, production)
      associativity_rules[production] = Disambiguation::IndividualAssociativityRule.new(direction, production)
    end

    def associate_equal_priority_group(direction, production_group)
      group_associativity_rule = Disambiguation::EqualPriorityGroupAssociativityRule.new(direction, Set.new(production_group))
      production_group.each do |production|
        associativity_rules[production] = group_associativity_rule
      end
    end
  end

  module Pattern
    EPSILON = :__epsilon__
    DOT = Object.new
    
    include PatternBuilder

    def self.included(mod)
      mod.class_eval do
        attr_accessor :extension
        attr_accessor :label
      end
    end
    
    def to_bnf
      @pattern
    end
    
    def nullable?
      false
    end
  end
  
  class Grammar
    class Terminal
      include Pattern
      
      def initialize(pattern)
        @pattern = pattern
      end
    end
    
    class NonTerminal
      include Pattern

      def initialize(pattern)
        @pattern = pattern
      end
    end

    class Dot
      include Pattern
      
      def initialize
        @pattern = DOT
      end
    end
    
    class Epsilon
      include Pattern
      
      def initialize
        @pattern = EPSILON
      end
      
      def to_bnf
        seq().to_bnf
      end
      
      def nullable?
        true
      end
    end

    class Sequence
      include Pattern
      
      def initialize(pattern_sequence)
        @sequence = pattern_sequence.map {|p| wrap(p) }
      end
      
      def to_bnf
        @sequence.map(&:to_bnf).flatten
      end
      
      def nullable?
        @sequence.all?{|pattern| pattern.nullable? }
      end
    end
  end

  ###############################################################################
  ############################# Grammar Definitions #############################
  ###############################################################################

  Production = Struct.new(:non_terminal, :pattern)

  # In a BNF Grammar, "productions" is a hash of the form:
  # { :NT -> [[:A, :B, 'c'], [:D, 'e'], ...] }
  # In other words, each key/value pair is a non-terminal/array-of-alternatives pair, where the
  # array-of-alternatives is an array of sequence arrays, with each sequence array being a flat array
  # containing only terminals (characters) and non-terminals (symbols).
  class BNFGrammar
    attr_accessor :start, :productions, :priority_tree, :associativity_rules

    def initialize
      @productions = {}
      @start = nil
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
    
    attr_accessor :start, :productions, :priority_tree, :associativity_rules
    
    def self.unique_non_terminal
      @id_count ||= 0
      @id_count += 1
      "__NT_#{@id_count}__".to_sym
    end
    
    def initialize(&block)
      @start = nil
      @productions = {}
      @priority_tree = Disambiguation::PriorityTree.new
      @associativity_rules = {}
      instance_eval(&block) if block_given?
    end
    
    def to_bnf
      bnf_grammar = BNFGrammar.new
      bnf_grammar.start = start
      tmp_productions = productions.reduce({}) do |m, kv|
        non_terminal, alternatives = kv
        m[non_terminal] = alternatives.map do|pattern|
          case pattern
          when Grammar::Sequence
            pattern.to_bnf
          else
            seq(pattern).to_bnf
          end
        end
        m
      end
      bnf_grammar.productions.merge!(tmp_productions)
      bnf_grammar.priority_tree = priority_tree
      bnf_grammar.associativity_rules = associativity_rules
      bnf_grammar
    end
    
    def to_s
      productions.map{|k,v| "#{k} -> #{v}" }
    end
    
    def non_terminals
      productions.keys
    end
    
    # This returns a set of non-terminals that are nullable
    # A non-terminal N is nullable if it can derive epsilon
    def nullable_non_terminals
      @nullable_non_terminals ||= non_terminals.select{|nt| productions[nt].nullable? }
    end
    
    def alternatives(non_terminal)
      productions[non_terminal] || []
    end

    # Create a production
    def production(name, pattern)
      sym = name.to_sym
      
      # set the start non-terminal if it isn't already set
      self.start ||= sym

      # ensure that productions[sym] is an array
      productions[sym] ||= []

      # productions[sym] is a set of pattern sequences representing one of the following Pattern types:
      # Terminal
      # NonTerminal
      # Epsilon
      # Any (Dot; wildcard)
      # Sequence (represents a sequence of patterns)
      alternative = wrap(pattern)
      productions[sym] << alternative

      Production.new(sym, alternative.to_bnf)
    end
  end
end

class Object
  def grammar(&block)
    Linguist::Grammar.new(&block)
  end
end
