$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class TreeNodeTest < Test::Unit::TestCase
  def test_node_deep_clone
    root = Linguist::PracticalEarleyParser::Node.new(:root, nil, :item1, :start1, :end1, :tree1)
    child1 = Linguist::PracticalEarleyParser::Node.new(:child1, root, :item2, :start2, :end2, :tree1)
    child2 = Linguist::PracticalEarleyParser::Node.new(:child2, child1, :item3, :start3, :end3, :tree1)
    child3 = Linguist::PracticalEarleyParser::Node.new(:child3, child1, :item4, :start4, :end4, :tree1)
    child4 = Linguist::PracticalEarleyParser::Node.new(:child4, child2, :item5, :start5, :end5, :tree1)
    child5 = Linguist::PracticalEarleyParser::Node.new(:child5, child2, :item6, :start6, :end6, :tree1)
    root.children << child1
    child1.children.concat [child2, child3]
    child2.children.concat [child4, child5]

    new_root = root.deep_clone {|node| node.tree = :tree2 }

    assert new_root != root
    assert_equal root.value,       new_root.value
    assert_equal root.parent,      new_root.parent
    assert_equal root.item,        new_root.item
    assert_equal root.start_index, new_root.start_index
    assert_equal root.end_index,   new_root.end_index
    assert_equal new_root.tree,    :tree2

    new_child1 = new_root.children[0]
    assert child1 != new_child1
    assert_equal child1.value,       new_child1.value
    assert_equal new_root,           new_child1.parent
    assert_equal child1.item,        new_child1.item
    assert_equal child1.start_index, new_child1.start_index
    assert_equal child1.end_index,   new_child1.end_index
    assert_equal new_child1.tree,    :tree2

    new_child2 = new_child1.children[0]
    assert child2 != new_child2
    assert_equal child2.value,       new_child2.value
    assert_equal new_child1,         new_child2.parent
    assert_equal child2.item,        new_child2.item
    assert_equal child2.start_index, new_child2.start_index
    assert_equal child2.end_index,   new_child2.end_index
    assert_equal new_child2.tree,    :tree2
  end

  def test_node_path
    #                 root
    #                  |
    #                child1
    #               /      \
    #         child2        child3
    #        /   |   \
    #  child4 child5  child6

    root = Linguist::PracticalEarleyParser::Node.new(:root, nil, :item1, :start1, :end1, :tree1)
    child1 = Linguist::PracticalEarleyParser::Node.new(:child1, root, :item2, :start2, :end2, :tree1)
    child2 = Linguist::PracticalEarleyParser::Node.new(:child2, child1, :item3, :start3, :end3, :tree1)
    child3 = Linguist::PracticalEarleyParser::Node.new(:child3, child1, :item4, :start4, :end4, :tree1)
    child4 = Linguist::PracticalEarleyParser::Node.new(:child4, child2, :item5, :start5, :end5, :tree1)
    child5 = Linguist::PracticalEarleyParser::Node.new(:child5, child2, :item6, :start6, :end6, :tree1)
    child6 = Linguist::PracticalEarleyParser::Node.new(:child6, child2, :item7, :start7, :end7, :tree1)
    root.children << child1
    child1.children.concat [child2, child3]
    child2.children.concat [child4, child5, child6]

    tree = Linguist::PracticalEarleyParser::Tree.new(root, [])

    assert_equal root.path, [0]
    assert_equal child1.path, [0, 0]
    assert_equal child2.path, [0, 0, 0]
    assert_equal child3.path, [0, 0, 1]
    assert_equal child4.path, [0, 0, 0, 0]
    assert_equal child5.path, [0, 0, 0, 1]
    assert_equal child6.path, [0, 0, 0, 2]

    assert_equal root, tree.node_at([0])
    assert_equal child1, tree.node_at([0, 0])
    assert_equal child2, tree.node_at([0, 0, 0])
    assert_equal child3, tree.node_at([0, 0, 1])
    assert_equal child4, tree.node_at([0, 0, 0, 0])
    assert_equal child5, tree.node_at([0, 0, 0, 1])
    assert_equal child6, tree.node_at([0, 0, 0, 2])
  end
end