# encoding: UTF-8

require 'strscan'
require 'pathname'
require 'set'
require 'pp'

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

  # Grammar is a data structure that represents a context-free grammar (CFG).
  # From wikipedia:
  # Formally, a context-free grammar G is defined by the 4-tuple:
  # G = (V, E, P, S)
  # where
  # V is a finite set of non-terminals.
  # E is a finite set of terminals, disjoint from V.
  # P is a finite set of productions.
  # S is the start symbol representing the non-terminal from which the grammar derives sentences.
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
      bnf_grammar = Grammar.new
      bnf_grammar.start = start
      bnf_grammar.productions = productions.reduce({}) do |m,kv|
        non_terminal, pattern = kv
        m[non_terminal] = case pattern
          when Grammar::Alternative
            pattern.to_bnf(bnf_grammar)
          when Grammar::Sequence
            [pattern.to_bnf(bnf_grammar)]
          else
            [[pattern.to_bnf(bnf_grammar)]]
        end
        m
      end
      bnf_grammar
    end
    
    def to_s
      productions.map{|k,v| "#{k} -> #{v}" }
    end
    
    def non_terminals
      productions.keys
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
    EPSILON = 1
    DOT = 2
    
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

  class Grammar::Epsilon
    include Pattern
    
    def initialize
      @pattern = EPSILON
    end
  end

  class Grammar::Dot
    include Pattern
    
    def initialize
      @pattern = DOT
    end
  end
  
  class Grammar::Sequence
    include Pattern
    
    def initialize(pattern_sequence)
      @sequence = pattern_sequence.map {|p| wrap(p) }
    end
    
    def to_bnf(bnf_grammar)
      flatten_sequence(bnf_grammar)
    end
    
    def flatten_sequence(bnf_grammar)
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
  end

  class Grammar::Kleene
    include Pattern
    
    def initialize(pattern)
      @pattern = wrap(pattern)
    end

    def to_bnf(bnf_grammar, new_non_terminal)
      alt(seq(@pattern, new_non_terminal), epsilon).to_bnf(bnf_grammar)
    end
  end
  
  class EarleyParser
    # This represents an Earley Item.
    # From the Parsing Techniques book:
    # An Item is a production with a gap in its right-hand side.
    # The first "half" (the left-hand portion) of the production's right-hand side is the portion of the pattern
    # that has already been recognized.
    # The last "half" (the right-hand portion) .
    # An Earley Item is an Item with an indication of the position of the symbol at which the 
    # recognition of the recognized part started.
    # The Item E-->E•QF@3 would be represented using this structure as:
    # Item.new(:E, [:E], [:Q, :F], 3)
    Item = Struct.new(:non_terminal, :left_pattern, :right_pattern, :position)
    
    attr_reader :grammar
    attr_reader :completed, :active, :predicted
    
    def initialize(bnf_grammar)
      @grammar = bnf_grammar
      
      # these collections hold a set of items per token in the input stream
      # they are covered in detail on page 207 of Parsing Techniques (2nd ed.)
      @completed = []
      @active = []
      @predicted = []
    end
    
    def match?(input)
      recognize(input.chars)
    end
    
    def parse(input)
      recognize(input.chars)
      parse_trees
    end
    
    def itemset(position)
      active[position] + predicted[position]
    end
    
    private
    
    # alternatives is an array of pattern sequences, where each pattern sequence is an array of terminals and non-terminals.
    def construct_initial_item_set(non_terminal, alternatives, position)
      Set.new(alternatives.map {|pattern| Item.new(non_terminal, [], pattern, position) })
    end
    
    def recognize(token_stream)
      build_initial_itemset

      token_stream.each_with_index do |token, position|
        scan(token, position, position + 1)
        complete(position)
        predict(position)
      end
      
      # If the completed set after the last symbol in the input contains an item 
      # S -> ...•@1, that is, an item spanning the entire input and reducing to the start symbol,
      # we have found a parsing.
      parse_success = (completed[token_stream.count] || []).any? do |item|
        item.non_terminal == grammar.start &&
        item.right_pattern.empty? &&
        item.position == 0
      end
      parse_success
    end
    
    def build_initial_itemset
      active[0] = construct_initial_item_set(grammar.start, grammar.alternatives(grammar.start), 0)
      predict(-1)
    end
    
    # this runs the scanner
    def scan(token, source_position, destination_position)
      # these items represent items that contain •σ somewhere in the item's pattern (σ is the token; σ === token)
      items_to_be_copied = itemset(source_position).select {|item| item.right_pattern.first == token }
      
      # In the copied items, the part before the dot was already recognized and now σ is recognized;
      # consequently, the Scanner changes •σ into σ•
      # σ === token
      modified_items = items_to_be_copied.map do |item|
        Item.new(item.non_terminal,
                 item.left_pattern + [item.right_pattern.first],
                 item.right_pattern[1...item.right_pattern.size],
                 item.position) 
      end
      
      # separate out the completed items and the active items from modified_items
      reduce_items, active_items = modified_items.partition {|item| item.right_pattern.empty? }
      
      completed[destination_position] ||= Set.new
      completed[destination_position] += reduce_items
      
      active[destination_position] ||= Set.new
      active[destination_position] += active_items
    end
    
    # this runs the completer
    def complete(position)
      # this is the closure of the scan/complete action
      begin
        reduce_items = completed[position + 1]
        
        # for each item of the form R -> ...•@m the Completer goes to itemset[m], and calls scan(R, m, position + 1)
        reduce_items.each do |item|
          scan(item.non_terminal, item.position, position + 1)
        end
        
        new_reduce_items = completed[position + 1]
      end until new_reduce_items == reduce_items
    end
    
    # this runs the predictor
    def predict(position)
      predicted[position + 1] ||= Set.new

      predict_items(active[position + 1], position)

      # this is the closure of the predict action
      begin
        original_predicted_items = predicted[position + 1]
        
        predict_items(original_predicted_items, position)
        
        new_predicted_items = predicted[position + 1]
      end until new_predicted_items == original_predicted_items
      
      # The sets active[p+1] and predicted[p+1] together form the new itemset[p+1].
      # itemset[position + 1] = active[position + 1] + predicted[position + 1]
    end
    
    def predict_items(item_collection, position)
      # build a list of non-terminals that are predicted by the items in item_collection. A non-terminal is predicted
      # by an item if the token to the right of the DOT is a non-terminal.
      predicted_non_terminals = item_collection.map do |item|
        predicted_token = item.right_pattern.first
        predicted_token.is_a?(Symbol) ? predicted_token : nil
      end.compact.uniq
      # "For each such non-terminal N and for each rule for that non-terminal N -> P..., the Predictor adds an
      #   item N -> •P...@p+1 to the set predicted[p+1]."
      predicted_non_terminals.each do |predicted_token|
        predicted[position + 1] += construct_initial_item_set(predicted_token, 
                                                              grammar.alternatives(predicted_token), 
                                                              position + 1)
      end
    end
    
    def parse_trees
    end
  end
end

class Object
  def grammar(&block)
    Linguist::Grammar.new(&block)
  end
end
