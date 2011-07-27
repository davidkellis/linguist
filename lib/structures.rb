require 'digest'

module Linguist
  class Node
    attr_accessor :value
    attr_accessor :children
    
    def initialize(node_value)
      @value = node_value
      @children = []
    end
    
    def non_terminal?
      @value.is_a? Symbol
    end

    def terminal?
      !non_terminal?
    end

    def hash
      Digest::SHA1.hexdigest("#{value.hash.to_s}[#{children.map(&:hash).join(',')}]").hash
    end
    
    def eql?(other)
      value == other.value && 
      children.count == other.children.count &&
      children.each_with_index.all? {|child, i| child.eql?(other.children[i]) }
    end
    
    def to_s
      "(#{children.map(&:to_s).unshift(value.to_s).join(',')})"
    end
    
    # adds another child to the far right-hand-side of the array of existing children
    def append_child(other_node)
      @children.push(other_node)
    end
    
    # adds another child to the far left-hand-side of the array of existing children
    def prepend_child(other_node)
      @children.unshift(other_node)
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
