# encoding: UTF-8

require 'set'
require 'pp'
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

    # Creates a new Alternative using each argument as an alternative.
    def alt(*args)
      Grammar::Alternative.new(args)
    end
    
    # Creates a new Kleene-star operator pattern
    def kleene(pattern)
      Grammar::Kleene.new(pattern)
    end
    alias_method :star, :kleene
    
    def plus(pattern)
      seq(pattern, kleene(pattern))
    end
    
    def optional(pattern)
      alt(pattern, epsilon)
    end

    # Adds +label+ to the given +pattern+.
    def label(pattern, label)
      pattern.label = label
      pattern
    end
  end

  class BNFGrammar
    attr_accessor :productions, :start

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

    # NOTE:
    # In a BNF Grammar, "productions" is a hash of the form:
    # { NT -> [[A, B, 'c'], [D, 'e'], ...] }
    # In other words, each key/value pair is a non-terminal/array-of-alternatives pair, where the
    # array-of-alternatives is an array of sequence arrays, with each sequence array being a flat array
    # containing only terminals (characters) and non-terminals (symbols).
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
    
    attr_accessor :productions, :start
    
    def self.unique_non_terminal
      @id_count ||= 0
      @id_count += 1
      "__NT_#{@id_count}__".to_sym
    end
    
    def initialize(&block)
      @productions = {}
      @start = nil
      instance_eval(&block) if block_given?
    end
    
    def to_bnf
      bnf_grammar = BNFGrammar.new
      bnf_grammar.start = start
      tmp_productions = productions.reduce({}) do |m,kv|
        non_terminal, pattern = kv
        m[non_terminal] = case pattern
          when Grammar::Alternative
            pattern.to_bnf(bnf_grammar)
          when Grammar::Sequence
            [pattern.to_bnf(bnf_grammar)]
          else
            [seq(pattern).to_bnf(bnf_grammar)]
        end
        m
      end
      bnf_grammar.productions.merge!(tmp_productions)
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

    # Sets the production with the given name.
    def production(name, pattern)
      sym = name.to_sym
      
      # set the start non-terminal if it isn't already set
      self.start ||= sym

      # productions[sym] is a pattern representing one of the following Pattern types:
      # Terminal
      # NonTerminal
      # Epsilon
      # Any (Dot; wildcard)
      # Sequence (represents a sequence of patterns)
      # Alternative (represents a collection of alternative patterns)
      productions[sym] = wrap(pattern)

      {sym => productions[sym]}
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
    
    def to_bnf(bnf_grammar)
      @pattern
    end
    
    def nullable?
      false
    end
  end
  
  class Grammar::Terminal
    include Pattern
    
    def initialize(pattern)
      @pattern = pattern
    end
  end
  
  class Grammar::NonTerminal
    include Pattern

    def initialize(pattern)
      @pattern = pattern
    end
  end

  class Grammar::Dot
    include Pattern
    
    def initialize
      @pattern = DOT
    end
  end
  
  class Grammar::Epsilon
    include Pattern
    
    def initialize
      @pattern = EPSILON
    end
    
    def to_bnf(bnf_grammar)
      seq().to_bnf(bnf_grammar)
    end
    
    def nullable?
      true
    end
  end

  class Grammar::Sequence
    include Pattern
    
    def initialize(pattern_sequence)
      @sequence = pattern_sequence.map {|p| wrap(p) }
    end
    
    def to_bnf(bnf_grammar)
      @sequence.map do |pattern|
        case pattern
        when Grammar::Alternative
          new_non_terminal = Grammar.unique_non_terminal
          # add a new production to the bnf_grammar representing the inline sub-expression
          bnf_grammar.productions[new_non_terminal] = pattern.to_bnf(bnf_grammar)
          new_non_terminal
        when Grammar::Kleene
          new_non_terminal = Grammar.unique_non_terminal
          # add a new production to the bnf_grammar representing the inline sub-expression
          bnf_grammar.productions[new_non_terminal] = pattern.to_bnf(bnf_grammar, new_non_terminal)
          new_non_terminal
        else
          pattern.to_bnf(bnf_grammar)
        end
      end.flatten
    end
    
    def nullable?
      @sequence.all?{|pattern| pattern.nullable? }
    end
  end
  
  class Grammar::Alternative
    include Pattern
    
    def initialize(pattern_alternatives)
      @alternatives = pattern_alternatives.map {|p| wrap(p) }
    end
    
    # returns an array of term sequences
    def to_bnf(bnf_grammar)
      # each element in array_of_alternatives is a nested array of the form: [[pattern1, ...]]
      # i.e. array_of_alternatives = [ [[pattern1, ...]], [[patternI, patternJ, ...]], [[patternN, ...]], ...]
      array_of_alternatives = @alternatives.map do |pattern|
        case pattern
        when Grammar::Alternative
          pattern.to_bnf(bnf_grammar)
        when Grammar::Sequence
          [pattern.to_bnf(bnf_grammar)]
        else
          [seq(pattern).to_bnf(bnf_grammar)]
        end
      end
      # now concatenate all the arrays together to form a single array of the form:
      # [ [pattern1, ...], [patternI, patternJ, ...], [patternN, ...] ]
      array_of_alternatives.reduce{|m,array| m.concat(array) }
    end
    
    def nullable?
      @alternatives.any?{|pattern| pattern.nullable? }
    end
  end

  class Grammar::Kleene
    include Pattern
    
    def initialize(pattern)
      @pattern = wrap(pattern)
    end

    def to_bnf(bnf_grammar, new_non_terminal)
      alt(seq(@pattern, new_non_terminal), epsilon).to_bnf(bnf_grammar)
    end
    
    def nullable?
      true
    end
  end
end

# Derived from: http://stackoverflow.com/questions/773403/ruby-want-a-set-like-object-which-preserves-order/773931#773931
class UniqueArray < Array
  def initialize(*args)
    if args.size == 1 and args[0].is_a? Array then
      super(args[0].uniq)
    else
      super(*args)
    end
    @set = Set.new(self)
  end

  def insert(i, v)
    unless @set.include?(v)
      @set << v
      super(i, v)
    end
  end

  def <<(v)
    unless @set.include?(v)
      @set << v
      super(v)
    end
  end

  def []=(*args)
    # note: could just call super(*args) then uniq!, but this is faster

    # there are three different versions of this call:
    # 1. start, length, value
    # 2. index, value
    # 3. range, value
    # We just need to get the value
    v = case args.size
      when 3 then args[2]
      when 2 then args[1]
      else nil
    end

    if v.nil? or !@set.include?(v)
      super(*args)
      @set << v
    end
  end
  
  def clear
    @set.clear
    super
  end
  
  def delete(obj)
    @set.delete(obj)
    super
  end
  
  def delete_at(i)
    obj = super
    @set.delete(obj)
    obj
  end
  
  def +(other_array)
    other_array.each{|obj| self << obj }
    self
  end
end

class Object
  def grammar(&block)
    Linguist::Grammar.new(&block)
  end
end
