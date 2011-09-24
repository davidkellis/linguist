module Linguist
  module PatternBuilder
    def wrap(pattern)
      case pattern
      when Range        # Range represents a character class (i.e. character alternatives)
        chars = pattern.to_a.map(:to_s)
        if chars.length == 0
          raise "A range must have one or more characters in it."
        elsif chars.count == 1
          Grammar::Terminal.new(chars.first)
        else
          new_character_range_non_terminal = Grammar.unique_non_terminal
          chars.each do |char|
            production(new_character_range_non_terminal, char)
          end
          new_character_range_non_terminal
        end
      when String       # String represents a sequence of characters
        if pattern.length == 0
          raise "A quoted string must have one or more characters in it."
        elsif pattern.length == 1
          Grammar::Terminal.new(pattern)
        else
          Grammar::Sequence.new(pattern.chars.map {|char| Grammar::Terminal.new(char) })
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

    def label(pattern, label_name)
      pattern = wrap(pattern)
      pattern.label = label_name
      pattern
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
    
    # returns a non terminal, NT, representing the productions:
    # NT  -> pattern NT1
    # NT1 -> pattern NT1
    # NT1 -> epsilon
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
  end

  class Grammar
    class Pattern
      EPSILON = :__epsilon__
      DOT = Object.new
      
      include PatternBuilder

      attr_accessor :label
      
      def to_bnf_pattern
        [@pattern]
      end

      def pattern_labels
        [label]
      end
    end
    
    class Terminal < Pattern
      def initialize(pattern)
        @pattern = pattern
      end
    end
    
    class NonTerminal < Pattern
      def initialize(pattern)
        @pattern = pattern
      end
    end

    class Dot < Pattern
      def initialize
        @pattern = DOT
      end
    end
    
    class Epsilon < Pattern
      def initialize
        @pattern = EPSILON
      end
      
      def to_bnf_pattern
        seq().to_bnf_pattern
      end
    end

    class Sequence < Pattern
      def initialize(pattern_sequence)
        @sequence = pattern_sequence.map {|p| wrap(p) }
      end
      
      def to_bnf_pattern
        @sequence.map(&:to_bnf_pattern).flatten
      end

      def pattern_labels
        @sequence.map(&:pattern_labels).flatten
      end
    end
  end
end